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
    guard !isInWindowResizeDenialPeriod() else {
      log.verbose{"[WinWillResize] Denying request=\(requestedSize): still inside denial period. Will stay at \(window.frame.size)"}
      pendingResizeForScreenChange = false  // should be safe to reset this now
      return window.frame.size
    }
    if !window.inLiveResize && isLeftMouseButtonDown {
      // Looks like user is moving the window, but not resizing it. Prevent the system from trying to resize it..
      log.verbose{"[WinWillResize] Denying request=\(requestedSize): left mouseBtn down, but not resizing"}
      return window.frame.size
    }

    guard !isAnimatingLayoutTransition else {
      return requestedSize
    }

    // FIXME: this still doesn't look great in music mode; maybe adjust VideoView constraints
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
    defer {
      videoView.forceDraw()  // needed if scaling to get a clearer image
    }

    let currentLayout = currentLayout
    let inLiveResize = window.inLiveResize

    let lockViewportToVideoSize = Preference.bool(for: .lockViewportToVideoSize) || currentLayout.mode.alwaysLockViewportToVideoSize
    log.verbose{"[WinWillResize] \(currentLayout.mode) Curr=\(window.frame.size) Req=\(requestedSize) Live=\(inLiveResize.yn) LockViewport=\(lockViewportToVideoSize.yn)"}

    videoView.enterAsynchronousMode()

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
      /// within the same animation transaction as the code below. But this solution seems to get us 99% there; the video
      /// only exhibits a small noticeable wobble for some limited cases ...
      resizeWindowSubviews(using: newGeometry, updateVideoView: false)
      // fall through

    case .fullScreenNormal, .fullScreenInteractive:
      if currentLayout.isNativeFullScreen {
        // This method can be called as a side effect of the animation. If so, ignore.
        return requestedSize
      }

      let newGeometry = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
      newWindowSize = newGeometry.windowFrame.size
      videoView.apply(newGeometry)
      // fall through

    case .musicMode:
      guard !sessionState.isRestoring else {
        log.error{"[WinWillResize] Still restoring; returning existing musicModeGeo=\(musicModeGeo.windowFrame.size)"}
        return musicModeGeo.windowFrame.size
      }

      let currentGeo = musicModeGeoForCurrentFrame()
      let newGeometry = currentGeo.resizingWindow(to: requestedSize, inLiveResize: window.inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
      newWindowSize = newGeometry.windowFrame.size

      /// This call is needed to update any necessary constraints & resize internal views
      _ = applyMusicModeGeo(newGeometry, setFrame: false, updateCache: false)
    }

    log.verbose{"[WinWillResize] Returning size=\(newWindowSize) for \(currentLayout.mode)"}
    return newWindowSize
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
    videoView.enterAsynchronousMode()

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setAnimationDuration(0)  // need immediate effect. No lag!
    defer {
      CATransaction.commit()
    }

    resizeWindowInstantlyNoTransaction(using: newGeometry)
  }

  func resizeWindowInstantlyNoTransaction(using newGeometry: PWinGeometry? = nil) {
    guard let window else { return }

    let layout = currentLayout
    let isTransientResize = newGeometry != nil
    let isFullScreen = layout.isFullScreen
    log.verbose{"[ResizeWindInstantly] fs=\(isFullScreen.yn) live=\(window.inLiveResize.yn) geo=\(newGeometry?.description ?? "nil")"}

    // These may no longer be aligned correctly. Just hide them
    hideSeekPreviewImmediately()

    let geo = newGeometry ?? layout.buildGeometry(windowFrame: window.frame, screenID: bestScreen.screenID, video: geo.video)

    if isFullScreen {
      // custom FS
      resizeWindowSubviews(using: geo)
    } else {
      /// This will also update `videoView`
      player.window.setFrameImmediately(geo, notify: false)
    }

    if !isFullScreen && !isTransientResize {
      player.saveState()
      if layout.mode == .windowedNormal {
        log.verbose{"[ResizeWindInstantly] calling updateMPVWindowScale"}
        player.updateMPVWindowScale(using: windowedModeGeo)
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  /// Resizes *only* the subviews in the window, not the window frame. Updates other state needed when resizing window.
  func resizeWindowSubviews(using newGeometry: PWinGeometry, updateVideoView: Bool = true) {
    videoView.enterAsynchronousMode()
    if updateVideoView {
      // Not sure if this helps fix the aspect constraint transition
      videoView.apply(newGeometry)
    }
    
    // Update floating control bar position if applicable
    adjustFloatingControllerOrigin(for: newGeometry)
    
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

  /// Applies changes to window geometry, possibly animating any changes.
  ///
  /// # Arguments:
  /// - `stateChange`: optional operator function for transforming `sessionState` and/or cancelling the transform.
  ///   - If `nil`, the transform will proceed with the existing `sessionState`.
  ///   - If non-nil, this function will be run in the mpv queue. It is given the current window's `sessionState` & is expected
  ///     to output a new value of `sessionState` to set at the end of the transform if it succeeds.
  ///     But if it returns `nil`, the transform will be cancelled.
  /// - `videoTransform`: optional operator function which, if provided, will run in the mpv queue.
  ///   - If `nil`, the transform will proceed with the existing `VideoGeometry`.
  ///   - If non-`nil`: t is given the current window's `VideoGeometry` (and other context), & is expected to output a new, possibly
  ///     transformed ` VideoGeometry`. But if it returns `nil`, then transform will be cancelled and no state will be changed.
  /// - `windowedTransform`: optional operator function which if provided, will run in the main queue.
  ///   - If non-nil, and if in music mode, this function is given the `PWinGeometry` which would otherwise be applied and is
  ///     is expected to output a ` PWinGeometry` containing further transforms which should be applied. If it returns `nil`,
  ///     the transform will ignore it and will proceed with its calculated values.
  /// - `musicModeTransform`: optional operator function which if provided, will run in the main queue.
  ///   - If non-nil, and if in music mode, this function is given the `MusicModeGeometry` which would otherwise be applied and is
  ///     is expected to output a ` MusicModeGeometry` containing further transforms which should be applied. If it returns `nil`,
  ///     the transform will not transform the geometry.
  func transformGeometry(_ transformName: String,
                         stateChange: PWinSessionState.Transform? = nil,
                         video videoTransform: VideoGeometry.Transform? = nil,
                         windowed windowedTransform: PWinGeometry.Transform? = nil,
                         musicMode musicModeTransform: MusicModeGeometry.Transform? = nil,
                         onSuccess: (() -> Void)? = nil) {
    // FIXME: figure out if this gets called before fileLoaded

    let tf = GeometryTransform(name: transformName, state: stateChange, video: videoTransform,
                               windowed: windowedTransform, musicMode: musicModeTransform, onSuccess: onSuccess)

    animationPipeline.submitInstantTask { [self] in
      let oldGeo = geo

      player.mpv.queue.async { [self] in

        /// Make sure `doAfter` is always executed
        func abort(_ reasonDebugMsg: String) {
          log.verbose{"[GeoTF:\(transformName)] Aborting TF: \(reasonDebugMsg)"}
        }

        guard !player.isStopping else {
          return abort("player stopping (status=\(player.state))")
        }

        guard let currentPlayback = player.info.currentPlayback else {
          return abort("currentPlayback is nil")
        }

        // File needs to be loaded before we can know its video geometry.
        // ...Unless we are restoring. But then we still want to wait until all windows are done loading, so we can open them all at once.
        // ...But streaming files can often fail to connect. So reopen those right away if restoring (we already have their saved geometry anyway).
        guard currentPlayback.state.isAtLeast(.started) || (sessionState.isRestoring && currentPlayback.isNetworkResource) else {
          return abort("playbackState=\(currentPlayback.state) restoring=\(sessionState.isRestoring.yn) network=\(currentPlayback.isNetworkResource.yn)")
        }

        let vidTrackID = player.info.vid ?? 0

        var cxt = GeometryTransform.Context(tf: tf, oldGeo: oldGeo, sessionState: sessionState,
                                           currentPlayback: currentPlayback, vidTrackID: vidTrackID,
                                           currentMediaAudioStatus: player.info.currentMediaAudioStatus,
                                           player: player)

        /// Apply `stateChange` if present
        if let stateChange {
          guard let newSessionState = stateChange(cxt) else {
            return abort("state change func returned nil from sessionState=\(sessionState)")
          }
          log.verbose{"[GeoTF:\(cxt.name)] sessionState change applied: \(cxt.sessionState) → \(newSessionState.description)"}
          cxt = cxt.clone(sessionState: newSessionState)
        } else {
          log.verbose{"[GeoTF:\(cxt.name)] Reusing current sessionState: \(cxt.sessionState)"}
        }

        /// Apply `videoTransform` if present
        let newVidGeo: VideoGeometry
        if let videoTransform {
          guard let resultGeo = videoTransform(cxt) else {
            return abort("videoTransform returned nil")
          }
          log.verbose{"[GeoTF:\(cxt.name)] VideoTransform returned: \(resultGeo)"}
          newVidGeo = resultGeo
        } else {
          newVidGeo = oldGeo.video
        }


        animationPipeline.submitInstantTask { [self] in
          log.verbose{"[GeoTF:\(cxt.name)] sessionState=\(cxt.sessionState)"}

          var immediateTasks: [IINAAnimation.Task]

          let builder = GeometryTransform.TaskBuilder(cxt: cxt, currentLayout: currentLayout, outputVidGeo: newVidGeo)
          if cxt.sessionState.isStartingSession {
            immediateTasks = builder.buildWindowInitialLayoutTasks()

            /// These tasks should not execute until *after* `super.showWindow` is called.
            let geoTransitionTasks = builder.buildApplyTransformTasks()

            let isRestoringMinimizedWindow = cxt.sessionState.isRestoring && UIState.shared.windowsMinimized.contains(window!.savedStateName)
            if isRestoringMinimizedWindow {
              // Minimized: can't rely on showWindow() being called, but window changes won't be seen anyway. Just run end task now.
              log.verbose{"[GeoTF:\(cxt.name)] Restoring minimized window: will run tasks immediately instead of enqueueing"}
              immediateTasks += geoTransitionTasks
            } else {
              pendingVideoGeoUpdateTasks = geoTransitionTasks
            }

          } else {
            immediateTasks = builder.buildApplyTransformTasks()

            // Need to switch to music mode? Append to above tasks
            if case .existingSession_startingNewPlayback = cxt.sessionState, Preference.bool(for: .autoSwitchToMusicMode) {
              let layout = builder.outputLayout
              if player.overrideAutoMusicMode {
                log.verbose{"[GeoTF:\(cxt.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y"}
              } else if cxt.currentMediaAudioStatus.isAudio && !layout.isMusicMode && !layout.isFullScreen {
                log.debug{"[GeoTF:\(cxt.name)] Opened media is audio: auto-switching to music mode"}
                let geo = buildGeoSet(video: newVidGeo, from: layout)
                let enterMusicModeTransitionTasks = buildTransitionTasksToEnterMusicMode(automatically: true, from: layout, geo)
                immediateTasks += enterMusicModeTransitionTasks
              } else if cxt.currentMediaAudioStatus == .notAudio && layout.isMusicMode {
                log.debug{"[GeoTF:\(cxt.name)] Opened media is not audio: auto-switching to normal window"}
                let geo = buildGeoSet(video: newVidGeo, from: layout)
                let enterMusicModeTransitionTasks = buildTransitionTasksToExitMusicMode(automatically: true, from: layout, geo)
                immediateTasks += enterMusicModeTransitionTasks
              }
            }
          }

          animationPipeline.submit(immediateTasks)
        }

      }
    }
  }

  // MARK: - Other window geometry functions

  func changeVideoScale(to desiredVideoScale: Double) {
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

    transformGeometry("SetVideoScale", windowed: { [self] cxt -> PWinGeometry? in
      let oldWindowedGeo = cxt.oldGeo.windowed
      // TODO: if Preference.bool(for: .usePhysicalResolution) {}
      // Not supported in music mode at this time. Need to resolve backing scale bugs
      // FIXME: regression: viewport keeps expanding when video runs into screen boundary

      // See also: PWinGeometry.mpvVideoScale
      let screen = NSScreen.getScreenOrDefault(screenID: oldWindowedGeo.screenID)
      let backingScaleFactor = screen.backingScaleFactor
      let adjustedVideoScale = desiredVideoScale / backingScaleFactor
      let videoSizeCAR = oldWindowedGeo.video.videoSizeCAR
      let videoSizeScaled = (videoSizeCAR * adjustedVideoScale).rounded()
      log.error{"SetVideoScale: desired=\(desiredVideoScale) adjusted=\(adjustedVideoScale) videoCAR=\(videoSizeCAR) → videoScaled=\(videoSizeScaled)"}
      let newGeoUnconstrained = oldWindowedGeo.scalingVideo(to: videoSizeScaled, screenFit: .noConstraints)
      player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      return newGeoUnconstrained.refitted(using: .stayInside)
    })
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

    switch currentLayout.mode {
    case .windowedNormal, .windowedInteractive:
      let oldGeo = windowedGeoForCurrentFrame()
      let newGeoUnconstrained = oldGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
      if currentLayout.mode == .windowedNormal {
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
      }

      let screenFit: ScreenFit = centerOnScreen ? .centerInside : .stayInside
      let newGeometry = newGeoUnconstrained.refitted(using: screenFit)
      log.verbose{"Calling applyWindowGeo from resizeViewport (center=\(centerOnScreen.yn)), to: \(newGeometry.windowFrame)"}
      buildApplyWindowGeoTasks(newGeometry, duration: duration, thenRun: true)
    case .musicMode:
      /// In music mode, `viewportSize==videoSize` always. Will get `nil` here if video is not visible
      let oldGeo = musicModeGeoForCurrentFrame()
      guard let newMusicModeGeo = oldGeo.scalingViewport(to: desiredViewportSize) else { return }
      log.verbose{"Calling applyMusicModeGeo from resizeViewport, to: \(newMusicModeGeo.windowFrame)"}
      buildApplyMusicModeGeoTasks(from: oldGeo, to: newMusicModeGeo, thenRun: true)
    default:
      return
    }
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
    case .windowedNormal:
      let windowedTransform: (GeometryTransform.Context) -> PWinGeometry? = { [self] cxt -> PWinGeometry? in
        let oldWindowedGeo = cxt.oldGeo.windowed
        let desiredViewportSize = scale(oldWindowedGeo.viewportSize, widthStep: widthStep)
        log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
        let newGeoUnconstrained = oldWindowedGeo.scalingViewport(to: desiredViewportSize, screenFit: .noConstraints)
        // User has actively resized the video. Assume this is the new preferred resolution
        player.info.intendedViewportSize = newGeoUnconstrained.viewportSize
        return newGeoUnconstrained.refitted(using: .stayInside)
      }
      transformGeometry("ScaleVideoBy\(widthStep)px", windowed: windowedTransform)

    case .musicMode:
      let musicModeTransform: (GeometryTransform.Context) -> MusicModeGeometry? = { [self] cxt -> MusicModeGeometry? in
        guard let oldViewportSize = cxt.oldGeo.musicMode.viewportSize else { return nil }
        let desiredViewportSize = scale(oldViewportSize, widthStep: widthStep)
        log.verbose{"Incrementing viewport width by \(widthStep), to desired size \(desiredViewportSize)"}
        return cxt.oldGeo.musicMode.scalingViewport(to: desiredViewportSize)
      }
      transformGeometry("ScaleVideoBy\(widthStep)px", musicMode: musicModeTransform)
    default:
      return
    }
  }

  private func adjustFloatingControllerOrigin(for newGeometry: PWinGeometry? = nil) {
    guard let window = window, currentLayout.hasFloatingOSC else { return }

    let newViewportSize = newGeometry?.viewportSize ?? viewportView.frame.size
    controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH,
                              originRatioV: floatingOSCOriginRatioV, layout: currentLayout, viewportSize: newViewportSize)

    // Detach the views in oscFloatingUpperView manually on macOS 11 only; as it will cause freeze
    if #available(macOS 11.0, *) {
      if #unavailable(macOS 12.0) {
        guard let maxWidth = [fragVolumeView, fragToolbarView].compactMap({ $0?.frame.width }).max() else {
          return
        }

        // window - 10 - controlBarFloating
        // controlBarFloating - 12 - oscFloatingUpperView
        let margin: CGFloat = (10 + 12) * 2
        let hide = (window.frame.width
                    - oscFloatingPlayButtonsContainerView.frame.width
                    - maxWidth*2
                    - margin) < 0

        let views = oscFloatingUpperView.views
        if hide {
          if views.contains(fragVolumeView) {
            oscFloatingUpperView.removeView(fragVolumeView)
          }
          if views.contains(fragToolbarView) {
            oscFloatingUpperView.removeView(fragToolbarView)
          }
        } else {
          if !views.contains(fragVolumeView) {
            oscFloatingUpperView.addView(fragVolumeView, in: .leading)
          }
          if !views.contains(fragToolbarView) {
            oscFloatingUpperView.addView(fragToolbarView, in: .trailing)
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

    if currentLayout.hasFloatingOSC {
      controlBarFloating.moveTo(centerRatioH: floatingOSCCenterRatioH, originRatioV: floatingOSCOriginRatioV,
                                layout: currentLayout, viewportSize: geometry.viewportSize)
    }

    updateOSDTopBarOffset(geometry, isLegacyFullScreen: true)
    let topBarHeight = currentLayout.topBarPlacement == .insideViewport ? geometry.insideBars.top : geometry.outsideBars.top
    updateTopBarHeight(to: topBarHeight, topBarPlacement: currentLayout.topBarPlacement, cameraHousingOffset: geometry.topMarginHeight)

    log.verbose{"Calling setFrame for legacyFullScreen, to \(geometry)"}
    player.window.setFrameImmediately(geometry)
  }

   func buildApplyFullScreenGeoTasks(fsGeo: PWinGeometry, newWindowedGeo: PWinGeometry,
                                     duration: CGFloat, showDefaultArt: Bool?) -> [IINAAnimation.Task] {
    let task = IINAAnimation.Task(duration: duration, { [self] in
      // Make sure video constraints are up to date, even in full screen. Also remember that FS & windowed mode share same screen.
      log.verbose{"Applying full screen geometry: updating videoView, videoSize=\(fsGeo.videoSize)"}
      videoView.apply(fsGeo)
      /// Update even if not currently in windowed mode, as it will be needed when exiting other modes
      windowedModeGeo = newWindowedGeo

      resetRotationPreview()
      hideSeekPreviewImmediately()
      updateDefaultArtVisibility(to: showDefaultArt)
      player.updateMPVWindowScale(using: fsGeo)
      updateUI(pullUpdatesFromMpv: true)  /// see note about OSD in `buildApplyWindowGeoTasks`
    })
    return [task]
  }

  /// Updates/redraws current `window.frame` and its internal views from `newGeometry`. Animated. Windowed mode only!
  ///
  /// Also updates cached `windowedModeGeo` and saves updated state.
  @discardableResult
  func buildApplyWindowGeoTasks(_ newGeometry: PWinGeometry,
                                duration: CGFloat = Constants.AnimationDuration.standard,
                                timing: CAMediaTimingFunctionName = .easeInEaseOut,
                                showDefaultArt: Bool? = nil,
                                thenRun: Bool = false) -> [IINAAnimation.Task] {

    log.verbose{"ApplyWindowGeo: dur=\(duration) showDefaultArt=\(showDefaultArt?.yn ?? "nil") run=\(thenRun.yn) newGeo=\(newGeometry)"}

    var tasks: [IINAAnimation.Task] = []

    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = true  /// try not to trigger `windowDidResize` while animating
      videoView.enterAsynchronousMode()

      assert(currentLayout.spec.mode.isWindowed, "applyWindowGeo called outside windowed mode! (found: \(currentLayout.spec.mode))")

      hideSeekPreviewImmediately()
      updateDefaultArtVisibility(to: showDefaultArt)
      resetRotationPreview()
    })

    tasks.append(.init(duration: duration, timing: timing, { [self] in

      // This is only needed to achieve "fade-in" effect when opening window:
      updateWindowBorderAndOpacity()

      /// Make sure this is up-to-date. Do this before `setFrame`
      if !isWindowHidden {
        player.window.setFrameImmediately(newGeometry)
      } else {
        videoView.apply(newGeometry)
      }
      windowedModeGeo = newGeometry

      log.verbose{"ApplyWindowGeo: Calling updateMPVWindowScale, videoSize=\(newGeometry.videoSize)"}
      player.updateMPVWindowScale(using: newGeometry)
      player.saveState()
    }))

    tasks.append(.instantTask{ [self] in
      isAnimatingLayoutTransition = false
      // OSD messages may have been supressed because file was not done loading. Display now if needed:
      updateUI(pullUpdatesFromMpv: true)
      player.events.emit(.windowSizeAdjusted, data: newGeometry.windowFrame)
    })

    if thenRun {
      animationPipeline.submit(tasks)
      return []
    }
    return tasks
  }

  // MARK: - Apply Geometry: Music Mode

  @discardableResult
  func buildApplyMusicModeGeoTasks(from inputGeo: MusicModeGeometry, to outputGeo: MusicModeGeometry,
                                   duration: CGFloat = Constants.AnimationDuration.standard,
                                   setFrame: Bool = true, updateCache: Bool = true,
                                   showDefaultArt: Bool? = nil,
                                   thenRun: Bool = false) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    let isTogglingVideoView = (inputGeo.isVideoVisible != outputGeo.isVideoVisible)
    let isShowingVideoView = isTogglingVideoView && outputGeo.isVideoVisible

    // TASK 1: Background prep
    tasks.append(.instantTask { [self] in
      isAnimatingLayoutTransition = true  /// do not trigger various listeners if possible
      if isShowingVideoView {
        if pip.status != .inPIP {
          // We are about to steal its video; close it:
          exitPIP()
        }
        // Show/hide art before showing videoView
        updateDefaultArtVisibility(to: showDefaultArt)
        addVideoViewToWindow(using: outputGeo)
      }

      if isTogglingVideoView {
        // Hide OSD during animation
        hideOSD(immediately: true)
        // Hide PiP overlay (if in PiP) during animation
        pipOverlayView.isHidden = true

        /// Temporarily hide window buttons. Using `isHidden` will conveniently override its alpha value
        closeButtonView.isHidden = true

        hideSeekPreviewImmediately()
      }
      resetRotationPreview()
    })

    // TASK 2: Apply animation
    tasks.append(IINAAnimation.Task(duration: duration, timing: .easeInEaseOut, { [self] in
      applyMusicModeGeo(outputGeo)
    }))

    // TASK 2A (if toggling video view visibility)
    if isTogglingVideoView {
      tasks.append(IINAAnimation.Task{ [self] in
        /// Allow it to show again
        closeButtonView.isHidden = false

        showOrHidePipOverlayView()

        // Need to force draw if window was restored while paused + video hidden
        if outputGeo.isVideoVisible {
          videoView.forceDraw()
        }
      })
    }

    // TASK 3: Background cleanup
    tasks.append(.instantTask { [self] in
      // Make sure to update art after videoView has settled
      updateDefaultArtVisibility(to: showDefaultArt)

      if isTogglingVideoView && !outputGeo.isVideoVisible {  // Hiding video
        if pip.status == .notInPIP {
          player.mpv.queue.async { [self] in
            player._setVideoTrackDisabled()
            DispatchQueue.main.async { [self] in
              videoView.removeFromSuperview()
            }
          }
        }

        let shouldDisableConstraint = outputGeo.isPlaylistVisible
        /// If needing to deactivate this constraint, do it before the toggle animation, so that window doesn't jump.
        /// (See note in `applyMusicModeGeo`)
        if shouldDisableConstraint {
          log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint priority = 499"}
          viewportBtmOffsetFromContentViewBtmConstraint.intPriority = 499
        }
      }

      isAnimatingLayoutTransition = false
      updateUI(pullUpdatesFromMpv: true)  /// see note about OSD in `buildApplyWindowGeoTasks`
    })

    if thenRun {
      animationPipeline.submit(tasks)
    }
    return tasks
  }

  /// Updates the current window and its subviews to match the given `MusicModeGeometry`.
  /// If `updateCache` is true, updates `musicModeGeo` and saves player state.
  @discardableResult
  func applyMusicModeGeo(_ geometry: MusicModeGeometry, setFrame: Bool = true, 
                         updateCache: Bool = true) -> MusicModeGeometry {
    let geometry = geometry.refitted()  // enforces internal constraints, and constrains to screen
    log.verbose{"Applying \(geometry), setFrame=\(setFrame.yn) updateCache=\(updateCache.yn)"}

    videoView.enterAsynchronousMode()

    // This is only needed to achieve "fade-in" effect when opening window:
    updateWindowBorderAndOpacity()

    updateMusicModeButtonsVisibility(using: geometry)

    /// Try to detect & remove unnecessary constraint updates - `updateBottomBarHeight()` may cause animation glitches if called twice
    var hasChange: Bool = !geometry.windowFrame.equalTo(window!.frame)
    if geometry.isVideoVisible != !(viewportViewHeightContraint?.isActive ?? false) {
      hasChange = true
    } else if let newVideoSize = geometry.videoSize, let oldVideoSize = musicModeGeo.videoSize, !oldVideoSize.equalTo(newVideoSize) {
      hasChange = true
    }

    guard hasChange else {
      log.verbose("No changes needed for music mode windowFrame or constraints")
      return geometry
    }

    /// Make sure to call `apply` AFTER `updateVideoViewHeightConstraint`!
    miniPlayer.updateVideoViewHeightConstraint(isVideoVisible: geometry.isVideoVisible)

    miniPlayer.resetScrollingLabels()

    updateBottomBarHeight(to: geometry.bottomBarHeight, bottomBarPlacement: .outsideViewport, mode: .musicMode)
    let convertedGeo = geometry.toPWinGeometry()

    if setFrame {
      player.window.setFrameImmediately(convertedGeo)
    } else {
      videoView.apply(convertedGeo)
    }

    /// For the case where video is hidden but playlist is shown, AppKit won't allow the window's height to be changed by the user
    /// unless we remove this constraint from the the window's `contentView`. For all other situations this constraint should be active.
    /// Need to execute this in its own task so that other animations are not affected.
    let shouldDisableConstraint = !geometry.isVideoVisible && geometry.isPlaylistVisible
    if !shouldDisableConstraint {
      log.verbose{"Setting viewportBtmOffsetFromContentViewBtmConstraint priority = required"}
      viewportBtmOffsetFromContentViewBtmConstraint.priority = .required
    }

    // Update defaults:
    Preference.set(geometry.isVideoVisible, for: .musicModeShowAlbumArt)
    Preference.set(geometry.isPlaylistVisible, for: .musicModeShowPlaylist)

    if updateCache {
      musicModeGeo = geometry
      player.saveState()
    }

    return geometry
  }

}
