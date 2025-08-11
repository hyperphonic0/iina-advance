//
//  GeometryTransform.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-08.
//

/// Contains a set of transform functions, along with any initial state, which forms a recipe for making changes to
/// a given window's geometry. Each instance must be executed via an `IINAAnimation.Pipeline` for any work to be done.
///
/// # Important Fields:
/// - `sessionStateTransform`: optional operator function (functor) for transforming `sessionState` and/or cancelling the transform.
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
///
/// See also: `VideoGeo_Sync.swift` for syncing `VideoGeometry` from mpv.
struct GeometryTransform {
  // Transforms (functors) for different types
  typealias PWinSessionStateTF = (PWinSessionState, ContextStage2) -> PWinSessionState?
  typealias VideoGeometryTF = (VideoGeometry, ContextStage2) -> VideoGeometry?
  typealias PWinGeometryTF = (GeometryTransform.ContextStage3) -> PWinGeometry?

  // MARK: - GeometryTransform Fields

  /// Descriptive name of the transform, and its `id` (string).
  let name: String
  /// The unique identifier of this `GeometryTransform`.
  let id: Int

  /// If `true`, then prior to executing `videoTransform`, call `GeometryTransform.Context.syncVideoParamsFromMpv` to update
  /// `ctx.inputGeoSet` with the latest video geometry from mpv (or abort if it returns `nil`).
  let syncVideoParams: Bool

  private let player: PlayerCore
  private var pwc: PlayerWindowController { player.windowController! }
  private var log: Logger.Subsystem { player.log }

  /// If `sessionStateTransform` is `nil` (omitted), treat as no-op and continue to `videoTransform`.
  /// If `sessionStateTransform` returns `nil`, transition should be aborted.
  private let sessionStateTransform: PWinSessionStateTF?
  private let videoTransform: VideoGeometryTF?
  private let windowedTransform: PWinGeometryTF?

  private let onSuccess: (() -> Void)?

  init(_ name: String,
       id pregeneratedID: Int? = nil,
       _ player: PlayerCore,
       syncVideoParams: Bool = true,
       sessionState: PWinSessionStateTF? = nil,
       video: VideoGeometryTF? = nil,
       windowed: PWinGeometryTF? = nil,
       onSuccess: (() -> Void)? = nil) {
    let pipeline = player.windowController.animationPipeline
    self.id = pregeneratedID ?? pipeline.gtfLock.withLock {
      pipeline.nextID_NoLock()
    }
    self.name = "\(name)-\(id)"
    self.player = player
    self.syncVideoParams = syncVideoParams
    self.sessionStateTransform = sessionState
    self.videoTransform = video
    self.windowedTransform = windowed
    self.onSuccess = onSuccess
  }

  /// Convenience method which enqueues this GeometryTransform for execution.
  func submit() {
    pwc.animationPipeline.submitGTF(self)
  }

  /// Aborts the transform (`animationPipeline` must always be notified for either success or failure).
  private func abort(_ reasonDebugMsg: String) {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    log.verbose{"[GTF:\(name)] Aborting GTF: \(reasonDebugMsg)"}
    pwc.animationPipeline.geoTransformDidFinish(self, success: false)
  }

