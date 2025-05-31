//
//  GeometryTransform.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-08.
//


/// Applies changes to window geometry, possibly animating any changes.
///
/// # Important Fields:
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
struct GeometryTransform {
  // MARK: - GeometryTransform Fields

  /// Name of the transform
  let name: String

  let player: PlayerCore

  var log: Logger.Subsystem { player.log }

  /// If `stateTransition` is `nil` (omitted), treat as no-op and continue to `videoTransform`.
  /// If `stateTransition` returns `nil`, transition should be aborted.
  let stateTransition: PWinSessionState.Transform?

  let videoTransform: VideoGeometry.Transform?
  let windowedTransform: PWinGeometry.Transform?
  let musicModeTransform: MusicModeGeometry.Transform?

  let onSuccess: (() -> Void)?

  init(_ name: String,
       _ player: PlayerCore,
       state: ((Context) -> PWinSessionState?)? = nil,
       video: ((Context) -> VideoGeometry?)? = nil,
       windowed: ((Context) -> PWinGeometry?)? = nil,
       musicMode: ((Context) -> MusicModeGeometry?)? = nil,
       onSuccess: (() -> Void)? = nil) {
    self.name = name
    self.player = player
    self.stateTransition = state
    self.videoTransform = video
    self.windowedTransform = windowed
    self.musicModeTransform = musicMode
    self.onSuccess = onSuccess
  }

  /// Do not call directly. Should only be called from an animation pipeline.
  /// Use `IINAAnimation.Pipeline.submit` to execute a `GeometryTransform`.
  func execute() {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let pwc = player.windowController else { return }

    // Get a copy of geo inside animationPipeline to ensure serial access.
    // This is reused asynchronously down below, so some parts of it may fall out of date, but
    // shouldn't be the parts we need for now...
    let oldGeo = pwc.geo

    // Need to be inside mpv queue to ensuren serial access to sessionState et al
    player.mpv.queue.async { [self] in

      /// Make sure `doAfter` is always executed
      func abort(_ reasonDebugMsg: String) {
        log.verbose{"[GeoTF:\(name)] Aborting TF: \(reasonDebugMsg)"}
        pwc.animationPipeline.geoTransformDidFinish(self)
      }

      guard !player.isStopping else {
        return abort("player stopping (status=\(player.state))")
      }

      guard let currentPlayback = player.info.currentPlayback else {
        return abort("currentPlayback is nil")
      }

      let sessionState = pwc.sessionState

      // File needs to be loaded before we can know its video geometry.
      // ...Unless we are restoring. But then we still want to wait until all windows are done loading, so we can open them all at once.
      // ...But streaming files can often fail to connect. So reopen those right away if restoring (we already have their saved geometry anyway).
      guard currentPlayback.state.isAtLeast(.loaded) || (sessionState.isRestoring && currentPlayback.isNetworkResource) else {
        return abort("playbackState=\(currentPlayback.state) restoring=\(sessionState.isRestoring.yn) network=\(currentPlayback.isNetworkResource.yn)")
      }

      let vidTrackID = player.info.vid ?? 0

      var cxt = GeometryTransform.Context(tf: self, currentPlayback: currentPlayback, vidTrackID: vidTrackID,
                                          currentMediaAudioStatus: player.info.currentMediaAudioStatus,
                                          sessionState: sessionState, oldGeo: oldGeo)

      /// 1: Apply `stateChange` if present
      if let stateChange = stateTransition {
        log.verbose{"[GeoTF:\(name)] Calling sessionStateChange"}
        guard let newSessionState = stateChange(cxt) else {
          return abort("state change func returned nil from sessionState=\(sessionState)")
        }
        log.verbose{"[GeoTF:\(name)] Result of sessionStateChange: \(sessionState) → \(newSessionState.description)"}
        cxt.sessionState = newSessionState
      } else {
        log.verbose{"[GeoTF:\(name)] No sessionStateChange func, will stay at: \(sessionState)"}
      }

      /// 2: Apply `videoTransform` if present.
      /// This needs to be on the mpv queue, because some transforms make mpv calls.
      if let videoTransform {
        log.verbose{"[GeoTF:\(name)] Calling videoTransform"}
        guard let transformedGeo = videoTransform(cxt) else {
          return abort("videoTransform returned nil")
        }
        log.verbose{"[GeoTF:\(name)] Result of videoTransform: \(transformedGeo)"}
        cxt.outputVidGeo = transformedGeo
      } else {
        log.verbose{"[GeoTF:\(name)] No videoTransform given, skipping"}
        cxt.outputVidGeo = cxt.oldGeo.video
      }

      pwc.animationPipeline.submitInstantTask { [self] in
        log.trace{"[GeoTF:\(name)] Starting main thread work"}

        // Cache this inside animation task to ensure serial access
        cxt.inputLayout = pwc.currentLayout

        // Update context's geo with current window frame
        cxt.oldGeo = pwc.buildGeoSet(from: cxt.outputLayout, baseGeoSet: cxt.oldGeo, forceWinFrameUpdate: !player.isRestoring)

        /// 3. (Optional) Transition window to initial layout. Must exexcute before `buildApplyTransformTasks`.
        /// Will return` []` if not applicable.
        var immediateTasks = pwc.buildWindowInitialLayoutTasks(using: &cxt)

        /// 4. Apply `windowedTransform` / `musicModeTransform`
        let transformTasks = cxt.buildApplyTransformTasks()

        if sessionState.isStartingSession {
          let isRestoringMinimizedWindow = sessionState.isRestoring && UIState.shared.windowsMinimized.contains(pwc.window!.savedStateName)
          if isRestoringMinimizedWindow {
            // Minimized: can't rely on showWindow() being called, but window changes won't be seen anyway. Just run end task now.
            log.verbose{"[GeoTF:\(name)] Restoring minimized window: will run tasks immediately instead of enqueueing"}
            immediateTasks += transformTasks
          } else {
            /// These tasks should not execute until *after* `super.showWindow` is called.
            pwc.pendingVideoGeoUpdateTasks = transformTasks
          }

        } else {
          immediateTasks += transformTasks

          /// 5. Need to switch to music mode? Append to above tasks
          if case .existingSession_startingNewPlayback = sessionState, Preference.bool(for: .autoSwitchToMusicMode) {
            let layout = cxt.outputLayout
            if player.overrideAutoMusicMode {
              log.verbose{"[GeoTF:\(name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y"}
            } else if cxt.currentMediaAudioStatus.isAudio && !layout.isMusicMode && !layout.isFullScreen {
              log.debug{"[GeoTF:\(name)] Opened media is audio: auto-switching to music mode"}
              let geo = pwc.buildGeoSet(video: cxt.outputVidGeo, from: layout)
              let enterMusicModeTransitionTasks = pwc.buildTasksToEnterMusicMode(automatically: true, from: layout, geo)
              immediateTasks += enterMusicModeTransitionTasks
            } else if cxt.currentMediaAudioStatus == .notAudio && layout.isMusicMode {
              log.debug{"[GeoTF:\(name)] Opened media is not audio: auto-switching to normal window"}
              let geo = pwc.buildGeoSet(video: cxt.outputVidGeo, from: layout)
              let enterMusicModeTransitionTasks = pwc.buildTasksToExitMusicMode(automatically: true, from: layout, geo)
              immediateTasks += enterMusicModeTransitionTasks
            }
          }
        }

        pwc.animationPipeline.submit(immediateTasks)
      }
    }
  }


