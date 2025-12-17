//
//  LogWindowController.swift
//  iina
//
//  Created by Yuze Jiang on 2022/11/10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let colorMap: [Int: NSColor] = [0: .lightGray, 1: .green, 2: .yellow, 3: .red]
@MainActor fileprivate var circleDict: [NSColor: NSImage] = [:]
fileprivate let kIconSize = 17.0
fileprivate let kBorderWidth = 1.25

class LogWindowController: WindowController, NSMenuDelegate {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("LogWindowController")
  }

  @IBOutlet weak var logTableView: NSTableView!
  @IBOutlet var logArrayController: NSArrayController!
  @IBOutlet weak var subsystemPopUpButton: NSPopUpButton!
  @IBOutlet weak var levelPopUpButton: NSPopUpButton!

  @objc dynamic var logs: [Logger.Log] = []
  @objc dynamic var predicate = NSPredicate(value: true)

  fileprivate var refreshTimer: Timer?

  init() {
    super.init(window: nil)
    self.windowFrameAutosaveName = WindowAutosaveName.logViewer.string
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func windowDidLoad() {
    super.windowDidLoad()

    logTableView.userInterfaceLayoutDirection = .leftToRight
    logTableView.sizeLastColumnToFit()
    let tableViewMenu = NSMenu()
    tableViewMenu.addItem(withTitle: "Copy", action: #selector(menuCopy), keyEquivalent: "")
    logTableView.menu = tableViewMenu

    levelPopUpButton.menu?.items.forEach {
      $0.image = LogWindowController.indicatorIcon(withColor: colorMap[$0.tag]!)
    }
    levelPopUpButton.selectItem(withTag: Logger.Level.preferred.rawValue)
    subsystemPopUpButton.menu!.delegate = self
    
    window?.initialFirstResponder = logTableView
  }

  override func showWindow(_ sender: Any?) {
    Logger.log.verbose("Log window will show")
    super.showWindow(sender)

    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
      DispatchQueue.main.async { [self] in
        syncLogs()
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    Logger.log.verbose("Log window will close")
    refreshTimer?.invalidate()
  }

  fileprivate static func indicatorIcon(withColor color: NSColor) -> NSImage {
    if let cached = circleDict[color] {
      return cached
    }
    let image = NSImage(size: NSMakeSize(kIconSize, kIconSize), flipped: false) { rect in
      let inset = NSInsetRect(rect, kBorderWidth / 2 + rect.size.width * 0.25, kBorderWidth / 2 + rect.size.height * 0.25)
      let path = NSBezierPath.init(ovalIn: inset)
      path.lineWidth = kBorderWidth

      let fractionOfBlendedColor = (NSApp.appearance?.isDark ?? false) ? 0.15 : 0.3
      let borderColor = color.blended(withFraction: fractionOfBlendedColor, of: .controlTextColor)

      borderColor?.setStroke()
      path.stroke()

      color.setFill()
      path.fill()

      return true
    }
    circleDict[color] = image
    return image
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    let subSystemNames = Logger.getSubsystems().map{ $0.rawValue }

    // The first menu item is "All"
    guard let menuItemAll = menu.item(at: 0) else { fatalError("Missing menu item for 'All' in Log window!") }
    menu.removeAllItems()
    menu.addItem(menuItemAll)

    for subSystemName in subSystemNames {
      menu.addItem(withTitle: subSystemName, action: nil, keyEquivalent: "")
    }
  }

  private func updatePredicate() {
    var subsystemPredicate = NSPredicate(value: true)
    if subsystemPopUpButton.indexOfSelectedItem != 0 {
      subsystemPredicate = NSPredicate(format: "subsystem = %@", subsystemPopUpButton.titleOfSelectedItem!)
    }
    let levelPredicate = NSPredicate(format: "level >= %d", levelPopUpButton.selectedTag())
    predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [subsystemPredicate, levelPredicate])
  }

  @IBAction func subsystemUpdated(_ sender: Any) {
    updatePredicate()
  }

  @IBAction func save(_ sender: Any) {
    Utility.quickSavePanel(title: "Log", filename: "iina.log", sheetWindow: window) { url in
      let logs = (self.logArrayController.content as! [Logger.Log]).map { $0.logString }.joined()
      try? logs.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  // MARK: - Menu actions

  @IBAction func copy(_ sender: Any) {
    menuCopy()
  }

  @objc private func menuCopy() {
    let string = (logArrayController.selectedObjects as! [Logger.Log]).map { $0.logString }.joined()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }

  // MARK: - Logs

  @MainActor
  @objc func syncLogs() {
    guard isWindowLoaded else { return }
    let newLogs = Logger.popNewestLinesForLogWindow()
    guard !newLogs.isEmpty else { return }
    var scroll = false
    let range = logTableView.rows(in: logTableView.visibleRect)
    if range.location + range.length >= logs.count {
      scroll = true
    }
    logs.append(contentsOf: newLogs)

    if scroll {
      // macOS couldn't calculate the frame size correctly when the row height is variable and
      // is not rendered. After the first scroll, all rows should be rendered, which makes the
      // second frame size correct. Scroll the second time to correctly scroll to the last row.
      logTableView.scroll(NSPoint(x: 0, y: logTableView.frame.size.height))
      logTableView.scroll(NSPoint(x: 0, y: logTableView.frame.size.height))
    }
  }

  @IBAction func showLogFileInFinder(_ sender: AnyObject) {
    NSWorkspace.shared.activateFileViewerSelecting([Logger.logFile])
  }

}

@objc(LogLevelTransformer) class LogLevelTransformer: ValueTransformer {
  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSImage.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let value = value as? Int else { return nil }
    return LogWindowController.indicatorIcon(withColor: colorMap[value]!)
  }
}

