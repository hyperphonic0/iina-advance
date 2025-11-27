//
//  PWin_LayoutTxBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 8/20/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// This file is not really a factory class due to limitations of the AppKit paradigm, but it contain
/// methods for creating/running `LayoutTransition`s to change between `LayoutState`s for the
/// given `PlayerWindowController`.
extension PlayerWindowController {

  // MARK: - Building LayoutTransition

  /// First builds a new `LayoutState` based on the given `LayoutState`, then builds & returns a `LayoutTransition`,
  /// which contains all the information needed to animate the UI changes from the current `LayoutState` to the new one.
  @discardableResult
  func buildLayoutTransition(named transitionName: String,
                             from inputLayout: LayoutState,
                             to outputLayout: LayoutState, outputGeo outputGeoExplicit: PWinGeometry? = nil,
                             isWindowInitialLayout: Bool = false,
                             _ geoSet: GeometrySet? = nil) -> LayoutTransition {

    var transitionID: Int = 0
    $layoutTransitionCounter.withLock {
      $0 += 1
      transitionID = $0
    }
    let transitionName = "#\(transitionID) \(transitionName)"

    // - Geometries Setup

    // use latest window frame in case it exists and was moved
    let inputGeoSet = geoSet ?? self.buildGeoSet(layoutMode: inputLayout.mode)

    // This also applies to full screen, because full screen always uses the same screen as windowed.
    // Does not apply to music mode, which can be a different screen.
    let windowedModeScreen = NSScreen.getScreenOrDefault(screenID: inputGeoSet.windowed.screenID)

    // InputGeometry
    let inputGeometry = buildInputGeometry(from: inputLayout, transitionName: transitionName,
                                           inputGeoSet, windowedModeScreen: windowedModeScreen)

    // OutputGeometry
    let outputGeometry = outputGeoExplicit ?? buildOutputGeometry(inputLayout: inputLayout, inputGeometry: inputGeometry,
                                                                  outputLayout: outputLayout, inputGeoSet,
                                                                  isWindowInitialLayout: isWindowInitialLayout)

    let protoTransition = LayoutTransition(name: transitionName,
                                           from: inputLayout, from: inputGeometry,
                                           to: outputLayout, to: outputGeometry,
                                           windowedModeScreen: windowedModeScreen,
                                           isWindowInitialLayout: isWindowInitialLayout)

    let closeOldPanelsGeometry = protoTransition.buildCloseOldPanelsGeometry()

    let moveAndScaleGeometry: PWinGeometry?
    if protoTransition.needsMoveAndScaleVideoFrameStep {
      // FIXME: For Interactive Mode with very slim crop, this sometimes shows black pillars. Maybe set a minimum zoom?
      // Need to have mode which is not music mode
      moveAndScaleGeometry = outputGeometry.clone(windowFrame: outputGeometry.videoFrameInScreenCoords,
                                                  mode: .windowedNormal,
                                                  topMarginHeight: 0,
                                                  outsideBars: .zero, insideBars: .zero,
                                                  viewportMargins: .zero)
    } else {
      moveAndScaleGeometry = nil
    }

    let transition = LayoutTransition(name: transitionName,
                                      from: inputLayout, from: inputGeometry,
                                      to: outputLayout, to: outputGeometry,
                                      closeOldPanelsGeometry: closeOldPanelsGeometry,
                                      moveAndScaleGeometry: moveAndScaleGeometry,
                                      windowedModeScreen: windowedModeScreen,
                                      isWindowInitialLayout: isWindowInitialLayout)


    log.verbose("[\(transitionName)] INPUT_GEO:  \(inputGeometry)")
    log.verbose("[\(transitionName)] CLOSE_OLD:  \(transition.closeOldPanelsGeometry?.description ?? "nil")")
    log.verbose("[\(transitionName)] MOVE_SCALE: \(transition.moveAndScaleGeometry?.description ?? "nil")")
    log.verbose("[\(transitionName)] OUTPUT_GEO\(outputGeoExplicit == nil ? "" : "(given)"): \(outputGeometry)")

    return transition
  }