  /// Standard `VideoGeometry.Transform` for use in response to a `vid` property change event from mpv.
  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  /// If current media's vid track changed, may need to apply new geometry
  static func vidTrackChanged(_ context: Context) -> VideoGeometry? {
    context.vidTrackChanged()
  }

  // MARK: - Context

  /// `struct GeometryTransform.Context`
  /// Can be used for `VideoGeometry` transforms, `PWinGeometry` transforms, or `MusicModeGeometry` transforms.
  /// See also: `VideoGeo_Sync.swift` for syncing `VideoGeometry` from mpv.
  struct Context {
    // The transform spec (immutable)
    let tf: GeometryTransform

    // Playback state at the start of execution.
    let currentPlayback: Playback
    let vidTrackID: Int
    let currentMediaAudioStatus: PlaybackInfo.MediaAudioStatus

    /// Contains most up-to-date version of the geometries (as well as possibly unapplied changes), which transforms should build
    /// on top of. (The `PlayerWindowController`'s `geo` field should not be referenced).
    var oldGeo: GeometrySet

    var inputVidGeo: VideoGeometry { oldGeo.video }
    /// The transformed `VideoGeometry`.
    var outputVidGeo: VideoGeometry {
      get {
        guard let _outputVidGeo else {
          Logger.fatal("Context.outputVidGeo cannot be accessed until after `videoTransform` is called")
        }
        return _outputVidGeo
      }
      set {
        _outputVidGeo = newValue
      }
    }
    fileprivate(set) var _outputVidGeo: VideoGeometry? = nil

    var inputLayout: LayoutState {
      get {
        guard let _inputLayout else {
          Logger.fatal("Context.inputLayout cannot be accessed until after `stateTransition` is called")
        }
        return _inputLayout
      }
      set {
        _inputLayout = newValue
        _outputLayout = newValue
      }
    }
    fileprivate(set) var _inputLayout: LayoutState? = nil

