//
//  MPVOptPair.swift
//  iina
//
//  Created by Matt Svoboda on 2025-12-20.
//  Copyright © 2025 lhc. All rights reserved.
//

// Options are of type text, which can be dangerous if unrelated text is on the clipboard.
fileprivate let maxAllowedPastedOptions = 1000

/// mpv user option, as used in the "Additional mpv options" table (in Settings… > Advanced).
struct MPVOptPair {
  /// Should match a valid mpv option or property name, or a name with a `no-` prefix added.
  /// Should not contain leading dashes.
  let key: String
  /// Can be empty ("")
  let val: String

  /// If this option is given in `no-{name}` format, strips the `no-` part to extract the option name.
  var optionName: String { key.droppingPrefix("no-") }

  /// If this option has only one token, returns a new `MPVOptPair` which satisfies one of the forms:
  /// `{optionName}=no` or `{optionName}=yes`
  var normalizedPair: MPVOptPair {
    if val.isEmpty {
      // check for special syntax for yes/no
      if key.hasPrefix("no-") {
        return MPVOptPair(key: optionName, val: Constants.String.mpvNo)
      } else {
        return MPVOptPair(key: key, val: Constants.String.mpvYes)
      }
    }

    // If option has value, use that
    return self
  }

  // MARK: String ser/de

  var undashedString: String {
    if val.isEmpty {
      return key
    }
    return "\(key)=\(val)"
  }

  var hasValidKey: Bool {
    // maybe expand on this more in the future
    !key.isEmpty && !key.containsWhitespaceOrNewlines()
  }

  static let empty = MPVOptPair(key: "", val: "")

  static func toUndashedStrings(_ optionsList: [MPVOptPair]) -> [String] {
    return optionsList.map { $0.undashedString }
  }

  static func toUndashedLinesString(_ optionsList: [MPVOptPair]) -> String {
    return toUndashedStrings(optionsList).joined(separator: "\n")
  }

  static func parseLines(from unparsedString: String) -> [MPVOptPair] {
    let unparsedLineStrings = unparsedString.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: true)
    let optionList = unparsedLineStrings.map{MPVOptPair.parseLine(String($0))}
    return optionList
  }

  static func parseLine(_ stringItem: String) -> MPVOptPair {
    let splitted = stringItem.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
    // Delete unnecessary leading dashes if present
    let key = String(splitted[0]).droppingPrefix("--")
    let val = splitted.count > 1 ? String(splitted[1]) : ""
    return MPVOptPair(key: key, val: val)
  }

  // MARK: - Clipboard

  /// Input pasteboard item: "{key}={val}" (i.e., `opt.undashedString`)
  /// Ouput item: `MPVOptPair`
  static func readOptionsListFromPasteboard(_ pasteboard: NSPasteboard) -> [MPVOptPair] {
    let stringItems = pasteboard.getStringItems()
    guard stringItems.count <= Constants.mpvOptionsTableMaxRowsPerOperation else {
      Logger.log.error("Aborting Paste request in Options table: too many options on the clipboard (\(stringItems.count))")
      return []
    }
    var opts: [MPVOptPair] = []
    for stringItem in stringItems {
      let parsedOpts = MPVOptPair.parseLines(from: stringItem)
      opts.append(contentsOf: parsedOpts)
      guard opts.count <= Constants.mpvOptionsTableMaxRowsPerOperation else {
        Logger.log.error("Aborting Paste request in Options table: too many options parsed so far (\(opts.count))")
        return []
      }
    }
    return opts
  }

  static func readOptionsFromClipboard() -> [MPVOptPair] {
    let optionsList = readOptionsListFromPasteboard(NSPasteboard.general)
    guard optionsList.count < maxAllowedPastedOptions else {
      Logger.log.debug("Disabling paste: clipboard contains more than \(maxAllowedPastedOptions) options (counted: \(optionsList.count))")
      return []
    }
    return optionsList
  }

  // Convert conf file path to URL and put it in clipboard
  static func copyOptionsToClipboard(_ optionsList: [MPVOptPair]) {
    guard !optionsList.isEmpty else {
      Logger.log.debug("Cannot copy options list to the clipboard: list is empty")
      return
    }
    let optionStrings = MPVOptPair.toUndashedStrings(optionsList) as [NSString]
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(optionStrings)
    Logger.log.verbose("Copied to the clipboard: \(optionsList.count) options as NSStrings")
  }

  // MARK: Preferences

  /// Each entry should have a 2-element array in the prefs entry for `PK.userOptions`.
  static func readFromPrefs() -> [MPVOptPair]? {
    guard let legacyOptsList = Preference.value(for: .userOptions) as? [[String]] else { return nil }
    let optsList = legacyOptsList.map { keyValArr in
      let stringItem = keyValArr.joined(separator: "=")
      return MPVOptPair.parseLine(stringItem)
    }
    return optsList
  }

  static func writeToPrefs(_ opts: [MPVOptPair]) {
    let stringArrays: [[String]] = opts.map{ $0.val.isEmpty ? [$0.key] : [$0.key, $0.val] }
    Preference.set(stringArrays, for: .userOptions)
  }
}
