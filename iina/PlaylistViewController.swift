//
//  PlaylistViewController.swift
//  iina
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let prefixMinLength = 7
fileprivate let displayNameMinLength = 12

fileprivate let isPlayingTextBlendFraction: CGFloat = 0.3
fileprivate let isPlayingPrefixTextBlendFraction: CGFloat = 0.4

fileprivate let playlistDraggableTypes: [NSPasteboard.PasteboardType] = [.nsFilenames, .nsURL, .iinaPlaylistItem, .string]

#if DEBUG
fileprivate let enablePrefetching = Preference.bool(for: .prefetchPlaylistVideoDuration) && !DebugConfig.disableLookaheadCaches
#else
fileprivate let enablePrefetching = Preference.bool(for: .prefetchPlaylistVideoDuration)
#endif


class PlaylistViewController: NSViewController, NSMenuDelegate, SidebarTabGroupViewController {

  override var nibName: NSNib.Name { .init("PlaylistViewController") }

  @IBOutlet weak var playlistTableBackgroundView: NSView!
  @IBOutlet weak var chapterTableBackgroundView: NSView!
  @IBOutlet weak var playlistTableView: EditableTableView!
  @IBOutlet weak var chapterTableView: EditableTableView!
  @IBOutlet weak var playlistBtn: NSButton!
  @IBOutlet weak var chaptersBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var tabHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var loopBtn: NSButton!
  @IBOutlet weak var shuffleBtn: NSButton!
  @IBOutlet weak var sortBtn: NSButton!
  @IBOutlet weak var totalDurationLabel: NSTextField!
  @IBOutlet var subPopover: NSPopover!
  @IBOutlet var addFileMenu: NSMenu!
  @IBOutlet weak var addBtn: NSButton!
  @IBOutlet weak var removeBtn: NSButton!

  fileprivate var isPlayingTextColor: NSColor = .textColor
  fileprivate var isPlayingPrefixTextColor: NSColor = .secondaryLabelColor

  private var isReloadingMeta = false

  unowned var player: PlayerCore!
  unowned var pwc: PlayerWindowController! {
    didSet {
      player = pwc.player
    }
  }

  struct PlaylistMetaWorkItem {
    let playlistIndex: Int
    let itemID: PlaybackID
    /// New mpv title to update
    let mpvTitle: String?

    func hasUpdate(for cachedMeta: MediaMeta) -> Bool {
      (itemID.isFile && !cachedMeta.triedFFmpeg) || (mpvTitle != nil && mpvTitle != cachedMeta.title)
    }
  }

  private var playlistDragDelegate: TableDragDelegate<PlaybackID>!
  private var notiHandler: NotificationHandler!

  private(set) var currentTab: Sidebar.Tab = .playlist

  /// Similar to the one in `QuickSettingViewController`.
  /// Since IBOutlet is `nil` when the view is not loaded at first time, use this variable to cache which tab it need to switch to when the
  /// view is ready. The value will be handled after loaded.
  private var pendingSwitchRequest: Sidebar.Tab?

  /// Currently displayed playlist rows. Should always be updated from `player.info.playlist`
  @MainActor var displayedPlaylist: [PlaybackID] = []

  // can't use main queue - it will block
  private var playlistTableReloadDebouncer = Debouncer(delay: 0.1, queue: PlayerCore.playlistMetaLoadDQ)
  /// Queue of playlist meta work to process on the `playlistMetaLoadDQ`.
  private var playlistItemCacheLoadQueue = LinkedList<PlaylistMetaWorkItem>()

  @Atomic private var playlistTotalDurationIsReady = false
  @Atomic private var playlistTotalDuration: Double? = nil
  private var lastNowPlayingIndex: Int = -1

  /// Cannot reliably scroll to current item until after the table finishes loading. So set this flag first.
  /// It will cause `scrollPlaylistToCurrentItem` to be called when done loading.
  var needsScrollToCurrentItem: Bool = true

  private var draggedRowInfo: (Int, IndexSet)? = nil

  private var downshift: CGFloat = 0
  private var tabHeight: CGFloat = 0

  override func viewDidLoad() {
    super.viewDidLoad()
    view.idString = "PlaylistView"

    playlistTableView.dataSource = self
    playlistTableView.menu?.delegate = self
    playlistTableView.editableDelegate = self
    playlistTableView.selectNextRowAfterDelete = player.playlistTableSelectNextRowAfterDelete
    playlistTableView.drawBackgroundForEmptyRows = true

    chapterTableView.dataSource = self
    chapterTableView.drawBackgroundForEmptyRows = true

    playlistDragDelegate = TableDragDelegate<PlaybackID>("Playlist", playlistTableView,
                                                         acceptableDraggedTypes: playlistDraggableTypes,
                                                         tableChangeNotificationName: player.playlistTableChangeNotificationName,
                                                         getFromPasteboardFunc: readPlaylistItemsFromPasteboard,
                                                         getAllCurentFunc: { self.displayedPlaylist },
                                                         moveFunc: { [self] rowIndexes, targetRowIndex in
      /// Drag & drop within `playlistTableView`
      player.movePlaylistRows(from: rowIndexes, to: targetRowIndex, .registerUndoRedo)

    }, insertFunc: { [self] desiredRowList, targetRowIndex in
      player.insertPlaylistRows(desiredRowList, at: targetRowIndex, .registerUndoRedo)
    },
                                                         removeFunc: { [self] rowIndexes in
      player.removePlaylistRows(rowIndexes, .registerUndoRedo)
    })

    for btn in [deleteBtn, loopBtn, shuffleBtn] {
      btn?.image?.isTemplate = true
      btn?.alternateImage?.isTemplate = true
    }

    if #unavailable(macOS 11.0) {
      sortBtn.image = NSImage.init(named: "triangle-down")
      sortBtn.image?.isTemplate = true
    }
    deleteBtn.toolTip = NSLocalizedString("mini_player.delete", comment: "delete")
    loopBtn.toolTip = NSLocalizedString("mini_player.loop", comment: "loop")
    shuffleBtn.toolTip = NSLocalizedString("mini_player.shuffle", comment: "shuffle")
    addBtn.toolTip = NSLocalizedString("mini_player.add", comment: "add")
    removeBtn.toolTip = NSLocalizedString("mini_player.remove", comment: "remove")
    sortBtn.toolTip = NSLocalizedString("mini_player.sort", comment: "sort")

