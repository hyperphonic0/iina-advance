//
//  PWin_GeoTransformTxBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 2024/08/05
//

import Foundation

extension GeometryTransform {
  /// Helps to build an array of `IINAAnimation.Task`, which will execute a window's transition from its
  /// current ("input") geometry to a transformed ("output") geometry, as transformed by a `GeometryTransform`.
  class TaskBuilder {
    var cxt: GeometryTransform.Context

    var inputVidGeo: VideoGeometry { cxt.oldGeo.video }
    /// The transformed `VideoGeometry`.
    let outputVidGeo: VideoGeometry

    let inputLayout: LayoutState
    /// Defaults to `inputLayout`, but can be overwritten by `buildWindowInitialLayoutTasks`.
    /// Do not reference until after that is called.
    var outputLayout: LayoutState

    fileprivate var needsNativeFullScreen = false

    var player: PlayerCore { cxt.player }
    var log: Logger.Subsystem { cxt.player.log }
    var pwc: PlayerWindowController { cxt.player.windowController! }

    init(cxt: GeometryTransform.Context, currentLayout: LayoutState, outputVidGeo: VideoGeometry) {
      self.cxt = cxt
      self.inputLayout = currentLayout
      self.outputLayout = currentLayout  // for now at least
      self.outputVidGeo = outputVidGeo
    }

    func buildWindowInitialLayoutTasks() -> [IINAAnimation.Task] {
      // See below
      let pwc = player.windowController!
      let initialLayoutTasks = pwc.buildWindowInitialLayoutTasks(using: self)
      return initialLayoutTasks
    }

    /// Only `transformGeometry` should call this.
    /// Note: `builder` is only used here for data storage. Will refactor to a cleaner design later
    func buildGeoTransitionTasks() -> [IINAAnimation.Task] {
      var geoTransitionTasks = buildGeoTransitionTasksExceptEnd()
      geoTransitionTasks.append(pwc.buildEndTask(cxt))
      return geoTransitionTasks
    }

    private func buildGeoTransitionTasksExceptEnd() -> [IINAAnimation.Task] {
      // Update context's geo with current window frame
      cxt = cxt.clone(oldGeo: pwc.buildGeoSet(from: outputLayout, baseGeoSet: cxt.oldGeo))
      log.verbose{"[GeoTF:\(cxt.name)] Mode=\(outputLayout.mode): updated cxt=\(cxt)"}
      let sessionState = cxt.sessionState

      var duration: CGFloat
      let didRotate = inputVidGeo.userRotation != outputVidGeo.userRotation
      if didRotate {
        // There's no good animation for rotation (yet), so just do as little animation as possible in this case
        duration = 0.0
      } else {
        duration = Constants.AnimationDuration.videoReconfig
      }
      var timing = CAMediaTimingFunctionName.easeInEaseOut

      switch outputLayout.mode {

      case .windowedNormal:
        let resizedGeo: PWinGeometry?

        if let windowedTransform = cxt.tf.windowedTransform {
          resizedGeo = windowedTransform(cxt)
        } else {
          switch sessionState {
          case .restoring(_):
            log.verbose{"[GeoTF:\(cxt.name)] Restore is in progress; aborting"}
            return []
          case .creatingNew:
            // Just opened new window. Use a longer duration for this one, because the window starts small and will zoom into place.
            duration = Constants.AnimationDuration.initialVideoReconfig
            timing = .linear
            resizedGeo = applyResizePrefsForWindowedFileOpen()
          case .newReplacingExisting:
            resizedGeo = applyResizePrefsForWindowedFileOpen()
          case .existingSession_startingNewPlayback:
            resizedGeo = applyResizePrefsForWindowedFileOpen()
          case .existingSession_videoTrackChangedForSamePlayback,
              .existingSession_continuing:
            // Not a new file. Some other change to a video geo property. Fall through and resize minimally
            resizedGeo = nil
          case .noSession:
            Logger.fatal("[GeoTF:\(cxt.name)] Invalid sessionState: \(sessionState)")
          }
        }

        let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let newGeo = resizedGeo ?? cxt.oldGeo.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                                       intendedViewportSize: intendedViewportSize)

        let showDefaultArt: Bool? = player.info.shouldShowDefaultArt

        log.debug{"[GeoTF:\(cxt.name)] Will apply windowed result (newSessionState=\(sessionState), showDefaultArt=\(showDefaultArt?.yn ?? "nil")): \(newGeo)"}
        return pwc.buildApplyWindowGeoTasks(newGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

      case .fullScreenNormal:
        let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let newWinGeo = cxt.oldGeo.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                            intendedViewportSize: intendedViewportSize)
        let fsGeo = outputLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, video: outputVidGeo)
        let showDefaultArt: Bool? = player.info.shouldShowDefaultArt
        log.debug{"[GeoTF:\(cxt.name)] Will apply FS result: \(fsGeo), showDefaultArt=\(showDefaultArt?.yn ?? "nil")"}

