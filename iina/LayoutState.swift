//
//  LayoutState.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `LayoutState`: data structure which contains all the variables which describe a single layout configuration of the `PlayerWindow`.
///
/// ("Layout" might have been a better name for this class, but it's already used by AppKit).
/// Notes:
///
/// • The values for most fields in this struct can be derived from IINA's application settings, although some state like active sidebar
///   tab & window mode can vary for each player window.
/// • With all the different window layout configurations which are now possible, it's crucial to use this class in order for animations
///   to work reliably.
/// • When any member variable inside it needs to be changed, a new `LayoutState` object should be constructed to describe the new state,
///   and a `LayoutTransition` should be built to construct the animations & structural changes from this `LayoutState` to the new one.
/// • The new `LayoutState`, once active, should be stored as the `currentLayout` of `PlayerWindowController`.
struct LayoutState {

  // MARK: Stored Properties

  let leadingSidebar: Sidebar
  let trailingSidebar: Sidebar

  let mode: PlayerWindowMode
  let isLegacyStyle: Bool

  let topBarPlacement: Preference.PanelPlacement
  let bottomBarPlacement: Preference.PanelPlacement
  var leadingSidebarPlacement: Preference.PanelPlacement { return leadingSidebar.placement }
  var trailingSidebarPlacement: Preference.PanelPlacement { return trailingSidebar.placement }

  /// Can only be `true` for `windowedNormal` & `fullScreenNormal` modes!
  /// This is always `false` for `musicMode` and interactive modes.
  ///
  /// To include possibility of music mode, see `hasControlBar()`.
  let enableOSC: Bool

  let oscPosition: Preference.OSCPosition
  let oscColorScheme: Preference.OSCColorScheme

  let controlBarGeo: ControlBarGeometry

  /// The mode of the interactive mode. ONLY used if `mode==.windowedInteractive || mode==.fullScreenInteractive`
  let interactiveMode: InteractiveMode?

  let moreSidebarState: Sidebar.SidebarMiscState

  /// Only applies for legacy full screen
  let hasTopPaddingForCameraHousing: Bool

  // MARK: Init / Factory

  init(leadingSidebar: Sidebar, trailingSidebar: Sidebar, mode: PlayerWindowMode, isLegacyStyle: Bool,
       topBarPlacement: Preference.PanelPlacement, bottomBarPlacement: Preference.PanelPlacement,
       enableOSC: Bool, oscPosition: Preference.OSCPosition,
       oscColorScheme: Preference.OSCColorScheme,
       controlBarGeo givenControlBarGeo: ControlBarGeometry? = nil,
       interactiveMode: InteractiveMode?,
       moreSidebarState: Sidebar.SidebarMiscState,
       hasTopPaddingForCameraHousing: Bool,
  ) {

    var mode = mode
    if (mode == .windowedInteractive || mode == .fullScreenInteractive) && interactiveMode == nil {
      Logger.log("Cannot enter interactive mode (\(mode)) because its mode field is nil! Falling back to windowed mode")
      // Prevent invalid mode from crashing IINA. Just go to windowed instead
      mode = .windowedNormal
    }
    self.mode = mode
    self.oscColorScheme = oscColorScheme

    switch mode {
    case .windowedNormal, .fullScreenNormal:
      self.leadingSidebar = leadingSidebar
      self.trailingSidebar = trailingSidebar
      self.topBarPlacement = topBarPlacement
      self.bottomBarPlacement = bottomBarPlacement
      self.enableOSC = enableOSC
      self.interactiveMode = nil

    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      // Override most properties for music mode & interactive mode
      self.leadingSidebar = leadingSidebar.clone(visibility: .closed)
      self.trailingSidebar = trailingSidebar.clone(visibility: .closed)
      self.topBarPlacement = mode == .windowedInteractive ? .outsideViewport : .insideViewport
      self.bottomBarPlacement = .outsideViewport
      self.enableOSC = false
      self.interactiveMode = interactiveMode
    }

    self.isLegacyStyle = isLegacyStyle
    self.oscPosition = oscPosition
    self.moreSidebarState = moreSidebarState
    // Should be ok to fill in most of ControlBarGeometry from prefs if not given
    let controlBarGeo = givenControlBarGeo ?? ControlBarGeometry(mode: mode, oscPosition: oscPosition)
    self.controlBarGeo = controlBarGeo

    self.hasTopPaddingForCameraHousing = hasTopPaddingForCameraHousing
  }

