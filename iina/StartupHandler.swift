//
//  swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//


import Foundation
import OrderedCollections

/// Encapsulates code for opening/restoring windows at application startup...and, um, also opening windows when files or URLs
/// are opened manually.
/// See also: `AppDelegate`
final class StartupHandler {

  enum OpenWindowsState: Int {
    case stillEnqueuing = 1
    case doneEnqueuing
    case doneOpening
  }

  /// Container for temporary metadata needed during the restore of a saved window.
  fileprivate class WindowToRestore {
    enum State {
      case restoring
      case done
      case cancelled
    }
    let savedWindow: SavedWindow
    var state: State = .restoring
    var wc: WindowController? = nil

    var pwc: PlayerWindowController? { wc as? PlayerWindowController }
    var done: Bool { state == .done }
    var cancelled: Bool { state == .cancelled }
    var saveName: WindowAutosaveName { savedWindow.saveName }

    init(_ savedWindow: SavedWindow, _ wc: WindowController? = nil) {
      self.savedWindow = savedWindow
      self.wc = wc
    }
  }

  /// Like `WindowToRestore`, but specialized for a `PlayerWindow` being restored
  final class PlayerToRestore {
    let savedWindow: SavedWindow
    let savedState: PlayerSaveState
    /// Set of volume remount URLs found in player to restore which still need to be processed.
    /// Key = absolute string of URL
    var volRemountsNotYetProcessed: Set<String>
    /// Dict of volume remount URLs which have been processed.
    /// Key = absolute string of URL
    /// Value = `true` if mounted; `false` if failed or not processed (which should be treated as failed)
    var volRemountsProcessed: [String: Bool] = [:]
    var saveName: WindowAutosaveName { savedWindow.saveName }

    init(_ savedWindow: SavedWindow, _ savedState: PlayerSaveState, volumeRemountsToProcess: Set<String>) {
      self.savedWindow = savedWindow
      self.savedState = savedState
      self.volRemountsNotYetProcessed = volumeRemountsToProcess
    }
  }

  // MARK: Properties

  @MainActor let launchStartTime = CFAbsoluteTimeGetCurrent()

  @Atomic private(set) var state: OpenWindowsState = .stillEnqueuing
  nonisolated var isDoneLaunching: Bool { state == .doneOpening }

  // - Properties: Opening Files Manually

  /// Serves as a queue to store file paths received across multiple invocations of `application(_:openFiles:)` within a short interval.
  @MainActor private var pendingFilesForApplicationOpenFiles: [URL] = []
  /// The timer for `OpenFileRepeatTime` and `application(_:openFiles:)`.
  @MainActor private let openFilesTimer = TimeoutTimer(timeout: Constants.TimeInterval.applicationOpenFilesRepeatTimeout)

  // TODO: clean up messy & confusing logic for `isAwaitingNewWindowsForOpenedFile` & `pwcsForOpenFiles`
  /// When launching, this variable indicates that the UI needs to wait for opened file(s) to finish loading before showing all windows.
  ///
  /// Should be set to `true` when `application(_:openFiles:)`, `handleURLEvent()` or `droppedText()` is called with file(s),
  /// & shortly afterwards, `pwcsForOpenFiles` is expected be set to a non-nil (and non-empty) value.
  /// If needing to abort the wait for new windows for any reason, this variable should be reset to `false`.
  ///
  /// This variable has evolved from its original incarnation in upstream IINA, where it is still named `openFileCalled`.
  @MainActor var isAwaitingNewWindowsForOpenedFile = false
  @MainActor var pwcsForOpenFiles: [PlayerWindowController]? = nil
  @MainActor var pwcsDoneWithFileOpen: [PlayerWindowController] = []

  // - Properties: Restore

  /// The enqueued list of all windows to restore when restoring at launch.
  ///
  /// This includes info for player windows, but for player-specific data the list `playersToRestore` should also be consulted.
  ///
  /// Try to wait until all windows are ready so that we can show all of them at once (when `done` & `!cancelled`).
  /// - Make sure order of `windowsToRestore` is from back to front to restore the order properly.
  /// - Dict key: saved window name
  @MainActor fileprivate var windowsToRestore: OrderedDictionary<WindowAutosaveName, WindowToRestore> = [:]
  @MainActor fileprivate var windowsToRestoreDoneCount: Int { windowsToRestore.values.reduce(0, { $0 + ($1.done ? 1 : 0) }) }
  @MainActor fileprivate var windowsToRestoreCancelCount: Int { windowsToRestore.values.reduce(0, { $0 + ($1.cancelled ? 1 : 0) }) }
  @MainActor fileprivate var windowsToRestoreCount: Int { windowsToRestore.count - windowsToRestoreCancelCount }
  /// Special case for Open File window when restoring. Because it is a panel, not a window, it will not have
  /// an `NSWindowController`.
  @MainActor fileprivate var restoreOpenFileWindow = false

  /// Dictionary of all pending players to restore.
  /// Dict key: player's saved window name (same as `windowsToRestore`)
  @MainActor var playersToRestore: [WindowAutosaveName: PlayerToRestore] = [:]

  /// Calls `self.restoreDidTimeOut` on timeout, which displays `restoreTimeoutPromptWindow`.
  @MainActor fileprivate let restoreTimer = TimeoutTimer(timeout: Constants.TimeInterval.restoreWindowsTimeout)
  @MainActor fileprivate var restoreTimeoutPromptWindow: ThreeButtonPromptWindow? = nil

  // - Properties: Command Line

  @MainActor var commandLineState: CommandLineState? = nil
  @MainActor var isCommandLine: Bool { commandLineState != nil }

  /// If launched from command line, should ignore `application(_, openFiles:)` during launch.
  /// This is because the above will be called redundantly by MacOS after startup has finished, and after the filenames have already
  /// been parsed from the command line args and we've already handled them. So we need a way to know to ignore these.
  /// However, the system may also call the same API later via various other sources, and we don't want to ignore those.
  /// So we need to set this back to `false` after we receive the call(s) we want to ignore (when the `openFilesTimer` action fires).
  @MainActor var shouldIgnoreOpenFile = false

  // MARK: Init

  @MainActor
  init() {
    restoreTimer.action = restoreDidTimeOut
    openFilesTimer.action = processPendingOpenFiles
  }