    /// Defaults to `inputLayout`, but can be overwritten by `buildWindowInitialLayoutTasks`.
    /// Do not reference until after that is called.
    var outputLayout: LayoutState {
      get {
        guard let _outputLayout else {
          Logger.fatal("Context.outputLayout cannot be accessed until after `stateTransition` is called")
        }
        return _outputLayout
      }
      set {
        _outputLayout = newValue
      }
    }
    fileprivate(set) var _outputLayout: LayoutState? = nil

    fileprivate var needsNativeFullScreen = false

    var sessionState: PWinSessionState

    // - Other derived properties

    var name: String { tf.name }
    var player: PlayerCore { tf.player }
    var pwc: PlayerWindowController { player.windowController! }
    var log: Logger.Subsystem { player.log }

    init(tf: GeometryTransform, currentPlayback: Playback, vidTrackID: Int,
         currentMediaAudioStatus: PlaybackInfo.MediaAudioStatus,
         sessionState: PWinSessionState, oldGeo: GeometrySet) {
      self.tf = tf
      self.currentPlayback = currentPlayback
      self.vidTrackID = vidTrackID
      self.currentMediaAudioStatus = currentMediaAudioStatus
      self.sessionState = sessionState
      self.oldGeo = oldGeo
    }

    /// Only `transformGeometry` should call this.
    fileprivate func buildApplyTransformTasks() -> [IINAAnimation.Task] {
      log.verbose{"[GeoTF:\(name)] Building transform tasks, mode=\(outputLayout.mode)"}

      // There's no good animation for rotation (yet), so just do as little animation as possible in this case
      var duration: CGFloat = isVideoRotating ? 0.0 : Constants.AnimationDuration.videoReconfig
      var timing = CAMediaTimingFunctionName.easeInEaseOut
      var tasks: [IINAAnimation.Task]

      switch outputLayout.mode {

      case .windowedNormal:
        let resizedGeo: PWinGeometry?

        if let windowedTransform = tf.windowedTransform {
          resizedGeo = windowedTransform(self)
        } else {
          switch sessionState {
          case .restoring(_):
            log.verbose{"[GeoTF:\(name)] Restore is in progress: no transform needed"}
            // still need post-transition task
            return [.instantTask{ [self] in
              doPostTransformWork()
            }]

          case .creatingNew:
            // Just opened new window. Use a longer duration for this one, because the window starts small and will zoom into place.
            duration = Constants.AnimationDuration.initialVideoReconfig
            timing = .linear
            resizedGeo = applyResizePrefsForNewPlaybackInWindowedMode()

          case .newReplacingExisting, .existingSession_startingNewPlayback:
            resizedGeo = applyResizePrefsForNewPlaybackInWindowedMode()

          case .existingSession_videoTrackChangedForSamePlayback,
              .existingSession_continuing:
            // Not a new file. Some other change to a video geo property. Fall through and resize minimally
            resizedGeo = nil

          case .noSession:
            Logger.fatal("[GeoTF:\(name)] Invalid sessionState: \(sessionState)")
          }
        }

        let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let newGeo = resizedGeo ?? oldGeo.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                                       intendedViewportSize: intendedViewportSize)

        let showDefaultArt: Bool? = player.info.shouldShowDefaultArt

        log.verbose{"[GeoTF:\(name)] Building windowed tasks: newSess=\(sessionState) defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(newGeo)"}
        tasks = pwc.buildApplyWindowGeoTasks(newGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

      case .fullScreenNormal:
        let intendedViewportSize: CGSize? = sessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let newWinGeo = oldGeo.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                            intendedViewportSize: intendedViewportSize)
        let fsGeo = outputLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, video: outputVidGeo)
        let showDefaultArt: Bool? = player.info.shouldShowDefaultArt
        log.verbose{"[GeoTF:\(name)] Building FS tasks: defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(fsGeo)"}

        tasks = pwc.buildApplyFullScreenGeoTasks(fsGeo: fsGeo, newWindowedGeo: newWinGeo, duration: duration, showDefaultArt: showDefaultArt)

