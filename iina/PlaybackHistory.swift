//
//  PlaybackHistory.swift
//  iina
//
//  Created by lhc on 28/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let KeyUrl = "IINAPHUrl"
fileprivate let KeyName = "IINAPHNme"
fileprivate let KeyMpvMd5 = "IINAPHMpvmd5"
fileprivate let KeyPlayed = "IINAPHPlayed"
fileprivate let KeyAddedDate = "IINAPHDate"
fileprivate let KeyDuration = "IINAPHDuration"
fileprivate let KeyTitle = "IINAPHTitle"

/// An entry in the playback history file.
/// - Important: This class conforms to [NSSecureCoding](https://developer.apple.com/documentation/foundation/nssecurecoding).
///     When making changes be certain the requirements for secure coding are not violated by the changes.
class PlaybackHistory: NSObject, NSSecureCoding {

  /// Indicate this class supports secure coding.
  static var supportsSecureCoding: Bool { true }

  private static let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
    return dateFormatter
  }()

  let id: PlaybackID

  /// As of v1.3, URL is are encapsulated in `id`.
  var url: URL { id.url }
  // As of v1.3, this is derived from URL; value stored on disk is redundant & is ignored.
  var name: String { id.url.lastPathComponent }
  // As of v1.3, this is derived from URL; value stored on disk is redundant & is ignored.
  var mpvMd5: String { id.mpvMD5 }

  let addedDate: Date

  let duration: Double
  var mpvProgress: Double?

  var title: String?

  /// A description of this playback history entry suitable to include in a log message.
  override var description: String {
    var description = """
      added: \(PlaybackHistory.dateFormatter.string(from: addedDate)) \
      duration: \(VideoTime(duration).stringRepresentation)
      """
    if let mpvProgress { description += " progress: \(VideoTime(mpvProgress).stringRepresentation)" }
    description += "\n  \(url)"
    if let title { description += "\n  \(title)" }
    description += "\n  MD5: \(mpvMd5)"
    return description
  }

  required init?(coder aDecoder: NSCoder) {
    guard
      let url = aDecoder.decodeObject(of: NSURL.self, forKey: KeyUrl),
      let date = aDecoder.decodeObject(of: NSDate.self, forKey: KeyAddedDate)
    else {
      return nil
    }

    let duration = aDecoder.decodeDouble(forKey: KeyDuration)
    let title = aDecoder.decodeObject(of: NSString.self, forKey: KeyTitle)

    self.id = PlaybackID(url as URL)
    self.addedDate = date as Date
    self.duration = duration
    self.title = title as String?
    self.mpvProgress = nil
  }

  init(id: PlaybackID, duration: Double, title: String?) {
    self.id = id
    self.addedDate = Date()
    self.duration = duration
    self.title = title
  }

  func encode(with aCoder: NSCoder) {
    aCoder.encode(url, forKey: KeyUrl)
    aCoder.encode(name, forKey: KeyName)  // obsolete; included only to support legacy versions
    aCoder.encode(mpvMd5, forKey: KeyMpvMd5)  // obsolete; included only to support legacy versions
    aCoder.encode(true, forKey: KeyPlayed)  // obsolete; included only to support legacy versions
    aCoder.encode(addedDate, forKey: KeyAddedDate)
    aCoder.encode(duration, forKey: KeyDuration)
    aCoder.encode(title, forKey: KeyTitle)
  }
}
