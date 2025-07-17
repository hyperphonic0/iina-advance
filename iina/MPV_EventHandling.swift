//
//  MPV_EventHandling.swift
//  iina
//
//  Created by Matt Svoboda on 2025-03-27.
//  Copyright © 2025 lhc. All rights reserved.

fileprivate let logEvents = false

extension MPVController {
  static let observeProperties: [String: mpv_format] = [
    MPVProperty.trackList: MPV_FORMAT_NONE,
    MPVProperty.vf: MPV_FORMAT_NONE,
    MPVProperty.af: MPV_FORMAT_NONE,
    MPVOption.Video.videoAspectOverride: MPV_FORMAT_NONE,
    MPVOption.TrackSelection.vid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.aid: MPV_FORMAT_INT64,
    MPVOption.TrackSelection.sid: MPV_FORMAT_INT64,
    MPVOption.Subtitles.secondarySid: MPV_FORMAT_INT64,
    MPVOption.PlaybackControl.pause: MPV_FORMAT_FLAG,
    MPVOption.PlaybackControl.loopPlaylist: MPV_FORMAT_STRING,
    MPVOption.PlaybackControl.loopFile: MPV_FORMAT_STRING,
    MPVOption.OSD.osdLevel: MPV_FORMAT_INT64,
    MPVProperty.chapter: MPV_FORMAT_INT64,
    MPVOption.Video.deinterlace: MPV_FORMAT_FLAG,
    MPVOption.Video.hwdec: MPV_FORMAT_STRING,
    MPVOption.Video.videoRotate: MPV_FORMAT_INT64,
    MPVProperty.dwidth: MPV_FORMAT_INT64,
    MPVProperty.dheight: MPV_FORMAT_INT64,
    MPVOption.Audio.mute: MPV_FORMAT_FLAG,
    MPVOption.Audio.volume: MPV_FORMAT_DOUBLE,
    MPVOption.Audio.audioDelay: MPV_FORMAT_DOUBLE,
    MPVOption.PlaybackControl.speed: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubVisibility: MPV_FORMAT_FLAG,
    MPVOption.Subtitles.secondarySubDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.secondarySubPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subDelay: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subPos: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subFont: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subFontSize: MPV_FORMAT_INT64,
    MPVOption.Subtitles.subBold: MPV_FORMAT_FLAG,
    MPVOption.Subtitles.subBorderColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subBorderSize: MPV_FORMAT_INT64,
    MPVOption.Subtitles.subBackColor: MPV_FORMAT_STRING,
    MPVOption.Subtitles.subScale: MPV_FORMAT_DOUBLE,
    MPVOption.Subtitles.subVisibility: MPV_FORMAT_FLAG,
    MPVOption.Equalizer.contrast: MPV_FORMAT_INT64,
    MPVOption.Equalizer.brightness: MPV_FORMAT_INT64,
    MPVOption.Equalizer.gamma: MPV_FORMAT_INT64,
    MPVOption.Equalizer.hue: MPV_FORMAT_INT64,
    MPVOption.Equalizer.saturation: MPV_FORMAT_INT64,
    MPVOption.Window.fullscreen: MPV_FORMAT_FLAG,
    MPVOption.Window.ontop: MPV_FORMAT_FLAG,
    MPVOption.Window.cursorAutohide: MPV_FORMAT_STRING,
    MPVOption.Window.cursorAutohideFsOnly: MPV_FORMAT_FLAG,
    /// As of mpv 0.38, cannot listen for `MPVProperty.currentWindowScale`
    MPVProperty.windowScale: MPV_FORMAT_DOUBLE,
    MPVProperty.mediaTitle: MPV_FORMAT_STRING,
    MPVProperty.videoParamsRotate: MPV_FORMAT_INT64,
    MPVProperty.videoParamsPrimaries: MPV_FORMAT_STRING,
    MPVProperty.videoParamsGamma: MPV_FORMAT_STRING,
    MPVProperty.idleActive: MPV_FORMAT_FLAG
  ]