  /// Specify any properties to override; if nil, will use self's property values -
  /// EXCEPT for `oscColorScheme`, which is computed.
  func clone(leadingSidebar: Sidebar? = nil,
             trailingSidebar: Sidebar? = nil,
             mode: PlayerWindowMode? = nil,
             isLegacyStyle: Bool? = nil,
             topBarPlacement: Preference.PanelPlacement? = nil,
             bottomBarPlacement: Preference.PanelPlacement? = nil,
             enableOSC: Bool? = nil,
             oscPosition: Preference.OSCPosition? = nil,
             controlBarGeo: ControlBarGeometry? = nil,
             hasTopPaddingForCameraHousing: Bool? = nil,
             interactiveMode: InteractiveMode? = nil,
             moreSidebarState: Sidebar.SidebarMiscState? = nil,
  ) -> LayoutState {

    // make sure mode is consistent for self & controlBarGeo
    let controlBarGeo = controlBarGeo ?? (mode == nil ? self.controlBarGeo : self.controlBarGeo.clone(mode: mode!))

    return LayoutState(leadingSidebar: leadingSidebar ?? self.leadingSidebar,
                       trailingSidebar: trailingSidebar ?? self.trailingSidebar,
                       mode: mode ?? self.mode,
                       isLegacyStyle: isLegacyStyle ?? self.isLegacyStyle,
                       topBarPlacement: topBarPlacement ?? self.topBarPlacement,
                       bottomBarPlacement: bottomBarPlacement ?? self.bottomBarPlacement,
                       enableOSC: enableOSC ?? self.enableOSC,
                       oscPosition: self.oscPosition,
                       oscColorScheme: self.oscColorScheme,
                       controlBarGeo: controlBarGeo,
                       interactiveMode: interactiveMode ?? self.interactiveMode,
                       moreSidebarState: moreSidebarState ?? self.moreSidebarState,
                       hasTopPaddingForCameraHousing: hasTopPaddingForCameraHousing ?? self.hasTopPaddingForCameraHousing)
  }

  func withSidebarsHidden() -> LayoutState {
    return clone(leadingSidebar: leadingSidebar.clone(visibility: .closed),
                 trailingSidebar: trailingSidebar.clone(visibility: .closed))
  }

  // MARK: - Computed Properties

  // - Visibility of views/categories

  var titleBar: VisibilityMode {
    switch mode {
    case .fullScreenNormal, .fullScreenInteractive, .musicMode:
      return .hidden
    case .windowedInteractive:
      return .showAlways
    case .windowedNormal:
      return topBarPlacement == .insideViewport ? .showFadeableTopBar : .showAlways
    }
  }

  var titleIconAndText: VisibilityMode { titleBar }
  var trafficLightButtons: VisibilityMode { titleBar }
  var titlebarAccessoryViewControllers: VisibilityMode { isLegacyStyle ? .hidden : titleBar }

  /// LeadingSidebar toggle button.
  ///
  /// Warning! This property can vary according to the value cooresponding to
  /// `Preference.Key.showLeadingSidebarToggleButton` and is not cached or persisted (so far there has been no need).
  var leadingSidebarToggleButton: VisibilityMode {
    let hasLeadingSidebar = mode.canShowSidebars && !leadingSidebar.tabGroups.isEmpty
    return hasLeadingSidebar && Preference.bool(for: .showLeadingSidebarToggleButton) ? titleBar : .hidden
  }

  /// TrailingSidebar toggle button.
  ///
  /// Warning! This property can vary according to the value cooresponding to
  /// `Preference.Key.showTrailingSidebarToggleButton` and is not cached or persisted (so far there has been no need).
  var trailingSidebarToggleButton: VisibilityMode {
    let hasTrailingSidebar = mode.canShowSidebars && !trailingSidebar.tabGroups.isEmpty
    return hasTrailingSidebar && Preference.bool(for: .showTrailingSidebarToggleButton) ? titleBar : .hidden
  }

  var bottomBarView: VisibilityMode {
    switch mode {
    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      return .showAlways
    case .windowedNormal, .fullScreenNormal:
      if hasBottomOSC {
        return (bottomBarPlacement == .insideViewport) ? .showFadeableNonTopBar : .showAlways
      }
      return .hidden
    }
  }

