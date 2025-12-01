//
//  CropBoxView.swift
//  iina
//
//  Created by lhc on 22/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

final class CropBoxView: NSView, DraggableObject {

  weak var settingsViewController: CropBoxViewController!

  /** Original video size. */
  var originalVideoSize: NSSize = NSZeroSize
  /** Crop box's frame. */
  private var boxRect: NSRect = NSZeroRect

  var selectedRect: NSRect = NSZeroRect

  // Is dragging to resize existing selection
  var isDraggingToResize = false
  private var dragSide: DragSide = .top

  // Is dragging to create new selection
  var isDraggingNew = false
  private var lastMousePos: NSPoint?

  private enum DragSide {
    case top, bottom, left, right
  }

  // top and bottom are related to view's coordinate
  private var rectTop: NSRect = NSZeroRect
  private var rectBottom: NSRect = NSZeroRect
  private var rectLeft: NSRect = NSZeroRect
  private var rectRight: NSRect = NSZeroRect

  // MARK: - Rect size settings

  override func viewWillDraw() {
    // Update layout from latest sizes
    updateBoxRect()
    updateCursorRects()
    updateSelectedRect()
    settingsViewController.selectedRectUpdated()
    super.viewWillDraw()
  }

  // set boxRect, and update selectedRect
  private func boxRectChanged(to rect: NSRect) {
    boxRect = rect
    updateSelectedRect()
    settingsViewController.selectedRectUpdated()
  }

  // set selectedRect, and update boxRect
  func setSelectedRect(to rect: NSRect) {
    selectedRect = rect
    updateBoxRect()
    updateCursorRects()
    settingsViewController.selectedRectUpdated()
  }

  // FIXME: these 2 functions below can result in major imprecisions!
  // The biggest problem shows up when un-flipping the y value.
  // To see this, start with a full selectedRect and drag the bottom up until only
  // the top 10% of the video is selected. The y value in the UI will be in double digits.

  // update selectedRect from (boxRect in displayedVideoSize)
  private func updateSelectedRect() {
    let displayedVideoSize = bounds
    guard displayedVideoSize.width > 0, displayedVideoSize.height > 0 else { return }
    let xScale = originalVideoSize.width / displayedVideoSize.width
    let yScale = originalVideoSize.height / displayedVideoSize.height

    var ix = (boxRect.origin.x * xScale).rounded()
    var iy = (boxRect.origin.y * xScale).rounded()
    var iw = (boxRect.width * xScale).rounded()
    var ih = (boxRect.height * yScale).rounded()

    if abs(ix) <= 4 { ix = 0 }
    if abs(iy) <= 4 { iy = 0 }
    if abs(iw + ix - originalVideoSize.width) <= 4 { iw = originalVideoSize.width - ix }
    if abs(ih + iy - originalVideoSize.height) <= 4 { ih = originalVideoSize.height - iy }

    selectedRect = NSMakeRect(ix, iy, iw, ih)
//    Logger.log("originalVideoSize: \(originalVideoSize), boxRect: \(boxRect) -> selectedRect: \(selectedRect) <-")
  }

  // update boxRect from (videoRect * selectedRect)
  private func updateBoxRect() {
    let displayedVideoSize = bounds
    guard originalVideoSize.width > 0, originalVideoSize.height > 0 else { return }  // avoid NaN values!

    let xScale =  displayedVideoSize.width / originalVideoSize.width
    let yScale =  displayedVideoSize.height / originalVideoSize.height

    let ix = selectedRect.minX * xScale
    let iy = selectedRect.minY * xScale
    let iw = selectedRect.width * xScale
    let ih = selectedRect.height * yScale

    boxRect = NSMakeRect(ix, iy, iw, ih)
//    Logger.log("originalVideoSize: \(originalVideoSize) -> boxRect: \(boxRect) <- selectedRect: \(selectedRect)")
  }

  // MARK: - Mouse event to change boxRect

