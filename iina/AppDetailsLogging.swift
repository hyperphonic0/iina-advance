//
//  AppDetailsLogging.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//

@MainActor
struct AppDetailsLogging {
  static let shared = AppDetailsLogging()

  // MARK: - FFmpeg version parsing

  /// Extracts the major version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MAJOR`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The major version number
  private static func avVersionMajor(_ version: UInt32) -> UInt32 {
    version >> 16
  }

  /// Extracts the minor version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MINOR`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The minor version number
  private static func avVersionMinor(_ version: UInt32) -> UInt32 {
    (version & 0x00FF00) >> 8
  }

  /// Extracts the micro version number from the given FFmpeg encoded version number.
  ///
  /// This is a Swift implementation of the FFmpeg macro `AV_VERSION_MICRO`.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: The micro version number
  private static func avVersionMicro(_ version: UInt32) -> UInt32 {
    version & 0xFF
  }

  /// Forms a string representation from the given FFmpeg encoded version number.
  ///
  /// FFmpeg returns the version number of its libraries encoded into an unsigned integer. The FFmpeg source
  /// `libavutil/version.h` describes FFmpeg's versioning scheme and provides C macros for operating on encoded
  /// version numbers. Since the macros can't be used in Swift code we've had to code equivalent functions in Swift.
  /// - Parameter version: Encoded version number in FFmpeg proprietary format.
  /// - Returns: A string containing the version number.
  private static func versionAsString(_ version: UInt32) -> String {
    let major = avVersionMajor(version)
    let minor = avVersionMinor(version)
    let micro = avVersionMicro(version)
    return "\(major).\(minor).\(micro)"
  }

  // MARK: - Logs

  @MainActor
  func logAllAppDetails() {
    // Start the log file by logging the version of IINA producing the log file.
    let (version, build) = InfoDictionary.shared.version
    let type = InfoDictionary.shared.buildTypeIdentifier
    Logger.log("IINA Advance \(version) Build \(build)" + (type == nil ? "" : " " + type!))

    // The copyright is used in the Finder "Get Info" window which is a narrow window so the
    // copyright consists of multiple lines.
    let copyright = InfoDictionary.shared.copyright
    copyright.enumerateLines { line, _ in
      Logger.log(line)
    }

    logDependencyDetails()
    logBuildDetails()
    logPlatformDetails()
    logScreenDetails()
    Preference.logSettings()
  }

  /// Useful to know the versions of significant dependencies that are being used so log that
  /// information as well when it can be obtained.
  private func logDependencyDetails() {
    Logger.log(MPVOptionDefaults.shared.mpvVersion)
    Logger.log("FFmpeg \(String(cString: av_version_info()))")
    // FFmpeg libraries and their versions in alphabetical order.
    let libraries: [(name: String, version: UInt32)] = [("libavcodec", avcodec_version()), ("libavformat", avformat_version()), ("libavutil", avutil_version()), ("libswscale", swscale_version())]
    for library in libraries {
      // The version of FFmpeg libraries is encoded into an unsigned integer in a proprietary
      // format which needs to be decoded into a string for display.
      Logger.log("  \(library.name) \(AppDetailsLogging.versionAsString(library.version))")
    }
    Logger.log("libass \(MPVOptionDefaults.shared.libassVersion)")
    
  }

  /// Log details about when and from what sources IINA was built.
  ///
  /// For developers that take a development build to other machines for testing it is useful to log information that can be used to
  /// distinguish between development builds.
  ///
  /// In support of this the build populated `Info.plist` with keys giving:
  /// - The build date
  /// - The git branch
  /// - The git commit
  private func logBuildDetails() {
    guard let buildDateString = InfoDictionary.shared.buildDateString,
          let sdk = InfoDictionary.shared.buildSDK,
          let xcode = InfoDictionary.shared.buildXcode else { return }
    Logger.log("Built using Xcode \(xcode) and macOS SDK \(sdk) on \(buildDateString)")
    guard let branch = InfoDictionary.shared.buildBranch,
          let commit = InfoDictionary.shared.buildCommit else { return }
    Logger.log("From branch \(branch), commit \(commit)")
  }

