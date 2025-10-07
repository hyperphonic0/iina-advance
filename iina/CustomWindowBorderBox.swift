//
//  CustomWindowBorderBox.swift
//  iina
//
//  Created by Matt Svoboda on 11/30/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `CustomWindowBorderBox` is used when drawing a "legacy" player window to provide a 0.5px border to
/// trailing, bottom, and leading sides, and a 1px gradient effect on the top side.
/// Because this element is higher in the Z ordering than the floating OSC and/or `VideoView`,
/// we need to add code to ignore `NSResponder` events appropriately
class CustomWindowBorderBox: NSBox {
  init(id: String, borderWidth: CGFloat, borderColor: NSColor) {
    super.init(frame: .zero)
    configureSelf(id: id, borderWidth: borderWidth, borderColor: borderColor)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureSelf()
  }

  private func configureSelf(id: String? = nil, borderWidth: CGFloat? = nil, borderColor: NSColor? = nil) {
    if let id {
      idString = id  // helps with debug logging
    }

    wantsLayer = true
    boxType = .custom
    titlePosition = .noTitle
    cornerRadius = 0
    translatesAutoresizingMaskIntoConstraints = false
    fillColor = .clear

    if let borderWidth {
      self.borderWidth = borderWidth
    }
    if let borderColor {
      self.borderColor = borderColor
    }
  }

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Do not accept any mouse events
    return nil
  }

}