  /// Do not call directly. Should only be called from an animation pipeline.
  /// Use `IINAAnimation.Pipeline.submit` to execute a `GeometryTransform`.
  func execute() {
    // MARK: - STAGE 1
    assert(DispatchQueue.isExecutingIn(.main))

    // Get a copy of geo inside animationPipeline to ensure serial access.
    // This is reused asynchronously down below, so some parts of it may fall out of date, but
    // shouldn't be the parts we need for now...
    let prevGeoSet = pwc.geo

    // Quick summary of how we will avoid race conditions with `pwc.sessionState` (tag: #SessionState-Race)
    // 1. All reads and writes of this variable occur on the main DQ.
    // 2. In `player.openPlayerWindow`, the use of `mpv.queue.sync` creates a sort of checkpoint betwween
    // the mpv & main queues, ensuring that the mpv queue is emptied (& thus discarding any enqueued GTFs) before
    // proceeding with an update of the variable.
    // 3. The logic in `IINAAnimation.Pipeline` ensures that each GTF starts after the last one has completed.
    // Thus, no GTFs overlap in their execution, even across the two queues.
    // 4. We set `pwc.sessionState = .noSession` when closing the player window. But we can check for this
    // before updating it at the end of the GTF, and pair with a check for `player.isStopping` in the mpv queue
    // to cover both cases.
    let prevSessionState = pwc.sessionState

    // MARK: - STAGE 2
    // -- mpv queue -------------------------------------------------------------------------
    // Need to be inside mpv queue to ensure serial access to `vid` & other mpv state
    player.mpv.queue.async { [self] in
      // Check for window close (tag: #SessionState-Race)
      guard !player.isStopping else { return abort("player stopping (status=\(player.state))") }
      guard let currentPlayback = player.info.currentPlayback else { return abort("currentPlayback is nil") }


      // File needs to be loaded before we can know its video geometry.
      // ...Unless we are restoring. But then we still want to wait until all windows are done loading, so we can open them all at once.
      // ...But streaming files can often fail to connect. So reopen those right away if restoring (we already have their saved geometry anyway).
      guard currentPlayback.state.isAtLeast(.loaded) || (prevSessionState.isRestoring && currentPlayback.isNetworkResource) else {
        return abort("playbackState=\(currentPlayback.state) restoring=\(prevSessionState.isRestoring.yn) network=\(currentPlayback.isNetworkResource.yn)")
      }

      // Get the freshest value of vid track from mpv
      let vidTrackID = Int(player.mpv.getInt(MPVOption.TrackSelection.vid))

      let ctxStage2 = ContextStage2(tf: self, currentPlayback: currentPlayback, vidTrackID: vidTrackID,
                                    currentMediaAudioStatus: player.info.currentMediaAudioStatus)

      let gtfSessionState: PWinSessionState
      /// 1: Apply `stateChange` if present
      if let sessionStateTransform {
        log.verbose{"[GTF:\(name)] Calling sessionStateTransform"}
        guard let updatedSessionState = sessionStateTransform(prevSessionState, ctxStage2) else {
          return abort("state change func returned nil from prevSessionState=\(prevSessionState)")
        }
        gtfSessionState = updatedSessionState
        log.verbose{"[GTF:\(name)] Result of sessionStateChange: \(prevSessionState) → \(gtfSessionState.description)"}
      } else {
        gtfSessionState = prevSessionState
        log.verbose{"[GTF:\(name)] No sessionStateChange provided; using prev value: \(gtfSessionState)"}
      }

      var outputVideoGeo = prevGeoSet.video

      /// 2a: Sync video params from mpv, if `syncVideoParamsFromMPV` is true.
      if syncVideoParams {
        log.verbose{"[GTF:\(name)] Calling syncVideoParamsFromMpv as configured"}
        guard let syncedVideoGeo = ctxStage2.syncVideoParamsFromMpv(startingWith: outputVideoGeo) else {
          return abort("syncVideoParamsFromMpv returned nil")
        }
        log.verbose{"[GTF:\(name)] Result of video sync: \(syncedVideoGeo)"}
        /// The result is the new `outputVideoGeo`
        outputVideoGeo = syncedVideoGeo
      }

      /// 2b: Apply `videoTransform` if present.
      /// This needs to be on the mpv queue, because some transforms make mpv calls.
      if let videoTransform {
        log.verbose{"[GTF:\(name)] Calling videoTF"}
        guard let transformedVidGeo = videoTransform(outputVideoGeo, ctxStage2) else {
          return abort("videoTF returned nil")
        }
        log.verbose{"[GTF:\(name)] Result of videoTF: \(transformedVidGeo)"}
        outputVideoGeo = transformedVidGeo
      } else {
        log.verbose{"[GTF:\(name)] No videoTF given, skipping. Will use: \(outputVideoGeo)"}
      }

      // MARK: - STAGE 3
      // -- main queue -------------------------------------------------------------------------
      pwc.animationPipeline.submitInstantTask { [self] in
        // Do not reference these variables until inside this animation task to ensure serial access
        let inputLayout = pwc.currentLayout

        // Update context's geo with current window frame
        let inputGeoSet = pwc.buildGeoSet(video: outputVideoGeo, activeMode: inputLayout.mode, baseGeoSet: prevGeoSet,
                                                 forceWinFrameUpdate: !gtfSessionState.isStartingSession)

        var ctxStage3 = GeometryTransform.ContextStage3(ctxStage2,
                                                        gtfSessionState: gtfSessionState,
                                                        inputGeoSet: inputGeoSet, outputVidGeo: outputVideoGeo,
                                                        inputLayout: inputLayout)

        doMainQueueWork(&ctxStage3)
      }
    }
  }

