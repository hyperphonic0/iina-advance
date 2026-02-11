//
//  PWin_Observers.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-27.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// `NotificationCenter` & `UserDefaults` observers for the player window. See also: `NotificationHandler`
extension PlayerWindowController {

  func buildObservers() -> NotificationHandler {
    let window = window!

    let observedPrefKeys: [Preference.Key] = [
      .enableAdvancedSettings,
      .mpvEventLogLevel,
      .enableToneMapping,
      .toneMappingTargetPeak,
      .loadIccProfile,
      .toneMappingAlgorithm,
      .keepOpenOnFileEnd,
      .useForceTouchForSpeedArrows,
      .playlistAutoPlayNext,
      .themeMaterial,
      .playerWindowOpacity,
      .maxVolume,
      .useMpvOsd,

      .showCachedRangesInSlider,
      .roundSliderBarRects,
      .sliderBarDoneColor,
      .alwaysShowSliderKnob,
      .showChapterPos,

        .seekPreviewShadow,
      .integrateWithThumbfast,
      .playlistShowMetadata,
      .playlistShowMetadataInMusicMode,
      .shortenFileGroupsInPlaylist,
      .autoSwitchToMusicMode,
      .hideWindowsWhenInactive,
      .enableControlBarAutoHide,
      .controlBarAutoHideTimeout,
      .osdAutoHideTimeout,
      .osdTextSize,
      .enableOSC,
      .oscForceSingleRow,
      .oscPosition,
      .oscColorScheme,
      .showRemainingTime,
      .oscTimeLabelsAlwaysWrapSlider,
      .topBarPlacement,
      .bottomBarPlacement,
      .oscBarHeight,
      .oscBarPlayIconSize,
      .oscBarPlayIconSpacing,
      .controlBarToolbarButtons,
      .oscBarToolIconSize,
      .oscBarToolIconSpacing,
      .floatingControlBarWidth,

      .enableThumbnailPreview,
      .enableThumbnailForRemoteFiles,
      .enableThumbnailForMusicMode,
      .thumbnailSizeOption,
      .thumbnailFixedLength,
      .thumbnailRawSizePercentage,
      .thumbnailDisplayedSizePercentage,
      .thumbnailBorderStyle,

      .arrowButtonAction,
      .blackOutMonitor,
      .useLegacyFullScreen,
      .enableOSD,
      .osdPosition,
      .displayTimeAndBatteryInFullScreen,
      .alwaysShowOnTopIcon,
      .alwaysFloatOnTop,
      .keepVideoAwayFromBars,
      .leadingSidebarPlacement,
      .trailingSidebarPlacement,
      .settingsTabGroupLocation,
      .playlistTabGroupLocation,
      .pluginsTabGroupLocation,
      .aspectRatioPanelPresets,
      .cropPanelPresets,
      .showLeadingSidebarToggleButton,
      .showTrailingSidebarToggleButton,
      .useLegacyWindowedMode,
      .lockViewportToVideoSize,
      .allowVideoToOverlapCameraHousing,
      .enablePinchToVideoZoom,
    ]

    let ncList: [NotificationCenter: [NotificationHandler.NCObserver]]
    ncList = [
      .default: [
        .init(NSScreen.colorSpaceDidChangeNotification) { note in self.colorSpaceDidChange(note) },
        .init(NSWindow.didChangeScreenNotification) { note in self.windowDidChangeScreen(note) },
        .init(.iinaMediaTitleChanged, object: player) { _ in self.updateTitle() },
        .init(.iinaActiveInputConfFileDidUpdate) { [self] _ in
          player.needsInputConfFileReload = true
        },
        /* Not currently used. Leave for testing purposes only.
        .init(NSWindow.didChangeScreenProfileNotification) { note in self.windowDidChangeScreenProfile(note) },
        .init(NSWindow.didChangeBackingPropertiesNotification) { note in self.windowDidChangeBackingProperties(note) },
         */
        .init(NSApplication.didChangeScreenParametersNotification) { _ in self.windowDidChangeScreenParameters() },

        // Play Slider loop knobs:
        .init(.iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [self] _ in
          let seconds = player.info.playbackTime.percentToSeconds(playSlider.abLoopA.posInSliderPercent)
          player.info.abLoopA = seconds
          player.abLoopA = seconds
          player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
        },
        .init(.iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [self] _ in
          let seconds = player.info.playbackTime.percentToSeconds(playSlider.abLoopB.posInSliderPercent)
          player.info.abLoopB = seconds
          player.abLoopB = seconds
          player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
        },

        .init(NSWorkspace.willSleepNotification) { [self] _ in
          guard Preference.bool(for: .pauseWhenGoesToSleep) else { return }
          player.pause()
        }
      ],

      NSWorkspace.shared.notificationCenter: [
        .init(NSWorkspace.activeSpaceDidChangeNotification) { [self] _ in
          // FIXME: this is not ready for production yet! Need to fix issues with freezing video
          guard Preference.bool(for: .togglePipWhenSwitchingSpaces) else { return }
          if !window.isOnActiveSpace {
            animationPipeline.submitInstantTask({ [self] in
              guard !currentLayout.isInPiP else { return }
              log.debug("Window is no longer in active space; entering PIP")
              enterPIP(then: { [self] in
                isWindowPipDueToInactiveSpace = true
              })
            })
          } else if window.isOnActiveSpace && isWindowPipDueToInactiveSpace {
            animationPipeline.submitInstantTask({ [self] in
              guard currentLayout.isInPiP else { return }
              log.debug("Window is in active space again; exiting PIP")
              isWindowPipDueToInactiveSpace = false
              exitPIP()
            })
          }
        }
      ],

      DistributedNotificationCenter.default(): [
        .init(.appleColorPreferencesChangedNotification) { [self] _ in
          player.log.verbose("Detected change to user accent color pref: reloading colors")
          if playlistView.isViewLoaded {
            playlistView.updateTableColors()
          }
          // Need to regenerate colors in BarFactory & redraw slider:
          updateTitleBarAndOSC()
        }
      ]
    ]

    return NotificationHandler(player.log, prefDidChange: prefDidChange, observedPrefKeys, ncList)
  }