  /// Log details about the Mac IINA is running on.
  ///
  /// Certain IINA capabilities, such as hardware acceleration, are contingent upon aspects of the Mac IINA is running on. If available,
  /// this method will log:
  /// - macOS version
  /// - Model identifier of the Mac
  /// - Kind of processor chip
  /// - Amount of physical memory
  /// - Thermal state
  /// - Whether low power mode is active
  /// - Note: At this time IINA does not listen for changes to the thermal state or whether low power mode is active or not. For now
  ///         this information is only logged at startup. That might change if some correlation between these states and IINA's
  ///         behavior is seen.
  private func logPlatformDetails() {
    Logger.log("Running under macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    if let cpu = Sysctl.shared.machineCpuBrandString, let model = Sysctl.shared.hwModel {
      let memory = ProcessInfo.processInfo.physicalMemory / 1073741824
      Logger.log("On a \(model) with an \(cpu) processor and \(memory) GiB of RAM")
    }
    let thermalState = ProcessInfo.processInfo.thermalState
    if thermalState != .nominal {
      Logger.log("Thermal state: \(thermalState)")
    }
    if #available(macOS 12, *), ProcessInfo.processInfo.isLowPowerModeEnabled {
      Logger.log("Low Power Mode is active")
    }
  }

  /// Log all the available [screens](https://developer.apple.com/documentation/appkit/nsscreen) and all the
  /// connected displays.
  private func logScreenDetails() {
    Task {
      await DisplayController.shared.addNewDisplays()
      NSScreen.screens.enumerated().forEach { screen in
        NSScreen.log("NSScreen.screens[\(screen.offset)]" , screen.element)
      }
    }
  }

}

extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .nominal:
      "nominal"
    case .fair:
      "fair"
    case .serious:
      "serious"
    case .critical:
      "critical"
    @unknown default:
      "unknown"
    }
  }
}