  func addEventCallbacks() {
    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: MPVController.self)
      mpvController.readEvents()
    }, mutableRawPointerOf(obj: self))
    
    // Observe properties.

    for (k, v) in MPVController.observeProperties {
      mpv_observe_property(mpv, 0, k, v)
    }
  }

  /// Start listening for the given property
  func observe(property: String, format: mpv_format = MPV_FORMAT_DOUBLE) {
    player.log.verbose("Adding mpv observer for prop \(property.quoted)")
    mpv_observe_property(mpv, 0, property, format)
  }


  /// As events arrive, read one at a time & handle it async
  func readEvents() {
    queue.async {
      while ((self.mpv) != nil) {
        let event = mpv_wait_event(self.mpv, 0)!
        let eventId = event.pointee.event_id
        // Do not deal with mpv-event-none
        if eventId == MPV_EVENT_NONE {
          break
        }
        self.handleEvent(event)
        // Must stop reading events once the mpv core is shutdown.
        if eventId == MPV_EVENT_SHUTDOWN {
          break
        }
      }
    }
  }

  /// Process the event
  private func handleEvent(_ event: UnsafePointer<mpv_event>!) {
    let eventId: mpv_event_id = event.pointee.event_id
    if logEvents && Logger.isEnabled(.verbose) {
      player.log.verbose("Got mpv event: \(eventId)")
    }

    switch eventId {
    case MPV_EVENT_PROPERTY_CHANGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
        handlePropertyChange(property)
      }

    case MPV_EVENT_CLIENT_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      let msg = UnsafeMutablePointer<mpv_event_client_message>(dataOpaquePtr)
      let numArgs: Int = Int((msg?.pointee.num_args)!)
      var args: [String] = []
      if numArgs > 0 {
        let bufferPointer = UnsafeBufferPointer(start: msg?.pointee.args, count: numArgs)
        for i in 0..<numArgs {
          args.append(String(cString: (bufferPointer[i])!))
        }

        if args[0] == "thumbfast-info", args.count > 1 {
          if let thumbfastInfo = ThumbfastInfo.fromJSON(args[1], player.log) {
            self.thumbfastInfo = thumbfastInfo
          }
        }
      }
      player.log.verbose("Got mpv '\(eventId)': \(numArgs >= 0 ? "\(args)": "numArgs=\(numArgs)")")

    case MPV_EVENT_SHUTDOWN:
      player.log.verbose("Got mpv shutdown event")
      DispatchQueue.main.async {
        self.player.mpvHasShutdown()
      }

    case MPV_EVENT_LOG_MESSAGE:
      let dataOpaquePtr = OpaquePointer(event.pointee.data)
      guard let dataPtr = UnsafeMutablePointer<mpv_event_log_message>(dataOpaquePtr) else { break }
      let prefix = String(cString: (dataPtr.pointee.prefix)!)
      let level = String(cString: (dataPtr.pointee.level)!)
      let text = String(cString: (dataPtr.pointee.text)!)

      mpvLogScanner.processLogLine(prefix: prefix, level: level, msg: text)

    case MPV_EVENT_HOOK:
      let userData = event.pointee.reply_userdata
      let hookEvent = event.pointee.data.bindMemory(to: mpv_event_hook.self, capacity: 1).pointee
      let hookID = hookEvent.id
      guard let hook = $hooks.withLock({ $0[userData] }) else { break }
      hook.call {
        mpv_hook_continue(self.mpv, hookID)
      }

    case MPV_EVENT_AUDIO_RECONFIG:
      break

    case MPV_EVENT_VIDEO_RECONFIG:
      break

    case MPV_EVENT_START_FILE:
      guard let path = getString(MPVProperty.path) else {
        // this can happen when file fails to load
        player.log.error("FileStarted: no path!")
        break
      }
      /// Do not use `playlist_entry_id`. It doesn't make sense outside of FileStarted & FileEnded
      let playlistPos = getInt(MPVProperty.playlistPos)

      player.fileStarted(path: path, playlistPos: playlistPos)

    case MPV_EVENT_FILE_LOADED:
      player.fileLoaded()

    case MPV_EVENT_SEEK:
      if needRecordSeekTime {
        recordedSeekStartTime = CACurrentMediaTime()
      }
      player.seeking()

    case MPV_EVENT_PLAYBACK_RESTART:
      if needRecordSeekTime {
        recordedSeekTimeListener?(CACurrentMediaTime() - recordedSeekStartTime)
        recordedSeekTimeListener = nil
      }

      player.playbackRestarted()

    case MPV_EVENT_END_FILE:
      // if receive end-file when loading file, might be error
      // wait for idle
      guard let dataPtr = UnsafeMutablePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data)) else { break }
      let reasonString = dataPtr.pointee.reasonString
      let reason = event!.pointee.data.load(as: mpv_end_file_reason.self)
      // let reasonString = dataPtr.pointee.reasonString
      player.log.verbose("FileEnded, reason: \(reasonString)")
      player.fileEnded(dueToStopCommand: reason == MPV_END_FILE_REASON_STOP)

    case MPV_EVENT_COMMAND_REPLY:
      let reply = event.pointee.reply_userdata
      if reply == MPVController.UserData.screenshot {
        let code = event.pointee.error
        guard code >= 0 else {
          let error = errorString(code)
          player.log.error("Cannot take a screenshot, mpv API error: \(error), returnCalue: \(code)")
          // Unfortunately the mpv API does not provide any details on the failure. The error
          // code returned maps to "error running command", so all the alert can report is
          // that we cannot take a screenshot.
          DispatchQueue.main.async {
            Utility.showAlert("screenshot.error_taking")
          }
          break
        }
        player.screenshotCallback()
      } else if reply == MPVController.UserData.screenshotRaw {
        let code = event.pointee.error
        guard code >= 0 else {
          let error = errorString(code)
          player.log.error("Cannot take a screenshot, mpv API error: \(error), returnCalue: \(code)")
          // Unfortunately the mpv API does not provide any details on the failure. The error
          // code returned maps to "error running command", so all the alert can report is
          // that we cannot take a screenshot.
          DispatchQueue.main.async {
            Utility.showAlert("screenshot.error_taking")
          }
          break
        }

      }

    default:
      player.log.trace("Unhandled mpv event: \(eventId)")
      break
    }

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = "mpv.\(String(cString: mpv_event_name(eventId)))"
      player.events.emit(.init(eventName))
    }
  }

  // MARK: - Property listeners

  private func handlePropertyChange(_ property: mpv_event_property) {
    let name = String(cString: property.name)

    switch name {

    case MPVProperty.videoParams:
      player.log.verbose("Δ mpv prop: \(MPVProperty.videoParams.quoted)")
      player.reloadQuickSettingsView()

    case MPVProperty.videoOutParams:
      /** From the mpv manual:
       ```
       video-out-params
       Same as video-params, but after video filters have been applied. If there are no video filters in use, this will contain the same values as video-params. Note that this is still not necessarily what the video window uses, since the user can change the window size, and all real VOs do their own scaling independently from the filter chain.

       Has the same sub-properties as video-params.
       ```
       */
      player.log.verbose("Δ mpv prop: \(MPVProperty.videoOutParams.quoted)")
      break

    case MPVProperty.videoParamsRotate:
      /** `video-params/rotate: Intended display rotation in degrees (clockwise).` - mpv manual
       Do not confuse with the user-configured `video-rotate` (below) */
      if let totalRotation = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee {
        player.log.verbose("Δ mpv prop: 'video-params/rotate' ≔ \(totalRotation)")
        player.saveState()
        /// Any necessary resizing will be handled elsewhere
      }

    case MPVOption.Video.videoRotate:
      guard player.windowController.loaded else { break }
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else { break }
      let userRotation = Int(data)

      // Will only get here if rotation was initiated from mpv. If IINA initiated, the new value would have matched videoGeo.
      player.log.verbose("Δ mpv prop: 'video-rotate' ≔ \(userRotation)")

      player.userRotationDidChange(to: userRotation)

    case MPVProperty.dwidth:
      guard player.windowController.loaded else { break }
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else { break }
      let dwidth = Int(data)
      player.log.verbose("Δ mpv prop: 'dwidth' ≔ \(dwidth)")
      player.displaySizeDidChange()

    case MPVProperty.dheight:
      guard player.windowController.loaded else { break }
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else { break }
      let dheight = Int(data)
      player.log.verbose("Δ mpv prop: 'dheight' ≔ \(dheight)")
      player.displaySizeDidChange()
    case MPVProperty.videoParamsPrimaries:
      fallthrough

    case MPVProperty.videoParamsGamma:
      player.refreshEdrMode()

    case MPVOption.TrackSelection.vid:
      player.vidChanged()

    case MPVOption.TrackSelection.aid:
      player.aidChanged()

    case MPVOption.TrackSelection.sid:
      player.sidChanged()

    case MPVOption.Subtitles.secondarySid:
      player.secondarySidChanged()

    case MPVOption.PlaybackControl.pause:
      guard let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        player.log.error("Failed to parse mpv pause data!")
        break
      }
      player.log.verbose("Δ mpv prop: 'pause' = \(paused.yn)")

      player.pausedStateDidChange(to: paused)

    case MPVProperty.chapter:
      player.chapterChanged()

    case MPVOption.PlaybackControl.speed:
      guard let speed = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else { break }
      player.log.verbose("Δ mpv prop: `speed` = \(speed)")

      player.speedDidChange(to: speed)
      player.reloadQuickSettingsView()

    case MPVOption.PlaybackControl.loopPlaylist, MPVOption.PlaybackControl.loopFile:
      let loopMode = player.getLoopMode()
      switch loopMode {
      case .file:
        player.sendOSD(.fileLoop)
      case .playlist:
        player.sendOSD(.playlistLoop)
      default:
        player.sendOSD(.noLoop)
      }
      player.syncUI(.loop)

    case MPVOption.OSD.osdLevel:
      guard let level = UnsafePointer<Int>(OpaquePointer(property.data))?.pointee else { break }
      player.log.verbose{"Δ mpv prop: `osdLevel` = \(level)"}
      let isUsingMpvOSD: Bool = level != 0
      player.isUsingMpvOSD = isUsingMpvOSD
      if isUsingMpvOSD {
        // If using mpv OSD, then disable IINA's OSD
        player.hideOSD()
      }

    case MPVOption.Video.deinterlace:
      guard let data = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else { break }
      // this property will fire a change event at file start
      if player.info.deinterlace != data {
        player.log.verbose{"Δ mpv prop: `deinterlace` = \(data.yesno)"}
        player.info.deinterlace = data
        player.sendOSD(.deinterlace(data))
      }
      player.reloadQuickSettingsView()

    case MPVOption.Video.hwdec:
      let data = String(cString: property.data.assumingMemoryBound(to: UnsafePointer<UInt8>.self).pointee)
      if player.info.hwdec != data {
        player.log.verbose{"Δ mpv prop: `hwdec` = \(data)"}
        player.info.hwdec = data
        player.sendOSD(.hwdec(player.info.hwdecEnabled))
      }
      player.reloadQuickSettingsView()

    case MPVOption.Audio.mute:
      guard let isMuted = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.mute, property.format)
        break
      }
      guard player.info.isMuted != isMuted else { break }
      player.info.isMuted = isMuted
      player.syncUI(.muteButton)
      let volume = Int(player.info.volume)
      player.sendOSD(isMuted ? OSDMessage.mute(volume) : OSDMessage.unMute(volume))

    case MPVOption.Audio.volume:
      guard let volume = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.volume, property.format)
        break
      }
      guard player.info.volume != volume else { break }
      player.info.volume = volume
      player.syncUI(.volume)
      player.sendOSD(.volume(Int(volume)))

    case MPVOption.Audio.audioDelay:
      guard let delayUnrounded = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Audio.audioDelay, property.format)
        break
      }
      let delay = delayUnrounded.roundedTo6()
      if player.info.audioDelay != delay {
        player.log.verbose{"Δ mpv prop: `audio-delay` = \(delay)"}
        player.info.audioDelay = delay
        player.sendOSD(.audioDelay(delay))
        player.reloadQuickSettingsView()
      }

    case MPVOption.Subtitles.subVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isSubVisible != visible {
          player.info.isSubVisible = visible
          player.sendOSD(visible ? .subVisible : .subHidden)
          player.reloadQuickSettingsView()
        }
      }

    case MPVOption.Subtitles.secondarySubVisibility:
      if let visible = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
        if player.info.isSecondSubVisible != visible {
          player.info.isSecondSubVisible = visible
          player.sendOSD(visible ? .secondSubVisible : .secondSubHidden)
          player.reloadQuickSettingsView()
        }
      }

    case MPVOption.Subtitles.secondarySubDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      player.log.verbose{"Δ mpv prop: `secondary-sub-delay` = \(data)"}

      player.secondarySubDelayChanged(data)

    case MPVOption.Subtitles.subDelay:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      player.subDelayChanged(data)

    case MPVOption.Subtitles.subScale:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Subtitles.subScale, property.format)
        break
      }
      player.subScaleChanged(data)

    case MPVOption.Subtitles.secondarySubPos:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      player.secondarySubPosChanged(data)

    case MPVOption.Subtitles.subPos:
      guard let data = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(name, property.format)
        break
      }
      player.subPosChanged(data)

    case MPVOption.Subtitles.subColor:
      // TODO:
      break

    case MPVOption.Subtitles.subFont:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Subtitles.subFontSize:
      player.reloadQuickSettingsView()
      //      if let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
      //        let fontSize = Int(data)
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBold:
      player.reloadQuickSettingsView()
      //      if let isBold = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBorderColor:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Subtitles.subBorderSize:
      player.reloadQuickSettingsView()
      //      if let borderSize = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee {
      //        // TODO: OSD
      //      }

    case MPVOption.Subtitles.subBackColor:
      player.reloadQuickSettingsView()
      // TODO: OSD

    case MPVOption.Equalizer.contrast:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.contrast, property.format)
        break
      }
      let intData = Int(data)
      player.log.verbose("Δ mpv prop: 'contrast' = \(intData)")
      player.info.contrast = intData
      player.sendOSD(.contrast(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.hue:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.hue, property.format)
        break
      }
      let intData = Int(data)
      player.log.verbose("Δ mpv prop: 'hue' = \(intData)")
      player.info.hue = intData
      player.sendOSD(.hue(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.brightness:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.brightness, property.format)
        break
      }
      let intData = Int(data)
      player.log.verbose("Δ mpv prop: 'brightness' = \(intData)")
      player.info.brightness = intData
      player.sendOSD(.brightness(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.gamma:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.gamma, property.format)
        break
      }
      let intData = Int(data)
      player.log.verbose("Δ mpv prop: 'gamma' = \(intData)")
      player.info.gamma = intData
      player.sendOSD(.gamma(intData))
      player.reloadQuickSettingsView()

    case MPVOption.Equalizer.saturation:
      guard let data = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVOption.Equalizer.saturation, property.format)
        break
      }
      let intData = Int(data)
      player.log.verbose("Δ mpv prop: 'saturation' = \(intData)")
      player.info.saturation = intData
      player.sendOSD(.saturation(intData))
      player.reloadQuickSettingsView()

    case MPVProperty.playlistCount:
      player.log.verbose("Δ mpv prop: 'playlist-count'")
      player.reloadPlaylist()

    case MPVProperty.trackList:
      player.log.verbose("Δ mpv prop: 'track-list'")
      player.trackListChanged()

    case MPVProperty.vf:
      player.log.verbose("Δ mpv prop: 'vf'")
      player.vfChanged()

    case MPVProperty.af:
      player.log.verbose("Δ mpv prop: 'af'")
      player.afChanged()

    case MPVOption.Video.videoAspectOverride:
      guard player.windowController.loaded, !player.isShuttingDown else { break }
      guard let aspect = getString(MPVOption.Video.videoAspectOverride) else { break }
      player.log.verbose("Δ mpv prop: 'video-aspect-override' = \(aspect.quoted)")
      player.setVideoAspectOverride(aspect)

    case MPVProperty.videoParamsAspect:
      guard player.isActive else { break }
      guard let aspectName = getString(MPVProperty.videoParamsAspect) else { break }
      player.log.verbose("Δ mpv prop: 'video-params/aspect' = \(aspectName.quoted)")

    case MPVOption.Window.fullscreen:
      player.syncFullScreenState()

    case MPVOption.Window.ontop:
      player.ontopChanged()

    case MPVOption.Window.cursorAutohide:
      guard let cursorAutohide = getString(MPVOption.Window.cursorAutohide) else { break }
      log.verbose{"Δ mpv prop: 'cursor-autohide' ≔ \(cursorAutohide)"}
      player.updateCursorAutohideState()
      player.windowController.hideCursorTimer.restart()

    case MPVOption.Window.cursorAutohideFsOnly:
      let cursorAutohideFS = getFlag(MPVOption.Window.cursorAutohideFsOnly)
      log.verbose{"Δ mpv prop: 'cursor-autohide-fs-only' ≔ \(cursorAutohideFS.yn)"}
      player.updateCursorAutohideState()
      player.windowController.hideCursorTimer.restart()

    case MPVProperty.windowScale:
      guard let windowScale = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVProperty.windowScale, property.format)
        break
      }

      log.verbose{"Δ mpv prop: 'window-scale' ≔ \(windowScale)"}
      player.setMpvWindowScale(to: windowScale)

    case MPVProperty.mediaTitle:
      player.mediaTitleChanged()

    case MPVProperty.idleActive:
      guard let idleActive = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee else {
        logPropertyValueError(MPVProperty.idleActive, property.format)
        break
      }
      guard idleActive else { break }
      player.idleActiveChanged()

    case MPVProperty.inputBindings:
      do {
        let dataNode = UnsafeMutablePointer<mpv_node>(OpaquePointer(property.data))?.pointee
        let inputBindingArray = try MPVNode.parse(dataNode!)
        let keyMappingList = toKeyMappings(inputBindingArray, filterCommandsBy: { s in true} )

        let mappingListStr = keyMappingList.enumerated().map { (index, mapping) in
          "\t\(String(format: "%03d", index))   \(mapping.confFileFormat)"
        }.joined(separator: "\n")

        player.log.verbose("Δ mpv prop: \(MPVProperty.inputBindings.quoted) ≔\n\(mappingListStr)")
      } catch {
        player.log.error("Failed to parse property data for \(MPVProperty.inputBindings.quoted)!")
      }

    default:
      player.log.verbose("Unhandled mpv prop: \(name.quoted)")
      break

    }

    let listeners = player.events.listeners
    guard !listeners.isEmpty else { return }  // optimization: don't enqueue anything if there are no listeners

    // This code is running in the com.colliderli.iina.controller dispatch queue. We must not run
    // plugins from a task in this queue. Accessing EventController data from a thread in this queue
    // results in data races that can cause a crash. See issue 3986.
    DispatchQueue.main.async { [self] in
      let eventName = EventController.Name("mpv.\(name).changed")
      if player.events.hasListener(for: eventName) {
        // FIXME: better convert to JSValue before passing to call()
        let data: Any
        switch property.format {
        case MPV_FORMAT_FLAG:
          data = property.data.bindMemory(to: Bool.self, capacity: 1).pointee
        case MPV_FORMAT_INT64:
          data = property.data.bindMemory(to: Int64.self, capacity: 1).pointee
        case MPV_FORMAT_DOUBLE:
          data = property.data.bindMemory(to: Double.self, capacity: 1).pointee
        case MPV_FORMAT_STRING:
          data = property.data.bindMemory(to: String.self, capacity: 1).pointee
        default:
          data = 0
        }
        player.events.emit(eventName, data: data)
      }
    }
  }

  /// Log an error when a `mpv` property change event can't be processed because a property value could not be converted to the
  /// expected type.
  ///
  /// A [MPV_EVENT_PROPERTY_CHANGE](https://mpv.io/manual/stable/#command-interface-mpv-event-property-change)
  /// event contains the new value of the property. If that value could not be converted to the expected type then this method is called
  /// to log the problem.
  ///
  /// _However_ the situation is not that simple. The documentation for [mpv_observe_property](https://github.com/mpv-player/mpv/blob/023d02c9504e308ba5a295cd1846f2508b3dd9c2/libmpv/client.h#L1192-L1195)
  /// contains the following warning:
  ///
  /// "if a property is unavailable or retrieving it caused an error, `MPV_FORMAT_NONE` will be set in `mpv_event_property`, even
  /// if the format parameter was set to a different value. In this case, the `mpv_event_property.data` field is invalid"
  ///
  /// With mpv 0.35.0 we are receiving some property change events for the video-params/rotate property that do not contain the
  /// property value. This happens when the core starts before a file is loaded and when the core is stopping. At some point this needs
  /// to be investigated. For now we suppress logging an error for this known case.
  /// - Parameter property: Name of the property whose value changed.
  /// - Parameter format: Format of the value contained in the property change event.
  private func logPropertyValueError(_ property: String, _ format: mpv_format) {
    guard property != MPVProperty.videoParamsRotate || format != MPV_FORMAT_NONE else { return }
    log.error("""
    Value of property \(property) in the property change event could not be converted from
    \(format) to the expected type
    """)
  }

}
