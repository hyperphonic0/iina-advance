//
//  NowPlayingInfoManager.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//
import Foundation
import MediaPlayer

final class MediaPlayerIntegration {
  @MainActor static let shared = MediaPlayerIntegration()

  private var enabled = false
  private var lastActivePlayer: PlayerCore? = nil

  @MainActor
  func update() {
    guard !AppDelegate.shared.isTerminating else { return }
    let newEnablement = Preference.bool(for: .useMediaKeys)
    updateEnablement(to: newEnablement)
    guard newEnablement else { return }
    updateNowPlayingInfo()
  }

  @MainActor
  private func updateEnablement(to newEnablement: Bool) {
    let didChange = enabled != newEnablement
    guard didChange else { return }
    enabled = newEnablement

    if newEnablement {
      attachRemoteCommands()
    } else {
      detachAllCommands()
    }
  }

  @MainActor
  func shutdown() {
    updateEnablement(to: false)
  }

  @MainActor
  private func buildCmdHandler(forKey normalizedMpvKey: String,
                               fallbackAction: @escaping (PlayerCore, MPRemoteCommandEvent) -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    { [self] event in
      guard let player = lastActivePlayer else { return .commandFailed }
      player.pwc.executeActionForKey(normalizedMpvKey: normalizedMpvKey, fallbackAction: { player in fallbackAction(player, event) })
      MediaPlayerIntegration.updateCommandEnablements(for: player)
      return .success
    }
  }

  private func buildCmdHandler(_ commandFunc: @escaping (PlayerCore, MPRemoteCommandEvent) -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    { [self] event in
      guard let player = lastActivePlayer else { return .commandFailed }
      commandFunc(player, event)
      MediaPlayerIntegration.updateCommandEnablements(for: player)
      return .success
    }
  }

  /// Returns the value to use for the [preferredIntervals](https://developer.apple.com/documentation/mediaplayer/mpskipintervalcommand/preferredintervals) property.
  ///
  /// The [MPRemoteCommandCenter](https://developer.apple.com/documentation/MediaPlayer/MPRemoteCommandCenter)
  /// expects the media keys tied to the  [seekBackwardCommand](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter/seekbackwardcommand) and the [seekForwardCommand](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter/seekforwardcommand) to seek backward and
  /// forward in the current media track. The
  /// [MPSkipIntervalCommand](https://developer.apple.com/documentation/mediaplayer/mpskipintervalcommand)
  /// property [preferredIntervals](https://developer.apple.com/documentation/mediaplayer/mpskipintervalcommand/preferredintervals) provides the number of
  /// seconds pressing the key will skip.
  ///
  /// IINA allows the user to bind a mpv command to the `FORWARD` and `REWIND` media keys. This method must:
  /// - Determine if there is a key binding for the given key and if not return the default of 15 seconds
  /// - Determine if the key is bound to an IINA command and if so return an empty array indicating the property is not applicable
  /// - Determine if the key is bound to the mpv
  ///     [seek](https://mpv.io/manual/stable/#command-interface-seek-%3Ctarget%3E-[%3Cflags%3E]) command
  ///     and if not, return an empty array
  /// - Parse the `target` value of the `seek` command as an integer, if it cannot be parsed log an error and  return an empty array
  /// - If present, parse the `seek` command flags and if any flags other than `exact`, `keyframes` and `relative` are
  ///     present then return an empty array as this is not a normal seek
  /// - When all the above checks pass the key has been bound to a normal seek command and the absolute value of the seek
  ///     command target parameter can be used as the interval
  ///
  /// To see the `preferredIntervals` value open
  /// [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// and double click on the Now Playing module with IINA playing media. The expanded Now Playing module will contain seek
  /// backward and seek forward buttons. The interval may be shown inside the button icons.
  /// - Parameter key: Media key the value is for.
  /// - Returns: Value to use for` preferredIntervals`.
  private func formPreferredIntervalsValue(_ key: String) -> Double {
    let seconds: Double
    if let player = lastActivePlayer, let keyBinding = player.keyBindingContext.matchActiveKeyBinding(endingWith: "GO_FORWARD"),
       let action = keyBinding.action, action.count >= 2, action[0] == MPVCommand.seek.rawValue,
       let targetSeekTime = Double(action[1]) {
          seconds = abs(targetSeekTime)
    } else {
      seconds = 15
    }
    // The seek command target may be negative to indicate seeking backwards, however the remote
    // command dictates the direction and requires that the interval to be positive.
    Logger.log.trace("Seek interval for key \(key) is \(seconds) s")
    return seconds
  }


