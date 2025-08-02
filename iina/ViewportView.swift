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

  let topSpacer = SpacerView(id: "ViewportTopSpacer")
  let bottomSpacer = SpacerView(id: "ViewportBottomSpacer")
  let leadingSpacer = SpacerView(id: "ViewportLeadingSpacer")
  let trailingSpacer = SpacerView(id: "ViewportTrailingSpacer")

  init() {
    super.init(frame: .zero)
    idString = "ViewportView"
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
    initVideoViewSpacers()
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

  // MARK: - Spacers

  func initVideoViewSpacers() {
    // These don't seem to matter. But set to reasonable values:
    let ch: Float = 250
    trailingSpacer.setContentHugging(h: ch, v: ch)
    leadingSpacer.setContentHugging(h: ch, v: ch)
    topSpacer.setContentHugging(h: ch, v: ch)
    bottomSpacer.setContentHugging(h: ch, v: ch)
    let ccr: Float = 250
    trailingSpacer.setCCResistance(h: ccr, v: ccr)
    leadingSpacer.setCCResistance(h: ccr, v: ccr)
    topSpacer.setCCResistance(h: ccr, v: ccr)
    bottomSpacer.setCCResistance(h: ccr, v: ccr)
    
    // Reduce the unused dimension of each spacer to keep it well-defined
    topSpacer.widthAnchor.constraint(equalToConstant: 0).isActive = true
    bottomSpacer.widthAnchor.constraint(equalToConstant: 0).isActive = true
    leadingSpacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
    trailingSpacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
  }

  func addSpacers() {
    player.log.verbose("[Load] Adding videoView spacers to viewportView")
    if !subviews.contains(topSpacer) {
      addSubview(topSpacer)
      topSpacer.addConstraintsToFillSuperview(top: 0, leading: 0)
    }
    if !subviews.contains(bottomSpacer) {
      addSubview(bottomSpacer)
      bottomSpacer.addConstraintsToFillSuperview(bottom: 0, trailing: 0)
    }
    if !subviews.contains(leadingSpacer) {
      addSubview(leadingSpacer)
      leadingSpacer.addConstraintsToFillSuperview(top: 0, leading: 0)
    }
    if !subviews.contains(trailingSpacer) {
      addSubview(trailingSpacer)
      trailingSpacer.addConstraintsToFillSuperview(top: 0, trailing: 0)
    }
  }

  func removeSpacers() {
    topSpacer.removeFromSuperview()
    bottomSpacer.removeFromSuperview()
    leadingSpacer.removeFromSuperview()
    trailingSpacer.removeFromSuperview()
  }

}

extension PlayerWindowController {

  /// Need to call this after adding a new subview to `viewportView` to ensure ordering of subviews is correct.
  func sortViewportViewSubviews() {
    let possibleSubviews = [viewportView.topSpacer, viewportView.bottomSpacer, viewportView.leadingSpacer, viewportView.trailingSpacer,
                            pip.overlayView,
                            videoView,
                            defaultAlbumArtView,
                            additionalInfoView,
                            osd.osdView]
    let correctOrderedSubviews = possibleSubviews.filter { viewportView.containsSubview($0) }
    for subview in correctOrderedSubviews {
      viewportView.addSubview(subview, positioned: .above, relativeTo: nil)
    }
  }

}
