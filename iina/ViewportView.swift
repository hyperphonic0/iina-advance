//
//  ViewportView.swift
//  iina
//
//  Created by Matt Svoboda on 11/24/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class ViewportView: NSView {
  unowned var player: PlayerCore!

  init() {
    super.init(frame: .zero)
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var playerWindowController: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    playerWindowController?.mouseDown(with: event)
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseDragged(with event: NSEvent) {
    super.mouseDragged(with: event)
    playerWindowController?.mouseDragged(with: event)
  }

  // Need to forward this so that dragging to resize sidebar works in native full screen
  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    playerWindowController?.mouseUp(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    super.rightMouseDown(with: event)
    playerWindowController?.rightMouseDown(with: event)
  }

  override func rightMouseUp(with event: NSEvent) {
    playerWindowController?.rightMouseUp(with: event)
    super.rightMouseUp(with: event)
  }

  override func pressureChange(with event: NSEvent) {
    playerWindowController?.pressureChange(with: event)
    super.pressureChange(with: event)
  }

  override func otherMouseDown(with event: NSEvent) {
    playerWindowController?.otherMouseDown(with: event)
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    playerWindowController?.otherMouseUp(with: event)
    super.otherMouseUp(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return player.acceptFromPasteboard(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }
}

extension PlayerWindowController {
  /// Need to call this after adding a new subview to `viewportView` to ensure ordering of subviews is correct.
  func sortViewportViewSubviews() {
    for possibleSubview in [viewportTopSpacer, viewportBottomSpacer, viewportLeadingSpacer, viewportTrailingSpacer,
                            pip.overlayView,
                            videoView,
                            defaultAlbumArtView,
                            additionalInfoView,
                            osd.osdView] {
      if viewportView.containsSubview(possibleSubview) {
        viewportView.addSubview(possibleSubview, positioned: .above, relativeTo: nil)
      }
    }
  }

  func addToViewportViewThenSortSubviews(_ newSubview: NSView) {
    viewportView.addSubview(newSubview)
    sortViewportViewSubviews()
  }

}
