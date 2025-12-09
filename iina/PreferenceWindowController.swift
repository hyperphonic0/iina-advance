//
//  PreferenceWindowController.swift
//  iina
//
//  Created by Collider LI on 6/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate extension String {
  func removedLastSemicolon() -> String {
    let trimmed = trimWhitespaceSuffix()
    guard !trimmed.hasSuffix(":") else { return String(trimmed.dropLast()) }
    return self
  }

  func trimWhitespaceSuffix() -> String {
    self.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
  }
}

fileprivate extension NSView {
  func identifierStartsWith(_ prefix: String) -> Bool {
    if let id = identifier {
      return id.rawValue.starts(with: prefix)
    } else {
      return false
    }
  }
}

protocol PreferenceWindowEmbeddable where Self: NSViewController {
  var preferenceTabTitle: String { get }
  var preferenceTabImage: NSImage { get }
  var preferenceContentIsScrollable: Bool { get }
}

extension PreferenceWindowEmbeddable {
  var preferenceContentIsScrollable: Bool {
    return true
  }
}

class CustomCellView: NSTableCellView {
  @IBOutlet weak var leadingConstraint: NSLayoutConstraint!

  override func viewWillDraw() {
    if #unavailable (macOS 11.0) {
      leadingConstraint.constant = 20
    }
    super.viewWillDraw()
  }
}


class PreferenceWindowController: WindowController, NSWindowDelegate {
  unowned var windowUndoManager: UndoManager? = nil
  /// Use for all animations in the `Preferences` window, if possible.
  let animationPipeline = IINAAnimation.Pipeline(nil)

  // Only used for MacOS 26+
  let detailView = NSView()

  class Trie {

    class Node {
      var children: [Node] = []
      let char: Character
      init(_ c: Character) {
        char = c
      }
    }

    typealias ReturnValue = (tab: String, strippedSection: String, strippedLabel: String?, section: String, label: String?)

    var s: String
    let returnValue: ReturnValue

    let root: Node
    var lastPosition: Node

    var active: Bool

    init(tab: String, section: String, label: String?) {
      s = [tab, section, label].compactMap { $0 }.joined(separator: " ").lowercased()
      returnValue = (tab, section.removedLastSemicolon(), label?.removedLastSemicolon(), section, label)

      root = Node(" ")
      lastPosition = root
      active = true

      let strings = s.components(separatedBy: " ")
      for string in strings {
        var t = string
        while t.count != 0 {
          addString(t)
          t.removeFirst()
        }
      }
    }

    func reset() {
      lastPosition = root
      active = true
    }

    func addString(_ str: String) {
      var current = root
      for c in Array(str) {
        if let next = current.children.first(where: { $0.char == c }) {
          current = next
        } else {
          let newNode = Node(c)
          current.children.append(newNode)
          current = newNode
        }
      }
    }