  @MainActor
  func doStartup() {
    // Register to restore for successive launches. Set status to currently running so that it isn't restored immediately by the next launch.
    // Do this *before* restoring, because the cleanup task will reassign windows to this launch
    if UIState.shared.isSaveEnabled {
      Logger.log.verbose("Setting pref \(UIState.shared.currentLaunchName.quoted) = \(UIState.LaunchLifecycleState.stillRunning.rawValue)")
      UserDefaults.standard.setValue(UIState.LaunchLifecycleState.stillRunning.rawValue, forKey: UIState.shared.currentLaunchName)
    }
    // Add observer even if save is disabled; it may be re-enabled again
    UserDefaults.standard.addObserver(AppDelegate.shared, forKeyPath: UIState.shared.currentLaunchName, options: .new, context: nil)

    // Restore window state *before* hooking up the listener which saves state.
    restoreWindowsFromPreviousLaunch()

    // If launched via command line, use the logic below to open files and/or stdin, bypassing the normal application openFiles callback
    openFilesFromCommandLine()

    state = .doneEnqueuing
    // Callbacks may have already fired before getting here. Check again to make sure we don't "drop the ball":
    showWindowsIfReady()
  }

  // MARK: - Open Files (at OR after launch)

  /// This can be called either at startup, or after startup. It is called when files are dropped onto the
  /// application icon.
  @MainActor
  func applicationOpenFilesWasReceived(with filePaths: [String]) {
    let urls = filePaths.map { URL(fileURLWithPath: $0) }
    guard !urls.isEmpty else {
      Logger.log.verbose("application(openFiles:) called with: no URLs; returning")
      return
    }

    guard AppDelegate.shared.isInteractiveLaunch else {
      Logger.log.debug("OpenFiles: Launch is not interactive. Ignoring \(urls.count) requested files")
      return
    }

    openFilesTimer.restart()
    pendingFilesForApplicationOpenFiles.append(contentsOf: urls)
  }

  /// Called when `openFilesTimer` times out.
  @MainActor
  private func processPendingOpenFiles() {
    let urls = pendingFilesForApplicationOpenFiles
    pendingFilesForApplicationOpenFiles = []
    guard !urls.isEmpty else { return }

    Logger.log.debug("OpenFiles: collected \(urls.map{PlaybackID.path(from: $0).pii})\(shouldIgnoreOpenFile ? ". Ignoring; launched from CLI" : "")")
    // if launched from command line, should ignore openFile during launch
    guard !shouldIgnoreOpenFile else {
      shouldIgnoreOpenFile = false
      return
    }

    Logger.log.verbose("OpenFiles: collected \(urls.count) files before timeout")

    // if installing a plugin package
    if let pluginPackageURL = urls.first(where: { $0.pathExtension == "iinaplgz" }) {
      Logger.log.debug("Opening plugin URL: \(pluginPackageURL.absoluteString.pii.quoted)")
      AppDelegate.shared.showPreferencesWindow(self)
      AppDelegate.shared.preferenceWindowController.performAction(.installPlugin(url: pluginPackageURL))
      return
    }

    let openedSomething = openFiles(urls) > 0
    if openedSomething {
      Logger.log.verbose("Replying to NSApp: success")
      NSApp.reply(toOpenOrPrint: .success)

      showWindowsIfReady()
    } else {
      Logger.log.verbose("Replying to NSApp: fail")
      NSApp.reply(toOpenOrPrint: .failure)
    }
  }

  @MainActor
  private func openFilesFromCommandLine() {
    guard let cli = commandLineState else { return }
    let validFileURLs: [URL] = cli.filenames.compactMap { filename in
      if Regex.url.matches(filename) {
        return URL(string: filename.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? filename)
      } else {
        return FileManager.default.fileExists(atPath: filename) ? URL(fileURLWithPath: filename) : nil
      }
    }
    guard !validFileURLs.isEmpty else {
      Logger.log.error("No valid file URLs provided via command line! Nothing to do")
      return
    }
    Logger.log.verbose("Will open \(validFileURLs.count) URLs from command line")
    shouldIgnoreOpenFile = true
    openFiles(validFileURLs, applyingCLI: cli)
  }

