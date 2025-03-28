//
//  MPV_Init.swift
//  iina
//
//  Created by Matt Svoboda on 2025-03-27.
//  Copyright © 2025 lhc. All rights reserved.
//

import VideoToolbox

/// Map from mpv codec name to core media video codec types.
///
/// This map only contains the mpv codecs `adjustCodecWhiteList` can remove from the mpv `hwdec-codecs` option.
/// If any codec types are added then `HardwareDecodeCapabilities` will need to be updated to support them.
fileprivate let mpvCodecToCodecTypes: [String: [CMVideoCodecType]] = [
  "av1": [kCMVideoCodecType_AV1],
  "prores": [kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ,
             kCMVideoCodecType_AppleProResRAW, kCMVideoCodecType_AppleProResRAWHQ],
  "vp9": [kCMVideoCodecType_VP9]
]

// Contains mpv init
extension MPVController {

  /**
   Init the mpv context, set options
   */
  func mpvInit() {
    player.log.verbose("Init mpv")
    // Create a new mpv instance and an associated client API handle to control the mpv instance.
    mpv = mpv_create()

    let userOptions: [[String]]
    if Preference.bool(for: .enableAdvancedSettings) {
      if let opts = Preference.value(for: .userOptions) as? [[String]] {
        // User Options table allows saving of empty values. Filter those out
        userOptions = opts.filter{ $0.count > 0 && !$0[0].isEmpty }
      } else {
        userOptions = []
        DispatchQueue.main.async {  // do not block at startup! Must avoid deadlock in static initializers
          Utility.showAlert("extra_option.cannot_read")
        }
      }
    } else {
      userOptions = []
    }

    // User default settings

    if !player.isRestoring {
      if Preference.bool(for: .enableInitialVolume) {
        setUserOption(PK.initialVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                      level: .verbose)
      } else {
        setUserOption(PK.softVolume, type: .int, forName: MPVOption.Audio.volume, sync: false,
                      level: .verbose)
      }
    }

    // - Advanced

    _updateUsingMpvOSDFromPrefs()

    // Don't log demo player
    if Logger.enabled && !player.isDemoPlayer {
      let path = Logger.logDirectory.appendingPathComponent("mpv-\(player.label).log").path
      player.log.debug("Path of mpv log: \(path.quoted)")
      chkErr(setOptionString(MPVOption.ProgramBehavior.logFile, path, level: .verbose))
    }

    // - General

    let setScreenshotPath = { (key: Preference.Key) -> String in
      if Preference.bool(for: .screenshotSaveToFile) {
        return Utility.screenshotCacheURL.path
      }
      let screenshotPath = Preference.string(for: .screenshotFolder)!
      return NSString(string: screenshotPath).expandingTildeInPath
    }

    if !isPresent(MPVOption.PlaybackControl.hrSeek, in: userOptions) {
      // Use exact seeks by default
      mpv_set_option_string(mpv, MPVOption.PlaybackControl.hrSeek, Constants.String.mpvYes)
    }

    setUserOption(PK.screenshotSaveToFile, type: .other, forName: MPVOption.Screenshot.screenshotDir,
                  level: .verbose, transformer: setScreenshotPath)

    setUserOption(PK.screenshotFormat, type: .other, forName: MPVOption.Screenshot.screenshotFormat,
                  verboseIfDefault: true) { key in
      let v = Preference.integer(for: key)
      let format = Preference.ScreenshotFormat(rawValue: v)
      // Workaround for mpv issue #15107, HDR screenshots are unimplemented (gpu/gpu-next).
      // If the screenshot format is set to JPEG XL then set the screenshot-sw option to yes. This
      // causes the screenshot to be rendered by software instead of the VO. If a HDR video is being
      // displayed in HDR then the resulting screenshot will be HDR.
      self.chkErr(self.setOptionFlag(MPVOption.Screenshot.screenshotSw, format == .jxl,
                                     verboseIfDefault: true))
      return format?.string
    }

    setUserOption(PK.screenshotTemplate, type: .string,
                  forName: MPVOption.Screenshot.screenshotTemplate)

    // Disable mpv's media key system as it now uses the MediaPlayer Framework.
    // Dropped media key support in 10.11 and 10.12.
    chkErr(mpv_set_option_string(mpv, MPVOption.Input.inputMediaKeys, Constants.String.mpvNo))

    updateKeepOpenOptionFromPrefs()

    chkErr(setOptionString(MPVOption.WatchLater.watchLaterDir, Utility.watchLaterURL.path, level: .verbose))
    setUserOption(PK.resumeLastPosition, type: .bool, forName: MPVOption.WatchLater.savePositionOnQuit,
                  verboseIfDefault: true)
    setUserOption(PK.resumeLastPosition, type: .bool, forName: "resume-playback", verboseIfDefault: true)

    // FIXME: set this strategically, based on when to resize.
    setUserOption(.initialWindowSizePosition, type: .string, forName: MPVOption.Window.geometry,
                  level: .verbose)

    // - Codec

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads,
                  verboseIfDefault: true)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads,
                  verboseIfDefault: true)

    setUserOption(PK.hardwareDecoder, type: .other, forName: MPVOption.Video.hwdec,
                  verboseIfDefault: true) { key in
      let value = Preference.integer(for: key)
      return Preference.HardwareDecoderOption(rawValue: value)?.mpvString ?? "auto"
    }

    setUserOption(PK.maxVolume, type: .int, forName: MPVOption.Audio.volumeMax, level: .verbose)

    setUserOption(PK.videoThreads, type: .int, forName: MPVOption.Video.vdLavcThreads, level: .verbose)
    setUserOption(PK.audioThreads, type: .int, forName: MPVOption.Audio.adLavcThreads, level: .verbose)

    setUserOption(PK.audioLanguage, type: .string, forName: MPVOption.TrackSelection.alang,
                  level: .verbose)

    var spdif: [String] = []
    if Preference.bool(for: PK.spdifAC3) { spdif.append("ac3") }
    if Preference.bool(for: PK.spdifDTS){ spdif.append("dts") }
    if Preference.bool(for: PK.spdifDTSHD) { spdif.append("dts-hd") }
    chkErr(setOptionString(MPVOption.Audio.audioSpdif, spdif.joined(separator: ","),
                           verboseIfDefault: true))

    setUserOption(PK.audioDevice, type: .string, forName: MPVOption.Audio.audioDevice,
                  verboseIfDefault: true)

    setUserOption(PK.replayGain, type: .other, forName: MPVOption.Audio.replaygain,
                  verboseIfDefault: true) { key in
      let value = Preference.integer(for: key)
      return Preference.ReplayGainOption(rawValue: value)?.mpvString ?? Constants.String.mpvNo
    }
    setUserOption(PK.replayGainPreamp, type: .float, forName: MPVOption.Audio.replaygainPreamp,
                  verboseIfDefault: true)
    setUserOption(PK.replayGainClip, type: .bool, forName: MPVOption.Audio.replaygainClip,
                  verboseIfDefault: true)
    setUserOption(PK.replayGainFallback, type: .float, forName: MPVOption.Audio.replaygainFallback,
                  verboseIfDefault: true)

    // - Sub

    chkErr(setOptionString(MPVOption.Subtitles.subAuto, Constants.String.mpvNo, level: .verbose))
    chkErr(setOptionalOptionString(MPVOption.Subtitles.subCodepage,
                                   Preference.string(for: .defaultEncoding), verboseIfDefault: true))
    player.info.subEncoding = Preference.string(for: .defaultEncoding)

    let subOverrideHandler: OptionObserverInfo.Transformer = { key in
      (Preference.enum(for: key) as Preference.SubOverrideLevel).string
    }
    setUserOption(PK.subOverrideLevel, type: .other, forName: MPVOption.Subtitles.subAssOverride,
                  verboseIfDefault: true, transformer: subOverrideHandler)
    setUserOption(PK.secondarySubOverrideLevel, type: .other,
                  forName: MPVOption.Subtitles.secondarySubAssOverride, verboseIfDefault: true,
                  transformer: subOverrideHandler)

    setUserOption(PK.subTextFont, type: .string, forName: MPVOption.Subtitles.subFont,
                  verboseIfDefault: true)
    setUserOption(PK.subTextSize, type: .float, forName: MPVOption.Subtitles.subFontSize,
                  verboseIfDefault: true)

    setUserOption(PK.subTextColorString, type: .color, forName: MPVOption.Subtitles.subColor,
                  verboseIfDefault: true)
    setUserOption(PK.subBgColorString, type: .color, forName: MPVOption.Subtitles.subBackColor,
                  verboseIfDefault: true)

    setUserOption(PK.subBold, type: .bool, forName: MPVOption.Subtitles.subBold,
                  verboseIfDefault: true)
    setUserOption(PK.subItalic, type: .bool, forName: MPVOption.Subtitles.subItalic,
                  verboseIfDefault: true)

    setUserOption(PK.subBlur, type: .float, forName: MPVOption.Subtitles.subBlur,
                  verboseIfDefault: true)
    setUserOption(PK.subSpacing, type: .float, forName: MPVOption.Subtitles.subSpacing,
                  verboseIfDefault: true)

    setUserOption(PK.subBorderSize, type: .float, forName: MPVOption.Subtitles.subBorderSize,
                  verboseIfDefault: true)
    setUserOption(PK.subBorderColorString, type: .color, forName: MPVOption.Subtitles.subBorderColor,
                  verboseIfDefault: true)

    setUserOption(PK.subShadowSize, type: .float, forName: MPVOption.Subtitles.subShadowOffset,
                  verboseIfDefault: true)
    setUserOption(PK.subShadowColorString, type: .color, forName: MPVOption.Subtitles.subShadowColor,
                  verboseIfDefault: true)

    setUserOption(PK.subAlignX, type: .other, forName: MPVOption.Subtitles.subAlignX,
                  verboseIfDefault: true) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForX
    }

    setUserOption(PK.subAlignY, type: .other, forName: MPVOption.Subtitles.subAlignY,
                  verboseIfDefault: true) { key in
      let v = Preference.integer(for: key)
      return Preference.SubAlign(rawValue: v)?.stringForY
    }

    setUserOption(PK.subMarginX, type: .int, forName: MPVOption.Subtitles.subMarginX,
                  verboseIfDefault: true)
    setUserOption(PK.subMarginY, type: .int, forName: MPVOption.Subtitles.subMarginY,
                  verboseIfDefault: true)

    setUserOption(PK.subPos, type: .float, forName: MPVOption.Subtitles.subPos, verboseIfDefault: true)

    setUserOption(PK.subLang, type: .string, forName: MPVOption.TrackSelection.slang, level: .verbose)

    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subUseMargins,
                  verboseIfDefault: true)
    setUserOption(PK.displayInLetterBox, type: .bool, forName: MPVOption.Subtitles.subAssForceMargins,
                  verboseIfDefault: true)

    setUserOption(PK.subScaleWithWindow, type: .bool, forName: MPVOption.Subtitles.subScaleByWindow,
                  verboseIfDefault: true)

    // - Network / cache settings

    setUserOption(PK.enableCache, type: .other, forName: MPVOption.Cache.cache,
                  verboseIfDefault: true) { key in
      return Preference.bool(for: key) ? nil : Constants.String.mpvNo
    }

    setUserOption(PK.defaultCacheSize, type: .other, forName: MPVOption.Demuxer.demuxerMaxBytes,
                  verboseIfDefault: true) { key in
      return "\(Preference.integer(for: key))KiB"
    }
    setUserOption(PK.secPrefech, type: .int, forName: MPVOption.Cache.cacheSecs, verboseIfDefault: true)

    setUserOption(PK.userAgent, type: .other, forName: MPVOption.Network.userAgent,
                  verboseIfDefault: true) { key in
      let ua = Preference.string(for: key)!
      return ua.isEmpty ? nil : ua
    }

    setUserOption(PK.transportRTSPThrough, type: .other, forName: MPVOption.Network.rtspTransport,
                  verboseIfDefault: true) { key in
      let v: Preference.RTSPTransportation = Preference.enum(for: .transportRTSPThrough)
      return v.string
    }

    setUserOption(PK.ytdlEnabled, type: .other, forName: MPVOption.ProgramBehavior.ytdl,
                  verboseIfDefault: true) { key in
      let v = Preference.bool(for: .ytdlEnabled)
      if JavascriptPlugin.hasYTDL {
        return "no"
      }
      return v ? "yes" : "no"
    }
    setUserOption(PK.ytdlRawOptions, type: .string, forName: MPVOption.ProgramBehavior.ytdlRawOptions,
                  verboseIfDefault: true)
    let propertiesToReset = [MPVOption.PlaybackControl.abLoopA, MPVOption.PlaybackControl.abLoopB]
    chkErr(setOptionString(MPVOption.ProgramBehavior.resetOnNextFile,
                           propertiesToReset.joined(separator: ","), level: .verbose))

    setUserOption(PK.audioDriverEnableAVFoundation, type: .other, forName: MPVOption.Audio.ao,
                  verboseIfDefault: true) { key in
      Preference.bool(for: key) ? "avfoundation" : "coreaudio"
    }

    // Set user defined conf dir.
    if Preference.bool(for: .enableAdvancedSettings),
       Preference.bool(for: .useUserDefinedConfDir),
       var userConfDir = Preference.string(for: .userDefinedConfDir) {
      userConfDir = NSString(string: userConfDir).standardizingPath
      setOptionString("config", "yes")
      let status = setOptionString(MPVOption.ProgramBehavior.configDir, userConfDir)
      if status < 0 {
        Utility.showAlert("extra_option.config_folder", arguments: [userConfDir], disableMenus: true)
      }
    }

    // Set user defined options.
    if !userOptions.isEmpty {
      log.debug("Setting \(userOptions.count) user configured mpv option values")
      for op in userOptions {
        guard op.count == 2 else {
          log.error("Invalid user option, skipping: \(op)")
          continue
        }

        let status = setOptionString(op[0], op[1])
        if status < 0 {
          let errorString = String(cString: mpv_error_string(status))
          DispatchQueue.main.async {  // do not block startup! Must avoid deadlock in static initializers
            Utility.showAlert("extra_option.error", arguments: [op[0], op[1], status, errorString])
          }
        }
      }
    }

    // Load external scripts

    // Load keybindings. This is still required for mpv to handle media keys or apple remote.
    let inputConfPath = ConfTableState.current.selectedConfFilePath
    chkErr(setOptionalOptionString(MPVOption.Input.inputConf, inputConfPath, level: .verbose))

    // Receive log messages at given level of verbosity.
    chkErr(mpv_request_log_messages(mpv, Constants.mpvLogSubscriptionLevel))

    // Request tick event.
    // chkErr(mpv_request_event(mpv, MPV_EVENT_TICK, 1))

    // Set a custom function that should be called when there are new events.
    mpv_set_wakeup_callback(self.mpv, { (ctx) in
      let mpvController = unsafeBitCast(ctx, to: MPVController.self)
      mpvController.readEvents()
    }, mutableRawPointerOf(obj: self))

    // Observe properties.
    observeProperties.forEach { (k, v) in
      mpv_observe_property(mpv, 0, k, v)
    }

    // Initialize an uninitialized mpv instance. If the mpv instance is already running, an error is returned.
    chkErr(mpv_initialize(mpv))

    // The option watch-later-options is not available until after the mpv instance is initialized.
    // Workaround for mpv issue #14417, watch-later-options missing secondary subtitle delay and sid.
    // Allow the user to override this workaround by setting this mpv option in advanced settings.
    if !isPresent(MPVOption.WatchLater.watchLaterOptions, in: userOptions),
       var watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {

      // In mpv 0.38.0 the default value for the watch-later-options property contains the options
      // sid and sub-delay, but not the corresponding options for the secondary subtitle. This
      // inconsistency is likely to confuse users, so insure the secondary options are also saved in
      // watch later files. Issue #14417 has been fixed, so this workaround will not be needed after
      // the next mpv upgrade.
      var needsUpdate = false
      if watchLaterOptions.contains(MPVOption.TrackSelection.sid),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySid) {
        log.debug("Adding \(MPVOption.Subtitles.secondarySid) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySid
        needsUpdate = true
      }
      if watchLaterOptions.contains(MPVOption.Subtitles.subDelay),
         !watchLaterOptions.contains(MPVOption.Subtitles.secondarySubDelay) {
        log.debug("Adding \(MPVOption.Subtitles.secondarySubDelay) to \(MPVOption.WatchLater.watchLaterOptions)")
        watchLaterOptions += "," + MPVOption.Subtitles.secondarySubDelay
        needsUpdate = true
      }
      if needsUpdate {
        chkErr(setOptionString(MPVOption.WatchLater.watchLaterOptions, watchLaterOptions, level: .verbose))
      }
    }
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {
      let sorted = watchLaterOptions.components(separatedBy: ",").sorted().joined(separator: ",")
      log.debug("Options mpv is configured to save in watch later files: \(sorted)")
    }

    // Must be called after mpv_initialize which sets the default value for hwdec-codecs.
    adjustCodecWhiteList(userOptions: userOptions)
    applyHardwareAccelerationWorkaround(userOptions: userOptions)

    // Set options that can be override by user's config. mpv will log user config when initialize,
    // so we put them here.
    chkErr(setString(MPVOption.Video.vo, "libmpv", level: .verbose))
    chkErr(setString(MPVOption.Window.keepaspect, "no", level: .verbose))
    chkErr(setString(MPVOption.Video.gpuHwdecInterop, "auto", level: .verbose))

    // The option watch-later-options is not available until after the mpv instance is initialized.
    // In mpv 0.34.1 the default value for the watch-later-options property contains the option
    // sub-visibility, but the option secondary-sub-visibility is missing. This inconsistency is
    // likely to confuse users, so insure the visibility setting for secondary subtitles is also
    // saved in watch later files.
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions),
       watchLaterOptions.contains(MPVOption.Subtitles.subVisibility),
       !watchLaterOptions.contains(MPVOption.Subtitles.secondarySubVisibility) {
      setString(MPVOption.WatchLater.watchLaterOptions, watchLaterOptions + "," +
                MPVOption.Subtitles.secondarySubVisibility)
    }
    if let watchLaterOptions = getString(MPVOption.WatchLater.watchLaterOptions) {
      player.log.debug("Options mpv is configured to save in watch later files: \(watchLaterOptions)")
      MPVController.watchLaterOptions = watchLaterOptions
      DispatchQueue.main.async { [self] in
        NotificationCenter.default.post(name: .watchLaterOptionsDidChange, object: player)
      }
    }

    // get version
    mpvVersion = getString(MPVProperty.mpvVersion)

    // Unlike upstream IINA, we do not start any mpv cores until a window has been opened.
    // So we must wait until now to log this info, instead of at app start.
    // Should be fine to log this for every mpv core - it may be useful to have it in every mpv log file.
    player.log.verbose("Configuration when building mpv: \(getString(MPVProperty.mpvConfiguration)!)")
  }

  // MARK: - Support Functions

  /// Remove codecs from the hardware decoding white list that this Mac does not support.
  ///
  /// As explained in [HWAccelIntro](https://trac.ffmpeg.org/wiki/HWAccelIntro),  [FFmpeg](https://ffmpeg.org/)
  /// will automatically fall back to software decoding. _However_ when it does so `FFmpeg` emits an error level log message
  /// referring to "Failed setup". This has confused users debugging problems. To eliminate the overhead of setting up for hardware
  /// decoding only to have it fail, this method removes codecs from the mpv
  /// [hwdec-codecs](https://mpv.io/manual/stable/#options-hwdec-codecs) option that are known to not have
  /// hardware decoding support on this Mac. This is not comprehensive. This method only covers the recent codecs whose support
  /// for hardware decoding varies among Macs. This merely reduces the dependence upon the FFmpeg fallback to software decoding
  /// feature in some cases.
  private func adjustCodecWhiteList(userOptions: [[String]]) {
    // Allow the user to override this behavior.
    guard !isPresent(MPVOption.Video.hwdecCodecs, in: userOptions) else {
      log.debug("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        will not adjust white list
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log.error("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)")
      return
    }
    log.debug("Hardware decoding whitelist (\(MPVOption.Video.hwdecCodecs)) is set to \(whitelist)")
    var adjusted: [String] = []
    var needsAdjustment = false
    codecLoop: for codec in whitelist.components(separatedBy: ",") {
      guard let codecTypes = mpvCodecToCodecTypes[codec] else {
        // Not a codec this method supports removing. Retain it in the option value.
        adjusted.append(codec)
        continue
      }
      // The mpv codec name can map to multiple codec types. If hardware decoding is supported for
      // any of them retain the codec in the option value.
      for codecType in codecTypes {
        if HardwareDecodeCapabilities.shared.isSupported(codecType) {
          adjusted.append(codec)
          continue codecLoop
        }
      }
      needsAdjustment = true
      log.debug("This Mac does not support \(codec) hardware decoding")
    }
    // Only set the option if a change is needed to avoid logging when nothing has changed.
    if needsAdjustment {
      chkErr(setOptionString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ",")))
    }
  }

  /// Determine if this Mac has an Apple Silicon chip.
  /// - Returns: `true` if running on a Mac with an Apple Silicon chip, `false` otherwise.
  private func runningOnAppleSilicon() -> Bool {
    // Old versions of macOS do not support Apple Silicon.
    if #unavailable(macOS 11.0) {
      return false
    }
    var sysinfo = utsname()
    let result = uname(&sysinfo)
    guard result == EXIT_SUCCESS else {
      log.error("uname failed returning \(result)")
      return false
    }
    let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
    guard let machine = String(bytes: data, encoding: .ascii) else {
      log.error("Failed to construct string for sysinfo.machine")
      return false
    }
    return machine.starts(with: "arm64")
  }

  /// Apply a workaround for issue [#4486](https://github.com/iina/iina/issues/4486), if needed.
  ///
  /// On Macs with an Intel chip VP9 hardware acceleration is causing a hang in
  ///[VTDecompressionSessionWaitForAsynchronousFrames](https://developer.apple.com/documentation/videotoolbox/1536066-vtdecompressionsessionwaitforasy).
  /// This has been reproduced with FFmpeg and has been reported in ticket [9599](https://trac.ffmpeg.org/ticket/9599).
  ///
  /// The workaround removes VP9 from the value of the mpv [hwdec-codecs](https://mpv.io/manual/master/#options-hwdec-codecs) option,
  /// the list of codecs eligible for hardware acceleration.
  private func applyHardwareAccelerationWorkaround(userOptions: [[String]]) {
    // The problem is not reproducible under Apple Silicon.
    guard !runningOnAppleSilicon() else {
      log.debug("Running on Apple Silicon, not applying FFmpeg 9599 workaround")
      return
    }
    // Allow the user to override this behavior.
    guard !isPresent(MPVOption.Video.hwdecCodecs, in: userOptions) else {
      log.debug("""
        Option \(MPVOption.Video.hwdecCodecs) has been set in advanced settings, \
        not applying FFmpeg 9599 workaround
        """)
      return
    }
    guard let whitelist = getString(MPVOption.Video.hwdecCodecs) else {
      // Internal error. Make certain this method is called after mpv_initialize which sets the
      // default value.
      log.error("Failed to obtain the value of option \(MPVOption.Video.hwdecCodecs)")
      return
    }
    var adjusted: [String] = []
    var needsWorkaround = false
    codecLoop: for codec in whitelist.components(separatedBy: ",") {
      guard codec == "vp9" else {
        adjusted.append(codec)
        continue
      }
      needsWorkaround = true
    }
    if needsWorkaround {
      log.debug("Disabling hardware acceleration for VP9 encoded videos to workaround FFmpeg 9599")
      chkErr(setOptionString(MPVOption.Video.hwdecCodecs, adjusted.joined(separator: ",")))
    }
  }

  /// Searches the list of user configured `mpv` options and returns `true` if the given option is present.
  /// - Parameter option: Option to look for.
  /// - Returns: `true` if the `mpv` option is found, `false` otherwise.
  private func isPresent(_ option: String, in userOptions: [[String]]) -> Bool {
    return userOptions.contains { $0.count >= 1 && $0[0] == option }
  }

}
