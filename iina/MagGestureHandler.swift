//
//  MagnificationHandler.swift
//  iina
//
//  Created by Matt Svoboda on 8/31/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Provides Pinch to Zoom feature.
class MagnificationGestureHandler: NSMagnificationGestureRecognizer {

  lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(PlayerWindowController.handleMagnifyGesture(recognizer:)))
  }()

  unowned var pwc: PlayerWindowController! = nil

  // Zoom constants
  private let pinchZoomMultiplier: Double = 1.0
  private let pinchMinZoom: Double = 1.0
  private let pinchMaxZoom: Double = 4.5
  private let pinchMaxPan: Double = 1.0

  // Zoom variables
  private var lastMagnification: CGFloat = 0.0
  private var pinchOriginInWindow: NSPoint?
  private var pinchOriginInVideo: NSPoint?
  private var pinchOriginInVideoUnit: NSPoint?
  private var pinchScale: CGFloat = 1.0
  private var pinchInitialZoom: Double = 1.0

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard !pwc.isInInteractiveMode else { return }
    guard !pwc.isInMiniPlayer || pwc.miniPlayer.isViewportShown else { return }
    guard !pwc.isAnimatingLayoutTransition else { return }

    let pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
    switch pinchAction {

    case .none:
      return

    case .fullScreen:
      // enter/exit fullscreen
      guard !pwc.isInMiniPlayer else { return }  // Disallow full screen toggle from pinch while in music mode
      
      if recognizer.state == .began {
        let wantsEnlarge = recognizer.magnification > 0
        if wantsEnlarge != pwc.isFullScreen {
          recognizer.state = .recognized
          pwc.toggleWindowFullScreen()
        }
      }

    case .windowSizeOrFullScreen:
      guard let window = pwc.window, let screen = window.screen else { return }

      // Check for full screen toggle conditions first
      if !pwc.isInMiniPlayer, recognizer.state != .ended {  // Disallow full screen toggle from pinch while in music mode

        let wantsShrink = recognizer.magnification < 0
        if pwc.isFullScreen, wantsShrink {
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
            let tasks = pwc.buildResizeViewportTasks(to: screen.visibleFrame.size, centerOnScreen: true, duration: Constants.AnimationDuration.standard * 0.25)
            pwc.animationPipeline.submit(tasks)
          }
          return

        } else if !pwc.isFullScreen, recognizer.magnification > 0 {
          let screenFrame = screen.visibleFrame
          let heightIsMax = window.frame.height >= screenFrame.height
          let widthIsMax = window.frame.width >= screenFrame.width
          // If viewport is not locked, the window must be the size of the screen in both directions before triggering full screen.
          // If viewport is locked, window is considered at maximum if either of its sides is filling all the available space in its dimension.
          if (heightIsMax && widthIsMax) || (Preference.bool(for: .lockViewportToVideoSize) && (heightIsMax || widthIsMax)) {
            pwc.isAnimatingLayoutTransition = true
            pwc.toggleWindowFullScreen()
            /// See note above
            recognizer.state = .ended
            pwc.isMagnifying = false
            return
          }
        }
      } else {
        // If full screen wasn't toggled, try scaling window:
        fallthrough
      }

    case .windowSize:
      IINAAnimation.disableAnimation {  // need this to prevent floating OSC from jumping
        let currentMode = pwc.currentLayout.mode
        if currentMode.isFullScreen {
          zoomVideoFromPinchGesture(recognizer, currentMode: currentMode)
        } else {
          pwc.scaleWindowFromPinch(recognizer, currentMode: currentMode)
        }
      }

    }  // end switch
  }

  /// Adjusts the window size as needed to scale the video as specified by `recognizer`.
  fileprivate func zoomVideoFromPinchGesture(_ recognizer: NSMagnificationGestureRecognizer, currentMode: PlayerWindowMode) {
    guard let window = pwc.window else { return }

    switch recognizer.state {

    case .began:
      // Fullscreen: pinch to zoom video around the pinch origin.
      lastMagnification = recognizer.magnification
      pinchScale = 1.0

      let currentZoom = pwc.player.mpv.getDouble(MPVOption.Video.videoZoom)
      pinchInitialZoom = max(pinchMinZoom, 1.0 + currentZoom)
      // Only update the pinch origin if starting from baseline; otherwise keep the prior origin to reduce jumps.
      if pinchInitialZoom <= pinchMinZoom {
        pinchOriginInWindow = recognizer.location(in: window.contentView)
        pinchOriginInVideo = clampedVideoPoint(fromWindowPoint: pinchOriginInWindow ?? .zero)
        pinchOriginInVideoUnit = normalizedVideoPoint(fromWindowPoint: pinchOriginInWindow ?? .zero)
      }
    case .changed:
      pinchScale = recognizer.magnification + 1.0
      applyVideoZoom(scaleMultiplier: pinchScale)
      lastMagnification = recognizer.magnification
    case .ended:
      applyVideoZoom(scaleMultiplier: pinchScale)
    case .cancelled, .failed:
      break
    default:
      break
    }
  }

  private func clampedVideoPoint(fromWindowPoint point: NSPoint) -> NSPoint {
    let viewPoint = pwc.videoView.convert(point, from: pwc.window?.contentView)
    let bounds = pwc.videoView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return .zero }

    let videoSize = pwc.player.videoGeo.videoSizeDisplay
    let fitSize = videoSize.shrink(toSize: bounds.size)
    let videoRect = fitSize.centeredRect(in: bounds)

    guard videoRect.width > 0, videoRect.height > 0 else { return .zero }

    let clampedX = max(videoRect.minX, min(videoRect.maxX - 1, viewPoint.x))
    let clampedY = max(videoRect.minY, min(videoRect.maxY - 1, viewPoint.y))

    return NSPoint(x: clampedX - videoRect.minX, y: clampedY - videoRect.minY)
  }

  private func normalizedVideoPoint(fromWindowPoint point: NSPoint) -> NSPoint? {
    guard let rect = videoRectInView() else { return nil }
    let clamped = clampedVideoPoint(fromWindowPoint: point)
    guard rect.width > 0, rect.height > 0 else { return nil }
    return NSPoint(x: clamped.x / rect.width, y: clamped.y / rect.height)
  }

  private func videoRectInView() -> NSRect? {
    let bounds = pwc.videoView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let videoSize = pwc.player.videoGeo.videoSizeDisplay
    let fitSize = videoSize.shrink(toSize: bounds.size)
    return fitSize.centeredRect(in: bounds)
  }

  private func applyVideoZoom(scaleMultiplier: CGFloat) {
    let s0 = pinchInitialZoom
    let s1 = min(pinchMaxZoom, max(pinchMinZoom, s0 * Double(scaleMultiplier) * pinchZoomMultiplier))
    let zoomProp = s1 - 1.0

    let origin = pinchOriginInVideoUnit ?? NSPoint(x: 0.5, y: 0.5)
    // Adjust pan to keep the pinch origin under the cursor relative to the current zoom.
    // mpv pan semantics: positive pan-x moves video right; positive pan-y moves video down.
    let invScale = 1.0 / s1
    let newPanX = clampPan(Double(0.5 - origin.x) * (1.0 - invScale))
    let newPanY = clampPan(Double(origin.y - 0.5) * (1.0 - invScale))

    pwc.player.mpv.setDouble(MPVOption.Video.videoZoom, zoomProp, level: .verbose)
    pwc.player.mpv.setDouble(MPVOption.Video.videoPanX, newPanX, level: .verbose)
    pwc.player.mpv.setDouble(MPVOption.Video.videoPanY, newPanY, level: .verbose)

    // If we're effectively back to 1x, forget the stored origin so a new pinch can pick a fresh focal point.
    if s1 <= pinchMinZoom + 0.0001 {
      pinchOriginInWindow = nil
      pinchOriginInVideo = nil
      pinchOriginInVideoUnit = nil
    }
  }

  private func clampPan(_ value: Double) -> Double {
    return min(pinchMaxPan, max(-pinchMaxPan, value))
  }
}

