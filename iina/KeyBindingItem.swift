//
//  KeyBindingItem.swift
//  iina
//
//  Created by lhc on 4/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

struct KeyBindingItem {
  static let separator = KeyBindingItem("---", type: .separator)

  // MARK: KeyBindingItem

  enum ItemType {
    case label, iinaCmd, string, number, placeholder, separator
  }

  let name: String
  let type: ItemType

  let l10nKey: String?

  let children: [KeyBindingItem]

  static func chooseIn(_ optionsList: String) -> [KeyBindingItem] {
    let options = optionsList.components(separatedBy: "|")
    var items: [KeyBindingItem] = []
    for op in options {
      items.append(KeyBindingItem(op))
    }
    return items
  }

  static func chooseIn(_ optionsList: String, children: KeyBindingItem...) -> [KeyBindingItem] {
    let options = optionsList.components(separatedBy: "|")
    var items: [KeyBindingItem] = []
    for op in options {
      items.append(KeyBindingItem(op, type: .label, children: children))
    }
    return items
  }

  init(_ name: String, type: ItemType, l10nKey: String? = nil, children: KeyBindingItem...) {
    self.name = name
    self.type = type
    self.l10nKey = l10nKey
    self.children = children
  }

  init(_ name: String, type: ItemType, l10nKey: String? = nil, children: [KeyBindingItem]) {
    self.name = name
    self.type = type
    self.l10nKey = l10nKey
    self.children = children
  }

  init(_ name: String, l10nKey: String? = nil) {
    self.name = name
    self.type = .label
    self.l10nKey = l10nKey
    self.children = []
  }

  init(_ name: String, type: ItemType, l10nKey: String? = nil) {
    self.name = name
    self.type = type
    self.l10nKey = l10nKey
    self.children = []
  }

  @MainActor
  func toCriterion(l10nKey: String? = nil) -> Criterion {

    let critChildren = children.map{ $0.toCriterion() }

    let criterion: Criterion

    switch type {
    case .label, .placeholder, .iinaCmd:
      let k = type == .iinaCmd ? "iina" : (l10nKey ?? self.l10nKey)
      let l10nPath = k == nil ? name : "\(k!).\(name)"
      let l10nString = KeyBindingTranslator.l10nDic[l10nPath] ?? name
      criterion = TextCriterion(name: name,
                                localizedName: l10nString,
                                children: critChildren,
                                isPlaceholder: type == .placeholder,
                                isIINACommand: type == .iinaCmd)
    case .string, .number:
      criterion = TextFieldCriterion(children: critChildren, isPlaceholder: false, isIINACommand: false)
    case .separator:
      criterion = SeparatorCriterion(children: critChildren)
    }


    return criterion
  }

}
