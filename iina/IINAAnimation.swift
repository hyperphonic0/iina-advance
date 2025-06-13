//
//  IINAAnimation.swift
//  iina
//
//  Created by Matt Svoboda on 2023-04-09.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class IINAAnimation {
  static let disableActionsWorkaround = false
  typealias TaskFunc = (() throws -> Void)

  // MARK: Misc static stuff

  /// "Disable all" override switch
  private static var disableAllAnimation = false

  static var isAnimationEnabled: Bool {
    return !disableAllAnimation && !Preference.bool(for: .disableAnimations) && !AccessibilityPreferences.motionReductionEnabled
  }

  // Wrap a block of code inside this function to disable its animations
  @discardableResult
  static func disableAnimation<T>(_ closure: () throws -> T) rethrows -> T {
    let prevDisableState = disableAllAnimation
    disableAllAnimation = true
    CATransaction.begin()
    defer {
      CATransaction.commit()
      disableAllAnimation = prevDisableState
    }
    return try closure()
  }

  /// Convenience func to reduce code verbosity
  static func runAsync(duration: CGFloat? = nil, _ timingName: CAMediaTimingFunctionName? = nil,
                       _ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
    runAsync(Task(duration: duration, timing: timingName, runFunc), then: doAfter)
  }

  /// Convenience func for running the giving closure in a transactional way
  static func runInstantAsync(_ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
    runAsync(.instantTask(runFunc), then: doAfter)
  }

  /// Convenience wrapper for running a task asynchronously and immediately via `NSAnimationContext.runAnimationGroup()`.
  /// Does not use pipeline.
  static func runAsync(_ task: Task, then doAfter: TaskFunc? = nil) {
    runAsync([task], then: doAfter)
  }

  /// Convenience wrapper for executing a chain of tasks sequentially via `NSAnimationContext.runAnimationGroup()`.
  /// The first task in the chain is launched immediately & asynchronously (does not use pipeline).
  static func runAsync(_ tasks: [Task], then doAfter: TaskFunc? = nil) {
    var tasks = tasks
    if let doAfter {
      tasks.append(.instantTask(doAfter))
    }

    let taskIterator: IndexingIterator<Array<Task>> = tasks.makeIterator()
    runSequentially(taskIterator)
  }

  // Recursive function which executes code for a single Task in a chain of tasks.
  private static func runSequentially(_ taskIterator: IndexingIterator<Array<Task>>) {
    // Fail if not running on main thread:
    assert(DispatchQueue.isExecutingIn(.main))

    var taskIterator = taskIterator
    guard let task = taskIterator.next() else { return }
    NSAnimationContext.runAnimationGroup({ context in
      let disableAnimation = !isAnimationEnabled
      if disableAnimation {
        context.duration = 0
      } else {
        context.duration = task.duration
      }
      context.allowsImplicitAnimation = !disableAnimation

      if let timingName = task.timingName {
        context.timingFunction = CAMediaTimingFunction(name: timingName)
      }
      do {
        try task.runFunc()
      } catch IINAError.cancelAnimationTransaction {
        Logger.log.debug("[AnimPipeline] Async task was cancelled")
      } catch {
        Logger.log.error("[AnimPipeline] Unexpected error thrown by async task: \(error)")
      }
    }, completionHandler: {
      runSequentially(taskIterator)
    })
  }
}

extension IINAAnimation {
  struct Task {
    let duration: CGFloat
    let timingName: CAMediaTimingFunctionName?
    let runFunc: TaskFunc

    init(duration: CGFloat? = nil,
         timing timingName: CAMediaTimingFunctionName? = nil,
         _ runFunc: @escaping TaskFunc) {
      self.duration = duration ?? Constants.AnimationDuration.standard
      self.timingName = timingName
      self.runFunc = runFunc
    }

    static func instantTask(_ runFunc: @escaping TaskFunc) -> Task {
      return Task(duration: 0, timing: nil, runFunc)
    }

  }

  struct Transaction {
    let tasks: [Task]
  }
}

extension IINAAnimation {
  /// Serial queue which executes `Task`s one after another.
  class Pipeline {

