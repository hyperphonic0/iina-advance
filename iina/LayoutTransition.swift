//
//  LayoutTransition.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {
  /// `LayoutTransition`: data structure which holds metadata needed to execute a series of animations which transition
  /// a single `PlayerWindow` from one layout (`inputLayout`) to another (`outputLayout`). Instances of `PWinGeometry`
  /// are also used along the way to dictate window location/size, viewport size, sidebar sizes, & other geometry.
  ///
  /// See `buildLayoutTransition()`, where an instance of this object is assembled.
  /// Other important variables: `currentLayout`, `windowedModeGeo`, `musicModeGeo` (in `PlayerWindowController`)
  struct LayoutTransition {
    enum Stage: Int, StateEnum, CustomStringConvertible {
      case preTransitionSetup
      case closeOldPanels
      /// NOTE: this can occur either before or after `closeOldPanels`
      //      case moveAndScale
      case midTransitionHiddenUpdates
      case openNewPanels
      case postTransition
      
      var description: String {
        switch self {
        case .preTransitionSetup:
          return "PreTxSetup"
        case .closeOldPanels:
          return "CloseOldPanels"
          //        case .moveAndScale:
          //          return "MoveAndScale"
        case .midTransitionHiddenUpdates:
          return "MidTxHiddenUpdates"
        case .openNewPanels:
          return "OpenNewPanels"
        case .postTransition:
          return "PostTx"
        }
      }
      
      func isAtLeast(_ minStatus: Stage) -> Bool { rawValue >= minStatus.rawValue }
      func isNotYet(_ status: Stage) -> Bool { rawValue < status.rawValue }
    }
    
    let name: String  // just used to improve logging
    
    let inputLayout: LayoutState
    let outputLayout: LayoutState
    
    let inputGeometry: PWinGeometry
    /// MiddleGeometry, if needed, is applied at end of ClosePanels step
    let middleGeometry: PWinGeometry?
    let outputGeometry: PWinGeometry
    
    /// Random datum needed for building tasks
    let windowedModeScreen: NSScreen
    
    /// Should only be true when setting layout on session open. See `buildWindowInitialLayoutTasks()`.
    let isWindowInitialLayout: Bool
    
    init(name: String, from inputLayout: LayoutState, from inputGeometry: PWinGeometry,
         to outputLayout: LayoutState, to outputGeometry: PWinGeometry,
         middleGeometry: PWinGeometry? = nil,
         windowedModeScreen: NSScreen,
         isWindowInitialLayout: Bool = false) {
      self.name = name
      self.inputLayout = inputLayout
      self.inputGeometry = inputGeometry
      self.middleGeometry = middleGeometry
      self.outputLayout = outputLayout
      self.outputGeometry = outputGeometry
      self.windowedModeScreen = windowedModeScreen
      self.isWindowInitialLayout = isWindowInitialLayout
    }
    
    // Always need to execute this step. But may not need to use an animation
    var needsAnimationForShowFadeables: Bool {
      return !outputLayout.isInteractiveMode && needsFadeOutOldViewsStep
    }
    
    var needsFadeOutOldViewsStep: Bool {
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade OUT
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue))
      || (inputLayout.leadingSidebarToggleButton.isShowable && !outputLayout.leadingSidebarToggleButton.isShowable)
      || (inputLayout.trailingSidebarToggleButton.isShowable && !outputLayout.trailingSidebarToggleButton.isShowable)
    }
    
    var needsFadeInNewViewsStep: Bool {
      if isWindowInitialLayout { return true }
      if isTogglingFullScreen { return false }
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (outputLayout.mode.isInteractiveMode)  // Needed to fade in cropBoxView again after layout update
      || (outputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade IN
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (outputLayout.enableOSC && (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue))
      || (!inputLayout.leadingSidebarToggleButton.isShowable && outputLayout.leadingSidebarToggleButton.isShowable)
      || (!inputLayout.trailingSidebarToggleButton.isShowable && outputLayout.trailingSidebarToggleButton.isShowable)
    }
    
    var needsCloseOldPanelsStep: Bool {
      if isEnteringFullScreen || isWindowInitialLayout {
        // Avoid bounciness and possible unwanted video scaling animation (not needed for ->FS anyway)
        return false
      }
      return middleGeometry != nil
      || isClosingLeadingSidebar || isClosingTrailingSidebar
      || inputLayout.hasTopPaddingForCameraHousing != outputLayout.hasTopPaddingForCameraHousing
      || isClosingPlaylistInMusicMode || isClosingViewport
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.isLegacyStyle != outputLayout.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue))
    }

    var needsMoveAndResizeVideoFrameStep: Bool {
      !isWindowInitialLayout && (isTogglingMusicMode || (isTogglingInteractiveMode && !inputLayout.isFullScreen))
    }

    /// Assuming that `needsMoveAndResizeVideoFrameStep==true`, returns `true` if the "move & resize video frame" step should
    /// execute *prior* to the `updateHiddenViewsAndConstraints` step; returns `false` if it should execute afterwards.
    var isMoveAndResizeStepBeforeMidpoint: Bool {
      assert(needsMoveAndResizeVideoFrameStep)
      return isEnteringMusicMode || isEnteringInteractiveMode
    }

    /// Always need to execute this step. But may not need to use an animation.
    var needsAnimationForOpenFinalPanels: Bool {
      return (inputGeometry.topMarginHeight != outputGeometry.topMarginHeight)
      || isOpeningLeadingSidebar || isOpeningTrailingSidebar
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.isLegacyStyle != outputLayout.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.topBarHeight != outputLayout.topBarHeight)
      || (inputGeometry.insideBars.bottom != outputGeometry.insideBars.bottom)
      || (inputGeometry.outsideBars.bottom != outputGeometry.outsideBars.bottom)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue))
    }

    var isAddingLegacyStyle: Bool {
      return !inputLayout.isLegacyStyle && outputLayout.isLegacyStyle
    }

    var isRemovingLegacyStyle: Bool {
      return inputLayout.isLegacyStyle && !outputLayout.isLegacyStyle
    }

    var isTogglingLegacyStyle: Bool {
      return inputLayout.isLegacyStyle != outputLayout.isLegacyStyle
    }

    var isTogglingFullScreen: Bool {
      return inputLayout.isFullScreen != outputLayout.isFullScreen
    }

    var isEnteringFullScreen: Bool {
      return outputLayout.isFullScreen && (!inputLayout.isFullScreen || isWindowInitialLayout)
    }

    var isExitingFullScreen: Bool {
      return inputLayout.isFullScreen && !outputLayout.isFullScreen
    }

    var isEnteringNativeFullScreen: Bool {
      return isEnteringFullScreen && outputLayout.isNativeFullScreen
    }

    var isExitingNativeFullScreen: Bool {
      return isExitingFullScreen && inputLayout.isNativeFullScreen
    }

    var isEnteringLegacyFullScreen: Bool {
      return isEnteringFullScreen && outputLayout.isLegacyFullScreen
    }

    var isExitingLegacyFullScreen: Bool {
      return isExitingFullScreen && inputLayout.isLegacyFullScreen
    }

    var isTogglingLegacyFullScreen: Bool {
      return isEnteringLegacyFullScreen || isExitingLegacyFullScreen
    }

    var isEnteringMusicMode: Bool {
      return !inputLayout.isMusicMode && outputLayout.isMusicMode
    }

    var isExitingMusicMode: Bool {
      return inputLayout.isMusicMode && !outputLayout.isMusicMode
    }

    var isTogglingMusicMode: Bool {
      return inputLayout.isMusicMode != outputLayout.isMusicMode
    }

    var isEnteringInteractiveMode: Bool {
      return !inputLayout.isInteractiveMode && outputLayout.isInteractiveMode
    }

    var isExitingInteractiveMode: Bool {
      return inputLayout.isInteractiveMode && !outputLayout.isInteractiveMode
    }

    var isTogglingInteractiveMode: Bool {
      return isEnteringInteractiveMode || isExitingInteractiveMode
    }

    var isTopBarPlacementChanging: Bool {
      return inputLayout.topBarPlacement != outputLayout.topBarPlacement
    }

    var isOSCStyleChanging: Bool {
      return (inputLayout.effectiveOSCColorScheme != outputLayout.effectiveOSCColorScheme) ||
      (inputLayout.controlBarGeo.isTwoRowBarOSC != outputLayout.controlBarGeo.isTwoRowBarOSC)
    }

    var isTopBarPlacementOrStyleChanging: Bool {
      // assume that if a style change is happening, it affects active panel
      // NOTE: Only 1 style is currently supported for topBar!
      return isTopBarPlacementChanging
    }

    /// Note: this may not include OSC
    var isBottomBarPlacementChanging: Bool {
      return inputLayout.bottomBarPlacement != outputLayout.bottomBarPlacement
    }

    var isBottomBarPlacementOrStyleChanging: Bool {
      // assume that if a style change is happening, it affects active panel
      return isBottomBarPlacementChanging || (outputLayout.hasBottomOSC && isOSCStyleChanging)
    }

    var isLeadingSidebarPlacementChanging: Bool {
      return inputLayout.leadingSidebarPlacement != outputLayout.leadingSidebarPlacement
    }

    var isTrailingSidebarPlacementChanging: Bool {
      return inputLayout.trailingSidebarPlacement != outputLayout.trailingSidebarPlacement
    }

    var isOpeningLeadingSidebar: Bool {
      return isOpening(.leadingSidebar)
    }

    var isOpeningTrailingSidebar: Bool {
      return isOpening(.trailingSidebar)
    }

    var isClosingLeadingSidebar: Bool {
      return isClosing(.leadingSidebar)
    }

    var isClosingTrailingSidebar: Bool {
      return isClosing(.trailingSidebar)
    }

    var isOpeningAnySidebar: Bool {
      isOpeningLeadingSidebar || isOpeningTrailingSidebar
    }

    var isOpeningOrClosingAnySidebar: Bool {
      isOpeningLeadingSidebar || isOpeningTrailingSidebar || isClosingLeadingSidebar || isClosingTrailingSidebar
    }

    /// Returns true if opening given sidebar from the closed state or from the initial state, or doing an open + close.
    func isOpening(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if (isWindowInitialLayout || !oldState.isVisible) && newState.isVisible {
        return true
      }
      return isClosingAndThenOpening(sidebarID)
    }

    /// Is closing given sidebar?
    func isClosing(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if oldState.isVisible {
        if !newState.isVisible {
          return true
        }
        if let oldVisibleTabGroup = oldState.visibleTabGroup, let newVisibleTabGroup = newState.visibleTabGroup,
           oldVisibleTabGroup != newVisibleTabGroup {
          return true
        }
        if let visibleTabGroup = oldState.visibleTabGroup, !newState.tabGroups.contains(visibleTabGroup) {
          Logger.log.error{"isClosing(sidebarID:): visibleTabGroup \(visibleTabGroup.rawValue.quoted) is not present in newState!"}
          return true
        }
      }
      return isClosingAndThenOpening(sidebarID)
    }

    func isClosingAndThenOpening(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if oldState.isVisible && newState.isVisible {
        if oldState.placement != newState.placement {
          return true
        }
        guard let oldGroup = oldState.visibleTabGroup, let newGroup = newState.visibleTabGroup else {
          Logger.log.error{"needToCloseAndReopen(sidebarID:): visibleTabGroup missing!"}
          return false
        }
        if oldGroup != newGroup {
          return true
        }
      }
      return false
    }

    var isOpeningViewport: Bool {
      !inputGeometry.isViewportShown && outputGeometry.isViewportShown
    }

    var isClosingViewport: Bool {
      inputGeometry.isViewportShown && !outputGeometry.isViewportShown
    }

    var isTogglingViewport: Bool {
      inputGeometry.isViewportShown != outputGeometry.isViewportShown
    }

    var isOpeningPlaylistInMusicMode: Bool {
      !inputGeometry.isMusicModePlaylistShown && outputGeometry.isMusicModePlaylistShown
    }

    var isClosingPlaylistInMusicMode: Bool {
      inputGeometry.isMusicModePlaylistShown && !outputGeometry.isMusicModePlaylistShown
    }

    var isTogglingPlaylistInMusicMode: Bool {
      isOpeningPlaylistInMusicMode || isClosingPlaylistInMusicMode
    }

    var ΔWindowWidth: CGFloat {
      return outputGeometry.windowFrame.width - inputGeometry.windowFrame.width
    }

    var isOpeningBarOSCFromZero: Bool {
      isWindowInitialLayout || (outputLayout.hasTopOrBottomOSC &&
                                (!inputLayout.hasTopOrBottomOSC || (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue) ||
                                 (outputLayout.hasTopOSC && isTopBarPlacementOrStyleChanging)
                                 || (outputLayout.hasBottomOSC && isBottomBarPlacementOrStyleChanging)))
    }

    /// For animation purposes only
    var isClosingBarOSC: Bool {
      guard inputLayout.hasTopOrBottomOSC else { return false }

      return !outputLayout.hasTopOrBottomOSC
      || (inputLayout.oscPosition.rawValue != outputLayout.oscPosition.rawValue)
      || (inputLayout.hasTopOSC && isTopBarPlacementOrStyleChanging)
      || (inputLayout.hasBottomOSC && isBottomBarPlacementOrStyleChanging)
    }

    var needsMpvKeepaspectUpdate: Bool {
      isWindowInitialLayout || (outputLayout.mode.needsMpvKeepaspectWindow != inputLayout.mode.needsMpvKeepaspectWindow)
    }

    // MARK: - Layout per Stage

    func logPreamble(for stage: Stage) -> String {
      "[\(name)-\(stage)]"
    }

    func geometry(for stage: Stage) -> PWinGeometry {
      switch stage {
      case .preTransitionSetup:
        return inputGeometry
      case .closeOldPanels, .midTransitionHiddenUpdates:
        return middleGeometry ?? inputGeometry
      case .openNewPanels:
        if isEnteringLegacyFullScreen && !isWindowInitialLayout && IINAAnimation.isAnimationEnabled {
          return computeExtraAnimationGeoForLegacyFS(fsGeometry: outputGeometry)
        } else {
          /// No need for extra animation. Apply final geometry.
          return outputGeometry
        }
      case .postTransition:
        return outputGeometry
      }
    }

    /// Entering or exiting
    func computeExtraAnimationGeoForLegacyFS(fsGeometry: PWinGeometry) -> PWinGeometry {
      assert(isTogglingLegacyFullScreen, "computeExtraAnimationGeoForLegacyFS should not be called unless toggling legacy full screen")
      let screen = NSScreen.getScreenOrDefault(screenID: fsGeometry.screenID)

      // Use extra animation to deal with possible top margin needed to hide camera housing
      if fsGeometry.hasTopPaddingForCameraHousing {
        /// Entering legacy FS on a screen with camera housing, but `Use entire Macbook screen` is unchecked in Settings.
        /// Prevent an unwanted bouncing near the top by using this animation to expand to visibleFrame.
        /// (If entering FS: will expand window to cover `cameraHousingHeight` in final animation)
        return fsGeometry.clone(windowFrame: screen.frameWithoutCameraHousing,
                                    screenID: screen.screenID, topMarginHeight: 0)
      } else {
        /// `Use entire Macbook screen` is checked in Settings. As of MacOS before Sonoma 14.4, Apple has been making improvements
        /// but we still need to use  a separate animation to give the OS time to show/hide the menu bar - otherwise there will be a flicker.
        let cameraHeight = screen.cameraHousingHeight ?? 0
        let margins = fsGeometry.viewportMargins.addingTo(top: -cameraHeight)
        return fsGeometry.clone(windowFrame: fsGeometry.windowFrame.addingTo(top: -cameraHeight), viewportMargins: margins, isMiddleTransition: true)
      }
    }

    // Top bar
    
    func topBarPlacement(for stage: Stage) -> Preference.PanelPlacement {
      switch stage {
      case .preTransitionSetup, .closeOldPanels:
        return inputLayout.topBarPlacement
      case .midTransitionHiddenUpdates, .openNewPanels, .postTransition:
        return outputLayout.topBarPlacement
      }
    }

    func topBarHeight(for stage: Stage) -> CGFloat {
      let geo = geometry(for: stage)
      return geo.topBarHeight
    }

    func cameraHousingOffset(for stage: Stage) -> CGFloat {
      switch stage {
      case .preTransitionSetup:
        return inputGeometry.topMarginHeight
      case .closeOldPanels, .midTransitionHiddenUpdates:
        if isExitingLegacyFullScreen {
          // Use prev offset for a smoother animation
          return inputGeometry.topMarginHeight
        } else {
          return outputGeometry.topMarginHeight
        }
      case .openNewPanels, .postTransition:
        return outputGeometry.topMarginHeight
      }
    }
    
    func topBarBtmOffsetFromVPTop(for stage: Stage) -> CGFloat {
      switch topBarPlacement(for: stage) {
      case .insideViewport:
        return topBarHeight(for: stage)
      case .outsideViewport:
        return 0
      }
    }

    func vpTopOffsetFromTopBarTop(for stage: Stage) -> CGFloat {
      switch topBarPlacement(for: stage) {
      case .insideViewport:
        return 0
      case .outsideViewport:
        return topBarHeight(for: stage)
      }
    }

    func vpTopOffsetFromCVTop(for stage: Stage) -> CGFloat {
      switch topBarPlacement(for: stage) {
      case .insideViewport:
        return 0 + cameraHousingOffset(for: stage)
      case .outsideViewport:
        return topBarHeight(for: stage) + cameraHousingOffset(for: stage)
      }
    }

    func vpBtmOffsetFromCVTop(for stage: Stage) -> CGFloat {
      let viewportHeight = geometry(for: stage).viewportSize.height
      return vpTopOffsetFromCVTop(for: stage) + viewportHeight
    }

    // Bottom bar

    func bottomBarTopOffsetFromCVTop(for stage: Stage) -> CGFloat {
      let vpBtmOffsetFromCVTop = vpBtmOffsetFromCVTop(for: stage)
      switch bottomBarPlacement(for: stage) {
      case .insideViewport:
        return vpBtmOffsetFromCVTop - bottomBarHeight(for: stage)
      case .outsideViewport:
        return vpBtmOffsetFromCVTop
      }
    }

    func bottomBarBtmOffsetFromCVTop(for stage: Stage) -> CGFloat {
      let geo = geometry(for: stage)
      return geo.windowFrame.height
    }

    func bottomBarHeight(for stage: Stage) -> CGFloat {
      let geo = geometry(for: stage)
      return geo.bottomBarHeight
    }

    func bottomBarPlacement(for stage: Stage) -> Preference.PanelPlacement {
      switch stage {
      case .preTransitionSetup, .closeOldPanels:
        return inputLayout.bottomBarPlacement
      case .midTransitionHiddenUpdates, .openNewPanels, .postTransition:
        return outputLayout.bottomBarPlacement
      }
    }

    func vpBtmOffsetFromTopOfBottomBar(for stage: Stage) -> CGFloat {
      switch bottomBarPlacement(for: stage) {
      case .insideViewport:
        return bottomBarHeight(for: stage)
      case .outsideViewport:
        return -viewportBtmSpecialOffset(for: stage)
      }
    }

    func bottomBarBtmOffsetFromVPBtm(for stage: Stage) -> CGFloat {
      switch bottomBarPlacement(for: stage) {
      case .insideViewport:
        return 0
      case .outsideViewport:
        return bottomBarHeight(for: stage) + viewportBtmSpecialOffset(for: stage)
      }
    }

    func cvBtmOffsetFromVPBtm(for stage: Stage) -> CGFloat {
      switch bottomBarPlacement(for: stage) {
      case .insideViewport:
        return 0
      case .outsideViewport:
        let bottomBarHeight = bottomBarHeight(for: stage)
        return bottomBarHeight + viewportBtmSpecialOffset(for: stage)
      }
    }

    func viewportBtmSpecialOffset(for stage: Stage) -> CGFloat {
      let inputViewportHeight = inputGeometry.viewportSize.height
      let outputViewportHeight = outputGeometry.viewportSize.height

      switch stage {
      case .preTransitionSetup, .closeOldPanels:
        if inputViewportHeight == 0 {
          return -inputGeometry.videoHeightWhenVisible
        } else {
          return 0
        }
      case .midTransitionHiddenUpdates, .openNewPanels, .postTransition:
        if outputViewportHeight == 0 {
          return -outputGeometry.videoHeightWhenVisible
        } else {
          return 0
        }
      }
    }
  }
}
