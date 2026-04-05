//
//  TableStateManager.swift
//  iina
//
//  Created by Matt Svoboda on 11/26/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// Just a bunch of boilerplate code for actionName, logging
@MainActor
class UndoHelper {
  static let DO = "Do"
  static let UNDO = "Undo"
  static let REDO = "Redo"

  typealias ActionBody = Callback

  var undoManager: UndoManager? {
    nil  // Subclasses should override
  }

  func willUndoOrRedo() {
    // Subclasses should override
  }

  // This can be called both for the "undo" of the original "do", and for the "redo" (AKA the undo of the undo).
  // `actionName` will only be used for the original "do" action, and will be cached for use in "undo" / "redo".
  // Note: the `redo` param exists to (hopefully) improve readability and better indicate intent. It does not need to
  // be used if `undoAction` calls `registerUndo()` itself.
  @discardableResult
  func register(_ actionName: String? = nil, undo undoAction: @escaping ActionBody, redo redoAction: ActionBody? = nil) -> Bool {
    guard let undoMan = self.undoManager else {
      Logger.log.verbose("Cannot register for undo: undoManager is nil")
      return false
    }

    let origActionName: String? = UndoHelper.getOrSetOriginalActionName(actionName, undoMan)

    Logger.log.verbose("[\(UndoHelper.formatAction(origActionName, undoMan))] Registering for \(undoMan.isRedoing ? UndoHelper.REDO : UndoHelper.UNDO)")

    undoMan.registerUndo(withTarget: self, handler: { [self] manager in
      guard let undoMan = undoManager else {
        Logger.log.error("Cannot undo: undoManager is nil!")
        return
      }
      // Undo starts here. Or: undo of the undo (redo)
      Logger.log.verbose("[\(UndoHelper.formatAction(origActionName, undoMan))] Starting \(UndoHelper.currentOp(undoMan)) (\(UndoHelper.extraDebug(undoMan)))")

      willUndoOrRedo()
      undoAction()

      if let redoAction {
        self.register(actionName, undo: redoAction, redo: undoAction)
      }
    })

    return true
  }

  func clearUndoes() {
    undoManager?.removeAllActions(withTarget: self)
  }

  func isUndoing() -> Bool {
    return self.undoManager?.isUndoing ?? false
  }

  func isUndoingOrRedoing() -> Bool {
    if let undoManager = self.undoManager, undoManager.isUndoing || undoManager.isRedoing {
      return true
    }
    return false
  }

  // Format the action name for Edit menu display (Undo/Redo)
  fileprivate func buildActionName(_ unit: Unit, basedOn tableUIChange: TableUIChange? = nil) -> String? {
    guard let tableUIChange else { return nil }

    switch tableUIChange.changeType {
    case .insertRows:
      return Utility.format(unit, tableUIChange.toInsert?.count ?? 0, .add)
    case .removeRows:
      return Utility.format(unit, tableUIChange.toRemove?.count ?? 0, .delete)
    case .moveRows:
      return Utility.format(unit, tableUIChange.toMove?.count ?? 0, .move)
    case .updateRows:
      return Utility.format(unit, tableUIChange.toUpdate?.count ?? 0, .update)
    default:
      return nil
    }
  }


  static private func getOrSetOriginalActionName(_ actionName: String?, _ undoMan: UndoManager) -> String? {
    if undoMan.isUndoing {
      return undoMan.undoActionName
    }
    if undoMan.isRedoing {
      return undoMan.redoActionName
    }

    // Action name only needs to be set once per action, and it will displayed for both "Undo {}" and "Redo {}".
    // There's no need to change the name of it for the redo.
    if let origActionName = actionName {
      undoMan.setActionName(origActionName)
      return origActionName
    }
    return nil
  }

  static private func extraDebug(_ undoMan: UndoManager) -> String {
    "canUndo=\(undoMan.canUndo.yn) canRedo=\(undoMan.canRedo.yn)"
  }

  static private func currentOp(_ undoMan: UndoManager) -> String {
    undoMan.isUndoing ? UNDO : (undoMan.isRedoing ? REDO : DO)
  }

  static private func formatAction(_ actionName: String?, _ undoMan: UndoManager) -> String {
    let op = UndoHelper.currentOp(undoMan)
    if let action = actionName {
      return "\(op) \(action)"
    }
    return op
  }
}

class PlayerWindowUndoHelper: UndoHelper {
  unowned var pwc: PlayerWindowController
  unowned var _undoManager: UndoManager? = nil

  init(_ pwc: PlayerWindowController, _ undoManager: UndoManager?) {
    self.pwc = pwc
    self._undoManager = undoManager
  }

  override var undoManager: UndoManager? {
    _undoManager
  }

  override func willUndoOrRedo() {
    pwc.showWindow(nil)
  }

  func buildActionName(basedOn tableUIChange: TableUIChange? = nil) -> String? {
    return buildActionName(.playlistItem, basedOn: tableUIChange)
  }
}

class PrefKeyBindingUndoHelper: UndoHelper {
  override var undoManager: UndoManager? {
    AppDelegate.shared.preferenceWindowController.windowUndoManager
  }

  override func willUndoOrRedo() {
    // Go into Key Bindings tab so it is clear to user what is being undone.
    AppDelegate.shared.preferenceWindowController.selectKeyBindingTab()
  }

  /// Format the action name for Edit menu display (Undo/Redo)
  func buildActionName(basedOn tableUIChange: TableUIChange? = nil) -> String? {
    return buildActionName(.keyBinding, basedOn: tableUIChange)
  }
}

class PrefAdvancedUndoHelper: UndoHelper {
  override var undoManager: UndoManager? {
    AppDelegate.shared.preferenceWindowController.windowUndoManager
  }

  override func willUndoOrRedo() {
    // Go into Key Bindings tab so it is clear to user what is being undone.
    AppDelegate.shared.preferenceWindowController.selectAdvancedTab()
  }

  func buildActionName(basedOn tableUIChange: TableUIChange? = nil) -> String? {
    return buildActionName(.option, basedOn: tableUIChange)
  }
}
