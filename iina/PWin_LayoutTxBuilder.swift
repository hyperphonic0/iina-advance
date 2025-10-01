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
                             from inputLayout: LayoutState, inputGeo inputGeoExplicit: PWinGeometry? = nil,
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
    let inputGeometry = inputGeoExplicit ?? buildInputGeometry(from: inputLayout, transitionName: transitionName,
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

    let middleGeometry = protoTransition.buildMiddleGeometry()?.clone(isMiddleTransition: true)
    let transition = LayoutTransition(name: transitionName,
                                      from: inputLayout, from: inputGeometry,
                                      to: outputLayout, to: outputGeometry,
                                      middleGeometry: middleGeometry,
                                      windowedModeScreen: windowedModeScreen,
                                      isWindowInitialLayout: isWindowInitialLayout)


    log.verbose("[\(transitionName)] INPUT\(inputGeoExplicit == nil ? "" : "(given)"):  \(inputGeometry)")
    log.verbose("[\(transitionName)] MIDDLE: \(transition.middleGeometry?.description ?? "nil")")
    log.verbose("[\(transitionName)] OUTPUT\(outputGeoExplicit == nil ? "" : "(given)"):  \(outputGeometry)")

    return transition
  }

  @discardableResult
  func buildTasks(for transition: LayoutTransition,
                  totalStartingDuration: CGFloat? = nil,
                  totalEndingDuration: CGFloat? = nil,
                  thenRun: Bool = false) -> [IINAAnimation.Task] {

    // - Timings Setup

    let closeOldPanelsTiming: CAMediaTimingFunctionName
    let openFinalPanelsTiming: CAMediaTimingFunctionName
    let fadeInNewViewsTiming: CAMediaTimingFunctionName = .linear
    if transition.isEnteringFullScreen {
      closeOldPanelsTiming = .easeIn
      openFinalPanelsTiming = .easeIn
    } else if transition.isExitingFullScreen {
      closeOldPanelsTiming = .easeOut
      openFinalPanelsTiming = .easeOut
    } else if transition.isOpeningOrClosingAnySidebar {
      closeOldPanelsTiming = .easeInEaseOut
      openFinalPanelsTiming = .easeInEaseOut
    } else if transition.isTogglingInteractiveMode {
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
    } else if transition.isTogglingMusicMode {
      // Try to reduce wobble when collapsing or expanding viewport. Need to do more research to prevent wobbling
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
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
      showFadeableViewsDuration = startingAnimationDuration * 0.5
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else if transition.isEnteringInteractiveMode {
      showFadeableViewsDuration = startingAnimationDuration * 0.25
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else if transition.isExitingInteractiveMode {
      showFadeableViewsDuration = 0
      fadeOutOldViewsDuration = startingAnimationDuration * 0.5
    } else {
      if !transition.needsAnimationForShowFadeables {
        showFadeableViewsDuration = 0
      }
      if !transition.needsFadeOutOldViews {
        fadeOutOldViewsDuration = 0
      } else if !transition.needsCloseOldPanels {
        closeOldPanelsDuration = 0
      }
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
    let useExtraAnimationForExitingLegacyFullScreen = IINAAnimation.isAnimationEnabled && transition.isExitingLegacyFullScreen && screenHasCameraHousing && !transition.isWindowInitialLayout

    var fadeInNewViewsDuration = endingAnimationDuration * 0.5
    var openFinalPanelsDuration = endingAnimationDuration
    if transition.isExitingFullScreen {
      fadeInNewViewsDuration = 0
    } else if useExtraAnimationForEnteringLegacyFullScreen || useExtraAnimationForExitingLegacyFullScreen {
      let winScreen = transition.windowedModeScreen
      let frameWithoutCameraRatio = winScreen.frameWithoutCameraHousing.size.height / winScreen.frame.height
      openFinalPanelsDuration *= frameWithoutCameraRatio
    } else if transition.isEnteringInteractiveMode {
      openFinalPanelsDuration *= 0.5
      fadeInNewViewsDuration *= 0.5
    } else {
      if !transition.needsFadeInNewViews {
        fadeInNewViewsDuration = 0
      } else if !transition.needsAnimationForOpenFinalPanels {
        openFinalPanelsDuration = 0
      }
    }

    log.verbose("[\(transition.name)] Task durations: ShowOldFadeables=\(showFadeableViewsDuration) FadeOutOldViews=\(fadeOutOldViewsDuration), CloseOldPanels=\(closeOldPanelsDuration) FadeInNewViews=\(fadeInNewViewsDuration) OpenFinalPanels=\(openFinalPanelsDuration)")

    var tasks: [IINAAnimation.Task] = []

    // - Starting animations:

    // Setup: Set initial var or other tasks which happen before main animations
    tasks.append(.instantTask{ [self] in
      doPreTransitionWork(transition)
    })

    // StartingAnimation 1: Show fadeable views from current layout
    for fadeAnimation in buildAnimationToShowFadeableViews(targetLayout: transition.inputLayout,
                                                           restartFadeTimer: false, duration: showFadeableViewsDuration,
                                                           forceShow: true, forceShowTopBar: true) {
      tasks.append(fadeAnimation)
    }

    // StartingAnimation 2: Fade out views which no longer will be shown but aren't enclosed in a panel.
    if transition.needsFadeOutOldViews {
      tasks.append(.init(duration: fadeOutOldViewsDuration, { [self] in
        fadeOutOldViews(transition)
      }))
    }

    // StartingAnimation 3: Close/Minimize panels which are no longer needed. Applies middleGeometry if it exists.
    // Not enabled for full screen transitions or if animation is disabled.
    if transition.needsCloseOldPanels, closeOldPanelsDuration > 0.0 {
      tasks.append(.init(duration: closeOldPanelsDuration, timing: closeOldPanelsTiming, { [self] in
        closeOldPanels(transition)
      }))
    }

    // (Only when animating Enter/Exit Music Mode or Enter/Exit Windowed Interactive Mode) Post-midpoint animation: move & scale video.
    var moveAndResizeVideoTask: IINAAnimation.Task? = nil
    if !transition.isWindowInitialLayout, closeOldPanelsDuration > 0.0,
        transition.isTogglingMusicMode ||
        (transition.isTogglingInteractiveMode && !transition.inputLayout.isFullScreen) {
      let duration = transition.isTogglingInteractiveMode ? (closeOldPanelsDuration * 0.5) : closeOldPanelsDuration
      moveAndResizeVideoTask = .init(duration: duration, timing: .easeInEaseOut) { [self] in
        moveAndResizeVideoFrame(transition)
      }
    }

    // Place this task either before or after updateHiddenViewsAndConstraints depending on entering or exiting.
    // Want to put this *before* it when entering music mode & hiding (closing) viewportView, but other cases the order shouldn't matter.
    if let moveAndResizeVideoTask, transition.isEnteringMusicMode {
      tasks.append(moveAndResizeVideoTask)
    }

    // Midpoint: perform major constraints updates (any affected panels should have been reduced to 0 thickness by the previous
    // task, so these updates can be performed without visible changes. In general, this step should have almost no visible
    // changes.
    tasks.append(.instantTask{ [self] in
      updateHiddenViewsAndConstraints(transition)
    })

    if let moveAndResizeVideoTask, !transition.isEnteringMusicMode {
      tasks.append(moveAndResizeVideoTask)
    }

    // - Ending animations:

    // (Only for Exit Legacy FS) Extra animation for camera housing. In Big Sur, AppKit needed an extra transaction & more
    // time when animating around the camera housing, especially if also changing window `titled` style. This may no longer
    // be the case, but it's not harming anything to leave this as-is for now.
    if useExtraAnimationForExitingLegacyFullScreen {
      let winScreen = transition.windowedModeScreen
      let cameraToTotalFrameRatio = 1 - (winScreen.frameWithoutCameraHousing.size.height / winScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio

      tasks.append(.init(duration: duration, timing: openFinalPanelsTiming) { [self] in
        let inputGeo = transition.inputGeometry
        let newGeo: PWinGeometry
        if inputGeo.hasTopPaddingForCameraHousing {
          /// Exiting legacy FS on a screen with camera housing, but `Use entire Macbook screen` is unchecked in Settings.
          newGeo = inputGeo.clone(windowFrame: winScreen.frameWithoutCameraHousing,
                                                  screenID: winScreen.screenID, topMarginHeight: 0)
        } else {
          /// `Use entire Macbook screen` is checked in Settings. As of MacOS before Sonoma 14.4, Apple has been making improvements
          /// but we still need to use  a separate animation to give the OS time to hide the menu bar - otherwise there will be a flicker.
          let cameraHeight = winScreen.cameraHousingHeight ?? 0
          let margins = inputGeo.viewportMargins.addingTo(top: -cameraHeight)
          newGeo = inputGeo.clone(windowFrame: inputGeo.windowFrame.addingTo(top: -cameraHeight), viewportMargins: margins,
                                  isMiddleTransition: true)
        }
        log.verbose("[\(transition.name)] Updating legacy FS window to show camera housing prior to entering native windowed mode with windowFrame=\(newGeo.windowFrame)")
        setFrameAndUpdateWindowSubviews(using: newGeo)
      })
    }

    // EndingAnimation 1: Open new panels
    tasks.append(.init(duration: openFinalPanelsDuration, timing: openFinalPanelsTiming, { [self] in
      // If toggling fullscreen, this also changes the window frame:
      openNewPanelsAndFinalizeOffsets(transition)
    }))

    // EndingAnimation 2: Fade in new views
    // If exiting FS, this task is skipped. It needs to run in a separate CATransaction so it is run down below.
    if transition.isWindowInitialLayout || transition.needsFadeInNewViews {
      tasks.append(.init(duration: fadeInNewViewsDuration, timing: fadeInNewViewsTiming) { [self] in
        fadeInNewViews(transition)
      })
    }

    // (Only for Enter Legacy FS) Adds an extra animation to hide camera housing / menu bar / dock.
    if useExtraAnimationForEnteringLegacyFullScreen {
      let winScreen = transition.windowedModeScreen
      let cameraToTotalFrameRatio = 1 - (winScreen.frameWithoutCameraHousing.size.height / winScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio

      tasks.append(.init(duration: duration, timing: openFinalPanelsTiming) { [self] in
        let topBlackBarHeight = Preference.bool(for: .allowVideoToOverlapCameraHousing) ? 0 : (winScreen.cameraHousingHeight ?? 0)
        let newGeo = transition.outputGeometry.clone(windowFrame: winScreen.frame,
                                                     screenID: winScreen.screenID, topMarginHeight: topBlackBarHeight,
                                                     isMiddleTransition: true)
        log.verbose("[\(transition.name)] Updating legacy FS window to cover camera housing / menu bar / dock with windowFrame=\(newGeo.windowFrame)")
        setFrameAndUpdateWindowSubviews(using: newGeo)
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

  /// Builds `inputGeometry`.
  private func buildInputGeometry(from inputLayout: LayoutState, transitionName: String, _ inputGeoSet: GeometrySet, 
                                  windowedModeScreen: NSScreen) -> PWinGeometry {
    
    // Restore window size & position
    switch inputLayout.mode {
    case .windowedNormal:
      return inputGeoSet.windowed
    case .fullScreenNormal, .fullScreenInteractive:
      return inputLayout.buildFullScreenGeometry(in: windowedModeScreen, inputGeoSet.video)
    case .windowedInteractive:
      /// `.inputGeoSet.windowed` should already be correct for interactiveWindowed mode, but it is easy enough to derive it
      /// from a small number of variables, and safer to do that than assume it is correct:
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeoSet.windowed.windowFrame,
                                                     screenID: inputGeoSet.windowed.screenID,
                                                     video: inputGeoSet.video)
    case .musicMode:
      /// `musicModeGeo` should have already been deserialized and set.
      /// But make sure we correct any size problems.
      return inputGeoSet.musicMode.clone(video: inputGeoSet.video).refitted()
    }
  }

  /// Builds `outputGeometry`.
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
      } else {
        log.verbose("Exiting interactive mode: reusing prev windowed geo for outputGeo")
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
        if inputGeoSet.windowed.mode == .windowedInteractive {
          log.verbose("Converting windowedModeGeo with mode=windowedInteractive to fullScreenInteractive for outputGeo")
          return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeoSet.windowed.windowFrame,
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

          // Tag: #ViewportSizeHeuristic
          var newViewportSize: CGSize
          if Preference.bool(for: .lockViewportToVideoSize) {
            // Try to avoid shrinking the window too much if the aspect changes dramatically.
            let containerSize = NSScreen.getScreenOrDefault(screenID: inputGeometry.screenID).visibleFrame.size
            let useRatioW = (inputGeometry.viewportSize.width / containerSize.width).clamped(to: 0...1)
            let useRatioH = (inputGeometry.viewportSize.height / containerSize.height).clamped(to: 0...1)
            let useRatioMax = max(useRatioW, useRatioH)

            newViewportSize = containerSize * useRatioMax  // not rounded. Need to round below.
          } else {
            // Try to keep current viewportSize
            newViewportSize = inputGeometry.viewportSize
          }

          // Add IM margins
          newViewportSize = CGSize(width: newViewportSize.width + Constants.InteractiveMode.viewportMargins.totalWidth,
                                   height: newViewportSize.height + Constants.InteractiveMode.viewportMargins.totalHeight)
          while (newViewportSize.width < Constants.InteractiveMode.minViewportSize.width) || (newViewportSize.height < Constants.InteractiveMode.minViewportSize.height) {
            newViewportSize = newViewportSize * 2.0
          }
          newViewportSize = newViewportSize.rounded()
          let newIMGeo = uncroppedNaiveGeo.scalingViewport(to: newViewportSize)

          return newIMGeo.toInteractiveMode()
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

  /// Builds `middleGeometry`.
  /// Currently there are 4 bars. Each can be either inside or outside, exclusively.
  func buildMiddleGeometry() -> PWinGeometry? {
    guard !isWindowInitialLayout else {
      // Not animated
      return nil
    }

    let log = inputGeometry.log

    if isTogglingInteractiveMode {
      // - Interactive Mode

      if inputLayout.isFullScreen {
        // Need to hide sidebars when entering interactive mode in full screen
        return outputGeometry
      }

      let mustUncropFirst = (outputLayout.interactiveMode == .crop) && (inputGeometry.video.cropFilter != nil)
      if mustUncropFirst, let cropFilter = inputGeometry.video.cropFilter {
        assert(isEnteringInteractiveMode, "Expected to be entering interactive mode only when uncropping video")
        let uncroppedVideoGeo = inputGeometry.video.removingCrop()
        log.verbose{"Uncropping video from cropRect=\(cropFilter.cropRect(origVideoSize: uncroppedVideoGeo.videoSizeRaw, flipY: true)) to videoSizeRaw=\(uncroppedVideoGeo.videoSizeRaw)"}

        let intermediateWindowFrame = inputGeometry.clone(video: uncroppedVideoGeo).refitted().videoFrameInScreenCoords
        let middleGeo = inputGeometry.clone(windowFrame: intermediateWindowFrame, mode: .windowedNormal,
                                            topMarginHeight: 0,
                                            outsideBars: .zero, insideBars: .zero,
                                            viewportMargins: .zero,
                                            isMiddleTransition: true)
        return middleGeo
      }

      let baseGeo = isEnteringInteractiveMode ? inputGeometry : outputGeometry
      // FIXME: For very slim crop, this sometimes shows black pillars. Maybe set a minimum zoom?
      let intermediateWindowFrame = baseGeo.refitted(lockViewportToVideoSize: true).videoFrameInScreenCoords

      let middleGeo = baseGeo.clone(windowFrame: intermediateWindowFrame, mode: .windowedNormal,
                                    topMarginHeight: 0,
                                    outsideBars: .zero, insideBars: .zero,
                                    viewportMargins: .zero,
                                    isMiddleTransition: true)
      return middleGeo

    } else if isEnteringMusicMode {
      // - Music Mode: Enter
      let baseGeo = inputGeometry

      let middleWindowFrame = baseGeo.videoFrameInScreenCoords
      return PWinGeometry(windowFrame: middleWindowFrame, screenID: baseGeo.screenID,
                          screenFit: baseGeo.screenFit, mode: .windowedNormal, topMarginHeight: 0,
                          outsideBars: .zero, insideBars: .zero, video: baseGeo.video,
                          isMiddleTransition: true)

    } else if isExitingMusicMode {
      // - Music Mode: Exit
      if isEnteringFullScreen {
        return nil
      }
      // Only bottom bar needs to be closed. No need to constrain in screen
      return inputGeometry.withResizedBars(mode: .windowedNormal,
                                           outsideBottom: 0,
                                           pinWidthOrHeightIfAtMax: false,
                                           isMiddleTransition: true)
    } else if inputGeometry.mode == .musicMode, outputGeometry.mode == .musicMode {
      // - Music Mode: Continuing
      if isTogglingViewport {
        return outputGeometry.cloneMusicMode(isMiddleTransition: true)
      } else {
        return nil
      }
    }

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
      return PWinGeometry.forFullScreen(in: screen, legacy: outputLayout.isLegacyFullScreen,
                                        mode: outputLayout.mode,
                                        outsideBars: outsideBars,
                                        insideBars: insideBars,
                                        video: outputGeometry.video,
                                        hasTopPaddingForCameraHousing: outputLayout.hasTopPaddingForCameraHousing)
    }

    let closedBarsGeo = outputGeometry.withResizedBars(outsideTop: outsideTopBarHeight,
                                                       outsideTrailing: outsideTrailingBarWidth,
                                                       outsideBottom: outsideBottomBarHeight,
                                                       outsideLeading: outsideLeadingBarWidth,
                                                       insideTop: insideTopBarHeight,
                                                       insideTrailing: insideTrailingBarWidth,
                                                       insideBottom: insideBottomBarHeight,
                                                       insideLeading: insideLeadingBarWidth,
                                                       pinWidthOrHeightIfAtMax: true,
                                                       isMiddleTransition: true)
    return closedBarsGeo.refitted()
  }
}