  private func doMainQueueWork(_ ctx: inout GeometryTransform.ContextStage3) {
    log.trace{"[GTF:\(name)] Starting main thread work"}

    /// 3. (Optional) Transition window to initial layout. Must exexcute before `buildApplyTransformTasks`.
    /// Will return` []` if not applicable.
    var immediateTasks: [IINAAnimation.Task]

    /// 4. Apply `windowedTransform` / `musicModeTransform`
    let transformTasks = ctx.buildApplyTransformTasks()

    if ctx.gtfSessionState.isStartingSession {
      let window = ctx.pwc.window!

      // Build tasks to transition the window to its "initial" layout.
      switch ctx.gtfSessionState {

      case .restoring(let priorState):
        /// Restoring from prior launch  (`PWinSessionState.restoring`)
        immediateTasks = ctx.pwc.buildTasksToRestoreLayout(priorState, &ctx)

      case .newReplacingExisting:
        /// Reusing existing window for new file (`PWinSessionState.newReplacingExisting`)
        log.verbose("[GTF:\(ctx.name)] Opening a new file in an already open window, mode=\(ctx.inputLayout.mode)")

        /// `windowFrame` may be slightly off; update it
        if ctx.inputLayout.mode == .windowedNormal {
          /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
          /// Side effect: future opened windows may use this size even if this window wasn't closed. Should be ok?
          PlayerWindowController.windowedModeGeoLastClosed = ctx.inputLayout.buildGeometry(windowFrame: window.frame,
                                                                                           screenID: ctx.pwc.bestScreen.screenID,
                                                                                           ctx.outputVidGeo)
        } else if ctx.inputLayout.mode == .musicMode {
          /// Set this so that `transformGeometry` will use the correct default window frame if it looks for it.
          PlayerWindowController.musicModeGeoLastClosed = ctx.inputGeoSet.musicMode.cloneMusicMode(windowFrame: window.frame,
                                                                                                   screenID: ctx.pwc.bestScreen.screenID,
                                                                                                   video: ctx.outputVidGeo)
        }
        // No initial layout tasks needed. Fall through to add post-layout task
        immediateTasks = []

      case .creatingNew:
        /// Opening window for new file (`PWinSessionState.creatingNew`)
        log.verbose{"[GTF:\(ctx.name)] Window is opening: building initial layout tasks"}

        immediateTasks = ctx.pwc.buildTasksForNewWindow(&ctx)

      default:
        Logger.fatal("Invalid PWinSessionState for initial layout: \(ctx.gtfSessionState)")
      }

      // Post-layout task: do other needed config
      let ctxSnapshot = ctx
      immediateTasks.append(.instantTask{
        ctxSnapshot.pwc.doPostInitialLayoutTask(ctxSnapshot, windowIsMinimized: window.isMiniaturized)
      })

      let isRestoringMinimizedWindow = ctx.gtfSessionState.isRestoring && UIState.shared.windowsMinimized.contains(pwc.window!.savedStateName)
      if isRestoringMinimizedWindow {
        // Minimized: can't rely on showWindow() being called, but window changes won't be seen anyway. Just run end task now.
        log.verbose{"[GTF:\(name)] Restoring minimized window: will run tasks immediately instead of enqueueing"}
        immediateTasks += transformTasks
      } else {
        /// These tasks should not execute until *after* `super.showWindow` is called.
        log.verbose{"[GTF:\(name)] Adding pending tasks: count=\(transformTasks.count) timeTotal=\(transformTasks.reduce(0) { $0 + $1.duration })"}
        pwc.pendingVideoGeoUpdateTasks = transformTasks
      }

    } else {
      immediateTasks = transformTasks

      /// 5. Need to switch to music mode? Append to above tasks
      if case .existingSession_startingNewPlayback = ctx.gtfSessionState, Preference.bool(for: .autoSwitchToMusicMode) {
        let layout = ctx.outputLayout
        if player.overrideAutoMusicMode {
          log.verbose{"[GTF:\(name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y"}
        } else if ctx.currentMediaAudioStatus.isAudio && !layout.isMusicMode && !layout.isFullScreen {
          log.debug{"[GTF:\(name)] Opened media is audio: auto-switching to music mode"}
          let geo = pwc.buildGeoSet(video: ctx.outputVidGeo, activeMode: layout.mode)
          let enterMusicModeTransitionTasks = pwc.buildTasksToEnterMusicMode(automatically: true, from: layout, geo)
          immediateTasks += enterMusicModeTransitionTasks
        } else if ctx.currentMediaAudioStatus == .notAudio && layout.isMusicMode {
          log.debug{"[GTF:\(name)] Opened media is not audio: auto-switching to normal window"}
          let geo = pwc.buildGeoSet(video: ctx.outputVidGeo, activeMode: layout.mode)
          let enterMusicModeTransitionTasks = pwc.buildTasksToExitMusicMode(automatically: true, from: layout, geo)
          immediateTasks += enterMusicModeTransitionTasks
        }
      }
    }

    log.verbose{"[GTF:\(name)] Submitting immediate tasks: count=\(immediateTasks.count) timeTotal=\(immediateTasks.reduce(0) { $0 + $1.duration })"}
    pwc.animationPipeline.submit(immediateTasks)
  }


  // MARK: - Context

  /// Builds on the state in the `GeometryTransform` object and adds the variables retrieved in Stage 2 (mpv queue).
  /// Used as input for `PWinSessionStateTF` & `VideoGeometryTF` functions.
  struct ContextStage2 {
    /// The transform spec. Immutable.
    let tf: GeometryTransform

    // - Variables retrieved from mpv

    let currentPlayback: Playback
    let vidTrackID: Int
    let currentMediaAudioStatus: PlaybackInfo.MediaAudioStatus

    // - Other derived properties

    var name: String { tf.name }
    var player: PlayerCore { tf.player }
    var pwc: PlayerWindowController { player.windowController! }
    var log: Logger.Subsystem { player.log }
  }

  /// Builds on the `ContextStage2` state, adding the results from the `PWinSessionState` & `VideoGeometry` transforms,
  /// & additional state retrieved / computed in the final main queue stage.
  /// Used as input for `PWinGeometry` transforms, as well as a useful container to pass around internal methods.
  struct ContextStage3 {
    let ctxStage2: ContextStage2

    // The transform spec (immutable)
    var tf: GeometryTransform { ctxStage2.tf }

    var currentPlayback: Playback {
      ctxStage2.currentPlayback
    }
    var vidTrackID: Int {
      ctxStage2.vidTrackID
    }
    var currentMediaAudioStatus: PlaybackInfo.MediaAudioStatus {
      ctxStage2.currentMediaAudioStatus
    }

    /// The `PWinSessionState` at the start of the transform. In some cases this has been updated from
    /// `PlayerWindowController`'s `sessionState` to a value which is applicable only during the execution of the GTF.
    /// Do not query `PlayerWindowController.sessionState` during the transform. Use this instead.
    let gtfSessionState: PWinSessionState

    /// Contains most up-to-date version of the geometries (as well as possibly unapplied changes), which transforms should build
    /// on top of. (The `PlayerWindowController`'s `geo` field should not be referenced in any transform functions).
    var inputGeoSet: GeometrySet

    /// Gets the `VideoGeometry` from `inputGeoSet`.
    var inputVidGeo: VideoGeometry { inputGeoSet.video }
    /// The transformed `VideoGeometry`.
    let outputVidGeo: VideoGeometry

    let inputLayout: LayoutState

    /// Defaults to `inputLayout`, but can be overwritten by `buildWindowInitialLayoutTasks`.
    /// Do not reference until after that is called.
    var outputLayout: LayoutState