  /// Open files either from `application(_ ,openFiles:)`, or via command line interface (CLI).
  @MainActor
  @discardableResult
  func openFiles(_ urls: [URL], applyingCLI cli: CommandLineState? = nil, useNewWindows: Bool? = nil) -> Int {
    let shouldOpenNewWindows: Bool
    if let separateWindowsCLI = cli?.openSeparateWindows {
      // Can force --separate-windows via CLI in addition to pref, for both yes/no
      shouldOpenNewWindows = separateWindowsCLI
    } else {
      shouldOpenNewWindows = useNewWindows ?? Preference.bool(for: .alwaysOpenInNewWindow)
    }

    if !isDoneLaunching, !shouldOpenNewWindows {
      // Use only if opening single window.
      // If multiple windows, don't wait; open each as soon as it loads
      isAwaitingNewWindowsForOpenedFile = true
    }

    var totalFilesOpened = 0
    var totalExistingFilesShown = 0

    var lastPlayer: PlayerCore? = nil
    var pwcsForOpenFiles: [PlayerWindowController] = []

    if shouldOpenNewWindows {
      Logger.log.debug("Opening new windows for URLs: count=\(urls.count) CLI=\((cli != nil).yesno)")

      let urlsToOpen: [URL]
      if Preference.bool(for: .allowDuplicatePlayers) {
        urlsToOpen = urls
      } else {
        urlsToOpen = urls.filter{ url in
          // skip if url is already open in some player
          let activePlayerCores = PlayerManager.shared.playerCores.filter { !$0.isIdleOrUnused }
          let relevantActivePlayerCore = activePlayerCores.first { $0.info.currentURL == url }

          if let relevantActivePlayerCore {
            Logger.log.debug("Requested URL is already playing in open window; will show it instead: \(url.path.pii.quoted)")
            relevantActivePlayerCore.pwc.showWindow(nil)
            totalExistingFilesShown += 1
            return false
          }
          return true
        }
      }

      if urlsToOpen.count > 10 {
        // TODO: put up a confirmation prompt
        Logger.log.warn("User requested to open a large number of windows (count: \(urlsToOpen.count))")
      }

      for url in urlsToOpen {
        // open one window per file
        let player: PlayerCore
        if let cli {
          // We never need to reuse a PlayerCore for command-line launches.
          // CLI args are only applied to the players which open at launch. Any new windows opened afterwards
          // should behave as though not launched via CLI.
          player = PlayerManager.shared.createNewPlayerCore(applyingCLI: cli)
        } else {
          player = PlayerManager.shared.getIdleOrCreateNew()
        }
        let playerFilesOpened = player.openURLs([url])

        guard playerFilesOpened > 0 else { continue }
        player.openedWindowsSetIndex = pwcsForOpenFiles.count
        pwcsForOpenFiles.append(player.pwc)
        totalFilesOpened += playerFilesOpened
        lastPlayer = player
      }

    } else {
      Logger.log.debug("Opening single window for URLs: count=\(urls.count) CLI=\((cli != nil).yesno)")
      let player: PlayerCore
      if let cli {
        player = PlayerManager.shared.createNewPlayerCore(applyingCLI: cli)
      } else {
        // Open pending files in single window. Replace existing player if available
        player = PlayerManager.shared.getActiveOrCreateNew()
      }
      let playerFilesOpened = player.openURLs(urls)
      if playerFilesOpened > 0 {
        pwcsForOpenFiles.append(player.pwc)
        totalFilesOpened += playerFilesOpened
        lastPlayer = player
      }
    }

    if let cli, cli.isStdin {
      Logger.log.debug("Opening player for stdin from CLI")
      let player = PlayerManager.shared.createNewPlayerCore(applyingCLI: cli)
      lastPlayer = player
      player.openURLString("-")
      totalFilesOpened += 1
    }

    if AppDelegate.shared.isInteractiveLaunch, !isDoneLaunching {
      if totalFilesOpened == 0, totalExistingFilesShown == 0 {
        DispatchQueue.main.async { [self] in
          abortWaitForOpenFilePlayerStartup()
          Logger.log.verbose("Notifying user nothing was opened")
          Utility.showAlert("nothing_to_open")
        }
      } else {
        Logger.log.verbose("Will open \(pwcsForOpenFiles.count) new windows for \(totalFilesOpened) files, & will show \(totalExistingFilesShown) existing")
        // Set pwcsForOpenFiles so they can be tracked & shown when ready:
        self.pwcsForOpenFiles = pwcsForOpenFiles

        if let cli, let lastPlayer {
          cli.applySpecialModeToLastPlayer(lastPlayer)
        }
      }
    }
    return totalFilesOpened + totalExistingFilesShown
  }

  @MainActor
  func droppedText(withURLString urlString: String) {
    guard let player = PlayerManager.shared.activePlayer else { return }
    let isStartingUp = !isDoneLaunching
    if isStartingUp {
      isAwaitingNewWindowsForOpenedFile = true
    }
    if player.openURLString(urlString) == 0 {
      abortWaitForOpenFilePlayerStartup()
    } else if isStartingUp {
      pwcsForOpenFiles = [player.pwc]
    }
    showWindowsIfReady()
  }

  // MARK: - Restore From Prev Launch

