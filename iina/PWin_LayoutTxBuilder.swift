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

  /// First builds a new `LayoutState` based on the given `LayoutSpec`, then builds & returns a `LayoutTransition`,
  /// which contains all the information needed to animate the UI changes from the current `LayoutState` to the new one.
  @discardableResult
  func buildLayoutTransition(named transitionName: String,
                             from inputLayout: LayoutState,
                             to outputSpec: LayoutSpec,
                             isWindowInitialLayout: Bool = false,
                             totalStartingDuration: CGFloat? = nil,
                             totalEndingDuration: CGFloat? = nil,
                             thenRun: Bool = false,
                             _ geoSet: GeometrySet? = nil) -> LayoutTransition {

    // use latest window frame in case it exists and was moved
    let inputGeoSet = geoSet ?? self.buildGeoSet(activeMode: inputLayout.mode)

    var transitionID: Int = 0
    $layoutTransitionCounter.withLock {
      $0 += 1
      transitionID = $0
    }
    let transitionName = "#\(transitionID) \(transitionName)"

    // This also applies to full screen, because full screen always uses the same screen as windowed.
    // Does not apply to music mode, which can be a different screen.
    let windowedModeScreen = NSScreen.getScreenOrDefault(screenID: inputGeoSet.windowed.screenID)

    // Compile outputLayout
    let outputLayout = LayoutState.buildFrom(outputSpec)

    // - Build GeometrySet

    // InputGeometry
    let inputGeometry: PWinGeometry = buildInputGeometry(from: inputLayout, transitionName: transitionName,
                                                         inputGeoSet, windowedModeScreen: windowedModeScreen)

    // OutputGeometry
    let outputGeometry: PWinGeometry = buildOutputGeometry(inputLayout: inputLayout, inputGeometry: inputGeometry,
                                                           outputLayout: outputLayout, inputGeoSet, isWindowInitialLayout: isWindowInitialLayout)

    let transition = LayoutTransition(name: transitionName,
                                      from: inputLayout, from: inputGeometry,
                                      to: outputLayout, to: outputGeometry,
                                      isWindowInitialLayout: isWindowInitialLayout)

    // MiddleGeometry if needed (is applied at end of ClosePanels step)
    if let middleGeo = buildMiddleGeometry(forTransition: transition, inputGeoSet) {
      transition.middleGeometry = middleGeo.clone(isMiddleTransition: true)
    }

    log.verbose("[\(transitionName)] INPUT:  \(inputGeometry)")
    log.verbose("[\(transitionName)] MIDDLE: \(transition.middleGeometry?.description ?? "nil")")
    log.verbose("[\(transitionName)] OUTPUT: \(outputGeometry)")

    let closeOldPanelsTiming: CAMediaTimingFunctionName
    let openFinalPanelsTiming: CAMediaTimingFunctionName
    let fadeInNewViewsTiming: CAMediaTimingFunctionName = .linear
    if transition.isTogglingFullScreen {
      closeOldPanelsTiming = .easeOut
      openFinalPanelsTiming = .easeOut
    } else if transition.isOpeningOrClosingAnySidebar {
      closeOldPanelsTiming = .easeIn
      openFinalPanelsTiming = .easeIn
    } else if transition.isExitingInteractiveMode {
      closeOldPanelsTiming = .easeOut
      openFinalPanelsTiming = .linear
    } else {
      closeOldPanelsTiming = .linear
      openFinalPanelsTiming = .linear
    }

    // - Determine durations

    let startingAnimationDuration: CGFloat
    if transition.isWindowInitialLayout {
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
    if transition.isWindowInitialLayout {
      endingAnimationDuration = 0
    } else {
      endingAnimationDuration = totalEndingDuration ?? Constants.AnimationDuration.standard
    }

    // Extra animation when entering legacy full screen: cover camera housing with black bar
    let useExtraAnimationForEnteringLegacyFullScreen = transition.isEnteringLegacyFullScreen && windowedModeScreen.hasCameraHousing && !transition.isWindowInitialLayout

    // Extra animation when exiting legacy full screen: remove camera housing with black bar
    let useExtraAnimationForExitingLegacyFullScreen = transition.isExitingLegacyFullScreen && windowedModeScreen.hasCameraHousing && !transition.isWindowInitialLayout

    var fadeInNewViewsDuration = endingAnimationDuration * 0.5
    var openFinalPanelsDuration = endingAnimationDuration
    if transition.isExitingFullScreen {
      fadeInNewViewsDuration = 0
    } else if useExtraAnimationForEnteringLegacyFullScreen || useExtraAnimationForEnteringLegacyFullScreen {
      let frameWithoutCameraRatio = windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height
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

    log.verbose("[\(transitionName)] Task durations: ShowOldFadeables=\(showFadeableViewsDuration) FadeOutOldViews=\(fadeOutOldViewsDuration), CloseOldPanels=\(closeOldPanelsDuration) FadeInNewViews=\(fadeInNewViewsDuration) OpenFinalPanels=\(openFinalPanelsDuration)")

    // - Starting animations:

    // Setup: Set initial var or other tasks which happen before main animations
    transition.tasks.append(.instantTask{ [self] in
      doPreTransitionWork(transition)
    })

    // StartingAnimation 1: Show fadeable views from current layout
    for fadeAnimation in buildAnimationToShowFadeableViews(restartFadeTimer: false, duration: showFadeableViewsDuration,
                                                           forceShow: true, forceShowTopBar: true) {
      transition.tasks.append(fadeAnimation)
    }

    // StartingAnimation 2: Fade out views which no longer will be shown but aren't enclosed in a panel.
    if transition.needsFadeOutOldViews {
      transition.tasks.append(.init(duration: fadeOutOldViewsDuration, { [self] in
        fadeOutOldViews(transition)
      }))
    }

    // StartingAnimation 3: Close/Minimize panels which are no longer needed. Applies middleGeometry if it exists.
    // Not enabled for full screen transitions.
    if transition.needsCloseOldPanels {
      transition.tasks.append(.init(duration: closeOldPanelsDuration, timing: closeOldPanelsTiming, { [self] in
        closeOldPanels(transition)
      }))
    }

    // Midpoint: perform major constraints updates (any affected panels should have been reduced to 0 thickness by the previous
    // task, so these updates can be performed without visible changes. In general, this step should have almost no visible
    // changes.
    transition.tasks.append(.instantTask{ [self] in
      updateHiddenViewsAndConstraints(transition)
    })

    // (Only for Enter/Exit Music Mode) Post-midpoint animation: move & scale video
    // When moving back or forth between windowedNormal & musicMode: scale & move the video frame for a nice transition animation.
    if transition.isTogglingMusicMode && !transition.isWindowInitialLayout {
      transition.tasks.append(.init(duration: closeOldPanelsDuration, timing: .easeInEaseOut) { [self] in
        let intermediateWindowFrame = transition.outputGeometry.videoFrameInScreenCoords
        log.verbose{"[\(transition.name)] Moving & resizing window to intermediate windowFrame=\(intermediateWindowFrame)"}

        // Need to have mode which is not music mode
        let middleGeo2 = transition.outputGeometry.clone(windowFrame: intermediateWindowFrame, mode: .windowedNormal,
                                                         topMarginHeight: 0,
                                                         outsideBars: MarginQuad.zero, insideBars: MarginQuad.zero,
                                                         isMiddleTransition: true)
        // For some reason, updating videoView constraints here causes a visual glich, so skip it (updateVideoView: false).
        // It's not needed until the next step anyway.
        setFrameAndUpdateWindowSubviews(using: middleGeo2, updateVideoView: false)
      })
    }

    // - Ending animations:

    // (Only for Exit Legacy FS) Extra animation for camera housing. In Big Sur, AppKit needed an extra transaction & more
    // time when animating around the camera housing, especially if also changing window `titled` style. This may no longer
    // be the case, but it's not harming anything to leave this as-is for now.
    if useExtraAnimationForExitingLegacyFullScreen {
      let cameraToTotalFrameRatio = 1 - (windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio

      transition.tasks.append(.init(duration: duration, timing: .easeIn) { [self] in
        let inputGeo = transition.inputGeometry
        let newGeo: PWinGeometry
        if inputGeo.hasTopPaddingForCameraHousing {
          /// Entering legacy FS on a screen with camera housing, but `Use entire Macbook screen` is unchecked in Settings.
          /// Prevent an unwanted bouncing near the top by using this animation to expand to visibleFrame.
          /// (will expand window to cover `cameraHousingHeight` in next animation)
          newGeo = inputGeo.clone(windowFrame: windowedModeScreen.frameWithoutCameraHousing,
                                                  screenID: windowedModeScreen.screenID, topMarginHeight: 0)
        } else {
          /// `Use entire Macbook screen` is checked in Settings. As of MacOS before Sonoma 14.4, Apple has been making improvements
          /// but we still need to use  a separate animation to give the OS time to hide the menu bar - otherwise there will be a flicker.
          let cameraHeight = windowedModeScreen.cameraHousingHeight ?? 0
          let margins = inputGeo.viewportMargins.addingTo(top: -cameraHeight)
          newGeo = inputGeo.clone(windowFrame: inputGeo.windowFrame.addingTo(top: -cameraHeight), viewportMargins: margins,
                                  isMiddleTransition: true)
        }
        log.verbose("[\(transition.name)] Updating legacy FS window to show camera housing prior to entering native windowed mode with windowFrame=\(newGeo.windowFrame)")
        setFrameAndUpdateWindowSubviews(using: newGeo)
      })
    }

    // EndingAnimation 1: Open new panels
    transition.tasks.append(.init(duration: openFinalPanelsDuration, timing: openFinalPanelsTiming, { [self] in
      // If toggling fullscreen, this also changes the window frame:
      openNewPanelsAndFinalizeOffsets(transition)
    }))

    // EndingAnimation 2: Fade in new views
    // If exiting FS, this task is skipped. It needs to run in a separate CATransaction so it is run down below.
    if transition.isWindowInitialLayout || transition.needsFadeInNewViews {
      transition.tasks.append(.init(duration: fadeInNewViewsDuration, timing: fadeInNewViewsTiming) { [self] in
        fadeInNewViews(transition)
      })
    }

    // (Only for Enter Legacy FS) Adds an extra animation to hiding camera housing / menu bar / dock.
    if useExtraAnimationForEnteringLegacyFullScreen {
      let cameraToTotalFrameRatio = 1 - (windowedModeScreen.frameWithoutCameraHousing.size.height / windowedModeScreen.frame.height)
      let duration = endingAnimationDuration * cameraToTotalFrameRatio

      transition.tasks.append(.init(duration: duration, timing: .easeIn) { [self] in
        let topBlackBarHeight = Preference.bool(for: .allowVideoToOverlapCameraHousing) ? 0 : (windowedModeScreen.cameraHousingHeight ?? 0)
        let newGeo = transition.outputGeometry.clone(windowFrame: windowedModeScreen.frame,
                                                     screenID: windowedModeScreen.screenID, topMarginHeight: topBlackBarHeight,
                                                     isMiddleTransition: true)
        log.verbose("[\(transition.name)] Updating legacy FS window to cover camera housing / menu bar / dock with windowFrame=\(newGeo.windowFrame)")
        setFrameAndUpdateWindowSubviews(using: newGeo)
      })
    }

    // Post: After animations all finish. Not animated.
    transition.tasks.append(.instantTask{ [self] in
      if transition.isTogglingFullScreen {
        // For a better visual experience wait until window finishes moving
        fadeInNewViews(transition)
      }
      doPostTransitionWork(transition)
    })

    if thenRun {
      animationPipeline.submit(transition.tasks)
    }
    return transition
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
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeoSet.windowed.windowFrame, screenID: inputGeoSet.windowed.screenID,
                                                     video: inputGeoSet.windowed.video)
    case .musicMode:
      /// `musicModeGeo` should have already been deserialized and set.
      /// But make sure we correct any size problems.
      return inputGeoSet.musicMode.refitted()
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
      } else if inputGeoSet.windowed.mode == .windowedInteractive {
        prevWindowedGeo = inputGeoSet.windowed.fromWindowedInteractiveMode()
      } else {
        prevWindowedGeo = inputGeoSet.windowed
      }
      let pinWidthOrHeightIfAtMax = !isWindowInitialLayout
      return outputLayout.convertWindowedModeGeometry(from: prevWindowedGeo, video: inputGeometry.video,
                                                      pinWidthOrHeightIfAtMax: pinWidthOrHeightIfAtMax, log)

    case .windowedInteractive:
      if inputGeometry.mode == .windowedInteractive {
        log.verbose("Already in interactive mode: converting windowed geo to interactiveWindowed for outputGeo")
        return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeoSet.windowed.windowFrame, screenID: inputGeoSet.windowed.screenID,
                                                       video: inputGeoSet.windowed.video)
      } else if inputGeometry.mode == .fullScreenInteractive {
        if inputGeoSet.windowed.mode == .windowedInteractive {
          log.verbose("Converting windowedModeGeo with mode=windowedInteractive to fullScreenInteractive")
          return PWinGeometry.buildInteractiveModeWindow(windowFrame: inputGeoSet.windowed.windowFrame, screenID: inputGeoSet.windowed.screenID,
                                                         video: inputGeometry.video)
        }
        log.verbose("Converting windowedModeGeo to fullScreenInteractive")
        return inputGeoSet.windowed.clone(video: inputGeometry.video).toInteractiveMode()
      }
      /// Entering interactive mode: convert from `windowed` to `windowedInteractive`
      return inputGeometry.toInteractiveMode()

    case .fullScreenNormal, .fullScreenInteractive:
      // Full screen always uses same screen as windowed mode
      return outputLayout.buildFullScreenGeometry(inScreenID: inputGeometry.screenID, inputGeometry.video)

    case .musicMode:
      /// `videoAspect` may have gone stale while not in music mode. Update it (playlist height will be recalculated if needed):
      let musicModeGeoCorrected = inputGeoSet.musicMode.cloneMusicMode(video: inputGeometry.video).refitted()

      if inputLayout.mode == .musicMode, let inputState = inputLayout.spec.musicModeState,
         let outputState = outputLayout.spec.musicModeState {

        if inputState.playlistShown != outputState.playlistShown {
          // Toggling music mode playlist
          let inputPlistHeight = inputGeometry.musicModePlaylistHeight
          let showPlaylist = !inputGeometry.isMusicModePlaylistVisible
          log.verbose{"Toggling playlist visibility: \((!showPlaylist).yn) → \(showPlaylist.yn)"}

          let outputWindowHeight: CGFloat
          if showPlaylist {
            // Try to show playlist using stored height
            let savedPlistHeight = CGFloat(Preference.integer(for: .musicModePlaylistHeight))
            // The window may be in the middle of a previous toggle, so we can't just assume window's current frame
            // represents a state where the playlist is fully shown or fully hidden. Instead, start by computing the height
            // we want to set, and then figure out the changes needed to the window's existing frame.
            let targetHeightToAdd = savedPlistHeight - inputPlistHeight
            // Fill up screen if needed
            outputWindowHeight = inputGeometry.windowFrame.height + targetHeightToAdd
          } else {
            // Hiding playlist
            let playlistHeightRounded = Int(round(inputPlistHeight))
            if playlistHeightRounded >= Int(Constants.Distance.MusicMode.minPlaylistHeight) {
              log.trace{"Saving prev playlist height: \(playlistHeightRounded)"}
              Preference.set(playlistHeightRounded, for: .musicModePlaylistHeight)
            }

            // If video is also hidden, do not try to shrink smaller than the control view, which would cause
            // a constraint violation. This is possible due to small imprecisions in various layout calculations.
            outputWindowHeight = max(Constants.Distance.MusicMode.oscHeight, inputGeometry.windowFrame.height - inputPlistHeight)
          }

          // adjust window origin to expand downwards
          let heightChange = outputWindowHeight - inputGeometry.windowFrame.height
          let outputWindowFrame = NSRect(x: inputGeometry.windowFrame.origin.x,
                                         y: inputGeometry.windowFrame.origin.y - heightChange,
                                         width: inputGeometry.windowFrame.width, height: outputWindowHeight)

          // Constrain window so that it doesn't expand below bottom of screen, or fall offscreen
          let outputGeometry = inputGeometry.cloneMusicMode(windowFrame: outputWindowFrame, playlistShown: showPlaylist)
          return outputGeometry
        }

      }
      return musicModeGeoCorrected

    }
  }

  /// Builds `middleGeometry`.
  /// Currently there are 4 bars. Each can be either inside or outside, exclusively.
  func buildMiddleGeometry(forTransition transition: LayoutTransition, _ inputGeoSet: GeometrySet) -> PWinGeometry? {
    guard !transition.isWindowInitialLayout else {
      // Not animated
      return nil
    }

    if transition.isTogglingInteractiveMode {
      // - Interactive Mode

      if transition.inputLayout.isFullScreen {
        // Need to hide sidebars when entering interactive mode in full screen
        return transition.outputGeometry
      }

      let outsideTopBarHeight = transition.inputLayout.outsideTopBarHeight >= transition.outputLayout.topBarHeight ? transition.outputLayout.outsideTopBarHeight : 0

      let videoFrame = transition.outputGeometry.videoFrameInScreenCoords
      let extraWidthNeeded = max(0, Constants.InteractiveMode.minWindowWidth - videoFrame.width)
      let newWindowFrame = NSRect(origin: NSPoint(x: videoFrame.origin.x - (extraWidthNeeded * 0.5), y: videoFrame.origin.y),
                                  size: CGSize(width: videoFrame.width + extraWidthNeeded, height: videoFrame.height + outsideTopBarHeight))

      // Need to supply explicit viewportMargins when exiting interactive mode, to ensure they are zero.
      // Otherwise they will be implicitly set to the standard interactive mode margins, which won't work for our animation.
      let viewportMargins: MarginQuad = .zero
      let resizedGeo = PWinGeometry(windowFrame: newWindowFrame, screenID: transition.outputGeometry.screenID,
                                    screenFit: transition.outputGeometry.screenFit,
                                    mode: transition.inputLayout.mode,
                                    topMarginHeight: 0,
                                    outsideBars: MarginQuad(top: outsideTopBarHeight), insideBars: MarginQuad.zero,
                                    viewportMargins: viewportMargins,
                                    video: transition.outputGeometry.video)
      return resizedGeo

    } else if transition.isEnteringMusicMode {
      // - Music Mode: Enter

      let baseGeo: PWinGeometry
      if transition.inputLayout.isFullScreen {
        // Need middle geo so that sidebars get closed
        baseGeo = inputGeoSet.musicMode.cloneMusicMode(video: inputGeoSet.video, playlistShown: false)
      } else {
        baseGeo = transition.inputGeometry
      }

      let middleWindowFrame = baseGeo.videoFrameInScreenCoords
      return PWinGeometry(windowFrame: middleWindowFrame, screenID: baseGeo.screenID,
                          screenFit: baseGeo.screenFit, mode: .windowedNormal, topMarginHeight: 0,
                          outsideBars: .zero, insideBars: .zero, video: baseGeo.video)

    } else if transition.isExitingMusicMode {
      // - Music Mode: Exit
      if transition.isEnteringFullScreen {
        return nil
      }
      // Only bottom bar needs to be closed. No need to constrain in screen
      return transition.inputGeometry.withResizedBars(mode: .windowedNormal,
                                                      outsideBottom: 0,
                                                      pinWidthOrHeightIfAtMax: false)
    }

    // TOP
    let insideTopBarHeight: CGFloat
    let outsideTopBarHeight: CGFloat
    if !transition.isWindowInitialLayout && transition.isTopBarPlacementOrStyleChanging {
      insideTopBarHeight = 0  // close completely. will animate reopening if needed later
      outsideTopBarHeight = 0
    } else if transition.outputGeometry.outsideBars.top < transition.inputGeometry.outsideBars.top {
      insideTopBarHeight = 0
      outsideTopBarHeight = transition.outputGeometry.outsideBars.top
    } else if transition.outputGeometry.insideBars.top < transition.inputGeometry.insideBars.top {
      insideTopBarHeight = transition.outputGeometry.insideBars.top
      outsideTopBarHeight = 0
    } else if transition.outputLayout.topBarHeight < transition.inputLayout.topBarHeight {
      insideTopBarHeight = 0
      outsideTopBarHeight = transition.outputLayout.topBarHeight
    } else {
      insideTopBarHeight = transition.inputGeometry.insideBars.top  // leave the same
      outsideTopBarHeight = transition.inputGeometry.outsideBars.top
    }

    // BOTTOM
    let insideBottomBarHeight: CGFloat
    let outsideBottomBarHeight: CGFloat
    if !transition.isWindowInitialLayout && transition.isBottomBarPlacementOrStyleChanging {
      // close completely. will animate reopening if needed later
      insideBottomBarHeight = 0
      outsideBottomBarHeight = 0
    } else if transition.outputGeometry.outsideBars.bottom < transition.inputGeometry.outsideBars.bottom {
      insideBottomBarHeight = 0
      outsideBottomBarHeight = transition.outputGeometry.outsideBars.bottom
    } else if transition.outputGeometry.insideBars.bottom < transition.inputGeometry.insideBars.bottom {
      insideBottomBarHeight = transition.outputGeometry.insideBars.bottom
      outsideBottomBarHeight = 0
    } else {
      insideBottomBarHeight = transition.inputGeometry.insideBars.bottom
      outsideBottomBarHeight = transition.inputGeometry.outsideBars.bottom
    }

    // LEADING
    let insideLeadingBarWidth: CGFloat
    let outsideLeadingBarWidth: CGFloat
    if transition.isClosingLeadingSidebar {
      insideLeadingBarWidth = 0
      outsideLeadingBarWidth = 0
    } else {
      insideLeadingBarWidth = transition.inputGeometry.insideBars.leading
      outsideLeadingBarWidth = transition.inputGeometry.outsideBars.leading
    }

    // TRAILING
    let insideTrailingBarWidth: CGFloat
    let outsideTrailingBarWidth: CGFloat
    if transition.isClosingTrailingSidebar {
      insideTrailingBarWidth = 0
      outsideTrailingBarWidth = 0
    } else {
      insideTrailingBarWidth = transition.inputGeometry.insideBars.trailing
      outsideTrailingBarWidth = transition.inputGeometry.outsideBars.trailing
    }

    let insideBars = MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                                bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
    let outsideBars = MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                                 bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)

    if transition.outputLayout.isFullScreen {
      let screen = NSScreen.getScreenOrDefault(screenID: transition.inputGeometry.screenID)
      return PWinGeometry.forFullScreen(in: screen, legacy: transition.outputLayout.isLegacyFullScreen,
                                        mode: transition.outputLayout.mode,
                                        outsideBars: outsideBars,
                                        insideBars: insideBars,
                                        video: transition.outputGeometry.video,
                                        hasTopPaddingForCameraHousing: transition.outputLayout.hasTopPaddingForCameraHousing)
    }

    let resizedBarsGeo = transition.outputGeometry.withResizedBars(outsideTop: outsideTopBarHeight,
                                                                   outsideTrailing: outsideTrailingBarWidth,
                                                                   outsideBottom: outsideBottomBarHeight,
                                                                   outsideLeading: outsideLeadingBarWidth,
                                                                   insideTop: insideTopBarHeight,
                                                                   insideTrailing: insideTrailingBarWidth,
                                                                   insideBottom: insideBottomBarHeight,
                                                                   insideLeading: insideLeadingBarWidth,
                                                                   pinWidthOrHeightIfAtMax: true)
    return resizedBarsGeo.refitted()
  }

}
