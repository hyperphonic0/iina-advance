//
//  FloatingControlBarView.swift
//  iina
//
//  Created by lhc on 16/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

// The control bar when position=="floating"
class FloatingControlBarView: NSVisualEffectView, DraggableObject {
  private static let barHeight: CGFloat = 67
  private static let minBarWidth: CGFloat = 200
  private static let preferredBarWidth: CGFloat = 440
  private static let margin: CGFloat = CGFloat(max(0, Preference.integer(for: .floatingControlBarMargin)))

  let topRowView = ClickThroughStackView()
  let bottomRowView = ClickThroughStackView()
  let playButtonsContainerView = ClickThroughStackView()

  var xConstraint: NSLayoutConstraint!  // this is X CENTER of OSC
  var yConstraint: NSLayoutConstraint!  // Bottom of OSC

  weak var leadingMarginConstraint: NSLayoutConstraint!
  weak var trailingMarginConstraint: NSLayoutConstraint!
  weak var bottomMarginConstraint: NSLayoutConstraint!

  private var minDragDistanceMet = false
  var mousePosRelatedToView: CGPoint?
  var mouseDownLocationInWindow: CGPoint?

  var isDragging: Bool {
    return playerWindowController?.currentDragObject == self
  }

  private var isAlignFeedbackSent = false

  private var playerWindowController: PlayerWindowController? {
    return window?.windowController as? PlayerWindowController
  }

  private var viewportView: NSView? {
    return playerWindowController?.viewportView
  }

  init() {
    super.init(frame: .zero)
    idString = "OSC-Floating"
    blendingMode = .withinWindow
    material = .popover
    state = .active

    if #available(macOS 26, *) {
      roundCorners(withRadius: 10)
    } else {
      roundCorners(withRadius: 6)
    }

    subviews = [topRowView, bottomRowView]

    for stackView in [topRowView, bottomRowView, playButtonsContainerView] {
      stackView.orientation = .horizontal
      stackView.alignment = .centerY
      stackView.distribution = .gravityAreas
      stackView.spacing = 0
      stackView.detachesHiddenViews = false
      stackView.translatesAutoresizingMaskIntoConstraints = false
    }

    topRowView.addConstraintsToFillSuperview(top: 4, leading: 10, trailing: 10)
    topRowView.idString = "OSC-Floating-TopRow"

    bottomRowView.addConstraintsToFillSuperview(bottom: 1, leading: 10, trailing: 10)
    bottomRowView.setHuggingPriority(.required, for: .vertical)
    bottomRowView.idString = "OSC-Floating-BottomRow"

    // playButtonsContainerView
    topRowView.addView(playButtonsContainerView, in: .center)
    playButtonsContainerView.setClippingResistancePriority(.init(500), for: .horizontal)
    playButtonsContainerView.setHuggingPriority(.init(500), for: .vertical)
    playButtonsContainerView.idString = "OSC-Floating-PlayBtnsContainer"

    let rowsEqHeightCon = topRowView.heightAnchor.constraint(equalTo: bottomRowView.heightAnchor, multiplier: 1)
    rowsEqHeightCon.isActive = true

    let rowsVertAlignCon = bottomRowView.topAnchor.constraint(equalTo: topRowView.bottomAnchor, constant: -10)
    rowsVertAlignCon.isActive = true

