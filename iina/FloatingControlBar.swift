//
//  FloatingControlBar.swift
//  iina
//
//  Created by lhc on 16/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

final class FloatingControlBarVisualEffectView: NSVisualEffectView, @MainActor DraggableObject {
  let controlBar: FloatingControlBar

  init(_ controlBar: FloatingControlBar) {
    self.controlBar = controlBar
    super.init(frame: .zero)
    blendingMode = .withinWindow
    material = .popover
    state = .active
    wantsLayer = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { Preference.bool(for: .videoViewAcceptsFirstMouse) }
  override func mouseDown(with event: NSEvent) { controlBar.mouseDown(with: event) }
  override func mouseDragged(with event: NSEvent) { controlBar.mouseDragged(with: event) }
  override func mouseUp(with event: NSEvent) { controlBar.mouseUp(with: event) }
  func cancelDrag() { controlBar.cancelDrag() }
}

@available(macOS 26.0, *)
final class FloatingControlBarGlassEffectView: NSGlassEffectView, @MainActor DraggableObject {
  let controlBar: FloatingControlBar

  init(_ controlBar: FloatingControlBar, style desiredStyle: Style) {
    self.controlBar = controlBar
    super.init(frame: .zero)
    if desiredStyle == .clear {
      style = .clear
    } else {
      style = .regular
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { Preference.bool(for: .videoViewAcceptsFirstMouse) }
  override func mouseDown(with event: NSEvent) { controlBar.mouseDown(with: event) }
  override func mouseDragged(with event: NSEvent) { controlBar.mouseDragged(with: event) }
  override func mouseUp(with event: NSEvent) { controlBar.mouseUp(with: event) }
  func cancelDrag() { controlBar.cancelDrag() }
}

// The control bar when position=="floating"
final class FloatingControlBar {
  static let barHeight: CGFloat = 67
  static let minBarWidth: CGFloat = 200
  private static let margin: CGFloat = CGFloat(max(0, Preference.integer(for: .floatingControlBarMargin)))

  static var preferredBarWidth: CGFloat { max(FloatingControlBar.minBarWidth, CGFloat(Preference.float(for: .floatingControlBarWidth))) }

  var view: NSView!

  var pwc: PlayerWindowController? { view.pwc }

  let topRowView = ClickThroughStackView()
  let bottomRowView = ClickThroughStackView()

  fileprivate var xConstraint: NSLayoutConstraint!  // this is X CENTER of OSC
  fileprivate var yConstraint: NSLayoutConstraint!  // Bottom of OSC

  var preferredWidthConstraint: NSLayoutConstraint!
  let leadingMarginConstraint = OptionalConstraint("OSC-Floating-LeadingMargin")
  let trailingMarginConstraint = OptionalConstraint("OSC-Floating-TrailingMargin")
  let bottomMarginConstraint = OptionalConstraint("OSC-Floating-BottomMargin")

  private var minDragDistanceMet = false
  var mousePosRelatedToView: CGPoint?
  var mouseDownLocationInWindow: CGPoint?
  private var isAlignFeedbackSent = false

  var isDragging: Bool { view.pwc?.currentDragObject == view }

  func rebuildView() {
    if let prevView = self.view {
      prevView.removeFromSuperview()
      prevView.removeAllSubviews()
    }

    let subviews = [topRowView, bottomRowView]

    let view: NSView
    if #available(macOS 26, *) {
      let osdGlassView = FloatingControlBarGlassEffectView(self, style: .clear)
      // MacOS Tahoe's style favors rounder corners. Try to fit in
      let contentView = NSView()
      osdGlassView.contentView = contentView
      contentView.subviews = subviews
      view = osdGlassView
      view.roundCorners(withRadius: Constants.liquidGlassCornerRadius)
    } else {
      view = FloatingControlBarVisualEffectView(self)
      view.roundCorners(withRadius: 6)
      view.subviews = subviews
    }

    view.idString = "OSC-Floating"
    view.translatesAutoresizingMaskIntoConstraints = false

    topRowView.addConstraintsToFillSuperview(top: 4, leading: 10, trailing: 10)
    topRowView.idString = "OSC-Floating-TopRow"

    bottomRowView.addConstraintsToFillSuperview(bottom: 1, leading: 10, trailing: 10)
    bottomRowView.setHuggingPriority(.required, for: .vertical)
    bottomRowView.idString = "OSC-Floating-BottomRow"

    let rowsEqHeightCon = topRowView.heightAnchor.constraint(equalTo: bottomRowView.heightAnchor, multiplier: 1)
    rowsEqHeightCon.isActive = true

    let rowsVertAlignCon = bottomRowView.topAnchor.constraint(equalTo: topRowView.bottomAnchor, constant: -10)
    rowsVertAlignCon.isActive = true

    let heightEqCon = view.heightAnchor.constraint(equalToConstant: FloatingControlBar.barHeight)
    heightEqCon.isActive = true
    preferredWidthConstraint?.isActive = false
    preferredWidthConstraint = view.widthAnchor.constraint(equalToConstant: FloatingControlBar.preferredBarWidth)
    preferredWidthConstraint.priority = .init(300)
    preferredWidthConstraint.isActive = true
    let minWidthConstraint = view.widthAnchor.constraint(greaterThanOrEqualToConstant: FloatingControlBar.minBarWidth)
    minWidthConstraint.isActive = true

    self.view = view
  }

  init() {
    for stackView in [topRowView, bottomRowView] {
      stackView.orientation = .horizontal
      stackView.alignment = .centerY
      stackView.distribution = .gravityAreas
      stackView.spacing = 0
      stackView.detachesHiddenViews = false
      stackView.translatesAutoresizingMaskIntoConstraints = false
    }

    rebuildView()
  }
  
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @MainActor
  func updatePreferredBarWidth() {
    preferredWidthConstraint.animateToConstant(FloatingControlBar.preferredBarWidth)
  }

  /// Adds margin constraints if missing
  @MainActor
  func addOrUpdateMarginConstraints(for layout: LayoutState) {
    guard let pwc, let contentView = pwc.window?.contentView else { return }
    pwc.log.verbose("Updating floating OSC constraints: leadingSidebarVisible=\(layout.leadingSidebar.isVisible.yn) traillingSidebarVisible=\(layout.leadingSidebar.isVisible.yn)")
    leadingMarginConstraint.weaken()
    trailingMarginConstraint.weaken()
    bottomMarginConstraint.weaken()

    let leadingConstraintSecondAnchor = layout.leadingSidebar.isVisible ? pwc.leadingSidebarView.trailingAnchor : contentView.leadingAnchor
    leadingMarginConstraint.createOrUpdate(to: FloatingControlBar.margin, priorityInt: 1000, requiredSecondAnchor: leadingConstraintSecondAnchor, pwc.log) { [self] c in
      view.leadingAnchor.constraint(greaterThanOrEqualTo: leadingConstraintSecondAnchor, constant: c)
    }

    let traillingConstraintFirstAnchor = layout.trailingSidebar.isVisible ? pwc.trailingSidebarView.leadingAnchor : contentView.trailingAnchor

    trailingMarginConstraint.createOrUpdate(to: FloatingControlBar.margin, priorityInt: 1000, requiredSecondAnchor: traillingConstraintFirstAnchor, pwc.log) { [self] c in
      traillingConstraintFirstAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor, constant: c)
    }

    bottomMarginConstraint.createOrUpdate(to: FloatingControlBar.margin, priorityInt: 1000, requiredSecondAnchor: traillingConstraintFirstAnchor, pwc.log) { [self] c in
      contentView.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor, constant: c)
    }
  }

