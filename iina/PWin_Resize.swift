//
//  PlayerWinResizeExtension.swift
//  iina
//
//  Created by Matt Svoboda on 12/13/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `PlayerWindowController` geometry functions
extension PlayerWindowController {
  // MARK: - Window Delegate: Zoom

  func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> NSRect {
    let newSize = resizeWindowSubviews(window, to: newFrame.size)
    let newNewFrame = NSRect(origin: newFrame.origin, size: newSize)
    log.verbose{"WindowWillZoom: \(window.frame) → \(newFrame) → \(newNewFrame)"}
    return newNewFrame
  }

  func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
    return windowShouldZoom(window, toFrame: defaultFrame)
  }

  // MARK: - Window Delegate: Resize

  /// NSWindowDelegate: windowWillResize
  ///
  /// # Notes for other NSWindowDelegate notifications:
  /// * `windowDidResize()`: Called after window is resized from (almost) any cause. Ca be called many times during every call to `window.setFrame()`.
  /// Do not use because it interferes with animations in progress.
  /// * `windowDidEndLiveResize`: Never use! It is unreliable. Use `windowDidResize` if anything.
  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    // Trigger forced draws
    videoView.activateForcedRedraws()

    guard !isInWindowResizeDenialPeriod() else {
      log.verbose{"[WinWillResize] Denying request=\(requestedSize): still inside denial period; will stay at \(window.frame.size)"}
      pendingResizeForScreenChange = false  // should be safe to reset this now
      return window.frame.size
    }
    if !window.inLiveResize && isLeftMouseButtonDown {
      // Looks like user is moving the window, but not resizing it. Prevent the system from trying to resize it..
      log.verbose{"[WinWillResize] Denying request=\(requestedSize): left mouseBtn down, but not resizing"}
      return window.frame.size
    }
    // Tweak to improve responsiveness in music mode. Doesn't seem to affect normal windowed mode.
    // FIXME: this still doesn't look great. Maybe tweak VideoView constraints in music mode
    CATransaction.setAnimationDuration(0)

    return resizeWindowSubviews(window, to: requestedSize)
  }

  func restartWindowResizeDenialPeriod(_ reason: String) {
    // Do not allow MacOS to change the window size
    log.verbose{"Restarting window resize denial period due to: \(reason)"}
    denyWindowResizePeriodStartTime = Date()
  }

  func isInWindowResizeDenialPeriod() -> Bool {
    guard !currentLayout.isFullScreen else { return false }
    let timeElapsed = Date().timeIntervalSince(denyWindowResizePeriodStartTime)
    let denyWindowResize = timeElapsed - Constants.TimeInterval.denyWindowResizeTimeout < 0
    log.trace{"Time elapsed=\(timeElapsed), timeout=\(Constants.TimeInterval.denyWindowResizeTimeout) → DenyWinResize=\(denyWindowResize.yn)"}
    return denyWindowResize
  }

  func restartWindowScrollDenialPeriod() {
    // Do not allow MacOS to change the window size
    log.trace{"Restarting window scroll denial period"}
    denyWindowScrollPeriodStartTime = Date()
  }

  func isInWindowScrollDenialPeriod() -> Bool {
    guard !currentLayout.isFullScreen else { return false }
    let timeElapsed = Date().timeIntervalSince(denyWindowScrollPeriodStartTime)
    let denyWindowScroll = timeElapsed - Constants.TimeInterval.denyWindowScrollTimeout < 0
    log.trace{"Time elapsed=\(timeElapsed), timeout=\(Constants.TimeInterval.denyWindowResizeTimeout) → DenyWinScroll=\(denyWindowScroll.yn)"}
    return denyWindowScroll
  }

  func resizeWindowSubviews(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    let currentLayout = currentLayout
    let inLiveResize = window.inLiveResize

    let lockViewportToVideoSize = currentLayout.mode.alwaysLockViewportToVideoSize || Preference.bool(for: .lockViewportToVideoSize)
    log.verbose{"[WinWillResize] \(currentLayout.mode) Curr=\(window.frame.size) Req=\(requestedSize) Live=\(inLiveResize.yn) LockViewport=\(lockViewportToVideoSize.yn)"}

    if lockViewportToVideoSize && inLiveResize {
      /// Notes on the trickiness of live window resize:
      /// 1. We need to decide whether to (A) keep the width fixed, and resize the height, or (B) keep the height fixed, and resize the width.
      /// "A" works well when the user grabs the top or bottom sides of the window, but will not allow resizing if the user grabs the left
      /// or right sides. Similarly, "B" works with left or right sides, but will not work with top or bottom.
      /// 2. We can make all 4 sides allow resizing by first checking if the user is requesting a different height: if yes, use "B";
      /// and if no, use "A".
      /// 3. Unfortunately (2) causes resize from the corners to jump all over the place, because in that case either height or width will change
      /// in small increments (depending on how fast the user moves the cursor) but this will result in a different choice between "A" or "B" schemes
      /// each time, with very different answers, which causes the jumpiness. In this case either scheme will work fine, just as long as we stick
      /// to the same scheme for the whole resize. So to fix this, we add `isLiveResizingWidth`, and once set, stick to scheme "B".
      if isLiveResizingWidth == nil {
        if window.frame.height != requestedSize.height {
          isLiveResizingWidth = false
        } else if window.frame.width != requestedSize.width {
          isLiveResizingWidth = true
        }
      }
      log.verbose{"[WinWillResize] choseWidth=\(self.isLiveResizingWidth?.yn ?? "nil")"}
    }

    let newWindowSize: NSSize
    let isLiveResizingWidth = isLiveResizingWidth ?? true
    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:

      guard !sessionState.isRestoring else {
        log.error{"[WinWillResize] Still restoring; returning existing geo=\(windowedModeGeo.windowFrame.size)"}
        return windowedModeGeo.windowFrame.size
      }
      let currentGeo = windowedGeoForCurrentFrame()
      assert(currentGeo.mode == currentLayout.mode,
             "[WinWillResize] currentGeo.mode (\(currentGeo.mode)) != currentLayout.mode (\(currentLayout.mode))")

      let newGeometry = currentGeo.resizingWindow(to: requestedSize, lockViewportToVideoSize: lockViewportToVideoSize,
                                                  inLiveResize: inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
      newWindowSize = newGeometry.windowFrame.size

      if currentLayout.mode == .windowedNormal {
        // User has resized the video. Assume this is the new preferred resolution until told otherwise. Do not constrain.
        player.info.intendedViewportSize = newGeometry.viewportSize
      }

      /// AppKit calls `setFrame` after this method returns, and we cannot access that code to ensure it is encapsulated
      /// within the same animation transaction as the code below. But the existing `VideoView` constraints should ensure
      /// that everything resizes properly.
      /// Update: need to update `VideoView` layout to ensure that cropbox in interactive mode is resized properly!
      resizeWindowSubviews(using: newGeometry, updateVideoView: true)
      // fall through

    case .fullScreenNormal, .fullScreenInteractive:
      if currentLayout.isNativeFullScreen {
        // This method can be called as a side effect of the animation. If so, ignore.
        return requestedSize
      }

      let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
      newWindowSize = newGeometry.windowFrame.size

      resizeWindowSubviews(using: newGeometry, updateVideoView: true)
      // fall through

    case .musicMode:
      guard !sessionState.isRestoring else {
        log.error{"[WinWillResize] Still restoring; returning existing musicModeGeo=\(musicModeGeo.windowFrame.size)"}
        return musicModeGeo.windowFrame.size
      }

      // Use explicit `videoShown`, `playlistShown`: these are derived from the windowFrame, but when we update from
      // current we can end up with small imprecisions which could alter their values.
      let currentGeo = musicModeGeoForCurrentFrame().cloneMusicMode(videoShown: musicModeGeo.videoShown,
                                                                    playlistShown: musicModeGeo.isMusicModePlaylistVisible)
      let newGeometry = currentGeo.resizingWindowInMusicMode(to: requestedSize,
                                                             inLiveResize: inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
      newWindowSize = newGeometry.windowFrame.size

      /// This call is needed to update any necessary constraints & resize internal views
      applyMusicModeGeo(newGeometry, setFrame: false, save: false)
    }

    log.verbose{"[WinWillResize] Returning size=\(newWindowSize) for \(currentLayout.mode)"}
    return newWindowSize
  }

  /**
   By default, `setFrame()` has its own implicit animation, and this can create an undesirable effect when combined with other animations.
   This function uses a `0` duration animation via the `animationResizeTime` callback to effectively remove the implicit
   default animation.
   • Also resizes window subviews.
   • It will still animate if used inside an `NSAnimationContext` or `IINAAnimation.Task` with non-zero duration.
   • If `notify` is `true`, a `windowDidEndLiveResize` event will be triggered, which is often not desirable!
   */
  func updateWindowFrameAndSubviews(using geometry: PWinGeometry, updateVideoView: Bool = true, notify: Bool = true) {
    let window = (window as? PlayerWindow)!
    resizeWindowSubviews(using: geometry, updateVideoView: updateVideoView)

    guard !window.frame.equalTo(geometry.windowFrame) else {
      log.verbose("[PWin.setFrame] No change to windowFrame; returning")
      return
    }

    log.verbose{"[PWin.setFrame] notify=\(notify.yn) frame=\(geometry.windowFrame)"}
    window.useZeroDurationForNextResize = true
    window.setFrame(geometry.windowFrame, display: true, animate: notify)
  }

  /// Resizes *only* the subviews in the window, not the window frame. Updates other state needed when resizing window.
  func resizeWindowSubviews(using newGeometry: PWinGeometry, updateVideoView: Bool = true) {
    videoView.enterAsynchronousMode()
    if newGeometry.videoShown {
      if updateVideoView {
        // Not sure if this helps fix the aspect constraint transition
        videoView.apply(newGeometry)
      }
      sendWindowScaleToMPV(newGeometry.mpvWindowScale())

      // Update floating control bar position if applicable
      adjustFloatingControllerOrigin(for: newGeometry)
    }

    if newGeometry.mode == .musicMode {
      miniPlayer.loadIfNeeded()
      // Re-evaluate space requirements for labels. May need to start scrolling.
      // Do not save musicModeGeo here! Pinch gesture will handle itself. Drag-to-resize will be handled elsewhere.
      miniPlayer.resetScrollingLabels()
    } else if newGeometry.mode.isInteractiveMode {
      // Update interactive mode selectable box size. Origin is relative to viewport origin
      let newVideoRect = NSRect(origin: CGPointZero, size: newGeometry.videoSize)
      cropSettingsView?.cropBoxView.resized(with: newVideoRect)
    }

    if osd.animationState == .shown {
      updateOSDTextSize(from: newGeometry)
      if player.info.isFileLoadedAndSized {
        setOSDViews()
      }
    }
  }

  /// NSWindowDelegate: start live resize
  func windowWillStartLiveResize(_ notification: Notification) {
    guard !isAnimatingLayoutTransition else { return }
    log.trace{"WindowWillStartLiveResize"}
    isLiveResizingWidth = nil  // reset this
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    log.trace{"WindowDidEndLiveResize"}
  }

  /// Explicitly changes the window frame & window subviews according to `newGeometry` (or generating a geometry if `nil`),
  /// without animation (i.e., immediately).
  /// Do not call in response to WindowWillResize, because this can call `setFrameImmediately`.
  /// Do not call if layout needs to change. For that, use a LayoutTransition.
  ///
  /// Use with non-nil `newGeometry` for: (1) pinch-to-zoom, (2) resizing outside sidebars when the whole window needs to be resized or moved.
  /// Not animated.
  /// Can be used in windowed or full screen modes.
  /// Can be used in music mode only if playlist is hidden.
  func resizeWindowImmediately(using newGeometry: PWinGeometry? = nil) {
    videoView.activateForcedRedraws()
    guard let window else { return }

    let layout = currentLayout
    let isTransientResize = newGeometry != nil
    let isFullScreen = layout.isFullScreen
    log.verbose{"[ResizeWindInstantly] fs=\(isFullScreen.yn) live=\(window.inLiveResize.yn) geo=\(newGeometry?.description ?? "nil")"}

    // These may no longer be aligned correctly. Just hide them
    hideSeekPreviewImmediately()

    let newGeo = newGeometry ?? layout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, video: geo.video)

    if isFullScreen {
      // custom FS
      resizeWindowSubviews(using: newGeo)
    } else {
      /// This will also update `videoView`
      updateWindowFrameAndSubviews(using: newGeo, notify: false)
    }

    if !isFullScreen && !isTransientResize {
      player.saveState()
      if layout.mode == .windowedNormal {
        let newWindScale = newGeo.mpvWindowScale()
        log.verbose{"[ResizeWindInstantly] calling sendWindowScaleToMPV with scale=\(newWindScale)"}
        sendWindowScaleToMPV(newWindScale)
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  // MARK: - Other window geometry functions

  func windowDidResize(_ notification: Notification) {
    // Plug loophole for window resize when not covered by windowWillResize.
    // Trigger forced draws
    videoView.activateForcedRedraws()
  }

  /// Changes video scale to `desiredVideoScale`, where a value of `1.0` is the video's native scale.
  func setVideoScale(to desiredVideoScale: Double) {
    assert(DispatchQueue.isExecutingIn(.main))
    // Not supported in music mode at this time. Need to resolve backing scale bugs
    guard currentLayout.mode == .windowedNormal else {
      log.error{"SetVideoScale: skipping; mode is unsupported: \(currentLayout.mode)"}
      return
    }
    guard desiredVideoScale > 0.0 else {
      log.error{"SetVideoScale: requested scale is invalid: \(desiredVideoScale)"}
      return
    }

    let gtf = GeometryTransform("SetVideoScale", player,
                                windowed: { [self] ctx -> PWinGeometry? in
      let oldWindowedGeo = ctx.oldGeo.windowed.clone(video: ctx.inputVidGeo)  // may need to sub from syncVideoParams
      // TODO: if Preference.bool(for: .usePhysicalResolution) {}
      // Not supported in music mode at this time. Need to resolve backing scale bugs
      // FIXME: regression: viewport keeps expanding when video runs into screen boundary

      let screen = NSScreen.getScreenOrDefault(screenID: oldWindowedGeo.screenID)
      let backingScaleFactor = screen.backingScaleFactor
      let adjustedVideoScale = desiredVideoScale
      let videoSizeCAR = oldWindowedGeo.video.videoSizeCAR
      let videoWidthScaled = (videoSizeCAR.width * adjustedVideoScale).rounded()

      let newGeoUnconstrained = oldWindowedGeo.scalingVideo(toWidth: videoWidthScaled, screenFit: .noConstraints)
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      let newGeo = newGeoUnconstrained.refitted(using: .stayInside)
      log.verbose{"SetVideoScale: desired=\(desiredVideoScale) adjusted=\(adjustedVideoScale) videoCAR=\(videoSizeCAR) → videoWidthScaled=\(videoWidthScaled) → windowScale=\(newGeo.mpvWindowScale())"}
      sendWindowScaleToMPV(newGeo.mpvWindowScale())
      return newGeo
    })
    animationPipeline.submit(gtf: gtf)
  }

  /// Scales the viewport (which is equivalent to mpv's concept of a window) to the given `desiredMpvWindowScale`.
  ///
  /// This method is really only useful for responding to mpv's `window-scale` property, because this property is
  /// meaningless to a casual user due to the way it is calculated using the viewport size; they should normally care about
  /// the video scale instead. To change the video scale, call `setVideoScale`.
  ///
  /// Not supported in music mode at this time. Need to resolve backing scale bugs.
  ///
  /// See also: `PWinGeometry.mpvWindowScale`.
  func sendWindowScaleToMPV(_ desiredMpvWindowScale: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))
    // Do not call while resizing the window, as doing so has race conditions.
    guard loaded, let window, !window.inLiveResize, !isAnimatingLayoutTransition else { return }

    guard desiredMpvWindowScale > 0.0 else {
      log.verbose("SetWindowScale: desiredMpvWindowScale (\(desiredMpvWindowScale)) is invalid; aborting")
      return
    }

    let currentMpvWindowScale = cachedMpvWindowScale
    guard desiredMpvWindowScale != currentMpvWindowScale else {
      log.verbose("SetWindowScale: skipping; same as cached value (\(desiredMpvWindowScale))")
      return
    }

    cachedMpvWindowScale = desiredMpvWindowScale

    let mpvKeepAspect = currentLayout.mode.needsMpvKeepaspectWindow

    log.verbose{"Sending window-scale to mpv: \(currentMpvWindowScale) → \(desiredMpvWindowScale)"}
    player.mpv.queue.async { [self] in
      guard player.isActive, player.info.isFileLoaded else {
        log.debug{"Skipping send of window-scale to mpv: player not ready"}
        return
      }

      player.mpv.setDouble(MPVProperty.windowScale, desiredMpvWindowScale)
      player._setMpvKeepaspectWindow(to: mpvKeepAspect)
    }
  }

  /// After receiving an updated `window-scale` (the `newMpvWindowScale` param) via an mpv property change event,
  /// this method is called to scale the window's viewport (which for mpv is equivalent to its concept of a window)
  /// to match as best as possible.
  ///
  /// This method is really only useful for responding to mpv's `window-scale` property, because this property is
  /// meaningless to a casual user due to the way it is calculated using the viewport size; they should normally care about
  /// the video scale instead. To change the video scale, call `setVideoScale`.
  ///
  /// Not supported in music mode at this time. Need to resolve backing scale bugs.
  ///
  /// See also: `PWinGeometry.mpvWindowScale`.
  func mpvWindowScaleDidUpdate(to newMpvWindowScale: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))
    /* FIXME: this is all broken
    // Do not call while resizing the window, as doing so has race conditions.
    guard loaded, let window, !window.inLiveResize, !isAnimatingLayoutTransition else { return }
    guard !isMagnifying else { return }
    guard currentLayout.mode == .windowedNormal || currentLayout.mode == .musicMode else {
      // Not supported in music mode at this time. Need to resolve backing scale bugs
      log.error{"mpv→SetWindowScale: skipping; unsupported mode: \(currentLayout.mode)"}
      return
    }

    let currentMpvWindowScale = cachedMpvWindowScale

    guard newMpvWindowScale != currentMpvWindowScale else {
      log.verbose("mpv→SetWindowScale: skipping; same as cached value (\(newMpvWindowScale))")
      return
    }
    // Need to update this right away in case mpv sends duplicate requests
    cachedMpvWindowScale = newMpvWindowScale
    log.verbose{"Got updated window-scale from mpv: \(currentMpvWindowScale) → \(newMpvWindowScale)"}

    let gtf = GeometryTransform("SetWindowScaleFromMPV", player,
                                windowed: { [self] ctx -> PWinGeometry? in
      let oldWindowedGeo = ctx.oldGeo.windowed
      // TODO: if Preference.bool(for: .usePhysicalResolution) {}

      /// This logic needs to match the function `mp_property_current_window_scale` in mpv's `player.command.c`
      // mpv uses viewport size for calculation when keepaspect-window=no, which we always use in our operation.
      let videoSizeCAR = oldWindowedGeo.video.videoSizeCAR
      let viewportSizeScaled = (fix_me * newMpvWindowScale).rounded()
      let newGeoUnconstrained = oldWindowedGeo.scalingViewport(to: viewportSizeScaled, screenFit: .noConstraints)
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      let newGeo = newGeoUnconstrained.refitted(using: .stayInside)
      let finalMpvWindowScale = newGeo.mpvWindowScale()
      if newMpvWindowScale == finalMpvWindowScale {
        log.verbose{"mpv→SetWindowScale: cached=\(currentMpvWindowScale) → \(finalMpvWindowScale)"}
      } else {
        // Could not match desired value. Notify mpv of value used
        log.verbose{"mpv→SetWindowScale: cached=\(currentMpvWindowScale) desired=\(newMpvWindowScale) → ACTUAL=\(finalMpvWindowScale)"}
        sendWindowScaleToMPV(finalMpvWindowScale)
      }
      return newGeo
    })
    animationPipeline.submit(gtf: gtf)
     */
  }

  /**
   Resizes and repositions the window, attempting to match `desiredViewportSize`, but the actual resulting
   video size will be scaled if needed so it is `<= screen.visibleFrame`.
   The window's position will also be updated to maintain its current center if possible, but also to
   ensure it is placed entirely inside `screen.visibleFrame`.
   */
  func resizeViewport(to desiredViewportSize: CGSize? = nil, centerOnScreen: Bool = false,
                      duration: CGFloat = Constants.AnimationDuration.standard) {
    assert(DispatchQueue.isExecutingIn(.main))

    let inputGeo: PWinGeometry
    let outputGeo: PWinGeometry
    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:
      inputGeo = windowedGeoForCurrentFrame()
      let newGeoUnconstrained = inputGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
      if inputGeo.mode == .windowedNormal {
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      }

      let screenFit: ScreenFit = centerOnScreen ? .centerInside : .stayInside
      outputGeo = newGeoUnconstrained.refitted(using: screenFit)
      log.verbose{"Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(outputGeo.windowFrame)"}
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      inputGeo = musicModeGeoForCurrentFrame()
      outputGeo = inputGeo.scalingViewport(to: desiredViewportSize)
      log.verbose{"Calling applyWindowGeo from resizeViewport, to: \(outputGeo.windowFrame)"}
    default:
      return
    }
    // windowed or music mode
    buildApplyWindowGeoTasks(from: inputGeo, to: outputGeo, duration: duration, thenRun: true)
  }


  // TODO: interpolate this
  func scaleVideoByIncrement(_ widthStep: CGFloat) {
    assert(DispatchQueue.isExecutingIn(.main))

    func scale(_ viewportSize: CGSize, widthStep: CGFloat) -> CGSize {
      let heightStep = widthStep / viewportSize.mpvAspect
      return CGSize(width: round(viewportSize.width + widthStep),
                    height: round(viewportSize.height + heightStep))
    }

    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive, .musicMode:

      let windowedTransform: (GeometryTransform.Context) -> PWinGeometry? = { [self] ctx -> PWinGeometry? in
        switch ctx.outputLayout.mode {
        case .fullScreenInteractive, .fullScreenNormal:
          return nil
        case .musicMode:
          let oldViewportSize = ctx.oldGeo.musicMode.viewportSize
          guard ctx.oldGeo.musicMode.videoShown else { return nil }
          let desiredViewportSize = scale(oldViewportSize, widthStep: widthStep)
          log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
          return ctx.oldGeo.musicMode.scalingViewport(to: desiredViewportSize)
        case .windowedNormal, .windowedInteractive:
          let oldWindowedGeo = ctx.oldGeo.windowed
          let desiredViewportSize = scale(oldWindowedGeo.viewportSize, widthStep: widthStep)
          log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
          let newGeoUnconstrained = oldWindowedGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
          // User has actively resized the video. Assume this is the new preferred resolution
          player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
          return newGeoUnconstrained.refitted(using: .stayInside)
        }
      }
      animationPipeline.submit(gtf: GeometryTransform("ScaleVideoBy\(widthStep)px", player,
                                                      windowed: windowedTransform))
    default:
      return
    }
  }


  func adjustFloatingControllerOrigin(for newGeometry: PWinGeometry? = nil) {
    guard let window = window, currentLayout.hasFloatingOSC else { return }
    guard controlBarFloating.superview != nil else { return }

    let newViewportSize = newGeometry?.viewportSize ?? viewportView.frame.size
    controlBarFloating.moveToLocationRatio(layout: currentLayout, viewportSize: newViewportSize)

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

  // MARK: - Apply Geometry - NOT Music Mode

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  func applyLegacyFSGeo(_ geometry: PWinGeometry) {
    assert(geometry.mode.isFullScreen, "Expected applyLegacyFSGeo to be called with full screen geometry but got \(geometry)")
    let currentLayout = currentLayout

    updateTopOffsetConstraints(for: geometry, isLegacyFullScreen: true)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideBars.top : geometry.outsideBars.top
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)

    log.verbose{"Calling setFrame for legacyFullScreen, to \(geometry)"}
    updateWindowFrameAndSubviews(using: geometry)
  }

   func buildApplyFullScreenGeoTasks(fsGeo: PWinGeometry, newWindowedGeo: PWinGeometry,
                                     duration: CGFloat, showDefaultArt: Bool?) -> [IINAAnimation.Task] {
     let tasks: [IINAAnimation.Task] = [
      .init(duration: duration, { [self] in
        // Make sure video constraints are up to date, even in full screen.
        // Also remember that FS & windowed mode share the same screen.
        log.verbose{"ApplyFullScreenGeo: updating videoView, videoSize=\(fsGeo.videoSize)"}
        videoView.apply(fsGeo)
        /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
        windowedModeGeo = newWindowedGeo

        resetRotationPreview()
        hideSeekPreviewImmediately()
        updateDefaultArtVisibility(to: showDefaultArt)
        updateUI(pullUpdatesFromMpv: true)  /// see note about OSD in `buildApplyWindowGeoTasks`
      })
     ]
     return tasks
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated. Windowed mode only!
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state.
  @discardableResult
  func buildApplyWindowGeoTasks(from inputGeo: PWinGeometry, to outputGeo: PWinGeometry,
                                duration: CGFloat = Constants.AnimationDuration.standard,
                                timing: CAMediaTimingFunctionName = .easeInEaseOut,
                                save: Bool = true,
                                showDefaultArt: Bool? = nil,
                                thenRun: Bool = false) -> [IINAAnimation.Task] {

    let isTogglingVideoView = (inputGeo.videoShown != outputGeo.videoShown)
    let isShowingVideo = isTogglingVideoView && outputGeo.videoShown
    let isHidingVideo = isTogglingVideoView && !outputGeo.videoShown
    log.verbose{"ApplyWindowGeo: task dur=\(duration) showDefaultArt=\(showDefaultArt?.yn ?? "nil") run=\(thenRun.yn) \(outputGeo)"}

    var tasks: [IINAAnimation.Task] = []

    // TASK 1: Background prep
    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      videoView.enterAsynchronousMode()

      assert(!currentLayout.spec.mode.isFullScreen, "applyWindowGeo called for non-windowed mode! (found: \(currentLayout.spec.mode))")

      if isTogglingVideoView {
        if isShowingVideo {
          if pip.status == .inPIP {
            // We are about to steal its video; close it:
            exitPIP()
          }
          addVideoViewToWindow(using: outputGeo)
        } else {  // hiding video
                  // Remove OSD constraints *before* reducing viewportView height to 0
          updateOSDConstraintsForMusicMode(outputGeo)
        }

        // Hide OSD during animation
        hideOSD(immediately: true)
        pip.hideOverlayView()

        /// Temporarily hide window buttons. Using `isHidden` will conveniently override its alpha value
        closeButtonView.isHidden = true
      } // end isTogglingVideoView

      hideSeekPreviewImmediately()
      // Show art if videoView is already visible, or before it needs to be shown:
      if outputGeo.videoShown {
        updateDefaultArtVisibility(to: showDefaultArt)
      }
      resetRotationPreview()
    })

    // TASK 2: Apply animation
    tasks.append(.init(duration: duration, timing: timing, { [self] in
      if outputGeo.mode == .musicMode {
        applyMusicModeGeo(outputGeo, setFrame: true, save: save)
      } else {
        // This is only needed to achieve "fade-in" effect when opening window:
        updateWindowBorderAndOpacity()
        /// Make sure this is up-to-date. Do this before `setFrame`
        if !isWindowHidden {
          updateWindowFrameAndSubviews(using: outputGeo)
        } else {
          videoView.apply(outputGeo)
        }

        if save {
          windowedModeGeo = outputGeo
          player.saveState()
        }

        log.verbose{"ApplyWindowGeo: Calling sendWindowScaleToMPV, viewportSize=\(outputGeo.viewportSize)"}
        sendWindowScaleToMPV(outputGeo.mpvWindowScale())
      }
    }))

    // TASK 3: Background cleanup
    tasks.append(.instantTask{ [self] in
      if isHidingVideo, pip.status == .notInPIP {
        updateWindowLayoutForVideoViewHidden(playlistShown: outputGeo.isMusicModePlaylistVisible)
      }

      isAnimatingLayoutTransition = false
      // OSD messages may have been supressed because file was not done loading. Display now if needed:
      updateUI(pullUpdatesFromMpv: true)  /// see note about OSD in `buildApplyWindowGeoTasks`
      player.events.emit(.windowSizeAdjusted, data: outputGeo.windowFrame)
    })

    if thenRun {
      animationPipeline.submit(tasks)
      return []
    }
    return tasks
  }

  // MARK: - Apply Geometry: Music Mode

  func updateWindowLayoutForVideoViewHidden(playlistShown: Bool) {
    videoView.apply(nil)  // remove constraints
    videoView.removeFromSuperview()
    viewportView.removeSpacers()
    updateDefaultArtVisibility(to: false)  // hide defaultAlbumArt

    player.setVideoTrackDisabled(showDefaultAlbumArt: false)

    /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
    /// (See note in `applyMusicModeGeo`)
    if playlistShown {
      log.verbose{"Hiding video, but playlist is shown. Setting viewportBtmOffsetFromContentViewBtmConstraint inactive"}
      viewportBtmOffsetFromContentViewBtmConstraint.priorityInt = 499
    }
  }

  /// Updates the current window and its subviews to match the given `PWinGeometry` in music mode.
  /// If `save` is true, updates `musicModeGeo`, prefs and saves player state.
  func applyMusicModeGeo(_ geometry: PWinGeometry, setFrame: Bool = true, save: Bool = true) {
    guard geometry.mode == .musicMode else { Logger.fatal("Expected mode=musicMode for: \(geometry)") }
    let geometry = geometry.refitted()  // enforces internal constraints, and constrains to screen
    log.verbose{"Applying \(geometry), setFrame=\(setFrame.yn) save=\(save.yn)"}

    videoView.enterAsynchronousMode()

    // This is only needed to achieve "fade-in" effect when opening window:
    updateWindowBorderAndOpacity()

    updateMusicModeButtonsVisibility(using: geometry)

    /// Try to detect & remove unnecessary constraint updates - `updateBottomBarHeight()` may cause animation glitches if called twice
    guard !geometry.windowFrame.equalTo(window!.frame)
            || (geometry.videoShown != musicModeGeo.videoShown)
            || (geometry.isMusicModePlaylistVisible != musicModeGeo.isMusicModePlaylistVisible) else {
      log.verbose("No changes needed for music mode windowFrame or constraints")
      return
    }

    miniPlayer.resetScrollingLabels()

    updateBottomBarHeight(to: geometry.outsideBars.bottom, bottomBarPlacement: .outsideViewport, mode: .musicMode)

    if setFrame {
      updateWindowFrameAndSubviews(using: geometry, updateVideoView: false)
    } else {
      resizeWindowSubviews(using: geometry, updateVideoView: false)
    }

    if geometry.videoShown {
      /// Make sure to call `apply` AFTER `updateVideoViewHeightConstraint` if video shown
      miniPlayer.updateVideoViewHeightConstraint(videoShown: geometry.videoShown)
      videoView.apply(geometry)
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldDisableVideoView = !geometry.videoShown && geometry.isMusicModePlaylistVisible
    if !shouldDisableVideoView {
      log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint isActive"}
      viewportBtmOffsetFromContentViewBtmConstraint.priorityInt = 1000
    }

    if save {
      // Update defaults:
      Preference.set(geometry.videoShown, for: .musicModeShowAlbumArt)
      Preference.set(geometry.isMusicModePlaylistVisible, for: .musicModeShowPlaylist)

      musicModeGeo = geometry
      player.saveState()
    }
  }

}