        return pwc.buildApplyFullScreenGeoTasks(fsGeo: fsGeo, newWindowedGeo: newWinGeo, duration: duration, showDefaultArt: showDefaultArt)

      case .musicMode:
        if case .creatingNew = sessionState {
          log.verbose{"[GeoTF:\(cxt.name)] Music mode already handled for opened window: \(cxt.oldGeo.musicMode)"}
          return []
        }
        let oldMusicModeGeo = cxt.oldGeo.musicMode  // has updated windowFrame
        let newMusicModeGeo: MusicModeGeometry
        if let musicModeTransform = cxt.tf.musicModeTransform {
          guard let transformedGeo = musicModeTransform(cxt) else {
            return []
          }
          newMusicModeGeo = transformedGeo
        } else {
          newMusicModeGeo = oldMusicModeGeo.clone(video: outputVidGeo)
        }
        /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
        /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)

        if oldMusicModeGeo.isVideoVisible != newMusicModeGeo.isVideoVisible {
          // Toggling videoView visiblity: use longer duration for nicety
          duration = Constants.AnimationDuration.standard
        }
        /// Default album art: check state before doing anything so that we don't duplicate work. Don't change in miniPlayer if videoView not visible.
        /// If `showDefaultArt == nil`, don't change existing visibility.
        let shouldDecideDefaultArtStatus = oldMusicModeGeo.isVideoVisible || newMusicModeGeo.isVideoVisible
        let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? player.info.shouldShowDefaultArt : nil
        log.verbose{"[GeoTF:\(cxt.name)] Applying musicMode result: \(newMusicModeGeo) (sessionState=\(sessionState) showDefaultArt=\(showDefaultArt?.yn ?? "nil"))"}
        return pwc.buildApplyMusicModeGeoTasks(from: oldMusicModeGeo, to: newMusicModeGeo,
                                               duration: duration, showDefaultArt: showDefaultArt)
      default:
        log.error{"[GeoTF:\(cxt.name)] INVALID MODE: \(outputLayout.mode)"}
        return []
      }
    }

    /// Applies the prefs `.resizeWindowTiming` & `resizeWindowScheme`, if applicable.
    /// Returns `nil` if no applicable settings were found/applied, and should fall back to minimal resize.
    private func applyResizePrefsForWindowedFileOpen() -> PWinGeometry? {
      // resize option applies
      let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      switch resizeTiming {
      case .always:
        log.verbose{"[GeoTF:\(cxt.name)] FileOpened & resizeTiming='Always' → will resize window"}
      case .onlyWhenOpen:
        if !cxt.sessionState.isOpeningFileManually {
          log.verbose{"[GeoTF:\(cxt.name)] FileOpened & resizeTiming='OnlyWhenOpen', but isOpeningFileManually=N → will resize minimally"}
          return nil
        }
      case .never:
        if !cxt.sessionState.isOpeningFileManually {
          log.verbose("[GeoTF:\(cxt.name)] FileOpened (not manually) & resizeTiming='Never' → will resize minimally")
          return nil
        }
        log.verbose{"[GeoTF:\(cxt.name)] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)"}
        return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                        video: outputVidGeo, keepFullScreenDimensions: true,
                                                        applyOffsetIndex: player.openedWindowsSetIndex, log)
      }

      let windowGeo = cxt.oldGeo.windowed.clone(video: outputVidGeo)
      let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).visibleFrame

      let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
      switch resizeScheme {
      case .mpvGeometry:
        // check if have mpv geometry set (initial window position/size)
        guard let mpvGeometry = player.getMPVGeometry() else {
          if cxt.sessionState.isOpeningFileManually {
            log.debug{"[GeoTF:\(cxt.name)] No mpv geometry found. Will fall back to windowedModeGeoLastClosed"}
            return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                            video: outputVidGeo, keepFullScreenDimensions: true,
                                                            applyOffsetIndex: player.openedWindowsSetIndex, log)
          } else {
            log.debug{"[GeoTF:\(cxt.name)] No mpv geometry found. Will fall back to minimal resize"}
            return nil
          }
        }

        var preferredGeo = windowGeo
        if Preference.bool(for: .lockViewportToVideoSize), cxt.sessionState.canUseIntendedViewportSize,
           let intendedViewportSize = player.info.intendedViewportSize {
          log.verbose{"[GeoTF:\(cxt.name)] Using intendedViewportSize \(intendedViewportSize)"}
          preferredGeo = windowGeo.scalingViewport(to: intendedViewportSize)
        }
        log.verbose{"[GeoTF:\(cxt.name)] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)"}
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)

      case .simpleVideoSizeMultiple:
        let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
        if resizeWindowStrategy == .fitScreen {
          log.verbose{"[GeoTF:\(cxt.name)] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)"}
          return windowGeo.scalingViewport(to: screenVisibleFrame.size, screenFit: .centerInside)
        } else {
          let resizeRatio = resizeWindowStrategy.ratio
          let scaledVideoSize = outputVidGeo.videoSizeCAR * resizeRatio
          log.verbose{"[GeoTF:\(cxt.name)] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(scaledVideoSize)"}
          let centeredScaledGeo = windowGeo.scalingVideo(to: scaledVideoSize, screenFit: .centerInside, mode: outputLayout.mode)
          // User has actively resized the video. Assume this is the new preferred resolution
          player.info.intendedViewportSize = centeredScaledGeo.viewportSize
          log.verbose{"[GeoTF:\(cxt.name)] After scaleVideo: \(centeredScaledGeo)"}
          return centeredScaledGeo
        }
      }
    }
  }
}