  @MainActor
  private func attachRemoteCommands() {
    Logger.log.trace("Attaching MediaPlayer remote commands")
    let remoteCommand = MPRemoteCommandCenter.shared()
    remoteCommand.playCommand.addTarget(handler: buildCmdHandler(forKey: "PLAYONLY", fallbackAction: { p, _ in p.resume() }))
    remoteCommand.pauseCommand.addTarget(handler: buildCmdHandler(forKey: "PAUSEONLY", fallbackAction: { p, _ in p.pause() }))
    remoteCommand.togglePlayPauseCommand.addTarget(handler: buildCmdHandler(forKey: "PLAYPAUSE", fallbackAction: { p, _ in p.togglePause() }))
    remoteCommand.stopCommand.addTarget(handler: buildCmdHandler(forKey: "STOP", fallbackAction: { p, _ in p.stop() }))
    remoteCommand.nextTrackCommand.addTarget(handler: buildCmdHandler(forKey: "NEXT", fallbackAction: { p, _ in p.navigateInPlaylist(nextMedia: true) }))
    remoteCommand.previousTrackCommand.addTarget(handler: buildCmdHandler(forKey: "PREV", fallbackAction: { p, _ in p.navigateInPlaylist(nextMedia: false) }))
    remoteCommand.changeRepeatModeCommand.addTarget(handler: buildCmdHandler{ player, _ in player.nextLoopMode() })
    remoteCommand.changeShuffleModeCommand.isEnabled = false
    // remoteCommand.changeShuffleModeCommand.addTarget {})
    remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
    remoteCommand.changePlaybackRateCommand.addTarget(handler: buildCmdHandler{ player, event in
      player.setSpeed(Double((event as! MPChangePlaybackRateCommandEvent).playbackRate))
    })

    let seekForwardInterval = formPreferredIntervalsValue("FORWARD")
    remoteCommand.skipForwardCommand.preferredIntervals = [NSNumber(value: seekForwardInterval)]
    remoteCommand.skipForwardCommand.addTarget(handler: buildCmdHandler(forKey: "FORWARD", fallbackAction: { player, event in
      player.seek(relativeSecond: Double(seekForwardInterval), option: .defaultValue)
    }))
    let seekBackwardInterval = formPreferredIntervalsValue("REWIND")
    remoteCommand.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekBackwardInterval)]
    remoteCommand.skipBackwardCommand.addTarget(handler: buildCmdHandler(forKey: "REWIND", fallbackAction: { player, event in
      player.seek(relativeSecond: -seekBackwardInterval, option: .defaultValue)
    }))
    remoteCommand.changePlaybackPositionCommand.addTarget(handler: buildCmdHandler{ player, event in
      player.seek(absoluteSecond: (event as! MPChangePlaybackPositionCommandEvent).positionTime)
    })
  }

  private func detachAllCommands() {
    Logger.log.trace("Detaching MediaPlayer remote commands")
    let remoteCommand = MPRemoteCommandCenter.shared()
    remoteCommand.playCommand.removeTarget(nil)
    remoteCommand.pauseCommand.removeTarget(nil)
    remoteCommand.togglePlayPauseCommand.removeTarget(nil)
    remoteCommand.stopCommand.removeTarget(nil)
    remoteCommand.nextTrackCommand.removeTarget(nil)
    remoteCommand.previousTrackCommand.removeTarget(nil)
    remoteCommand.changeRepeatModeCommand.removeTarget(nil)
//    remoteCommand.changeShuffleModeCommand.removeTarget(nil)
    remoteCommand.changePlaybackRateCommand.removeTarget(nil)
    remoteCommand.skipForwardCommand.removeTarget(nil)
    remoteCommand.skipBackwardCommand.removeTarget(nil)
    remoteCommand.changePlaybackPositionCommand.removeTarget(nil)
  }


  /// Update the information shown by macOS in `Now Playing`.
  ///
  /// The macOS [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// contains a `Now Playing` module. This module can also be configured to be directly accessible from the menu bar.
  /// `Now Playing` displays the title of the media currently  playing and other information about the state of playback. It also can be
  /// used to control playback. IINA is fully integrated with the macOS `Now Playing` module.
  ///
  /// - Note: See [Becoming a Now Playable App](https://developer.apple.com/documentation/mediaplayer/becoming_a_now_playable_app)
  ///         and [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
  ///         for more information.
  ///
  /// This method must be run on the main thread because it references `PlayerManager.shared.lastActivePlayer`.
  @MainActor
  private func updateNowPlayingInfo() {
    let center = MPNowPlayingInfoCenter.default()
    let info = center.nowPlayingInfo ?? [String: Any]()

    guard let activePlayer = PlayerManager.shared.lastActivePlayer else {
      center.playbackState = .unknown
      center.nowPlayingInfo = nil
      updateEnablement(to: false)
      return
    }

    self.lastActivePlayer = activePlayer
    activePlayer.updateNowPlayingInfo(from: info)
  }

  fileprivate static func updateCommandEnablements(for player: PlayerCore) {
    player.mpv.queue.async {
      let canSkipBackward = player.canSkipBackward
      let canSkipForward = player.canSkipForward
      let canPlayPrevTrack = player.canPlayPrevTrack
      let canPlayNextTrack = player.canPlayNextTrack
      DispatchQueue.main.async {
        let remoteCommand = MPRemoteCommandCenter.shared()
        remoteCommand.skipBackwardCommand.isEnabled = canSkipBackward
        remoteCommand.skipForwardCommand.isEnabled = canSkipForward
        remoteCommand.previousTrackCommand.isEnabled = canPlayPrevTrack
        remoteCommand.nextTrackCommand.isEnabled = canPlayNextTrack
      }
    }
  }
}

