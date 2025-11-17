//
//  EditableTextField.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.23.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class EditableTableCellView : NSTableCellView {
  /// Workaround for an AppKit quirk which would otherwise result in the cell's text and/or image to be set to a different
  /// size than what is in the XIB.
  override func viewWillDraw() {
    let imageViewFrame = imageView?.frame
    let textFieldFrame = textField?.frame

    super.viewWillDraw()

    if let imageView, let imageViewFrame, imageViewFrame.origin.x != imageView.frame.origin.x {
      imageView.setFrameOrigin(NSPoint(x: imageViewFrame.origin.x, y: imageView.frame.origin.y))
    }

    if let textField, let textFieldFrame {
      if textFieldFrame.origin.x != textField.frame.origin.x {
        textField.setFrameOrigin(NSPoint(x: textFieldFrame.origin.x, y: textField.frame.origin.y))
      }
      if textFieldFrame.size.width != textField.frame.size.width {
        textField.setFrameSize(NSSize(width: textFieldFrame.size.width, height: textField.frame.size.height))
      }
    }
  }
}

/*
 Should only be used within cells of `EditableTableView`.
 */
class EditableTextField: NSTextField {
  var editTracker: CellEditTracker? = nil
  /// Created & activated when editing starts, then removed when editing ends.
  ///
  /// This is a bit of a kludge to force a multi-line text field to maintain its height during editing.
  /// Otherwise it wants to collapse into the height of a single line when the field editor is inserted…
  var heightConstraint: NSLayoutConstraint? = nil

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      guard let editTracker = self.editTracker else {
        Logger.log("Table textField \(self) received double-click event without validateProposedFirstResponder() being called first!", level: .error)
        super.mouseDown(with: event)
        return
      }

      Logger.log.verbose{"EditableTextField: Got a double-cick"}
      let approved = editTracker.askUserToApproveDoubleClickEdit()
      Logger.log.verbose{"Double-click approved: \(approved.yesno)"}
      if approved {
        self.window?.makeFirstResponder(self)
      }
      // These are the only cases where `super.mouseDown()` should not be called
      return
    }
    super.mouseDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    if let editTracker = editTracker {
      editTracker.startEdit()
    } else {
      Logger.log("Table textField \(self) had becomeFirstResponder() called without editTracker being set first!", level: .error)
    }
    return true
  }

  override var textColor: NSColor? {
    didSet {
      if let cell = self.cell as? EditableTextFieldCell {
        cell.textColorOrig = textColor
      }
    }
  }
}

// This class (so far) exists only for one reason: to make sure that rows with custom colored text
// will change back to the regular control color when their row is highlighted.
//
// To use, just make sure this class name is specified for every text field cell in every column which
// can have colored text (also that its parent is an `EditableTextField' and the parent table is
// an `EditableTableView`), and to set the desired color for the text, set the `textColor` property of
// the parent `EditableTextField`.
class EditableTextFieldCell: NSTextFieldCell {
  var textColorOrig: NSColor? = nil

  // When the background changes (as a result of selection/deselection), change text color appropriately.
  // This is needed to account for custom text coloring.
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      switch backgroundStyle {
        case .normal, .lowered:      // Deselected
          textColor = textColorOrig
        case .emphasized, .raised:  // AKA selected
          textColor = nil  // Use standard color
        default:
          Logger.log("Unsupported background style: \(backgroundStyle)", level: .warning	)
      }
    }
  }
}
