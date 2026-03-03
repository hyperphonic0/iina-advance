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
      guard !isStopping else { return }
      let current = mpv.getInt(MPVProperty.playlistPos)
      pwc.animationPipeline.submitInstantTask { [self] in
        movePlaylistRows(from: playlistItemIndexes, to: current + 1, .registerUndoRedo)
      }
    }
  }

  /// For restore, or auto-load. Adds all the media in `pathList` to the current playlist, except for the now-playing item.
  /// Each item in `pathList` may be either a file path or a network URL.
  ///
  /// • The current mpv core is expected to have only this item in its playlist at the time of this operation. If additional
  ///   items are present in the playlist, they will get pushed to the top or to the bottom of the playlist.
  /// • This inserts around the currently playing item is in the list. If `indexOfCurrentItem` is provided, the currently playing item
  ///  will be located at `indexOfCurrentItem` after all inserts are done. Otherwise, the current item index will try to be derived by
  ///  matching playlist item URLs against `info.currentPlayback`.
  func addAllToPlaylist(playbackIDsIncludingCurrent playbackIDs: [PlaybackID], indexOfCurrentItem currentItemExplicitIndex: Int? = nil) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    guard !isStopping else { return }
    _reloadPlaylist(thenPostNotification: false, savePlayerState: false)

    if info.playlist.count != 1 {
      log.debug("[Playlist] Expected exactly 1 item in playlist before bulk-add, but found \(info.playlist.count). Some items may be out of order afterwards")
    }

    log.trace("[Playlist] Adding URLs: [\(playbackIDs.map(\.path.pii.quoted).joined(separator: ", "))]")

    let nowPlayingIndex: Int
    if let currentItemExplicitIndex, currentItemExplicitIndex >= 0 {
      // Newer versions should include this info
      nowPlayingIndex = currentItemExplicitIndex
    } else if let currentPlaybackID = info.currentPlayback?.id {
      if let firstMatchingIndex = playbackIDs.firstIndex(of: currentPlaybackID) {
        // Try to derive current item index.
        // Use index of first match found. If there are duplicate paths in the playlist, this will be wrong,
        // but older versions of IINA did not support duplicates in the playlist, so shouldn't be an issue.
        nowPlayingIndex = firstMatchingIndex
      } else {
        log.error("[Playlist] Playlist (count=\(info.playlist.count) items) does not contain currently playing item (\(currentPlaybackID.path.pii.quoted))")
        nowPlayingIndex = -1
      }
    } else {
      log.warn("[Playlist] Cannot determine current item index: currentPlayback is nil!")
      assert(false, "currentPlayback should never be nil if used properly!")
      nowPlayingIndex = -1
    }

    let itemsAtInsertIndexes: [(Int, PlaybackID)] = playbackIDs.enumerated().compactMap { itemIndex, itemID in
      // skip current item bc it's already present in playlist
      if itemIndex == nowPlayingIndex { return nil }
      // Use ID which contains bookmark, if available
      let itemIDWithBookmark = MediaMetaCache.shared.getPlaybackIDWithBookmark(forID: itemID)
      // Insert in 2 blocks: before & after current item, respectively
      return (itemIndex < nowPlayingIndex ? 0 : 1, itemIDWithBookmark)
    }

    _playlistInsert(itemsAtIndexes: itemsAtInsertIndexes,
                    expectedCurrentPlaylist: info.playlist,
                    newIsPlayingIndex: nowPlayingIndex,
                    onSuccess: { [self] in
      log.verbose("[Playlist] Done adding \(playbackIDs.count) items. Playlist count is now \(info.playlist.count)")
      pwc.playlistView.refreshNowPlayingIndex(thenScrollToVisible: true)
    })
  }

  @MainActor
  func appendToPlaylist(_ path: String,
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    appendToPlaylist([path], onSuccess: onSuccess, onError: onError)
  }

  @MainActor
  func appendToPlaylist(_ paths: [String],
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    addToPlaylist(paths: paths, onSuccess: onSuccess, onError: onError, .registerUndoRedo)
  }

  @MainActor
  func appendToPlaylist(urls: any Collection<URL>,
                        onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil) {
    let paths = urls.map({PlaybackID.path(from: $0)})
    addToPlaylist(paths: paths, onSuccess: onSuccess, onError: onError, .registerUndoRedo)
  }

  @MainActor
  func addToPlaylist(paths: [String], at targetRowIndex: Int? = nil,
                     onSuccess: OnSuccessCallback? = nil, onError: OnErrorCallback? = nil,
                     _ undoOption: UndoOption) {

    let rowList: [PlaybackID] = paths.compactMap{ path in
      guard let id = PlaybackID(path: path) else { return nil }
      return MediaMetaCache.shared.getPlaybackIDWithBookmark(forID: id)
    }
    insertPlaylistRows(rowList, at: targetRowIndex, undoOption)
  }

  /// All playlist "insert" operations should ultimately call this method.
  @MainActor
  func insertPlaylistRows(_ desiredRowList: [PlaybackID], at targetRowIndex: Int? = nil, _ undoOption: UndoOption) {
    pwc.animationPipeline.submitInstantTask { [self] in
      insertPlaylistRows_TaskBody(desiredRowList, at: targetRowIndex, undoOption)
    }
  }

  @MainActor
  private func insertPlaylistRows_TaskBody(_ desiredRowList: [PlaybackID], at targetRowIndex: Int? = nil, _ undoOption: UndoOption) {
    let rowList = getPlayableFiles(in: desiredRowList)
    guard rowList.count > 0 else { return }
    log.verbose("[Playlist] Inserting \(rowList.count) rows at index \(targetRowIndex?.description ?? "nil"): \(rowList.map{$0.path.pii})")
    let expectedCurrentPlaylist = displayedPlaylist  // make sure user is moving what they expect!

    let (tableUIChange, allItemsNew): (TableUIChange, [PlaybackID])
    if pwc.playlistView.isViewLoaded {
      (tableUIChange, allItemsNew) = pwc.playlistView.playlistTableView.buildInsert(of: rowList, at: targetRowIndex, in: expectedCurrentPlaylist)
    } else {
      (tableUIChange, allItemsNew) = TableUIChangeBuilder.shared.buildInsert(of: rowList, at: targetRowIndex ?? expectedCurrentPlaylist.count, in: expectedCurrentPlaylist)
    }

    let playlistSize = expectedCurrentPlaylist.count
    var insertStartIndex = targetRowIndex ?? playlistSize
    insertStartIndex = (insertStartIndex >= 0 && insertStartIndex <= playlistSize) ? insertStartIndex : playlistSize
    let itemsAtIndexes = rowList.map ({ row in (insertStartIndex, row)} )

    playlistInsert(itemsAtIndexes: itemsAtIndexes,
                   expectedCurrentPlaylist: expectedCurrentPlaylist,
                   onSuccess: { [self] in
      tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // update UI
      sendOSD(.addToPlaylist(rowList.count))

      // Register undo/redo for this action?
      switch undoOption {
      case .ignoreUndoRedo:
        break
      case .clearUndoStack:
        log.debug("[Playlist] Clearing undo stack for playlist after 'insert'")
        undoHelper.clearUndoes()
      case .registerUndoRedo:
        let actionName = undoHelper.buildActionName(basedOn: tableUIChange)
        undoHelper.register(actionName, undo: { [self] in
          let expectedPlaylist = displayedPlaylist
          guard expectedPlaylist == allItemsNew else {
            log.error("[Playlist] Cannot undo insert: playlist is in unexpected state! Clearing undo stack & aborting.")
            playlistErrorDidOccur()
            return
          }
          let rmStartIndex = tableUIChange.toInsert!.first!
          let rmEndIndex = rmStartIndex + rowList.count
          let rowIndexesToRemove = IndexSet(rmStartIndex..<rmEndIndex)
          removePlaylistRows(rowIndexesToRemove, .ignoreUndoRedo)
        }, redo: { [self] in
          insertPlaylistRows(rowList, at: targetRowIndex, .ignoreUndoRedo)
        })

        // Enqueue BG task to generate bookmark data for the new item if it doesn't yet exist.
        // Do not do this for initial `addAllToPlaylist` inserts because that will be handled separately (and better cancellation).
        // Generally we only want to execute this logic once per operation (not undo or redo), so attach this to `.registerUndoRedo`,
        // and this conveniently will also omit `addAllToPlaylist` because that does not register an undo.
        let itemsNeedingBookmarks = rowList.filter { $0.needsBookmark }
        let currentTicket = postLoadBGQTicket  // attach to current ticket; should be fine
        if !itemsNeedingBookmarks.isEmpty {
          PlayerCore.postLoadBGQ.async { [self] in
            for item in itemsNeedingBookmarks {
              guard currentTicket == postLoadBGQTicket else { return }
              if MediaMetaCache.shared.createBookmarkIfNotExist(fromURL: item.url) {
                log.verbose("Created bookmark data from URL \(item.url.path.pii.quoted)")
              }
            }
          }
        }
      }
    })
  }

  /// Insert playlist items at mapped indexes. Contains the backend logic only.
  ///
  /// This is internal: should *only* be called by `insertPlaylistRows` or by other non-private `PlayerCore` methods,
  /// and must be called on the `mpv` queue.
  /// - `itemsAtIndexes` must be in ascending index order.
  func playlistInsert(itemsAtIndexes: [(insertTargetIndex: Int, itemToInsert: PlaybackID)],
                      expectedCurrentPlaylist: [PlaybackID]? = nil,
                      newIsPlayingIndex: Int? = nil,
                      onSuccess: @escaping MainActorSuccessCallback) {
    mpv.queue.async { [self] in
      _playlistInsert(itemsAtIndexes: itemsAtIndexes, expectedCurrentPlaylist: expectedCurrentPlaylist,
                      newIsPlayingIndex: newIsPlayingIndex,
                      onSuccess: onSuccess)
    }
  }

  /// Insert playlist items at mapped indexes. Contains the backend logic only.
  ///
  /// This is internal: should *only* be called by `insertPlaylistRows` or by other non-private `PlayerCore` methods,
  /// and must be called on the `mpv` queue.
  /// - `itemsAtIndexes` must be in ascending index order.
  func _playlistInsert(itemsAtIndexes: [(insertTargetIndex: Int, itemToInsert: PlaybackID)],
                       expectedCurrentPlaylist: [PlaybackID]? = nil,
                       newIsPlayingIndex: Int?,
                       onSuccess: @escaping MainActorSuccessCallback) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.verbose("[Playlist] Insert requested: \(itemsAtIndexes.count) total items @ mpvIndexes=\(itemsAtIndexes.map(\.0))")

    // Verify playlist state first before changing anything
    let expectedPlaylistBeforeInsert = expectedCurrentPlaylist ?? info.playlist
    guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistBeforeInsert) else { return }

    // Insert at playlist.count => append
    for (workItemIndex, (insertTargetIndex, _)) in itemsAtIndexes.enumerated() {
      guard (insertTargetIndex >= 0) && (insertTargetIndex <= info.playlist.count + workItemIndex) else {
        log.error("[Playlist] Cannot insert items: 1 or more indexes are out of bounds! Indexes=\(itemsAtIndexes.map(\.0)) PlaylistSize=\(info.playlist.count)")
        playlistErrorDidOccur()
        return
      }
    }
    var expectedPlaylistAfterInsert = expectedPlaylistBeforeInsert
    var prevInsertCount = 0
    for (itemToInsertIndex, itemToInsert) in itemsAtIndexes {
      let insertIndex = itemToInsertIndex + prevInsertCount
      let itemToInsertPath = itemToInsert.path
      let returnCode = mpv.playlistInsert(itemToInsertPath, index: insertIndex)

      guard returnCode == 0 else {
        playlistErrorDidOccur(returnCode, opDesc: "insert playlist item \(prevInsertCount) / \(itemsAtIndexes.count)")
        return
      }
      expectedPlaylistAfterInsert.insert(itemToInsert, at: insertIndex)
      prevInsertCount += 1
    }

    // If `newIsPlayingIndex` is provided, use it rather than trying to derive playlistPos because that can be wrong for duplicates
    if let newIsPlayingIndex, let currentPlayback = info.currentPlayback,
       newIsPlayingIndex >= 0, newIsPlayingIndex < expectedPlaylistAfterInsert.count {
      info.currentPlayback = currentPlayback.clone(playlistPos: newIsPlayingIndex)
    }

    // Now verify playlist state again to ensure changes were correct
    guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistAfterInsert) else { return }

    pwc.animationPipeline.submitInstantTask { [self] in
      displayedPlaylist = info.playlist  // update cached data
      saveState()
      onSuccess()
    }
  }

  // MARK: - Move

  func playlistMove(_ fromIndex: Int, to targetRowIndex: Int) {
    movePlaylistRows(from: IndexSet(integer: fromIndex), to: targetRowIndex, .registerUndoRedo)
  }

  func movePlaylistRows(from rowIndexes: IndexSet, to insertIndex: Int, _ undoOption: UndoOption) {
    pwc.animationPipeline.submitInstantTask { [self] in
      movePlaylistRows_TaskBody(from: rowIndexes, to: insertIndex, undoOption)
    }
  }

  @MainActor
  private func movePlaylistRows_TaskBody(from rowIndexes: IndexSet, to insertIndex: Int, _ undoOption: UndoOption) {
    // 1. Build UI update in main queue
    let allItemsOld = displayedPlaylist  // save in case of undo
    let (tableUIChange, allItemsNew) = TableUIChangeBuilder.shared.buildMove(rowIndexes, to: insertIndex, in: allItemsOld)

    let moveIndexPairs = buildMpvMoveIndexPairs(from: rowIndexes, to: insertIndex)
    log.verbose("[Playlist] Moving indexes=\(rowIndexes.toArray()) → \(insertIndex); indexPairs=\(moveIndexPairs)")

    // 2. Execute backend update on mpv queue. Validate playlist before & after for consistency
    playlistMoveIndexPairs(moveIndexPairs,
                           expectedPlaylistBefore: allItemsOld,
                           expectedPlaylistAfter: allItemsNew,
                           onSuccess: { [self] in
      // 3. Update UI with result, register undo, kick off other post-processing
      tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // notify UI

      switch undoOption {
      case .ignoreUndoRedo:
        break
      case .clearUndoStack:
        log.debug("[Playlist] Clearing undo stack after 'move'")
        undoHelper.clearUndoes()
      case .registerUndoRedo:
        undoHelper.register(undoHelper.buildActionName(basedOn: tableUIChange), undo: { [self] in
          log.verbose("[Playlist] Requested: undo move of \(rowIndexes.count) items")

          // Undo 1. Build UI update in main queue
          // Builds an insert. Unlike the undo for `insertPlaylistRows()`, this is non-trivial because the original deleted items
          // can be at non-contiguous indexes in the playlist.
          let tableUIChangeUndo = tableUIChange.inverted(selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)
          let undoMoveIndexPairs = buildInvertedMpvMoveIndexPairs(from: rowIndexes, to: insertIndex, movePairs: moveIndexPairs)
          log.verbose("[Playlist] Undo move (original op: move rows=\(rowIndexes.toArray()) → \(insertIndex); undoMoveIndexPairs=\(undoMoveIndexPairs))")
          // Undo 2. Execute backend update on mpv queue. Validate playlist before & after for consistency
          playlistMoveIndexPairs(undoMoveIndexPairs,
                                 expectedPlaylistBefore: allItemsNew,
                                 expectedPlaylistAfter: allItemsOld,
                                 onSuccess: { [self] in
            // 3. Update UI with result (undo is already registered)
            tableUIChangeUndo.postNotification(name: playlistTableChangeNotificationName)  // notify UI
          })

        }, redo: { [self] in
          mpv.queue.async { [self] in
            // Make sure this is an exact same redo! Need to run this in mpv queue to avoid data loss due to races
            guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }

            movePlaylistRows(from: rowIndexes, to: insertIndex, .ignoreUndoRedo)
          }
        })
      }

    })
  }

  /// Drag & drop within `playlistTableView`. Should be called only by `movePlaylistRows`.
  private func playlistMoveIndexPairs(_ indexPairs: [(Int, Int)],
                                       expectedPlaylistBefore: [PlaybackID],
                                       expectedPlaylistAfter: [PlaybackID],
                                       onSuccess: @escaping MainActorSuccessCallback) {
    mpv.queue.async { [self] in
      log.debug("[Playlist] Executing move of (src,dst) indexPairs=\(indexPairs)")

      // Verify playlist state first before changing anything. This will take proper steps on failure, so just return in that case.
      guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistBefore) else { return }

      for (srcIndex, dstIndex) in indexPairs {
        let returnCode = mpv.playlistMove(srcIndex, to: dstIndex)
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "move playlist item \(srcIndex) → \(dstIndex)")
        }
      }

      guard syncAndValidatePlaylist(expectedPlaylist: expectedPlaylistAfter) else {
        if log.isVerboseEnabled {
          let tableChangeExpected = TableUIChangeBuilder.shared.buildDiff(oldRows: expectedPlaylistBefore,
                                                                          newRows: expectedPlaylistAfter)
          let tableChangeActual = TableUIChangeBuilder.shared.buildDiff(oldRows: expectedPlaylistBefore,
                                                                        newRows: info.playlist)
          let expStr: String = tableChangeExpected.toMove?.compactMap{"\($0.0) → \($0.1)"}.joined(separator: "\n") ?? "nil"
          let actStr: String = tableChangeActual.toMove?.compactMap{"\($0.0) → \($0.1)"}.joined(separator: "\n") ?? "nil"
          log.warn("[Playlist] Mismatch after MOVE:\nEXPECTED:\n\(expStr)\n\nACTUAL:\n\(actStr)")
        }
        return
      }

      // Success!
      pwc.animationPipeline.submitInstantTask { [self] in
        displayedPlaylist = info.playlist  // Update cached data
        saveState()
        onSuccess()
      }
    }
  }

  /// The arguments for mpv's `playlist-move` command are slightly different than Cocoa's
  /// `NSTableView.moveRow` command. If row's source index is above the insert index, Cocoa requires an
  /// extra -1 subtracted from its destination index, whereas mpv does not.
  ///
  /// See `TableUIChangeBuilder.buildMove` for the Cocoa version.
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

  /// Given the arguments for a list of mpv `playlist-move` commands which were executed together to rearrange playlist rows,
  /// returns a list of "inverted" (src, dst) index pairs which can be used to undo the first list of commands.
  /// * `rowIndexes`, `insertIndex`: source indexes & insert index args from the original "move" operation.
  /// * `movePairs`: mpv (source, destination) pairs created by `buildMpvMoveIndexPairs()`.
  private func buildInvertedMpvMoveIndexPairs(from rowIndexes: IndexSet, to insertIndex: Int,
                                              movePairs: [(Int, Int)]) -> [(Int, Int)] {
    var movePairsInverted: [(Int, Int)] = []

    var undoSrcOffset = 0
    var undoDstOffset = 0
    for (origIndex, (_, opDstIndex)) in zip(rowIndexes, movePairs).reversed() {
      if origIndex < insertIndex {
        undoSrcOffset -= 1
        movePairsInverted.append((opDstIndex + undoSrcOffset, origIndex))
      } else {
        undoDstOffset += 1
        movePairsInverted.append((opDstIndex + undoSrcOffset, origIndex + undoDstOffset))
      }
    }
    return movePairsInverted.reversed()
  }


  // MARK: - Remove

  @MainActor
  func playlistRemove(_ index: Int, _ undoOption: UndoOption) {
    playlistRemove(IndexSet(integer: index), undoOption)
  }

  @MainActor
  func playlistRemove(_ indexSet: IndexSet,_ undoOption: UndoOption) {
    removePlaylistRows(indexSet, undoOption)
  }

  /// REMOVE operation with undo support
  @MainActor
  func removePlaylistRows(_ rowIndexes: IndexSet, _ undoOption: UndoOption) {
    pwc.animationPipeline.submitInstantTask { [self] in
      removePlaylistRows_TaskBody(rowIndexes, undoOption)
    }
  }

  @MainActor
  private func removePlaylistRows_TaskBody(_ rowIndexes: IndexSet, _ undoOption: UndoOption) {
    guard !rowIndexes.isEmpty else { return }

    // 1. Build UI update in main queue
    let allItemsOld = displayedPlaylist     // save in case of undo
    let (tableUIChange, allItemsNew) = TableUIChangeBuilder.shared.buildRemove(rowIndexes, in: allItemsOld,
                                                                               selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)

    // 2. Execute backend update on mpv queue. Validate playlist before & after for consistency
    mpv.queue.async { [self] in
      log.verbose("[Playlist] Remove requested: mpvIndexes=\(rowIndexes.map{$0})")

      guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }

      // Remove playlist items one at a time, from top to bottom (increasing index).
      // After an item is removed, the indexes of all items below it are subtracted by 1.
      var countRemoved = 0
      for origIndex in rowIndexes {
        let index = origIndex - countRemoved
        log.verbose("[Playlist] Sending mpv remove cmd for row \(index)")
        let returnCode = mpv.playlistRemove(index)
        // If error occurred, report using callback, reload state, and do not continue
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "remove playlist item \(countRemoved) / \(rowIndexes.count)")
        }
        countRemoved += 1
      }

      guard syncAndValidatePlaylist(expectedPlaylist: allItemsNew) else { return }
      let countRemovedCopy = countRemoved

      // 3. Update UI with result, register undo, kick off other post-processing
      pwc.animationPipeline.submitInstantTask { [self] in
        displayedPlaylist = info.playlist                                          // update cached data
        tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // update UI
        sendOSD(.removeFromPlaylist(countRemovedCopy))
        saveState()

        // Register undo/redo?
        switch undoOption {
        case .ignoreUndoRedo:
          break
        case .clearUndoStack:
          log.debug("[Playlist] Clearing undo stack after 'remove'")
          undoHelper.clearUndoes()
        case .registerUndoRedo:
          undoHelper.register(undoHelper.buildActionName(basedOn: tableUIChange), undo: { [self] in
            // 1. Build UI update for undo in main queue
            // Builds an insert. Unlike the undo for `insertPlaylistRows()`, this is non-trivial because the original deleted items
            // can be at non-contiguous indexes in the playlist.
            let indexedInsertItems = rowIndexes.enumerated().map{ ($0.element - $0.offset, allItemsOld[$0.element]) }
            assert(indexedInsertItems.map(\.0).sorted(by: { $0 < $1 }).elementsEqual(indexedInsertItems.map(\.0)),
                   "itemsAtIndexes must be sorted in ascending order, but found: \(indexedInsertItems.map(\.0))")
            let tableUIChangeUndo = tableUIChange.inverted(selectNextRowAfterDelete: playlistTableSelectNextRowAfterDelete)

            // 2. Execute backend update for undo on mpv queue. Validate playlist before & after for consistency
            playlistInsert(itemsAtIndexes: indexedInsertItems,
                           expectedCurrentPlaylist: allItemsNew,
                           onSuccess: { [self] in
              // 3. Update UI with result, register undo, kick off other post-processing
              tableUIChangeUndo.postNotification(name: playlistTableChangeNotificationName)  // update UI
              sendOSD(.addToPlaylist(indexedInsertItems.count))
            })

          }, redo: { [self] in
            // Almost the same code as above. But don't want to re-register an undo action
            removePlaylistRows(rowIndexes, .ignoreUndoRedo)
          })
        }
      }
    }
  }

  // MARK: - Reorder

  /// REORDER operation with undo support
  @MainActor
  func playlistReorder(newPlaylist allItemsNew: [PlaybackID], _ undoOption: UndoOption = .registerUndoRedo) {
    // 1. Build UI update in main queue
    let allItemsOld = displayedPlaylist     // save in case of undo
    guard Set(allItemsOld) == Set(allItemsNew) else { return }
    if allItemsOld == allItemsNew { return }
    let tableUIChange = TableUIChangeBuilder.shared.buildDiff(oldRows: allItemsOld, newRows: allItemsNew)

    // 2. Execute backend update on mpv queue. Validate playlist before & after for consistency
    mpv.queue.async { [self] in
      log.verbose("[Playlist] Reorder playlist requested")
      guard syncAndValidatePlaylist(expectedPlaylist: allItemsOld) else { return }
      guard let currentPlayback = info.currentPlayback else {
        log.error("[Playlist] Aborting request to reorder playlist: currentPlayback is nil!")
        return
      }
      let currentURL = currentPlayback.url

      // FIXME: Need to parameterize currentPlayingIndexNew. Otherwise our assumption here may be wrong when it is a duplicate!
      guard let currentPlayingIndexNew = allItemsNew.firstIndex(where: { $0.url == currentURL } ) else {
        log.error("[Playlist] Aborting request to reorder playlist: failed to find current item in new playlist")
        return playlistErrorDidOccur()
      }

      // Rather than try actually move things around, just:
      // - Clear the entire playlist:
      let clearRC = mpv.command(.playlistClear)
      guard clearRC == 0 else {
        return playlistErrorDidOccur(clearRC, opDesc: "clear playlist to reorder")
      }

      // - Insert the new "currently playing" item, then work backwards (up the playlist) to insert the preceding items:
      for i in (0..<currentPlayingIndexNew).reversed() {
        let returnCode = mpv.playlistInsert(allItemsNew[i].path, index: 0)
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "insert to reorder playlist")
        }
      }
      // - Finally just append all the items after (AKA below) the current item
      for i in currentPlayingIndexNew + 1..<allItemsNew.count {
        let returnCode = mpv.playlistAppend(allItemsNew[i].path)
        guard returnCode == 0 else {
          return playlistErrorDidOccur(returnCode, opDesc: "append to reorder playlist")
        }
      }

      info.currentPlayback = currentPlayback.clone(playlistPos: currentPlayingIndexNew)

      guard syncAndValidatePlaylist(expectedPlaylist: allItemsNew) else { return }

      // 3. Update UI with result, register undo, kick off other post-processing
      pwc.animationPipeline.submitInstantTask { [self] in
        displayedPlaylist = info.playlist                                          // update cached data
        tableUIChange.postNotification(name: playlistTableChangeNotificationName)  // update UI
        postNotification(.iinaPlaylistChanged)
        saveState()

        // Register undo/redo?
        switch undoOption {
        case .ignoreUndoRedo:
          break
        case .clearUndoStack:
          log.debug("[Playlist] Clearing undo stack after 'remove'")
          undoHelper.clearUndoes()
        case .registerUndoRedo:
          undoHelper.register(undoHelper.buildActionName(basedOn: tableUIChange), undo: { [self] in
            playlistReorder(newPlaylist: allItemsOld, .ignoreUndoRedo)
          }, redo: { [self] in
            // Don't want to re-register an undo action
            playlistReorder(newPlaylist: allItemsNew, .ignoreUndoRedo)
          })
        }
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

  /// 1. Gets the up-to-date playlist & `playlist-pos` (now playing item index) from mpv
  ///    & updates `info.currentPlayback?.playlistPos`.
  /// 2. Updates `info.playlist` with the up-to-date playlist
  /// 3. If `expectedPlaylist` is provided, checks that the updated playlist against it and calls `playlistErrorDidOccur`
  ///    if different.
  /// 4. If `thenPostNotification` is true, posts `iinaPlaylistChanged` notification.
  /// 5. If `savePlayerState` is true, saves player state.
  ///
  /// Expected to be called in the `mpv` queue. Use `reloadPlaylist` if calling from other threads.
  @discardableResult
  func _reloadPlaylist(validateAgainst expectedPlaylist: [PlaybackID]? = nil,
                       thenPostNotification: Bool = true,
                       savePlayerState: Bool = true) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return false }
    var actualPlaylist: [PlaybackID] = []
    let playlistCount = mpv.getInt(MPVProperty.playlistCount)
    log.verbose("[Playlist] Reloading with \(playlistCount) items")
    for index in 0..<playlistCount {
      let urlPath = mpv.getString(MPVProperty.playlistNFilename(index))!
      guard let playlistItem = PlaybackID(path: urlPath) else {
        log.error("[Playlist] Item has invalid path, skipping: \(urlPath.pii.quoted)")
        continue
      }
      actualPlaylist.append(playlistItem)
    }

    var passedValidation = true
    if let expectedPlaylist {
      if actualPlaylist == expectedPlaylist {
        info.playlist = expectedPlaylist
      } else {
        passedValidation = false
        info.playlist = actualPlaylist
        log.error("[Playlist] Playlist mismatch! Will clear undo stack to prevent further issues")
        playlistErrorDidOccur()
      }
    } else {
      info.playlist = actualPlaylist
    }

    if let currentPlayback = info.currentPlayback {
      let playlist = info.playlist
      // Make sure `currentPlayback.playlistPos` still points to the playlist index of that item
      if currentPlayback.playlistPos >= 0, currentPlayback.playlistPos < playlist.count, currentPlayback.id == playlist[currentPlayback.playlistPos] {
        // good
      } else {
        // Try to find new index of playlist, becuase we can't reliabily pull it from mpv (so far...)
        // Find matching URLs in playlist. There may be duplicates, so try to grab the closest one to the last known playlistPos ...
        let candidateIndexes = playlist.enumerated().filter { $0.element == currentPlayback.id }.map(\.offset)
        var bestCandidateIndex = Int.max
        for candidateIndex in candidateIndexes {
          if candidateIndex.distance(to: currentPlayback.playlistPos) < bestCandidateIndex {
            bestCandidateIndex = candidateIndex
          }
        }
        if bestCandidateIndex < playlist.count {
          log.debug("[Playlist] After reload, currentPlayback.playlistPos (\(currentPlayback.playlistPos)) no longer matches that item in playlist. Updating it to \(bestCandidateIndex)")
          info.currentPlayback = currentPlayback.clone(playlistPos: bestCandidateIndex)
          DispatchQueue.main.async { [self] in
            pwc?.playlistView.refreshNowPlayingIndex()
          }
        }
      }
    }

    if thenPostNotification, isInteractivePlayer {
      postNotification(.iinaPlaylistChanged)
    }

    if savePlayerState {
      saveState()  // save playlist URLs to prefs
    }
    return passedValidation
  }

  func syncAndValidatePlaylist(expectedPlaylist: [PlaybackID]) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    return _reloadPlaylist(validateAgainst: expectedPlaylist, thenPostNotification: false, savePlayerState: false)
  }

  // MARK: - Other playlist ops

  /// Clears the entire playlist. Usually this closes the player window in the process, so make it un-undoable.
  func clearPlaylist() {
    mpv.queue.async { [self] in
      guard !isStopping else { return }
      log.verbose("[Playlist] Sending 'playlist-clear' cmd to mpv")
      mpv.command(.playlistClear, checkError: false)
      _reloadPlaylist()
      pwc.animationPipeline.submitInstantTask { [self] in
        log.verbose("[Playlist] Clearing undo stack after 'playlist-clear' cmd")
        undoHelper.clearUndoes()
      }
    }
  }

  func playFile(_ path: String) {
    mpv.queue.async { [self] in
      guard !isStopping else { return }
      info.shouldAutoLoadFiles = true
      let returnCode = mpv.command(.loadfile, args: [path, "replace"], checkError: false)
      guard returnCode == 0 else {
        playlistErrorDidOccur(returnCode, opDesc: "load file")
        return
      }
      _reloadPlaylist()
    }
  }

  func playFileInPlaylist(_ pos: Int) {
    mpv.queue.async { [self] in
      guard !isStopping else { return }
      log.verbose("[Playlist] Changing mpv playlist-pos to \(pos)")
      mpv.setInt(MPVProperty.playlistPos, pos)
    }
  }

  func navigateInPlaylist(nextMedia: Bool) {
    mpv.queue.async { [self] in
      guard !isStopping else { return }
      if nextMedia {
        mpv.command(.playlistNext, checkError: false)
      } else {
        // Prev
        let playlistPos = mpv.getInt(MPVProperty.playlistPos)
        if playlistPos == 0 {
          seek(absoluteSecond: 0)
        } else {
          mpv.command(.playlistPrev, checkError: false)
        }
      }
    }
  }

  // MARK: - Utils

  private func playlistErrorDidOccur(_ returnCode: Int32, opDesc: String) {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    let errorString = mpv.errorString(returnCode)
    log.error("[Playlist] Failed to \(opDesc) (will clear undo stack): \(errorString)")
    playlistErrorDidOccur()
  }

  private func playlistErrorDidOccur() {
    SwiftTask { @MainActor in
      undoHelper.clearUndoes()
      reloadPlaylist(savePlayerState: false)
      // Emit the system beep
      log.debug("[Playlist] Emitting system beep for error")
      NSSound.beep()
    }
  }

}