  var topBarView: VisibilityMode {
    if hasTopOSC {
      if topBarPlacement == .outsideViewport {
        return .showAlways
      } else if titleBar.isShowable {
        // Match value from above
        return titleBar
      } else {
        return .showFadeableTopBar
      }
    }
    return titleBar
  }


  var controlBarFloating: VisibilityMode {
    // floating is always fadeable if shown at all
    hasFloatingOSC ? .showFadeableNonTopBar : .hidden
  }

  // - Sizes / offsets

  var titleBarHeight: CGFloat {
    if titleBar.isShowable {
      if hasTopOSC {
        // Reduce title height a bit because it will share space with OSC
        return Constants.Distance.reducedTitleBarHeight
      }
      return Constants.Distance.standardTitleBarHeight
    }
    return 0
  }

  var topOSCHeight: CGFloat {
    if hasTopOSC {
      return controlBarGeo.barHeight
    }
    return 0
  }

  var bottomBarHeight: CGFloat {
    if mode.isInteractiveMode {
      return Constants.InteractiveMode.outsideBottomBarHeight
    }
    if isMusicMode {
      // Unspecified! We do not have this information!
      return -1
    }
    if hasBottomOSC {
      return controlBarGeo.barHeight
    }
    return 0
  }

  var insideLeadingBarWidth: CGFloat {
    if leadingSidebar.placement == .insideViewport, let visibleTabGroup = leadingSidebar.visibleTabGroup {
      return visibleTabGroup.width(using: moreSidebarState)
    }
    return 0
  }

  var insideTrailingBarWidth: CGFloat {
    if trailingSidebar.placement == .insideViewport, let visibleTabGroup = trailingSidebar.visibleTabGroup {
      return visibleTabGroup.width(using: moreSidebarState)
    }
    return 0
  }

  var outsideTrailingBarWidth: CGFloat {
    if trailingSidebar.placement == .outsideViewport, let visibleTabGroup = trailingSidebar.visibleTabGroup {
      return visibleTabGroup.width(using: moreSidebarState)
    }
    return 0
  }

  var outsideLeadingBarWidth: CGFloat {
    if leadingSidebar.placement == .outsideViewport, let visibleTabGroup = leadingSidebar.visibleTabGroup {
      return visibleTabGroup.width(using: moreSidebarState)
    }
    return 0
  }

  var isInteractiveMode: Bool {
    return mode.isInteractiveMode
  }

  var isFullScreen: Bool {
    return mode.isFullScreen
  }

  var isWindowed: Bool {
    return mode.isWindowed
  }

  var isNativeFullScreen: Bool {
    return isFullScreen && !isLegacyStyle
  }

  var isLegacyFullScreen: Bool {
    return isFullScreen && isLegacyStyle
  }

  var hasPermanentControlBar: Bool {
    if mode == .musicMode {
      return true
    }
    return enableOSC && ((oscPosition == .top && topBarPlacement == .outsideViewport) ||
                         (oscPosition == .bottom && bottomBarPlacement == .outsideViewport))
  }

  var hasBottomOSC: Bool {
    return enableOSC && oscPosition == .bottom
  }

  var hasTopOrBottomOSC: Bool {
    return enableOSC && (oscPosition == .top || oscPosition == .bottom)
  }

  var effectiveOSCColorScheme: Preference.OSCColorScheme {
    if hasBottomOSC && bottomBarPlacement == .insideViewport {
      return oscColorScheme
    }
    return .visualEffectView
  }

  /// Has OSC with clear background.
  ///
  /// Equivalent to `effectiveOSCColorScheme == .clearGradient`.
  var oscBackgroundIsClear: Bool {
    return effectiveOSCColorScheme == .clearGradient
  }

  var canShowSidebars: Bool {
    mode.canShowSidebars
  }

  var isLeadingSidebarVisible: Bool {
    leadingSidebar.isVisible
  }

  var isTrailingSidebarVisible: Bool {
    trailingSidebar.isVisible
  }

  var isAnySidebarVisible: Bool {
    leadingSidebar.isVisible || trailingSidebar.isVisible
  }

  var topBarHeight: CGFloat {
    titleBarHeight + topOSCHeight
  }

