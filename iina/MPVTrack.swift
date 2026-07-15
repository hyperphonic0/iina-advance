//
//  MPVTrack.swift
//  iina
//
//  Created by lhc on 31/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

struct MPVTrack: Sendable, CustomStringConvertible, Equatable {

  /** For binding a none track object to menu, id = 0 */
  static let noneVideoTrack = MPVTrack(id: 0, type: .video, title: NSLocalizedString("track.none", comment: "<None>"),
                                       isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneAudioTrack = MPVTrack(id: 0, type: .audio, title: NSLocalizedString("track.none", comment: "<None>"),
                                       isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneSubTrack = MPVTrack(id: 0, type: .sub, title: NSLocalizedString("track.none", comment: "<None>"),
                                     isDefault: false, isForced: false, isSelected: false, isExternal: false)
  /** For binding a none track object to menu, id = 0 */
  static let noneSecondSubTrack = MPVTrack(id: 0, type: .secondSub, title: NSLocalizedString("track.none", comment: "<None>"),
                                           isDefault: false, isForced: false, isSelected: false, isExternal: false)

  static func emptyTrack(for type: TrackType) -> MPVTrack {
    switch type {
    case .video: return noneVideoTrack
    case .audio: return noneAudioTrack
    case .sub: return noneSubTrack
    case .secondSub: return noneSecondSubTrack
    }

  }

  enum TrackType: String {
    case audio = "audio"
    case video = "video"
    case sub = "sub"
    // Only for setting a second sub track, hence the raw value is unused
    case secondSub = "secondSub"
  }

  let id: Int
  let type: TrackType
  let srcId: Int?
  let title: String?
  let lang: String?
  let isDefault: Bool
  let isForced: Bool
  let isImage: Bool
  let isSelected: Bool
  let isExternal: Bool
  let externalFilename: String?
  let codec: String?
  let demuxW: Int?
  let demuxH: Int?
  let demuxChannelCount: Int?
  let demuxChannels: String?
  let demuxSamplerate: Int?
  let demuxFps: Double?
  let isAlbumart: Bool
  let decoderDesc: String?

  init(id: Int,
       type: TrackType,
       srcId: Int? = nil,
       title: String? = nil,
       lang: String? = nil,
       isDefault: Bool,
       isForced: Bool,
       isImage: Bool = false,
       isSelected: Bool,
       isExternal: Bool,
       externalFilename: String? = nil,
       codec: String? = nil,
       demuxW: Int? = nil,
       demuxH: Int? =  nil,
       demuxChannelCount: Int? = nil,
       demuxChannels: String? = nil,
       demuxSamplerate: Int? = nil,
       demuxFps: Double? = nil,
       isAlbumart: Bool = false,
       decoderDesc: String? = nil,

  ) {
    self.id = id
    self.type = type
    self.srcId = srcId
    self.title = title
    self.lang = lang
    self.isDefault = isDefault
    self.isForced = isForced
    self.isImage = isImage
    self.isSelected = isSelected
    self.isExternal = isExternal
    self.externalFilename = externalFilename
    self.codec = codec
    self.demuxW = demuxW
    self.demuxH = demuxH
    self.demuxChannelCount = demuxChannelCount
    self.demuxChannels = demuxChannels
    self.demuxSamplerate = demuxSamplerate
    self.demuxFps = demuxFps
    self.isAlbumart = isAlbumart
    self.decoderDesc = decoderDesc
  }

  var readableTitle: String { "\(idString) \(infoString)" }
  var idString: String { "#\(id)" }

  var description: String { "MPVTrack(\(idString): \(infoString))" }

  /// A textual representation of this instance.
  /// - Note: Optional properties that are `nil` are not included in the description of the instance.
  var longDescription: String {
    var result =
      """
      Track \(idString)
        type: \(type)\n
      """
    result += Mirror(reflecting: self).children.compactMap { child -> (String, String)? in
      guard let label = child.label, label != "id", label != "type" else { return nil }
      if case Optional<Any>.none = child.value { return nil }
      var value = String(describing: child.value)
      let prefix = "Optional("
      if value.hasPrefix(prefix), value.hasSuffix(")") {
        value = String(value.dropFirst(prefix.count).dropLast(1))
      }
      return (label, "\(value)")
    }.sorted { $0.0 < $1.0 }.map { "  \($0): \($1)" }.joined(separator: "\n")
    return result
  }

  var infoString: String {
    // title
    let title = title ?? ""
    // lang
    let language: String
    if let lang, lang != "und", let rawLang = ISO639Helper.dictionary[lang] {
      language = "[\(rawLang)]"
    } else {
      language = ""
    }
    // info
    var components: [String] = []
    if let codec {
      components.append(codec)
    }
    switch type {
    case .video:
      if let demuxW, let demuxH {
        components.append("\(demuxW)\u{d7}\(demuxH)")
      }
      if let demuxFps {
        components.append("\(demuxFps.prettyFormat())fps")
      }
    case .audio:
      if let demuxChannelCount {
        components.append("\(demuxChannelCount)ch")
      }
      if let demuxSamplerate {
        components.append("\((Double(demuxSamplerate)/1000).prettyFormat())kHz")
      }
    default:
      break
    }
    let info = components.joined(separator: ", ")
    // default
    let isDefault = isDefault ? "(" + NSLocalizedString("quicksetting.item_default", comment: "Default") + ")" : ""
    // final string
    return [language, title, info, isDefault].filter { !$0.isEmpty }.joined(separator: " ")
  }


  // Utils

  var isImageSub: Bool {
    if type == .video || type == .audio { return false }
    // demux/demux_mkv.c:1727
    return codec == "hdmv_pgs_subtitle" || codec == "dvb_subtitle"
  }

  var isAssSub: Bool {
    if type == .video || type == .audio { return false }
    // demux/demux_mkv.c:1727
    return codec == "ass"
  }
}
