//
//  Player_PlaylistOps.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-26.
//  Copyright © 2025 lhc. All rights reserved.
//

// mpv: Playlist Operations

extension PlayerCore {

  enum UndoOption {
    /// Executes the associated operation but do not register a new undo. Use this for the initial operation, or if undo / redo
    /// is being handled elsewhere.
    case ignoreUndoRedo

    /// After executing the associated operation, calls the `registerUndo` method of the window's `UndoManager` to make it undoable within the window.
    /// The undo operation will also be set to call `UndoManager.registerUndo`, so that it is redoable.
    case registerUndoRedo

    /// Clear the undo stack of the window's `UndoManager`. Use this if the operation cannot be undone, e.g. if hard-deleting a file,
    /// or if an error occurred which left the undo stack in an uncertain state.
    case clearUndoStack
  }

  // MARK: - Insert / Add / Append

  /// Moves the given items so that they are immediately following the now-playing item
  /// (i.e. they will be next in the queue).
  func playNextInPlaylist(_ playlistItemIndexes: IndexSet) {
    mpv.queue.async { [self] in
      let current = mpv.getInt(MPVProperty.playlistPos)
      movePlaylistRows(from: playlistItemIndexes, to: current + 1, .registerUndoRedo)
    }
  }

  /// For restore, or auto-load. Adds all the media in `pathList` to the current playlist, except for the now-playing item.
  /// Each item in `pathList` may be either a file path or a network URL.
  ///
  /// • The current mpv core is expected to have only this item in its playlist at the time of this operation. If additional
  ///   items are present in the playlist, they will get pushed to the top or to the bottom of the playlist.
  /// • This inserts around the currently playing item is in the list, so that it may end up at `indexOfCurrentItem`
  ///   (if provided), which may be in the middle of the playlist.
  func _addAllToPlaylist(pathListIncludingCurrent pathList: [String], indexOfCurrentItem: Int? = nil) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    // This checks for !isStopping, so we don't have to
    guard _reloadPlaylistAndReturn() != nil else { return }

    if info.playlist.count != 1 {
      log.debug{"Found \(info.playlist.count) items instead of exactly 1 before bulk-loading the playlist. Some items may be out of order afterwards"}
    }

    let currentItem: Int
    if let indexOfCurrentItem {
      // Newer versions should include this info
      currentItem = indexOfCurrentItem
    } else if let currentPath = info.currentPlayback?.path,
              let firstMatchingIndex = pathList.firstIndex(of: currentPath) {
      // Try to derive current item index.
      // Use index of first match found. If there are duplicate paths in the playlist, this will be wrong,
      // but older versions of IINA did not support duplicates in the playlist, so shouldn't be an issue.
      currentItem = firstMatchingIndex
    } else {
      log.warn{"Failed to find currently playing item in playlist of size \(info.playlist.count)!"}
      assert(false, "should never get here if used properly!")
      currentItem = -1
    }

    let itemsAtInsertIndexes: [(Int, String)] = pathList.enumerated().compactMap { index, path in
      // skip current item bc it's already present in playlist
      if index == currentItem { return nil }
      // Insert in 2 blocks: before & after current item, respectively
      return (index < currentItem ? 0 : 1, path)
    }

