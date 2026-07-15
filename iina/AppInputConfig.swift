//
//  AppInputConfig.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// Application-scoped input config (key bindings).
///
/// The currently active bindings for the IINA app. Includes key lookup table, list of binding candidates, & other data.
/// Built by: `PlayerInputContext.buildAppInputConfig()`
struct AppInputConfig: Sendable {
  /// Return true to send notifications; false otherwise
  typealias NotificationData = [AnyHashable : Any]

  static let log = Logger.input

  // MARK: Shared input sections

  /// Contains static sections which occupy the bottom of every stack.
  /// Sort of like a prototype, but a change to any of these sections will immediately affect all players.
  static private let sharedSectionStack = InputSectionStack(initialEnabledSections: [
    MPVInputSection(name: MPVInputSection.Shared.USER_CONF_SECTION_NAME, [], isForce: true, origin: .confFile),
    MPVInputSection(name: MPVInputSection.Shared.AUDIO_FILTERS_SECTION_NAME, [], isForce: true, origin: .savedFilter),
    MPVInputSection(name: MPVInputSection.Shared.VIDEO_FILTERS_SECTION_NAME, [], isForce: true, origin: .savedFilter),
    MPVInputSection(name: MPVInputSection.Shared.PLUGINS_SECTION_NAME, [], isForce: false, origin: .iinaPlugin),
    MPVInputSection(name: MPVInputSection.Shared.STATIC_MENU_ITEMS_SECTION_NAME, [], isForce: true, origin: .staticMenuItem)
  ])

  /// Should only be called from within a `InputSectionStack.lock` block.
  static var sharedSections: [InputSection] {
    sharedSectionStack.sectionsEnabled.map( { sharedSectionStack.sectionsDefined[$0.name]! })
  }

  /// This includes all key mappings which were auto-created for the built-in menu items and are not configurable
  /// (e.g. File > Quit, Edit > Undo, etc.).
  static var staticMenuItemMappings: [KeyMapping] {
    return sharedSectionStack.sectionsDefined[MPVInputSection.Shared.STATIC_MENU_ITEMS_SECTION_NAME]!.keyMappingList
  }

  /// This should include all mappings loaded from the the user's currently selected Configuration in the Key Bindings UI.
  static func replaceUserConfSectionMappings(with userConfMappings: [KeyMapping], attaching userData: NotificationData? = nil) {
    replaceMappings(forSharedSectionName: MPVInputSection.Shared.USER_CONF_SECTION_NAME, with: userConfMappings, attaching: userData)
  }

  /// This can get called a lot for menu item bindings [by MacOS], so setting onlyIfDifferent=true can possibly cut down on redundant work.
  static func replaceMappings(forSharedSectionName sectionName: String, with mappings: [KeyMapping],
                              onlyIfDifferent: Bool = false, attaching userData: NotificationData? = nil) {
    InputSectionStack.lock.withLock {
      guard let sharedSection = sharedSectionStack.sectionsDefined[sectionName] else { return }

      if DebugConfig.logBindingsRebuild {
        AppInputConfig.log.verbose("Replacing entire section \"\(sharedSection.name)\" with \(mappings.count) mappings")
      }
      // TODO: honor onlyIfDifferent with diff logic
      let sharedSectionUpdated = sharedSection.clone(mappings)
      sharedSectionStack.sectionsDefined[sectionName] = sharedSectionUpdated
      AppInputConfig.rebuildForLastActivePlayer(attaching: userData)
    }
  }

  // MARK: Other Static

  static private var rebuildTicketCounter: Int = 0

  // Use dummy player label initially to ensure it gets overwritten by rebuildForLastActivePlayer() below.
  // We do not want to init the demo player in a variable initializer.
  /// The current instance. The app can only ever support one set of active key bindings at a time, so each time a change is made,
  /// the active bindings are rebuilt and the old set is discarded.
  static private(set) var current = AppInputConfig(version: 0, playerLabel: "null", bindingCandidateList: [], resolverDict: [:],
                                                   partialSequenceDict: [:], duplicateKeys: [],
                                                   userConfSectionStartIndex: 0, userConfSectionEndIndex: 0)

