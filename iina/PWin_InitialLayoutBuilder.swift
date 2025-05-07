//
//  PWInitialLayoutBldr.swift
//  iina
//
//  Created by Matt Svoboda on 2024/08/05
//

import Foundation

/// Window Initial Layout
extension PlayerWindowController {
  class InitialLayoutBuilder {
    let cxt: GeometryTransform.Context
    let inputLayout: LayoutState

    let outputVidGeo: VideoGeometry
    var outputLayout: LayoutState
    fileprivate var needsNativeFullScreen = false

    fileprivate var tasks: [IINAAnimation.Task] = []

    init(cxt: GeometryTransform.Context, currentLayout: LayoutState, outputVidGeo: VideoGeometry) {
      self.cxt = cxt
      self.inputLayout = currentLayout
      self.outputLayout = currentLayout  // for now at least
      self.outputVidGeo = outputVidGeo
    }

    func buildWindowInitialLayoutTasks(for pwc: PlayerWindowController) -> [IINAAnimation.Task] {
      // See below
      pwc.buildWindowInitialLayoutTasks(using: self)
      return tasks
    }
  }


  /// Builds tasks to transition the window to its "initial" layout.
  ///
  /// Sets the window layout when one of the following is happening:
  /// 1. Opening window for new file
  /// 2. Reusing existing window for new file
  /// 3. Restoring from prior launch.
  ///
  /// See `PWinSessionState`.
  fileprivate func buildWindowInitialLayoutTasks(using builder: InitialLayoutBuilder) {
    assert(DispatchQueue.isExecutingIn(.main))

    let cxt = builder.cxt
    let currentMediaAudioStatus = cxt.currentMediaAudioStatus

    guard cxt.sessionState.isStartingSession, let window = window else {
      return
    }

    switch cxt.sessionState {
    case .restoring(let priorState):
      buildForRestore(priorState, builder)

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
      let newGeoSet = configureFromPrefs(builder.outputLayout, builder.outputVidGeo)

      buildTransitionTasks(builder, newGeoSet)
    default:
      Logger.fatal("Invalid PWinSessionState for initial layout: \(cxt.sessionState)")
    }

    builder.tasks.append(.instantTask{ [self] in
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
  }

  /// Generates animation tasks to adjust the window layout appropriately for a newly opened file.
  private func buildTransitionTasks(_ builder: InitialLayoutBuilder, _ newGeoSet: GeometrySet) {

    // Don't want window resize/move listeners doing something untoward
    isAnimatingLayoutTransition = true

    // Send GeometrySet object to builder so that it doesn't default to current window frame
    log.verbose{"Setting initial \(builder.outputLayout.spec), windowedModeGeo=\(newGeoSet.windowed), musicModeGeo=\(newGeoSet.musicMode)"}

    let isRestoring = builder.cxt.sessionState.isRestoring
    let transitionName = "\(isRestoring ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: builder.inputLayout, to: builder.outputLayout.spec,
                                                  isWindowInitialLayout: true, newGeoSet)

    builder.tasks.append(.instantTask { [self] in
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
      builder.tasks.append(.instantTask { [self] in
        enterFullScreen()
      })
      return
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

        builder.tasks.append(contentsOf: transition.tasks)
      }
    }
  }

  private func buildForRestore(_ priorState: PlayerSaveState, _ builder: InitialLayoutBuilder) {
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
      buildTransitionTasks(builder, initialGeoSet)
    } else {
      buildTransitionTasks(builder, priorState.geoSet)
    }

  }

  private func configureFromPrefs(_ initialLayout: LayoutState, _ videoGeo: VideoGeometry) -> GeometrySet {
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
}
