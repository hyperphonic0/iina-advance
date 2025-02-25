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

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Do not accept any mouse events
    return nil
  }

}