  override func mouseDown(with event: NSEvent) {
    guard let pwc = settingsViewController.pwc else { return }
    pwc.currentDragObject = self

    let mousePosInView = convert(event.locationInWindow, from: nil)
    lastMousePos = mousePosInView

    if rectTop.contains(mousePosInView) {
      isDraggingToResize = true
      dragSide = .top
    } else if rectBottom.contains(mousePosInView) {
      isDraggingToResize = true
      dragSide = .bottom
    } else if rectLeft.contains(mousePosInView) {
      isDraggingToResize = true
      dragSide = .left
    } else if rectRight.contains(mousePosInView) {
      isDraggingToResize = true
      dragSide = .right
    } else if isMousePoint(mousePosInView, in: bounds) {
      // free select
      isDraggingNew = true
      window?.invalidateCursorRects(for: self)
    } else {
      super.mouseDown(with: event)
    }
    if isDraggingToResize || isDraggingNew {
      settingsViewController.pwc.currentDragObject = self
    }
    pwc.log.verbose("CropBoxView mouseDown, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)")
  }

  override func mouseDragged(with event: NSEvent) {
    let mousePosInView = convert(event.locationInWindow, from: nil).constrained(to: bounds)
    guard let pwc = settingsViewController.pwc else { return }
    guard pwc.currentDragObject == self else { return }
    pwc.log.trace{"CropBoxView mouseDragged, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)"}

    if isDraggingToResize {
      // resizing selected box
      var newBoxRect = boxRect
      switch dragSide {
      case .top:
        let diff = mousePosInView.y - lastMousePos!.y
        newBoxRect.origin.y += diff
        newBoxRect.size.height -= diff

      case .bottom:
        let diff = mousePosInView.y - lastMousePos!.y
        newBoxRect.size.height += diff

      case .right:
        let diff = mousePosInView.x - lastMousePos!.x
        newBoxRect.size.width += diff

      case .left:
        let diff = mousePosInView.x - lastMousePos!.x
        newBoxRect.origin.x += diff
        newBoxRect.size.width -= diff
      }

      boxRectChanged(to: newBoxRect)
      updateCursorRects()
      lastMousePos = mousePosInView
      needsDisplay = true
    } else if isDraggingNew {
      // free selecting
      let startingMousePos = lastMousePos!
      let newBoxRect: NSRect
      if startingMousePos.distance(to: mousePosInView) <= Constants.Window.minInitialDragThreshold {
        // snap to no selection if min distance not met
        newBoxRect = NSRect(origin: startingMousePos, size: CGSizeZero)
      } else {
        newBoxRect = NSRect(vertexPoint: startingMousePos, and: mousePosInView)
      }
      boxRectChanged(to: newBoxRect)
      needsDisplay = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    Logger.log.verbose("CropBoxView mouseUp, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)")
    guard let pwc = settingsViewController.pwc else { return }

    if isDraggingToResize || isDraggingNew {
      mouseDragged(with: event)
      isDraggingToResize = false
      isDraggingNew = false
      updateCursorRects()
    } else {
      super.mouseUp(with: event)
    }

    if pwc.currentDragObject == self {
      pwc.currentDragObject = nil
    }
  }

  func cancelDrag() {
    Logger.log.verbose("CropBoxView: cancelling drag")
    isDraggingToResize = false
    isDraggingNew = false
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSColor.controlAccentColor.setStroke()
    NSColor.cropBoxFill.setFill()

    let path = NSBezierPath(rect: boxRect)
    path.lineWidth = 2
    path.fill()
    path.stroke()
  }

  // MARK: - Cursor rects

  override func resetCursorRects() {
    addCursorRect(rectTop, cursor: .resizeUpDown)
    addCursorRect(rectBottom, cursor: .resizeUpDown)
    addCursorRect(rectLeft, cursor: .resizeLeftRight)
    addCursorRect(rectRight, cursor: .resizeLeftRight)
  }

  private func updateCursorRects() {
    // FIXME: these are actually half their stated values because the cursor rects cannot go outside the bounds of this view
    let x = boxRect.origin.x
    let y = boxRect.origin.y
    let w = boxRect.size.width
    let h = boxRect.size.height
    rectTop = NSMakeRect(x, y-4, w, 8).standardized
    rectBottom = NSMakeRect(x, y+h-4, w, 8).standardized
    rectLeft = NSMakeRect(x-4, y+4, 8, h-8).standardized
    rectRight = NSMakeRect(x+w-4, y+4, 8, h-8).standardized

    window?.invalidateCursorRects(for: self)
  }

}