  var hasTopBar: Bool {
    topBarHeight > 0
  }

  var hasBottomBar: Bool {
    bottomBarView.isShowable
  }

  /// - Bar widths/heights IF `.outsideViewport`

  var outsideTopBarHeight: CGFloat {
    return topBarPlacement == .outsideViewport ? topBarHeight : 0
  }

  var outsideBottomBarHeight: CGFloat {
    return bottomBarPlacement == .outsideViewport ? bottomBarHeight : 0
  }

  var outsideBars: MarginQuad {
    return MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                      bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)
  }

  /// - Bar widths/heights IF `.insideViewport`

  var insideTopBarHeight: CGFloat {
    return topBarPlacement == .insideViewport ? topBarHeight : 0
  }

  var insideBottomBarHeight: CGFloat {
    return bottomBarPlacement == .insideViewport ? bottomBarHeight : 0
  }

  var insideBars: MarginQuad {
    return MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                      bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)
  }

  // - Other computed properties

  var canEnterInteractiveMode: Bool {
    return mode == .windowedNormal || mode == .fullScreenNormal
  }

  var hasAdditionalInfo: Bool {
    isFullScreen && Preference.bool(for: .displayTimeAndBatteryInFullScreen)
  }

  var isMusicMode: Bool {
    return mode == .musicMode
  }

  /// Only windowed & full screen modes can have floating OSC, and OSC must be enabled
  var hasFloatingOSC: Bool {
    return enableOSC && oscPosition == .floating
  }

  var hasTopOSC: Bool {
    return enableOSC && oscPosition == .top
  }

  var hasControlBar: Bool {
    return isMusicMode || enableOSC
  }

  var hasFadeableOSC: Bool {
    return enableOSC && (oscPosition == .floating ||
                         (oscPosition == .top && topBarView.isFadeable) ||
                         (oscPosition == .bottom && bottomBarView.isFadeable))
  }

  /// Whether PlaySlider & VolumeSlider should change height when in focus (on mouse hover or during scroll)
  var useSliderFocusEffect: Bool {
    return mode == .musicMode || (enableOSC && (oscPosition == .top || oscPosition == .bottom))
  }

  var playlistShown: Bool {
    if isMusicMode {
      return outsideBottomBarHeight > Constants.Distance.MusicMode.oscHeight
    } else {
      return leadingSidebar.visibleTab == .playlist || trailingSidebar.visibleTab == .playlist
    }
  }

  // MARK: Utility Functions

  func sidebar(withID id: Preference.SidebarLocation) -> Sidebar {
    switch id {
    case .leadingSidebar:
      return leadingSidebar
    case .trailingSidebar:
      return trailingSidebar
    }
  }

  func computeOnTopButtonVisibility(isOnTop: Bool) -> VisibilityMode {
    let showOnTopStatus = Preference.bool(for: .alwaysShowOnTopIcon) || isOnTop
    if isFullScreen || isMusicMode || !showOnTopStatus {
      return .hidden
    }

    if topBarPlacement == .insideViewport {
      return .showFadeableNonTopBar
    }

    return .showAlways
  }

  /// Returns `true` if `otherSpec` has the same values which are configured from IINA app-wide prefs
  func hasSamePrefsValues(as otherSpec: LayoutState) -> Bool {
    return otherSpec.enableOSC == enableOSC
    && otherSpec.oscPosition == oscPosition
    && otherSpec.isLegacyStyle == isLegacyStyle
    && otherSpec.topBarPlacement == topBarPlacement
    && otherSpec.bottomBarPlacement == bottomBarPlacement
    && otherSpec.leadingSidebarPlacement == leadingSidebarPlacement
    && otherSpec.trailingSidebarPlacement == trailingSidebarPlacement
    && otherSpec.leadingSidebar.tabGroups == leadingSidebar.tabGroups
    && otherSpec.trailingSidebar.tabGroups == trailingSidebar.tabGroups
    && otherSpec.moreSidebarState.playlistSidebarWidth == moreSidebarState.playlistSidebarWidth
  }

  // MARK: Static

  /// Factory method. Fills in most from app singleton preferences, and the rest from default values.
  static func fromPrefsAndDefaults() -> LayoutState {
    return fromPreferences()
  }

  /// Factory method. Init from preferences, except for `mode` and tab params
  static func fromPreferences(andMode newMode: PlayerWindowMode? = nil,
                              isLegacyStyle: Bool? = nil,
                              fillingInFrom oldSpec: LayoutState? = nil) -> LayoutState {

    let oldLeadingSidebar = oldSpec?.leadingSidebar
    let oldTrailingSidebar = oldSpec?.trailingSidebar

    let leadingSidebar =  Sidebar(.leadingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .leadingSidebar),
                                  placement: Preference.enum(for: .leadingSidebarPlacement),
                                  visibility: oldLeadingSidebar?.visibility ?? .closed,
                                  lastVisibleTab: oldLeadingSidebar?.lastVisibleTab)
    let trailingSidebar = Sidebar(.trailingSidebar,
                                  tabGroups: Sidebar.TabGroup.fromPrefs(for: .trailingSidebar),
                                  placement: Preference.enum(for: .trailingSidebarPlacement),
                                  visibility: oldTrailingSidebar?.visibility ?? .closed,
                                  lastVisibleTab: oldTrailingSidebar?.lastVisibleTab)
    let mode = newMode ?? oldSpec?.mode ?? .windowedNormal
    // Tricky need for parantheses here! Would be great as an interview question
    let isLegacyStyle = isLegacyStyle ?? (mode.isFullScreen ? Preference.bool(for: .useLegacyFullScreen) : Preference.bool(for: .useLegacyWindowedMode))
    let interactiveMode = mode.isInteractiveMode ? oldSpec?.interactiveMode ?? InteractiveMode.crop : nil

    let isLegacyFullScreen = mode.isFullScreen && isLegacyStyle
    let hasTopPaddingForCameraHousing = isLegacyFullScreen && !Preference.bool(for: .allowVideoToOverlapCameraHousing)
    return LayoutState(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar,
                       mode: mode,
                       isLegacyStyle: isLegacyStyle,
                       topBarPlacement: Preference.enum(for: .topBarPlacement),
                       bottomBarPlacement: Preference.enum(for: .bottomBarPlacement),
                       enableOSC: Preference.bool(for: .enableOSC),
                       oscPosition: Preference.enum(for: .oscPosition),
                       oscColorScheme: effectiveOSCColorSchemeFromPrefs,
                       interactiveMode: interactiveMode,
                       moreSidebarState: oldSpec?.moreSidebarState ?? Sidebar.SidebarMiscState.fromDefaultPrefs(),
                       hasTopPaddingForCameraHousing: hasTopPaddingForCameraHousing)
  }

  static var effectiveOSCColorSchemeFromPrefs: Preference.OSCColorScheme {
    if Preference.bool(for: .enableOSC), Preference.enum(for: .oscPosition) == Preference.OSCPosition.bottom,
       Preference.enum(for: .bottomBarPlacement) == Preference.PanelPlacement.insideViewport {
      return Preference.enum(for: .oscColorScheme)
    }
    return .visualEffectView
  }

  // MARK: - Geometry

  /// Converts & updates existing geometry to this layout.
  ///
  /// Useful when restoring a saved layout and ironing out any inconsistencies between the given `PWinGeometry` & this `LayoutState`.
  func convertWindowedModeGeometry(from existingGeometry: PWinGeometry, video: VideoGeometry? = nil, pinWidthOrHeightIfAtMax: Bool,
                                   applyOffsetIndex offsetIndex: Int = 0, _ log: Logger.Subsystem) -> PWinGeometry {
    assert(existingGeometry.mode.isWindowed, "Expected existingGeometry to be windowed: \(existingGeometry)")
    let insideBars = insideBars
    let outsideBars = outsideBars
    let resizedBarsGeo = existingGeometry.withResizedBars(outsideTop: outsideBars.top,
                                                          outsideTrailing: outsideBars.trailing,
                                                          outsideBottom: outsideBars.bottom,
                                                          outsideLeading: outsideBars.leading,
                                                          insideTop: insideBars.top,
                                                          insideTrailing: insideBars.trailing,
                                                          insideBottom: insideBars.bottom,
                                                          insideLeading: insideBars.leading,
                                                          video: video,
                                                          pinWidthOrHeightIfAtMax: pinWidthOrHeightIfAtMax).refitted()

    var geo = resizedBarsGeo
    if offsetIndex > 0 {
      let screenVisibleFrame: NSRect = geo.getContainerFrame(screenFit: .stayInside)!
      let offsetIncrement = Constants.Distance.multiWindowOpenOffsetIncrement
      for _ in 1...offsetIndex {
        var newWindowFrame = NSRect(origin: NSPoint(x: geo.windowFrame.origin.x + offsetIncrement,
                                                    y: geo.windowFrame.origin.y - offsetIncrement),
                                    size: geo.windowFrame.size)
        let x = newWindowFrame.maxX > screenVisibleFrame.maxX ? 0 : newWindowFrame.minX
        let y = newWindowFrame.minY < screenVisibleFrame.minY ? screenVisibleFrame.maxY - newWindowFrame.height : newWindowFrame.minY
        newWindowFrame = NSRect(origin: NSPoint(x: x, y: y), size: geo.windowFrame.size)
        // TODO: be more sophisticated
        geo = geo.clone(windowFrame: newWindowFrame).refitted(using: .stayInside)
      }
      log.verbose{"Applied windowedGeo offsetIndex=\(offsetIndex) for multi-window open: \(resizedBarsGeo.windowFrame) → \(geo.windowFrame)"}
    }
    return geo
  }

  func buildFullScreenGeometry(inScreenID screenID: String, _ video: VideoGeometry) -> PWinGeometry {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    return buildFullScreenGeometry(in: screen, video)
  }

  /// Builds a new `PWinGeometry` from this `LayoutState` using the given params.
  func buildFullScreenGeometry(in screen: NSScreen, _ video: VideoGeometry) -> PWinGeometry {
    var modeToUse = mode
    if !modeToUse.isFullScreen {
      // Try to use analogue of last windowed mode.
      if modeToUse == .windowedNormal {
        modeToUse  = .fullScreenNormal
      } else if modeToUse == .windowedInteractive {
        modeToUse = .fullScreenInteractive
      }
      Logger.log.warn("Cannot build full screen geometry for non-FS mode (\(mode)); will use best guess: \(modeToUse)")
      modeToUse = .fullScreenNormal
    }
    return PWinGeometry.forFullScreen(in: screen, legacy: isLegacyStyle, mode: modeToUse,
                                      outsideBars: outsideBars,
                                      insideBars: insideBars,
                                      video: video,
                                      hasTopPaddingForCameraHousing: hasTopPaddingForCameraHousing)
  }

  /// Builds a new `PWinGeometry` from this `LayoutState` using the given params.
  /// Works for all modes.
  func buildGeometry(usingMode modeOverride: PlayerWindowMode? = nil,
                     windowFrame: NSRect, screenID: String, _ video: VideoGeometry) -> PWinGeometry {
    let mode = modeOverride ?? mode
    switch mode {
    case .fullScreenNormal, .fullScreenInteractive:
      return buildFullScreenGeometry(inScreenID: screenID, video)
    case .windowedInteractive:
      return PWinGeometry.buildInteractiveModeWindow(windowFrame: windowFrame, screenID: screenID, video: video)
    case .windowedNormal:
      let geo = PWinGeometry(windowFrame: windowFrame, screenID: screenID, screenFit: .stayInside,
                             mode: mode,
                             topMarginHeight: 0,  // is only nonzero when in legacy FS
                             outsideBars: outsideBars,
                             insideBars: insideBars,
                             video: video)
      return geo.scalingViewport()
    case .musicMode:
      let geo = PWinGeometry.forMusicMode(windowFrame: windowFrame, screenID: screenID, video: video,
                                          isViewportShown: Preference.bool(for: .musicModeShowAlbumArt),
                                          playlistShown: Preference.bool(for: .musicModeShowPlaylist))
      return geo
    }

  }

  /// Only for windowed modes!
  func buildDefaultInitialGeometry(screen: NSScreen, video: VideoGeometry? = nil) -> PWinGeometry {
    let videoGeo = video ?? VideoGeometry.defaultGeometry()
    let videoSize = videoGeo.videoSizeRaw
    let windowFrame = NSRect(origin: CGPoint.zero, size: videoSize)
    let geo = buildGeometry(windowFrame: windowFrame, screenID: screen.screenID, videoGeo)
    return geo.refitted(using: .centerInside)
  }


}  // end class LayoutState
