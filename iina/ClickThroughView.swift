//
//  ClickThroughView.swift
//  iina
//
//  Created by Matt Svoboda on 11/28/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
 
class ClickThroughView: NSView {
  // Just return true always. May have a SymButton underneath.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class ClickThroughStackView: NSStackView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class ClickThroughTextField: NSTextField {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class MouseIgnoringVisualEffectView: NSVisualEffectView {

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Do not accept any mouse events
    return nil
  }
}