extension PlayerWindowController {
  fileprivate func scaleWindowFromPinch(_ recognizer: NSMagnificationGestureRecognizer, currentMode: PlayerWindowMode) {

    // avoid zero and negative numbers because they will cause problems
    let targetScale = max(0.0001, recognizer.magnification + 1.0)

    switch recognizer.state {

    case .began:
      isMagnifying = true

      // Save current window frame. All updates until the end of this session will operate on this.
      if currentMode == .musicMode {
        musicModeGeo = musicModeGeoForCurrentFrame()
      } else {
        windowedModeGeo = windowedGeoForCurrentFrame()
      }

      scaleVideoFromPinchGesture(to: targetScale, currentMode: currentMode)

    case .changed:
      guard isMagnifying else { return }
      scaleVideoFromPinchGesture(to: targetScale, currentMode: currentMode)

    case .ended:
      guard isMagnifying else { return }
      scaleVideoFromPinchGesture(to: targetScale, currentMode: currentMode, submitResult: true)
      isMagnifying = false

    case .cancelled, .failed:
      guard isMagnifying else { return }
      scaleVideoFromPinchGesture(to: 1.0, currentMode: currentMode)
      isMagnifying = false

    default:
      return
    }
  }

  private func scaleVideoFromPinchGesture(to targetScale: CGFloat, currentMode: PlayerWindowMode,
                                          submitResult: Bool = false) {
    /// For best experience for the user, do not check `isAnimatingLayoutTransition` at state `began` (i.e., allow it to
    /// start keeping track  of pinch), but do not allow this method to execute (i.e. do not respond) until after layout
    /// transitions are complete.
    guard !isAnimatingLayoutTransition else { return }

    let outputGeo: PWinGeometry

    // If in music mode but playlist is not visible, allow scaling up to screen size like regular windowed mode.
    // If playlist is visible, do not resize window beyond current window height
    if currentMode == .musicMode {
      miniPlayer.loadIfNeeded()

      guard miniPlayer.isViewportShown else {
        log.verbose("Window is in music mode but video not visible. Ignoring pinch gesture")
        return
      }
      let inputWidth = musicModeGeo.windowFrame.width
      let desiredWidth = (inputWidth * targetScale).rounded()
      outputGeo = musicModeGeo.scalingVideo(toWidth: desiredWidth)
      log.verbose("Scaling pinched video in music mode, scale=\(targetScale) reqWidth=\(desiredWidth) → result=\(outputGeo)")

    } else {
      let originalGeo = windowedModeGeo
      
      let newViewportSize = originalGeo.viewportSize.multiplyThenRound(targetScale)
      outputGeo = originalGeo.scalingViewport(to: newViewportSize, screenFit: .stayInside, mode: currentMode)
      log.verbose("Scaling pinched video in windowed mode, scale=\(targetScale) → result=\(outputGeo)")
    }
    setFrameAndUpdateWindowSubviews(using: outputGeo, submitUpdate: submitResult)
  }

}
