//
//  MPVChapter.swift
//  iina
//
//  Created by lhc on 29/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

struct MPVChapter: Sendable, CustomStringConvertible {

  private var privTitle: String?
  var title: String {
    return privTitle ?? "\(StringConstants.chapter) \(index)"
  }
  let startTime: Double
  let index: Int

  var startTimeString: String {
    return VideoTime.string(from: startTime)
  }

  init(title: String?, startTime: Double, index: Int) {
    self.privTitle = title
    self.startTime = startTime
    self.index = index
  }

  var description: String {
    return "Ch\(index < 10 ? "0" : "")\(index): \(VideoTime.string(from: startTime, precision: 3)) \(privTitle?.quoted ?? "")"
  }

}