// MARK: - PlayerWindowController: Geometry Transform Tasks
extension PlayerWindowController {

  /// Builds tasks to transition the window to its "initial" layout.
  ///
  /// Sets the window layout when one of the following is happening:
  /// 1. Restoring from prior launch  (`PWinSessionState.restoring`)
  /// 2. Reusing existing window for new file (`PWinSessionState.newReplacingExisting`)
  /// 3. Opening window for new file (`PWinSessionState.creatingNew`)
  ///
  /// See `PWinSessionState`.
  fileprivate func buildWindowInitialLayoutTasks(using builder: GeometryTransform.TaskBuilder) -> [IINAAnimation.Task] {
    assert(DispatchQueue.isExecutingIn(.main))

    guard builder.cxt.sessionState.isStartingSession, let window = window else {
      return []
    }

    let cxt = builder.cxt
    let currentMediaAudioStatus = cxt.currentMediaAudioStatus
    var tasks: [IINAAnimation.Task]

    switch cxt.sessionState {

    case .restoring(let priorState):
      tasks = buildTasksToRestoreLayout(priorState, builder)

    case .newReplacingExisting:
      log.verbose("[GeoTF:\(cxt.name)] Opening a new file in an already open window, mode=\(builder.inputLayout.mode)")

      /// `windowFrame` may be slightly off; update it
      if builder.inputLayout.mode == .windowedNormal {
        /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
        /// Side effect: future opened windows may use this size even if this window wasn't closed. Should be ok?
        PlayerWindowController.windowedModeGeoLastClosed = builder.inputLayout.buildGeometry(windowFrame: window.frame,
                                                                                             screenID: bestScreen.screenID,
                                                                                             video: builder.outputVidGeo)
      } else if builder.inputLayout.mode == .musicMode {
        /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
        PlayerWindowController.musicModeGeoLastClosed = musicModeGeo.clone(windowFrame: window.frame,
                                                                           screenID: bestScreen.screenID,
                                                                           video: builder.outputVidGeo)
      }
      // No additional layout needed
      tasks = []

    case .creatingNew:
      log.verbose("[GeoTF:\(cxt.name)] Window is opening: setting initial layout from app prefs")
      var mode: PlayerWindowMode = .windowedNormal

      if player.startInMusicModeRequested {
        log.debug("[GeoTF:\(cxt.name)] Will open window in music mode as requested via CLI")
        player.startInMusicModeRequested = false  // reset for reuse
        mode = .musicMode
      } else if Preference.bool(for: .autoSwitchToMusicMode) && currentMediaAudioStatus.isAudio {
        log.debug("[GeoTF:\(cxt.name)] Opened media is audio: will open window in music mode")
        mode = .musicMode
      } else if Preference.bool(for: .fullScreenWhenOpen) {
        player.didEnterFullScreenViaUserToggle = false
        let useLegacyFS = Preference.bool(for: .useLegacyFullScreen)
        log.debug("[GeoTF:\(cxt.name)] Changing to \(useLegacyFS ? "legacy " : "")fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
        if useLegacyFS {
          mode = .fullScreenNormal
        } else {
          builder.needsNativeFullScreen = true
        }
      }

      // Set to default layout, but use existing aspect ratio & video size for now, because we don't have that info yet for the new video
      let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: mode, fillingInFrom: lastWindowedLayoutSpec)
      builder.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
      let outputGeoSet = configureNewWindowGeoFromPrefs(builder.outputLayout, builder.outputVidGeo)

      tasks = buildTransitionTasksToInitialLayout(builder, outputGeoSet)
    default:
      Logger.fatal("Invalid PWinSessionState for initial layout: \(cxt.sessionState)")
    }

    // Post-layout task: do other needed config
    tasks.append(.instantTask{ [self] in
      defer {
        if cxt.sessionState.isRestoring, window.isMiniaturized {
          log.verbose("Restoring minimized window; skipping windowIsReadyToShow")
        } else if cxt.sessionState.isRestoring, isWindowHidden {
          log.verbose("Restoring window which was hidden; posting windowMustCancelShow")
          postWindowMustCancelShow()
        } else {
          /// This will fire a notification to `AppDelegate` which will respond by calling `showWindow` when all windows are ready. Post this always.
          log.verbose("Posting windowIsReadyToShow")
          postWindowIsReadyToShow()
        }
      }

      // Run this early when restoring, before showWindow(), to avoid noticeable color flickering
      videoView.refreshAllVideoDisplayState()

      player.refreshSyncUITimer()
      player.touchBarSupport.setupTouchBarUI()

      let shouldDecideDefaultArtStatus = !builder.outputLayout.isMusicMode || (musicModeGeo.isVideoVisible)
      let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? player.info.shouldShowDefaultArt : nil
      if let showDefaultArt {
        // May need to set this while restoring a network audio stream
        updateDefaultArtVisibility(to: showDefaultArt)
      }

      /// This check is after `reloadSelectedTracks` which will ensure that `info.aid` will have been updated with the
      /// current audio track selection, or `0` if none selected.
      /// Before `fileLoaded` it may change to `0` while the track info is still being processed, but this is unhelpful
      /// because it can mislead us into thinking that the user has deselected the audio track.
      if player.info.aid == 0 {
        muteButton.isEnabled = false
        volumeSlider.isEnabled = false
      }

      hideSeekPreviewImmediately()
      quickSettingView.reload()
      updateTitle()
      playlistView.scrollPlaylistToCurrentItem()

      // FIXME: here be race conditions
      if case .newReplacingExisting = sessionState {
        // Need to switch to music mode?
        if Preference.bool(for: .autoSwitchToMusicMode) {
          if player.overrideAutoMusicMode {
            log.verbose("[GeoTF:\(cxt.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y")
          } else if cxt.currentMediaAudioStatus.isAudio && !builder.outputLayout.isMusicMode && !builder.outputLayout.isFullScreen {
            log.debug("[GeoTF:\(cxt.name)] Opened media is audio: auto-switching to music mode")
            player.enterMusicMode(automatically: true, withNewVidGeo: builder.outputVidGeo)
            return  // do not even try to go to full screen if already going to music mode
          } else if cxt.currentMediaAudioStatus == .notAudio && builder.outputLayout.isMusicMode {
            log.debug("[GeoTF:\(cxt.name)] Opened media is not audio: auto-switching to normal window")
            player.exitMusicMode(automatically: true, withNewVidGeo: builder.outputVidGeo)
            return  // do not even try to go to full screen if already going to windowed mode
          }
        }

        // Need to switch to full screen?
        if Preference.bool(for: .fullScreenWhenOpen) && !isFullScreen && !isInMiniPlayer {
          log.debug("[GeoTF:\(cxt.name)] Changing to full screen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
          enterFullScreen()
        }
      }
    })

    return tasks
  }

  /// Generates animation tasks to adjust the window layout appropriately for a newly opened file.
  private func buildTransitionTasksToInitialLayout(_ builder: GeometryTransform.TaskBuilder, _ outputGeoSet: GeometrySet) -> [IINAAnimation.Task] {

    // Set this now, instead of waiting for it to be set by `initialTransition`.
    // Don't want window resize/move listeners doing something untoward.
    isAnimatingLayoutTransition = true

    // Send GeometrySet object to builder so that it doesn't default to current window frame
    log.verbose{"Setting initial \(builder.outputLayout.spec), windowedModeGeo=\(outputGeoSet.windowed), musicModeGeo=\(outputGeoSet.musicMode)"}

    let isRestoring = builder.cxt.sessionState.isRestoring
    let transitionName = "\(isRestoring ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: builder.inputLayout, to: builder.outputLayout.spec,
                                                  isWindowInitialLayout: true, outputGeoSet)

    var tasks: [IINAAnimation.Task] = []
    tasks.append(.instantTask { [self] in
      // For initial layout (when window is first shown), to reduce jitteriness when drawing, do all the layout
      // in a single animation block.
      do {
        for task in initialTransition.tasks {
          try task.runFunc()
        }
      } catch {
        log.error{"Failed to run initial layout tasks: \(error)"}
      }

      if !isRestoring {
        if builder.outputLayout.mode == .windowedNormal {
          player.info.intendedViewportSize = initialTransition.outputGeometry.viewportSize

          // Set window opacity to 0 initially to start fade-in effect
          updateWindowBorderAndOpacity(using: builder.outputLayout, windowOpacity: 0.0)
        }

        if !builder.outputLayout.isFullScreen, Preference.bool(for: .alwaysFloatOnTop) && !player.info.isPaused {
          log.verbose("Setting window OnTop=Y per app pref")
          setWindowFloatingOnTop(true, from: builder.outputLayout)
        }
      }

      /// Note: `isAnimatingLayoutTransition` should be `false` now
      log.verbose("Done with transition to initial layout")
    })

    if builder.needsNativeFullScreen {
      tasks.append(.instantTask { [self] in
        enterFullScreen()
      })
      return tasks
    }

    if isRestoring {
      /// Stored window state may not be consistent with global IINA prefs.
      /// To check this, build another `LayoutSpec` from the global prefs, then compare it to the player's.
      let prefsSpec = LayoutSpec.fromPreferences(fillingInFrom: builder.outputLayout.spec)
      if builder.outputLayout.spec.hasSamePrefsValues(as: prefsSpec) {
        log.verbose{"Saved layout is consistent with IINA global prefs"}
      } else {
        // Not consistent. But we already have the correct spec, so just build a layout from it and transition to correct layout
#if DEBUG
        log.errorDebugAlert{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#else
        log.warn{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#endif
        log.debug{"SavedSpec: \(currentLayout.spec). PrefsSpec: \(prefsSpec)"}
        let transition = buildLayoutTransition(named: "FixInvalidInitialLayout",
                                               from: initialTransition.outputLayout, to: prefsSpec)

        tasks.append(contentsOf: transition.tasks)
      }
    }
    return tasks
  }

  private func buildTasksToRestoreLayout(_ priorState: PlayerSaveState,
                                         _ builder: GeometryTransform.TaskBuilder) -> [IINAAnimation.Task] {
    log.verbose{"Setting geometries from prior state, windowed=\(priorState.geoSet.windowed), musicMode=\(priorState.geoSet.musicMode)"}
    let cxt = builder.cxt

    if let priorLayoutSpec = priorState.layoutSpec {
      log.verbose("[GeoTF:\(cxt.name)] Transitioning to initial layout from prior window state")

      let initialLayoutSpec: LayoutSpec
      if priorLayoutSpec.isNativeFullScreen {
        // Special handling for native fullscreen. Rely on mpv to put us in FS when it is ready
        initialLayoutSpec = priorLayoutSpec.clone(mode: .windowedNormal)
        builder.needsNativeFullScreen = true
      } else {
        initialLayoutSpec = priorLayoutSpec
      }
      builder.outputLayout = LayoutState.buildFrom(initialLayoutSpec)
    } else {
      log.error("[GeoTF:\(cxt.name)] Failed to read LayoutSpec object for restore! Will try to assemble window from prefs instead")
      let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: .windowedNormal, fillingInFrom: lastWindowedLayoutSpec)
      builder.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
    }

    if builder.outputLayout.mode == .musicMode {
      player.overrideAutoMusicMode = true
    }

    // Clean up windowedModeGeo if serious errors found with it
    let priorWindowedModeGeo = priorState.geoSet.windowed
    if !priorWindowedModeGeo.mode.isWindowed || priorWindowedModeGeo.screenFit.isFullScreen {
      log.error{"While transitioning to initial layout: windowedModeGeo from prior state has invalid mode (\(priorWindowedModeGeo.mode)) or screenFit (\(priorWindowedModeGeo.screenFit)). Will generate a fresh windowedModeGeo from saved layoutSpec and last closed window instead"}
      let lastClosedGeo = PlayerWindowController.windowedModeGeoLastClosed
      let windowed: PWinGeometry
      if lastClosedGeo.mode.isWindowed && !lastClosedGeo.screenFit.isFullScreen {
        windowed = builder.outputLayout.convertWindowedModeGeometry(from: lastClosedGeo, video: priorState.geoSet.video,
                                                                    keepFullScreenDimensions: false, log)
      } else {
        windowed = builder.outputLayout.buildDefaultInitialGeometry(screen: bestScreen, video: priorState.geoSet.video)
      }
      let initialGeoSet = priorState.geoSet.clone(windowed: windowed)
      return buildTransitionTasksToInitialLayout(builder, initialGeoSet)
    } else {
      return buildTransitionTasksToInitialLayout(builder, priorState.geoSet)
    }
  }

  // FIXME: this needs to be deleted
  private func configureNewWindowGeoFromPrefs(_ initialLayout: LayoutState, _ videoGeo: VideoGeometry) -> GeometrySet {
    // Should only be here if window is a new window or was previously closed. Copy layout from the last closed window

    let musicModeGeo = PlayerWindowController.musicModeGeoLastClosed.clone(video: videoGeo)

    let windowedModeGeo: PWinGeometry
    if initialLayout.isFullScreen || initialLayout.isMusicMode {
      windowedModeGeo = PlayerWindowController.windowedModeGeoLastClosed

    } else {
      /// Use `minVideoSize` at first when a new window is opened, so that when `transformGeometry()` is called shortly after,
      /// it expands and creates a nice zooming effect. But try to start with video's correct aspect, if available
      let viewportSize = CGSize.computeMinSize(withAspect: videoGeo.videoAspectCAR,
                                               minWidth: Constants.Window.minViewportSize.width,
                                               minHeight: Constants.Window.minViewportSize.height)
      let intendedWindowSize = NSSize(width: viewportSize.width + initialLayout.outsideLeadingBarWidth + initialLayout.outsideTrailingBarWidth,
                                      height: viewportSize.height + initialLayout.outsideTopBarHeight + initialLayout.outsideBottomBarHeight)
      let windowFrame = NSRect(origin: NSPoint.zero, size: intendedWindowSize)
      /// Change the window origin so that it opens where the mouse was when `openURLs` was called. This visually reinforces the user-initiated
      /// behavior and is less jarring than popping out of the periphery. It will move while zooming to its final location, which remains
      /// well-defined based on current user prefs and/or last closed window.
      let mouseLoc = PlayerCore.mouseLocationAtLastOpen ?? NSEvent.mouseLocation
      let mouseLocScreenID = NSScreen.getOwnerOrDefaultScreenID(forPoint: mouseLoc)
      let initialGeo = initialLayout.buildGeometry(windowFrame: windowFrame, screenID: mouseLocScreenID, video: videoGeo).refitted(using: .stayInside)
      let windowSize = initialGeo.windowFrame.size
      let windowOrigin = NSPoint(x: round(mouseLoc.x - (windowSize.width * 0.5)), y: round(mouseLoc.y - (windowSize.height * 0.5)))
      log.verbose("Initial layout: starting with tiny window, videoAspect=\(videoGeo.videoAspectCAR), windowSize=\(windowSize)")
      windowedModeGeo = initialGeo.clone(windowFrame: NSRect(origin: windowOrigin, size: windowSize)).refitted(using: .stayInside)
    }

    return GeometrySet(windowed: windowedModeGeo, musicMode: musicModeGeo, video: videoGeo)
  }

  // MARK: PlayerWindowController: Geometry Transform

  /// Cleanup, update `sessionState` & UI.
  fileprivate func buildEndTask(_ cxt: GeometryTransform.Context, onSuccess: (() -> Void)? = nil) -> IINAAnimation.Task {
    IINAAnimation.Task.instantTask{ [self] in
      log.verbose{"[GeoTF:\(cxt.name)] Running endTask for sessionState=\(cxt.sessionState) vid=\(cxt.vidTrackID)"}
      if cxt.sessionState.isChangingVideoTrack {
        // Set to prevent future duplicate calls from continuing
        cxt.currentPlayback.vidTrackLastSized = cxt.vidTrackID
        // Return to normal status:
        sessionState = .existingSession_continuing

        // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
        // The OSD can have weird stretching glitches if displayed while zooming open...
        if cxt.currentPlayback.state == .loaded {
          // If minimized, the call to DispatchQueue.main.async below doesn't seem to execute. Just do this for all cases now.
          log.debug{"[GeoTF:\(cxt.name)] Updating playback.state = .loadedAndSized, vidTrackLastSized=\(cxt.vidTrackID), will emit fileLoaded notifications"}
          cxt.currentPlayback.state = .loadedAndSized
          // Should refresh EDR each time switching files
          videoView.refreshAllVideoDisplayState()

          // If is network resource, may not be loaded yet. If file, it will be.
          player.postNotification(.iinaFileLoaded)
          player.events.emit(.fileLoaded, data: cxt.currentPlayback.url.absoluteString)
        }
      }

      // Need to call here to ensure file title OSD is displayed when navigating playlist...
      player.refreshSyncUITimer()
      // Fix rare case where window is still invisible after closing in music mode and reopening in windowed
      updateWindowBorderAndOpacity()

      // Always do this in case the video geometry changed:
      player.reloadQuickSettingsView()

      // Must force drawing to cover the case where this player was previously used to play a video
      // and is now playing an audio file without an album cover and without using music mode.
      // See issue #5403.
      videoView.forceDraw()

      if let onSuccess {
        onSuccess()
      }
    }
  }

}