    _playlistInsert(itemsAtIndexes: itemsAtInsertIndexes, info.playlist, onSuccess: { [self] in
      // FIXME: scroll playlist to current item
      displayedPlaylist = info.playlist
      _reloadPlaylist(savePlayerState: false)  // will send notification
    })
  }

  func appendToPlaylist(_ path: String,
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    appendToPlaylist([path], onSuccess: onSuccess, onError: onError)
  }

  func appendToPlaylist(_ paths: [String],
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    addToPlaylist(paths: paths, onSuccess: onSuccess, onError: onError, .registerUndoRedo)
  }

  func appendToPlaylist(urls: any Collection<URL>,
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    let paths = urls.map({PlaybackID.path(from: $0)})
    addToPlaylist(paths: paths, onSuccess: onSuccess, onError: onError, .registerUndoRedo)
  }

  func addToPlaylist(paths: [String], at targetRowIndex: Int? = nil,
                     onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil,
                     _ undoOption: UndoOption) {

    let rowList = paths.compactMap{PlaybackID(path: $0)}
    insertPlaylistRows(rowList, at: targetRowIndex, undoOption)
  }

  /// All playlist "insert" operations should ultimately call this method.
  func insertPlaylistRows(_ desiredRowList: [PlaybackID], at targetRowIndex: Int? = nil, _ undoOption: UndoOption) {
    let playableFiles = getPlayableFiles(in: desiredRowList.map{ $0.url })
    guard playableFiles.count > 0 else { return }
    let rowList = playableFiles.map { PlaybackID($0) }
    log.verbose{"Inserting \(rowList.count) rows into playlist at index \(targetRowIndex?.description ?? "nil"): \(rowList.map{$0.path.pii})"}


    let (tableUIChange, allItemsNew) = windowController.playlistView.isViewLoaded
    ? windowController.playlistView.playlistTableView.buildInsert(of: rowList, at: targetRowIndex, in: displayedPlaylist)
    : TableUIChange.builder.buildInsert(of: rowList, at: targetRowIndex ?? displayedPlaylist.count, in: displayedPlaylist)

    let playlistSize = info.playlist.count
    var insertStartIndex = targetRowIndex ?? playlistSize
    insertStartIndex = (insertStartIndex >= 0 && insertStartIndex <= playlistSize) ? insertStartIndex : playlistSize
    let paths = rowList.map { $0.path }
    let itemsAtIndexes = paths.map ({ path in (insertStartIndex, path)} )

    let expectedCurrentPlaylist = displayedPlaylist  // make sure user is moving what they expect!
    mpv.queue.async { [self] in
      _playlistInsert(itemsAtIndexes: itemsAtIndexes, expectedCurrentPlaylist, onSuccess: { [self] in
        displayedPlaylist = info.playlist                                          // update cached data
        tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // update UI
        sendOSD(.addToPlaylist(paths.count))
        saveState()

        // Register undo/redo for this action?
        switch undoOption {
        case .ignoreUndoRedo:
          break
        case .clearUndoStack:
          log.debug{"Clearing undo stack for playlist after insert"}
          undoHelper.clearUndoes()
        case .registerUndoRedo:
          let actionName = undoHelper.buildActionName(basedOn: tableUIChange)
          undoHelper.register(actionName, undo: { [self] in
            mpv.queue.async { [self] in
              guard validateItemsAreEqual(displayedPlaylist, allItemsNew) else {
                log.error{"Cannot undo insert of playlist items: playlist is in unexpected state! Clearing undo stack."}
                playlistErrorDidOccur()
                return
              }
              let rmStartIndex = tableUIChange.toInsert!.first!
              let rmEndIndex = rmStartIndex + rowList.count
              let rowIndexesToRemove = IndexSet(rmStartIndex..<rmEndIndex)
              DispatchQueue.main.async { [self] in
                removePlaylistRows(rowIndexesToRemove, .ignoreUndoRedo)
              }
            }
          }, redo: { [self] in
            insertPlaylistRows(rowList, at: targetRowIndex, .ignoreUndoRedo)
          })
        }
      })

    }  // end mpv.queue.async

  }

  /// Insert playlist items at mapped indexes. Internal: should *only* be called by `insertPlaylistRows` or by
  /// other non-private `PlayerCore` methods.
  /// - `itemsAtIndexes` must be in ascending index order.
  func _playlistInsert(itemsAtIndexes: [(Int, String)],
                       _ expectedCurrentPlaylist: [PlaybackID]? = nil,
                       onSuccess: OnSuccessCallback? = nil) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.verbose{"Requested to insert \(itemsAtIndexes.count) mpv playlist items at indexes: \(itemsAtIndexes.map(\.0))"}

    // Verify playlist state first before changing anything
    let expectedPlaylistBeforeInsert = expectedCurrentPlaylist ?? info.playlist
    guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistBeforeInsert) else { return }

    // Insert at playlist.count => append
    for (itemsAtIndexIndex, itemsAtIndex) in itemsAtIndexes.enumerated() {
      guard (itemsAtIndex.0 >= 0) && (itemsAtIndex.0 <= info.playlist.count + itemsAtIndexIndex) else {
        log.error{"Cannot insert playlist items; 1 or more indexes are out of bounds: \(itemsAtIndexes.map(\.0)) (playlist size=\(info.playlist.count))"}
        playlistErrorDidOccur()
        return
      }
    }
    var expectedPlaylistAfterInsert = expectedPlaylistBeforeInsert
    var prevInsertCount = 0
    for (itemToInsertIndex, itemToInsertPath) in itemsAtIndexes {
      let insertIndex = itemToInsertIndex + prevInsertCount
      let returnCode = mpv.command(.loadfile, args: [itemToInsertPath, "insert-at", "\(insertIndex)"], checkError: false)
      guard returnCode == 0 else {
        playlistErrorDidOccur(returnCode, opDesc: "insert playlist item \(prevInsertCount) / \(itemsAtIndexes.count)")
        return
      }
      guard let playbackInserted = PlaybackID(path: itemToInsertPath) else {
        log.error("Failed to create PlaybackID from playlist item path! Will cancel remaining item inserts (path=\(itemToInsertPath))")
        playlistErrorDidOccur()
        return
      }
      expectedPlaylistAfterInsert.insert(playbackInserted, at: insertIndex)
      prevInsertCount += 1
    }

    // Now verify playlist state again to ensure changes were correct
    guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistAfterInsert) else { return }

    if let onSuccess {
      _ = onSuccess()
    }
  }

  // MARK: - Move

  func playlistMove(_ fromIndex: Int, to targetRowIndex: Int) {
    movePlaylistRows(from: IndexSet(integer: fromIndex), to: targetRowIndex, .registerUndoRedo)
  }

  /// Drag & drop within `playlistTableView`. Should be called only by `movePlaylistRows`.
  private func playlistMoveIndexPairs(_ indexPairs: [(Int, Int)],
                                      _ expectedCurrentPlaylist: [PlaybackID]? = nil,
                                      onSuccess: OnSuccessCallback? = nil) {
    mpv.queue.async { [self] in
      log.debug{"Playlist move index pairs: \(indexPairs)"}

      // Verify playlist state first before changing anything
      let expectedPlaylistBeforeInsert = expectedCurrentPlaylist ?? info.playlist
      guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistBeforeInsert) else {
        return
      }

      for (srcIndex, dstIndex) in indexPairs {
        let returnCode = mpv.command(.playlistMove, args: ["\(srcIndex)", "\(dstIndex)"], checkError: false, level: .verbose)
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "move playlist item \(srcIndex) → \(dstIndex)")
        }
      }

      if let onSuccess {
        _ = onSuccess()
      } else {
        _reloadPlaylist()
      }
    }

  }

  /// The arguments for mpv's `playlist-move` command are slightly different than Cocoa's
  /// `NSTableView.moveRow` command. If row's source index is above the insert index, Cocoa requires an
  /// extra -1 subtracted from its destination index, whereas mpv does not.
  private func buildMpvMoveIndexPairs(from rowIndexes: IndexSet, to insertIndex: Int) -> [(Int, Int)] {
    var moveIndexPairs: [(Int, Int)] = []
    var moveFromOffset = 0
    var moveToOffset = 0
    for origIndex in rowIndexes {
      if origIndex < insertIndex {
        moveIndexPairs.append((origIndex + moveFromOffset, insertIndex))
        moveFromOffset -= 1
      } else {
        moveIndexPairs.append((origIndex, insertIndex + moveToOffset))
        moveToOffset += 1
      }
    }
    return moveIndexPairs
  }

  func buildInvertedMpvMoveIndexPairs(from rowIndexes: IndexSet, to insertIndex: Int) -> [(Int, Int)] {
    var movePairsInverted: [(Int, Int)] = []

    var moveFromOffset = 0
    var moveToOffset = 0
    for origIndex in rowIndexes {
      if insertIndex < origIndex {
        movePairsInverted.append((insertIndex, origIndex + moveFromOffset))
        moveFromOffset -= 1
      } else {
        movePairsInverted.append((insertIndex + moveToOffset - 1, origIndex))
        moveToOffset += 1
      }
    }
    return movePairsInverted.reversed()
  }

  func movePlaylistRows(from rowIndexes: IndexSet, to insertIndex: Int, _ undoOption: UndoOption) {
    let (tableUIChange, allItemsNew) = TableUIChange.builder.buildMove(rowIndexes, to: insertIndex, in: displayedPlaylist)
    let allItemsOld = displayedPlaylist  // save in case of undo

    let moveIndexPairs = buildMpvMoveIndexPairs(from: rowIndexes, to: insertIndex)
    log.verbose{"Moving playlist rows=\(rowIndexes.toArray()) → \(insertIndex); movePairs=\(moveIndexPairs)"}

    playlistMoveIndexPairs(moveIndexPairs, allItemsOld, onSuccess: { [self] in
      guard syncAndValidatePlaylist(expectedPlaylist: allItemsNew) else { return }

      displayedPlaylist = info.playlist                                          // update cached data
      tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // notify UI
      saveState()

      switch undoOption {
      case .ignoreUndoRedo:
        break
      case .clearUndoStack:
        log.debug{"Clearing undo stack for playlist after 'move'"}
        undoHelper.clearUndoes()
      case .registerUndoRedo:
        undoHelper.register(undoHelper.buildActionName(basedOn: tableUIChange), undo: { [self] in
          log.verbose{"Requested: undo move of \(rowIndexes.count) playlist items"}

          // Builds an insert. Unlike the undo for `insertPlaylistRows()`, this is non-trivial because the original deleted items
          // can be at non-contiguous indexes in the playlist.
          let tableUIChangeUndo = tableUIChange.inverted(selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)
          // FIXME: there is a bug here
          let undoMoveIndexPairs = buildInvertedMpvMoveIndexPairs(from: rowIndexes, to: insertIndex)

          log.verbose{"Undo move of playlist rows=\(rowIndexes.toArray()) → \(insertIndex); undoMoveIndexPairs=\(undoMoveIndexPairs)"}
          playlistMoveIndexPairs(undoMoveIndexPairs, allItemsNew, onSuccess: { [self] in
            guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }

            displayedPlaylist = info.playlist                                              // update cached data
            tableUIChangeUndo.postNotification(name: playlistTableChangeNotificationName)  // notify UI
            saveState()
          })
        }, redo: { [self] in
          mpv.queue.async { [self] in
            guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }

            DispatchQueue.main.async { [self] in
              movePlaylistRows(from: rowIndexes, to: insertIndex, .ignoreUndoRedo)
            }
          }
        })
      }

    })

  }

  // MARK: - Remove

  func playlistRemove(_ index: Int, _ undoOption: UndoOption) {
    playlistRemove(IndexSet(integer: index), undoOption)
  }

  func playlistRemove(_ indexSet: IndexSet,_ undoOption: UndoOption) {
    removePlaylistRows(indexSet, undoOption)
  }

  func removePlaylistRows(_ rowIndexes: IndexSet, _ undoOption: UndoOption) {
    guard !rowIndexes.isEmpty else { return }

    let (tableUIChange, allItemsNew) = TableUIChange.builder.buildRemove(rowIndexes, in: displayedPlaylist,
                                                                         selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)
    let allItemsOld = displayedPlaylist     // save in case of undo

    mpv.queue.async { [self] in
      log.verbose{"Requested to remove rows \(rowIndexes.map{$0}) from playlist"}

      guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }

      // Remove playlist items one at a time, from top to bottom (increasing index).
      // After an item is removed, the indexes of all items below it are subtracted by 1.
      var countRemoved = 0
      for origIndex in rowIndexes {
        let index = origIndex - countRemoved
        log.verbose("Removing row \(index) from playlist")
        let returnCode = mpv.command(.playlistRemove, args: [index.description], checkError: false)
        // If error occurred, report using callback, reload state, and do not continue
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "remove playlist item \(countRemoved) / \(rowIndexes.count)")
        }
        countRemoved += 1
      }

      guard syncAndValidatePlaylist(expectedPlaylist: allItemsNew) else { return }
      displayedPlaylist = info.playlist                                          // update cached data
      tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // update UI
      sendOSD(.removeFromPlaylist(countRemoved))

      // Register undo/redo?
      switch undoOption {
      case .ignoreUndoRedo:
        break
      case .clearUndoStack:
        log.debug{"Clearing undo stack for playlist after 'remove'"}
        undoHelper.clearUndoes()
      case .registerUndoRedo:
        undoHelper.register(undoHelper.buildActionName(basedOn: tableUIChange), undo: { [self] in
          mpv.queue.async { [self] in
            guard syncAndValidatePlaylist(expectedPlaylist: allItemsNew) else { return }

            // Builds an insert. Unlike the undo for `insertPlaylistRows()`, this is non-trivial because the original deleted items
            // can be at non-contiguous indexes in the playlist.
            let indexedInsertItems = rowIndexes.enumerated().map{ ($0.element - $0.offset, allItemsOld[$0.element].path) }
            assert(indexedInsertItems.map(\.0).sorted(by: { $0 < $1 }).elementsEqual(indexedInsertItems.map(\.0)),
                   "itemsAtIndexes must be sorted in ascending order, but found: \(indexedInsertItems.map(\.0))")
            let tableUIChangeUndo = tableUIChange.inverted(selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)

            _playlistInsert(itemsAtIndexes: indexedInsertItems, onSuccess: { [self] in
              displayedPlaylist = info.playlist                                              // update cached data
              tableUIChangeUndo.postNotification(name: playlistTableChangeNotificationName)  // update UI
              sendOSD(.addToPlaylist(indexedInsertItems.count))
            })
          }
        }, redo: { [self] in
          // Almost the same code as above. But don't want to re-register an undo action
          removePlaylistRows(rowIndexes, .ignoreUndoRedo)
        })
      }
    }
  }

  // MARK: - Reload

  /// Reloads playlist from mpv, then enqueues state save & sends `iinaPlaylistChanged` notification.
  func reloadPlaylist(thenPostNotification: Bool = true, savePlayerState: Bool = true) {
    mpv.queue.async { [self] in
      _reloadPlaylist(thenPostNotification: thenPostNotification, savePlayerState: savePlayerState)
    }
  }

  func _reloadPlaylist(thenPostNotification: Bool = true, savePlayerState: Bool = true) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return }

    guard _reloadPlaylistAndReturn() != nil else { return }

    if thenPostNotification {
      postNotification(.iinaPlaylistChanged)
    }

    if savePlayerState {
      saveState()  // save playlist URLs to prefs
    }
  }

  /// 1. Gets the up-to-date playlist & `playlist-pos` (now playing item index) from mpv.
  /// 2. Updates `info.playlist` & `info.currentPlayback?.playlistPos`.
  /// 3. Returns the up-to-date playlist (or `nil` on error or incorrect state).
  func _reloadPlaylistAndReturn() -> [PlaybackID]? {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return nil }

    var newPlaylist: [PlaybackID] = []
    let playlistCount = mpv.getInt(MPVProperty.playlistCount)
    log.verbose{"Reloading playlist with \(playlistCount) items"}
    for index in 0..<playlistCount {
      let urlPath = mpv.getString(MPVProperty.playlistNFilename(index))!
      guard let playlistItem = PlaybackID(path: urlPath) else {
        log.error{"Playlist item has invalid path; skipping: \(urlPath.pii.quoted)"}
        continue
      }
      newPlaylist.append(playlistItem)
    }

    let mpvPlaylistPos = mpv.getInt(MPVProperty.playlistPos)
    info.currentPlayback?.playlistPos = mpvPlaylistPos
    info.playlist = newPlaylist
    log.verbose{"After reloading playlist: playlistPos is: \(mpvPlaylistPos)"}

    return newPlaylist
  }

  // MARK: - Other playlist ops

  func clearPlaylist() {
    mpv.queue.async { [self] in
      log.verbose("Sending 'playlist-clear' cmd to mpv")
      mpv.command(.playlistClear, checkError: false)
      _reloadPlaylist()
      log.verbose("Clearing undo stack after 'playlist-clear' cmd")
      undoHelper.clearUndoes()
    }
  }

  func playFile(_ path: String) {
    mpv.queue.async { [self] in
      info.shouldAutoLoadFiles = true
      let returnCode = mpv.command(.loadfile, args: [path, "replace"], checkError: false)
      guard returnCode == 0 else {
        // TODO: report error
        return
      }
      _reloadPlaylist()
    }
  }

  func playFileInPlaylist(_ pos: Int) {
    mpv.queue.async { [self] in
      log.verbose{"Changing mpv playlist-pos to \(pos)"}
      mpv.setInt(MPVProperty.playlistPos, pos)
    }
  }

  func navigateInPlaylist(nextMedia: Bool) {
    mpv.queue.async { [self] in
      mpv.command(nextMedia ? .playlistNext : .playlistPrev, checkError: false)
    }
  }

  // MARK: - Utils

  private func validateItemsAreEqual(_ p1: [PlaybackID], _ p2: [PlaybackID]) -> Bool {
    let p1Paths = p1.map{ $0.path }
    return (p1.count == p2.count) && p2.map({$0.path}).elementsEqual(p1Paths)
  }

  private func syncAndValidatePlaylist(expectedPlaylist: [PlaybackID]) -> Bool {
    guard let actualPlaylist = _reloadPlaylistAndReturn() else {
      return false
    }

    if validateItemsAreEqual(actualPlaylist, expectedPlaylist) {
      return true
    } else {
      log.error{"Playlist is in unexpected state! Clearing undo stack to prevent further issues."}
      playlistErrorDidOccur()
      return false
    }
  }

  private func playlistErrorDidOccur(_ returnCode: Int32, opDesc: String) {
    let errorString = String(cString: mpv_error_string(returnCode))
    log.error{"Failed to \(opDesc) (will clear undo stack): \(errorString)"}
    playlistErrorDidOccur()
  }

  private func playlistErrorDidOccur() {
    undoHelper.clearUndoes()
    _reloadPlaylist(savePlayerState: false)
    // TODO: beep
  }

}