    // Use contentView appearance (for now)
    updateTableColors(effectiveAppearance: player.pwc.window!.contentView!.effectiveAppearance)

    hideTotalDuration()
    reloadData(playlist: true, chapters: true, animate: false)

    // handle pending switch tab request
    if pendingSwitchRequest == nil {
      // Initial display: need to draw highlight for currentTab
      updateTabButtonSelection()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    updateVerticalConstraints()

    if !enablePrefetching {
      player.log.debug("Playlist: video duration prefetch is disabled")
    }

    // register for double click action
    let action = #selector(performDoubleAction(sender:))
    playlistTableView.doubleAction = action
    playlistTableView.target = self
    chapterTableView.doubleAction = action
    chapterTableView.target = self

    (subPopover.contentViewController as! SubPopoverViewController).player = player
    if let popoverView = subPopover.contentViewController?.view,
       popoverView.trackingAreas.isEmpty {
      popoverView.addTrackingArea(NSTrackingArea(rect: popoverView.bounds,
                                                 options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                 owner: pwc, userInfo: [PlayerWindowController.TrackingArea.key: PlayerWindowController.TrackingArea.playerWindow]))
    }

    notiHandler = NotificationHandler(player.log, [], [
      .default: [
        .init(.iinaPlaylistChanged, object: player, self.playlistDidChange),
        .init(.iinaFileHistoryDidUpdate, object: player, self.fileHistoryDidUpdate),
      ]
    ])
    notiHandler.addAllObservers()

    // Register this sidebar for dragged files, just so we can deny all drops onto the sidebar
    // not including the Playlist table. See note in QuickSettingsViewController.viewDidLoad().
    view.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])

    view.configureSubtreeForCoreAnimation()
    view.needsLayout = true
    player.log.verbose("PlaylistView viewDidLoad done")
  }

  deinit {
    notiHandler.removeAllObservers()
  }

  /// Execute in pipeline task to prevent hiccups if running other animations
  @MainActor
  func scrollPlaylistToCurrentItem() {
    guard isViewLoaded else {
      player.log.verbose("Playlist table not loaded yet, skipping scroll")
      return
    }
    guard let entryIndex = player.info.currentPlayback?.playlistPos else { return }
    guard let playlistTableView else { return }
    player.log.verbose("Scrolling playlist table to index \(entryIndex)")
    playlistTableView.scrollRowToVisible(entryIndex)
  }

  /// Use `animate: false` only for initial load, to avoid seeing a briefly empty table
  @MainActor
  func reloadData(playlist: Bool, chapters: Bool, animate: Bool = true) {
    guard player.isActive else { return }
    guard pwc.currentLayout.isMusicMode || pwc.isOpen(sidebarTabGroup: .playlist) else { return }

    if playlist {
      playlistTableReloadDebouncer.run { [self] in
        player.mpv.queue.async { [self] in
          reloadPlaylistTable(animate: animate)
        }
      }
    }

    if chapters {
      pwc.animationPipeline.submitInstantTask { [self] in
        player.log.verbose("Reloading chapters table for \(player.info.chapters.count) entries")
        chapterTableView.reloadData()
      }
    }
  }

  /// If `animate` is false, does a full reload instantly.
  private func reloadPlaylistTable(animate: Bool) {
    // Be sure to access playlist data only from within mpv queue
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    let playlistOld = displayedPlaylist
    let playlistNew = player.info.playlist
    if let nowPlayingIndex = player.info.currentPlayback?.playlistPos,
       nowPlayingIndex >= 0, nowPlayingIndex < playlistNew.count {
      // Update this prior to reload so the highlight is drawn correctly at first draw:
      lastNowPlayingIndex = nowPlayingIndex
    }

    let sw = Utility.Stopwatch()

    let doAfterReload: @MainActor () -> Void = { [self] in
      refreshNowPlayingIndex()
      updateCachesForAllItems()
      removeBtn.isEnabled = !playlistTableView.selectedRowIndexes.isEmpty
      if needsScrollToCurrentItem {
        needsScrollToCurrentItem = false
        scrollPlaylistToCurrentItem()
      }
      player.log.verbose("Done with playlist table reload in \(sw.secElapsedString)")
    }

    if animate {
      let tableUIChange = TableUIChangeBuilder.shared.buildDiff(oldRows: playlistOld,
                                                                newRows: playlistNew, completionHandler: { [self] _ in
        displayedPlaylist = playlistNew
        pwc.animationPipeline.submitInstantTask {
          doAfterReload()
        }
      })
      player.log.verbose("Updating playlist table via diff")
      playlistTableView.post(tableUIChange)
    } else {
      pwc.animationPipeline.submitInstantTask { [self] in
        player.log.trace("Updating playlist table via reloadData")
        playlistTableView.reloadData()
        player.log.verbose("Updated playlist table via reloadData: \(playlistTableView.numberOfRows) rows")
        doAfterReload()
      }
    }
  }

  @MainActor
  func updateTableColors(effectiveAppearance: NSAppearance) {
    player.log.verbose("Playlist sidebar: updating table colors: dark=\(effectiveAppearance.isDark.yn)")
    // Need to use this closure for dark/light mode toggling to get picked up while running (not sure why...)
    effectiveAppearance.performAsCurrentDrawingAppearance {
      isPlayingTextColor = NSColor.controlAccentColor.blended(withFraction: isPlayingTextBlendFraction, of: .textColor)!
      isPlayingPrefixTextColor = NSColor.controlAccentColor.blended(withFraction: isPlayingPrefixTextBlendFraction, of: .textColor)!

      // Need a dedicated view behind each table to use for background color.
      // NSTableView & its component views don't support translucent background color.
      // Also note: CGColor does not support dark mode, so the view layer needs to be updated
      // explicitly whenever the appearance changes.
      let tableBackgroundColor = NSColor.sidebarTableBackground.cgColor
      playlistTableBackgroundView.wantsLayer = true
      playlistTableBackgroundView.layer?.backgroundColor = tableBackgroundColor
    }
    reloadData(playlist: true, chapters: true, animate: false)
  }

  func setVerticalConstraints(downshift: CGFloat, tabHeight: CGFloat) {
    if (self.downshift != downshift) || (self.tabHeight != tabHeight) {
      self.downshift = downshift
      self.tabHeight = tabHeight
      updateVerticalConstraints()
    }
  }

  private func updateVerticalConstraints() {
    // may not be available until after load
    player.log.verbose("Playlist: updating downshift=\(downshift), tabHeight=\(tabHeight)")
    self.buttonTopConstraint?.animateToConstant(downshift)
    self.tabHeightConstraint?.animateToConstant(tabHeight)
    view.needsLayout = true
  }

  // MARK: - Total Duration

  @MainActor
  private func showTotalDuration() {
    guard let playlistTotalDuration else { return }
    totalDurationLabel.isHidden = false
    let totalDurationString = VideoTime(playlistTotalDuration).stringRepresentation

    if playlistTableView.numberOfSelectedRows > 0 {
      let playlist: [PlaybackID] = displayedPlaylist
      let urls = playlistTableView.selectedRowIndexes.compactMap{ $0 < playlist.count ? playlist[$0].url : nil }
      let selectedDuration = MediaMetaCache.shared.calculateTotalDuration(urls)

      totalDurationLabel.stringValue = String(format: NSLocalizedString("playlist.total_length_with_selected", comment: "%@ of %@ selected"),
                                              VideoTime(selectedDuration).stringRepresentation,
                                              totalDurationString)
    } else {
      totalDurationLabel.stringValue = String(format: NSLocalizedString("playlist.total_length", comment: "%@ in total"),
                                              totalDurationString)
    }
  }

  @MainActor
  private func hideTotalDuration() {
    totalDurationLabel.isHidden = true
  }

  /// Only if `playlistTotalDurationIsReady`
  private func refreshTotalDuration() {
    assert(DispatchQueue.isExecutingIn(PlayerCore.playlistMetaLoadDQ))
    guard playlistTotalDurationIsReady else { return }

    let playlist: [PlaybackID] = displayedPlaylist
    let urls = playlist.map { $0.url }
    let totalDuration = MediaMetaCache.shared.calculateTotalDuration(urls)

    player.log.trace("Playlist: recalculated total duration: \(totalDuration)")
    pwc.animationPipeline.submitInstantTask { [self] in
      playlistTotalDuration = totalDuration
      showTotalDuration()
    }
  }

  // - Loop Button

  func updateLoopBtnStatus() {
    player.mpv.queue.async { [self] in
      guard player.isActive else { return }
      let loopMode = player.getLoopMode()
      pwc.animationPipeline.submitInstantTask { [self] in
        guard isViewLoaded else { return }
        switch loopMode {
        case .off:  loopBtn.state = .off
        case .file: loopBtn.state = .on
        default:    loopBtn.state = .mixed
        }
        loopBtn.alternateImage = NSImage.init(named: loopBtn.state == .on ? "loop_file" : "loop_dark")
      }
    }
  }

  // MARK: - Tab switching

  /// Switch tab (call from other objects)
  @MainActor
  func pleaseSwitchToTab(_ tab: Sidebar.Tab) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  /// Switch tab (for internal call)
  @MainActor
  private func switchToTab(_ tab: Sidebar.Tab) {
    guard tab.group == .playlist else {
      player.log.error("PlaylistViewController: cannot switch to tab: \(tab)")
      return
    }
    assert(pwc.isInMiniPlayer || pwc.isOpen(sidebarTabGroup: .playlist),
           "switchToTab should not be called when playlist TabGroup is not shown or not in music mode")
    guard currentTab != tab else { return }

    currentTab = tab
    updateTabButtonSelection()
    pwc.didChangeTab(to: tab)

    let buttonTag: Int
    switch tab {
    case .playlist:
      needsScrollToCurrentItem = true
      reloadData(playlist: true, chapters: false)
      updateLoopBtnStatus()
      buttonTag = 0
    case .chapters:
      reloadData(playlist: false, chapters: true)
      buttonTag = 1
    default:
      Logger.fatal("PlaylistViewController: invalid tab requested for switching: \(tab)")
    }
    tabView.selectTabViewItem(at: buttonTag)
  }

  // Updates display of all tabs buttons to indicate that the given tab is active and the rest are not
  @MainActor private func updateTabButtonSelection() {
    updateTabActiveStatus(for: playlistBtn, isActive: currentTab == .playlist)
    updateTabActiveStatus(for: chaptersBtn, isActive: currentTab == .chapters)
  }

  // MARK: - IBActions

  @IBAction func addToPlaylistBtnAction(_ sender: NSButton) {
    addFileMenu.popUp(positioning: nil, at: .zero, in: sender)
  }

  @IBAction func removeBtnAction(_ sender: NSButton) {
    player.removePlaylistRows(playlistTableView.selectedRowIndexes, .registerUndoRedo)
  }

  @IBAction func addFileAction(_ sender: AnyObject) {
    Utility.quickMultipleOpenPanel(title: "Add to playlist", canChooseDir: true) { [self] urls in
      let rows = urls.map{ PlaybackID($0) }
      player.insertPlaylistRows(rows, at: displayedPlaylist.count, .registerUndoRedo)
    }
  }

  @IBAction func addURLAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_url") { [self] url in
      if Regex.url.matches(url) {
        player.appendToPlaylist(url)
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @IBAction func clearPlaylistBtnAction(_ sender: AnyObject) {
    player.clearPlaylist()
    player.sendOSD(.clearPlaylist)
  }

  @IBAction func playlistBtnAction(_ sender: AnyObject) {
    switchToTab(.playlist)
  }

  @IBAction func chaptersBtnAction(_ sender: AnyObject) {
    switchToTab(.chapters)
  }

  @IBAction func loopBtnAction(_ sender: NSButton) {
    player.nextLoopMode()
  }

  @IBAction func shuffleBtnAction(_ sender: AnyObject) {
    player.toggleShuffle()
  }

  @objc func performDoubleAction(sender: AnyObject) {
    guard let tv = sender as? NSTableView, tv.numberOfSelectedRows > 0 else { return }
    if tv == playlistTableView {
      player.playFileInPlaylist(tv.selectedRow)
    } else {
      let index = tv.selectedRow
      player.playChapter(index)
    }
    tv.deselectAll(self)
    tv.reloadData()
  }

  @IBAction func prefixBtnAction(_ sender: PlaylistPrefixButton) {
    sender.isFolded = !sender.isFolded
  }

  @IBAction func subBtnAction(_ sender: NSButton) {
    let row = playlistTableView.row(for: sender)
    guard let vc = subPopover.contentViewController as? SubPopoverViewController else { return }
    let playlist = displayedPlaylist
    guard row < playlist.count else { return }
    vc.filePath = playlist[row].url.path
    vc.tableView.reloadData()
    subPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  @IBAction func sortingBtnAction(_ sender: NSButton) {
    let menu = NSMenu()
    if #available(macOS 14.0, *) {
      menu.addItem(.sectionHeader(title: NSLocalizedString("playlist.sorting.header", comment: "Sorting")))
    }
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.filename_ascending", comment: "Filename Ascending"),
                 action: #selector(sortPathAscending), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.filename_descending", comment: "Filename Descending"),
                 action: #selector(sortPathDesecnding), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.path_ascending", comment: "File Path Ascending"),
                 action: #selector(sortPathAscending), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("playlist.sorting.path_descending", comment: "File Path Descending"),
                 action: #selector(sortPathDesecnding), keyEquivalent: "")
    NSMenu.popUpContextMenu(menu, with: NSApplication.shared.currentEvent!, for: sender)
  }

  @objc func sortNameAscending() { sortName(ascending: true) }
  @objc func sortNameDesecnding() { sortName(ascending: false) }
  @objc func sortPathAscending() { sortPath(ascending: true) }
  @objc func sortPathDesecnding() { sortPath(ascending: false) }

  private func sortName(ascending: Bool) {
    var playlist = player.info.playlist
    playlist.sort(by: {
      let results = $0.displayName < $1.displayName
      return ascending ? results : !results
    })
    player.playlistReorder(newPlaylist: playlist)
  }

  private func sortPath(ascending: Bool) {
    var playlist = player.info.playlist
    playlist.sort(by: {
      let results = $0.path < $1.path
      return ascending ? results : !results
    })
    player.playlistReorder(newPlaylist: playlist)
  }

  // MARK: - Playlist Table: Drag and Drop

  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return playlistDragDelegate.draggingSession(session, sourceOperationMaskFor: context)
  }

  /// Drag start: set session variables.
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    playlistDragDelegate.tableView(tableView, draggingSession: session, willBeginAt: screenPoint, forRowIndexes: rowIndexes)
  }

  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    playlistDragDelegate.tableView(tableView, draggingSession: session, endedAt: screenPoint, operation: operation)
  }

  @objc func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    return playlistDragDelegate.tableView(tableView, validateDrop: info, proposedRow: rowIndex, proposedDropOperation: dropOperation)
    //    return player.acceptFromPasteboard(info, isPlaylist: true)  // FIXME: reconcile with this old code
  }

  /// Accept the drop and execute changes, or reject drop.
  ///
  /// Remember that we can expect the following (see notes in `tableView(_, validateDrop, …)`)
  /// 1. `0 <= targetRowIndex <= rowCount`
  /// 2. `dropOperation = .above`.
  @objc func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo, row targetRowIndex: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
    return playlistDragDelegate.tableView(tableView, acceptDrop: info, row: targetRowIndex, dropOperation: dropOperation)
  }

  // MARK: - Playlist Table: Pasteboard CRUD

  private func copyPlaylistRowsToPasteboard(_ rowIndexes: IndexSet, to pboard: NSPasteboard) {
    player.log.verbose("Copying playlist indexes to pasteboard: \(rowIndexes.toArray())")
    do {
      let indexesData = try NSKeyedArchiver.archivedData(withRootObject: rowIndexes, requiringSecureCoding: true)
      let playlist = displayedPlaylist
      pboard.declareTypes([.iinaPlaylistItem, .nsFilenames, .nsURL], owner: playlistTableView)
      pboard.setData(indexesData, forType: .iinaPlaylistItem)
      let filePaths = rowIndexes.compactMap{ $0 < playlist.count ? playlist[$0].filePath : nil }
      pboard.setPropertyList(filePaths, forType: .nsFilenames)
      let paths = rowIndexes.compactMap{ $0 < playlist.count ? playlist[$0].path : nil }
      pboard.setPropertyList(paths, forType: .nsURL)

    } catch {
      // Internal error, archivedData should not fail.
      player.log.error("Failed to copy from playlist to pasteboard: \(error)")
    }
  }

  private func readPlaylistItemsFromPasteboard(_ pboard: NSPasteboard) -> [PlaybackID] {
    if let filenamePaths = pboard.propertyList(forType: .nsFilenames) as? [String] {
      let fileURLs: [URL] = filenamePaths.map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0)!
      }
      let resolvedURLs = Utility.resolveURLs(fileURLs)
      let ids = resolvedURLs.compactMap{ PlaybackID($0) }
      return player.getPlayableFiles(in: ids)
    } else if let urlPaths = pboard.propertyList(forType: .nsURL) as? [String] {
      return urlPaths.compactMap{ PlaybackID(path: $0) }
    } else if let droppedString = pboard.string(forType: .string), Regex.url.matches(droppedString) {
      return [droppedString].compactMap{ PlaybackID(URL(string: $0)) }
    } else {
      return []
    }
  }

  @discardableResult
  private func pasteFromPasteboard(from pboard: NSPasteboard) -> Bool {
    let playlistItems = readPlaylistItemsFromPasteboard(pboard)
    player.log.verbose("User pasted \(playlistItems.count) items from pasteboard into playlist")

    guard !playlistItems.isEmpty else {
      return false
    }
    let insertIndex: Int
    if let lastSelectedRowIndex = playlistTableView.selectedRowIndexes.last {
      insertIndex = lastSelectedRowIndex + 1
    } else {
      insertIndex = playlistTableView.numberOfRows
    }
    player.insertPlaylistRows(playlistItems, at: insertIndex, .registerUndoRedo)
    return true
  }

}