  /// Returns `true` if any windows were restored; `false` otherwise.
  @MainActor @discardableResult
  private func restoreWindowsFromPreviousLaunch() -> Bool {
    let log = Logger.restore

    guard UIState.shared.isRestoreEnabled else {
      log.debug("Restore is disabled. Skipping restore")
      return false
    }

    if isCommandLine && !Preference.bool(for: .enableRestoreUIStateForCmdLineLaunches) {
      log.debug("Restore is disabled for command-line launches. Will not restore launches or save this launch's state")
      UIState.shared.disableSaveAndRestoreUntilNextLaunch()
      return false
    }

    let pastLaunches: [UIState.LaunchState] = UIState.shared.collectLaunchStateForRestore()
    log.verbose("Found \(pastLaunches.count) past launches to restore")
    if pastLaunches.isEmpty {
      return false
    }

    let stopwatch = Utility.Stopwatch()

    let isRestoreApproved = checkForRestoreApproval()
    if !isRestoreApproved {
      // Clear out old state. It may have been causing errors, or user wants to start new
      log.debug("User denied restore. Clearing all saved launch state.")
      UIState.shared.clearAllSavedLaunches()
      Preference.set(false, for: .isRestoreInProgress)
      return false
    }

    // If too much time has passed (in particular if user took a long time to respond to confirmation dialog), consider the data stale.
    // Due to 1s delay in chosen strategy for verifying whether other instances are running, try not to repeat it twice.
    // Users who are quick with their user interface device probably know what they are doing and will be impatient.
    let pastLaunchesCache = stopwatch.secElapsed > Constants.TimeInterval.pastLaunchResponseTimeout ? nil : pastLaunches
    let savedWindowsBackToFront = UIState.shared.consolidateSavedWindowsFromPastLaunches(pastLaunches: pastLaunchesCache)

    guard !savedWindowsBackToFront.isEmpty else {
      log.debug("Nothing to restore: stored window list empty")
      return false
    }

    if savedWindowsBackToFront.count == 1 {
      let onlyWindow = savedWindowsBackToFront[0].saveName

      if onlyWindow == WindowAutosaveName.inspector {
        // Do not restore this on its own
        log.verbose("Nothing to restore: only open window was Inspector")
        return false
      }

      let action: Preference.ActionAfterLaunch = Preference.enum(for: .actionAfterLaunch)
      if (onlyWindow == WindowAutosaveName.welcome && action == .welcomeWindow)
          || (onlyWindow == WindowAutosaveName.openURL && action == .openPanel)
          || (onlyWindow == WindowAutosaveName.playbackHistory && action == .historyWindow) {
        log.verbose("Nothing to restore: the only open window was identical to launch action (\(action))")
        // Skip the prompts below because they are just unnecessary nagging
        return false
      }
    }

    log.verbose("Starting restore of \(savedWindowsBackToFront.count) windows")
    Preference.set(true, for: .isRestoreInProgress)

    /// # VOLUME REMOUNT HANDLING: #VolumeRemount
    var volumeRemountsToProcess: [String: [PlayerSaveState.PlaybackItemData]] = [:]

    let app = AppDelegate.shared
    // Show windows one by one, starting at back and iterating to front:
    for savedWindow in savedWindowsBackToFront {
      log.verbose("Starting restore of window: \(savedWindow.saveName)\(savedWindow.isMinimized ? " (minimized)" : "")")

      switch savedWindow.saveName {
      case .playbackHistory:
        addWindowToRestore(savedWindow, app.historyWindow)
        app.showHistoryWindow(self)
      case .welcome:
        addWindowToRestore(savedWindow, app.initialWindow)
        app.showWelcomeWindow()
      case .preferences:
        addWindowToRestore(savedWindow, app.preferenceWindowController)
        app.showPreferencesWindow(nil)
      case .about:
        addWindowToRestore(savedWindow, app.aboutWindow)
        app.showAboutWindow(self)
      case .openFile:
        // No windowController for Open File window. Set flag instead
        restoreOpenFileWindow = true
        UIState.shared.windowsOpen.insert(savedWindow.saveName.string)
      case .openURL:
        // TODO: persist isAlternativeAction too
        addWindowToRestore(savedWindow, app.openURLWindow)
        app.showOpenURLWindow(isAlternativeAction: true)
      case .fontPicker:
        // TODO: restore font picker
        continue
      case .inspector:
        let windowToRestore = addWindowToRestore(savedWindow, app.inspector)
        // Do not show Inspector window. It doesn't support being drawn in the background, but it loads very quickly.
        // So just mark it as 'ready' and show with the rest when they are ready.
        windowToRestore.state = .done
      case .videoFilter:
        addWindowToRestore(savedWindow, app.vfWindow)
        app.showVideoFilterWindow(nil)
      case .audioFilter:
        addWindowToRestore(savedWindow, app.afWindow)
        app.showAudioFilterWindow(nil)
      case .logViewer:
        addWindowToRestore(savedWindow, app.logWindow)
        app.showLogWindow(nil)
      case .newFilter, .editFilter, .saveFilter:
        log.debug("Restoring sheet window \(savedWindow.saveString) is not yet implemented; skipping")

      case .playerWindow(let id):
        /// Attempt to exactly restore play state & UI from last run of IINA (for given player)
        log.debug("Creating new PlayerCore & restoring saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")
        guard let savedState = UIState.shared.getPlayerSaveState(forPlayerID: id) else {
          log.errorDebugAlert("Cannot restore window: could not find saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")
          continue
        }

        // Build these in the loop below
        let pwinToRestore = addWindowToRestore(savedWindow)
        var uniqueVolRemountsForPlayer = Set<String>()

        /// #VolumeRemount
        /// Prepare data structures needed for processing volume remount URLs
        let playerItemsWithVolRemount = savedState.getAllPlaybackBookmarkData().filter({ $0.hasVolRemountURL })
        for remountRelatedData in playerItemsWithVolRemount {
          var array = volumeRemountsToProcess[remountRelatedData.volRemountURL] ?? []
          array.append(remountRelatedData)
          volumeRemountsToProcess[remountRelatedData.volRemountURL] = array
          uniqueVolRemountsForPlayer.insert(remountRelatedData.volRemountURL)
        }

        let playerToRestore = PlayerToRestore(pwinToRestore.savedWindow, savedState, volumeRemountsToProcess: uniqueVolRemountsForPlayer)

        if uniqueVolRemountsForPlayer.isEmpty {
          // Player has no volumes to remount: can proceed immediately with restoring it
          proceedWithPlayerRestore(pwinToRestore, playerToRestore)
        } else {
          // Save player meta, then process volumeRemountURLs asychronously in background DQ.
          playersToRestore[pwinToRestore.saveName] = playerToRestore
        }

      default:
        // Note: Guide is not saved
        log.error("Cannot restore unrecognized autosave enum: \(savedWindow.saveName)")
      }  // end switch

    }  // end loop over savedWindowsBackToFront

    processVolRemountsAsync(volumeRemountsToProcess, log)

    return !windowsToRestore.isEmpty || restoreOpenFileWindow
  }

  /// If this returns true, restore should be attempted using the saved launch state.
  /// If false is returned, then the saved launch state should be deleted and app should launch fresh.
  private func checkForRestoreApproval() -> Bool {
#if DEBUG
    if DebugConfig.alwaysApproveRestore {
      // skip approval to make testing easier
      Logger.restore.debug("Skipping restore approval ∵ pref 'alwaysApproveRestore' is enabled")
      return true
    }
#endif

    if Preference.bool(for: .isRestoreInProgress) {
      // If this flag is still set, the last restore probably failed. If it keeps failing, launch will be impossible.
      // Let user decide whether to try again or delete saved state.
      Logger.restore.debug("Looks like there was a previous restore which didn't complete (pref "
                           + "\(Preference.Key.isRestoreInProgress.rawValue)=Y). Asking user whether to retry or skip")
      return Utility.quickAskPanel("restore_prev_error", useCustomButtons: true)

    } else if Preference.bool(for: .alwaysAskBeforeRestoreAtLaunch) {
      Logger.restore.verbose("Prompting user whether to restore app state, per pref")
      return Utility.quickAskPanel("restore_confirm", useCustomButtons: true)

    } else {
      Logger.restore.trace("No approval for restore required")
      return true
    }
  }

  @MainActor
  fileprivate func proceedWithPlayerRestore(_ pwinToRestore: WindowToRestore, _ playerToRestore: PlayerToRestore) {
    // This will call `player.openURLs()` when done
    if let player = playerToRestore.savedState.restorePlayer(volRemounts: playerToRestore.volRemountsProcessed) {
      pwinToRestore.wc = player.pwc
      if playerToRestore.savedWindow.isMinimized {
        player.pwc.window?.miniaturize(self)
        UIState.shared.windowsMinimized.insert(playerToRestore.saveName.string)
      }
    } else {
      pwinToRestore.state = .cancelled
      showWindowsIfReady()
    }
  }

