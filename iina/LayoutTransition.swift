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
  /// See `buildLayoutTransition()`, where an instance of this class is assembled.
  /// Other important variables: `currentLayout`, `windowedModeGeo`, `musicModeGeo` (in `PlayerWindowController`)
  class LayoutTransition {
    let name: String  // just used for debugging

    let inputLayout: LayoutState
    let outputLayout: LayoutState

    let inputGeometry: PWinGeometry
    var middleGeometry: PWinGeometry?
    let outputGeometry: PWinGeometry

    /// Should only be true when setting layout on session open. See `buildWindowInitialLayoutTasks()`.
    let isWindowInitialLayout: Bool

    var tasks: [IINAAnimation.Task] = []

    init(name: String, from inputLayout: LayoutState, from inputGeometry: PWinGeometry,
         to outputLayout: LayoutState, to outputGeometry: PWinGeometry,
         middleGeometry: PWinGeometry? = nil,
         isWindowInitialLayout: Bool = false) {
      self.name = name
      self.inputLayout = inputLayout
      self.inputGeometry = inputGeometry
      self.middleGeometry = middleGeometry
      self.outputLayout = outputLayout
      self.outputGeometry = outputGeometry
      self.isWindowInitialLayout = isWindowInitialLayout
    }

    // Always need to execute this step. But may not need to use an animation
    var needsAnimationForShowFadeables: Bool {
      return !outputLayout.isInteractiveMode && needsFadeOutOldViews
    }

    var needsFadeOutOldViews: Bool {
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade OUT
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
      || (inputLayout.leadingSidebarToggleButton.isShowable && !outputLayout.leadingSidebarToggleButton.isShowable)
      || (inputLayout.trailingSidebarToggleButton.isShowable && !outputLayout.trailingSidebarToggleButton.isShowable)
    }

    var needsFadeInNewViews: Bool {
      if isTogglingFullScreen { return false }
      return isTogglingLegacyStyle || isTopBarPlacementOrStyleChanging
      || (inputLayout.mode != outputLayout.mode)
      || (outputLayout.mode.isInteractiveMode)  // Needed to fade in cropBoxView again after layout update
      || (outputLayout.bottomBarPlacement == .insideViewport && isBottomBarPlacementOrStyleChanging) // fade IN
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (outputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
      || (!inputLayout.leadingSidebarToggleButton.isShowable && outputLayout.leadingSidebarToggleButton.isShowable)
      || (!inputLayout.trailingSidebarToggleButton.isShowable && outputLayout.trailingSidebarToggleButton.isShowable)
    }

    var needsCloseOldPanels: Bool {
      if isEnteringFullScreen {
        // Avoid bounciness and possible unwanted video scaling animation (not needed for ->FS anyway)
        return false
      }
      return isClosingLeadingSidebar || isClosingTrailingSidebar
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
    }

    // Always need to execute this step. But may not need to use an animation
    var needsAnimationForOpenFinalPanels: Bool {
      return (inputGeometry.topMarginHeight != outputGeometry.topMarginHeight)
      || isOpeningLeadingSidebar || isOpeningTrailingSidebar
      || isTopBarPlacementOrStyleChanging || isBottomBarPlacementOrStyleChanging
      || (inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle)
      || (inputLayout.mode != outputLayout.mode)
      || (inputLayout.topBarHeight != outputLayout.topBarHeight)
      || (inputGeometry.insideBars.bottom != outputGeometry.insideBars.bottom)
      || (inputGeometry.outsideBars.bottom != outputGeometry.outsideBars.bottom)
      || (inputLayout.enableOSC != outputLayout.enableOSC)
      || (inputLayout.enableOSC && (inputLayout.oscPosition != outputLayout.oscPosition))
    }

    var isAddingLegacyStyle: Bool {
      return !inputLayout.spec.isLegacyStyle && outputLayout.spec.isLegacyStyle
    }

    var isRemovingLegacyStyle: Bool {
      return inputLayout.spec.isLegacyStyle && !outputLayout.spec.isLegacyStyle
    }

    var isTogglingLegacyStyle: Bool {
      return inputLayout.spec.isLegacyStyle != outputLayout.spec.isLegacyStyle
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
      return isTopBarPlacementChanging // || (outputLayout.hasTopOSC && isOSCStyleChanging)
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

    lazy var isOpeningLeadingSidebar: Bool = {
      return isOpening(.leadingSidebar)
    }()

    lazy var isOpeningTrailingSidebar: Bool = {
      return isOpening(.trailingSidebar)
    }()

    lazy var isClosingLeadingSidebar: Bool = {
      return isClosing(.leadingSidebar)
    }()

    lazy var isClosingTrailingSidebar: Bool = {
      return isClosing(.trailingSidebar)
    }()

    lazy var isOpeningOrClosingAnySidebar: Bool = {
      return isOpeningLeadingSidebar || isOpeningTrailingSidebar || isClosingLeadingSidebar || isClosingTrailingSidebar
    }()

    /// Is opening given sidebar?
    func isOpening(_ sidebarID: Preference.SidebarLocation) -> Bool {
      let oldState = inputLayout.sidebar(withID: sidebarID)
      let newState = outputLayout.sidebar(withID: sidebarID)
      if !oldState.isVisible && newState.isVisible {
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

    var ΔWindowWidth: CGFloat {
      return outputGeometry.windowFrame.width - inputGeometry.windowFrame.width
    }

    var isOpeningBarOSCFromZero: Bool {
      isWindowInitialLayout || (outputLayout.hasTopOrBottomOSC &&
      (!inputLayout.hasTopOrBottomOSC || (inputLayout.oscPosition != outputLayout.oscPosition) ||
       (outputLayout.hasTopOSC && isTopBarPlacementOrStyleChanging)
       || (outputLayout.hasBottomOSC && isBottomBarPlacementOrStyleChanging)))
    }

    /// For animation purposes only
    var isClosingBarOSC: Bool {
      guard inputLayout.hasTopOrBottomOSC else { return false }

      return !outputLayout.hasTopOrBottomOSC
      || (inputLayout.oscPosition != outputLayout.oscPosition)
      || (inputLayout.hasTopOSC && isTopBarPlacementOrStyleChanging)
      || (inputLayout.hasBottomOSC && isBottomBarPlacementOrStyleChanging)
    }
  }

}