      case .musicMode:
        if case .creatingNew = sessionState {
          log.verbose{"[GeoTF:\(name)] Music mode already handled for opened window: \(oldGeo.musicMode)"}
          tasks = []
          break
        }
        let oldMusicModeGeo = oldGeo.musicMode  // has updated windowFrame
        let newMusicModeGeo: MusicModeGeometry
        if let musicModeTransform = tf.musicModeTransform {
          guard let transformedGeo = musicModeTransform(self) else {
            tasks = []
            break
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
        log.verbose{"[GeoTF:\(name)] Building musicMode tasks: sess=\(sessionState) defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(newMusicModeGeo)"}
        tasks = pwc.buildApplyMusicModeGeoTasks(from: oldMusicModeGeo, to: newMusicModeGeo,
                                                duration: duration, showDefaultArt: showDefaultArt)
      default:
        // Interactive mode. Should be handled by its special code. Don't step on it.
        log.debug{"[GeoTF:\(name)] Invalid mode for TF: \(outputLayout.mode)"}
        tasks = []
        // Fall through and add post-work task
      }

      // Task: post-transform work
      tasks.append(.instantTask{ [self] in
        doPostTransformWork()
      })

      return tasks
    }

    /// Cleanup, update `sessionState` & UI.
    fileprivate func doPostTransformWork() {
      log.verbose{"[GeoTF:\(name)] Running doPostTransformWork task for sessionState=\(sessionState) vid=\(vidTrackID)"}
      let pwc = player.windowController!
      if sessionState.isChangingVideoTrack {
        // Set to prevent future duplicate calls from continuing
        currentPlayback.vidTrackLastSized = vidTrackID
        // Return to normal status:
        pwc.sessionState = .existingSession_continuing

        // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
        // The OSD can have weird stretching glitches if displayed while zooming open...
        if currentPlayback.state == .loaded {
          // If minimized, the call to DispatchQueue.main.async below doesn't seem to execute. Just do this for all cases now.
          log.debug{"[GeoTF:\(name)] Updating playback.state = .loadedAndSized, vidTrackLastSized=\(vidTrackID), will emit fileLoaded notifications"}
          currentPlayback.state = .loadedAndSized
          // Should refresh EDR each time switching files
          pwc.videoView.refreshAllVideoDisplayState()

          // If is network resource, may not be loaded yet. If file, it will be.
          player.postNotification(.iinaFileLoaded)
          player.events.emit(.fileLoaded, data: currentPlayback.url.absoluteString)
        }
      }

      // Need to call here to ensure file title OSD is displayed when navigating playlist...
      player.refreshSyncUITimer()
      // Fix rare case where window is still invisible after closing in music mode and reopening in windowed
      pwc.updateWindowBorderAndOpacity()

      // Always do this in case the video geometry changed:
      player.reloadQuickSettingsView()

      // Must force drawing to cover the case where this player was previously used to play a video
      // and is now playing an audio file without an album cover and without using music mode.
      // See issue #5403.
      pwc.videoView.forceDraw()

      if let onSuccess = tf.onSuccess {
        onSuccess()
      }

      pwc.animationPipeline.geoTransformDidFinish(tf)
    }

    /// Applies the prefs `.resizeWindowTiming` & `resizeWindowScheme`, if applicable.
    /// Returns `nil` if no applicable settings were found/applied, and should fall back to minimal resize.
    private func applyResizePrefsForNewPlaybackInWindowedMode() -> PWinGeometry? {
      // resize option applies
      let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      switch resizeTiming {
      case .always:
        log.verbose{"[GeoTF:\(name)] FileOpened & resizeTiming='Always' → will resize window"}
      case .onlyWhenOpen:
        if !sessionState.isStartingNewPlaybackManually {
          log.verbose{"[GeoTF:\(name)] FileOpened & resizeTiming='OnlyWhenOpen', but isStartingNewPlaybackManually=N → will resize minimally"}
          return nil
        }
      case .never:
        if !sessionState.isStartingNewPlaybackManually {
          log.verbose{"[GeoTF:\(name)] FileOpened (not manually) & resizeTiming='Never' → will resize minimally"}
          return nil
        }
        log.verbose{"[GeoTF:\(name)] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)"}
        return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                        video: outputVidGeo,
                                                        pinWidthOrHeightIfAtMax: true,
                                                        pinToAnySideOfScreen: true,
                                                        applyOffsetIndex: player.openedWindowsSetIndex, log)
      }

      let windowGeo = oldGeo.windowed.clone(video: outputVidGeo)
      let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).visibleFrame

      let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
      switch resizeScheme {
      case .mpvGeometry:
        // check if have mpv geometry set (initial window position/size)
        guard let mpvGeometry = player.getMPVGeometry() else {
          if sessionState.isStartingNewPlaybackManually {
            log.debug{"[GeoTF:\(name)] No mpv geometry found, starting new playback: will fall back to windowedModeGeoLastClosed"}
            return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                            video: outputVidGeo,
                                                            pinWidthOrHeightIfAtMax: true,
                                                            pinToAnySideOfScreen: true,
                                                            applyOffsetIndex: player.openedWindowsSetIndex, log)
          } else {
            log.debug{"[GeoTF:\(name)] No mpv geometry found. Will fall back to minimal resize"}
            return nil
          }
        }

