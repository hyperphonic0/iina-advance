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
    DisplayController.shared.addNewDisplays()
    NSScreen.screens.enumerated().forEach { screen in
      NSScreen.log("NSScreen.screens[\(screen.offset)]" , screen.element)
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