  /// Thread-safe method to rebuild `AppInputConfig.current` (i.e. the app's active set of key bindings)
  /// from the input sections of the last active player.
  ///
  /// This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c.
  /// Rebuilds `appBindingsList` and `currentResolverDict`, updating menu item key equivalents along the way.
  /// When done, notifies the Preferences > Key Bindings table of the update so it can refresh itself, as well
  /// as notifies the other callbacks supplied here as needed.
  static func rebuildForLastActivePlayer(attaching userData: NotificationData? = nil) {
    let ticket = AppInputConfig.rebuildTicketCounter + 1
    if DebugConfig.logBindingsRebuild {
      log.verbose("Requesting AppInputConfig rebuild (tkt #\(ticket))")
    }

    DispatchQueue.main.async {
      guard !AppDelegate.shared.isTerminating else { return }

      // Optimization: drop all but the most recent request (but not if there is an attachment to deliver)
      let hasAttachedData = (userData?.count ?? 0) > 0
      if (ticket <= AppInputConfig.rebuildTicketCounter) && !hasAttachedData {
        return
      }

      AppInputConfig.rebuildTicketCounter = ticket

      let lastActivePlayer = PlayerManager.shared.lastActivePlayer ?? PlayerManager.shared.getOrCreateDemo()
      let activePlayerInputContext = lastActivePlayer.keyBindingContext!
      let appInputConfigNew = activePlayerInputContext.buildAppInputConfig(version: ticket)
      AppInputConfig.current = appInputConfigNew
      log.verbose("Updated AppInputConfig: v\(appInputConfigNew.version), \(appInputConfigNew.resolverDict.count) bindings, for player \(lastActivePlayer.label)")

      var data = userData ?? [:]
      data[BindingTableStateManager.Key.appInputConfig] = appInputConfigNew

      let notification = Notification(name: .iinaAppInputConfigDidChange, object: nil, userInfo: data)
      NotificationCenter.default.post(notification)
    }
  }

  /// Loads the currently selected user InputConf file from cache or disk, using its contents as the `default` section in rebuild
  /// of the app-wide conf (calling `AppInputConfig.rebuildForLastActivePlayer()`.
  ///
  /// 1. Needs to be called at app launch to do the initial build.
  /// 2. Also triggered any time the selected conf is changed in the Configuration table (specifically, in response to
  /// the value of `ConfTableState.current.selectedConfName` being changed (ignoring case).
  /// Returns `true` if load was successful; `false` if not successful and the default IINA conf was used as a fallback.
  @MainActor
  @discardableResult
  static func loadSelectedConfBindingsIntoAppConfig() -> Bool {
    let confManager = ConfTableState.manager
    let inputConfFile = confManager.loadConfFile()
    guard !inputConfFile.failedToLoad else {
      log.error("Cannot get bindings from \(inputConfFile.confName.pii.quoted): file failed to load")
      let fileName = URL(fileURLWithPath: inputConfFile.filePath).lastPathComponent
      confManager.sendErrorAlert(key: "keybinding_config.error", args: [fileName])
      ConfTableState.current.fallBackToDefaultConf()
      return false
    }

    var userData: [BindingTableStateManager.Key: Any] = [BindingTableStateManager.Key.confFile: inputConfFile]

    // Key Bindings table will reload after it receives new data from AppInputConfig.
    // It will default to an animated transition based on calculated diff.
    // To disable animation, specify type .reloadAll explicitly.
    if !Preference.bool(for: .animateKeyBindingTableReloadAll) {
      userData[BindingTableStateManager.Key.tableUIChange] = TableUIChange(.reloadAll)
    }

    // Send down the pipeline
    let userConfMappingsNew = inputConfFile.parseMappings()
    replaceUserConfSectionMappings(with: userConfMappingsNew, attaching: userData)
    return true
  }

  // ---------------------------------------------------------------------------------------------
  // MARK: - Single instance

  let version: Int

  /// The player for which the `default` section & various other player-related sections are relevant.
  /// Should be the last active player when this object was built, or (if no player window was opened since app launch) the "demo" player.
  let associatedPlayerLabel: String

  /// The list of all bindings including those with duplicate keys. The list `allRows` of `BindingTableState` should be kept
  /// consistent with this one as much as possible, but some brief inconsistencies may be acceptable due to the asynchronous nature of UI.
  let bindingCandidateList: [InputBinding]