        var preferredGeo = windowGeo
        if Preference.bool(for: .lockViewportToVideoSize), sessionState.canUseIntendedViewportSize,
           let intendedViewportSize = player.info.intendedViewportSize {
          log.verbose{"[GeoTF:\(name)] Using intendedViewportSize \(intendedViewportSize)"}
          preferredGeo = windowGeo.scalingViewport(to: intendedViewportSize)
        }
        log.verbose{"[GeoTF:\(name)] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)"}
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)

      case .simpleVideoSizeMultiple:
        let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
        if resizeWindowStrategy == .fitScreen {
          log.verbose{"[GeoTF:\(name)] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)"}
          return windowGeo.scalingViewport(to: screenVisibleFrame.size, screenFit: .centerInside)
        } else {
          let resizeRatio = resizeWindowStrategy.ratio
          let scaledVideoSize = outputVidGeo.videoSizeCAR * resizeRatio
          log.verbose{"[GeoTF:\(name)] Applied resizeRatio (\(resizeRatio)) to newVideoSize → \(scaledVideoSize)"}
          let centeredScaledGeo = windowGeo.scalingVideo(to: scaledVideoSize, screenFit: .centerInside, mode: outputLayout.mode)
          // User has actively resized the video. Assume this is the new preferred resolution
          player.info.intendedViewportSize = centeredScaledGeo.viewportSize
          log.verbose{"[GeoTF:\(name)] After scaleVideo: \(centeredScaledGeo)"}
          return centeredScaledGeo
        }
      }
    }

    /// Does this `GeometryTransform` contain a change to video rotation?
    var isVideoRotating: Bool {
      inputVidGeo.userRotation != outputVidGeo.userRotation
    }

    /// Standard `VideoGeometry.Transform` for use in response to a `vid` property change event from mpv.
    /// If current media is file, this should be called after it is done loading.
    /// If current media is network resource, should be called immediately & show buffering msg.
    /// If current media's vid track changed, may need to apply new geometry
    ///
    /// See: `GeometryTransform.vidTrackChanged`
    fileprivate func vidTrackChanged() -> VideoGeometry? {
      assert(DispatchQueue.isExecutingIn(player.mpv.queue))

      guard let videoGeo = syncVideoParamsFromMpv() else { return nil }
      log.debug{"[GeoTF:\(name)] Derived videoGeo \(videoGeo)"}
      return videoGeo
    }  // end of transform block

  }  // end struct GeometryTransform.Context
}

// MARK: - Window Initial Layout

extension PlayerWindowController {

  /// Builds tasks to transition the window to its "initial" layout.
  ///
  /// Sets the window layout when one of the following is happening:
  /// 1. Restoring from prior launch  (`PWinSessionState.restoring`)
  /// 2. Reusing existing window for new file (`PWinSessionState.newReplacingExisting`)
  /// 3. Opening window for new file (`PWinSessionState.creatingNew`)
  ///
  /// See `PWinSessionState`.
  fileprivate func buildWindowInitialLayoutTasks(using cxt: inout GeometryTransform.Context) -> [IINAAnimation.Task] {
    assert(DispatchQueue.isExecutingIn(.main))

    guard cxt.sessionState.isStartingSession, let window = window else {
      log.verbose("[GeoTF:\(cxt.name)] No initial layout tasks needed: sessState=\(cxt.sessionState)")
      return []
    }

    var tasks: [IINAAnimation.Task]

    switch cxt.sessionState {

    case .restoring(let priorState):
      tasks = buildTasksToRestoreLayout(priorState, &cxt)

    case .newReplacingExisting:
      log.verbose("[GeoTF:\(cxt.name)] Opening a new file in an already open window, mode=\(cxt.inputLayout.mode)")

      /// `windowFrame` may be slightly off; update it
      if cxt.inputLayout.mode == .windowedNormal {
        /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
        /// Side effect: future opened windows may use this size even if this window wasn't closed. Should be ok?
        PlayerWindowController.windowedModeGeoLastClosed = cxt.inputLayout.buildGeometry(windowFrame: window.frame,
                                                                                             screenID: bestScreen.screenID,
                                                                                             video: cxt.outputVidGeo)
      } else if cxt.inputLayout.mode == .musicMode {
        /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
        PlayerWindowController.musicModeGeoLastClosed = cxt.oldGeo.musicMode.clone(windowFrame: window.frame,
                                                                                           screenID: bestScreen.screenID,
                                                                                           video: cxt.outputVidGeo)
      }
      // No additional layout needed
      tasks = []

    case .creatingNew:
      log.verbose{"[GeoTF:\(cxt.name)] Window is opening: building initial layout tasks"}

      tasks = buildTasksForNewWindow(&cxt)

    default:
      Logger.fatal("Invalid PWinSessionState for initial layout: \(cxt.sessionState)")
    }

    // Post-layout task: do other needed config
    let cxtSnapshot = cxt
    tasks.append(.instantTask{ [self] in
      doPostInitialLayoutTask(cxtSnapshot, windowIsMinimized: window.isMiniaturized)
    })

    return tasks
  }