  func addAllObservers() {
    notiHandler.addAllObservers()
    addObserver(self, forKeyPath: #keyPath(window.effectiveAppearance), options: [.old, .new], context: nil)
    log.verbose("Done adding all observers")
  }

  func removeAllObservers() {
    notiHandler.removeAllObservers()
    ObjcUtils.silenced { [self] in
      removeObserver(self, forKeyPath: #keyPath(window.effectiveAppearance))
    }
    log.verbose("Done removing all observers")
  }

  /// Called each time a pref `key`'s value is set
  func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    guard isOpen else { return }  // do not want to respond to some things like blackOutOtherMonitors while closed!
    
    guard !player.isDemoPlayer else { return }

    switch key {
    case .enableAdvancedSettings:
      player.mpv.updateLoggingLevels()
      player.mpv.updateUsingMpvOSDFromPrefs()

      animationPipeline.submitInstantTask({ [self] in
        // May change enablement of 2-row OSC; refresh:
        updateTitleBarAndOSC()
        updateWindowBorderAndOpacity()
        // may need to hide cropbox label and other advanced stuff
        player.setQuickSettingsViewNeedsUpdate()
        seekPreview.refreshThumbfastFromPrefs()
      })
    case .mpvEventLogLevel:
      player.mpv.updateLoggingLevels()
    case .integrateWithThumbfast:
      seekPreview.refreshThumbfastFromPrefs()
    case .useMpvOsd:
      player.mpv.updateUsingMpvOSDFromPrefs()
    case .enableToneMapping,
        .toneMappingTargetPeak,
        .loadIccProfile,
        .toneMappingAlgorithm:
      player.refreshEdrMode()
    case .themeMaterial:
      animationPipeline.submitInstantTask { [self] in
        if let window, let screen = window.screen {
          applyThemeMaterial(window, screen)
        } else {
          log.debug("Could not apply theme change: no window or screen!")
        }
      }
    case .playerWindowOpacity:
      animationPipeline.submitInstantTask({ [self] in
        updateWindowBorderAndOpacity()
      })
    case .showCachedRangesInSlider:
      if let isEnabled = newValue as? Bool, !isEnabled {
        player.info.cacheState = player.info.cacheState.clone(cachedRanges: [])
        if let osc = currentControlBar, !osc.isHidden {
          playSlider.needsDisplay = true
        }
      }
    case .maxVolume:
      if let newValue = newValue as? Int {
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        } else {
          updateVolumeUI()
        }
      }
    case .seekPreviewShadow:
      seekPreview.updateStyle()
    case .playlistShowMetadata, .playlistShowMetadataInMusicMode, .shortenFileGroupsInPlaylist:
      // Reload now, even if not visible. Don't nitpick.
      playlistView.playlistTableView.reloadData()
    case .autoSwitchToMusicMode:
      // Reset this to disable manual override if it's in place
      player.overrideAutoMusicMode = false

    case .keepOpenOnFileEnd, .playlistAutoPlayNext:
      player.mpv.updateKeepOpenOptionFromPrefs()

    case .arrowButtonAction,
        .useForceTouchForSpeedArrows:
      updateArrowButtonAccelerationFromPrefs()
      updateTitleBarAndOSC()

    case .enableOSC,
        .oscPosition,
        .oscColorScheme,
        .oscForceSingleRow,
        .topBarPlacement,
        .bottomBarPlacement,
        .oscBarHeight,
        .oscBarPlayIconSize,
        .oscBarPlayIconSpacing,
        .oscBarToolIconSize,
        .oscBarToolIconSpacing,
        .showLeadingSidebarToggleButton,
        .showTrailingSidebarToggleButton,
        .controlBarToolbarButtons,
        .allowVideoToOverlapCameraHousing,
        .useLegacyWindowedMode,
        .showRemainingTime,
        .oscTimeLabelsAlwaysWrapSlider,
        .keepVideoAwayFromBars,
      // These need calls to regenerate BarFactory:
        .roundSliderBarRects,
        .sliderBarDoneColor:

      log.verbose("Calling updateTitleBarAndOSC in response to pref change: \(key.rawValue.quoted) = \(String(describing: newValue))")
      updateTitleBarAndOSC()
    case .floatingControlBarWidth:
      controlBarFloating.updatePreferredBarWidth()
    case .alwaysShowSliderKnob:
      playSlider.needsDisplay = true
      volumeSlider.needsDisplay = true
    case .controlBarAutoHideTimeout:
      fadeableViews.hideTimer.restart()
    case .lockViewportToVideoSize:
      animationPipeline.submitInstantTask { [self] in
        if let isLocked = newValue as? Bool, isLocked {
          log.debug("Pref \(key.rawValue.quoted) changed to \(isLocked): resizing viewport to remove any excess space")
          var tasks = buildResizeViewportTasks()

          tasks.append(.instantTask { [self] in  // do after resize tasks
            player.updateMpvKeepaspectWindowSynchronously()
          })

          animationPipeline.submit(tasks)
        } else {
          // No need for animation
          player.updateMpvKeepaspectWindowSynchronously()
        }
      }
    case .enablePinchToVideoZoom:
      if let enabled = newValue as? Bool, !enabled {
        log.debug("Pref \(key.rawValue.quoted) changed to \(enabled): will reset any active zoom from pinch")
        magnificationHandler.resetZoom()
      }
    case .hideWindowsWhenInactive:
      animationPipeline.submitInstantTask({ [self] in
        refreshHidesOnDeactivateStatus()
      })
    case .thumbnailBorderStyle:
      player.info.currentPlayback?.thumbnails?.invalidateDisplayedThumbnail()

    case .thumbnailSizeOption,
        .thumbnailFixedLength,
        .thumbnailRawSizePercentage,
        .enableThumbnailPreview,
        .enableThumbnailForRemoteFiles,
        .enableThumbnailForMusicMode:

      log.verbose("Pref \(key.rawValue.quoted) changed: requesting thumbs regen")
      // May need to remove thumbs or generate new ones: let method below figure it out:
      player.reloadThumbnails()

    case .showChapterPos:
      if let newValue = newValue as? Bool {
        playSlider.customCell.drawChapters = newValue
      }
    case .blackOutMonitor:
      if let newValue = newValue as? Bool {
        if isFullScreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindows()
        }
      }
    case .useLegacyFullScreen:
      updateUseLegacyFullScreen()
    case .alwaysShowOnTopIcon,
        .alwaysFloatOnTop:
      guard loaded else { return }
      if Preference.bool(for: .alwaysFloatOnTop) {
        let playing = player.info.isPlaying
        setWindowFloatingOnTop(playing, from: currentLayout)
      } else {
        updateOnTopButton(from: currentLayout)
      }
    case .leadingSidebarPlacement, .trailingSidebarPlacement:
      updateSidebarPlacements()
    case .settingsTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.settings, toSidebarLocation: newLocationID)
      }
    case .playlistTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.playlist, toSidebarLocation: newLocationID)
      }
    case .pluginsTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.plugins, toSidebarLocation: newLocationID)
      }
    case .osdAutoHideTimeout, .enableControlBarAutoHide:
      if osd.animationState == .shown, osd.hideOSDTimer.isValid {
        // Reschedule timer to prevent prev long timeout from lingering
        osd.hideOSDTimer.restart(withNewTimeout: OSDState.osdTimeoutFromPrefs())
      }
    case .enableOSD:
      if !Preference.bool(for: .enableOSD) {
        if osd.hideOSDTimer.isValid {
          // Do not wait for OSD timeout. Hide now.
          // But make sure to only do this if the current OSD has a timeout!
          // Do not want to dismiss "always enabled" OSDs.
          // Need to improve OSD state management design...
          hideOSD()
        }
      }
      updateTitleBarAndOSC()
    case .osdPosition, .displayTimeAndBatteryInFullScreen:
      updateTitleBarAndOSC()
    case .osdTextSize:
      animationPipeline.submitInstantTask { [self] in
        updateOSDViews()
      }
    case .aspectRatioPanelPresets, .cropPanelPresets:
      let videoGeo = player.videoGeo
      quickSettingView.updateSegmentLabelsForVideoTab(using: videoGeo)
    default:
      return
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case #keyPath(window.effectiveAppearance):
      /// This indicates light/dark mode was toggled. But this won't be sent when `controlAccentColor` changes...
      /// For that, we follow `appleColorPreferencesChangedNotification`
      guard let window else { return }
      let effectiveAppearanceName = window.effectiveAppearance.name.rawValue
      guard cachedEffectiveAppearanceName != effectiveAppearanceName else { return }
      log.verbose("Window appearance changed to: \(effectiveAppearanceName)")
      cachedEffectiveAppearanceName = effectiveAppearanceName

      animationPipeline.submitInstantTask { [self] in
        if let screen = window.screen {
          applyThemeMaterial(window, screen)
        } else {
          log.debug("Could not apply appearance change: no screen!")
        }
      }
    default:
      return
    }
  }

}