    func search(_ str: String) {
      let lowercaseStr = str.lowercased()
      for c in lowercaseStr {
        // half-width and full-width spaces
        if c == " " || c == "　" {
          lastPosition = root
          continue
        }
        if let next = lastPosition.children.first(where: { $0.char == c }) {
          lastPosition = next
        } else {
          active = false
          return
        }
      }
    }

  }

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PreferenceWindowController")
  }

  private var tries: [Trie] = []
  private var searchString: String = ""
  private var currentCompletionResults: [Trie.ReturnValue] = []

  private var needsIndex: Bool = true
  
  enum Action {
    case installPlugin(url: URL)
  }

  @IBOutlet weak var searchField: NSSearchField!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var maskView: PrefSearchResultMaskView!
  @IBOutlet weak var prefDetailScrollView: NSScrollView!  // contains the prefs detail panel (on right)
  // Check `prefDetailContentView` constraints in the XIB for window content insets
  @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var prefDetailContentView: NSView!       // contains the sections stack
  @IBOutlet var completionPopover: NSPopover!
  @IBOutlet weak var completionTableView: NSTableView!
  @IBOutlet weak var noResultLabel: NSTextField!

  @IBOutlet weak var searchFieldTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var searchFieldBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var navTableSearchFieldSpacingConstraint: NSLayoutConstraint!

  private var detailViewBottomConstraint: NSLayoutConstraint?

  private var viewControllers: [NSViewController & PreferenceWindowEmbeddable]

  private var observers: [NSObjectProtocol] = []

  init() {
    var viewControllers: [NSViewController & PreferenceWindowEmbeddable] = [
      PrefGeneralViewController(),
      PrefUIViewController(),
      PrefDataViewController(),
      PrefCodecViewController(),
      PrefSubViewController(),
      PrefNetworkViewController(),
      PrefControlViewController(),
      PrefKeyBindingViewController(),
      PrefAdvancedViewController(),
      // PrefPluginViewController(),
      PrefUtilsViewController(),
    ]

    if AppDelegate.iinaPluginSystemEnabled {
      viewControllers.insert(PrefPluginViewController(), at: 8)
    }
    self.viewControllers = viewControllers
    super.init(window: nil)
    self.windowFrameAutosaveName = WindowAutosaveName.preferences.string
    Logger.log("PreferenceWindowController init", level: .verbose)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    for observer in observers {
      ObjcUtils.silenced {
        NotificationCenter.default.removeObserver(observer)
      }
    }
    observers = []
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    // Set this to true temporarily, so that table doesn't fire selectionChanged events while setting up
    tableView.allowsEmptySelection = true

    if let undoManager = window?.undoManager {
      Logger.log.verbose("PreferenceWindow loaded: setting UndoManager")
      // Make more easily accessible for other components
      windowUndoManager = undoManager
    }
    window?.isMovableByWindowBackground = true

    tableView.delegate = self
    tableView.dataSource = self
    completionTableView.delegate = self
    completionTableView.dataSource = self

    detailViewBottomConstraint = prefDetailContentView.bottomAnchor.constraint(equalTo: prefDetailContentView.superview!.bottomAnchor)

    // NSTableView's "Source List" style is only available with MacOS 11.0+ and includes a built-in 10pt offset for its highlights.
    // But for older MacOS versions, the style will default to "full width" with no highlight offset, which will touch the Search field.
    if #unavailable(macOS 11.0) {
      navTableSearchFieldSpacingConstraint.constant = 10.0
    }

#if compiler(>=6.2) // only when using Xcode 26+

    // replace with split view when all subviews are properly loaded
    if #available(macOS 26.0, *) {
      setupForLiquidGlass()
    }