    fileprivate var needsNativeFullScreen = false

    // - Other derived properties

    var name: String { tf.name }
    var player: PlayerCore { tf.player }
    var pwc: PlayerWindowController { player.windowController! }
    var log: Logger.Subsystem { player.log }

    init(_ ctxStage2: ContextStage2, gtfSessionState: PWinSessionState,
         inputGeoSet: GeometrySet, outputVidGeo: VideoGeometry,
         inputLayout: LayoutState) {
      self.ctxStage2 = ctxStage2
      self.gtfSessionState = gtfSessionState
      self.inputGeoSet = inputGeoSet
      self.outputVidGeo = outputVidGeo
      self.inputLayout = inputLayout
      self.outputLayout = inputLayout  // until updated
    }

    /// Default album art: to avoid race conditions, use the context's state instead of player.info
    /// If `showDefaultArt == nil`, don't change existing visibility.
    fileprivate var shouldChangeDefaultArt: Bool? {
      // Don't show art if currently loading
      if currentPlayback.state.isAtLeast(.loaded) {
        // Show art if no video track is selected (i.e., vid=0)
        return vidTrackID == 0
      }
      return nil
    }

    /// Only `transformGeometry` should call this.
    fileprivate func buildApplyTransformTasks() -> [IINAAnimation.Task] {
      log.verbose{"[GTF:\(name)] Building transform tasks, mode=\(outputLayout.mode), vidTrackID=\(vidTrackID)"}

      // There's no good animation for rotation (yet), so just do as little animation as possible in this case
      var duration: CGFloat = Constants.AnimationDuration.videoReconfig
      var timing = CAMediaTimingFunctionName.easeInEaseOut
      var tasks: [IINAAnimation.Task]

      switch outputLayout.mode {

      case .windowedNormal:
        let resizedGeo: PWinGeometry?

        if let windowedTransform = tf.windowedTransform {
          resizedGeo = windowedTransform(self)
        } else {
          switch gtfSessionState {
          case .restoring(_):
            log.verbose{"[GTF:\(name)] Restore is in progress: no transform needed"}
            // still need post-transition task
            return [.instantTask(doPostTransformWork)]

          case .creatingNew:
            // Just opened new window. Use a longer duration for this one, because the window starts small and will zoom into place.
            duration = Constants.AnimationDuration.initialVideoReconfig
            timing = .linear
            resizedGeo = applyResizePrefsForNewPlaybackInWindowedMode()

          case .newReplacingExisting, .existingSession_startingNewPlayback:
            resizedGeo = applyResizePrefsForNewPlaybackInWindowedMode()
            if let resizedGeo, resizedGeo.windowFrame != inputGeoSet.windowed.windowFrame {
            } else {
              // No need for animation if window's frame didn't change. Video param transitions are not animated by mpv
              duration = 0.0
            }

          case .existingSession_videoTrackChangedForSamePlayback, .existingSession_continuing:
            // Not a new file. Some other change to a video geo property. Fall through and resize minimally
            resizedGeo = nil

          case .noSession:
            Logger.fatal("[GTF:\(name)] Invalid gtfSessionState: \(gtfSessionState)")
          }
        }

        let intendedViewportSize: CGSize? = gtfSessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let outputGeo = resizedGeo ?? inputGeoSet.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                                   intendedViewportSize: intendedViewportSize)
        let showDefaultArt: Bool? = shouldChangeDefaultArt

        log.verbose{"[GTF:\(name)] Building windowed tasks: sess=\(gtfSessionState) defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(outputGeo)"}
        tasks = pwc.buildApplyWindowGeoTasks(from: inputGeoSet.windowed, to: outputGeo, duration: duration, timing: timing, showDefaultArt: showDefaultArt)

      case .fullScreenNormal:
        let intendedViewportSize: CGSize? = gtfSessionState.canUseIntendedViewportSize ? player.info.intendedViewportSize : nil
        let newWinGeo = inputGeoSet.windowed.resizeMinimally(forNewVideoGeo: outputVidGeo,
                                                        intendedViewportSize: intendedViewportSize)
        let fsGeo = outputLayout.buildFullScreenGeometry(inScreenID: newWinGeo.screenID, outputVidGeo)
        let showDefaultArt: Bool? = shouldChangeDefaultArt

        log.verbose{"[GTF:\(name)] Building FS tasks: defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(fsGeo)"}
        tasks = pwc.buildApplyFullScreenGeoTasks(fsGeo: fsGeo, newWindowedGeo: newWinGeo, duration: duration, showDefaultArt: showDefaultArt)

      case .musicMode:
        if case .creatingNew = gtfSessionState {
          log.verbose{"[GTF:\(name)] Music mode already handled for opened window: \(inputGeoSet.musicMode)"}
          tasks = []
          break
        }
        let oldMusicModeGeo = inputGeoSet.musicMode  // has updated windowFrame
        let newMusicModeGeo: PWinGeometry
        /// Use transformed music mode geo if provided. Otherwise update minimally for new `VideoGeometry`:
        if let windowedTransform = tf.windowedTransform, let transformedGeo = windowedTransform(self) {
          assert(transformedGeo.mode == .musicMode, "[GTF:\(name)] Tranform expected to return geometry with mode=.musicMode, but got: \(transformedGeo) ")
          newMusicModeGeo = transformedGeo
        } else {
          /// Keep prev `windowFrame`. Just adjust height to fit new video aspect ratio
          /// (unless it doesn't fit in screen; see `applyMusicModeGeo`)
          newMusicModeGeo = oldMusicModeGeo.clone(video: outputVidGeo)
        }

        if oldMusicModeGeo.videoShown != newMusicModeGeo.videoShown {
          // Toggling videoView visiblity: use longer duration for nicety
          duration = Constants.AnimationDuration.standard
        }

        let showDefaultArt: Bool? = shouldChangeDefaultArt

        log.verbose{"[GTF:\(name)] Building musicMode tasks: sess=\(gtfSessionState) defaultArt=\(showDefaultArt?.yn ?? "nil") dur=\(duration) \(newMusicModeGeo)"}
        tasks = pwc.buildApplyWindowGeoTasks(from: oldMusicModeGeo, to: newMusicModeGeo, duration: duration, showDefaultArt: showDefaultArt)
      default:
        // Interactive mode. Should be handled by its special code. Don't step on it.
        log.debug{"[GTF:\(name)] Invalid mode for TF: \(outputLayout.mode)"}
        tasks = []
        // Fall through and add post-work task
      }