  @MainActor
  func removeFloatingControlBar() {
    view.removeFromSuperview()
    leadingMarginConstraint.remove(pwc?.log)
    trailingMarginConstraint.remove(pwc?.log)
    bottomMarginConstraint.remove(pwc?.log)
  }

  // MARK: - Positioning

  @MainActor
  fileprivate func moveToLocationRatio(parentGeo: PWinGeometry) {
    guard view.superview != nil, let xConstraint, let yConstraint else { return }

    let ratioH = Preference.double(for: .controlBarPositionHorizontal)
    let ratioV = Preference.double(for: .controlBarPositionVertical)

    guard ratioH >= 0 && ratioH <= 1 else {
      pwc?.log.error("FloatingOSC: cannot update position; centerRatioH is invalid: \(ratioH)")
      return
    }
    guard ratioV >= 0 && ratioV <= 1 else {
      pwc?.log.error("FloatingOSC: cannot update position; originRatioV is invalid: \(ratioV)")
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
  @MainActor
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

  @MainActor
  func mouseDown(with event: NSEvent) {
    guard let pwc, let geometry = buildFloatingGeometry() else { return }

    pwc.log.verbose("FloatingOSC mouseDown")
    view.window?.isMovableByWindowBackground = false
    mousePosRelatedToView = view.convert(event.locationInWindow, from: nil)
    mouseDownLocationInWindow = event.locationInWindow
    let originInViewport = pwc.viewportView.convert(view.frame.origin, from: nil)
    let threshold = geometry.availableWidth * Constants.floatingControllerSnapToCenterThresholdMultiplier
    isAlignFeedbackSent = abs(originInViewport.x - (pwc.viewportView.frame.width - view.frame.width) / 2) <= threshold

    // Claim this now to signal to other things that nothing else should drag:
    pwc.currentDragObject = view
    // Reset flag
    minDragDistanceMet = false
  }

  @MainActor
  func mouseDragged(with event: NSEvent) {
    guard let mousePosRelatedToView,
          let mouseDownLocationInWindow,
          let pwc,
          let geometry = buildFloatingGeometry() else {
      return
    }
    assert(xConstraint != nil && yConstraint != nil, "xConstraint or yConstraint is nil!")

    if !minDragDistanceMet {
      let dragDistance = mouseDownLocationInWindow.distance(to: event.locationInWindow)
      guard dragDistance >= Constants.Window.minInitialDragThreshold else { return }
      pwc.log.verbose("FloatingOSC mouseDrag: minimum dragging distance was met")
      minDragDistanceMet = true
    }
    assert(isDragging, "Something's wrong: isDragging should be true here")

    let currentLocInViewport = pwc.viewportView.convert(event.locationInWindow, from: nil)
    let xxx = currentLocInViewport.x - mousePosRelatedToView.x

    var newCenterX = (view.userInterfaceLayoutDirection == .rightToLeft ? geometry.maxCenterX - xxx : xxx + geometry.halfBarWidth)
    let newOriginY = currentLocInViewport.y - mousePosRelatedToView.y
    // stick to center
    if Preference.bool(for: .controlBarStickToCenter) {
      let xPosWhenCenter = geometry.centerX
      let threshold = geometry.availableWidth * Constants.floatingControllerSnapToCenterThresholdMultiplier
      pwc.log.trace("Floating OSC snap distanceToCenter=\(newCenterX - xPosWhenCenter) threshold=\(threshold)")
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

  @MainActor
  func mouseUp(with event: NSEvent) {
    guard let pwc, let geometry = buildFloatingGeometry()  else { return }
    if isDragging {
      pwc.log.verbose("FloatingOSC mouseUp: ending drag")
      pwc.currentDragObject = nil
    } else {
      pwc.log.verbose("FloatingOSC mouseUp")
    }

    if event.clickCount == 2 {
      // Double-clicked: center the OSC
      let (xConst, yConst) = geometry.calculateConstraintConstants(centerX: geometry.centerX, originY: view.frame.origin.y)

      // apply position
      xConstraint.animateToConstant(xConst)
      yConstraint.animateToConstant(yConst)

      updateRatios(xConst: xConst, yConst: yConst, geometry)
    } else {
      updateRatios(xConst: xConstraint.constant, yConst: yConstraint.constant, geometry)
    }
  }

  @MainActor
  func cancelDrag() {
    guard let geometry = buildFloatingGeometry() else { return }
    updateRatios(xConst: xConstraint.constant, yConst: yConstraint.constant, geometry)
  }

  // MARK: - Coordinates in Viewport

  fileprivate func buildFloatingGeometry() -> FloatingControlBarGeometry? {
    guard let pwc else { return nil }
    let currentLayout = pwc.currentLayout
    guard currentLayout.hasFloatingOSC else { return nil }
    // TODO: Consolidate duplicate code [#PWinGeoForAnyMode]
    let pwinGeo = currentLayout.isFullScreen ? pwc.fullScreenGeo() : pwc.windowedGeoForCurrentFrame()
    return FloatingControlBarGeometry(parentGeo: pwinGeo)
  }

  @MainActor
  fileprivate struct FloatingControlBarGeometry {
    let parentGeo: PWinGeometry
    let preferredBarWidth: CGFloat = FloatingControlBar.preferredBarWidth

    // "available" == space to move OSC within
    var availableWidthMinX: CGFloat {
      return parentGeo.insideBars.leading + FloatingControlBar.margin
    }

    var availableWidthMaxX: CGFloat {
      let viewportMaxX = parentGeo.viewportSize.width
      let trailingUsedSpace = parentGeo.insideBars.trailing + FloatingControlBar.margin
      return max(viewportMaxX - trailingUsedSpace, FloatingControlBar.margin + FloatingControlBar.minBarWidth)
    }

    var availableWidth: CGFloat {
      return availableWidthMaxX - availableWidthMinX
    }

    var barWidth: CGFloat {
      if availableWidth < preferredBarWidth {
        return FloatingControlBar.minBarWidth
      }
      return preferredBarWidth
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
      return FloatingControlBar.margin
    }

    var maxOriginY: CGFloat {
      let maxYWithoutTopBar = parentGeo.viewportSize.height - FloatingControlBar.barHeight - FloatingControlBar.margin
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

} // end class FloatingControlBar

// MARK: - PlayerWindowController

extension PlayerWindowController {

  func addFloatingControlBarToViewportView() {
    guard !viewportView.containsSubview(controlBarFloating.view) else { return }

    log.verbose("Adding controlBarFloating to contentView")
    viewportView.addSubview(controlBarFloating.view)
    sortViewportViewSubviews()

    controlBarFloating.xConstraint?.isActive = false
    controlBarFloating.yConstraint?.isActive = false

    let newY = viewportView.bottomAnchor.constraint(equalTo: controlBarFloating.view.bottomAnchor, constant: 60)
    newY.identifier = "FloatingOSC-BtmY-Con"
    newY.priority = .defaultHigh
    controlBarFloating.yConstraint = newY

    let newX = controlBarFloating.view.centerXAnchor.constraint(equalTo: viewportView.leadingAnchor, constant: 330)
    newX.identifier = "FloatingOSC-CenterX-Con"
    newX.priority = .init(450)
    controlBarFloating.xConstraint = newX

    newY.isActive = true
    newX.isActive = true
  }

  func adjustFloatingControllerOrigin(for targetGeometry: PWinGeometry? = nil) {
    guard let window = window else { return }
    guard controlBarFloating.view.superview != nil else { return }

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
                    - fragPlaybackBtnsView.frame.width
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