  @discardableResult
  func buildTasks(for transition: LayoutTransition,
                  totalStartingDuration: CGFloat? = nil,
                  totalEndingDuration: CGFloat? = nil,
                  thenRun: Bool = false) -> [IINAAnimation.Task] {

    let needsCloseOldPanelsStep = transition.needsCloseOldPanelsStep
    // - Timings Setup

    let closeOldPanelsTiming: CAMediaTimingFunctionName
    let openFinalPanelsTiming: CAMediaTimingFunctionName
    let fadeInNewViewsTiming: CAMediaTimingFunctionName = .linear
    if transition.isTogglingInteractiveMode {
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
    } else if transition.isTogglingMusicMode {
      // Try to reduce wobble when collapsing or expanding viewport. Need to do more research to prevent wobbling
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
    } else if transition.isEnteringFullScreen {
      closeOldPanelsTiming = .linear  // doesn't matter; not used
      openFinalPanelsTiming = .easeInEaseOut
    } else if transition.isExitingFullScreen {
      closeOldPanelsTiming = .linear  // doesn't matter; not used
      openFinalPanelsTiming = .easeInEaseOut
    } else if transition.isOpeningOrClosingAnySidebar {
      closeOldPanelsTiming = .easeInEaseOut
      openFinalPanelsTiming = .easeInEaseOut
    } else {
      closeOldPanelsTiming = .easeInEaseOut
      openFinalPanelsTiming = .easeInEaseOut
    }

    // - Durations Setup

    let startingAnimationDuration: CGFloat
    if transition.isWindowInitialLayout || !IINAAnimation.isAnimationEnabled {
      startingAnimationDuration = 0
    } else if transition.isEnteringFullScreen {
      startingAnimationDuration = 0
    } else if transition.isEnteringMusicMode && !transition.isExitingFullScreen {
      startingAnimationDuration = Constants.AnimationDuration.standard
    } else if let totalStartingDuration {
      startingAnimationDuration = totalStartingDuration / 3
    } else {
      startingAnimationDuration = Constants.AnimationDuration.standard
    }

    var showFadeableViewsDuration: CGFloat = startingAnimationDuration
    var fadeOutOldViewsDuration: CGFloat = startingAnimationDuration
    var closeOldPanelsDuration: CGFloat = startingAnimationDuration
    if transition.isEnteringMusicMode && !transition.isExitingFullScreen {
      showFadeableViewsDuration = startingAnimationDuration * 0.25
      fadeOutOldViewsDuration = startingAnimationDuration * 0.25
    } else if transition.isEnteringInteractiveMode {
      showFadeableViewsDuration = startingAnimationDuration * 0.25
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else if transition.isExitingInteractiveMode {
      showFadeableViewsDuration = 0
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else {
      if !transition.needsShowFadeablesAnimation {
        showFadeableViewsDuration = 0
      }
      if !transition.needsFadeOutOldViewsStep {
        fadeOutOldViewsDuration = 0
      }
    }

    if !needsCloseOldPanelsStep {
      closeOldPanelsDuration = 0
    }

    let endingAnimationDuration: CGFloat
    if transition.isWindowInitialLayout || !IINAAnimation.isAnimationEnabled {
      endingAnimationDuration = 0
    } else {
      endingAnimationDuration = totalEndingDuration ?? Constants.AnimationDuration.standard
    }

    let screenHasCameraHousing = transition.windowedModeScreen.hasCameraHousing

    // Extra animation when entering legacy full screen: cover camera housing with black bar
    let useExtraAnimationForEnteringLegacyFullScreen = IINAAnimation.isAnimationEnabled && transition.isEnteringLegacyFullScreen && screenHasCameraHousing && !transition.isWindowInitialLayout

    // Extra animation when exiting legacy full screen: remove camera housing with black bar
    let addClosePanelsStepForExitingLegacyFullScreen = IINAAnimation.isAnimationEnabled && transition.isExitingLegacyFullScreen && screenHasCameraHousing && !transition.isWindowInitialLayout

    let addClosePanelsStepForExitingNativeFullScreen = IINAAnimation.isAnimationEnabled && transition.isExitingNativeFullScreen && !transition.isWindowInitialLayout

    var fadeInNewViewsDuration = endingAnimationDuration * 0.5
    var openFinalPanelsDuration = endingAnimationDuration
    if addClosePanelsStepForExitingNativeFullScreen {
      closeOldPanelsDuration = endingAnimationDuration
      openFinalPanelsDuration = 0.0
    } else if addClosePanelsStepForExitingLegacyFullScreen {
      let cameraHeightToFrameHeightRatio = transition.windowedModeScreen.cameraHeightToFrameHeightRatio
      closeOldPanelsDuration *= cameraHeightToFrameHeightRatio
      let nonCameraHeightToFrameHeightRatio = transition.windowedModeScreen.nonCameraHeightToFrameHeightRatio
      openFinalPanelsDuration *= nonCameraHeightToFrameHeightRatio
      fadeInNewViewsDuration = 0
    } else if useExtraAnimationForEnteringLegacyFullScreen {
      let cameraHeightToFrameHeightRatio = transition.windowedModeScreen.cameraHeightToFrameHeightRatio
      openFinalPanelsDuration *= cameraHeightToFrameHeightRatio
      fadeInNewViewsDuration = 0
    } else if transition.isExitingFullScreen {
      fadeInNewViewsDuration = 0
    } else if transition.isEnteringInteractiveMode {
      openFinalPanelsDuration *= 0.5
      fadeInNewViewsDuration *= 0.5
    } else {
      if !transition.needsFadeInNewViewsStep {
        fadeInNewViewsDuration = 0
      }
      if !transition.needsAnimationForOpenFinalPanels {
        // Probably hiding a sidebar. We still need to execute the task, but will do it with no animation.
        openFinalPanelsDuration = 0
      }
    }

    log.verbose("[\(transition.name)] Task durations: ShowOldFadeables=\(showFadeableViewsDuration) FadeOutOldViews=\(fadeOutOldViewsDuration), CloseOldPanels=\(closeOldPanelsDuration) FadeInNewViews=\(fadeInNewViewsDuration) OpenFinalPanels=\(openFinalPanelsDuration)")

    var tasks: [IINAAnimation.Task] = []

    // - Starting animations:

    // Setup: Set initial var or other tasks which happen before main animations
    tasks.append(.instantTask{ [self] in
      doPreTransitionWork(transition)

      if transition.isTogglingFullScreen {
        fadeOutOldViews(transition)
      }
    })

    if transition.needsShowFadeablesAnimation {
      // StartingAnimation 1: Show fadeable views from current layout
      for fadeAnimation in buildAnimationToShowFadeableViews(targetLayout: transition.inputLayout,
                                                             restartFadeTimer: false, duration: showFadeableViewsDuration,
                                                             forceShow: true, forceShowTopBar: true) {
        tasks.append(fadeAnimation)
      }
    }

    // StartingAnimation 2: Fade out views which no longer will be shown but aren't enclosed in a panel.
    if transition.needsFadeOutOldViewsStep {
      tasks.append(.init(duration: fadeOutOldViewsDuration, { [self] in
        fadeOutOldViews(transition)
      }))
    }

    // (Only when animating Enter/Exit Music Mode or Enter/Exit Windowed Interactive Mode) Post-midpoint animation: move & scale video.
    var moveAndScaleTask: IINAAnimation.Task? = nil

    // StartingAnimation 3: Close/Minimize panels which are no longer needed. Applies closeOldPanelsGeometry if it exists.
    // Not enabled for full screen transitions or if animation is disabled.
    if needsCloseOldPanelsStep || addClosePanelsStepForExitingLegacyFullScreen {
      tasks.append(.init(duration: closeOldPanelsDuration, timing: closeOldPanelsTiming, { [self] in
        closeOldPanels(transition)
      }))
    }

    if transition.needsMoveAndScaleVideoFrameStep {
      let duration = transition.isTogglingInteractiveMode ? closeOldPanelsDuration * 0.5 : closeOldPanelsDuration
      moveAndScaleTask = .init(duration: duration, timing: .easeInEaseOut) { [self] in
        moveAndScaleVideoFrame(transition)
      }
    }

    // Place this task either before or after updateHiddenViewsAndConstraints depending on entering or exiting.
    // Want to put this *before* it when entering music mode & hiding (closing) viewportView, but other cases the order shouldn't matter.
    if let moveAndScaleTask, transition.isMoveAndScaleStepBeforeMidpoint {
      tasks.append(moveAndScaleTask)
    }

    // Midpoint: perform major constraints updates (any affected panels should have been reduced to 0 thickness by the previous
    // task, so these updates can be performed without visible changes. In general, this step should have almost no visible
    // changes.
    tasks.append(.instantTask{ [self] in
      updateHiddenViewsAndConstraints(transition)
    })

    if let moveAndScaleTask, !transition.isMoveAndScaleStepBeforeMidpoint {
      tasks.append(moveAndScaleTask)
    }

    // - Ending animations:

    // (Only for Enter Legacy FS) Extra animation for camera housing. In Big Sur, AppKit needed an extra transaction & more
    // time when animating around the camera housing, especially if also changing window `titled` style. This may no longer
    // be the case, but it's not harming anything to leave this as-is for now.
    if useExtraAnimationForEnteringLegacyFullScreen {
      let duration = endingAnimationDuration * transition.windowedModeScreen.nonCameraHeightToFrameHeightRatio
      if duration > 0.0 {
        tasks.append(.init(duration: duration, timing: .linear) { [self] in
          rebuildPanelConstraints(transition, stage: .extraAnimationBeforeOpenNewPanels)
          // Do this here to reduce chance of an animation jump
          updatePresentationOptions(windowIsFS: true)
        })
      }
    }

    // EndingAnimation 1: Open new panels
    tasks.append(.init(duration: openFinalPanelsDuration, timing: openFinalPanelsTiming, { [self] in
      // If toggling fullscreen, this also changes the window frame:
      openNewPanelsAndFinalizeOffsets(transition)
    }))

    // EndingAnimation 2: Fade in new views
    // If exiting FS, this task is skipped. It needs to run in a separate CATransaction so it is run down below.
    if transition.needsFadeInNewViewsStep {
      tasks.append(.init(duration: fadeInNewViewsDuration, timing: fadeInNewViewsTiming) { [self] in
        fadeInNewViews(transition)
      })
    }

    // Post: After animations all finish. Not animated.
    tasks.append(.instantTask{ [self] in
      if transition.isTogglingFullScreen {
        // For a better visual experience wait until window finishes moving
        fadeInNewViews(transition)
      }
      doPostTransitionWork(transition)
    })

    if thenRun {
      animationPipeline.submit(tasks)
    }
    return tasks
  }

  // MARK: - Geometry

  /// INPUT GEOMETRY
  private func buildInputGeometry(from inputLayout: LayoutState, transitionName: String, _ inputGeoSet: GeometrySet,
                                  windowedModeScreen: NSScreen) -> PWinGeometry {
    
    // Restore window size & position
    switch inputLayout.mode {
    case .windowedNormal:
      return inputGeoSet.windowed
    case .fullScreenNormal, .fullScreenInteractive:
      return inputLayout.buildFullScreenGeometry(in: windowedModeScreen, inputGeoSet.video)
    case .windowedInteractive:
      /// `.inputGeoSet.windowed` should already be correct for interactiveWindowed mode
      return inputGeoSet.windowed
    case .musicMode:
      /// When restoring, `musicModeGeo` should have already been deserialized and set.
      /// But make sure we correct any size problems.
      return inputGeoSet.musicMode.clone(video: inputGeoSet.video).refitted()
    }
  }

  /// OUTPUT GEOMETRY
  private func buildOutputGeometry(inputLayout: LayoutState, inputGeometry: PWinGeometry,
                                   outputLayout: LayoutState, _ inputGeoSet: GeometrySet,
                                   isWindowInitialLayout: Bool) -> PWinGeometry {

    switch outputLayout.mode {
    case .windowedNormal:
      let prevWindowedGeo: PWinGeometry
      if inputGeometry.mode == .windowedInteractive {
        /// `windowedInteractive` -> `windowed`
        log.verbose("Exiting interactive mode: converting windowedInteractive geo to windowed for outputGeo")
        prevWindowedGeo = inputGeometry.fromWindowedInteractiveMode()
      } else if inputGeometry.mode == .windowedNormal {
        log.verbose("Reusing inputGeometry for outputGeo (inputGeometry.mode=\(inputGeometry.mode))")
        prevWindowedGeo = inputGeometry
      } else {
        log.verbose("Reusing inputGeoSet.windowed for outputGeo (inputGeometry.mode=\(inputGeometry.mode))")
        prevWindowedGeo = inputGeoSet.windowed
      }
      let pinWidthOrHeightIfAtMax = !isWindowInitialLayout
      // Make sure videoGeo is up to date
      return outputLayout.convertWindowedModeGeometry(from: prevWindowedGeo, video: inputGeometry.video,
                                                      pinWidthOrHeightIfAtMax: pinWidthOrHeightIfAtMax, log)

    case .windowedInteractive:
      if inputGeometry.mode == .windowedInteractive {
        log.verbose("Already in interactive mode: reusing inputGeo for outputGeo")
        return inputGeometry
      } else if inputGeometry.mode == .fullScreenInteractive {
        // FIXME: toggling FS while in interactive mode is broken
        if inputGeoSet.windowed.mode == .windowedInteractive {
          log.verbose("Converting windowedModeGeo with mode=windowedInteractive to fullScreenInteractive for outputGeo")
          return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeometry.windowFrame,
                                                         screenID: inputGeoSet.windowed.screenID,
                                                         video: inputGeometry.video)
        } else {
          assert(inputGeoSet.windowed.mode == .windowedNormal,
                 "Expected mode==.windowedNormal for inputGeoSet.windowed: \(inputGeoSet.windowed)")
          log.verbose("Exiting full screen in interactive mode: converting windowedModeGeo to fullScreenInteractive")
          return inputGeoSet.windowed.clone(video: inputGeometry.video).toInteractiveMode()
        }
      } else {
        /// Entering interactive mode: convert from `windowed` to `windowedInteractive`
        log.verbose("Entering windowed interactive mode from windowed mode")

        if outputLayout.interactiveMode == .crop {
          // Need to remove crop if it exists
          let uncroppedNaiveGeo = inputGeometry.clone(video: inputGeometry.video.removingCrop())
          let uncroppedScaledGeo = uncroppedNaiveGeo.scalingViewport(toSimilarSizeAs: inputGeometry)

          return uncroppedScaledGeo.toInteractiveMode()
        }
        // Not cropping, but entering some other interactive mode mode
        return inputGeometry.toInteractiveMode()
      }

    case .fullScreenNormal, .fullScreenInteractive:
      let vidGeo: VideoGeometry
      if outputLayout.isInteractiveMode, outputLayout.interactiveMode == .crop {
        // Need to remove crop if it exists
        vidGeo = inputGeometry.video.removingCrop()
      } else {
        vidGeo = inputGeometry.video
      }
      // Full screen always uses same screen as windowed mode
      return outputLayout.buildFullScreenGeometry(inScreenID: inputGeometry.screenID, vidGeo)

    case .musicMode:
      /// `videoAspect` may have gone stale while not in music mode. Update it (playlist height will be recalculated if needed):
      let musicModeGeoCorrected = inputGeoSet.musicMode.cloneMusicMode(video: inputGeometry.video).refitted()
      return musicModeGeoCorrected
    }
  }

}

extension PlayerWindowController.LayoutTransition {