      // Task: post-transform work
      tasks.append(.instantTask(doPostTransformWork))

      return tasks
    }

    /// Conforms to `IINAnimation.TaskFunc`. Does cleanup, updates state vars & UI.
    fileprivate func doPostTransformWork() {
      log.verbose{"[GTF:\(name)] Running post-TF task, sess=\(gtfSessionState) vid=\(vidTrackID)"}
      let pwc = player.windowController!

      // (tag: #SessionState-Race)
      if player.isStopping {
        log.debug{"[GTF:\(name)] In post-TF task: player is stopping. Aborting remaining updates"}
        return
      } else if case .noSession = pwc.sessionState {
        log.debug{"[GTF:\(name)] In post-TF task: found 'noSession' for sessionState. Possibly the player is stopping. Aborting remaining updates."}
        return
      }
      // Apply new session state (need to do this in .main). This will always be `.continuing`.
      pwc.sessionState = .existingSession_continuing

      // Must only modify currentPlayback state inside mpv queue
      player.mpv.queue.async {
        guard !player.isStopping else {
          return
        }

        if gtfSessionState.isChangingVideoTrack {
          // Update `currentPlayback`'s state. If, by chance, playback has changed since the start of this GTF's
          // execution, then `player.info.currentPlayback` will have been set to a new object, and thus the
          // following updates will be made to a disused object and will not cause trouble.
          // (Posting the notifications below is similarly harmless - at leas for now. Unclear if/how they may
          // be used by plugins).

          // Set to prevent future duplicate calls from continuing
          currentPlayback.vidTrackLastSized = vidTrackID
          
          // Wait until window is completely opened before setting this, so that OSD will not be displayed until then.
          // The OSD can have weird stretching glitches if displayed while zooming open...
          if currentPlayback.state == .loaded {
            log.debug{"[GTF:\(name)] Updating playback.state = .loadedAndSized; will emit fileLoaded"}
            currentPlayback.state = .loadedAndSized
            DispatchQueue.main.async {
              // Should refresh EDR each time switching files
              pwc.videoView.refreshAllVideoDisplayState()
              // If is network resource, may not be loaded yet. If file, it will be.
              player.postNotification(.iinaFileLoaded)
              player.events.emit(.fileLoaded, data: currentPlayback.url.absoluteString)
            }
          }
        }
      }
      
      // If minimized, the call to DispatchQueue.main.async below doesn't seem to execute. Just do the below for all cases now.
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

      pwc.animationPipeline.geoTransformDidFinish(tf, success: true)
    }

    /// Applies the prefs `.resizeWindowTiming` & `resizeWindowScheme`, if applicable.
    /// Returns `nil` if no applicable settings were found/applied, and should fall back to minimal resize.
    private func applyResizePrefsForNewPlaybackInWindowedMode() -> PWinGeometry? {
      // resize option applies
      let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      switch resizeTiming {
      case .always:
        log.verbose{"[GTF:\(name)] FileOpened & resizeTiming='Always' → will resize window"}
      case .onlyWhenOpen:
        if !gtfSessionState.isStartingNewPlaybackManually {
          log.verbose{"[GTF:\(name)] FileOpened & resizeTiming='OnlyWhenOpen', but isStartingNewPlaybackManually=N → will resize minimally"}
          return nil
        }
      case .never:
        if !gtfSessionState.isStartingNewPlaybackManually {
          log.verbose{"[GTF:\(name)] FileOpened (not manually) & resizeTiming='Never' → will resize minimally"}
          return nil
        }
        log.verbose{"[GTF:\(name)] FileOpenedManually & resizeTiming='Never' → using windowedModeGeoLastClosed: \(PlayerWindowController.windowedModeGeoLastClosed)"}
        return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                        video: outputVidGeo,
                                                        pinWidthOrHeightIfAtMax: true,
                                                        applyOffsetIndex: player.openedWindowsSetIndex, log)
      }

      let windowGeo = inputGeoSet.windowed.clone(video: outputVidGeo)
      let screenVisibleFrame = NSScreen.getScreenOrDefault(screenID: windowGeo.screenID).visibleFrame

