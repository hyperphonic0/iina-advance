//
//  KeyBindingDataLoader.swift
//  iina
//
//  Created by lhc on 4/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias KBI = KeyBindingItem

fileprivate enum PropertyType {
  case bool, num, string, separator
}

struct KeyBindingDataLoader {
  @MainActor
  fileprivate static let commands: [KeyBindingItem] = [
    KBI("ignore"),
    KBI.separator,
    KBI("seek", type: .label, children:
          KBI.chooseIn("forward|backward", children:
                        KBI("value", type: .number, children:
                              KBI.chooseIn("relative|relative-percent|relative+exact|relative-percent+exact")
                           )
                      )
        +
        KBI.chooseIn("seek-to", children:
                      KBI("value", type: .number, children:
                            KBI.chooseIn("absolute|absolute-percent|absolute+keyframe|absolute-percent+keyframe")
                         )
                    )
       ),
    KBI("frame-step"),
    KBI("frame-back-step"),
    KBI("ab-loop"),
    KBI.separator,
    KBI("set", type: .label, children: propertiesForSet()),
    KBI("cycle", type: .label, children: propertiesForCycle()),
    KBI("cycle-values", type: .label, children: propertiesForCycleValues()),
    KBI("add", type: .label, children: propertiesForAdd()),
    KBI("multiply", type: .label, children: propertiesForMultiply()),
    KBI.separator,
    KBI("playlist-next"),
    KBI("playlist-prev"),
    KBI("playlist-clear"),
    KBI("playlist-remove"),
    KBI("playlist-shuffle"),
    KBI.separator,
    KBI(IINACommand.videoPanel.rawValue, type: .iinaCmd),
    KBI(IINACommand.audioPanel.rawValue, type: .iinaCmd),
    KBI(IINACommand.subPanel.rawValue, type: .iinaCmd),
    KBI(IINACommand.playlistPanel.rawValue, type: .iinaCmd),
    KBI(IINACommand.chapterPanel.rawValue, type: .iinaCmd),
    KBI.separator,
    KBI(IINACommand.openFile.rawValue, type: .iinaCmd),
    KBI(IINACommand.openURL.rawValue, type: .iinaCmd),
    KBI(IINACommand.saveCurrentPlaylist.rawValue, type: .iinaCmd),
    KBI(IINACommand.showCurrentFileInFinder.rawValue, type: .iinaCmd),
    KBI(IINACommand.deleteCurrentFile.rawValue, type: .iinaCmd),
    KBI(IINACommand.deleteCurrentFileHard.rawValue, type: .iinaCmd),
    KBI.separator,
    KBI(IINACommand.findOnlineSubs.rawValue, type: .iinaCmd),
    KBI(IINACommand.saveDownloadedSub.rawValue, type: .iinaCmd),
    KBI.separator,
    KBI("write-watch-later-config"),
    KBI("stop"),
    KBI("quit")
  ]

  fileprivate static let propertyList: [(String, PropertyType)] = [
    ("pause", .bool),
    ("speed", .num),
    ("---", .separator),
    ("video", .num),
    ("video-aspect-override", .string),
    ("contrast", .num),
    ("brightness", .num),
    ("gamma", .num),
    ("saturation", .num),
    ("deinterlace", .bool),
    ("---", .separator),
    ("audio", .num),
    ("volume", .num),
    ("mute", .bool),
    ("audio-delay", .num),
    ("---", .separator),
    ("sub", .num),
    ("sub-delay", .num),
    ("sub-pos", .num),
    ("sub-scale", .num),
    ("sub-visibility", .bool),
    ("---", .separator),
    ("fullscreen", .bool),
    ("ontop", .bool),
    ("---", .separator),
    ("chapter", .num)
  ]

  static let toggleableIINAProperties: [String] = [
    IINACommand.flip,
    IINACommand.mirror,
    IINACommand.togglePIP,
    IINACommand.toggleMusicMode,
  ].map{$0.rawValue.droppingPrefix("toggle-")}

  static let cycleableIINAProperties: [String] = [
    IINACommand.enableOscAutohide,
  ].map(\.rawValue)

  static private func propertiesForSet() -> [KeyBindingItem] {
    return propertyList.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator }
      let kbi = KBI(str, type: .label, l10nKey: "opt", children:
                  KBI("to", type: .placeholder, children:
                    type == .bool ?
                      KBI.chooseIn("yes|no") :
                      [KBI("value", type: .string)]
                  )
                )
      return kbi
    }
  }

  static private func propertiesForMultiply() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool && $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator }
      let kbi = KBI(str, type: .label, l10nKey: "opt", children:
                  KBI("by", type: .placeholder, children:
                    KBI("value", type: .string)
                  )
                )
      return kbi
    }
  }

  static private func propertiesForAdd() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool && $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator }
      let kbi = KBI(str, type: .label, l10nKey: "opt", children:
                  KBI.chooseIn("add|minus", children:
                    KBI("value", type: .string)
                  )
                )
      return kbi
    }
  }

  static private func propertiesForCycle() -> [KeyBindingItem] {
    var list = propertyList.filter { $0.1 != .string }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator }
      let kbi = KBI(str, l10nKey: "opt")
      return kbi
    }
    // add properties for iina
    list.append(KBI.separator)
    toggleableIINAProperties.forEach { p in
      let kbi = KBI(p, type: .iinaCmd, l10nKey: "opt")
      list.append(kbi)
    }
    // More IINA properties
    for iinaProp in cycleableIINAProperties {
      let kbi = KBI(iinaProp, type: .iinaCmd, l10nKey: iinaProp)
      list.append(kbi)
    }
    return list
  }

  static private func propertiesForCycleValues() -> [KeyBindingItem] {
    return propertyList.filter { $0.1 != .bool }.map { (str, type) -> KeyBindingItem in
      if type == .separator { return KBI.separator }
      let kbi = KBI(str, type: .label, children:
        KBI("in", type: .placeholder, l10nKey: "opt", children:
          KBI("value", type: .string)
        )
      )
      return kbi
    }
  }

  @MainActor
  static func load() -> [Criterion] {
    commands.map{ $0.toCriterion(l10nKey: "cmd") }
  }
}


