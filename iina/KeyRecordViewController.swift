//
//  KeyRecordViewController.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Combine

class KeyRecordViewController: NSViewController, @MainActor KeyRecordViewDelegate, @MainActor NSRuleEditorDelegate, NSTextFieldDelegate {
  private var activeObservers: Set<AnyCancellable> = []

  @IBOutlet weak var keyRecordView: KeyRecordView!
  @IBOutlet weak var keyLabel: NSTextField!
  @IBOutlet weak var actionTextField: NSTextField!
  @IBOutlet weak var ruleEditor: NSRuleEditor!

  private lazy var criterions: [Criterion] = KeyBindingDataLoader.load()

  private var pendingKey: String?
  private var pendingAction: String?

  @objc dynamic var ready = false

  var keyCode: String {
    get {
      return keyLabel.stringValue
    }
    set {
      if let f = keyLabel {
        f.stringValue = newValue
      } else {
        pendingKey = newValue
      }
    }
  }

  var action: String {
    get {
      return actionTextField.stringValue
    }
    set {
      if let f = actionTextField {
        f.stringValue = newValue
      } else {
        pendingAction = newValue
      }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    keyRecordView.delegate = self

    ruleEditor.nestingMode = .single
    ruleEditor.canRemoveAllRows = false
    ruleEditor.delegate = self
    ruleEditor.addRow(self)

    keyLabel.delegate = self
    actionTextField.delegate = self

    if let pk = pendingKey {
      keyLabel.stringValue = pk
      pendingKey = nil
    }
    if let pa = pendingAction {
      actionTextField.stringValue = pa
      pendingAction = nil
    }

  }

  override func viewWillAppear() {
    super.viewWillAppear()

    NotificationCenter.default.publisher(for: .iinaKeyBindingInputChanged, object: nil)
      .receive(on: RunLoop.main)
      .sink(receiveValue: { [self] _ in
        self.updateCommandField()
      })
      .store(in: &activeObservers)
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()

    let activeObservers = activeObservers
    self.activeObservers = []
    for observer in activeObservers {
      observer.cancel()
    }
  }

  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent) {
    keyLabel.stringValue = KeyCodeHelper.mpvKeyCode(from: event)
    NotificationCenter.default.post(.init(name: NSControl.textDidChangeNotification, object: keyLabel))
  }

  // MARK: - NSRuleEditorDelegate

  func ruleEditor(_ editor: NSRuleEditor, child index: Int, forCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Any {
    if criterion == nil {
      return criterions[index]
    } else {
      return (criterion as! Criterion).child(at: index)
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, numberOfChildrenForCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Int {
    if criterion == nil {
      return criterions.count
    } else {
      return (criterion as! Criterion).childrenCount()
    }
  }

  func ruleEditor(_ editor: NSRuleEditor, displayValueForCriterion criterion: Any, inRow row: Int) -> Any {
    return (criterion as! Criterion).displayValue()
  }

  func ruleEditorRowsDidChange(_ notification: Notification) {
    updateCommandField()
  }

  // MARK: - Other

  @MainActor
  private func updateCommandField() {
    guard let criterions = ruleEditor.criteria(forRow: 0) as? [Criterion] else { return }
    actionTextField.stringValue = KeyBindingTranslator.string(fromCriteria: criterions)
    NotificationCenter.default.post(.init(name: NSControl.textDidChangeNotification, object: actionTextField))
  }

  func controlTextDidChange(_ obj: Notification) {
    ready = !keyCode.isEmpty && !action.isEmpty
  }
}