#endif

    // To restore selection properly, must set table to allow empty selection initially (in XIB).
    // Otherwise, it will automatically select the first value and trigger the selection notification.
    // Much safer to disable empty selection after selecting a row.
    loadTab(at: UIState.shared.getSavedValue(for: .uiPrefWindowNavTableSelectionIndex))
    tableView.allowsEmptySelection = false
    let observer = prefDetailScrollView.restoreAndObserveVerticalScroll(key: .uiPrefDetailViewScrollOffsetY, defaultScrollAction: {
      prefDetailScrollView.scroll(NSPoint())
    })
    self.observers.append(observer)

    // Focus on searchField first
    window?.initialFirstResponder = searchField

    Logger.log.verbose("PreferenceWindowController windowDidLoad done")
  }

  // Need to wait until window is in focus before trying to show the completion popup (if restoring).
  // Otherwise it will sometimes silently fail to display.
  func windowDidBecomeKey(_ notification: Notification) {
    if needsIndex {
      buildIndexAndRestoreSavedSearch()
    }
  }

  private func buildIndexAndRestoreSavedSearch() {
    assert(DispatchQueue.isExecutingIn(.main))

    var viewMap = [
      ["general", "PrefGeneralViewController"],
      ["ui", "PrefUIViewController"],
      ["data", "PrefDataViewController"],
      ["subtitle", "PrefSubViewController"],
      ["network", "PrefNetworkViewController"],
      ["control", "PrefControlViewController"],
      ["keybindings", "PrefKeyBindingViewController"],
      ["video_audio", "PrefCodecViewController"],
      ["advanced", "PrefAdvancedViewController"],
      ["utilities", "PrefUtilsViewController"],
    ]
    if AppDelegate.iinaPluginSystemEnabled {
      viewMap.insert(["plugins", "PrefPluginViewController"], at: 8)
    }
    let labelDict = [String: [String: [String]]](
      uniqueKeysWithValues: viewMap.map { (NSLocalizedString("preference.\($0[0])", comment: ""), self.getLabelDict(inNibNamed: $0[1])) })

#if DEBUG
    // As the following call emits a lot of messages that are only needed when debugging the NIB
    // scan it is checked into source control commented out.
    //logLabelDict(labelDict)
#endif

    // Do the indexing in background - no need to hurry to display the popup, but don't
    // want to slow down the launch even by 25ms
    DispatchQueue.global(qos: .background).async { [self] in
      let sw = Utility.Stopwatch()

      makeTries(labelDict)
      needsIndex = false
      Logger.log.verbose("PreferenceWindow indexing done in \(sw.msElapsedString)")

      // Restore previous search (if any):
      guard let savedSearchString = PreferenceWindowController.getSearchStringFromPrefs() else { return }
      // Add a small delay from time of window open to draw user's attention to the popup
      DispatchQueue.main.async { [self] in
        searchField.stringValue = savedSearchString
        searchField.sendAction(searchField.action, to: searchField.target)
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    dismissCompletionList()
    super.mouseDown(with: event)
  }

  // MARK: - Searching

  private static func getSearchStringFromPrefs() -> String? {
    return UIState.shared.isRestoreEnabled ? Preference.string(for: .uiPrefWindowSearchString) : nil
  }

  private func makeTries(_ labelDict: [String: [String: [String]]]) {
    // search for sections and labels
    for (k1, v1) in labelDict {
      for (k2, v2) in v1 {
        tries.append(Trie(tab: k1, section: k2, label: nil))
        for k3 in v2 {
          tries.append(Trie(tab: k1, section: k2, label: k3))
        }
      }
    }
  }

  @IBAction func searchFieldAction(_ sender: Any) {
    guard !needsIndex else { return }
    let newSearchString = searchField.stringValue.lowercased().trimWhitespaceSuffix().removedLastSemicolon()
    guard newSearchString != searchString else { return }
    Logger.log.verbose("Prefs search string: \(newSearchString.quoted)")
    if newSearchString.isEmpty {
      dismissCompletionList()
    } else {
      for trie in tries {
        trie.reset()
        trie.search(newSearchString)
      }
      currentCompletionResults = tries.filter { $0.active }.map { $0.returnValue }
      completeSearchField()
    }
    // Save search string in UI state, if enabled:
    if UIState.shared.isRestoreEnabled, Preference.string(for: .uiPrefWindowSearchString) != newSearchString {
      Preference.set(newSearchString, for: .uiPrefWindowSearchString)
    }
    searchString = newSearchString
  }

  private func completeSearchField() {
    assert(DispatchQueue.isExecutingIn(.main))
    let resultsCount = currentCompletionResults.count
    noResultLabel.isHidden = resultsCount != 0
    if !completionPopover.isShown {
      Logger.log.verbose("Showing Prefs search field completion popover, resultsCount=\(resultsCount)")
      let range = searchField.currentEditor()?.selectedRange
      completionPopover.show(relativeTo: searchField.bounds, of: searchField, preferredEdge: .maxY)
      searchField.selectText(self)
      searchField.currentEditor()?.selectedRange = range ?? NSMakeRange(0, 0)
    }
    completionTableView.reloadData()
  }

  private func dismissCompletionList() {
    if completionPopover.isShown {
      Logger.log.verbose("Closing Prefs search field completion popover")
      completionPopover.close()
    }
  }

  // MARK: - Tabs

  /// Opens the tab at the given index.
  @discardableResult
  private func loadTab(at index: Int, thenFindLabelTitled title: String? = nil) -> PreferenceWindowEmbeddable? {
    // load view
    if index != tableView.selectedRow {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    prefDetailContentView.removeAllSubviews()
    guard let vc = viewControllers[at: index] else { return nil }
    prefDetailContentView.addSubview(vc.view)
    if #available(macOS 26.0, *) {
      // Liquid Glass: make top of content start below search bar, but allow it to scroll underneath it.
      // Use padding so that content aligns with title bar text
      vc.view.addConstraintsToFillSuperview(top: detailView.safeAreaInsets.top, bottom: 20, leading: 20, trailing: 20)
    } else {
      vc.view.addConstraintsToFillSuperview(top: 0, bottom: 28, leading: 28, trailing: 28)
    }

    let isScrollable = vc.preferenceContentIsScrollable
    detailViewBottomConstraint?.isActive = !isScrollable

    // find label
    if let title = title, let label = findLabel(titled: title, in: vc.view) {
      maskView.perform(#selector(maskView.highlight(_:)), with: label, afterDelay: 0.25)
      if let collapseView = findCollapseView(label) {
        collapseView.setCollapsed(false, animated: false)
      }
    }

    UIState.shared.set(index, for: .uiPrefWindowNavTableSelectionIndex)

    // As per Apple's Human Interface Guidelines update the window’s title to reflect the currently
    // visible tab. Although the window's title is hidden it still can be seen in the Window menu
    // and in the dock menu.
    window?.title = vc.preferenceTabTitle

    // Now that new views have been added, need to regenerate the chain of views for keyboard navigation
    window?.recalculateKeyViewLoop()

    return vc
  }

  func selectKeyBindingTab() {
    let kbIndex = viewControllers.firstIndex(where: { $0 is PrefKeyBindingViewController })
    guard let kbIndex, kbIndex >= 0, tableView.selectedRow != kbIndex else { return }
    loadTab(at: kbIndex)
  }

  func selectAdvancedTab() {
    let kbIndex = viewControllers.firstIndex(where: { $0 is PrefAdvancedViewController })
    guard let kbIndex, kbIndex >= 0, tableView.selectedRow != kbIndex else { return }
    loadTab(at: kbIndex)
  }

  private func getLabelDict(inNibNamed name: String) -> [String: [String]] {
    var objects: NSArray? = NSArray()
    Bundle.main.loadNibNamed(NSNib.Name(name), owner: nil, topLevelObjects: &objects)
    if let topObjects = objects as? [Any] {
      // we assume this nib is a preference view controller, so each section must be a top-level `NSView`.
      return [String: [String]](uniqueKeysWithValues: topObjects.compactMap { view -> (title: String, labels: [String])? in
        if let section = view as? NSView {
          return findLabels(inSection: section)
        } else {
          return nil
        }
      })
    }
    return [:]
  }

  private func findLabels(inSection section: NSView) -> (title: String, labels: [String])? {
    guard let sectionTitleLabel = section.subviews.first(where: {
        $0 is NSTextField && $0.identifierStartsWith("SectionTitle")
      }) else {
        return nil
    }
    let title = formSearchTerm((sectionTitleLabel as! NSTextField).stringValue)
    var labels = findLabels(in: section)
    labels.remove(at: labels.firstIndex(of: title)!)
    return (title, labels)
  }

  private func findLabels(in view: NSView) -> [String] {
    var labels: [String] = []
    for subView in view.subviews {
      if let title = getTitle(from: subView) {
        labels.append(title)
      }
      labels.append(contentsOf: findLabels(in: subView))
    }
    return labels
  }

  /// Form a search term from the given string.
  ///
  /// The UI labels and titles contain extraneous characters that must be removed for them to be used as a search term.
  /// - Parameter string: The string to turn into a search term.
  /// - Returns: The given string with extraneous characters removed.
  private func formSearchTerm(_ string: String) -> String {
    string.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "[:…()\"\n]", with: "", options: .regularExpression)
  }

  private func findLabel(titled title: String, in view: NSView) -> NSView? {
    for subView in view.subviews {
      if getTitle(from: subView) == title {
        return subView
      }
      if let r = findLabel(titled: title, in: subView) {
        return r
      }
    }
    return nil
  }

  private func getTitle(from view: NSView) -> String? {
    if let label = view as? NSTextField,
      !label.isEditable, label.textColor == .labelColor, label.stringValue != "Label",
      !label.identifierStartsWith("AccessoryLabel"), !label.identifierStartsWith("Trigger") {
      return formSearchTerm(label.stringValue)
    } else if let button = view as? NSButton,
      (button.identifierStartsWith("FunctionalButton") || button.bezelStyle == .regularSquare) {
      return formSearchTerm(button.title)
    }
    return nil
  }

  private func findCollapseView(_ view: NSView) -> CollapseView? {
    if let superview = view.superview {
      if let collapseView = superview as? CollapseView {
        return collapseView
      } else {
        return findCollapseView(_:superview)
      }
    }
    return nil
  }

  @discardableResult
  func openPreferenceView(withNibName name: NSNib.Name) -> PreferenceWindowEmbeddable? {
    showWindow(self)
    guard let idx = viewControllers.firstIndex(where: { $0.nibName == name } ) else { return nil }
    return loadTab(at: idx)
  }

  func performAction(_ action: Action) {
    switch action {
    case .installPlugin(url: let url):
      let vc = openPreferenceView(withNibName: "PrefPluginViewController") as! PrefPluginViewController
      vc.installPluginAction(localPackageURL: url)
      // vc.perform(#selector(vc.installPluginAction(localPackageURL:)), with: url, afterDelay: 0.25)
    }
  }

  // MARK: - Debugging

#if DEBUG
  /// Log the search terms found in the NIB scan.
  ///
  /// The log messages emitted by this method are only useful to developers when validating the results of scanning the settings NIBs.
  /// - Parameter labelDict: Nested dictionary  containing the search terms that were found in the scan.
  private func logLabelDict(_ labelDict: [String: [String: [String]]]) {
    Logger.log("--------------------------------------------------")
    Logger.log("Search terms found in scan of settings panel NIBs:")
    for (section, subSection) in labelDict {
      Logger.log("\(section)")
      for (subSectionName, contents) in subSection {
        Logger.log("  \(subSectionName)")
        for label in contents {
          Logger.log("    \(label)")
        }
      }
    }
    Logger.log("--------------------------------------------------")
  }
#endif
}

extension PreferenceWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == self.tableView {
      return viewControllers.count
    } else {
      return currentCompletionResults.count
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == self.tableView {
      return [
        "image": viewControllers[at: row]?.preferenceTabImage,
        "title": viewControllers[at: row]?.preferenceTabTitle
      ] as [String: Any?]
    } else {
      guard let result = currentCompletionResults[at: row] else { return nil }
      let noLabel = result.strippedLabel == nil
      return [
        "tab": result.tab,
        "noSection": noLabel,
        "section": result.strippedSection,
        "label": result.strippedLabel ?? result.strippedSection,
      ] as [String: Any?]
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if (notification.object as! NSTableView) == self.tableView {
      loadTab(at: tableView.selectedRow)
    } else {  // clicked on search result from Search box
      dismissCompletionList()
      guard
        let result = currentCompletionResults[at: completionTableView.selectedRow],
        let index = viewControllers.enumerated().first(where: { (_, vc) in vc.preferenceTabTitle == result.tab })?.offset
        else {
          return
      }
      loadTab(at: index, thenFindLabelTitled: result.label ?? result.section)
    }
  }

}

// MARK: - Liquid Glass

#if compiler(>=6.2)

extension PreferenceWindowController {
  @available(macOS 26.0, *)
  func setupForLiquidGlass() {
    guard let window else { return }
    window.styleMask = [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView]
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = false
    window.collectionBehavior = .fullScreenAuxiliary
    let toolbar = NSToolbar(identifier: "preference.window.toolbar") // dummy toolbar to make sidebar merge with titlebar
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsDisplayModeCustomization = false
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    for v in [maskView!, prefDetailScrollView!] {
      detailView.addSubview(v)
      v.constraints.forEach(v.removeConstraint(_:))
    }
    NSLayoutConstraint.activate([
      prefDetailScrollView.topAnchor.constraint(equalTo: detailView.topAnchor),
      prefDetailScrollView.leadingAnchor.constraint(equalTo: detailView.safeAreaLayoutGuide.leadingAnchor),
      detailView.trailingAnchor.constraint(equalTo: prefDetailScrollView.trailingAnchor),
      detailView.bottomAnchor.constraint(equalTo: prefDetailScrollView.bottomAnchor),

      maskView.topAnchor.constraint(equalTo: detailView.topAnchor),
      maskView.leadingAnchor.constraint(equalTo: detailView.leadingAnchor), // stretch all the way under sidebar
      maskView.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
      maskView.bottomAnchor.constraint(equalTo: detailView.bottomAnchor),
    ])
    prefDetailScrollView.contentView.automaticallyAdjustsContentInsets = true
    let navTableScrollView = tableView.enclosingScrollView!
    let splitController = NSSplitViewController()
    splitController.splitViewItems = [
      NSSplitViewItem(sidebarWithViewController: SimpleViewController(wrapped: navTableScrollView)),
      NSSplitViewItem(viewController: SimpleViewController(wrapped: detailView)),
    ]
    splitController.splitViewItems.forEach {
      $0.automaticallyAdjustsSafeAreaInsets = true // allow mask to stretch under side bar
    }
    navTableScrollView.contentView.automaticallyAdjustsContentInsets = true
    let navContainer = splitController.splitViewItems[0]
    navContainer.canCollapse = false
    navContainer.minimumThickness = 200
    navContainer.maximumThickness = 200
    window.contentViewController = splitController
  }
}

// MARK: - Toolbar for macOS 26+
@available(macOS 26.0, *)
private extension NSToolbarItem.Identifier {
  static let preferenceSearchItem = NSToolbarItem.Identifier("PreferenceSearchItem")
}

@available(macOS 26.0, *)
extension PreferenceWindowController: NSToolbarDelegate {
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .sidebarTrackingSeparator,
      .flexibleSpace,
      .preferenceSearchItem,
    ]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case .preferenceSearchItem:
      let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
      item.searchField.target = self
      item.searchField.placeholderString = "Search in Settings…"
      item.searchField.action = #selector(searchFieldAction(_:))
      // replace the on in xib
      searchField = item.searchField
      return item
    default:
      return nil
    }
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemIdentifier: NSToolbarItem.Identifier, canBeInsertedAt index: Int) -> Bool {
    true
  }
}
#endif // compiler(>=6.2)