// MARK: - EditableTableViewDelegate

extension PlaylistViewController: EditableTableViewDelegate {
  var parentTableView: EditableTableView! { playlistTableView }

  // Allows for sidebar resize to happen from inside the table, by giving it higher priority than row drag & drop.
  // If this returns false, table will proceed to process normally
  func handleMouseDown(with event: NSEvent) -> Bool {
    return pwc.startResizingSidebar(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    if let pwc = pwc, pwc.currentDragObject == view,
       let sidebar = pwc.getConfiguredSidebar(forTabGroup: .playlist) {

      // Do not animate. It will cause lag while dragging
      IINAAnimation.disableAnimation {
        pwc.continueResizingSidebar(sidebar.locationID, with: event)
      }
      return
    }

    super.mouseDragged(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    if let pwc = pwc, pwc.currentDragObject == view,
       let sidebar = pwc.getConfiguredSidebar(forTabGroup: .playlist) {
      pwc.finishResizingSidebar(sidebar.locationID, with: event)
      pwc.currentDragObject = nil
      return
    }
    super.mouseUp(with: event)
  }

  // MARK: - Edit Menu Support

  func isCutEnabled() -> Bool {
    return hasSelectionInPlaylistTable()
  }

  func isCopyEnabled() -> Bool {
    return hasSelectionInPlaylistTable()
  }

  func isPasteEnabled() -> Bool {
    (currentTab == .playlist) && (NSPasteboard.general.types?.contains(.nsFilenames) ?? false)
  }

  func isDeleteEnabled() -> Bool {
    return hasSelectionInPlaylistTable()
  }

  func isSelectAllEnabled() -> Bool {
    (currentTab == .playlist) && (playlistTableView.numberOfRows > 0)
  }

  func doEditMenuCopy() {
    copyPlaylistRowsToPasteboard(playlistTableView.selectedRowIndexes, to: .general)
  }

  func doEditMenuCut() {
    doEditMenuCopy()
    doEditMenuDelete()
  }

  func doEditMenuPaste() {
    pasteFromPasteboard(from: .general)
  }

  func doEditMenuDelete() {
    player.removePlaylistRows(playlistTableView.selectedRowIndexes, .registerUndoRedo)
  }

  private func hasSelectionInPlaylistTable() -> Bool {
    (currentTab == .playlist) && !playlistTableView.selectedRowIndexes.isEmpty
  }
}

// MARK: - NSTableViewDataSource

extension PlaylistViewController: NSTableViewDataSource {

  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    if tableView == playlistTableView {
      copyPlaylistRowsToPasteboard(rowIndexes, to: pboard)
      return true
    }
    return false
  }


  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == playlistTableView {
      let playlist = displayedPlaylist
      return playlist.count
    } else if tableView == chapterTableView {
      return player.info.chapters.count
    } else {
      return 0
    }
  }

}

  // MARK: - NSTableViewDelegate

