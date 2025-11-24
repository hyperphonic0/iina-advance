//
//  KeyBindingCriterion.swift
//  iina
//
//  Created by lhc on 3/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

/// Needs `@MainActor` for `TextFieldCriterion`...
@MainActor
class Criterion: NSObject {

  let isPlaceholder: Bool
  let isIINACommand: Bool

  let children: [Criterion]

  var mpvCommandValue: String { get { return "" } }

  init(children: [Criterion], isPlaceholder: Bool, isIINACommand: Bool) {
    self.children = children
    self.isPlaceholder = isPlaceholder
    self.isIINACommand = isIINACommand
    super.init()
  }

  func childrenCount() -> Int {
    return children.count
  }

  func child(at index: Int) -> Criterion {
    return children[index]
  }

  func displayValue() -> Any { return "" }

}


class TextCriterion: Criterion {

  let name: String
  let localizedName: String

  override var mpvCommandValue: String {
    get {
      return name
    }
  }

  init(name: String, localizedName: String, children: [Criterion], isPlaceholder: Bool, isIINACommand: Bool) {
    self.name = name
    self.localizedName = localizedName
    super.init(children: children, isPlaceholder: isPlaceholder, isIINACommand: isIINACommand)
  }

  override func displayValue() -> Any {
    return localizedName
  }

}


class TextFieldCriterion: Criterion, NSTextFieldDelegate, NSControlTextEditingDelegate {

  private let field: NSTextField

  override init(children: [Criterion], isPlaceholder: Bool, isIINACommand: Bool) {
    self.field = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 18))
    field.focusRingType = .none
    field.bezelStyle = .roundedBezel
    field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
    super.init(children: children, isPlaceholder: isPlaceholder, isIINACommand: isIINACommand)
    field.delegate = self
  }

  override var mpvCommandValue: String {
    get {
      return field.stringValue
    }
  }

  override func displayValue() -> Any {
    return field
  }

  func controlTextDidChange(_ obj: Notification) {
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingInputChanged))
  }

}

class SeparatorCriterion: Criterion {

  init(children: [Criterion]) {
    super.init(children: children, isPlaceholder: false, isIINACommand: false)
  }

  override func displayValue() -> Any {
    return NSMenuItem.separator()
  }

}
