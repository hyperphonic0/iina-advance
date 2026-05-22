//
//  Playlist_ContextMenu.swift
//  iina
//
//  Created by Matt Svoboda on 2026-01-26.
//  Copyright © 2026 lhc. All rights reserved.
//

extension PlaylistViewController {
  // MARK: - Context menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    buildContextMenu(menu)
  }

  private func getTargetRowsForContextMenu() -> IndexSet {
    let selectedRows = playlistTableView.selectedRowIndexes
    let clickedRow = playlistTableView.clickedRow
    guard clickedRow != -1 else {
      return IndexSet()
    }

    if selectedRows.contains(clickedRow) {
      return selectedRows
    } else {
      return IndexSet(integer: clickedRow)
    }
  }

  @IBAction func contextMenuPlayNext(_ sender: ContextMenuItem) {
    player.playNextInPlaylist(sender.targetRows)
    playlistTableView.deselectAll(nil)
  }

  @IBAction func contextMenuPlayInNewWindow(_ sender: ContextMenuItem) {
    let playlistItems = displayedPlaylist

    let urlList: [URL] = sender.targetRows.compactMap{ playlistRowIndex in
      guard playlistRowIndex < playlistItems.count else { return nil }
      return playlistItems[playlistRowIndex].url
    }
    PlayerManager.shared.getIdleOrCreateNew().openURLs(urlList)
  }

  @IBAction func contextMenuRemove(_ sender: ContextMenuItem) {
    player.log.verbose("User chose to remove rows \(sender.targetRows.map{$0}) from playlist")
    player.removePlaylistRows(sender.targetRows, .registerUndoRedo)
  }

  @IBAction func contextMenuDeleteFile(_ sender: ContextMenuItem) {
    player.log.debug("User chose to delete files from playlist at indexes: \(sender.targetRows.map{$0})")

    let playlistItems = displayedPlaylist
    var successes = IndexSet()
    for index in sender.targetRows {
      guard index < playlistItems.count else { continue }
      guard !playlistItems[index].isNetworkResource else { continue }
      let url = playlistItems[index].url
      do {
        player.log.debug("Trashing row \(index): \(url.standardizedFileURL)")
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        successes.insert(index)
      } catch let error {
        Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
      }
    }
    if !successes.isEmpty {
      player.removePlaylistRows(successes, .clearUndoStack)
    }
  }

  /// Gets the list of URLs for the files in the playlist (if any). Any URLs for non-files (i.e. network streams) will be omitted from the list.
  /// For each file: if bookmark data is found, tries to resolve the URL from it. Otherwise just use its static URL.
  private func getFileURLs(fromPlaylistRows rowIndexes: IndexSet) -> [URL] {
    var urls: [URL] = []
    let playlistItems = displayedPlaylist
    for index in rowIndexes {
      guard index < playlistItems.count else { continue }
      if let fileURL = playlistItems[index].resolveFileURL(player.log) {
        urls.append(fileURL)
      }
    }

    return urls
  }

  @IBAction func contextMenuShowInFinder(_ sender: ContextMenuItem) {
    let urls: [URL] = getFileURLs(fromPlaylistRows: sender.targetRows)
    guard !urls.isEmpty else {
      player.log.error("Show in Finder failed: found no files in \(sender.targetRows.count) provided rows!")
      return
    }
    playlistTableView.deselectAll(nil)
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func contextMenuAddSubtitle(_ sender: ContextMenuItem) {
    guard let index = sender.targetRows.first else { return }
    let playlistItems = displayedPlaylist
    guard index < playlistItems.count else { return }
    let filename = playlistItems[index].path
    let fileURL = playlistItems[index].url.deletingLastPathComponent()
    Utility.quickMultipleOpenPanel(title: NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File"), dir: fileURL, canChooseDir: true) { subURLs in
      for subURL in subURLs {
        guard Utility.supportedFileExt[.sub]!.contains(subURL.pathExtension.lowercased()) else { return }
        self.player.info.$matchedSubs.withLock { $0[filename, default: []].append(subURL) }
      }
      self.reloadPlaylistRows(sender.targetRows)
    }
  }

  @IBAction func contextMenuWrongSubtitle(_ sender: ContextMenuItem) {
    let playlistItems = displayedPlaylist
    for index in sender.targetRows {
      guard index < playlistItems.count else { continue }
      let filename = playlistItems[index].path
      player.info.$matchedSubs.withLock { $0[filename]?.removeAll() }
      self.reloadPlaylistRows(sender.targetRows)
    }
  }

  @IBAction func contextOpenInBrowser(_ sender: ContextMenuItem) {
    let playlistItems = displayedPlaylist
    for i in sender.targetRows {
      guard i < playlistItems.count else { continue }

      let info = playlistItems[i]
      if info.isNetworkResource {
        NSWorkspace.shared.open(info.url)
      }
    }
  }

  @IBAction func contextCopyURL(_ sender: ContextMenuItem) {
    let playlistItems = displayedPlaylist
    let urls = sender.targetRows.compactMap { i -> String? in
      guard i < playlistItems.count else { return nil }
      let item = playlistItems[i]
      return item.networkPath
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([urls.joined(separator: "\n") as NSString])
  }

  @MainActor
  private func buildContextMenu(_ menu: NSMenu) {
    let playlistItems = displayedPlaylist
    let rows = getTargetRowsForContextMenu()
    player.log.verbose("Building context menu for rows: \(rows.map{ $0 })")

    menu.removeAllItems()

    let isSingleItem = rows.count == 1

    if !rows.isEmpty {
      let firstItem = playlistItems[rows.first!]
      let matchedSubCount = player.info.getMatchedSubs(firstItem.path)?.count ?? 0
      let title: String = isSingleItem ? firstItem.displayName :
      String(format: NSLocalizedString("pl_menu.title_multi", comment: "%d Items"), rows.count)

      menu.addItem(withTitle: title)
      menu.addItem(NSMenuItem.separator())
      menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.play_next", comment: "Play Next"),
                   image: ["text.line.first.and.arrowtriangle.forward"],
                   action: #selector(self.contextMenuPlayNext(_:)))
      menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.play_in_new_window", comment: "Play in New Window"),
                   image: ["macwindow.badge.plus"],
                   action: #selector(self.contextMenuPlayInNewWindow(_:)))
      menu.addItem(forRows: rows, withTitle: NSLocalizedString(isSingleItem ? "pl_menu.remove" : "pl_menu.remove_multi", comment: "Remove"),
                   image: ["delete.backward"],
                   action: #selector(self.contextMenuRemove(_:)))

      if !player.isInMiniPlayer {
        menu.addItem(NSMenuItem.separator())
        if isSingleItem {
          menu.addItem(forRows: rows, withTitle: String(format: NSLocalizedString("pl_menu.matched_sub", comment: "Matched %d Subtitle(s)"), matchedSubCount))
          menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.add_sub", comment: "Add Subtitle…"),
                       image: ["custom.captions.bubble.badge.plus"],
                       action: #selector(self.contextMenuAddSubtitle(_:)))
        }
        if matchedSubCount != 0 {
          menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.wrong_sub", comment: "Wrong Subtitle"),
                       image: ["custom.captions.bubble.slash"],
                       action: #selector(self.contextMenuWrongSubtitle(_:)))
        }
      }

      menu.addItem(NSMenuItem.separator())
      // network resources related operations
      let networkCount = rows.filter {
        playlistItems[$0].isNetworkResource
      }.count
      if networkCount != 0 {
        menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.browser", comment: "Open in Browser"),
                     image: ["globe"],
                     action: #selector(self.contextOpenInBrowser(_:)))
        menu.addItem(forRows: rows, withTitle: NSLocalizedString(networkCount == 1 ? "pl_menu.copy_url" : "pl_menu.copy_url_multi", comment: "Copy URL(s)"),
                     image: ["link"],
                     action: #selector(self.contextCopyURL(_:)))
        menu.addItem(NSMenuItem.separator())
      }
      // file related operations
      let localCount = rows.count - networkCount
      if localCount != 0 {
        menu.addItem(forRows: rows, withTitle: NSLocalizedString(localCount == 1 ? "pl_menu.delete" : "pl_menu.delete_multi", comment: "Delete"),
                     image: ["trash"],
                     action: #selector(self.contextMenuDeleteFile(_:)))
        menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.show_in_finder", comment: "Show in Finder"),
                     image: ["finder"],
                     action: #selector(self.contextMenuShowInFinder(_:)))
        menu.addItem(NSMenuItem.separator())
      }
    }

    // menu items from plugins
    var hasPluginMenuItems = false
    let filenames = Array(rows)
    let plugins = player.plugins
    let pluginMenuItems = plugins.map {
      plugin -> (JavascriptPluginInstance, [JavascriptPluginMenuItem]) in
      if let builder = (plugin.apis["playlist"] as! JavascriptAPIPlaylist).menuItemBuilder?.value,
         let value = builder.call(withArguments: [filenames]),
         value.isObject,
         let items = value.toObject() as? [JavascriptPluginMenuItem] {
        hasPluginMenuItems = true
        return (plugin, items)
      }
      return (plugin, [])
    }
    if hasPluginMenuItems {
      menu.addItem(withTitle: NSLocalizedString("preference.plugins", comment: "Plugins"),
                   image: ["puzzlepiece.extension"])
      for (plugin, items) in pluginMenuItems {
        for item in items {
          add(menuItemDef: item, to: menu, for: plugin)
        }
      }
      menu.addItem(NSMenuItem.separator())
    }

    menu.addItem(withTitle: NSLocalizedString("pl_menu.add_file", comment: "Add File"),
                 image: ["document.badge.plus"],
                 action: #selector(self.addFileAction(_:)))
    menu.addItem(withTitle: NSLocalizedString("pl_menu.add_url", comment: "Add URL"),
                 image: ["link.badge.plus"],
                 action: #selector(self.addURLAction(_:)))
    menu.addItem(withTitle: NSLocalizedString("pl_menu.clear_playlist", comment: "Clear Playlist"),
                 image: ["delete.left.fill"],
                 action: #selector(self.clearPlaylistBtnAction(_:)))

    if #unavailable (macOS 26.0) {
      for item in menu.items {
        item.image = nil
      }
    }
  }

  @discardableResult
  private func add(menuItemDef item: JavascriptPluginMenuItem,
                   to menu: NSMenu,
                   for plugin: JavascriptPluginInstance) -> NSMenuItem {
    if (item.isSeparator) {
      let item = NSMenuItem.separator()
      menu.addItem(item)
      return item
    }

    let menuItem: NSMenuItem
    if item.action == nil {
      menuItem = menu.addItem(withTitle: item.title, action: nil, target: plugin, obj: item)
    } else {
      menuItem = menu.addItem(withTitle: item.title,
                              action: #selector(plugin.playlistMenuItemAction(_:)),
                              target: plugin,
                              obj: item)
    }

    menuItem.isEnabled = item.enabled
    menuItem.state = item.selected ? .on : .off
    if !item.items.isEmpty {
      menuItem.submenu = NSMenu()
      for submenuItem in item.items {
        add(menuItemDef: submenuItem, to: menuItem.submenu!, for: plugin)
      }
    }
    return menuItem
  }
}