      let resizeScheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)
      switch resizeScheme {
      case .mpvGeometry:
        // check if have mpv geometry set (initial window position/size)
        guard let mpvGeometry = player.getMPVGeometry() else {
          if gtfSessionState.isStartingNewPlaybackManually {
            log.debug{"[GTF:\(name)] No mpv geometry found, starting new playback: will fall back to windowedModeGeoLastClosed"}
            return outputLayout.convertWindowedModeGeometry(from: PlayerWindowController.windowedModeGeoLastClosed,
                                                            video: outputVidGeo,
                                                            pinWidthOrHeightIfAtMax: true,
                                                            applyOffsetIndex: player.openedWindowsSetIndex, log)
          } else {
            log.debug{"[GTF:\(name)] No mpv geometry found. Will fall back to minimal resize"}
            return nil
          }
        }

        var preferredGeo = windowGeo
        if Preference.bool(for: .lockViewportToVideoSize), gtfSessionState.canUseIntendedViewportSize,
           let intendedViewportSize = player.info.intendedViewportSize {
          log.verbose{"[GTF:\(name)] Using intendedViewportSize \(intendedViewportSize)"}
          preferredGeo = windowGeo.scalingViewport(to: intendedViewportSize)
        }
        log.verbose{"[GTF:\(name)] Applying mpv \(mpvGeometry) within screen \(screenVisibleFrame)"}
        return windowGeo.apply(mpvGeometry: mpvGeometry, desiredWindowSize: preferredGeo.windowFrame.size)

      case .simpleVideoSizeMultiple:
        let resizeWindowStrategy: Preference.ResizeWindowOption = Preference.enum(for: .resizeWindowOption)
        if resizeWindowStrategy == .fitScreen {
          log.verbose{"[GTF:\(name)] ResizeWindowOption=FitToScreen. Using screenFrame \(screenVisibleFrame)"}
          return windowGeo.scalingViewport(to: screenVisibleFrame.size, screenFit: .centerInside)
        } else {
          let resizeRatio = resizeWindowStrategy.ratio
          let scaledVideoWidth = (outputVidGeo.videoSizeCAR.width * resizeRatio).rounded()
          log.verbose{"[GTF:\(name)] Applied resizeRatio (\(resizeRatio)) to newVideoWidth → \(scaledVideoWidth)"}
          let centeredScaledGeo = windowGeo.scalingVideo(toWidth: scaledVideoWidth, screenFit: .centerInside, mode: outputLayout.mode)
          // User has actively resized the video. Assume this is the new preferred resolution
          player.info.intendedViewportSize = centeredScaledGeo.viewportSize
          log.verbose{"[GTF:\(name)] After scaleVideo: \(centeredScaledGeo)"}
          return centeredScaledGeo
        }
      }
    }

  }  // end struct GeometryTransform.Context
}

// MARK: - Window Initial Layout

extension PlayerWindowController {