  @MainActor @discardableResult
  fileprivate func addWindowToRestore(_ savedWindow: SavedWindow, _ wc: WindowController? = nil) -> WindowToRestore {
    Logger.restore.verbose("Adding window to restore: \(savedWindow.saveName.string.quoted), minimized=\(savedWindow.isMinimized.yn)")
    let winMeta = WindowToRestore(savedWindow, wc)
    assert(windowsToRestore[winMeta.saveName] == nil, "Duplicate window to restore: \(winMeta.saveName.string.quoted)")
    windowsToRestore[winMeta.saveName] = winMeta

    // Rebuild UIState window sets as we go:
    if savedWindow.isMinimized, let wc {
      wc.window?.miniaturize(self)
      UIState.shared.windowsMinimized.insert(winMeta.saveName.string)
      // No danger of partial show because it's hidden, so no need to wait; just mark as done now
      winMeta.state = .done
    } else {
      // Add to set of windows to wait for, so we can show them all nicely
      windowsToRestore[winMeta.saveName] = winMeta
      UIState.shared.windowsOpen.insert(winMeta.saveName.string)
    }
    return winMeta
  }

  @MainActor
  func setDoneWithRestore(savedWindowName: WindowAutosaveName) {
    guard !isDoneLaunching, let windowToRestore = windowsToRestore[savedWindowName] else { return }
    Logger.log.verbose("Marking window as done with restore: \(savedWindowName.string.quoted)")
    windowToRestore.state = .done
    showWindowsIfReady()
  }

  /// Called by a `TimeoutTimer` if the restore process is taking too long.  Displays a dialog prompting
  /// the user to discard the stored state, or keep waiting.
  @MainActor
  private func restoreDidTimeOut() {
    let log = Logger.restore
    guard state == .doneEnqueuing else {
      log.error("Restore timed out but state is \(state)")
      return
    }

    // FIXME: also indicate if waiting on opened file

    let totalCount = windowsToRestoreCount
    let doneCount = windowsToRestoreDoneCount
    let stalledWindows: [WindowToRestore] = windowsToRestore.values.filter{ !$0.cancelled && !$0.done }
    var namesStalled: [String] = []
    for (index, stalledWin) in stalledWindows.enumerated() {
      let str: String
      if index > Constants.maxWindowNamesInRestoreTimeoutAlert {
        break
      } else if index == Constants.maxWindowNamesInRestoreTimeoutAlert {
        str = "…"
      } else if let path = stalledWin.pwc?.player.info.currentPlayback?.path {
        str = "\(index+1). \(path.quoted)  [\(stalledWin.saveName)]"
      } else if let player = playersToRestore[stalledWin.saveName], let path = player.savedState.staticURL?.path {
        str = "\(index+1). \(path.quoted)  [\(stalledWin.saveName)]"
      } else {
        str = "\(index+1). \(stalledWin.saveName)"
      }
      namesStalled.append(str)
    }

    log.debug("Restore timed out. Progress: \(doneCount)/\(totalCount). Stalled: \(namesStalled)")
    log.debug("Prompting user whether to discard them & continue, or quit")

    let countStalled = "\(stalledWindows.count)"
    let countTotal = "\(windowsToRestoreCount)"
    let namesStalledString = namesStalled.joined(separator: "\n")
    let msgArgs = [countStalled, countTotal, namesStalledString]

    let keepWaitingAction = { [self] in
      log.debug("User chose button 1: keep waiting")
      dismissTimeoutAlertPanel()
      guard state != .doneOpening else {
        log.debug("Looks like windows finished opening - no need to restart restore timer")
        return
      }
      restoreTimer.restart()
    }

    let discardAction = { [self] in
      // Launch async in case loading actually finished between time the dialog was shown & the time user clicked button
      DispatchQueue.main.async { [self] in
        log.debug("User chose button 2: discard stalled windows & continue with partial restore")
        dismissTimeoutAlertPanel()

        guard state != .doneOpening else {
          log.debug("Looks like windows finished opening - no need to close anything")
          return
        }
        for stalledWindow in stalledWindows {
          // Need to check status again because we are in async task
          guard !stalledWindow.done else {
            log.verbose("Window has become ready; skipping close: \(stalledWindow.saveName)")
            continue
          }
          log.debug("Telling stalled window to close: \(stalledWindow.saveName)")
          if let pwc = stalledWindow.pwc {
            /// This will guarantee `windowMustCancelShow` notification is sent
            pwc.player.closeWindow()
          } else if let wc = stalledWindow.wc {
            wc.close()
            // explicitly call this, as the line above may fail
            wc.postWindowMustCancelShow()
          } else {
            stalledWindow.state = .cancelled
          }
        }
        showWindowsIfReady()
      }
    }

    let quitAction = {
      log.debug("User chose button 3: quit")
      NSApp.terminate(nil)
    }

    if let restoreTimeoutPromptWindow {
      restoreTimeoutPromptWindow.update("restore_timeout", msgArgs: msgArgs, middleBtnArgs: [countStalled],
                                        okAction: keepWaitingAction, middleAction: discardAction, cancelAction: quitAction)
    } else {
      let promptWindow = ThreeButtonPromptWindow("restore_timeout", msgArgs: msgArgs, middleBtnArgs: [countStalled],
                                                 okAction: keepWaitingAction, middleAction: discardAction, cancelAction: quitAction)
      restoreTimeoutPromptWindow = promptWindow
    }

    restoreTimeoutPromptWindow?.makeKeyAndOrderFront(nil)
  }

  /// Called if all the windows become ready while still displaying the timeout dialog, Dismisses the dialog
  /// automatically, so the user does not have to do it themselves.
  @MainActor
  private func dismissTimeoutAlertPanel() {
    guard let restoreTimeoutPromptWindow else { return }

    /// Dismiss the prompt (if any). It seems we can't just call `close` on its `window` object, because the
    /// responder chain is left unusable. Instead, click its default button after setting `state`.
    Logger.log.debug("Dismissing Restore Timeout alert panel")
    restoreTimeoutPromptWindow.close()

    /// This may restart the timer if not in the correct state, so account for that.
  }

  /// Call this if the user opened a new file at startup but we want to discard the state for it
  /// (for example if it couldn't be opened).
  @MainActor
  func abortWaitForOpenFilePlayerStartup() {
    guard !isDoneLaunching else { return }
    Logger.log.verbose("Aborting wait for open files")
    isAwaitingNewWindowsForOpenedFile = false
    pwcsForOpenFiles = nil
    pwcsDoneWithFileOpen.removeAll()
    showWindowsIfReady()
  }

