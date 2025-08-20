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
    let newSize = resizeSubviews(of: window, to: newFrame.size)
    let newNewFrame = NSRect(origin: newFrame.origin, size: newSize)
    log.verbose{"WindowWillZoom: \(window.frame) → \(newFrame) → \(newNewFrame)"}
    return newNewFrame
  }

  func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
    return windowShouldZoom(window, toFrame: defaultFrame)
  }

  // MARK: - Window Delegate: Resize

  func windowWillStartLiveResize(_ notification: Notification) {
    guard !isAnimatingLayoutTransition else { return }
    log.trace{"WindowWillStartLiveResize"}
    isLiveResizingWidth = nil  // reset this
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    log.trace{"WindowDidEndLiveResize"}
  }

  func windowDidResize(_ notification: Notification) {
    // Trigger forced draws (plugs loophole for window resize when not covered by windowWillResize):
    videoView.activateForcedRedraws()
  }

  /// NSWindowDelegate: `windowWillResize`: pretty important. Called by AppKit when it wants to resize the window.
  ///
  /// # Notes for other NSWindowDelegate notifications:
  /// * `windowDidResize`: Called after window is resized from (almost) any cause. Ca be called many times during every call to
  ///   `window.setFrame`. Do not use for anything too serious because it seems to sometimes fire during animations in progress.
  /// * `windowDidEndLiveResize`: Never use! It is unreliable. Use `windowDidResize` if anything.
  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    // Trigger forced draws so that mpv can [try its best to] redraw the video without distortion during window resize:
    videoView.activateForcedRedraws()

    guard !isInWindowResizeDenialPeriod() else {
      log.verbose{"[WinWillResize] Denying req=\(requestedSize): still inside denial period. Will stay at \(window.frame.size)"}
      pendingResizeForScreenChange = false  // should be safe to reset this now
      return window.frame.size
    }
    if !window.inLiveResize && isLeftMouseButtonDown {
      // Looks like user is moving the window, but not resizing it. Prevent the system from trying to resize it..
      log.verbose{"[WinWillResize] Denying req=\(requestedSize): left mouseBtn down, but not resizing"}
      return window.frame.size
    }
    // Tweak to improve responsiveness in music mode. Doesn't seem to affect normal windowed mode.
    // FIXME: this still doesn't look great. Maybe tweak VideoView constraints in music mode
    CATransaction.setAnimationDuration(0)

    return resizeSubviews(of: window, to: requestedSize)
  }

  /// Calculates the size to return for `windowWillResize` & `windowShouldZoom`. Also resizes the window's subviews appropriately.
  private func resizeSubviews(of window: NSWindow, to requestedSize: NSSize) -> NSSize {
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

      let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, geo.video)
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

      // Updates any necessary constraints & resize internal views (calls resizeWindowSubviews among other things)
      resizeWindowSubviews(using: newGeometry, updateVideoView: true)
    }

    log.verbose{"[WinWillResize] Returning size=\(newWindowSize) for \(currentLayout.mode)"}
    return newWindowSize
  }

  /**
   This method is used to move & resize a `PlayerWindow`. It performs additional work needed beyond what `setFrame` provides.
   Do not ever call `PlayerWindow.setFrame()` directly - call this instead!

   By default, `setFrame()` has its own implicit animation, and this can create an undesirable effect when combined with other animations.
   This function uses a `0` duration animation via the `animationResizeTime` callback to effectively remove the implicit
   default animation.
   • Also resizes window subviews.
   • It will still animate if used inside an `NSAnimationContext` or `IINAAnimation.Task` with non-zero duration.
   • If `animate` is `true`, a `windowDidEndLiveResize` event will be triggered, which is often not desirable!
   */
  func setFrameAndUpdateWindowSubviews(using geometry: PWinGeometry,
                                       updateVideoView: Bool = true, animate: Bool = true,
                                       submitUpdate: Bool = false) {
    log.verbose{"[PWin.setFrame] Entered: \(geometry) updateVideoView=\(updateVideoView.yn) animate=\(animate.yn) submit=\(submitUpdate.yn)"}

    resizeWindowSubviews(using: geometry, updateVideoView: updateVideoView && (geometry.mode != .musicMode))

    if geometry.mode == .musicMode {
      guard !geometry.windowFrame.equalTo(window!.frame)
              || (geometry.videoShown != musicModeGeo.videoShown)
              || (geometry.isMusicModePlaylistVisible != musicModeGeo.isMusicModePlaylistVisible)
              || (geometry.isMiddleTransition != musicModeGeo.isMiddleTransition) else {
        log.verbose("[PWin.setFrame] No changes needed for music mode windowFrame or constraints")
        return
      }

      // FIXME: change bottom bar to shrink while in music mode
      updateBottomBarHeight(to: geometry.outsideBars.bottom, bottomBarPlacement: .outsideViewport)

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
        log.verbose{"[PWin.setFrame] Setting viewportBtmOffsetFromContentViewBtmConstraint isActive"}
        viewportBtmOffsetFromContentViewBtmConstraint.priorityInt = 1000
      }
    } else if geometry.mode.isFullScreen && geometry.screenFit == .legacyFullScreen {
      updateTopOffsetConstraints(for: geometry, isLegacyFullScreen: true)
      updateTopBarHeight(to: currentLayout.topBarHeight, topBarPlacement: currentLayout.topBarPlacement,
                         cameraHousingOffset: geometry.topMarginHeight)
    }

    let window = (window as? PlayerWindow)!
    if window.frame.equalTo(geometry.windowFrame) {
      log.verbose("[PWin.setFrame] No change to windowFrame")
    } else {
      log.verbose{"[PWin.setFrame] Setting frame=\(geometry.windowFrame) animate=\(animate.yn)"}
      window.useZeroDurationForNextResize = true
      window.setFrame(geometry.windowFrame, display: true, animate: animate)

      if !geometry.mode.isFullScreen {
        player.events.emit(.windowResized, data: window.frame)
      }
    }

    if submitUpdate {
      if geometry.mode == .musicMode {
        musicModeGeo = geometry
        // Update defaults:
        Preference.set(geometry.videoShown, for: .musicModeShowAlbumArt)
        Preference.set(geometry.isMusicModePlaylistVisible, for: .musicModeShowPlaylist)
      } else if geometry.mode.isWindowed {
        windowedModeGeo = geometry
      }

      log.verbose{"[PWin.setFrame] Calling sendWindowScaleToMPV"}
      sendWindowScaleToMPV(basedOn: geometry)

      player.saveState()
    }
  }

  /// Intended to be used only for resizing one or more of PlayerWindow's subviews, or to accomodate a window resize.
  /// Resizes *only* the subviews in the window, not the window frame. May update other state needed relating to resize.
  ///
  /// This method cannot handle complex layout changes. For that, use a `LayoutTransition` (see `PWin_LayoutTxBuilder.swift`).
  private func resizeWindowSubviews(using newGeometry: PWinGeometry, updateVideoView: Bool = true) {
    videoView.enterAsynchronousMode()
    videoView.activateForcedRedraws()

    // These may no longer be aligned correctly. Just hide them
    hideSeekPreviewImmediately()

    if newGeometry.videoShown {
      if updateVideoView {
        // Not sure if this helps fix the aspect constraint transition
        videoView.apply(newGeometry)
      }

      // Update floating control bar position if applicable
      adjustFloatingControllerOrigin(for: newGeometry)
    }

    if newGeometry.mode == .musicMode {

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

  // MARK: - Window Resize Denial Period
  // Trying to wrestle control of the window size away from MacOS. Hopefully someday a proper solution will be discovered...

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

  // MARK: - Other window resize methods

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
      let oldWindowedGeo = ctx.inputGeoSet.windowed.clone(video: ctx.inputVidGeo)  // may need to sub from syncVideoParams

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
      sendWindowScaleToMPV(basedOn: newGeo)
      return newGeo
    })
    animationPipeline.submitGTF(gtf)
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
  func sendWindowScaleToMPV(basedOn geometry: PWinGeometry) {
    assert(DispatchQueue.isExecutingIn(.main))
    // Do not call while resizing the window, as doing so has race conditions.
    guard loaded, let window, !window.inLiveResize, !isAnimatingLayoutTransition else { return }

    let desiredMpvWindowScale = geometry.mpvWindowScale()
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

    log.verbose{"Sending window-scale to mpv: \(currentMpvWindowScale) → \(desiredMpvWindowScale)"}
    player.mpv.queue.async { [self] in
      guard player.isActive, player.info.isFileLoaded else {
        log.debug{"Skipping send of window-scale to mpv: player not ready"}
        return
      }

      player.mpv.setDouble(MPVProperty.windowScale, desiredMpvWindowScale)
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
     animationPipeline.submitGTF(gtf)
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
      log.verbose{"Calling applyPWinGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(outputGeo.windowFrame)"}
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      inputGeo = musicModeGeoForCurrentFrame()
      outputGeo = inputGeo.scalingViewport(to: desiredViewportSize)
      log.verbose{"Calling applyPWinGeo from resizeViewport, to: \(outputGeo.windowFrame)"}
    default:
      return
    }
    // windowed or music mode
    buildApplyPWinGeoTasks(from: inputGeo, to: outputGeo, duration: duration, thenRun: true)
  }


  // TODO: interpolate this
  func scaleVideoByIncrement(_ widthStep: Int) {
    assert(DispatchQueue.isExecutingIn(.main))
    let currentLayout = currentLayout

    guard currentLayout.isWindowed || currentLayout.isMusicMode else { return }

    func scaleByWidthStep(_ viewportSize: CGSize) -> CGSize {
      let widthNew = (viewportSize.width + CGFloat(widthStep)).rounded()
      let heightNew = (widthNew / viewportSize.mpvAspect).rounded()
      return CGSize(width: widthNew, height: heightNew)
    }

    let gtf = GeometryTransform("ScaleVideoWidthBy\(widthStep.signString)\(abs(widthStep))pts", player,
                                windowed: { [self] ctx -> PWinGeometry? in
      let mode = ctx.outputLayout.mode
      switch mode {

      case .musicMode:
        let inputGeo = ctx.inputGeoSet.musicMode
        let inputViewportSize = inputGeo.viewportSize
        guard inputGeo.videoShown else { return nil }
        let desiredViewportSize = scaleByWidthStep(inputViewportSize)
        log.verbose{"Stepping viewport scale: mode=\(mode) stepW=\(widthStep)pt → \(desiredViewportSize)"}
        return inputGeo.scalingViewport(to: desiredViewportSize)

      case .windowedNormal, .windowedInteractive:
        let inputGeo = ctx.inputGeoSet.windowed
        let desiredViewportSize = scaleByWidthStep(inputGeo.viewportSize)
        log.verbose{"Stepping viewport scale: mode=\(mode) stepW=\(widthStep)pt → \(desiredViewportSize)"}
        let scaledGeoUnconstrained = inputGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = scaledGeoUnconstrained.viewportSize
        return scaledGeoUnconstrained.refitted(using: .stayInside)

      case .fullScreenInteractive, .fullScreenNormal:
        return nil
      }
    })
    animationPipeline.submitGTF(gtf)
  }

  // MARK: - Apply PWinGeometry (General Cases)

  /// Generates tasks which, when executed, will update the layout of the player window & its internal views to match the
  /// state described by `outputGeo`. Animated. Can be used for all `PlayerWindowMode` cases.
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state.
  @discardableResult
  func buildApplyPWinGeoTasks(from inputGeo: PWinGeometry, to outputGeo: PWinGeometry,
                              duration: CGFloat = Constants.AnimationDuration.standard,
                              timing: CAMediaTimingFunctionName = .easeInEaseOut,
                              save: Bool = true,
                              showDefaultArt: Bool? = nil,
                              thenRun: Bool = false) -> [IINAAnimation.Task] {

    // Music mode only
    let isTogglingVideoView = (inputGeo.videoShown != outputGeo.videoShown)
    let isShowingVideo = isTogglingVideoView && outputGeo.videoShown
    let isHidingVideo = isTogglingVideoView && !outputGeo.videoShown
    let middleGeo: PWinGeometry? = isTogglingVideoView ? outputGeo.cloneMusicMode(isMiddleTransition: true) : nil

    log.verbose{"ApplyPWinGeo: task dur=\(duration) showDefaultArt=\(showDefaultArt?.yn ?? "nil") run=\(thenRun.yn) \(outputGeo)"}

    var tasks: [IINAAnimation.Task] = []

    // TASK 1: Background prep
    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      videoView.enterAsynchronousMode()

      hideSeekPreviewImmediately()

      if isTogglingVideoView {
        // [MusicModeKludge-A] When toggling video, loosen constraints while animating to prevent occasional crash in mpv_render
        let middleGeo = middleGeo!
        if isShowingVideo {
          if pip.status == .inPIP {
            // We are about to steal its video; close it:
            exitPIP()
          }
          addVideoViewToWindow(using: middleGeo)
        } else {
          // Hiding video
          // Remove OSD constraints *before* reducing viewportView height to 0
          updateOSDConstraintsForMusicMode(middleGeo)
          // [MusicModeKludge-A] Loosen constraints manually *before* the animation task below
          videoView.videoViewConstraints?.aspectRatio.isActive = false
        }

        // Hide OSD during animation
        hideOSD(immediately: true)
        pip.hideOverlayView()
      } // end isTogglingVideoView

      // Show art if videoView is already visible, or before it needs to be shown:
      if outputGeo.videoShown {
        updateDefaultArtVisibility(to: showDefaultArt)
      }
      resetRotationPreview()
    })

    // TASK 2: Apply animation
    tasks.append(.init(duration: duration, timing: timing, { [self] in
      if outputGeo.mode == .musicMode {
        // This is only needed to achieve "fade-in" effect when opening window:
        updateWindowBorderAndOpacity()

        // [MusicModeKludge-A] Constraints in videoVideo are applied again here, nestled deep. Use middle geo for consistency
        let geoToApply = middleGeo ?? outputGeo
        setFrameAndUpdateWindowSubviews(using: geoToApply)

      } else if outputGeo.mode.isFullScreen {
        // Make sure video constraints are up to date, even in full screen.
        // Also remember that FS & windowed mode share the same screen.
        log.verbose{"ApplyPWinGeo: updating videoView for FS, videoSize=\(outputGeo.videoSize)"}
        videoView.apply(outputGeo)

      } else {
        assert(outputGeo.mode.isWindowed, "Expected windowed mode: \(outputGeo.mode)")
        // This is only needed to achieve "fade-in" effect when opening window:
        updateWindowBorderAndOpacity()

        /// Make sure this is up-to-date. Do this before `setFrame`
        if !isWindowHidden {
          setFrameAndUpdateWindowSubviews(using: outputGeo, submitUpdate: save)
        } else {
          videoView.apply(outputGeo)

          if save {
            // This is also done in `setFrameAndUpdateWindowSubviews()`
            windowedModeGeo = outputGeo
            player.saveState()
          }
        }
      }
    }))

    // TASK 3: Post-animation background state updates
    tasks.append(.instantTask{ [self] in
      if outputGeo.mode == .musicMode {
        // [MusicModeKludge-A] Previous task used a middle transition geometry. Apply the stricter geometry now
        setFrameAndUpdateWindowSubviews(using: outputGeo, submitUpdate: save)
        videoView.apply(outputGeo)

        if !outputGeo.videoShown, pip.status == .notInPIP {
          updateWindowLayoutForVideoViewHidden(playlistShown: outputGeo.isMusicModePlaylistVisible)
        }

        updateMusicModeButtonsVisibility(using: outputGeo)
      }

      isAnimatingLayoutTransition = false

      // Need to wait until after isAnimatingLayoutTransition=NO before calling this, or it will be ignored
      log.verbose{"ApplyPWinGeo: Calling sendWindowScaleToMPV, viewportSize=\(outputGeo.viewportSize)"}
//      sendWindowScaleToMPV(basedOn: outputGeo)

      // OSD messages may have been supressed because isAnimatingLayoutTransition was set.
      // Display now if needed (see note about OSD in `buildApplyPWinGeoTasks`)
      updateUI(pullUpdatesFromMpv: true)
      if !outputGeo.mode.isFullScreen {
        player.events.emit(.windowSizeAdjusted, data: outputGeo.windowFrame)
      }
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
    /// (See note in `setFrameAndUpdateWindowSubviews`)
    if playlistShown {
      log.verbose{"Hiding video, but playlist is shown. Setting viewportBtmOffsetFromContentViewBtmConstraint inactive"}
      viewportBtmOffsetFromContentViewBtmConstraint.priorityInt = 499
    }
  }

}