  fileprivate func doPostInitialLayoutTask(_ ctx: GeometryTransform.ContextStage3, windowIsMinimized: Bool) {
    defer {
      if ctx.gtfSessionState.isRestoring, windowIsMinimized {
        log.verbose("Restoring minimized window; skipping windowIsReadyToShow")
      } else if ctx.gtfSessionState.isRestoring, isWindowHidden {
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

    let shouldDecideDefaultArtStatus = !ctx.outputLayout.isMusicMode || musicModeGeo.videoShown
    let showDefaultArt: Bool? = shouldDecideDefaultArtStatus ? ctx.shouldChangeDefaultArt : nil
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
    updateTitle()
    playlistView.needsScrollToCurrentItem = true  // reset flag for when it does open

    // FIXME: here be race conditions
    if case .newReplacingExisting = sessionState {
      // Need to switch to music mode?
      if Preference.bool(for: .autoSwitchToMusicMode) {
        if player.overrideAutoMusicMode {
          log.verbose("[GTF:\(ctx.name)] Skipping music mode auto-switch ∴ overrideAutoMusicMode=Y")
        } else if ctx.currentMediaAudioStatus.isAudio && !ctx.outputLayout.isMusicMode && !ctx.outputLayout.isFullScreen {
          log.debug("[GTF:\(ctx.name)] Opened media is audio: auto-switching to music mode")
          player.enterMusicMode(automatically: true, withNewVidGeo: ctx.outputVidGeo)
          return  // do not even try to go to full screen if already going to music mode
        } else if ctx.currentMediaAudioStatus == .notAudio && ctx.outputLayout.isMusicMode {
          log.debug("[GTF:\(ctx.name)] Opened media is not audio: auto-switching to normal window")
          player.exitMusicMode(automatically: true, withNewVidGeo: ctx.outputVidGeo)
          return  // do not even try to go to full screen if already going to windowed mode
        }
      }

      // Need to switch to full screen?
      if Preference.bool(for: .fullScreenWhenOpen) && !isFullScreen && !isInMiniPlayer {
        log.debug("[GTF:\(ctx.name)] Changing to full screen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y")
        enterFullScreen()
      }
    }
  }

  /// Generates animation tasks to adjust the window layout appropriately for a newly opened file.
  private func buildTransitionTasksToInitialLayout(_ ctx: GeometryTransform.ContextStage3,
                                                   _ outputGeoSet: GeometrySet) -> [IINAAnimation.Task] {

    // Set this now, instead of waiting for it to be set by `initialTransition`.
    // Don't want window resize/move listeners doing something untoward.
    isAnimatingLayoutTransition = true

    // Send GeometrySet object to builder so that it doesn't default to current window frame
    log.verbose{"[GTF:\(ctx.name)] Setting initial \(ctx.outputLayout.spec), windowedModeGeo=\(outputGeoSet.windowed), musicModeGeo=\(outputGeoSet.musicMode)"}

    let isRestoring = ctx.gtfSessionState.isRestoring
    let transitionName = "\(isRestoring ? "Restore" : "Set")InitialLayout"
    let initialTransition = buildLayoutTransition(named: transitionName,
                                                  from: ctx.inputLayout, to: ctx.outputLayout.spec,
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
        log.error{"[GTF:\(ctx.name)] Failed to run initial layout tasks: \(error)"}
      }

      if !isRestoring {
        if ctx.outputLayout.mode == .windowedNormal {
          player.info.intendedViewportSize = initialTransition.outputGeometry.viewportSize

          // Set window opacity to 0 initially to start fade-in effect
          updateWindowBorderAndOpacity(using: ctx.outputLayout, windowOpacity: 0.0)
        }

        if !ctx.outputLayout.isFullScreen, Preference.bool(for: .alwaysFloatOnTop) && !player.info.isPaused {
          log.verbose("[GTF:\(ctx.name)] Setting window OnTop=Y per app pref")
          setWindowFloatingOnTop(true, from: ctx.outputLayout)
        }
      }

      /// Note: `isAnimatingLayoutTransition` should be `false` now
      log.verbose("[GTF:\(ctx.name)] Done with transition to initial layout")
    })

    if ctx.needsNativeFullScreen {
      tasks.append(.instantTask { [self] in
        enterFullScreen()
      })
      return tasks
    }

    if isRestoring {
      /// Stored window state may not be consistent with global IINA prefs.
      /// To check this, build another `LayoutSpec` from the global prefs, then compare it to the player's.
      let prefsSpec = LayoutSpec.fromPreferences(fillingInFrom: ctx.outputLayout.spec)
      if ctx.outputLayout.spec.hasSamePrefsValues(as: prefsSpec) {
        log.verbose{"[GTF:\(ctx.name)] Saved layout is consistent with IINA global prefs"}
      } else {
        // Not consistent. But we already have the correct spec, so just build a layout from it and transition to correct layout
#if DEBUG
        log.errorDebugAlert{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#else
        log.warn{"Player's saved layout does not match IINA app prefs. Will fix & apply corrected layout"}
#endif
        log.debug{"[GTF:\(ctx.name)] SavedSpec: \(currentLayout.spec). PrefsSpec: \(prefsSpec)"}
        let transition = buildLayoutTransition(named: "FixInvalidInitialLayout",
                                               from: initialTransition.outputLayout, to: prefsSpec)

        tasks.append(contentsOf: transition.tasks)
      }
    }

    return tasks
  }

  fileprivate func buildTasksToRestoreLayout(_ priorState: PlayerSaveState,
                                             _ ctx: inout GeometryTransform.ContextStage3) -> [IINAAnimation.Task] {
    if let priorLayoutSpec = priorState.layoutSpec {
      log.verbose("[GTF:\(ctx.name)] Transitioning to initial layout from prior window state")

      let initialLayoutSpec: LayoutSpec
      if priorLayoutSpec.isNativeFullScreen {
        // Special handling for native fullscreen. Rely on mpv to put us in FS when it is ready
        initialLayoutSpec = priorLayoutSpec.clone(mode: .windowedNormal)
        ctx.needsNativeFullScreen = true
      } else {
        initialLayoutSpec = priorLayoutSpec
      }
      ctx.outputLayout = LayoutState.buildFrom(initialLayoutSpec)
    } else {
      log.error("[GTF:\(ctx.name)] Failed to read LayoutSpec object for restore! Will try to assemble window from prefs instead")
      let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: .windowedNormal, fillingInFrom: lastWindowedLayoutSpec)
      ctx.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)
    }

    if ctx.outputLayout.mode == .musicMode {
      player.overrideAutoMusicMode = true
    }

    // Clean up windowedModeGeo if serious errors found with it
    var geoSet = priorState.geoSet

    if !geoSet.windowed.mode.isWindowed || geoSet.windowed.screenFit.isFullScreen {
      log.error{"[GTF:\(ctx.name)] Initial layout: windowedModeGeo from prior state has invalid mode (\(geoSet.windowed.mode)) or screenFit (\(geoSet.windowed.screenFit)). Will generate a fresh windowedModeGeo from saved layoutSpec and last closed window instead"}

      let lastClosedGeo = PlayerWindowController.windowedModeGeoLastClosed
      let windowed: PWinGeometry
      if lastClosedGeo.mode.isWindowed && !lastClosedGeo.screenFit.isFullScreen {
        windowed = ctx.outputLayout.convertWindowedModeGeometry(from: lastClosedGeo, video: priorState.geoSet.video,
                                                                pinWidthOrHeightIfAtMax: false, log)
      } else {
        windowed = ctx.outputLayout.buildDefaultInitialGeometry(screen: bestScreen, video: priorState.geoSet.video)
      }
      geoSet = geoSet.clone(windowed: windowed)

    } else if geoSet.windowed.outsideBars.totalWidth + geoSet.windowed.insideBars.totalWidth > geoSet.windowed.windowFrame.width {
      log.error{"[GTF:\(ctx.name)] Initial layout: windowedModeGeo from prior state has window size (\(geoSet.windowed.windowFrame.size)) which is too small to accomodate bars (outside=\(geoSet.windowed.outsideBars), inside=\(geoSet.windowed.insideBars)). Will close sidebars."}

      ctx.outputLayout = LayoutState.buildFrom(ctx.outputLayout.spec.withSidebarsHidden())
      let outsideNew = geoSet.windowed.outsideBars.clone(trailing: 0, leading: 0)
      let insideNew = geoSet.windowed.insideBars.clone(trailing: 0, leading: 0)
      let windowed = geoSet.windowed.clone(outsideBars: outsideNew, insideBars: insideNew)

      geoSet = priorState.geoSet.clone(windowed: windowed)
    }