fileprivate extension Preference {
  /// Log the value of settings that have been changed from their default value.
  ///
  /// These log messages are intended to be used by developers, not the user, so not all settings that have been changed are logged,
  /// ones not of interest to developers are not logged:
  /// - assrtToken Sensitive information
  /// - controlBarPositionHorizontal Not of interest, frequently changed
  /// - controlBarPositionVertical Not of interest, frequently changed
  /// - musicModeShowAlbumArt Not of interest
  /// - musicModeShowPlaylist Not of interest
  /// - openSubUsername Sensitive information
  /// - playlistWidth Not of interest
  /// - recentDocuments Sensitive information, not of interest, maybe large
  /// - savedAudioFilters Not of interest, maybe large
  /// - savedVideoFilters Not of interest, maybe large
  /// - softVolume Not of interest, frequently changed
  /// - watchProperties Not of interest, maybe large
  ///
  /// Although some values of settings can be determined from log messages emitted by `MPVController` it is easier for
  /// developers to have a concentrated list logged at startup.
  /// - Important: To determine if a setting has changed this method converts the current value of the setting as well as the default
  ///     value for the setting to [AnyHashable](https://developer.apple.com/documentation/swift/anyhashable)
  ///     and then compares the hash values. This filters out many settings that are still set to their default values. _However_ the
  ///     hash values can differ even when the setting is set to the default value. For example, if the user directly sets an IINA setting
  ///     using the [defaults](https://support.apple.com/guide/terminal/edit-property-lists-apda49a1bb2-577e-4721-8f25-ffc0836f6997/mac)
  ///     command like so:
  ///     ```bash
  ///     defaults write com.colliderli.iina enableNowPlayingArtwork true
  ///     ```
  ///     Instead of:
  ///     ```bash
  ///     defaults write com.colliderli.iina enableNowPlayingArtwork -bool true
  ///     ```
  ///     The type of the value will be `NSTaggedPointerString` instead of `__NSCFBoolean` and the hash values will differ
  ///     even when set to the default value. For this reason there is an additional check once the value has been converted to the
  ///     appropriate type and can be directly compared to the default value.
  static func logSettings() {
    guard Logger.isEmitting(.debug) else { return }
    // See the list in this method's documentation comment for why these settings are not logged.
    let doNotLog: [Key] = [.assrtToken, .controlBarPositionHorizontal, .controlBarPositionVertical,
                           .musicModeShowAlbumArt, .musicModeShowPlaylist, .openSubUsername, .playlistWidth,
                           .recentDocuments, .savedAudioFilters, .savedVideoFilters, .softVolume, .watchProperties]
    // There isn't an enumeration of the settings, so we use the keys in the dictionary containing
    // the defaults. Filter the list to remove the keys we do not want to log and then sort the keys
    // so the log messages are ordered for easier reading.
    let keys = Preference.defaultPreference.keys.filter( { !doNotLog.contains($0) } )
      .sorted(by: { $0.rawValue < $1.rawValue })
    log("Partial list of settings changed from their default values:")
    for key in keys {
      guard let defaultValue = Preference.defaultPreference[key] else {
        // Internal error. Nil is not a valid default value.
        log("Default for \(key) is nil", level: .error)
        continue
      }
      guard let value = Preference.value(for: key) else {
        // Internal error. All settings must have defaults.
        log("Value for \(key) is nil", level: .error)
        continue
      }
      // Only the value of recentDocuments which is of type Array<Any> cannot be cast to
      // AnyHashable. As that setting is not logged we do not bother to exclude that key.
      guard let hashableDefault = defaultValue as? AnyHashable else {
        log("Default for \(key) is of type \(type(of: defaultValue)) and cannot be cast to AnyHashable",
            level: .error)
        continue
      }
      guard let hashableValue = value as? AnyHashable else {
        log("Value for \(key) is of type \(type(of: value)) and cannot be cast to AnyHashable",
            level: .error)
        continue
      }
      // NOTE that if the hash does not match may not mean the setting is not set to the default.
      // See the discussion in this method's documentation comment. This check is still useful as it
      // avoids the work to convert the value and its default to their respective type and then into
      // a string.
      guard hashableValue.hashValue != hashableDefault.hashValue else { continue }
      // The values of many settings are not stored in a human friendly representation. The values
      // must be converted to their respective types and then converted to a string.
      let defaultAsString: String
      let valueAsString: String
      // Other than the first entry the cases in the switch are ordered based on the name of the
      // type of the value.
      switch key {
      case .assrtToken, .openSubUsername:
        // These keys should have been filtered above, so this code should never be executed. This
        // code makes sure that if a change to the code causes these keys to be logged the value
        // will be hidden.
        defaultAsString = ""
        valueAsString = "<private>"
      case .actionAfterLaunch:
        defaultAsString = String(describing: ActionAfterLaunch.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ActionAfterLaunch)
      case .arrowButtonAction:
        defaultAsString = String(describing: ArrowButtonAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ArrowButtonAction)
      case .allowScreenSaverForAudio,
          .alwaysFloatOnTop,
          .alwaysOpenInNewWindow,
          .alwaysShowOnTopIcon,
          .audioDriverEnableAVFoundation,
          .autoRepeat,
          .autoSearchOnlineSub,
          .autoSwitchToMusicMode,
          .blackOutMonitor,
          .controlBarStickToCenter,
          .disableAnimations,
          .disableOSDFileStartMsg,
          .disableOSDPauseResumeMsgs,
          .disableOSDSeekMsg,
          .disableOSDSpeedMsg,
          .enableScrollOverSliders,
          .displayInLetterBox,
          .displayKeyBindingRawValues,
          .displayTimeAndBatteryInFullScreen,
          .enableAdvancedSettings,
          .enableCache,
          .enableCmdN,
          .enableControlBarAutoHide,
          .enableDisplayIdle,
          .enableFFmpegImageDecoder,
          .enableHdrSupport,
          .enableHdrWorkaround,
          .enableInitialVolume,
          .enableLogging,
          .enableNowPlayingArtwork,
          .enableOSD,
          .enableRecentDocumentsWorkaround,
          .enableThumbnailForRemoteFiles,
          .enableThumbnailPreview,
          .enableToneMapping,
          .followGlobalSeekTypeWhenAdjustSlider,
          .forceDedicatedGPU,
          .fullScreenWhenOpen,
          .ignoreAssStyles,
          .iinaEnablePluginSystem,
          .keepOpenOnFileEnd,
          .loadIccProfile,
          .musicModeShowAlbumArt,
          .musicModeShowPlaylist,
          .pauseWhenGoesToSleep,
          .pauseWhenInactive,
          .pauseWhenLeavingFullScreen,
          .pauseWhenMinimized,
          .pauseWhenOpen,
          .pauseWhenPip,
          .playlistAutoAdd,
          .playlistAutoPlayNext,
          .playlistShowMetadata,
          .playlistShowMetadataInMusicMode,
          .playWhenEnteringFullScreen,
          .prefetchPlaylistVideoDuration,
          .preventScreenSaver,
          .quitWhenNoOpenedWindow,
          .receiveBetaUpdate,
          .recordPlaybackHistory,
          .recordRecentFiles,
          .replayGainClip,
          .resumeLastPosition,
          .scaleRemainingTime,
          .screenshotCopyToClipboard,
          .screenshotIncludeSubtitle,
          .screenshotSaveToFile,
          .screenshotShowPreview,
          .showBufferingThrobber,
          .showChapterPos,
          .showRemainingTime,
          .showSeekingThrobber,
          .spdifAC3,
          .spdifDTS,
          .spdifDTSHD,
          .subBold,
          .subItalic,
          .subScaleWithWindow,
          .togglePipByMinimizingWindow,
          .togglePipByMinimizingWindowForVideoOnly,
          .touchbarShowRemainingTime,
          .trackAllFilesInRecentOpenMenu,
          .useLegacyFullScreen,
          .useMediaKeys,
          .useMpvOsd,
          .usePhysicalResolution,
          .useUserDefinedConfDir,
          .videoViewAcceptsFirstMouse,
          .ytdlEnabled:
        guard let defaultAsBool = defaultValue as? Bool else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to Bool",
              level: .error)
          continue
        }
        defaultAsString = String(defaultAsBool)
        valueAsString = String(Preference.bool(for: key))
      case .defaultRepeatMode:
        defaultAsString = String(describing: DefaultRepeatMode.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as DefaultRepeatMode)
      case .controlBarAutoHideTimeout,
          .controlBarPositionHorizontal,
          .controlBarPositionVertical,
          .osdAutoHideTimeout,
          .osdTextSize,
          .subBlur,
          .subBorderSize,
          .subMarginX,
          .subMarginY,
          .subPos,
          .subShadowSize,
          .subSpacing,
          .subTextSize:
        guard let defaultAsFloat = defaultValue as? Float else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to Float",
              level: .error)
          continue
        }
        defaultAsString = String(defaultAsFloat)
        valueAsString = String(Preference.float(for: key))
      case .gaplessAudio:
        defaultAsString = String(describing: GaplessAudioOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as GaplessAudioOption)
      case .hardwareDecoder:
        defaultAsString = String(describing: HardwareDecoderOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as HardwareDecoderOption)
      case .subAutoLoadIINA:
        defaultAsString = String(describing: IINAAutoLoadAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as IINAAutoLoadAction)
      case .logLevel:
        defaultAsString = String(describing: Logger.Level.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as Logger.Level)
      case .doubleClickAction,
          .forceTouchAction,
          .middleClickAction,
          .rightClickAction,
          .singleClickAction:
        defaultAsString = String(describing: MouseClickAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as MouseClickAction)
      case .oscPosition:
        defaultAsString = String(describing: OSCPosition.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as OSCPosition)
      case .pinchAction:
        defaultAsString = String(describing: PinchAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as PinchAction)
      case .replayGain:
        defaultAsString = String(describing: ReplayGainOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ReplayGainOption)
      case .resizeWindowOption:
        defaultAsString = String(describing: ResizeWindowOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ResizeWindowOption)
      case .resizeWindowTiming:
        defaultAsString = String(describing: ResizeWindowTiming.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ResizeWindowTiming)
      case .transportRTSPThrough:
        defaultAsString = String(describing: RTSPTransportation.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as RTSPTransportation)
      case .screenshotFormat:
        defaultAsString = String(describing: ScreenshotFormat.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ScreenshotFormat)
      case .horizontalScrollAction, .verticalScrollAction:
        defaultAsString = String(describing: ScrollAction.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ScrollAction)
      case .useExactSeek:
        defaultAsString = String(describing: SeekOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SeekOption)
      case.userOptions:
        defaultAsString = "[]"
        guard let valueAsArray = value as? [[String]] else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to [[String]]",
              level: .error)
          continue
        }
        valueAsString = valueAsArray.reduce("[", { $0 + $1.joined(separator: " = ") }) + "]"
      case .subAlignX:
        defaultAsString = String(describing: SubAlignX.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubAlignX)
      case .subAlignY:
        defaultAsString = String(describing: SubAlignY.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubAlignY)
      case .secondarySubOverrideLevel, .subOverrideLevel:
        defaultAsString = String(describing: SubOverrideLevel.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as SubOverrideLevel)
      case .themeMaterial:
        defaultAsString = String(describing: Theme.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as Theme)
      case .toneMappingAlgorithm:
        defaultAsString = String(describing: ToneMappingAlgorithmOption.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as ToneMappingAlgorithmOption)
      case .controlBarToolbarButtons:
        // The value is an array of ToolBarButton enum values stored as integers.
        guard let defaultAsArray = defaultValue as? [Int] else {
          // Should not occur. Internal error.
          log("Default for \(key) is of type \(type(of: value)) and cannot be cast to [Int]",
              level: .error)
          continue
        }
        defaultAsString = "[" + defaultAsArray.compactMap({
          guard let button = ToolBarButton.init(rawValue: $0) else { return "unknown(\($0))" }
          return String(describing: button)
        }).joined(separator: ", ") + "]"
        guard let valueAsArray = value as? [Int] else {
          // Should not occur. Internal error.
          log("Value for \(key) is of type \(type(of: value)) and cannot be cast to [Int]",
              level: .error)
          continue
        }
        valueAsString = "[" + valueAsArray.compactMap({
          guard let button = ToolBarButton.init(rawValue: $0) else { return "unknown(\($0))" }
          return String(describing: button)
        }).joined(separator: ", ") + "]"
      case .windowBehaviorWhenPip:
        defaultAsString = String(describing: WindowBehaviorWhenPip.defaultValue)
        valueAsString = String(describing: Preference.enum(for: key) as WindowBehaviorWhenPip)
      default:
        // The remaining settings have values that are integers or strings and can be directly
        // converted to strings.
        defaultAsString = String(describing: defaultValue)
        valueAsString = String(describing: value)
      }
      // Now that the value and the default have both been converted to their human readable form
      // we can deterministically check if the setting has been changed from its default.
      guard valueAsString != defaultAsString else { continue }
      // To make the output easier to read we don't include the default value of boolean settings as
      // it is obviously the opposite of the current value of the setting. Defaults that are empty
      // strings or arrays are also not included to reduce clutter.
      switch defaultAsString {
      case "", "false", "true", "[]":
        log("\(key.rawValue) = \(valueAsString)")
      default:
        log("\(key.rawValue) = \(valueAsString) (default: \(defaultAsString))")
      }
    }
  }

  /// Log a message using the `settings` logger subsystem.
  ///
  /// This is a wrapper function that merely avoids the need to include the `settings` subsystem in calls to the logger.
  /// - Important: As settings control the logger use of logging by this class _must not_ occur during class initialization.
  /// - Parameters:
  ///   - message: A closure that when executed gives the message to log.
  ///   - level: The log level of the message.
  private static func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.settings)
  }

}

fileprivate extension Logger.Sub {
  static let settings = Logger.makeSubsystem("settings")
}
