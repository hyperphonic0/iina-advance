//
//  SleepPreventer.swift
//  iina
//
//  Created by lhc on 6/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

/// Manage process information agent
/// [activities](https://developer.apple.com/documentation/foundation/processinfo#1651116) for preventing
/// sleep.
/// - Attention: This portion of macOS has proven to be **unreliable**. Previously the macOS function
///     [IOPMAssertionCreateWithName](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname)
///     was used to create a
///     [kIOPMAssertionTypeNoDisplaySleep](https://developer.apple.com/documentation/iokit/kiopmassertiontypenodisplaysleep)
///     assertion with the macOS power management system. That method returns a status code so IINA was able to detect when
///     macOS power management was malfunctioning. This class now uses the
///     [beginActivity](https://developer.apple.com/documentation/foundation/processinfo/1415995-beginactivity)
///     method that does not provide a status code so it will not be obvious when macOS is broken. Should a user report problems
///     with sleep prevention review issues [#3842](https://github.com/iina/iina/issues/3842) and
///     [#3478](https://github.com/iina/iina/issues/3478) to see if they explain the failure.
@MainActor final class SleepPreventer: NSObject {

  /// Token returned by [beginActivity](https://developer.apple.com/documentation/foundation/processinfo/1415995-beginactivity).
  static private var activityToken: NSObjectProtocol?

  /// If `true` then the current activity only prevents the system from sleeping.
  static private var allowScreenSaver = false

  /// Ask macOS to prevent the screen saver from starting or just prevent the system from sleeping.
  ///
  /// This method uses the macOS function
  /// [beginActivity](https://developer.apple.com/documentation/foundation/processinfo/1415995-beginactivity)
  /// to create an
  /// [idleDisplaySleepDisabled](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/1416839-idledisplaysleepdisabled)
  /// activity that prevents the screen saver from starting or an
  /// [idleSystemSleepDisabled](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/1409849-idlesystemsleepdisabled)
  /// activity that prevents the system from sleeping.
  ///
  /// To see the power management assertion created by the activity run the command `pmset -g assertions` in  terminal.
  /// - Parameter allowScreenSaver: If `true` the screen saver will be allowed to start but the system will be prevented from
  ///     sleeping.
  static private func preventSleep(allowScreenSaver: Bool = false) {
    if activityToken != nil {
      guard self.allowScreenSaver != allowScreenSaver else {
        Logger.log.verbose("[sleep] Skipping preventSleep; activity token exists & no change to allowScreenSaver=\(allowScreenSaver.yn)")
        return
      }
      // The outstanding activity does not match what is requested. End the current activity and
      // create a new one.
      Logger.log.verbose("[sleep] Found existing activity token via preventSleep. Calling allowSleep to end it before creating new one")
      allowSleep()
    }
    SleepPreventer.allowScreenSaver = allowScreenSaver
    let options: ProcessInfo.ActivityOptions = allowScreenSaver ?
      .idleSystemSleepDisabled : .idleDisplaySleepDisabled
    activityToken = ProcessInfo.processInfo.beginActivity(options: options,
                                                          reason: "IINA playback is in progress")

    Logger.log.verbose("[sleep] \(allowScreenSaver ? "Preventing system from sleeping" : "Preventing screen saver from starting")")
  }

  static private func allowSleep() {
    guard let activityToken else {
      Logger.log.verbose("[sleep] Skipping allowSleep; no activity token")
      return
    }
    Logger.log.verbose("[sleep] \(allowScreenSaver ? "Allowing system to sleep when inactive" : "Allowing screen saver to start when inactive")")

    ProcessInfo.processInfo.endActivity(activityToken)
    SleepPreventer.activityToken = nil
  }

  /// Re-evaluates whether sleep should be prevented by examining the states of all players, then applies any necessary changes.
  ///
  /// This method is safe to call repeatedly but should always be called on the main thread to prevent race conditions.
  /// After this method returns, exactly one of the following states will be in effect:
  /// 1. Prevent both display sleep & screen saver from starting (`ProcessInfo.ActivityOptions.idleDisplaySleepDisabled`)
  /// 2. Prevent display sleep but allow screen saver to start (`ProcessInfo.ActivityOptions.idleSystemSleepDisabled`)
  /// 3. Do not prevent display sleep or screen saver from starting.
  static func updateSleepPrevention() {
    if Preference.bool(for: .preventScreenSaver) {
      let activePlayers = PlayerManager.shared.getNonIdle()
      for player in activePlayers {
        if !player.info.isPaused {
          // Either prevent the screen saver from activating or prevent system from sleeping depending
          // upon user setting.
          let allowScreenSaver = Preference.bool(for: .allowScreenSaverForAudio) && (player.info.currentMediaAudioStatus.isAudio || player.isInMiniPlayer)
          SleepPreventer.preventSleep(allowScreenSaver: allowScreenSaver)
          return
        }
      }
      Logger.log.verbose("[sleep] None of the \(activePlayers.count) active players are playing")
    } else {
      Logger.log.trace("[sleep] Skipping: pref preventScreenSaver=N")
    }
    SleepPreventer.allowSleep()
  }

}