  @MainActor
  func showWindowsIfReady() {
    let log = Logger.restore
    let isInteractiveLaunch = AppDelegate.shared.isInteractiveLaunch

    if isInteractiveLaunch {
      guard state == .doneEnqueuing else {
        log.verbose("Skipping showWindowsIfReady: state (\(state)) != doneEnqueuing")
        return
      }

      let doneCount = windowsToRestoreDoneCount
      let totalCount = windowsToRestoreCount
      guard doneCount == totalCount else {
        log.verbose({
          let openStr: String
          if let pwcsForOpenFiles {
            openStr = " & opening \(pwcsDoneWithFileOpen.count) / \(pwcsForOpenFiles.count)"
          } else {
            openStr = ""
          }
          return "Restarting restore timer: only done restoring \(doneCount) / \(totalCount)\(openStr)"
        }())
        restoreTimer.restart()
        return
      }

      // If an new player window was opened at startup (i.e. not a restored window), wait for this also.
      if isAwaitingNewWindowsForOpenedFile {
        guard let pwcsForOpenFiles else {
          // Probably still building the list. Return for now.
          log.verbose("Startup: isAwaitingNewWindowsForOpenedFile=Y but pwcsForOpenFiles is nil; returning")
          return
        }

        // If opening more than 1 file, proceed immediately. Otherwise wait for it to be ready.
        guard (pwcsForOpenFiles.count > 1) || (pwcsForOpenFiles.count == pwcsDoneWithFileOpen.count) else {
          log.verbose("Startup: still waiting for opened file")
          return
        }
      }

      let newWindCount = pwcsForOpenFiles?.count ?? 0
      if newWindCount == 0 && totalCount == 0 {
        log.verbose("No windows exist to wait for; finishing startup")
      } else {
        log.verbose("All \(totalCount) restored" + (newWindCount > 0 ? " & \(newWindCount) new windows ready" : "") + ". Showing all")
      }
      restoreTimer.cancel()
      dismissTimeoutAlertPanel()

      var prevWindowNumber: Int? = nil
      for winToRestore in windowsToRestore.values {
        guard !winToRestore.cancelled else { continue }
        let windowIsMinimized = UIState.shared.windowsMinimized.contains(winToRestore.saveName.string)
        log.verbose("Showing restored window: \(winToRestore.saveName)\(windowIsMinimized ? " (minimized)" : "")")
        guard !windowIsMinimized else { continue }

        let wc = winToRestore.wc!
        if let prevWindowNumber {
          wc.window?.order(.above, relativeTo: prevWindowNumber)
        }
        prevWindowNumber = wc.window?.windowNumber
        wc.showWindow(self)
      }

      // Windows for opened files (if any).
      // Don't wait for these to be ready. But at least ensure that their ordering is correct.
      if let pwcsForOpenFiles {
        for pwc in pwcsForOpenFiles {
          let wndName = pwc.window!.savedStateName
          log.verbose("Showing new window: \(wndName)")

          // Make this topmost
          if let prevWindowNumber {
            pwc.window?.order(.above, relativeTo: prevWindowNumber)
          }
          prevWindowNumber = pwc.window?.windowNumber
          pwc.showWindow(self)
        }
      }

      if restoreOpenFileWindow {
        // TODO: persist isAlternativeAction too
        AppDelegate.shared.showOpenFileWindow(isAlternativeAction: false)
      }

      // Bring this app to the front, possibly annoying the user who got bored waiting & is now doing something else.
      Logger.log.debug("Activating app")
      NSApp.activate(ignoringOtherApps: true)

      if Preference.bool(for: .isRestoreInProgress) {
        log.verbose("Done restoring windows (\(windowsToRestoreDoneCount))")
        Preference.set(false, for: .isRestoreInProgress)
      } else {
        log.verbose("Done opening windows")
      }
    }

    state = .doneOpening

    if isInteractiveLaunch {
      /// Make sure to do this *after* `state = .doneOpening`
      dismissTimeoutAlertPanel()

      initAppUI()

      let didRestoreSomething = (windowsToRestoreDoneCount > 0) || restoreOpenFileWindow
      let didShowSomething = didRestoreSomething || (pwcsForOpenFiles != nil)
      let canShowWelcomeWindowByDefault = Preference.enum(for: .actionAfterLaunch) == Preference.ActionAfterLaunch.welcomeWindow
      var didShowWelcomeWindow = windowsToRestore[WindowAutosaveName.welcome] != nil
      if !isCommandLine {
        if !didShowSomething {
          // Fall back to default action:
          AppDelegate.shared.doLaunchOrReopenAction()
          if canShowWelcomeWindowByDefault {
            didShowWelcomeWindow = true
          }
          DispatchQueue.main.async {
            // Optimization: pre-load a new idle player if none started, for a snappier drag & drop effect in Welcome window
            log.debug("No players were explicitly opened at launch - will preemptively create a new idle player")
            // Don't load "Additional mpv options" yet - they may immediately show error pop-ups if invalid.
            // And they will be loaded again when the user actually opens a window, so don't do duplicate work.
            _ = PlayerManager.shared.getIdleOrCreateNew(loadAdditionalMpvOptionsFromPrefs: false)
          }
        }

        // Optimization: pre-load welcome window dependencies if it can be shown
        if !didShowWelcomeWindow {
          let canShowWelcomeWindow = Preference.bool(for: .enableCmdN) || canShowWelcomeWindowByDefault
          if canShowWelcomeWindow {
            log.debug("Welcome window can be shown but is not yet shown; will preemptively load it from XIB & start History service for it")
            let _ = AppDelegate.shared.initialWindow.window
            HistoryController.shared.start()
          }
        }
      }
    }

    // Free memory no longer needed
    windowsToRestore = [:]

    let timeElapsed: Double = CFAbsoluteTimeGetCurrent() - launchStartTime
    Logger.log.verbose("Done with startup (\(timeElapsed.stringMaxFrac2)s)")
  }


  @MainActor
  func initAppUI() {
    Logger.log.debug("Init app UI")
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }

