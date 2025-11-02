//
//  TimeoutTimer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

class TimeoutTimer {
  private var scheduledTimer: Timer? = nil
  var timeout: TimeInterval

  /// nillable because sometimes this needs to be set after the containing class has finished init
  var action: (() -> Void)?

  /// If not nil, is executed before starting or restarting the timer.
  /// If it returns false, the timer will not be started.
  /// Can also be used to execute extra logic before each timer restart.
  var startCondition: ((_ thisTimer: TimeoutTimer) -> Bool)?

  init(timeout: TimeInterval,
       startCondition: ((TimeoutTimer) -> Bool)? = nil,
       action: (() -> Void)? = nil) {
    self.timeout = timeout
    self.startCondition = startCondition
    self.action = action
  }

  func restart(withNewTimeout newTimeout: TimeInterval? = nil) {
    cancel()

    if let newTimeout {
      timeout = newTimeout
    }

    if let startCondition {
      let canProceed = startCondition(self)
      guard canProceed else {
        return
      }
    }
    scheduledTimer = Timer.scheduledTimer(timeInterval: timeout,
                                          target: self, selector: #selector(self.timeoutReached),
                                          userInfo: nil, repeats: false)
  }

  var isValid: Bool {
    if let scheduledTimer, scheduledTimer.isValid {
      return true
    }
    return false
  }

  func cancel() {
    scheduledTimer?.invalidate()
  }

  /// Convenience method to excute `startCondition` without its boilerplate args.
  func runStartCondition() {
    if let startCondition {
      _ = startCondition(self)
    }
  }

  @objc private func timeoutReached() {
    cancel()
    if let action {
      action()
    }
  }
}
