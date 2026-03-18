//
//  MagnificationHandler.swift
//  iina
//
//  Created by Matt Svoboda on 8/31/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Combine

// Zoom constants
private let pinchZoomMultiplier: Double = 1.0  // increase to accelerate zoom
private let pinchMinZoom: Double = 1.0
private let pinchMinZoomForPan: Double = pinchMinZoom + 0.0001
private let panSpeed: Double = 2.3
private let zoomResetFPS = 1.0 / 60

/// Provides Pinch to Zoom feature.
final class MagnificationGestureHandler: NSMagnificationGestureRecognizer {

  lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(PlayerWindowController.handleMagnifyGesture(recognizer:)))
  }()

  unowned var pwc: PlayerWindowController! = nil

  /// Only used for PinchActions `.windowSize`, `.windowSizeOrFullScreen`.
  /// Only needs to be updated at start of each pinch gesture: only used for the life of the gesture.
  private var currrentResizeOperation: ResizeOperation = .none

  fileprivate enum ResizeOperation {
    case none
    case videoZoom
    case windowScale
  }

  // Zoom variables
  private var pinchOriginInWindow: NSPoint?
  private var pinchOriginInVideo: NSPoint?
  private var pinchOriginInVideoUnit: NSPoint?
  private var currentPinchScale: CGFloat = 1.0
  /// The video-zoom value at the start of the most recent pinch
  private var pinchInitialZoom: Double = 1.0
  private var pinchMaxZoom: Double = 1.0  // will be updated at start of every pinch gesture

  /// Timer used to generate crude "zoom out" operation to reset the video-zoom when window is resized.
  private var resetTimerSubscription: AnyCancellable?

  private enum PanAxis {
    case x
    case y
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard !pwc.isInInteractiveMode else {
      pwc.isMagnifying = false
      return
    }
    // If in music mode, viewport must be shown to allow scaling window
    guard !pwc.isInMiniPlayer || pwc.miniPlayer.isViewportShown else {
      pwc.isMagnifying = false
      return
    }
    guard !pwc.isAnimatingLayoutTransition, !pwc.isApplyingPWinGeo else {
      pwc.isMagnifying = false
      return
    }
    guard pwc.animationPipeline.enableRunning, !pwc.animationPipeline.isExecuting else {
      // Need to reset this in case the "ended" event was received after some new animation started
      pwc.isMagnifying = false
      return
    }

    let pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
    switch pinchAction {

    case .none:
      return

    case .fullScreen:
      // enter/exit fullscreen

      // Disallow full screen toggle from pinch while in music mode
      guard !pwc.isInMiniPlayer else { return }

      if recognizer.state == .began {
        let wantsToGrow = recognizer.magnification > 0
        if wantsToGrow != pwc.isFullScreen {
          recognizer.state = .recognized
          pwc.toggleWindowFullScreen()
        }
      }

    case .windowSize,
        .windowSizeOrFullScreen:

      if recognizer.state == .began {
        currrentResizeOperation = chooseOperationForNewGesture(pinchAction, recognizer)
        pwc.log.verbose("Pinch gesture started: resizeOperation=\(currrentResizeOperation)")
      }  // end BEGAN

      switch currrentResizeOperation {
      case .none:
        return
      case .videoZoom:
        zoomVideoFromPinchGesture(recognizer, currentMode: pwc.currentLayout.mode)
      case .windowScale:
        IINAAnimation.disableAnimation {  // need this to prevent floating OSC from jumping
          pwc.scaleWindowFromPinch(recognizer, currentMode: pwc.currentLayout.mode)
        }
      }

    }  // end switch
  }

  private func chooseOperationForNewGesture(_ pinchAction: Preference.PinchAction,
                                            _ recognizer: NSMagnificationGestureRecognizer) -> ResizeOperation {
    assert(pinchAction == .windowSize || pinchAction == .windowSizeOrFullScreen)
    guard let window = pwc.window, let screen = window.screen else { return .none }

    let wantsToShrink = recognizer.magnification < 0
    let wantsToGrow = recognizer.magnification > 0
    let isPinchToZoomEnabled = Preference.bool(for: .enablePinchToVideoZoom)

    if pwc.isFullScreen {
      if pwc.isZoomedViaGesture {
        // If zoom is already in progress, give it priority
        return .videoZoom
      } else if wantsToShrink && pinchAction == .windowSizeOrFullScreen {
        // Exit FS and end the current gesture
        /// Change `windowedModeGeo` so that the window still fills the screen after leaving full screen, rather than whatever size it was
        pwc.windowedModeGeo = pwc.windowedModeGeo.clone(windowFrame: screen.visibleFrame, screenID: screen.screenID)
        // Set this immediately instead of waiting for the transitionn to set it (to disable window resize listeners).
        // (seems to prevent hiccups in the animation):
        pwc.isAnimatingLayoutTransition = true
        // Exit FS:
        pwc.toggleWindowFullScreen()
        /// Force the gesture to end after toggling FS. Window scaling via `scaleWindow` looks terrible when overlapping FS animation
        // TODO: put effort into truly seamless window scaling which also can toggle legacy FS
        recognizer.state = .ended
        pwc.isMagnifying = false  // really need to work hard to stop future events

        // KLUDGE! AppKit does not give us the correct visibleFrame until after we have exited FS. The resulting window (as of MacOS 14.4)
        // is 6 pts too tall. For now, run another quick resize after exiting FS using the (now) correct visibleFrame
        pwc.animationPipeline.submitInstantTask{ [self] in
          let tasks = pwc.buildResizeViewportTasks(to: screen.visibleFrame.size, centerOnScreen: true,
                                                   duration: Constants.AnimationDuration.standard * 0.25)
          pwc.animationPipeline.submit(tasks)
        }
        return .none
      } else if isPinchToZoomEnabled {
        // Will do nothing if already at min zoom
        return .videoZoom
      }
      return .none
    } else if !pwc.isInMiniPlayer, GeoUtil.isWindowMaximized(windowFrame: window.frame, in: screen) {
      // Maximized window in windowed mode
      if wantsToGrow, pinchAction == .windowSizeOrFullScreen {
        // Enter FS and end the current gesture.
        // Favor this over any kind of video zoom.
        pwc.isAnimatingLayoutTransition = true
        pwc.toggleWindowFullScreen()
        /// See note above
        recognizer.state = .ended
        pwc.isMagnifying = false
        return .none
      } else if isPinchToZoomEnabled, wantsToGrow || pwc.isZoomedViaGesture {
        // Continue zooming if already zoomed; otherwise start via expand pinch motion
        return .videoZoom
      }
    }
    return .windowScale
  }


  // MARK: - Video Zoom

  /// Pinch-to-zoom is only enabled while window is maximized on screen.
  /// Checks if the window (described by the gien geomeetry) is still maximized on screen, and if not, resets the zoom & pan values to zero.
  /// Makes no changes if pinch-to-zoom was not used (e.g., if zoomed using mpv key commands).
  func resetZoomIfNotMaximized(_ targetGeo: PWinGeometry) {
    // Don't reset if still magnifying
    guard !pwc.isMagnifying else { return }
    guard pwc.isZoomedViaGesture, !targetGeo.mode.isFullScreen else { return }

    if let screen = NSScreen.forScreenID(targetGeo.screenID),
       GeoUtil.isWindowMaximized(windowFrame: targetGeo.windowFrame, in: screen) {
      return
    }
    resetZoom()
  }

  func resetZoom() {
    guard pwc.isZoomedViaGesture else { return }
    pwc.log.verbose("Resetting pinch-to-zoom props (video-zoom, video-pan-x, video-pan-y)")

    // Cancel any prev timer first
    resetTimerSubscription?.cancel()

    guard let currentZoom = getCurrentZoomFromMPV() else { return }
    // Shrink the zoom by this multiplier at every redraw (1.0 == no change)
    currentPinchScale = 1.0 - (zoomResetFPS * currentZoom)
    let currentMode = pwc.currentLayout.mode

    pwc.isMagnifying = true

    resetTimerSubscription = Timer.publish(every: zoomResetFPS, on: .main, in: .common)
      .autoconnect()
      .sink { [self] time in
        guard pwc.isZoomedViaGesture else {
          pwc.log.verbose("Cancelling timer: no longer zoomed")
          pwc.isMagnifying = false
          resetTimerSubscription?.cancel()
          return
        }
        guard let currentZoom = getCurrentZoomFromMPV() else {
          pwc.log.verbose("Cancelling timer: no zoom from mpv!")
          pwc.isMagnifying = false
          resetTimerSubscription?.cancel()
          return
        }
        pinchInitialZoom = currentZoom
        applyVideoZoom(currentMode: currentMode, submitResult: false)
      }
  }

  /// Returns current value of `video-zoom`, converted to linear scale. Returns `nil` if player is not available.
  fileprivate func getCurrentZoomFromMPV() -> Double? {
    guard pwc.player.isActive else { return nil }
    return pwc.player.getVideoZoom().clamped(to: pinchMinZoom...)
  }

  /// Adjusts the window size as needed to scale the video as specified by `recognizer`.
  /// This assumes the window is already full screen or maximized.
  @MainActor
  fileprivate func zoomVideoFromPinchGesture(_ recognizer: NSMagnificationGestureRecognizer, currentMode: PlayerWindowMode) {
    guard let window = pwc.window else { return }

    switch recognizer.state {

    case .began, .changed:
      // Group these two cases to match the logic in `scaleWindowFromPinch`. See the comments there for why we do this.

      if pwc.isMagnifying {
        // Already magnifying: treat as `.changed`
        currentPinchScale = recognizer.magnification + 1.0
        applyVideoZoom(currentMode: currentMode)
      } else {
        // Begin magnifying: pinch to zoom video around the pinch origin.
        pwc.isMagnifying = true
        currentPinchScale = 1.0
        // Update from prefs
        pinchMaxZoom = Preference.double(for: .pinchMaxZoom)

        if currentMode.isWindowed, Preference.bool(for: .lockViewportToVideoSize) {
          // Update cached copy: we will reference them as we zoom
          pwc.windowedModeGeo = pwc.windowedGeoForCurrentFrame()
        }

        guard let currentZoom = getCurrentZoomFromMPV() else { return }
        pinchInitialZoom = max(pinchMinZoom, currentZoom)
        // Only update the pinch origin if starting from baseline; otherwise keep the prior origin to reduce jumps.
        if pinchInitialZoom <= pinchMinZoom {
          pinchOriginInWindow = recognizer.location(in: window.contentView)
          pinchOriginInVideo = clampedVideoPoint(fromWindowPoint: pinchOriginInWindow ?? .zero)
          pinchOriginInVideoUnit = normalizedVideoPoint(fromWindowPoint: pinchOriginInWindow ?? .zero)
        }
      }
    case .ended:
      applyVideoZoom(currentMode: currentMode, submitResult: true)
      pwc.isMagnifying = false
    case .cancelled, .failed:
      pwc.isMagnifying = false
    default:
      pwc.isMagnifying = false
    }
  }

  @MainActor
  private func clampedVideoPoint(fromWindowPoint point: NSPoint) -> NSPoint {
    let viewPoint = pwc.videoView.convert(point, from: pwc.window?.contentView)
    let bounds = pwc.videoView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return .zero }

    let videoSize = pwc.geo.video.videoSizeDisplay
    let fitSize = videoSize.shrink(toSize: bounds.size)
    let videoRect = fitSize.centeredRect(in: bounds)

    guard videoRect.width > 0, videoRect.height > 0 else { return .zero }

    let clampedX = max(videoRect.minX, min(videoRect.maxX - 1, viewPoint.x))
    let clampedY = max(videoRect.minY, min(videoRect.maxY - 1, viewPoint.y))

    return NSPoint(x: clampedX - videoRect.minX, y: clampedY - videoRect.minY)
  }

  @MainActor
  private func normalizedVideoPoint(fromWindowPoint point: NSPoint) -> NSPoint? {
    guard let rect = videoRectInView() else { return nil }
    let clamped = clampedVideoPoint(fromWindowPoint: point)
    guard rect.width > 0, rect.height > 0 else { return nil }
    return NSPoint(x: clamped.x / rect.width, y: clamped.y / rect.height)
  }

  @MainActor
  private func videoRectInView() -> NSRect? {
    let bounds = pwc.videoView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let videoSize = pwc.geo.video.videoSizeDisplay
    let fitSize = videoSize.shrink(toSize: bounds.size)
    return fitSize.centeredRect(in: bounds)
  }

  private func applyVideoZoom(currentMode: PlayerWindowMode, submitResult: Bool = false) {
    let oldZoom = pinchInitialZoom
    let newZoom = (oldZoom * Double(currentPinchScale) * pinchZoomMultiplier).clamped(to: pinchMinZoom...pinchMaxZoom)
    let bounds = pwc.videoView.bounds
    let rect = videoRectInView() ?? bounds
    pwc.log.trace("Zooming from pinch: \(oldZoom) -> \(newZoom)")

    let origin = pinchOriginInVideoUnit ?? NSPoint(x: 0.5, y: 0.5)
    // Adjust pan to keep the pinch origin under the cursor relative to the current zoom.
    // mpv pan semantics: positive pan-x moves video right; positive pan-y moves video down.
    let marginX = panMargin(forScale: newZoom, rect: rect, bounds: bounds, axis: .x)
    let marginY = panMargin(forScale: newZoom, rect: rect, bounds: bounds, axis: .y)
    let newPanX = clampPan(Double(0.5 - origin.x), reach: marginX)
    let newPanY = clampPan(Double(origin.y - 0.5), reach: marginY)

    guard pwc.player.isActive else { return }
    pwc.player.setVideoZoom(to: newZoom)
    pwc.player.mpv.setDouble(MPVOption.Video.videoPanX, newPanX, level: .verbose)
    pwc.player.mpv.setDouble(MPVOption.Video.videoPanY, newPanY, level: .verbose)

    // If we're effectively back to 1x, forget the stored origin so a new pinch can pick a fresh focal point.
    if newZoom <= pinchMinZoomForPan {
      pinchOriginInWindow = nil
      pinchOriginInVideo = nil
      pinchOriginInVideoUnit = nil
    }

    pwc.isZoomedViaGesture = newZoom > pinchMinZoom

    // TODO: this correctly scales the window to match the zoom, but breaks when other parts of the layout system
    // resize the window on their own...
#if ENABLE_RESIZE_ON_ZOOM_WITH_LOCKED_VIEWPORT
    // If lockViewportToVideoSize applies, we need to resize the window frame as we zoom
    if currentMode.isWindowed, Preference.bool(for: .lockViewportToVideoSize) {
      IINAAnimation.disableAnimation {
        let originalGeo: PWinGeometry = pwc.windowedModeGeo
        let screenFrame = pwc.window!.screen!.visibleFrame

        let outputGeo = originalGeo.scalingViewport(to: screenFrame.size, screenFit: .stayInside, videoZoom: newZoom)
        pwc.log.verbose("Scaling pinched video in windowed mode, zoom=\(newZoom) → result=\(outputGeo)")
        pwc.applyPWinGeometry(outputGeo, submitUpdate: submitResult)
      }
    }
#endif
  }

  private func clampPan(_ value: Double, reach: Double) -> Double {
    let limit = 0.5 - reach
    guard limit > 0 else { return 0 }
    return min(limit, max(-limit, value))
  }

  private func clampedNormalizedCenter(_ value: Double, reach: Double) -> Double {
    return min(1.0 - reach, max(reach, value))
  }

  private func panMargin(forScale scale: Double, rect: NSRect, bounds: NSRect, axis: PanAxis) -> Double {
    guard scale > 1.0 else { return 0.5 }
    guard rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return 0.5 / scale }

    let aspectVideo = rect.width / rect.height
    let aspectView = bounds.width / bounds.height
    let fillX: Double
    let fillY: Double
    if aspectVideo > aspectView {
      fillX = 1.0
      fillY = aspectView / aspectVideo
    } else {
      fillX = aspectVideo / aspectView
      fillY = 1.0
    }

    let fill = (axis == .x) ? fillX : fillY
    let reach = 0.5 / (scale * fill)
    return min(0.5, max(0.0, reach))
  }

  /// Provides video panning while zoomed (via vertical/horizontal scroll)
  func handlePanGesture(with event: NSEvent) -> Bool {
    guard event.hasPreciseScrollingDeltas else { return false }
    guard event.momentumPhase.isEmpty else { return true }
    guard pwc.player.isActive else { return false }
    guard Preference.bool(for: .enablePinchToVideoZoom) else { return false }

    guard let zoom = getCurrentZoomFromMPV() else { return false }
    pwc.log.trace("Panning while zoomed (zoom=\(zoom))")
    guard zoom > pinchMinZoomForPan else { return false }

    guard let rect = videoRectInView(), rect.width > 0, rect.height > 0 else { return false }
    let bounds = pwc.videoView.bounds

    var deltaX = event.scrollingDeltaX
    var deltaY = event.scrollingDeltaY

    if event.isDirectionInvertedFromDevice {
      deltaX = -deltaX
      deltaY = -deltaY
    }

    let normalizedDeltaX = Double(deltaX) * panSpeed / (Double(rect.width) * zoom)
    let normalizedDeltaY = -Double(deltaY) * panSpeed / (Double(rect.height) * zoom)

    if abs(normalizedDeltaX) < 0.000001 && abs(normalizedDeltaY) < 0.000001 {
      return true
    }

    let currentPanX = pwc.player.mpv.getDouble(MPVOption.Video.videoPanX)
    let currentPanY = pwc.player.mpv.getDouble(MPVOption.Video.videoPanY)

    let marginX = panMargin(forScale: zoom, rect: rect, bounds: bounds, axis: .x)
    let marginY = panMargin(forScale: zoom, rect: rect, bounds: bounds, axis: .y)

    let currentCenterX = 0.5 - currentPanX
    let currentCenterY = 0.5 + currentPanY

    let newCenterX = clampedNormalizedCenter(currentCenterX + normalizedDeltaX, reach: marginX)
    let newCenterY = clampedNormalizedCenter(currentCenterY + normalizedDeltaY, reach: marginY)

    let newPanX = clampPan(0.5 - newCenterX, reach: marginX)
    let newPanY = clampPan(newCenterY - 0.5, reach: marginY)

    pwc.player.mpv.setDouble(MPVOption.Video.videoPanX, newPanX, level: .verbose)
    pwc.player.mpv.setDouble(MPVOption.Video.videoPanY, newPanY, level: .verbose)

    pinchOriginInVideoUnit = NSPoint(x: newCenterX, y: newCenterY)

    return true
  }
}