    /// ID of the latest transaction to be generated, but not necessarily run.
    /// (Basically used for ID generation).
    private var newestTxID: Int = 0
    /// ID of the currently executing transaction. When enqueued, all tasks in the same transaction are
    /// associated with an identical ID, which is one greater than the previous transaction
    /// (see `newestTxID`). If an exception is thrown by any task, `currentTxID` will be incremented. Any task associated with ID less than `currentTxID` will not be run, but if a task is found to have an ID greater
    /// than `currentTxID`, then `currentTxID` will be updated to its value and the task will be run.
    /// In this way, if any task in the transaction throws an exception, this will cause the remaining tasks
    /// to be skipped.
    private var currentTxID: Int = 0

    private(set) var isRunning = false
    private var taskQueue = LinkedList<(Int, Task)>()
    private var geoTransformQueue = LinkedList<GeometryTransform>()
    private var lastStartedGeoTransformID: Int = 0
    private var lastCompletedGeoTransformID: Int = 0

    var log = Logger.log

    // Convenience function. Run the task with no animation / zero duration.
    // Useful for updating constraints, etc., which cannot be animated or do not look good animated.
    func submitInstantTask(_ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
      // TODO: investigate smart enqueuing in main queue
      submit(.instantTask(runFunc), then: doAfter)
    }

    /// Convenience function. Same as `submit(Task)`
    func submitTask(duration: CGFloat? = nil, timing timingName: CAMediaTimingFunctionName? = nil,
                    _ runFunc: @escaping TaskFunc, then doAfter: TaskFunc? = nil) {
      let task = Task(duration: duration, timing: timingName, runFunc)
      submit(task)
    }

    /// Convenience function. Same as `submit([Task])`, but for a single animation.
    func submit(_ task: Task, then doAfter: TaskFunc? = nil) {
      submit([task], then: doAfter)
    }

    /// Recursive function which enqueues each of the given `AnimationTask`s for execution, one after another.
    /// Will execute without animation if motion reduction is enabled, or if wrapped in a call to `IINAAnimation.disableAnimation()`.
    /// If animating, it uses either the supplied `duration` for duration, or if that is not provided, uses `Constants.AnimationDuration.standard`.
    func submit(_ tasks: [Task], then doAfter: TaskFunc? = nil) {
      DispatchQueue.main.execOrAsync { [self] in
        _submit(tasks, then: doAfter)
      }
    }

    private var submitCounter: Int = 0
    private var lastLoggedTaskCount: Int = 0
    private var alarmActivated = false
    private static let alarmStartWatermark: Int = 100
    private static let alarmResetWatermark: Int = 10

    func _submit(_ tasks: [Task], then doAfter: TaskFunc? = nil) {
      // Fail if not running on main thread:
      assert(DispatchQueue.isExecutingIn(.main))

      var enqueuedCount = 0

      if !tasks.isEmpty {
        newestTxID += 1
        let transactionID = newestTxID

        for task in tasks {
          taskQueue.append((transactionID, task))
        }
        enqueuedCount += tasks.count
      }

      if let doAfter {
        newestTxID += 1
        taskQueue.append((newestTxID, .instantTask(doAfter)))
        enqueuedCount += 1
      }

      guard enqueuedCount > 0 else { return }
      submitCounter += enqueuedCount

      if log.isVerboseEnabled {
        let taskQueueSize = taskQueue.count
        let submittedTasks = submitCounter
        if alarmActivated {
          let canDisable = taskQueueSize < IINAAnimation.Pipeline.alarmResetWatermark
          if canDisable {
            alarmActivated = false
          }
          if canDisable || (submittedTasks >= lastLoggedTaskCount + 20) {
            lastLoggedTaskCount = submittedTasks
            log.verbose{"[AnimPipeline] TaskQueue size: \(taskQueueSize), totalSubmits: \(submittedTasks)"}
          }
        } else if taskQueue.count >= IINAAnimation.Pipeline.alarmStartWatermark {
          alarmActivated = true
          lastLoggedTaskCount = submitCounter
          log.verbose{"[AnimPipeline] TaskQueue is falling behind! Size: \(taskQueueSize), submitCount: \(submitCounter)"}
        }
      }

      if isRunning {
        // Let existing chain pick up the new animations
      } else {
        // Launch for new tasks
        isRunning = true
        runTasks()
      }
    }