// MARK: - Support classes

class PrefSearchResultMaskView: NSView {

  var maskRect: NSRect?

  override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
    if key == "alphaValue" {
      let kfa = CAKeyframeAnimation(keyPath: "alphaValue")
      kfa.duration = 1.5
      kfa.timingFunctions = [CAMediaTimingFunction(name: .default), CAMediaTimingFunction(name: .linear)]
      kfa.values = [1, 1, 0]
      kfa.keyTimes = [0, 0.75, 1.5]
      return kfa
    } else {
      return super.defaultAnimation(forKey: key)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let maskRect = maskRect else { return }
    NSGraphicsContext.saveGraphicsState()
    let framePath = NSBezierPath(rect: bounds)
    let maskPath =  NSBezierPath(roundedRect: maskRect, xRadius: 6, yRadius: 6)
    framePath.append(maskPath)
    framePath.windingRule = .evenOdd
    framePath.setClip()
    NSColor.windowBackgroundColor.withSystemEffect(.pressed).setFill()
    bounds.fill()
    NSGraphicsContext.restoreGraphicsState()
  }

  @objc func highlight(_ view: NSView) {
    view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -20))

    isHidden = false
    alphaValue = 1

    let viewToHighlight = view.identifierStartsWith("SectionTitle") ? view.superview! : view

    let rectInWindow = viewToHighlight.convert(viewToHighlight.bounds.insetBy(dx: -8, dy: -8), to: nil)
    maskRect = convert(rectInWindow, from: nil)
    needsDisplay = true

    NSAnimationContext.runAnimationGroup({ _ in
      self.animator().alphaValue = 0
    }, completionHandler: {
      self.isHidden = true
    })
  }

}

class PrefTabTitleLabelCell: NSTextFieldCell {
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet {
      if backgroundStyle == .emphasized {
        self.textColor = NSColor.white
      } else {
        self.textColor = NSColor.controlTextColor
      }
    }
  }
}

fileprivate class SimpleViewController: NSViewController {
  let wrappedView: NSView

  init(wrapped wrappedView: NSView) {
    self.wrappedView = wrappedView
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = wrappedView
  }
}