extension PlayerCore {
  fileprivate func updateNowPlayingInfo(from existingInfo: [String: Any]) {
    var nowPlayingInfo = existingInfo
    mpv.queue.async { [self] in
      guard !isStopping else { return }

      if info.currentMediaAudioStatus.isAudio {
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        let (title, album, artist) = getMusicMetadata()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
      } else {
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        nowPlayingInfo[MPMediaItemPropertyTitle] = getMediaTitle(withExtension: false)
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = ""
        nowPlayingInfo[MPMediaItemPropertyArtist] = ""
      }

      let positionSec = info.playbackTime.positionSec
      let isVideoTrackSelected = info.isVideoTrackSelected

      DispatchQueue.main.async { [self] in
        let artwork: MPMediaItemArtwork?
        if isVideoTrackSelected, let currentMediaThumbnails, currentMediaThumbnails.thumbnails.count > 0 {
          artwork = MPMediaItemArtwork(boundsSize: pwc.geo.video.videoSizeCAR, requestHandler: { displaySize in
            // TODO: figure out a way to use screenshot-raw from mpv instead!
            // Use thumbnail if available
            if let positionSec,
               let thumbImg = currentMediaThumbnails.getThumbnail(forSecond: positionSec)?.image {
              // Crop to aspect ratio of requested size, rather than stretching/squeezing. Then resize
              let cropRect = thumbImg.size().getCropRect(withAspect: displaySize.aspect)
              if let previewImg = thumbImg.cropping(to: cropRect)?.resized(newWidth: displaySize.widthInt, newHeight: displaySize.heightInt).toNSImage() {
                return previewImg
              }
            }
            // Default album art
            return #imageLiteral(resourceName: "default-album-art").resized(newWidth: displaySize.widthInt, newHeight: displaySize.heightInt)
          })
        } else {
          artwork = nil
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork

        let duration = info.playbackTime.durationSec ?? 0
        let time = positionSec ?? 0
        let speed = info.playSpeed

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = speed
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = info.currentPlayback?.url

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nowPlayingInfo

        if info.isFileLoaded {
          center.playbackState = info.isPaused ? .paused : .playing
        } else {
          center.playbackState = .unknown
        }

        MediaPlayerIntegration.updateCommandEnablements(for: self)
      }
    }
  }
}
