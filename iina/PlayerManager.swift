//
//  PlayerManager.swift
//  iina
//
//  Created by Matt Svoboda on 8/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class PlayerManager {
  static var shared = PlayerManager()

  private let lock = Lock()
  private var playerCoreCounter = 0

  private var _playerCores: [PlayerCore] = []
  private var _demoPlayer: PlayerCore? = nil

  var pipPlayer: PlayerCore? = nil {
    willSet {
      let usurperPlayer = newValue
      if let prevPlayer = pipPlayer, prevPlayer != usurperPlayer, let prevPWC = prevPlayer.pwc, prevPWC.currentLayout.isInPiP {
        prevPWC.animationPipeline.submit(.instantTask {
          prevPlayer.log.debug("PlayerManager: another player wants PiP; exiting PiP")
          prevPWC.exitPIP()
        })
      }
    }
  }

  /// Audio-only player. Needed for listing audio devices when no player windows are open.
  /// Should not be used for playing anything.
  var demoPlayer: PlayerCore? {
    var player: PlayerCore?
    lock.withLock {
      player = _demoPlayer
    }
    return player
  }

  /// Returns the last player whose window was "active" (or in MacOS terminology, was the key window).
  var lastActivePlayer: PlayerCore? {
    get {
      lock.withLock {
        return _lastActivePlayer ?? findCurrentlyActivePlayer()
      }
    }
    set {
      lock.withLock {
        _lastActivePlayer = newValue
      }
    }
  }
  weak private var _lastActivePlayer: PlayerCore?

  // Returns a copy of the list of PlayerCores, to ensure concurrency
  var playerCores: [PlayerCore] {
    lock.withLock {
      _playerCores
    }
  }

  var allPlayersShutdown: Bool {
    lock.withLock {
      let runningLabels = _playerCores.compactMap({ player in
        // Non-interactive players don't have callbacks registered.
        // So just assume they finished shutting down and hope it's fine.
        !player.isInteractivePlayer || player.isShutDown ? nil : player.label}
      )
      if !runningLabels.isEmpty {
        Logger.log.verbose("Players have not yet shut down: \(runningLabels)")
        return false
      }
      return true
    }
  }

  var hasOpenPlayer: Bool {
    for player in playerCores {
      if player.pwc.isOpen {
        return true
      }
    }
    return false
  }

  private func _getOrCreateFirst() -> PlayerCore {
    if _playerCores.isEmpty {
      return _createNewPlayerCore()
    }
    return _playerCores[0]
  }

  func getOrCreateFirst() -> PlayerCore {
    lock.withLock {
      _getOrCreateFirst()
    }
  }

  func getActiveOrCreateNew() -> PlayerCore {
    lock.withLock {
      if _playerCores.isEmpty {
        return _createNewPlayerCore()
      } else {
        if Preference.bool(for: .alwaysOpenInNewWindow) {
          return _getIdleOrCreateNew()
        } else {
          if let activePlayer = findCurrentlyActivePlayer() {
            return activePlayer
          } else {
            Logger.log.debug("No active player found; creating new")
            return _createNewPlayerCore()
          }
        }
      }
    }
  }

  /// `isAlternative` means to negate the current value of pref `.alwaysOpenInNewWindow`
  func getActiveOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    if !useNew, let activePlayer {
      return activePlayer
    }
    // If no active player, need to create new. Or if by pref
    return getIdleOrCreateNew()
  }

  /// Finds a player core which was already created but is not in use (idle or not started), or nil if none
  private func _findIdlePlayerCore() -> PlayerCore? {
    var firstIdlePlayer: PlayerCore? = nil
    for p in _playerCores {
      let isPlayerIdleOrUnused = p.isIdleOrUnused
      Logger.log.verbose("Player-\(p.label): hasPlayback=\(p.hasPlayback.yn) idle=\(p.state == .idle) → UNUSED=\(isPlayerIdleOrUnused.yn)")
      if firstIdlePlayer == nil && isPlayerIdleOrUnused {
        firstIdlePlayer = p
      }
    }
    return firstIdlePlayer
  }

  func getNonIdle() -> [PlayerCore] {
    lock.withLock {
      _playerCores.filter { $0.isActive }
    }
  }

  private func _getIdleOrCreateNew() -> PlayerCore {
    if let idleCore = _findIdlePlayerCore() {
      Logger.log.debug("Found idle player: #\(idleCore.label)")
      return idleCore
    }
    Logger.log.debug("No idle player found; creating new")
    return _createNewPlayerCore()
  }

  func getIdleOrCreateNew() -> PlayerCore {
    lock.withLock {
      _getIdleOrCreateNew()
    }
  }

  var activePlayer: PlayerCore? {
    lock.withLock {
      findCurrentlyActivePlayer()
    }
  }

  /// The "active" player is the player attached to the current key window, if any.
  /// If no player window is the key window, returns `nil`.
  private func findCurrentlyActivePlayer() -> PlayerCore? {
    if let wc = NSApp.keyWindow?.windowController as? PlayerWindowController, wc.player.isActive {
      return wc.player
    } else {
      return nil
    }
  }

  /// Demo player is a redundant player which is used for app-wide things such as configuring audio devices or input bindings in prefs
  func getOrCreateDemo() -> PlayerCore {
    let player = lock.withLock {
      if let _demoPlayer {
        return _demoPlayer
      } else {
        Logger.log.debug("Creating demo player")
        let player = PlayerCore(Constants.demoPlayerLabel, isDemoPlayer: true)
        _demoPlayer = player
        return player
      }
    }
    player.start()
    return player
  }

  private func _playerExists(withLabel label: String) -> Bool {
    var exists = false
    exists = _playerCores.first(where: { $0.label == label }) != nil
    return exists
  }

  private func _createNewPlayerCore(withLabel label: String? = nil) -> PlayerCore {
    Logger.log.debug("Creating PlayerCore instance with ID \(label?.quoted ?? "nil")")
    let pc: PlayerCore
    if let label = label {
      guard !_playerExists(withLabel: label) else {
        Logger.fatal("Cannot create new PlayerCore: a player already exists with label \(label.quoted)")
      }
      pc = PlayerCore(label)
    } else {
      let playerLabel = AppData.label(forPlayerCore: playerCoreCounter)
      while _playerExists(withLabel: playerLabel) {
        playerCoreCounter += 1
      }
      pc = PlayerCore(playerLabel)
      playerCoreCounter += 1
    }
    Logger.log.debug("Successfully created PlayerCore \(pc.label)")

    _playerCores.append(pc)
    return pc
  }

  func createNewPlayerCore(withLabel label: String? = nil) -> PlayerCore {
    var pc: PlayerCore? = nil
    lock.withLock {
      pc = _createNewPlayerCore(withLabel: label)
    }
    return pc!
  }

  func removePlayer(withLabel label: String) {
    lock.withLock {
      _playerCores.removeAll(where: { (player) in player.label == label })
      Logger.log.debug("Removed player from app-wide list: \(label.quoted); \(_playerCores.count) remain")
    }
  }
}