  private func doPostInitialLayoutTask(_ cxt: GeometryTransform.Context, windowIsMinimized: Bool) {
    defer {
      if cxt.sessionState.isRestoring, windowIsMinimized {
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

    let shouldDecideDefaultArtStatus = !cxt.outputLayout.isMusicMode || (musicModeGeo.isVideoVisible)
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
    if currentLayout.isPlaylistVisible {
      playlistView.scrollPlaylistToCurrentItem()
    } else {
      playlistView.needsScrollToCurrentItem = true  // reset flag for when it does open
    }

    // FIXME: here be race conditions
    if case .newReplacingExisting = sessionState {
      // Need to switch to music mode?
      if Preference.bool(for: .autoSwitchToMusicMode) {
        if player.overrideAutoMusicMode {
          log.verbose("[GeoTF:\(cxt.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y")
        } else if cxt.currentMediaAudioStatus.isAudio && !cxt.outputLayout.isMusicMode && !cxt.outputLayout.isFullScreen {
          log.debug("[GeoTF:\(cxt.name)] Opened media is audio: auto-switching to music mode")
          player.enterMusicMode(automatically: true, withNewVidGeo: cxt.outputVidGeo)
          return  // do not even try to go to full screen if already going to music mode
        } else if cxt.currentMediaAudioStatus == .notAudio && cxt.outputLayout.isMusicMode {
          log.debug("[GeoTF:\(cxt.name)] Opened media is not audio: auto-switching to normal window")
          player.exitMusicMode(automatically: true, withNewVidGeo: cxt.outputVidGeo)
          return  // do not even try to go to full screen if already going to windowed mode
        }
      }

      // Need to switch to full screen?
      if Preference.bool(for: .fullScreenWhenOpen) && !isFullScreen && !isInMiniPlayer {
        log.debug("[GeoTF:\(cxt.name)] Changing to full screen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
        enterFullScreen()
      }
    }
  }

  /// Generates animation tasks to adjust the window layout appropriately for a newly opened file.
  private func buildTransitionTasksToInitialLayout(_ cxt: GeometryTransform.Context, _ outputGeoSet: GeometrySet) -> [IINAAnimation.Task] {

    // Set this now, instead of waiting for it to be set by `initialTransition`.
    // Don't want window resize/move listeners doing something untoward.
    isAnimatingLayoutTransition = true

    // Send GeometrySet object to builder so that it doesn't default to current window frame
    log.verbose{"[GeoTF:\(cxt.name)] Setting initial \(cxt.outputLayout.spec), windowedModeGeo=\(outputGeoSet.windowed), musicModeGeo=\(outputGeoSet.musicMode)"}

    let isRestoring = cxt.sessionState.isRestoring
    let transitionName = "\(isRestoring ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: cxt.inputLayout, to: cxt.outputLayout.spec,
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
        log.error{"[GeoTF:\(cxt.name)] Failed to run initial layout tasks: \(error)"}
      }

      if !isRestoring {
        if cxt.outputLayout.mode == .windowedNormal {
          player.info.intendedViewportSize = initialTransition.outputGeometry.viewportSize

          // Set window opacity to 0 initially to start fade-in effect
          updateWindowBorderAndOpacity(using: cxt.outputLayout, windowOpacity: 0.0)
        }

        if !cxt.outputLayout.isFullScreen, Preference.bool(for: .alwaysFloatOnTop) && !player.info.isPaused {
          log.verbose("[GeoTF:\(cxt.name)] Setting window OnTop=Y per app pref")
          setWindowFloatingOnTop(true, from: cxt.outputLayout)
        }
      }

      /// Note: `isAnimatingLayoutTransition` should be `false` now
      log.verbose("[GeoTF:\(cxt.name)] Done with transition to initial layout")
    })

    if cxt.needsNativeFullScreen {
      tasks.append(.instantTask { [self] in
        enterFullScreen()
      })
      return tasks
    }

    if isRestoring {
      /// Stored window state may not be consistent with global IINA prefs.
      /// To check this, build another `LayoutSpec` from the global prefs, then compare it to the player's.
      let prefsSpec = LayoutSpec.fromPreferences(fillingInFrom: cxt.outputLayout.spec)
      if cxt.outputLayout.spec.hasSamePrefsValues(as: prefsSpec) {
        log.verbose{"[GeoTF:\(cxt.name)] Saved layout is consistent with IINA global prefs"}
      } else {
        // Not consistent. But we already have the correct spec, so just build a layout from it and transition to correct layout
#if DEBUG
        log.errorDebugAlert{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#else
        log.warn{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#endif
        log.debug{"[GeoTF:\(cxt.name)] SavedSpec: \(currentLayout.spec). PrefsSpec: \(prefsSpec)"}
        let transition = buildLayoutTransition(named: "FixInvalidInitialLayout",
                                               from: initialTransition.outputLayout, to: prefsSpec)

        tasks.append(contentsOf: transition.tasks)
      }
    }

    return tasks
  }

  private func buildTasksToRestoreLayout(_ priorState: PlayerSaveState,
                                         _ cxt: inout GeometryTransform.Context) -> [IINAAnimation.Task] {
    if let priorLayoutSpec = priorState.layoutSpec {
      log.verbose("[GeoTF:\(cxt.name)] Transitioning to initial layout from prior window state")

      let initialLayoutSpec: LayoutSpec
      if priorLayoutSpec.isNativeFullScreen {
        // Special handling for native fullscreen. Rely on mpv to put us in FS when it is ready
        initialLayoutSpec = priorLayoutSpec.clone(mode: .windowedNormal)
        cxt.needsNativeFullScreen = true
      } else {
        initialLayoutSpec = priorLayoutSpec
      }
      cxt.outputLayout = LayoutState.buildFrom(initialLayoutSpec)
    } else {
      log.error("[GeoTF:\(cxt.name)] Failed to read LayoutSpec object for restore! Will try to assemble window from prefs instead")
      let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: .windowedNormal, fillingInFrom: lastWindowedLayoutSpec)
      cxt.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
    }

    if cxt.outputLayout.mode == .musicMode {
      player.overrideAutoMusicMode = true
    }

    // Clean up windowedModeGeo if serious errors found with it
    var geoSet = priorState.geoSet

    if !geoSet.windowed.mode.isWindowed || geoSet.windowed.screenFit.isFullScreen {
      log.error{"[GeoTF:\(cxt.name)] Initial layout: windowedModeGeo from prior state has invalid mode (\(geoSet.windowed.mode)) or screenFit (\(geoSet.windowed.screenFit)). Will generate a fresh windowedModeGeo from saved layoutSpec and last closed window instead"}

      let lastClosedGeo = PlayerWindowController.windowedModeGeoLastClosed
      let windowed: PWinGeometry
      if lastClosedGeo.mode.isWindowed && !lastClosedGeo.screenFit.isFullScreen {
        windowed = cxt.outputLayout.convertWindowedModeGeometry(from: lastClosedGeo, video: priorState.geoSet.video,
                                                                pinWidthOrHeightIfAtMax: false, pinToAnySideOfScreen: false, log)
      } else {
        windowed = cxt.outputLayout.buildDefaultInitialGeometry(screen: bestScreen, video: priorState.geoSet.video)
      }
      geoSet = geoSet.clone(windowed: windowed)

    } else if geoSet.windowed.outsideBars.totalWidth + geoSet.windowed.insideBars.totalWidth > geoSet.windowed.windowFrame.width {
      log.error{"[GeoTF:\(cxt.name)] Initial layout: windowedModeGeo from prior state has window size (\(geoSet.windowed.windowFrame.size)) which is too small to accomodate bars (outside=\(geoSet.windowed.outsideBars), inside=\(geoSet.windowed.insideBars)). Will close sidebars."}

      cxt.outputLayout = LayoutState.buildFrom(cxt.outputLayout.spec.withSidebarsHidden())
      let outsideNew = geoSet.windowed.outsideBars.clone(trailing: 0, leading: 0)
      let insideNew = geoSet.windowed.insideBars.clone(trailing: 0, leading: 0)
      let windowed = geoSet.windowed.clone(outsideBars: outsideNew, insideBars: insideNew)

      geoSet = priorState.geoSet.clone(windowed: windowed)
    }

    return buildTransitionTasksToInitialLayout(cxt, geoSet)
  }

  /// Creates IINAAnimation tasks for the case of `PWinSessionState.creatingNew`.
  /// Also sets `cxt.needsNativeFullScreen` & `cxt.outputLayout`.
  private func buildTasksForNewWindow(_ cxt: inout GeometryTransform.Context) -> [IINAAnimation.Task] {
    var mode: PlayerWindowMode = .windowedNormal

    if player.startInMusicModeRequested {
      log.debug{"[GeoTF:\(cxt.name)] Will open window in music mode as requested via CLI"}
      player.startInMusicModeRequested = false  // reset for reuse
      mode = .musicMode
    } else if Preference.bool(for: .autoSwitchToMusicMode) && cxt.currentMediaAudioStatus.isAudio {
      log.debug{"[GeoTF:\(cxt.name)] Opened media is audio: will open window in music mode"}
      mode = .musicMode
    } else if Preference.bool(for: .fullScreenWhenOpen) {
      player.didEnterFullScreenViaUserToggle = false
      let useLegacyFS = Preference.bool(for: .useLegacyFullScreen)
      log.debug{"[GeoTF:\(cxt.name)] Changing to \(useLegacyFS ? "legacy " : "")fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y"}
      if useLegacyFS {
        mode = .fullScreenNormal
      } else {
        cxt.needsNativeFullScreen = true
      }
    }

    // Set to default layout, but use existing aspect ratio & video size for now, because we don't have that info yet for the new video
    let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: mode, fillingInFrom: lastWindowedLayoutSpec)
    cxt.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)

