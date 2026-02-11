//
//  Debouncer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-23.
//  Copyright © 2025 lhc. All rights reserved.
//

class Debouncer {
  @Atomic private(set) var ticketCount: Int = 0
  private let delay: TimeInterval
  private let queue: DispatchQueue
  private var lastRunTS: Date = Date(timeIntervalSince1970: 0)

#if DEBUG
  // Measuring the number of dropped tasks indicates the amount of work saved, so is helpful in quantifying the
  // usefulness of a given debouncer.
  var droppedCount: Int = 0
#endif

  init(delay: TimeInterval = 0.0, queue: DispatchQueue = .main) {
    self.delay = delay
    self.queue = queue
  }

  func run(_ taskFunc: @escaping () -> Void) {
    let currentTicket = $ticketCount.withLock {
      $0 += 1
      return $0
    }

    queue.asyncAfter(deadline: .now() + delay) { [self] in
      // If delay is very short, there is a risk of starvation: if run() is called again before this task
      // has a chance to run, it will invalidate the previous ticket, and as long as the pattern continues,
      // no tasks would run. Keep track of last run's timestamp, and ensure that in the case of heavy request
      // load, a task runs at least every `delay` seconds.
      guard (currentTicket == ticketCount) || Date().timeIntervalSince(lastRunTS) > delay else {
#if DEBUG
        droppedCount += 1;
#endif
        return
      }
      taskFunc()
      lastRunTS = Date()
    }
  }

  func invalidate() {
    $ticketCount.withLock { $0 += 1 }
  }
}