  /// This structure results from merging the layers of enabled input sections for the currently active player using precedence rules.
  /// Contains indexes into `bindingCandidateList`, only for the bindings which are currently enabled for this player, plus extra dummy
  /// "ignored" bindings for partial key sequences.
  /// For lookup use `resolveInputBinding()` or `matchActiveKeyBinding()` from the active player's input config.
  let resolverDict: [String: Int]

  let partialSequenceDict:  [String: InputBinding]

  /// Binding for mpv's `ANY_UNICODE` wildcard, if any (as of mpv 0.40.0). Index into `bindingCandidateList`.
  let anyUnicode: Int?

  /// Binding for mpv's `UNMAPPED` wildcard, if any (as of mpv 0.40.0). Index into `bindingCandidateList`.
  let unmapped: Int?

  /// (Note: These two fields are used for optimizing the Key Bindings UI  but are otherwise not important.)
  /// The index into `bindingCandidateList` of the first binding in the "default" (user conf) section.
  /// • If the "default" section has no bindings, then this will be the index of the next binding after it in the list,
  /// and also equal to `userConfSectionEndIndex` (thus, userConfSectionSize = userConfSectionEndIndex - userConfSectionStartIndex = 0).
  /// • If the "default" section has no bindings *and* there are no other "strong" sections in the table, then this will be equal to the
  /// size of the list (and not a valid index for lookup)
  /// [Remember that larger index in `bindingCandidateList` signifies higher priority; all "weak" sections' bindings are placed at lower
  /// indexes than "default"; and all "strong" sections' bindings (other than default) are placed at higher indexes than "default"].
  let userConfSectionStartIndex: Int
  /// The index into `bindingCandidateList` of the last binding in the "default" section.
  /// If the "default" section has no bindings, then this will be the index of the first binding belonging to the next "strong" section,
  /// or simply `bindingCandidateList.count` if there are no sections after it.
  let userConfSectionEndIndex: Int

  var userConfSectionLength: Int {
    userConfSectionEndIndex - userConfSectionStartIndex
  }

  init(version: Int, playerLabel: String,
       bindingCandidateList: [InputBinding], resolverDict: [String: Int],
       partialSequenceDict:  [String: InputBinding],
       anyUnicode: Int? = nil, unmapped: Int? = nil,
       duplicateKeys: Set<String>, userConfSectionStartIndex: Int, userConfSectionEndIndex: Int) {
    self.version = version
    self.associatedPlayerLabel = playerLabel
    self.bindingCandidateList = bindingCandidateList
    self.resolverDict = resolverDict
    self.partialSequenceDict = partialSequenceDict
    self.anyUnicode = anyUnicode
    self.unmapped = unmapped
    self.duplicateKeys = duplicateKeys
    self.userConfSectionStartIndex = userConfSectionStartIndex
    self.userConfSectionEndIndex = userConfSectionEndIndex
  }

  let duplicateKeys: Set<String>

  func logEnabledBindings() {
    if DebugConfig.logBindingsRebuild, Logger.isVerboseEnabled {
      let bindingList = bindingCandidateList.filter({ $0.isEnabled })
      AppInputConfig.log.verbose("Currently enabled bindings (\(bindingList.count)):\n\(bindingList.map { "\t\($0)" }.joined(separator: "\n"))")
    }
  }

  /// Takes a raw string directly, and does not examine past key presses.
  /// - `keySequence` must be normalized.
  func resolveInputBinding(_ keySequence: String) -> InputBinding? {
    // Emulate mpv logic for matching ANY_UNICODE
    let keyStrokes = KeyCodeHelper.splitKeystrokes(keySequence)
    if let lastKey = keyStrokes.last {
      if let anyUnicode, KeyCodeHelper.isTypedUnicodeChar(normalizedMpvKey: lastKey) {
        AppInputConfig.log.trace("Key \(lastKey.quoted) matches ANY_UNICODE binding")
        return bindingCandidateList[anyUnicode]
      }
    }

    if let activeBindingIndex = resolverDict[keySequence] {
      return bindingCandidateList[activeBindingIndex]
    }

    if let partialSequnceBinding = partialSequenceDict[keySequence] {
      return partialSequnceBinding
    }

    if let unmapped {
      return bindingCandidateList[unmapped]
    }

    return nil
  }
}