    let outputGeoSet = buildGeoSetForNewWindow(cxt)
    return buildTransitionTasksToInitialLayout(cxt, outputGeoSet)
  }

  /// For the case of `PWinSessionState.creatingNew`.
  ///
  /// - Uses `musicModeGeoLastClosed` for `musicMode`
  /// - Uses `windowedModeGeoLastClosed` for `windowedMode` if not in windowed mode, but uses a minimized window if in windowed mode
  ///   (as the start of window open animation)
  private func buildGeoSetForNewWindow(_ cxt: GeometryTransform.Context) -> GeometrySet {
    // Should only be here if window is a new window or was previously closed. Copy layout from the last closed window
    let musicModeGeo = PlayerWindowController.musicModeGeoLastClosed.clone(video: cxt.outputVidGeo)

    let windowedModeGeo: PWinGeometry
    if cxt.outputLayout.isFullScreen || cxt.outputLayout.isMusicMode {
      windowedModeGeo = PlayerWindowController.windowedModeGeoLastClosed

    } else {
      /// Use `minVideoSize` at first when a new window is opened, so that when `GeometryTransform` is submitted shortly after,
      /// it expands and creates a nice zooming effect. But try to start with video's correct aspect, if available
      let viewportSize = CGSize.computeMinSize(withAspect: cxt.outputVidGeo.videoAspectCAR,
                                               minWidth: Constants.Window.minViewportSize.width,
                                               minHeight: Constants.Window.minViewportSize.height)
      let intendedWindowSize = NSSize(width: viewportSize.width + cxt.outputLayout.outsideLeadingBarWidth + cxt.outputLayout.outsideTrailingBarWidth,
                                      height: viewportSize.height + cxt.outputLayout.outsideTopBarHeight + cxt.outputLayout.outsideBottomBarHeight)
      let windowFrame = NSRect(origin: NSPoint.zero, size: intendedWindowSize)
      /// Change the window origin so that it opens where the mouse was when `openURLs` was called. This visually reinforces the user-initiated
      /// behavior and is less jarring than popping out of the periphery. It will move while zooming to its final location, which remains
      /// well-defined based on current user prefs and/or last closed window.
      let mouseLoc = PlayerCore.mouseLocationAtLastOpen ?? NSEvent.mouseLocation
      let mouseLocScreenID = NSScreen.getOwnerOrDefaultScreenID(forPoint: mouseLoc)
      let initialGeo = cxt.outputLayout.buildGeometry(windowFrame: windowFrame, screenID: mouseLocScreenID, video: cxt.outputVidGeo).refitted(using: .stayInside)
      let windowSize = initialGeo.windowFrame.size
      let windowOrigin = NSPoint(x: round(mouseLoc.x - (windowSize.width * 0.5)), y: round(mouseLoc.y - (windowSize.height * 0.5)))
      log.verbose{"[GeoTF:\(cxt.name)] Initial layout: starting with tiny window, videoAspect=\(cxt.outputVidGeo.videoAspectCAR), windowSize=\(windowSize)"}
      windowedModeGeo = initialGeo.clone(windowFrame: NSRect(origin: windowOrigin, size: windowSize)).refitted(using: .stayInside)
    }

    return GeometrySet(windowed: windowedModeGeo, musicMode: musicModeGeo, video: cxt.outputVidGeo)
  }

}
