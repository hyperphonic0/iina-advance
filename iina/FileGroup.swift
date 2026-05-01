//
//  FileGroup.swift
//  iina
//
//  Created by lhc on 20/5/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate let log = Logger.makeSubsystem("fgroup", symbolName: ["rectangle.3.group"])

class FileInfo: Hashable {
  // - Stored properties

  let id: PlaybackID
  var dist: [FileInfo: UInt] = [:]
  var minDist: [FileInfo] = []
  var relatedSubs: [FileInfo] = []
  var priorityStringOccurrences = 0
  var isMatched = false

  // - Computed properties

  var url: URL { id.url }
  var path: String { id.path }
  var ext: String { id.pathExtension }
  var filename: String { url.deletingPathExtension().lastPathComponent }
  var nameInSeries: String? {
    // e.g. "abc_" "ch01_xxx" -> "ch01"
    var firstDigit = false
    let name = suffix.unicodeScalars.prefix {
      if CharacterSet.decimalDigits.contains($0) {
        if !firstDigit {
          firstDigit = true
        }
      } else {
        if firstDigit {
          return false
        }
      }
      return true
    }
    return String(name)
  }
  var characters: [Character] { [Character](self.filename) }

  /// prefix detected by FileGroup
  var prefix: String {
    didSet {
      assert(prefix.count < filename.count)
    }
  }
  /// filename - prefix
  var suffix: String { String(filename[filename.index(filename.startIndex, offsetBy: prefix.count)...]) }

  init(_ url: URL) {
    self.id = MediaMetaCache.shared.getBestPlaybackID(forURL: url)
    self.prefix = ""
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(path)
  }
  
  static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
    return lhs.path == rhs.path
  }
}


class FileGroup {

  var prefix: String
  var contents: [FileInfo]
  var groups: [FileGroup]

  static func group(files: [FileInfo]) -> FileGroup {
    log.debug("Start grouping \(files.count) files")
    let group = FileGroup(prefix: "", contents: files)
    group.tryGroupFiles()
    return group
  }

  private func tryGroupFiles() {
    log.verbose("Try group files, prefix=\(prefix.quoted), count=\(contents.count)")
    guard contents.count >= 3 else {
      log.verbose("Contents count < 3, skipped")
      return
    }

    var tempGroup: [String: [FileInfo]] = [:]
    var currChars: [(Character, String)] = []
    var i = prefix.count

    while tempGroup.count < 2 {
      var lastPrefix = prefix
      var anyProcessed = false
      for finfo in contents {
        // if reached string end
        if i >= finfo.characters.count {
          tempGroup[prefix, default: []].append(finfo)
          currChars.append(("/", prefix))
          continue
        }
        let c = finfo.characters[i]
        var p = prefix
        p.append(c)
        lastPrefix = p
        if tempGroup[p] == nil {
          tempGroup[p] = []
          currChars.append((c, p))
        }
        tempGroup[p]!.append(finfo)
        anyProcessed = true
      }
      // if all items have the same prefix
      if tempGroup.count == 1 {
        prefix = lastPrefix
        tempGroup.removeAll()
        currChars.removeAll()
      }
      i += 1
      // if all items have the same name
      if !anyProcessed {
        break
      }
    }

    let maxSubGroupCount = tempGroup.reduce(0, { max($0, $1.value.count) })
    if FileGroup.shouldStopGrouping(currChars) || maxSubGroupCount < 3 {
      log.verbose("Stop grouping, maxSubGroup=\(maxSubGroupCount)")
      contents.forEach { $0.prefix = self.prefix }
    } else {
      log.verbose("Continue grouping, groups=\(tempGroup.count), chars=\(currChars)")
      groups = tempGroup.map { FileGroup(prefix: $0.0, contents: $0.1) }
      // continue
      for g in groups {
        g.tryGroupFiles()
      }
    }
  }


  init(prefix: String, contents: [FileInfo] = []) {
    self.prefix = prefix
    self.contents = contents
    self.groups = []
  }

  func flatten() -> [String: [FileInfo]] {
    var result: [String: [FileInfo]] = [:]
    func search(_ group: FileGroup) {
      if group.groups.count > 0 {
        for g in group.groups {
          search(g)
        }
      } else {
        result[group.prefix] = group.contents
      }
    }
    search(self)
    return result
  }

  private static func shouldStopGrouping(_ chars: [(Character, String)]) -> Bool {
    var chineseNumberCount = 0
    for (c, _) in chars {
      if c >= "0" && c <= "9" { return true }
      // chinese characters
      if Constants.chineseNumbers.contains(c) { chineseNumberCount += 1 }
      if chineseNumberCount >= 3 { return true }
    }
    return false
  }

}