    translatesAutoresizingMaskIntoConstraints = false
    let heightEqCon = heightAnchor.constraint(equalToConstant: FloatingControlBarView.barHeight)
    heightEqCon.isActive = true
    let widthEqCon = widthAnchor.constraint(equalToConstant: 440)
    widthEqCon.priority = .init(300)
    widthEqCon.isActive = true
    let widthGT = widthAnchor.constraint(greaterThanOrEqualToConstant: FloatingControlBarView.minBarWidth)
    widthGT.isActive = true
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Adds margin constraints if missing
  func addOrUpdateMarginConstraints(for layout: LayoutState) {
    guard let pwc = playerWindowController, let contentView = pwc.window?.contentView else { return }
    pwc.log.verbose{"Updating floating OSC constraints: leadingSidebarVisible=\(layout.leadingSidebar.isVisible.yn) traillingSidebarVisible=\(layout.leadingSidebar.isVisible.yn)"}

    let leadingConstraintSecondAnchor = layout.leadingSidebar.isVisible ? pwc.leadingSidebarView.trailingAnchor : contentView.leadingAnchor
    if leadingMarginConstraint == nil || !leadingMarginConstraint.isActive || (leadingMarginConstraint?.secondAnchor != leadingConstraintSecondAnchor) {
      leadingMarginConstraint?.isActive = false
      leadingMarginConstraint = self.leadingAnchor.constraint(greaterThanOrEqualTo: leadingConstraintSecondAnchor, constant: FloatingControlBarView.margin)
    }

    let traillingConstraintFirstAnchor = layout.trailingSidebar.isVisible ? pwc.trailingSidebarView.leadingAnchor : contentView.trailingAnchor
    if trailingMarginConstraint == nil || !trailingMarginConstraint.isActive || (trailingMarginConstraint?.firstAnchor != traillingConstraintFirstAnchor) {
      trailingMarginConstraint?.isActive = false
      trailingMarginConstraint = traillingConstraintFirstAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor, constant: FloatingControlBarView.margin)
    }
    if bottomMarginConstraint == nil || !bottomMarginConstraint.isActive {
      bottomMarginConstraint?.isActive = false
      bottomMarginConstraint = self.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: FloatingControlBarView.margin)
    }
    bottomMarginConstraint.isActive = true
    leadingMarginConstraint.isActive = true
    trailingMarginConstraint.isActive = true
  }

  func removeMarginConstraints() {
    if let leadingMarginConstraint {
      leadingMarginConstraint.isActive = false
      self.leadingMarginConstraint = nil
    }
    if let trailingMarginConstraint {
      trailingMarginConstraint.isActive = false
      self.trailingMarginConstraint = nil
    }
    if let bottomMarginConstraint {
      bottomMarginConstraint.isActive = false
      self.bottomMarginConstraint = nil
    }
  }

  // MARK: - Positioning

  func moveToLocationRatio(parentGeo: PWinGeometry) {
    guard superview != nil, let xConstraint, let yConstraint else { return }

    let ratioH = Preference.double(for: .controlBarPositionHorizontal)
    let ratioV = Preference.double(for: .controlBarPositionVertical)

    guard ratioH >= 0 && ratioH <= 1 else {
      if let playerWindowController {
        playerWindowController.log.error("FloatingOSC: cannot update position; centerRatioH is invalid: \(ratioH)")
      }
      return
    }
    guard ratioV >= 0 && ratioV <= 1 else {
      if let playerWindowController {
        playerWindowController.log.error("FloatingOSC: cannot update position; originRatioV is invalid: \(ratioV)")
      }
      return
    }

    let geometry = FloatingControlBarGeometry(parentGeo: parentGeo)
    let availableWidth = geometry.availableWidth
    let centerX = geometry.minCenterX + ((availableWidth - geometry.barWidth) * ratioH)
    let originY = geometry.minOriginY + (ratioV * (geometry.maxOriginY - geometry.minOriginY))
    let (xConst, yConst) = geometry.calculateConstraintConstants(centerX: centerX, originY: originY)
//    Logger.log("Setting xConstraint to: \(xConst), from \(geometry.minCenterX) + ((\(availableWidth) - \(geometry.barWidth)) * \(ratioH))", level: .verbose)
    xConstraint.animateToConstant(xConst)
    yConstraint.animateToConstant(yConst)
    updateRatios(xConst: xConst, yConst: yConst, geometry)
  }

  /// Converts the relative offsets of `xConst` and `yConst` into ratios into available space in the range [0...1]
  private func updateRatios(xConst: CGFloat, yConst: CGFloat, _ geometry: FloatingControlBarGeometry) {
    let minCenterX = geometry.minCenterX

    // save final position
    let ratioH = (xConst - minCenterX) / (geometry.availableWidth - geometry.barWidth)
    let minOriginY = geometry.minOriginY
    let ratioV = (yConst - minOriginY) / (geometry.maxOriginY - minOriginY)
    //    Logger.log("Drag: Setting ratioH to: (\(xConst) - \(minCenterX)) / (\(geometry.availableWidth) - \(geometry.barWidth)) = \(ratioH)", level: .verbose)

    // Save to prefs as future default
    Preference.set(ratioH, for: .controlBarPositionHorizontal)
    Preference.set(ratioV, for: .controlBarPositionVertical)
  }

  // MARK: - Mouse Events

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  override func mouseDown(with event: NSEvent) {
    guard let pwc = playerWindowController else { return }

    pwc.log.verbose("FloatingOSC mouseDown")
    window?.isMovableByWindowBackground = false
    mousePosRelatedToView = self.convert(event.locationInWindow, from: nil)
    mouseDownLocationInWindow = event.locationInWindow
    assert(pwc.currentLayout.isWindowed, "FloatingOSC mouseDown called in non-windowed mode!")
    let windowedGeo = pwc.windowedGeoForCurrentFrame()
    let geometry = FloatingControlBarGeometry(parentGeo: windowedGeo)
    let originInViewport = pwc.viewportView.convert(frame.origin, from: nil)
    let threshold = geometry.availableWidth * Constants.Distance.floatingControllerSnapToCenterThresholdMultiplier
    isAlignFeedbackSent = abs(originInViewport.x - (pwc.viewportView.frame.width - frame.width) / 2) <= threshold

    // Claim this now to signal to other things that nothing else should drag:
    pwc.currentDragObject = self
    // Reset flag
    minDragDistanceMet = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mousePosRelatedToView,
          let mouseDownLocationInWindow,
          let pwc = playerWindowController else {
      return
    }
    assert(xConstraint != nil && yConstraint != nil, "xConstraint or yConstraint is nil!")

    if !minDragDistanceMet {
      let dragDistance = mouseDownLocationInWindow.distance(to: event.locationInWindow)
      guard dragDistance >= Constants.Window.minInitialDragThreshold else { return }
      pwc.log.verbose{"FloatingOSC mouseDrag: minimum dragging distance was met"}
      minDragDistanceMet = true
    }
    assert(isDragging, "Something's wrong: isDragging should be true here")

    let windowedGeo = pwc.windowedGeoForCurrentFrame()
    let geometry = FloatingControlBarGeometry(parentGeo: windowedGeo)

    let currentLocInViewport = pwc.viewportView.convert(event.locationInWindow, from: nil)
    let xxx = currentLocInViewport.x - mousePosRelatedToView.x

    var newCenterX = (userInterfaceLayoutDirection == .rightToLeft ? geometry.maxCenterX - xxx : xxx + geometry.halfBarWidth)
    let newOriginY = currentLocInViewport.y - mousePosRelatedToView.y
    // stick to center
    if Preference.bool(for: .controlBarStickToCenter) {
      let xPosWhenCenter = geometry.centerX
      let threshold = geometry.availableWidth * Constants.Distance.floatingControllerSnapToCenterThresholdMultiplier
      pwc.log.trace{"Floating OSC snap distanceToCenter=\(newCenterX - xPosWhenCenter) threshold=\(threshold)"}
      if abs(newCenterX - xPosWhenCenter) <= threshold {
        newCenterX = xPosWhenCenter
        if !isAlignFeedbackSent {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
          isAlignFeedbackSent = true
        }
      } else {
        isAlignFeedbackSent = false
      }
    }

    let (xConst, yConst) = geometry.calculateConstraintConstants(centerX: newCenterX, originY: newOriginY)
    xConstraint.constant = xConst
    yConstraint.constant = yConst
  }

  override func mouseUp(with event: NSEvent) {
    guard let pwc = playerWindowController else { return }
    if isDragging {
      pwc.log.verbose("FloatingOSC mouseUp: ending drag")
      pwc.currentDragObject = nil
    } else {
      pwc.log.verbose("FloatingOSC mouseUp")
    }

    let geo = pwc.windowedGeoForCurrentFrame()
    let geometry = FloatingControlBarGeometry(parentGeo: geo)

    if event.clickCount == 2 {
      // Double-clicked: center the OSC
      let (xConst, yConst) = geometry.calculateConstraintConstants(centerX: geometry.centerX, originY: frame.origin.y)

      // apply position
      xConstraint.animateToConstant(xConst)
      yConstraint.animateToConstant(yConst)

      updateRatios(xConst: xConst, yConst: yConst, geometry)
    } else {
      updateRatios(xConst: xConstraint.constant, yConst: yConstraint.constant, geometry)
    }
  }

  func cancelDrag() {
    guard let pwc = playerWindowController else { return }
    let geo = pwc.windowedGeoForCurrentFrame()
    let geometry = FloatingControlBarGeometry(parentGeo: geo)
    updateRatios(xConst: xConstraint.constant, yConst: yConstraint.constant, geometry)
  }

  // MARK: - Coordinates in Viewport

  struct FloatingControlBarGeometry {
    let parentGeo: PWinGeometry

    // "available" == space to move OSC within
    var availableWidthMinX: CGFloat {
      return parentGeo.insideBars.leading + FloatingControlBarView.margin
    }

    var availableWidthMaxX: CGFloat {
      let viewportMaxX = parentGeo.viewportSize.width
      let trailingUsedSpace = parentGeo.insideBars.trailing + FloatingControlBarView.margin
      return max(viewportMaxX - trailingUsedSpace, FloatingControlBarView.margin + FloatingControlBarView.minBarWidth)
    }

    var availableWidth: CGFloat {
      return availableWidthMaxX - availableWidthMinX
    }

    var barWidth: CGFloat {
      if availableWidth < FloatingControlBarView.preferredBarWidth {
        return FloatingControlBarView.minBarWidth
      }
      return FloatingControlBarView.preferredBarWidth
    }

    var halfBarWidth: CGFloat {
      return barWidth / 2
    }

    var minCenterX: CGFloat {
      return availableWidthMinX + halfBarWidth
    }

    // Centered
    var maxCenterX: CGFloat {
      return availableWidthMaxX - halfBarWidth
    }

    var minOriginY: CGFloat {
      // There is no bottom bar is OSC is floating
      return FloatingControlBarView.margin
    }

    var maxOriginY: CGFloat {
      let maxYWithoutTopBar = parentGeo.viewportSize.height - FloatingControlBarView.barHeight - FloatingControlBarView.margin
      let topBarHeight = parentGeo.insideBars.top
      return maxYWithoutTopBar - topBarHeight
    }

    var centerX: CGFloat {
      let minX = minCenterX
      let maxX = maxCenterX
      let availableWidth = maxX - minX
      return minX + (availableWidth * 0.5)
    }

    func calculateConstraintConstants(centerX: CGFloat, originY: CGFloat) -> (CGFloat, CGFloat) {
      let minOriginY = minOriginY
      let minCenterX = minCenterX
      let maxCenterX = maxCenterX
      let maxOriginY = maxOriginY
      // bound to viewport frame
      let constraintRect = NSRect(x: minCenterX, y: minOriginY, width: maxCenterX - minCenterX, height: maxOriginY - minOriginY)
      let newOrigin = CGPoint(x: centerX, y: originY).constrained(to: constraintRect)
      return (newOrigin.x, newOrigin.y)
    }

  }

} // end class FloatingControlBarView