    private func popNextValidTask() -> IINAAnimation.Task? {
      while true {
        guard let (taskTxID, poppedTask) = taskQueue.removeFirst() else {
          self.isRunning = false
          return nil
        }

        guard taskTxID >= currentTxID else {
          log.debug("[AnimPipeline] Skipping task with txID \(taskTxID) (next valid txID: \(currentTxID))")
          continue
        }
        currentTxID = taskTxID
        return poppedTask
      }
    }

    private func runTasks() {
      let nextTask: Task

      // First check for enqueued GeometryTransforms.
      if !geoTransformQueue.isEmpty, lastStartedGeoTransformID == lastCompletedGeoTransformID, let tf = geoTransformQueue.removeFirst() {
        lastStartedGeoTransformID += 1

        nextTask = Task.instantTask { [self] in
          log.verbose{"[AnimPipeline] Starting GeoTF \(tf.name.quoted), id=\(lastStartedGeoTransformID)"}
          tf.execute()
        }
      } else {
        guard let task = popNextValidTask() else { return }
        nextTask = task
      }

      NSAnimationContext.runAnimationGroup({ context in
        let disableAnimation = !isAnimationEnabled
        if disableAnimation {
          context.duration = 0
        } else {
          context.duration = nextTask.duration
        }
        context.allowsImplicitAnimation = !disableAnimation

        if let timingName = nextTask.timingName {
          context.timingFunction = CAMediaTimingFunction(name: timingName)
        }
        do {
          try nextTask.runFunc()
        } catch IINAError.cancelAnimationTransaction {
          if log.isTraceEnabled {
            log.trace("[AnimPipeline] Task was cancelled")
          }
        } catch {
          log.error("[AnimPipeline] Unexpected error thrown by task: \(error)")
        }
      }, completionHandler: {
        self.runTasks()
      })
    }

    /// Uses a queue if necessary to ensure that only one `GeometryTransform` is ever running at a time.
    /// This is a safety feature. The transform's work takes place asynchronously via multiple tasks across
    /// multiple `DispatchQueue`s, while drawing from disparate state variables, so if they overlapped they
    /// could interfere with each other in difficult-to-predict ways.
    func submit(_ tf: GeometryTransform) {
      submitInstantTask{ [self] in
        if lastStartedGeoTransformID == lastCompletedGeoTransformID {
          lastStartedGeoTransformID += 1
          log.verbose{"[AnimPipeline] Starting GeoTF \(tf.name.quoted), id=\(lastStartedGeoTransformID)"}
          tf.execute()
        } else {
          log.verbose{"[AnimPipeline] Enqueuing GeoTF: \(tf.name.quoted). Queue status: \(lastCompletedGeoTransformID) / \(lastStartedGeoTransformID)"}
          geoTransformQueue.append(tf)
        }
      }
    }

    /// Can be called in any DispatchQueue.
    func geoTransformDidFinish(_ tf: GeometryTransform) {
      submitInstantTask{ [self] in
        log.verbose{"[AnimPipeline] Done: GeoTF \(tf.name.quoted), id=\(lastStartedGeoTransformID)"}
        lastCompletedGeoTransformID += 1
      }
    }

  }
}

// MARK: - Extensions for disabling animation

extension NSLayoutConstraint {
  /// Even when executed inside an animation block, MacOS only sometimes creates implicit animations for changes to constraints.
  /// Using an explicit call to `animator()` seems to be required to guarantee it, but we do not always want it to animate.
  /// This function will automatically disable animations in case they are disabled.
  func animateToConstant(_ newConstantValue: CGFloat) {
    if IINAAnimation.isAnimationEnabled {
      self.animator().constant = newConstantValue
    } else {
      self.constant = newConstantValue
    }
  }
}