  /// Builds `closeOldPanelsGeometry`.
  /// Currently there are 4 bars, each of which can be either `inside` or `outside`, exclusively.
  func buildCloseOldPanelsGeometry() -> PWinGeometry? {
    guard !isWindowInitialLayout, !isEnteringLegacyFullScreen else {
      // Not animated
      return nil
    }

    let log = inputGeometry.log

    if isExitingLegacyFullScreen {
      return buildGeoForExtraLegacyFSAnimation(fsGeometry: inputGeometry)
    } else if isEnteringNativeFullScreen {
      return outputGeometry
    } else if isExitingNativeFullScreen {
      if outputLayout.topBarPlacement == .insideViewport {
        // Remove title bar only
        let insideTopH = outputGeometry.insideBars.top - outputLayout.titleBarHeight
        assert(insideTopH >= 0, "Expected insideBars.top - titleBarHeight to be non-negative! Found: \(insideTopH)")
        return outputGeometry.withResizedBars(insideTop: insideTopH)
      } else {
        // Do not modify case for .outsideViewport - there is a bug in MacOS Tahoe which causes the traffic light buttons to flicker
        // in the wrong place
        return outputGeometry
      }
    } else if isTogglingInteractiveMode {
      // - Interactive Mode

      let baseGeo: PWinGeometry
      if isEnteringInteractiveMode {
        if outputLayout.interactiveMode == .crop, let cropFilter = inputGeometry.video.cropFilter {
          assert(isEnteringInteractiveMode, "Expected to be entering interactive mode only when uncropping video")
          baseGeo = inputGeometry.clone(video: inputGeometry.video.removingCrop())
          log.verbose("Uncropping video from cropRect=\(cropFilter.cropRect(origVideoSize: inputGeometry.video.videoSizeCAR, flipY: true)) to uncroppedVideo=\(baseGeo.video.videoSizeDisplay)")
        } else {
          baseGeo = inputGeometry
        }
      } else {
        baseGeo = outputGeometry
      }

      if inputLayout.isFullScreen {
        return baseGeo.clone(topMarginHeight: 0,
                             outsideBars: .zero, insideBars: .zero)
      } else {  // Windowed

        // FIXME: For very slim crop, this sometimes shows black pillars. Maybe set a minimum zoom?
        let videoFrameInScreenCoords = baseGeo.refitted(lockViewportToVideoSize: true).videoFrameInScreenCoords

        let closedGeo = baseGeo.clone(windowFrame: videoFrameInScreenCoords, mode: .windowedNormal,
                                      topMarginHeight: 0,
                                      outsideBars: .zero, insideBars: .zero,
                                      viewportMargins: .zero,
                                      video: baseGeo.video)
        return closedGeo
      }

    } else if isEnteringMusicMode {
      // - Music Mode: Enter
      let baseGeo = inputGeometry

      let closedWindowFrame = baseGeo.videoFrameInScreenCoords
      return PWinGeometry(windowFrame: closedWindowFrame, screenID: baseGeo.screenID,
                          screenFit: baseGeo.screenFit, mode: .windowedNormal, topMarginHeight: 0,
                          outsideBars: .zero, insideBars: .zero, video: baseGeo.video)

    } else if isExitingMusicMode {
      // - Music Mode: Exit
      let baseGeo = inputGeometry

      let closedWindowFrame = baseGeo.videoFrameInScreenCoords
      return PWinGeometry(windowFrame: closedWindowFrame, screenID: baseGeo.screenID,
                          screenFit: baseGeo.screenFit, mode: .windowedNormal, topMarginHeight: 0,
                          outsideBars: .zero, insideBars: .zero, video: baseGeo.video)
    } else if inputGeometry.mode == .musicMode, outputGeometry.mode == .musicMode {
      // - Music Mode: Continuing
      if isTogglingViewport {
        return outputGeometry
      } else {
        return nil
      }
    }
    guard self.needsCloseOldPanelsStep else { return nil }

    // TOP
    let insideTopBarHeight: CGFloat
    let outsideTopBarHeight: CGFloat
    if !isWindowInitialLayout && isTopBarPlacementOrStyleChanging {
      insideTopBarHeight = 0  // close completely. will animate reopening if needed later
      outsideTopBarHeight = 0
    } else if outputGeometry.outsideBars.top < inputGeometry.outsideBars.top {
      insideTopBarHeight = 0
      outsideTopBarHeight = outputGeometry.outsideBars.top
    } else if outputGeometry.insideBars.top < inputGeometry.insideBars.top {
      insideTopBarHeight = outputGeometry.insideBars.top
      outsideTopBarHeight = 0
    } else if outputLayout.topBarHeight < inputLayout.topBarHeight {
      insideTopBarHeight = 0
      outsideTopBarHeight = outputLayout.topBarHeight
    } else {
      insideTopBarHeight = inputGeometry.insideBars.top  // leave the same
      outsideTopBarHeight = inputGeometry.outsideBars.top
    }

    // BOTTOM
    let insideBottomBarHeight: CGFloat
    let outsideBottomBarHeight: CGFloat
    if !isWindowInitialLayout && isBottomBarPlacementOrStyleChanging {
      // close completely. will animate reopening if needed later
      insideBottomBarHeight = 0
      outsideBottomBarHeight = 0
    } else if outputGeometry.outsideBars.bottom < inputGeometry.outsideBars.bottom {
      insideBottomBarHeight = 0
      outsideBottomBarHeight = outputGeometry.outsideBars.bottom
    } else if outputGeometry.insideBars.bottom < inputGeometry.insideBars.bottom {
      insideBottomBarHeight = outputGeometry.insideBars.bottom
      outsideBottomBarHeight = 0
    } else {
      insideBottomBarHeight = inputGeometry.insideBars.bottom
      outsideBottomBarHeight = inputGeometry.outsideBars.bottom
    }

    // LEADING
    let insideLeadingBarWidth: CGFloat
    let outsideLeadingBarWidth: CGFloat
    if isClosingLeadingSidebar {
      insideLeadingBarWidth = 0
      outsideLeadingBarWidth = 0
    } else {
      insideLeadingBarWidth = inputGeometry.insideBars.leading
      outsideLeadingBarWidth = inputGeometry.outsideBars.leading
    }

    // TRAILING
    let insideTrailingBarWidth: CGFloat
    let outsideTrailingBarWidth: CGFloat
    if isClosingTrailingSidebar {
      insideTrailingBarWidth = 0
      outsideTrailingBarWidth = 0
    } else {
      insideTrailingBarWidth = inputGeometry.insideBars.trailing
      outsideTrailingBarWidth = inputGeometry.outsideBars.trailing
    }

    let insideBars = MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                                bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
    let outsideBars = MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                                 bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)

    if outputLayout.isFullScreen {
      let screen = NSScreen.getScreenOrDefault(screenID: inputGeometry.screenID)
      return GeoUtil.buildFullScreenGeometry(in: screen, legacy: outputLayout.isLegacyFullScreen,
                                             mode: outputLayout.mode,
                                             outsideBars: outsideBars,
                                             insideBars: insideBars,
                                             video: outputGeometry.video,
                                             hasTopPaddingForCameraHousing: outputLayout.hasTopPaddingForCameraHousing)
    }

    let closedBarsGeo = inputGeometry.withResizedBars(outsideTop: outsideTopBarHeight,
                                                      outsideTrailing: outsideTrailingBarWidth,
                                                      outsideBottom: outsideBottomBarHeight,
                                                      outsideLeading: outsideLeadingBarWidth,
                                                      insideTop: insideTopBarHeight,
                                                      insideTrailing: insideTrailingBarWidth,
                                                      insideBottom: insideBottomBarHeight,
                                                      insideLeading: insideLeadingBarWidth,
                                                      pinWidthOrHeightIfAtMax: true)
    return closedBarsGeo.refitted()
  }
}
