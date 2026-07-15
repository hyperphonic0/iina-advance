//
//  PWinGeoSet.swift
//  iina
//
//  Created by Matt Svoboda on 2024/05/25.
//

import Foundation

/// Describes the current panel sizes & locations for all modes of a unique `PlayerWindow`.
struct GeometrySet: Sendable {
  /// The window geometry, whether in regular  or interactive mode.
  ///
  /// Full screen geometry is not stored in a `GeometrySet`, but is expected to be derived from the properties
  /// of `windowed`
  let windowed: PWinGeometry
  let musicMode: PWinGeometry
  let video: VideoGeometry

  init(windowed: PWinGeometry, musicMode: PWinGeometry, video: VideoGeometry) {
    self.windowed = windowed
    self.musicMode = musicMode
    self.video = video
  }

  /// Makes a copy of this `GeometrySet` but uses the given `windowed` geometry, and uses its `VideoGeometry`
  /// as the new current video settings.
  func clone(windowed windowedNew: PWinGeometry) -> GeometrySet {
    return GeometrySet(windowed: windowedNew, musicMode: musicMode, video: windowedNew.video)
  }

  /// Makes a copy of this `GeometrySet` but uses the given `musicMode` geometry, and uses its `VideoGeometry`
  /// as the new current video settings.
  func clone(musicMode musicModeNew: PWinGeometry) -> GeometrySet {
    return GeometrySet(windowed: windowed, musicMode: musicModeNew, video: musicModeNew.video)
  }

  /// Makes a copy of this `GeometrySet` but uses the given `VideoGeometry`.
  /// Note: the `PWinGeometry` and `MusicModeGeometry` will contain the old `VideoGeometry`.
  func clone(video videoNew: VideoGeometry) -> GeometrySet {
    return GeometrySet(windowed: windowed, musicMode: musicMode, video: videoNew)
  }

  /// For use when restoring a saved launch. Looks for inconsistencies in `priorState.geoSet` (actually just its `.windowed` property
  /// so far), and tries to fix what it finds. May also make changes to `initialLayout` if needed - returns these in the result.
  @MainActor
  func fixingErrorsInSavedGeoSet(_ log: any Logger.Subsystem,
                                 initialLayout: LayoutState,
                                 modeToRestore: PlayerWindowMode) -> (GeometrySet, LayoutState) {

    var adjustedLayout = initialLayout
    let adjustedGeoSet: GeometrySet
    switch modeToRestore {

    case .windowedNormal, .windowedInteractive:
      let savedWindowedGeo = self.windowed
      if !savedWindowedGeo.mode.isWindowed || savedWindowedGeo.screenFit.isFullScreen {
        log.error("Initial layout: windowedModeGeo from prior state has invalid mode (\(savedWindowedGeo.mode)) or screenFit (\(savedWindowedGeo.screenFit)). Will generate a fresh windowedModeGeo from saved layoutState and last closed window instead")

        let lastClosedGeo = PlayerWindowController.windowedModeGeoLastClosed
        let windowed: PWinGeometry
        if lastClosedGeo.mode.isWindowed && !lastClosedGeo.screenFit.isFullScreen {
          windowed = initialLayout.convertWindowedModeGeometry(from: lastClosedGeo, video: self.video,
                                                               pinWidthOrHeightIfAtMax: false, log)
        } else {
          let bestScreen = NSScreen.forScreenID(lastClosedGeo.screenID) ?? NSScreen.main ?? NSScreen.screens.first!
          windowed = initialLayout.buildDefaultInitialGeometry(screen: bestScreen, video: self.video)
        }
        adjustedGeoSet = self.clone(windowed: windowed)

      } else if savedWindowedGeo.outsideBars.totalWidth + savedWindowedGeo.insideBars.totalWidth > savedWindowedGeo.windowFrame.width {
        log.error("Initial layout: windowedModeGeo from prior state has window size (\(savedWindowedGeo.windowFrame.size)) which is too small to accomodate bars (outside=\(savedWindowedGeo.outsideBars), inside=\(savedWindowedGeo.insideBars)). Will close sidebars.")

        /// Overwrite `outputLayout` with fixed version
        adjustedLayout = initialLayout.withSidebarsHidden()
        let outsideNew = savedWindowedGeo.outsideBars.clone(trailing: 0, leading: 0)
        let insideNew = savedWindowedGeo.insideBars.clone(trailing: 0, leading: 0)
        let windowed = savedWindowedGeo.clone(outsideBars: outsideNew, insideBars: insideNew)

        adjustedGeoSet = self.clone(windowed: windowed)
      } else {
        // Valid (as far as we've checked anyway)
        adjustedGeoSet = self
      }

    case .musicMode,
        .fullScreenNormal, .fullScreenInteractive:
      // No validation at present
      adjustedGeoSet = self
    }

    return (adjustedGeoSet, adjustedLayout)
  }

}

