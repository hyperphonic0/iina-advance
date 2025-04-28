//
//  InfoDictionary.swift
//  iina
//
//  Created by low-batt on 10/9/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// Wrapper for the dictionary constructed from the bundle’s `Info.plist` file.
///
/// This class exposes some of the entries contained in `Bundle.main.infoDictionary` as properties to provide for easier access
/// to information contained in the dictionary from other classes.
struct InfoDictionary {
  static let executableName = "IINA Advance"
  /// The usage message to be displayed for help on the command line.
  static var iinaBinaryUsageText: String { buildUsageText(iinaCLI: false) }
  static var iinaCLIUsageText: String { buildUsageText(iinaCLI: true) }

  private static func buildUsageText(iinaCLI: Bool) -> String {
    let execName = iinaCLI ? "iina-cli" : executableName
    var text =
    """
    Usage: \(execName) [arguments] [files] [-- mpv_option [...]]
    
    Arguments:
    --mpv-*:
            All mpv options are supported here, except those starting with "--no-".
            Example: --mpv-volume=20 --mpv-resume-playback=no
    --separate-windows | -w:
            Open all files in separate windows.
    --stdin, --no-stdin:
            You may also pipe to stdin directly. Sometimes \(execName) can detect whether
            stdin has a file, but sometimes not. Therefore it's recommended to always
            supply --stdin when piping to iina, and --no-stdin when you do not intend
            to use stdin.\n
    """

    if iinaCLI {
      text +=
      """
      --keep-running:
              Normally iina-cli launches IINA and quits immediately. Supply this option
              if you would like to keep it running until the main application exits.\n
      """
    }
    text +=
    """
    --music-mode:
            Enter music mode after opening the media.
    --pip:
            Enter Picture-in-Picture after opening the media. Music mode does not
            support Picture-in-Picture.
    --help | -h:
            Print this message.
    
    mpv Option:
    Raw mpv options without --mpv- prefix. All mpv options are supported here.
    Example: --volume=20 --no-resume-playback
    """

    return text
  }

  static let shared = InfoDictionary()

  var buildBranch: String? { dictionary["\(buildKeyPrefix).branch"] as? String }
  var buildConfiguration: String? { dictionary["\(buildKeyPrefix).configuration"] as? String }
  var buildCommit: String? { dictionary["\(buildKeyPrefix).commit"] as? String }
  var shortCommitSHA: String? {
    guard let buildCommit = buildCommit else { return nil }
    return String(buildCommit.prefix(7))
  }

  var buildDateString: String? {
    return dictionary["\(buildKeyPrefix).date"] as? String
  }

  var buildDate: Date? {
    let dateParser: (String) -> Date?
    let formatter = ISO8601DateFormatter()
    dateParser = formatter.date(from:)
    guard let date = buildDateString,
          let dateObj = dateParser(date) else {
      return nil
    }
    return dateObj
  }

  private var buildKeyPrefix: String {
    // As recommended by Apple, IINA's custom Info.plist keys start with the bundle identifier.
    bundleIdentifier + ".build"
  }

  /// The version of the macOS SDK the application was built with.
  ///
  /// This is the value of the Xcode `SDK_VERSION` build setting.
  var buildSDK: String? { dictionary["\(buildKeyPrefix).sdk"] as? String }

  /// The type of build used to generate this IINA executable.
  ///
  /// This corresponds to the Xcode build configuration.
  var buildType: BuildType {
    guard let buildConfiguration = buildConfiguration else { return .nightly }
    return BuildType(rawValue: buildConfiguration) ?? .nightly
  }

  /// A string identifying the Xcode build configuration that was used to generate this executable.
  ///
  /// IINA's convention is that if there is no indication of the type of build then it is a release build. Therefore this property is `nil` if
  /// this executable was built using the release configuration. Otherwise this property contains a string suitable for display to the user.
  var buildTypeIdentifier: String? { buildType == .release ? nil : buildType.description }

  /// The version of Xcode the application was built with.
  ///
  /// For the SDK Xcode provides a setting with the version in human readable form. Unfortunately that is not the case for the Xcode
  /// version, so the `XCODE_VERSION_ACTUAL` build setting is used which provides the version number in a four character format
  /// that must be parsed and turned into a human readable form.
  var buildXcode: String? {
    guard let asFourChars = dictionary["\(buildKeyPrefix).xcode"] as? String else {
      return nil
    }
    guard asFourChars.count == 4 else { return asFourChars }
    let major: String.SubSequence
    if asFourChars.first == "0" {
      let index = asFourChars.index(asFourChars.startIndex, offsetBy: 1)
      major = asFourChars[index...index]
    } else {
      major = asFourChars.prefix(2)
    }
    let minor: String.SubSequence
    if asFourChars.last == "0" {
      let index = asFourChars.index(asFourChars.endIndex, offsetBy: -2)
      minor = asFourChars[index...index]
    } else {
      minor = asFourChars.suffix(2)
    }
    return "\(major).\(minor)"
  }

  var bundleIdentifier: String { dictionary["CFBundleIdentifier"] as! String }

  var copyright: String { dictionary["NSHumanReadableCopyright"] as! String }

  let dictionary = Bundle.main.infoDictionary!

  /// A Boolean value that indicates whether this executable was an optimized (not debug) build.
  #if DEBUG
  let isDebug = true
  #else
  let isDebug = false
  #endif

  var version: (String, String) {
    return (dictionary["CFBundleShortVersionString"] as! String,
            dictionary["CFBundleVersion"] as! String)
  }

  // MARK: - Enums

  /// Enum corresponding to the build configurations in IINA's Xcode project.
  enum BuildType: String, CustomStringConvertible {
    case beta = "Beta"
    case nightly = "Nightly"
    case release = "Release"
    case debug = "Debug"

    /// A textual representation of this instance.
    ///
    /// IINA's convention is to display the build type in capital letters to ensure it is not over looked.
    var description: String {
      switch self {
      case .beta: return "BETA"
      case .nightly: return "NIGHTLY"
      case .release: return "RELEASE"
      case .debug: return "DEBUG"
      }
    }
  }
}