// MARK: - Scale Window

extension PlayerWindowController {
  fileprivate func scaleWindowFromPinch(_ recognizer: NSMagnificationGestureRecognizer, currentMode: PlayerWindowMode) {

    // Avoid zero and negative numbers because they will cause problems.
    // Round to 6 decimal places: mpv doesn't support finer grained behavior, so anything beyond that is just noise.
    let targetScale = max(0.0001, recognizer.magnification + 1.0).roundedTo6()

    switch recognizer.state {

    case .began, .changed:
      // Need to group these two cases together, because we may ignore the actual `.begin` event (not to mentio first
      // several `.changed` events) if we are not ready to start zooming when the pinch starts (due to an animation which
      // is completing or other situations). See the `guard` statements at the start of `handleMagnifyGesture`.
      // We use our `isMagnifying` variable to know when we have actually begun our pinch handling.
      if !isMagnifying {
        isMagnifying = true

        // Save current window frame. All updates until the end of this session will operate on this.
        if currentMode == .musicMode {
          miniPlayer.loadIfNeeded()
          musicModeGeo = musicModeGeoForCurrentFrame(force: true)
        } else if currentMode.isWindowed {
          windowedModeGeo = windowedGeoForCurrentFrame(force: true)
        }
      }

      scaleWindowFromPinchGesture(targetVideoScale: targetScale, currentMode: currentMode)

    case .ended:
      scaleWindowFromPinchGesture(targetVideoScale: targetScale, currentMode: currentMode, submitResult: true)
      isMagnifying = false

    case .cancelled, .failed:
      scaleWindowFromPinchGesture(targetVideoScale: 1.0, currentMode: currentMode)
      isMagnifying = false

    default:
      isMagnifying = false
    }
  }

  private func scaleWindowFromPinchGesture(targetVideoScale: CGFloat, currentMode: PlayerWindowMode,
                                           submitResult: Bool = false) {
    /// For best experience for the user, do not check `isAnimatingLayoutTransition` at state `began` (i.e., allow it to
    /// start keeping track  of pinch), but do not allow this method to execute (i.e. do not respond) until after layout
    /// transitions are complete.
    assert(!isAnimatingLayoutTransition && !isApplyingPWinGeo,
           "Should never get here if either isAnimatingLayoutTransition (\(isAnimatingLayoutTransition)) or isApplyingPWinGeo (\(isApplyingPWinGeo)) is true!")

    let originalGeo: PWinGeometry
    if currentMode == .musicMode {
      originalGeo = musicModeGeo
    } else {
      originalGeo = windowedModeGeo
    }
    let newViewportSize = originalGeo.viewportSize.multiplyThenRound(targetVideoScale)
    let outputGeo = originalGeo.scalingViewport(to: newViewportSize, screenFit: .stayInside)
    log.verbose("Scaling window from pinch gesture: mode=\(currentMode) scale=\(targetVideoScale) → result=\(outputGeo)")
    applyPWinGeometry(outputGeo, submitUpdate: submitResult)
  }

}