    // Various initializations at App level
    NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = false
    // Make sure this is enabled so that tab-related menu items show up in the Window menu.
    // We will disable tabbing on a per-window basis in each window controller's constructor method.
    NSWindow.allowsAutomaticWindowTabbing = true

    JavascriptPlugin.loadGlobalInstances()

    if let menuController = AppDelegate.shared.menuController {
      menuController.initMenus()
    }

#if !MACOS_13_AVAILABLE
    // show alpha in color panels
    // This actually causes a window to open in the background. Only run this if newer API can't be used
    NSColorPanel.shared.showsAlpha = true
#endif

    // Init MediaPlayer integration
    MediaPlayerIntegration.shared.update()

    NSApplication.shared.servicesProvider = self

    Logger.log.verbose("Registering for URL events")
    NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(AppDelegate.shared.handleURLEvent(event:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

    // Hide Window > "Enter Full Screen" menu item, because this is already present in the Video menu
    UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
  }

  // MARK: - Volume Remounts

  /// #VolumeRemount
  private func processVolRemountsAsync(_ volumeRemountsToProcess: [String: [PlayerSaveState.PlaybackItemData]],
                                       _ log: any Logger.Subsystem) {
    // Need to process volume remounts in background DQ because bookmark resolution can block for a long time before timing out
    PlayerSaveState.saveQueue.async { [self] in
      log.debug("[Remount] Found \(volumeRemountsToProcess.count) volume remount URLs to process")
      var mountedSet: Set<String> = []

      // 1st pass: loop over all remoounts & check if each is already mounted. This should be very fast, and will ensure that
      // any players which do not rely on unmounted volumes can proceed without being blocked by those which do.
      for (volRemountURLString, dependentItems) in volumeRemountsToProcess {
        assert(!volRemountURLString.isEmpty && !dependentItems.isEmpty)
        guard !isDoneLaunching else {
          return log.debug("[Remount] Aborting processing of remaining remount URLs")
        }

        if let remountURL = URL(string: volRemountURLString), isMounted(remountURL: remountURL) {
          log.verbose("[Remount] Volume is already mounted: remountURL=\(volRemountURLString.pii.quoted)")
          mountedSet.insert(volRemountURLString)
          Task { @MainActor in
            didProcessRemountURLString(volRemountURLString, isMounted: true, log)
          }
        }

      }

      // 2nd pass: check all remount URLs which are not already confirmed as mounted, possibly auto-mounting each.
      for (volRemountURLString, dependentItems) in volumeRemountsToProcess {
        guard !mountedSet.contains(volRemountURLString) else { continue }
        guard !isDoneLaunching else {
          return log.debug("[Remount] Aborting restore of remaining players; startup was marked as done despite remount URLs not completing")
        }
        let isMounted = processVolRemount(volRemountURLString, dependentItems, log)
        Task { @MainActor in
          didProcessRemountURLString(volRemountURLString, isMounted: isMounted, log)
        }
      }
    }

  }

  /// Checks the mounted status of the given mountpoint with remount URL `volRemountURLString`.
  ///
  /// If this returns `true`, the volume at `volRemountURLString` was successfully mounted.
  /// If this returns `false`, the volume could not be mounted or will not be tried, which means that all dependent items should not
  /// try to load from bookmarks, but instead should fall back to loading their static URLs.
  private func processVolRemount(_ volRemountURLString: String,
                                 _ dependentItems: [PlayerSaveState.PlaybackItemData],
                                 _ log: any Logger.Subsystem) -> Bool {
    assert(DispatchQueue.isExecutingIn(PlayerSaveState.saveQueue))

    guard let remountURL = URL(string: volRemountURLString) else {
      log.error("[Remount] Failed to build URL from volume remount string: \(volRemountURLString.pii.quoted)")
      return false
    }

    // Easy case: if volume already mounted, nothing to worry about
    if isMounted(remountURL: remountURL) {
      log.verbose("[Remount] Volume is already mounted: remountURL=\(volRemountURLString.pii.quoted)")
      return true
    }

    // Set this pref to false to fail fast for all bookmarks from this mount (will fall back to static URLs),
    // instead of risking long delays from trying to load unreachable volumes.
    guard Preference.bool(for: .remountVolumesOnRestore) else {
      log.debug("[Remount] Remount on restore disabled: giving up on unmounted or nonexistent volume with remountURL="
                + volRemountURLString.pii.quoted)
      return false
    }

    // Try first bookmark found. The resolution process will trigger remount of the volume, even if the resource
    // ultimately isn't found on it. This method seems better than using `NSWorkspace.shared.open(remountURL)`,
    // because the latter always prompts the user with an authentication dialog even if stored credentials exist.
    log.verbose("[Remount] Trying to load first bookmark from remountURL=\(volRemountURLString.pii.quoted)…")
    let firstItemBookmark = dependentItems[0].bookmark
    if PlaybackID.url(fromBookmark: firstItemBookmark, log) != nil {
      log.verbose("[Remount] Successfully loaded bookmark from remountURL=\(volRemountURLString.pii.quoted)")
      return true
    }

    // Bookmark resolution failed for file. Maybe file doesn't exist. But did it mount the volume?
    if isMounted(remountURL: remountURL) {
      log.verbose("[Remount] Volume was successful mounted by restoring bookmark: remountURL=\(volRemountURLString.pii.quoted)")
      return true
    }

    log.error("[Remount] Failed to remount volume: \(volRemountURLString.pii.quoted)")
    return false
  }

  @MainActor
  private func didProcessRemountURLString(_ volRemountURLString: String, isMounted: Bool, _ log: any Logger.Subsystem) {
    // Need to go back to main DQ to safely access data structures
      guard !isDoneLaunching else {
        log.warn("[Remount] Aborting restore of remaining players; startup was marked as done despite remount URLs not completing")
        return
      }

      for playerToRestore in playersToRestore.values {
        guard let remountProcessed = playerToRestore.volRemountsNotYetProcessed.remove(volRemountURLString) else { continue }
        playerToRestore.volRemountsProcessed[remountProcessed] = isMounted

        guard playerToRestore.volRemountsNotYetProcessed.isEmpty else { continue }
        log.verbose("[Remount] Done processing all \(playerToRestore.volRemountsProcessed.count) volRemountURLs for player "
                    + "\(playerToRestore.saveName.string.quoted): will begin its restore")
        let pwinToRestore = windowsToRestore[playerToRestore.saveName]!
        proceedWithPlayerRestore(pwinToRestore, playerToRestore)
      }
  }

  nonisolated
  private func isMounted(remountURL: URL) -> Bool {
    let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []

    // Normalize for comparison
    let target = remountURL.standardized

    for vol in mounted {
      guard let volStd = vol.volumeRemountURL else { continue }

      // For file volumes: path prefix match is typically sufficient
      if target.isFileURL && volStd.isFileURL {
        // Either same root volume path or the target is contained under it
        if target == volStd || target.path.hasPrefix(volStd.path) {
          return true
        }
        continue
      }

      // For network shares: compare scheme/host and path prefix
      if target.scheme != "file",
         volStd.scheme == target.scheme,
         volStd.host?.localizedCaseInsensitiveCompare(target.host ?? "") == .orderedSame {
        // Loose path prefix match (e.g., smb://server/share vs smb://server/share/folder)
        if target.path.hasPrefix(volStd.path) || volStd.path.hasPrefix(target.path) {
          return true
        }
      }
    }
    return false
  }


  // MARK: - Notification Listeners

  /// Window is done loading and is ready to show.
  /// If the application has already finished launching, this simply calls `showWindow` for the calling window.
  /// If restoring, this should not be fired at all if the window being restored is minimized or hidden due to PiP.
  @MainActor
  func windowIsReadyToShow(_ notification: Notification) {
    let log = Logger.restore

    guard let window = notification.object as? NSWindow else { return }
    guard let wc = window.windowController as? WindowController else {
      log.error("Restored window is ready, but no WindowController for window: \(window.savedStateName.quoted)!")
      return
    }
    guard let savedStateName = WindowAutosaveName(window.savedStateName) else {
      Logger.fatal("Could not create WindowAutosaveName from ready window's savedStateName: \(window.savedStateName.quoted)")
    }

    if isDoneLaunching {
      if window.isMiniaturized {
        Logger.log.verbose("OpenWindow: deminiaturizing window \(window.savedStateName.quoted)")
        // Need to call this instead of showWindow if minimized (otherwise there are visual glitches)
        window.deminiaturize(self)
      } else {
        Logger.log.verbose("OpenWindow: showing window \(window.savedStateName.quoted)")
        wc.showWindow(window)
      }

    } else { // Not done launching
      if Preference.bool(for: .isRestoreInProgress), let winToRestore = windowsToRestore[savedStateName] {
        winToRestore.wc = wc
        winToRestore.state = .done
        log.verbose("Restored window is ready: \(savedStateName.string.quoted). Progress: \(windowsToRestoreDoneCount)/\(state == .doneEnqueuing ? "\(windowsToRestore.count)" : "?")")
      } else if let pwcsForOpenFiles, pwcsForOpenFiles.contains(where: {$0.window!.savedStateName == savedStateName.string}) {
        pwcsDoneWithFileOpen.append(wc as! PlayerWindowController)
        log.verbose("OpenedFile window is ready: \(savedStateName.string.quoted)")
      }
      // Else may be multiple files opened at launch

      // Show all windows if ready
      showWindowsIfReady()
    }
  }

  /// Window failed to load or is hidden. Stop waiting for it
  @MainActor
  func windowMustCancelShow(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let log = Logger.restore

    guard !isDoneLaunching else { return }

    guard let savedStateName = WindowAutosaveName(window.savedStateName) else {
      Logger.fatal("Could not create WindowAutosaveName from cancelled window's savedStateName: \(window.savedStateName.quoted)")
    }

    // No longer waiting for this window before showing all windows
    let toRestoreCountOld = windowsToRestoreCount
    windowsToRestore[savedStateName]?.state = .cancelled
    let toRestoreCountNew = windowsToRestoreCount

    let toOpenFileCountOld = pwcsForOpenFiles?.count ?? 0
    pwcsForOpenFiles?.removeAll(where: { pwc in
      pwc.window!.savedStateName == window.savedStateName
    })
    let toOpenFileCountNew = pwcsForOpenFiles?.count ?? 0

    let removedFromRestoreCount = toRestoreCountOld - toRestoreCountNew
    let removedFromOpenCount = toOpenFileCountOld - toOpenFileCountNew

    log.verbose("Canceled wait for window: \(window.savedStateName.quoted) (removedFromRestoreCount=\(removedFromRestoreCount),"
                + " removedFromOpenCount=\(removedFromOpenCount)). Progress is now: \(windowsToRestoreDoneCount)/\(state == .doneEnqueuing ? "\(windowsToRestoreCount)" : "?")")

    showWindowsIfReady()
  }

  // MARK: - Command Line

  @MainActor
  func processCommandLine(_ cmdLineArgs: ArraySlice<String>) {
    if cmdLineArgs.contains(where: { $0 == "--help" || $0 == "-h" }) {
      print(InfoDictionary.shared.iinaBinaryUsageText)
      exit(0)
    }

    commandLineState = CommandLineState(cmdLineArgs)
    guard let commandLineState else { return }

    // Apply args

    // Replicate logic from main.swift in case this launch did not originate there
    if commandLineState.enterMusicMode && commandLineState.enterPIP {
      // Music mode does not support Picture-in-Picture. Combining these options is not permitted.
      print("Cannot specify both --music-mode and --pip")
      // Command line usage error.
      exit(EX_USAGE)
    }

    let activationPolicy = commandLineState.mpvArguments.last(where: { arg in
      (arg.key == MPVOption.GPURendererOptions.macosAppActivationPolicy) && !arg.val.isEmpty
    })
    if let activationPolicy {
      switch activationPolicy.val {
      case "regular":
        NSApp.setActivationPolicy(.regular)
      case "accessory":
        NSApp.setActivationPolicy(.accessory)
        AppDelegate.shared.isInteractiveLaunch = false
      case "prohibited":
        NSApp.setActivationPolicy(.prohibited)
      default:
        break
      }
    }

    if commandLineState.mpvArguments.contains(where: { $0.key == MPVEncoding.o }) {
      AppDelegate.shared.isInteractiveLaunch = false
    }
  }
}