    return buildTransitionTasksToInitialLayout(ctx, geoSet)
  }

  /// Creates IINAAnimation tasks for the case of `PWinSessionState.creatingNew`.
  /// Also sets `ctx.needsNativeFullScreen` & `ctx.outputLayout`.
  fileprivate func buildTasksForNewWindow(_ ctx: inout GeometryTransform.ContextStage3) -> [IINAAnimation.Task] {
    var mode: PlayerWindowMode = .windowedNormal

    if player.startInMusicModeRequested {
      log.debug{"[GTF:\(ctx.name)] Will open window in music mode as requested via CLI"}
      player.startInMusicModeRequested = false  // reset for reuse
      mode = .musicMode
    } else if Preference.bool(for: .autoSwitchToMusicMode) && ctx.currentMediaAudioStatus.isAudio {
      log.debug{"[GTF:\(ctx.name)] Opened media is audio: will open window in music mode"}
      mode = .musicMode
    } else if Preference.bool(for: .fullScreenWhenOpen) {
      player.didEnterFullScreenViaUserToggle = false
      let useLegacyFS = Preference.bool(for: .useLegacyFullScreen)
      log.debug{"[GTF:\(ctx.name)] Changing to \(useLegacyFS ? "legacy " : "")fullscreen because \(Preference.Key.fullScreenWhenOpen.rawValue)==Y"}
      if useLegacyFS {
        mode = .fullScreenNormal
      } else {
        ctx.needsNativeFullScreen = true
      }
    }

    // Set to default layout, but use existing aspect ratio & video size for now, because we don't have that info yet for the new video
    let layoutSpecFromPrefs = LayoutSpec.fromPreferences(andMode: mode, fillingInFrom: lastWindowedLayoutSpec)
    ctx.outputLayout = LayoutState.buildFrom(layoutSpecFromPrefs)

    let outputGeoSet = buildGeoSetForNewWindow(ctx)
    return buildTransitionTasksToInitialLayout(ctx, outputGeoSet)
  }

  /// For the case of `PWinSessionState.creatingNew`.
  ///
  /// - Uses `musicModeGeoLastClosed` for `musicMode`
  /// - Uses `windowedModeGeoLastClosed` for `windowedMode` if not in windowed mode, but uses a minimized window if in windowed mode
  ///   (as the start of window open animation)
  private func buildGeoSetForNewWindow(_ ctx: GeometryTransform.ContextStage3) -> GeometrySet {
    // Should only be here if window is a new window or was previously closed. Copy layout from the last closed window
    let musicModeGeo = PlayerWindowController.musicModeGeoLastClosed.clone(video: ctx.outputVidGeo)

    let windowedModeGeo: PWinGeometry
    if ctx.outputLayout.isFullScreen || ctx.outputLayout.isMusicMode {
      windowedModeGeo = PlayerWindowController.windowedModeGeoLastClosed

    } else {
      /// Use `minVideoSize` at first when a new window is opened, so that when `GeometryTransform` is submitted shortly after,
      /// it expands and creates a nice zooming effect. But try to start with video's correct aspect, if available
      let viewportSize = CGSize.computeMinSize(withAspect: ctx.outputVidGeo.videoAspectCAR,
                                               minWidth: Constants.Window.minViewportSize.width,
                                               minHeight: Constants.Window.minViewportSize.height)
      let intendedWindowSize = NSSize(width: viewportSize.width + ctx.outputLayout.outsideLeadingBarWidth + ctx.outputLayout.outsideTrailingBarWidth,
                                      height: viewportSize.height + ctx.outputLayout.outsideTopBarHeight + ctx.outputLayout.outsideBottomBarHeight)
      let windowFrame = NSRect(origin: NSPoint.zero, size: intendedWindowSize)
      /// Change the window origin so that it opens where the mouse was when `openURLs` was called. This visually reinforces the user-initiated
      /// behavior and is less jarring than popping out of the periphery. It will move while zooming to its final location, which remains
      /// well-defined based on current user prefs and/or last closed window.
      let mouseLoc = PlayerCore.mouseLocationAtLastOpen ?? NSEvent.mouseLocation
      let mouseLocScreenID = NSScreen.getOwnerOrDefaultScreenID(forPoint: mouseLoc, fallbackScreenID: ctx.inputGeoSet.windowed.screenID)
      let initialGeo = ctx.outputLayout.buildGeometry(windowFrame: windowFrame, screenID: mouseLocScreenID, ctx.outputVidGeo)
        .refitted(using: .stayInside)
      let windowSize = initialGeo.windowFrame.size
      let windowOrigin = NSPoint(x: round(mouseLoc.x - (windowSize.width * 0.5)), y: round(mouseLoc.y - (windowSize.height * 0.5)))
      log.verbose{"[GTF:\(ctx.name)] Initial layout: starting with tiny window, videoAspect=\(ctx.outputVidGeo.videoAspectCAR), windowSize=\(windowSize)"}
      windowedModeGeo = initialGeo.clone(windowFrame: NSRect(origin: windowOrigin, size: windowSize)).refitted(using: .stayInside)
    }

    return GeometrySet(windowed: windowedModeGeo, musicMode: musicModeGeo, video: ctx.outputVidGeo)
  }

}