extension PlaylistViewController: NSTableViewDelegate {

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tv = notification.object as! NSTableView
    if tv == playlistTableView {
      showTotalDuration()
      totalDurationLabel.needsDisplay = true

      removeBtn.isEnabled = !playlistTableView.selectedRowIndexes.isEmpty
      return
    }
  }

  func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
    /// The background color for a `NSTableRowView` will default to the parent's background color, which results in an
    /// unwanted additive effect for translucent backgrounds. Just make each row transparent.
    rowView.backgroundColor = .clear
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let v = tableView.makeView(withIdentifier: identifier, owner: self) as! NSTableCellView

    if tableView == playlistTableView {  // Playlist table
                                         // use cached value
      let isPlaying = self.lastNowPlayingIndex == row
      if isPlaying {
        Logger.log("IS PLAYING")
      }

      switch identifier {
      case .isChosen:
        let pointer = view.userInterfaceLayoutDirection == .rightToLeft ? Constants.String.blackLeftPointingTriangle : Constants.String.blackRightPointingTriangle
        // ▶︎ Is Playing icon
        let text = isPlaying ? pointer : ""
        v.textField?.setFormattedText(stringValue: text, textColor: isPlayingTextColor)
      case .trackName:
        let cellView = v as! PlaylistTrackCellView
        updateCellForPlaylistTrackNameColumn(cellView, rowIndex: row, isPlaying: isPlaying)
      default:
        Logger.fatal("Unknown identifier in Playlist table: \(identifier)")
      }
      return v

    } else if tableView == chapterTableView {  // Chapters table

      let chapters = player.info.chapters
      guard row < chapters.count else { return nil }
      let chapter = chapters[row]

      // next chapter time
      let nextChapterTime = chapters[at: row+1]?.startTime ?? Double.infinity
      let isCurrentChapter = player.info.chapter == row
      let textColor = isCurrentChapter ? isPlayingTextColor : .controlTextColor

      switch identifier {
      case .isChosen:
        // left column
        let pointerGlyph: String
        if isCurrentChapter {
          pointerGlyph = view.userInterfaceLayoutDirection == .rightToLeft ?
          Constants.String.blackLeftPointingTriangle :  Constants.String.blackRightPointingTriangle
        } else {
          pointerGlyph = ""
        }
        v.setTitle(pointerGlyph, textColor: textColor)
      case .trackName:
        // right column
        let titleString = chapter.title.isEmpty ? "Chapter \(row)" : chapter.title
        v.setTitle(titleString, textColor: textColor)
        let cellView = v as! ChapterTableCellView
        let durationText = "\(VideoTime.string(from: chapter.startTime)) → \(VideoTime.string(from: nextChapterTime))"
        cellView.durationTextField.setText(durationText, textColor: textColor)
      default:
        Logger.fatal("Unknown identifier in Chapters table: \(identifier)")
      }
      return v
    }

    return nil
  }

  private var wantsPlaylistTitleDisplayed: Bool {
    if Preference.bool(for: .playlistShowMetadata) {
      let onlyInMusicMode = Preference.bool(for: .playlistShowMetadataInMusicMode)
      if onlyInMusicMode {
        return player.isInMiniPlayer
      } else {
        return true
      }
    }
    return false
  }

  /// Rebuilds playlist table's `Track Name` column cell
  private func updateCellForPlaylistTrackNameColumn(_ cellView: PlaylistTrackCellView, rowIndex: Int, isPlaying: Bool) {
    guard let cachedMeta = getOrCreateMeta(forRowIndex: rowIndex) else {
      player.log.error("No playlist item found for rowIndex \(rowIndex). Skipping cell update")
      return
    }

    let wantsTitleDisplayed = wantsPlaylistTitleDisplayed
    let displayName = (wantsTitleDisplayed ? cachedMeta.title : nil) ?? cachedMeta.id.displayName
    let artist = wantsTitleDisplayed ? cachedMeta.artist : nil

    player.log.trace("Building row \(rowIndex) of playlist: \(displayName.quoted)")

    let textColor = isPlaying ? isPlayingTextColor : .controlTextColor
    let prefixTextColor = isPlaying ? isPlayingPrefixTextColor : .secondaryLabelColor

    // Title, artist, prefix
    if Preference.bool(for: .shortenFileGroupsInPlaylist),
       let prefix = player.info.currentVideosInfo.first(where: { $0.url == cachedMeta.id.url })?.prefix,
       !prefix.isEmpty,
       prefix.count <= displayName.count,  // check whether prefix length > displayName length
       prefix.count >= prefixMinLength,
       displayName.count > displayNameMinLength {
      cellView.setPrefix(prefix, textColor: prefixTextColor)
      cellView.setAdditionalInfo(nil)
      cellView.setTitle(String(displayName[displayName.index(displayName.startIndex, offsetBy: prefix.count)...]), textColor: textColor)
    } else {
      cellView.setPrefix(nil, textColor: prefixTextColor)
      cellView.setAdditionalInfo(artist, textColor: textColor)
      cellView.setTitle(displayName, textColor: textColor)
    }

    // playback progress and duration
    cellView.durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    if let duration = cachedMeta.duration {
      let durationString = VideoTime(duration).stringRepresentation
      let durationTextColor = isPlaying ? isPlayingTextColor : .secondaryLabelColor
      cellView.durationLabel.setFormattedText(stringValue: durationString, textColor: durationTextColor)
    } else {
      cellView.durationLabel.stringValue = ""
    }
    if let progress = cachedMeta.progress, let duration = cachedMeta.duration {
      cellView.playbackProgressView.layerContentsRedrawPolicy = .duringViewResize
      cellView.playbackProgressView.percentage = progress / duration
      cellView.playbackProgressView.isHidden = false
    } else {
      cellView.playbackProgressView.isHidden = true
    }

    // sub button
    if !player.info.isMatchingSubtitles,
       let matchedSubs = player.info.getMatchedSubs(cachedMeta.id.path), !matchedSubs.isEmpty {
      cellView.setDisplaySubButton(true)
    } else {
      cellView.setDisplaySubButton(false)
    }
    // not sure why this line exists, but let's keep it for now
    cellView.subBtn.image?.isTemplate = true
  }

  // MARK: - Playlist Table: Model Data Management

  fileprivate func playlistDidChange(_ noti: Notification) {
    guard player.playlistShown else {
      player.log.verbose("Got iinaPlaylistChanged, but playlist is not visible. Ignoring")
      return
    }
    player.log.verbose("Got iinaPlaylistChanged (enablePrefetch=\(enablePrefetching.yn)); reloading playlist table…")

    playlistTotalDuration = nil
    playlistTotalDurationIsReady = false
    hideTotalDuration()

    reloadData(playlist: true, chapters: false)
  }

  fileprivate func fileHistoryDidUpdate(_ noti: Notification) {
    guard !AppDelegate.shared.isTerminating else { return }
    guard let url = noti.userInfo?["url"] as? URL else {
      player.log.error("Cannot update file history: no url found in userInfo!")
      return
    }
    guard url.isFileURL else { return }
    let playlist = displayedPlaylist
    for (rowIndex, item) in playlist.enumerated() {
      if item.url == url {
        player.log.trace("Got iinaFileHistoryDidUpdate: reloading playlist row \(rowIndex)")
        reloadPlaylistRow(rowIndex)
      }
    }
  }

  private func getOrCreateMeta(forRowIndex rowIndex: Int) -> MediaMeta? {
    guard rowIndex >= 0 else { return nil }
    let playlistItems = displayedPlaylist
    player.log.trace("Playlist: reloading cache for row \(rowIndex)/\(playlistItems.count)")
    guard rowIndex < playlistItems.count else { return nil }
    let playlistItem = playlistItems[rowIndex]
    return MediaMetaCache.shared.getOrAddCachedMeta(for: playlistItem)
  }

  /// [Re-]loads & redraws the item at the given index as quickly as feasible
  @MainActor private func loadCachedItem(forRowIndex rowIndex: Int) {
    guard rowIndex >= 0 else { return }
    let playlistItems = displayedPlaylist
    player.log.trace("Playlist: reloading cache for row \(rowIndex)/\(playlistItems.count)")
    guard rowIndex < playlistItems.count else { return }
    let playlistItem = playlistItems[rowIndex]

    // Kick this off, but return the existing (possibly stale) data below for efficiency
    player.mpv.queue.async { [self] in
      guard player.isActive else { return }
      // Get updated title from mpv
      let mpvTitle = player.mpv.getString(MPVProperty.playlistNTitle(rowIndex))

      PlayerCore.playlistMetaLoadDQ.async { [self] in
        // Get watch-later form file system; get other meta from ffmpeg:
        let cachedMeta = MediaMetaCache.shared.updateCachedMeta(playlistItem, mpvTitle: mpvTitle,
                                                                pullFromWatchLater: true, pullFromFfmpeg: true)
        // Now update the total length if needed (but only if it's already done calculating):
        if cachedMeta.duration != nil {
          // if FFmpeg got the duration successfully
          refreshTotalDuration()
        }

        pwc.animationPipeline.submitInstantTask{ [self] in
          /// This should trigger a call to `updateCellForPlaylistTrackNameColumn` to rebuild the row
          reloadPlaylistRow(rowIndex)
        }
      }

    }
  }

  private func updateCachesForAllItems() {
    guard enablePrefetching else { return }

    let playlistItems = displayedPlaylist
    player.log.verbose("[Playlist] Updating caches for \(playlistItems.count) rows…")

    player.mpv.queue.async { [self] in
      guard player.isActive else { return }
      var titles: [String?] = []

      for rowIndex in 0..<playlistItems.count {
        // Get updated title from mpv
        let mpvTitle = player.mpv.getString(MPVProperty.playlistNTitle(rowIndex))
        titles.append(mpvTitle) // may be nil
      }

      PlayerCore.playlistMetaLoadDQ.async { [self] in
        // Clear previous items & replace with new list
        playlistItemCacheLoadQueue = []
        for (playlistIndex, (itemID, mpvTitle)) in (zip(playlistItems, titles)).enumerated() {
          let workItem = PlaylistMetaWorkItem(playlistIndex: playlistIndex, itemID: itemID, mpvTitle: mpvTitle)
          playlistItemCacheLoadQueue.append(workItem)
        }

        if !isReloadingMeta {
          isReloadingMeta = true
          continueReloadingCachedItems()
        }
      }
    }
  }

  /// Each call of this function processes the next item in `playlistItemCacheLoadQueue` using
  /// `PlayerCore.playlistMetaLoadDQ`.
  ///
  /// - Uses `isReloadingMeta` flag to prevent duplicate processing.
  /// - By Waiting until processing is complete for the current item until enqueuing work for the next
  ///   item, we avoid tying up `PlayerCore.playlistMetaLoadDQ` for use with other work, notably for
  ///   `loadCachedItem`, which needs priority to ensure that the "Now Playing" item is correctly drawn.
  fileprivate func continueReloadingCachedItems() {
    PlayerCore.playlistMetaLoadDQ.async { [self] in
      guard let workItem = playlistItemCacheLoadQueue.removeHead() else {
        // Finally, append a task to recalculate the total length. Do not show it until it is done!
        player.log.verbose("[Playlist] Finished cache updates")
        isReloadingMeta = false
        playlistTotalDurationIsReady = true
        refreshTotalDuration()
        return
      } 

      let existingCachedMeta = MediaMetaCache.shared.getOrAddCachedMeta(for: workItem.itemID)
      if workItem.hasUpdate(for: existingCachedMeta) {
        // Get watch-later form file system; get other meta from ffmpeg:
        MediaMetaCache.shared.updateCachedMeta(workItem.itemID, mpvTitle: workItem.mpvTitle,
                                               pullFromWatchLater: true, pullFromFfmpeg: true)
        // Refresh each row as it gets updated. May take a while to refresh all
        pwc.animationPipeline.submitInstantTask{ [self] in
          /// This should trigger a call to `updateCellForPlaylistTrackNameColumn` to rebuild the row
          reloadPlaylistRow(workItem.playlistIndex)
        }
      }

      continueReloadingCachedItems()
    }
  }

  func clearBackgroundQueue() {
    PlayerCore.playlistMetaLoadDQ.async { [self] in
      player.log.verbose("Clearing background queue work (was: \(playlistItemCacheLoadQueue.count) items)")
      playlistItemCacheLoadQueue = []
      isReloadingMeta = false
      playlistTotalDurationIsReady = false
    }
  }

  // Updates index of playing item. Don't need to reload whole playlist
  @MainActor
  func refreshNowPlayingIndex(setNewIndexTo newNowPlayingIndex: Int? = nil,
                              thenScrollToVisible: Bool = false) {
    guard isViewLoaded else { return }
    guard !view.isHidden else { return }

    let oldNowPlayingIndex = lastNowPlayingIndex
    let newNowPlayingIndex = newNowPlayingIndex ?? player.info.currentPlayback?.playlistPos ?? oldNowPlayingIndex

    player.log.verbose("Updating nowPlayingIndex: \(oldNowPlayingIndex) → \(newNowPlayingIndex)")
    lastNowPlayingIndex = newNowPlayingIndex

    // ... also make sure the old "now playing" row is redrawn so it loses its status
    loadCachedItem(forRowIndex: oldNowPlayingIndex)
    // If "now playing" row changed, make sure the new "now playing" row is redrawn to show its new status...
    loadCachedItem(forRowIndex: newNowPlayingIndex)
    // The calls to loadCachedItem should refresh the given indexes, but will go through multiple queues
    // to do so and may be delayed by a minute or more. We need to update the nowPlaying status ASAP,
    // so just add extra redraws right away:
    reloadPlaylistRow(oldNowPlayingIndex)
    reloadPlaylistRow(newNowPlayingIndex)

    if thenScrollToVisible {
      playlistTableView.scrollRowToVisible(newNowPlayingIndex)
    }
  }

  @MainActor
  func reloadPlaylistRow(_ rowIndex: Int) {
    reloadPlaylistRows(IndexSet(integer: rowIndex))
  }

  /// Reload all rows if not specified
  @MainActor
  func reloadPlaylistRows(_ rows: IndexSet) {
    playlistTableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0...1))
  }

  @MainActor
  func reloadAllPlaylistRows(_ rows: IndexSet? = nil) {
    playlistTableView.reloadExistingRows(reselectRowsAfter: true)
  }

}
