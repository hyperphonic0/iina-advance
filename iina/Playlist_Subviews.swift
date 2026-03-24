//
//  Playlist_Subviews.swift
//  iina
//
//  Created by Matt Svoboda on 2026-01-27.
//  Copyright © 2026 lhc. All rights reserved.
//
//  Custom classes for use in PlaylistView, ChaptersView.

class PlaylistTrackCellView: NSTableCellView {
  @IBOutlet weak var subBtn: NSButton!
  @IBOutlet weak var subBtnWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var subBtnTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var prefixBtn: PlaylistPrefixButton!
  @IBOutlet weak var infoLabel: EditableTextField!  /// use `EditableTextField` class for proper highlight color
  @IBOutlet weak var infoLabelTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var durationLabel: EditableTextField!
  @IBOutlet weak var playbackProgressView: PlaylistPlaybackProgressView!

  func setPrefix(_ prefix: String?, textColor: NSColor? = nil) {
    prefixBtn.contentTintColor = textColor

    if let prefix {
      prefixBtn.hasPrefix = true
      prefixBtn.text = prefix
      prefixBtn.isHidden = false
    } else {
      prefixBtn.hasPrefix = false
      prefixBtn.isHidden = true
    }
  }

  func setDisplaySubButton(_ show: Bool) {
    if show {
      subBtn.isHidden = false
      subBtnWidthConstraint.constant = 12
      subBtnTrailingConstraint.constant = 4
    } else {
      subBtn.isHidden = true
      subBtnWidthConstraint.constant = 0
      subBtnTrailingConstraint.constant = 0
    }
  }

  func setAdditionalInfo(_ string: String?, textColor: NSColor? = nil) {
    if let string = string {
      infoLabel.isHidden = false
      infoLabelTrailingConstraint.constant = 4
      infoLabel.setFormattedText(stringValue: string, textColor: textColor)
      infoLabel.stringValue = string
      infoLabel.toolTip = string
    } else {
      infoLabel.isHidden = true
      infoLabelTrailingConstraint.constant = 0
      infoLabel.stringValue = ""
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    playbackProgressView.percentage = 0
    playbackProgressView.isHidden = true
    playbackProgressView.needsDisplay = true
    setPrefix(nil)
    setAdditionalInfo(nil)
  }
}


class PlaylistPrefixButton: NSButton {

  var text = "" {
    didSet {
      refresh()
    }
  }

  var hasPrefix = true {
    didSet {
      refresh()
    }
  }

  var isFolded = true {
    didSet {
      refresh()
    }
  }

  private func refresh() {
    self.title = hasPrefix ? (isFolded ? "…" : text) : ""
  }

}


class SubPopoverViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var playlistTableView: NSTableView!

  unowned var player: PlayerCore!
  var pwc: PlayerWindowController! { player.pwc }

  var filePath: String = ""

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return false
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let matchedSubs = player.info.getMatchedSubs(filePath) else { return nil }
    return matchedSubs[row].lastPathComponent
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.getMatchedSubs(filePath)?.count ?? 0
  }

  @IBAction func wrongSubBtnAction(_ sender: AnyObject) {
    player.info.$matchedSubs.withLock { $0[filePath]?.removeAll() }
    tableView.reloadData()
    let playlist = pwc.playlistView.displayedPlaylist
    if let row = playlist.firstIndex(where: { $0.path == filePath }) {
      playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
    }
  }
}

class ChapterTableCellView: NSTableCellView {
  @IBOutlet weak var durationTextField: EditableTextField!
}

final class PlaylistView: NSView, DraggableObject {
  override func mouseDragged(with event: NSEvent) {
    // Send to view controller (above)
    nextResponder?.mouseDragged(with: event)
  }

  func cancelDrag() {
    guard let pwc, let sidebar = pwc.getConfiguredSidebar(forTabGroup: .playlist) else { return }
    pwc.log.verbose("Cancelled drag of playlist sidebar")
    pwc.finishResizingSidebar(sidebar.locationID)
  }

}