// MARK: - PlayerWindowController

extension PlayerWindowController {

  func adjustFloatingControllerOrigin(for targetGeometry: PWinGeometry? = nil) {
    guard let window = window, currentLayout.hasFloatingOSC else { return }
    guard controlBarFloating.superview != nil else { return }

    let parentGeo = targetGeometry ?? windowedModeGeo
    guard parentGeo.isViewportShown else { return }
    controlBarFloating.moveToLocationRatio(parentGeo: parentGeo)

    // Detach the views in topRowView manually on macOS 11 only; as it will cause freeze
    if #available(macOS 11.0, *) {
      if #unavailable(macOS 12.0) {
        guard let maxWidth = [fragVolumeView, fragToolbarView].compactMap({ $0?.frame.width }).max() else {
          return
        }

        // window - 10 - controlBarFloating
        // controlBarFloating - 12 - topRowView
        let margin: CGFloat = (10 + 12) * 2
        let hide = (window.frame.width
                    - controlBarFloating.playButtonsContainerView.frame.width
                    - maxWidth*2
                    - margin) < 0

        let upper = controlBarFloating.topRowView
        let views = upper.views
        if hide {
          if views.contains(fragVolumeView) {
            upper.removeView(fragVolumeView)
          }
          if views.contains(fragToolbarView) {
            upper.removeView(fragToolbarView)
          }
        } else {
          if !views.contains(fragVolumeView) {
            upper.addView(fragVolumeView, in: .leading)
          }
          if !views.contains(fragToolbarView) {
            upper.addView(fragToolbarView, in: .trailing)
          }
        }
      }
    }
  }

}