extension PlayerWindowController {
  @MainActor
  func getLatestWindowFrameAndScreenID(force: Bool = false) -> (NSRect, String)? {
    guard let window else { return nil }
    if !force {
      // Need to check state of current playback to avoid race conditions
      guard loaded, player.info.isFileLoaded, window.isOpen else {
        log.trace("Will use cached windowFrame/screenID instead of latest: playerActive=\(player.isActive) fileLoaded=\(player.info.isFileLoaded) wndOpen=\(window.isOpen.yn)")
        return nil
      }
      guard !sessionState.isRestoring else {
        log.verbose("Still restoring; will use cached window frame & screenID instead of latest")
        return nil
      }
    }
    return (window.frame, bestScreen.screenID)
  }

  /// Builds a new `GeometrySet` using this one as a base.
  /// 1. For each of the 3 components (`windowed`, `musicMode`, & `video`: if a non-nil object is specified in the params,
  /// it will be used in the new `GeometrySet` without being modified.
  /// 2. For each of `windowed` & `musicMode`: if an object is not specified in the params (see 1), an updated object will be built
  /// using the updated `video` param (if given), and possibly using the latest windowFrame. (See code below for more details, bleh).
  @MainActor
  func buildGeoSet(windowed: PWinGeometry? = nil, musicMode: PWinGeometry? = nil,
                   video: VideoGeometry? = nil, layoutMode: PlayerWindowMode? = nil,
                   baseGeoSet: GeometrySet? = nil, forceWinFrameUpdate: Bool = false) -> GeometrySet {
    let mode: PlayerWindowMode
    if let layoutMode {
      guard layoutMode == currentLayout.mode else {
        log.warn("Mode has changed (current=\(currentLayout.mode), provided=\(layoutMode)): will reuse existing GeometrySet instead of updating")
        return geo
      }
      mode = layoutMode
    } else {
      mode = currentLayout.mode
    }

    let geo = baseGeoSet ?? geo

    // need to make sure latest video gets propogated to *both* windowed and musicMode geos
    let videoNew = video ?? geo.video

    let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID(force: forceWinFrameUpdate) ?? (nil, nil)

    let windowedNew: PWinGeometry
    let musicModeNew: PWinGeometry

    // Windowed, full screen
    if let windowed {
      windowedNew = windowed
    } else if mode.isWindowed {
      if geo.windowed.mode != mode {
        // If this message is seen, could be a corrupted pref key, or a code bug
        log.error("buildGeoSet: geo.windowed.mode (\(geo.windowed.mode)) != layout.mode (\(mode))! Will change geo mode to match the latter; hope it doesn't break anything...")
      }
      windowedNew = geo.windowed.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, mode: layoutMode, video: videoNew)

    } else if mode.isFullScreen {
      // may have changed screen while in FS
      windowedNew = geo.windowed.clone(screenID: latestScreenID, video: videoNew)
    } else {
      windowedNew = geo.windowed
    }

    // Music mode
    if let musicMode {
      musicModeNew = musicMode
    } else if mode == .musicMode {
      musicModeNew = geo.musicMode.cloneMusicMode(windowFrame: latestWindowFrame, screenID: latestScreenID, video: videoNew)
    } else {
      musicModeNew = geo.musicMode
    }

    return GeometrySet(windowed: windowedNew, musicMode: musicModeNew, video: videoNew)
  }

  /// If `force=true`, then skip validation checks for latest frame & always use current frame
  @MainActor
  func windowedGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil, force: Bool = false) -> PWinGeometry {
    let geo = geo
    if currentLayout.mode.isWindowed, let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID(force: force) {
      log.trace("Cloning windowed geometry with current windowFrame=\(latestWindowFrame), screenID=\(latestScreenID.quoted)")
      // If user moved the window recently, window frame might not be completely up to date. Update it & return:
      return geo.windowed.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, video: newVidGeo)
    }
    // Doesn't make sense to update window if currently in FS or some other mode. But update video
    log.trace("Cloning windowed geometry, updating only videoGeo=\(newVidGeo?.description ?? "nil")")
    return geo.windowed.clone(video: newVidGeo)
  }


  /// See also `windowedGeoForCurrentFrame`
  @MainActor
  func musicModeGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil, force: Bool = false) -> PWinGeometry {
    let geo = geo
    if currentLayout.mode == .musicMode, let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID(force: force) {
      log.trace("Cloning musicMode geometry with current windowFrame=\(latestWindowFrame) screenID=\(latestScreenID.quoted)")
      return geo.musicMode.cloneMusicMode(windowFrame: latestWindowFrame, screenID: latestScreenID, video: newVidGeo)
    }
    return geo.musicMode.cloneMusicMode(video: newVidGeo)
  }

  func fullScreenGeo() -> PWinGeometry {
    return currentLayout.buildFullScreenGeometry(in: bestScreen, geo.video)
  }
}
