//
//  InputBinding.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/**
 Contains metadata for a single input binding (a mapping: {key combination or sequence / mouse input / etc} -> {action}) for use by the IINA app.

 The intent of this class was to decorate an otherwise naive `KeyMapping` object with additional metadata such as its origin, whether it
 is also attached to a menu item, its origin, etc, which are populated during the conflict resolution process and can be output to the UI.

 All of the sources of key bindings (mpv config file, IINA plugin, etc) are flattened into one standard list so that comflicts between bindings
 can be resolved player window or the menubar (and also to distinguish it from `KeyMapping` and other objects).
 If multiple bindings are specified with the same key, only one can be enabled, and the others' have property `isEnabled` set to false.

 An instance of this class encapsulates all the data needed to display a single row/line in the Key Bindings table.
 */
struct InputBinding: Sendable, Hashable, CustomStringConvertible {
  /// Will be `nil` for plugin bindings.
  let keyMapping: KeyMapping

  let origin: InputBindingOrigin

  /// Will be one of:
  /// - "default", if origin == .confFile
  /// - The input section name, if origin == .libmpv
  /// - The Plugins section name, if origin == .iinaPlugin
  /// - The Video or Audio Filters section name, if origin == .savedFilter
  let srcSectionName: String
  
  let isEnabled: Bool

  /// for use in UI only
  let displayMessage: String

  init(_ keyMapping: KeyMapping, origin: InputBindingOrigin, srcSectionName: String, isEnabled: Bool = true,
       displayMessage: String = "") {
    self.keyMapping = keyMapping
    self.origin = origin
    self.srcSectionName = srcSectionName
    self.isEnabled = isEnabled
    self.displayMessage = displayMessage.isEmpty ? (keyMapping.comment ?? "") : displayMessage
  }

  /// Clones this `InputBinding`, but using the given fields if provided.
  func shallowClone(keyMapping: KeyMapping? = nil, isEnabled: Bool? = nil, displayMessage: String? = nil) -> InputBinding {
    InputBinding(keyMapping ?? self.keyMapping,
                 origin: self.origin, srcSectionName: self.srcSectionName,
                 isEnabled: isEnabled ?? self.isEnabled, displayMessage: displayMessage ?? "")
  }

  /// Only mpv bindings in the "default" section can be modified or deleted
  var canBeModified: Bool { origin == .confFile }

  var hasMenuItem: Bool { !keyMapping.sourceName.isEmpty }

  /// Only mpv bindings can be copied
  var canBeCopied: Bool { origin == .confFile || origin == .libmpv }

  var description: String { "{\(srcSectionName)} \(keyMapping)" }

  /// Hashable protocol conformance, to enable diffing
  func hash(into hasher: inout Hasher) {
    hasher.combine(keyMapping)
    hasher.combine(origin)
    hasher.combine(srcSectionName)
    hasher.combine(isEnabled)
    hasher.combine(displayMessage)
  }

  /// Equatable protocol conformance, to enable diffing
  func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? InputBinding else {
      return false
    }
    return self == other
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    (lhs.keyMapping == rhs.keyMapping)
    && (lhs.origin == rhs.origin)
    && (lhs.srcSectionName == rhs.srcSectionName)
    && (lhs.isEnabled == rhs.isEnabled)
    && (lhs.displayMessage == rhs.displayMessage)
  }
  static func != (lhs: Self, rhs: Self) -> Bool {
    !(lhs == rhs)
  }

  func getKeyColumnDisplay(raw: Bool) -> String {
    raw ? keyMapping.rawKey : keyMapping.prettyKey
  }

  func getActionColumnDisplay(raw: Bool) -> String {
    keyMapping.actionDescription(preferRaw: raw)
  }
}
