//
//  PWin_LayoutTxSteps.swift
//  iina
//
//  Created by Matt Svoboda on 10/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// This file contains tasks to run in the animation queue, which form a `LayoutTransition`.
/// Each task is a separate `CATransaction`. Some tasks are assumed to have animations (although they can also be run immediately),
/// but others are expected to always be immediate.
extension PlayerWindowController {

  /// -------------------------------------------------
  /// PRE TRANSITION
  /// Setup work. Always immediate (i.e., not animated).
  func doPreTransitionWork(_ transition: LayoutTransition) {
    log.verbose{"[\(transition.name)] DoPreTransitionWork"}
    isAnimatingLayoutTransition = true
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to/from full screen mode.
    videoView.enterAsynchronousMode()
    videoView.displayActive()

    /// Some methods where reference `currentLayout` get called as a side effect of the transition animations.
    /// To avoid possible bugs as a result, let's update this at the very beginning.
    currentLayout = transition.outputLayout

    if !player.isRestoring {
      if !transition.outputLayout.isWindowed && transition.inputLayout.isWindowed {
        /// `inputGeometry` may contain the most up-to-date `windowFrame` for `windowedModeGeo`, which `windowedModeGeo` does not have.
        /// Make sure to save it for later use, or later references may use an older version which the user will not expect
        windowedModeGeo = transition.inputGeometry
      } else if !transition.outputLayout.isMusicMode && transition.inputLayout.isMusicMode {
        // Ditto with musicMode
        musicModeGeo = transition.inputGeometry
      }

      /// Set this here because we are setting `currentLayout`
      switch transition.outputLayout.mode {
      case .windowedNormal, .windowedInteractive:
        windowedModeGeo = transition.outputGeometry
      case .fullScreenNormal, .fullScreenInteractive:
        break  // Not applicable
      case .musicMode:
        musicModeGeo = transition.outputGeometry
      }
    }

    guard let window = window else { return }

    if transition.outputLayout.isInteractiveMode || transition.outputLayout.isFullScreen {
      // Disable; can cause problems in interactive mode. Set this ASAP because there is sometimes a small delay
      window.isMovableByWindowBackground = false
    }

    // Skip for initial layout: not all panels have been init'd yet.
    // Don't use with legacy full screen transitions; they use extra animations which will be screwed up
    if !transition.isWindowInitialLayout {
      rebuildPanelConstraints(transition, stage: .preTransitionSetup)
    }

    // Need to call this here to avoid border being drawn incorrectly during FS transition.
    // But don't want to interfere with special effects such as fade-in
    let opacity = window.contentView?.layer?.opacity ?? -1
    updateWindowBorderAndOpacity(using: transition.outputLayout, windowOpacity: opacity)

    if transition.isEnteringFullScreen {
      /// `windowedModeGeo` should already be kept up to date. Might be hard to track down bugs...
      log.verbose{"[\(transition.name)] Entering full screen; priorWindowedGeometry = \(windowedModeGeo)"}

      // Hide traffic light buttons & title during the animation.
      // Do not move this block. It needs to go here.
      hideNativeTitleBarViews(andSetAlpha: true)

      if #unavailable(macOS 10.14) {
        // Set the appearance to match the theme so the title bar matches the theme
        let iinaTheme = Preference.enum(for: .themeMaterial) as Preference.Theme
        switch(iinaTheme) {
        case .dark, .ultraDark:
          window.appearance = NSAppearance(named: .vibrantDark)
        default: 
          window.appearance = NSAppearance(named: .vibrantLight)
        }
      }

      setWindowFloatingOnTop(false, from: transition.inputLayout, updateOnTopStatus: false)

      if transition.outputLayout.isLegacyFullScreen {
        // stylemask
        let hasTitled = window.styleMask.contains(.titled)
        log.verbose{"[\(transition.name)] Entering legacy FS\(hasTitled ? ": removing window styleMask: .titled" : "")"}
        if #available(macOS 10.16, *) {
          if hasTitled {
            window.styleMask.remove(.titled)
          }
          window.styleMask.insert(.borderless)
        } else {
          window.styleMask.insert(.fullScreen)
        }

        window.styleMask.remove(.resizable)

        // auto hide menubar and dock (this will freeze all other animations, so must do it last)
        updatePresentationOptions(windowIsLegacyFS: true)

        /// When restoring, it's possible this window is not actually topmost.
        /// Make sure to check before putting it on top.
        refreshKeyWindowStatus()
      }
      if !player.isStopping {
        player.mpv.setFlag(MPVOption.Window.fullscreen, true)
        player.didEnterFullScreenViaUserToggle = true
      }

    } else if transition.isExitingFullScreen {
      // Exiting Full Screen
      fadeableViews.applyVisibility(.hidden, to: additionalInfoView)

      if transition.inputLayout.isNativeFullScreen {
        // Hide traffic light buttons & title during the animation:
        hideNativeTitleBarViews(andSetAlpha: true)
      }

      if !player.isStopping {
        player.mpv.setFlag(MPVOption.Window.fullscreen, false)
        player.didEnterFullScreenViaUserToggle = false
      }
    }

    // Apply workaround for edge case when both sidebars are "outside" and visible, then one is opened or closed.
    // Need extra checks here so that the workaround isn't also applied when switching sidebar from "inside" to "outside".
    if transition.inputLayout.leadingSidebar.isVisible, transition.inputLayout.leadingSidebar.placement == .outsideViewport,
       transition.inputLayout.trailingSidebar.isVisible, transition.inputLayout.trailingSidebar.placement == .outsideViewport {
      prepareDepthOrderOfOutsideSidebarsForToggle(transition)
    }

    // Interactive mode
    if transition.isEnteringInteractiveMode {
      isPausedPriorToInteractiveMode = player.info.isPaused
      player.pause()
    }

    // Music mode
    if transition.isExitingMusicMode {
      // Make sure to restore video
      if !transition.inputGeometry.isViewportShown {
        // Video was disabled in music mode, but need to restore it now
        player.setVideoTrackEnabled()
      }
    }

    if transition.outputLayout.isMusicMode {
      if transition.isClosingViewport {
        // Hiding video
        // Remove OSD & AdditionalInfo *before* reducing viewportView height to 0
        addOrRemoveOSDViews(transition.outputGeometry)

        // [MusicModeKludge-A] Loosen constraints manually *before* the animation task below
        videoView.videoViewConstraints?.aspectRatio.isActive = false
      }
    }

    if transition.isWindowInitialLayout {
      // Reset other views to initial minimums:
      speedLabelBtmConstraint.isActive = false

      /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
      /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
      /// notch and the preference `allowVideoToOverlapCameraHousing` is false. Also needed so that sidebars don't
      /// bleed through during their show/hide animations.
      setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)
    }
  }

  /// -------------------------------------------------
  /// FADE OUT OLD VIEWS
  /// Expected to be animated.
  func fadeOutOldViews(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    log.verbose{"[\(transition.name)] FadeOutOldViews"}

    fadeableViews.clearFadeableSets()

    // Title bar & title bar accessories:

    let needToHideTopBar = transition.isTopBarPlacementOrStyleChanging || transition.isTogglingLegacyStyle || transition.isTogglingInteractiveMode

    // Hide all title bar items if top bar placement is changing
    if needToHideTopBar || outputLayout.titleBar == .hidden {
      // Native & custom title bar components
      fadeableViews.applyVisibility(.hidden, documentIconButton, titleTextField, customTitleBar?.view)

      // native windowed or full screen
      for button in trafficLightButtons {
        button.alphaValue = 0
      }
    }

    if needToHideTopBar || outputLayout.titlebarAccessoryViewControllers == .hidden {
      // Hide all title bar accessories (if needed):
      leadingTitleBarAccessoryView.alphaValue = 0
      trailingTitleBarAccessoryView.alphaValue = 0
    } else {
      /// We may have gotten here in response to one of these buttons' visibility being toggled in the prefs,
      /// so we need to allow for showing/hiding these individually.
      /// Setting `.isHidden = true` for these icons visibly messes up their layout.
      /// So just set alpha value for now, and hide later in `updateHiddenViewsAndConstraints()`
      if outputLayout.leadingSidebarToggleButton == .hidden {
        leadingSidebarToggleButton.alphaValue = 0

        // Match behavior for custom title bar's copy:
        if let customTitleBar {
          customTitleBar.leadingSidebarToggleButton.alphaValue = 0
        }
      }
      if outputLayout.trailingSidebarToggleButton == .hidden {
        trailingSidebarToggleButton.alphaValue = 0

        if let customTitleBar {
          customTitleBar.trailingSidebarToggleButton.alphaValue = 0
        }
      }

      let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)
      if onTopButtonVisibility == .hidden {
        onTopButton.alphaValue = 0

        if let customTitleBar {
          customTitleBar.onTopButton.alphaValue = 0
        }
      }
    }

    if transition.inputLayout.hasFloatingOSC && !outputLayout.hasFloatingOSC {
      // Hide floating OSC
      fadeableViews.applyVisibility(outputLayout.controlBarFloating, to: controlBarFloating)
    }

    // Change blending modes
    if transition.isTogglingFullScreen {
      /// Need to use `.withinWindow` during animation or else panel tint can change in odd ways
      topBarView.blendingMode = .withinWindow
      if let bottomBarView = bottomBarView as? NSVisualEffectView {
        bottomBarView.blendingMode = .withinWindow
      }
      leadingSidebarView.blendingMode = .withinWindow
      trailingSidebarView.blendingMode = .withinWindow
    }

    if transition.isTogglingMusicMode || transition.isTogglingInteractiveMode {
      hideOSD()
    }

    if outputLayout.mode == .fullScreenInteractive {
      fadeableViews.applyVisibility(.hidden, to: additionalInfoView)
    }

    if transition.isExitingInteractiveMode, let cropController = self.cropSettingsView {
      cropController.view.alphaValue = 0
      cropController.view.isHidden = true
      cropController.cropBoxView.isHidden = true
      cropController.cropBoxView.alphaValue = 0
      // Need to remove these ASAP. Their constraints can interfere with window resize animation (e.g. during crop).
      removeCropControls()
    }

    // Hide seek preview for mode transitions or large animations
    let isChangingMode = transition.outputLayout.mode != transition.inputLayout.mode
    if isChangingMode || transition.isTopBarPlacementOrStyleChanging ||
        transition.isBottomBarPlacementOrStyleChanging || transition.isOpeningOrClosingAnySidebar {
      hideSeekPreviewImmediately()
    }

    if outputLayout.isInteractiveMode || outputLayout.isMusicMode {
      // Fade out OSC
      if !outputLayout.enableOSC || outputLayout.controlBarGeo.isTwoRowBarOSC {
        if oscOneRowView.superview != nil {
          log.verbose{"[\(transition.name)] Removing oscOneRowView from window"}
          oscOneRowView.dispose()
        }
      }
      if !outputLayout.enableOSC || !outputLayout.controlBarGeo.isTwoRowBarOSC {
        if oscTwoRowView.superview != nil {
          log.verbose{"[\(transition.name)] Removing oscTwoRowView from window"}
          oscTwoRowView.dispose()
        }
      }
    }
  }

  /// -------------------------------------------------
  /// CLOSE OLD PANELS
  /// This step is not always executed (e.g.: not for initial layout or for full screen toggle).
  /// Expected to be animated.
  func closeOldPanels(_ transition: LayoutTransition) {
    assert(!transition.isWindowInitialLayout)
    let log = log.withPreamble(transition.logPreamble(for: .closeOldPanels))
    let outputLayout = transition.outputLayout
    let isClosingBarOSC = transition.isClosingBarOSC
    let isOpeningBarOSC = transition.isOpeningBarOSCFromZero
    log.verbose{"Start: title_H=\(outputLayout.titleBarHeight) topOSC_H=\(outputLayout.topOSCHeight) isClosingBarOSC=\(isClosingBarOSC.yn) isOpeningBarOSC=\(isOpeningBarOSC.yn) hasControlBar=\(outputLayout.hasControlBar.yn)"}

    // TODO: incorporate this into middleGeometry for cleaner code
    if isOpeningBarOSC || isClosingBarOSC {
      // Shrink all the buttons vertically to create cool animated effect.
      // Don't worry about horizontal.
      for toolbarItem in fragToolbarView.views {
        (toolbarItem as! OSCToolbarButton).setStyle(iconSize: 0, iconSpacing: 0)
      }

      // Volume icon
      volumeIconHeightConstraint.animateToConstant(0)
      // Play & arrow buttons
      playBtnHeightConstraint.animateToConstant(0)
      arrowBtnWidthConstraint.animateToConstant(0)
      fragPlaybackBtnsHeightConstraint.animateToConstant(0)
      playSliderHeightConstraint.animateToConstant(0)

    } else if outputLayout.hasControlBar {
      // Reduce size of icons if they are smaller. This is needed to look pleasant when panels are also shrinking.
      let oldGeo = transition.inputLayout.controlBarGeo
      let newGeo = outputLayout.controlBarGeo

      // - Vertical

      if oldGeo.volumeIconHeight > newGeo.volumeIconHeight {
        volumeIconHeightConstraint.animateToConstant(newGeo.volumeIconHeight)
      }

      if oldGeo.volumeSliderWidth > newGeo.volumeSliderWidth {
        volumeSliderWidthConstraint.animateToConstant(newGeo.volumeSliderWidth)
      }

      if let img = muteButton.image {
        volumeIconAspectConstraint.isActive = false
        volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
        volumeIconAspectConstraint.isActive = true
      }

      if oldGeo.playIconSize > newGeo.playIconSize {
        playBtnHeightConstraint.animateToConstant(newGeo.playIconSize)
      }

      if oldGeo.fullIconHeight > newGeo.fullIconHeight {
        fragPlaybackBtnsHeightConstraint.animateToConstant(newGeo.fullIconHeight)
      }

      if transition.inputLayout.controlBarGeo.playSliderHeight > outputLayout.controlBarGeo.playSliderHeight {
        playSliderHeightConstraint.animateToConstant(outputLayout.controlBarGeo.playSliderHeight)
      }

      // - Horizontal

      if oldGeo.arrowIconHeight > newGeo.arrowIconHeight {
        arrowBtnWidthConstraint.animateToConstant(newGeo.arrowIconWidth)
      }

      if oldGeo.totalPlayControlsWidth > newGeo.totalPlayControlsWidth {
        fragPlaybackBtnsWidthConstraint.animateToConstant(newGeo.totalPlayControlsWidth)
      }

      // `leftArrowCenterXOffset` is always negative! Need to reverse sign.
      if oldGeo.leftArrowCenterXOffset < newGeo.leftArrowCenterXOffset {
        leftArrowBtn_CenterXOffsetConstraint.animateToConstant(newGeo.leftArrowCenterXOffset)
      }

      if oldGeo.rightArrowCenterXOffset > newGeo.rightArrowCenterXOffset {
        rightArrowBtn_CenterXOffsetConstraint.animateToConstant(newGeo.rightArrowCenterXOffset)
      }

      let toolSize = min(newGeo.toolIconSize, oldGeo.toolIconSize)
      let toolSpacing = min(newGeo.toolIconSpacing, oldGeo.toolIconSpacing)
      for toolbarItem in fragToolbarView.views {
        (toolbarItem as! OSCToolbarButton).setStyle(iconSize: toolSize, iconSpacing: toolSpacing)
      }
      updateToolbarHStack(iconSpacing: toolSpacing)
    }

    // - Middle Geometry

    if let middleGeo = transition.middleGeometry {
      if transition.outputLayout.hasFloatingOSC && !transition.isExitingFullScreen {
        controlBarFloating.moveToLocationRatio(parentGeo: middleGeo)
      }

      // Do not do this when first opening the window though, because it will cause the window location restore to be incorrect.
      // Also do not apply when toggling fullscreen because it is not relevant at this stage and will look glitchy because the
      // animation has zero duration.
      log.debug{"Applying middleGeo windowFrame=\(middleGeo.windowFrame)"}
      if transition.isTogglingMusicMode {
        // Don't add or remove aspect constraint while animating music mode toggle!
        setFrameAndUpdateWindowSubviews(using: middleGeo, updateVideoView: false)
      } else if !transition.isTogglingFullScreen {
        setFrameAndUpdateWindowSubviews(using: middleGeo, updateVideoView: true)
      }
    }
    
    rebuildPanelConstraints(transition, stage: .closeOldPanels)
  }

  /// -------------------------------------------------
  /// MIDPOINT: MOVE & RESIZE VIDEO FRAME
  /// Only executed for certain transitions (windowed mode <-> either music mode or interactive mode).
  /// All bars are expected to be closed at this point, leaving only the viewportView.
  /// This animation moves & resizes the video frame for a nice effect.
  /// May execute either before or after `updateHiddenViewsAndConstraints`.
  func moveAndScaleVideoFrame(_ transition: LayoutTransition) {
    let logPre = transition.logPreamble(for: .moveAndScale)
    let geo = transition.middleGeometry2!
    log.verbose{"\(logPre) Moving & scaling video window to middleGeo2=\(geo)"}

    // For some reason, updating videoView constraints here causes a visual glich, so skip it (updateVideoView: false).
    // It's not needed until the next step anyway.
    setFrameAndUpdateWindowSubviews(using: geo, updateVideoView: false)
    rebuildPanelConstraints(transition, stage: .moveAndScale)
  }

  /// -------------------------------------------------
  /// MIDPOINT: UPDATE INVISIBLES
  /// This is needed as its own transaction in case constraints need to be replaced or views need to be added or replaced in the window such that
  /// there is not an appropriate animation which should be seen.
  func updateHiddenViewsAndConstraints(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let logPre = transition.logPreamble(for: .midTransitionHiddenUpdates)
    let outputLayout = transition.outputLayout
    log.verbose{"\(logPre) Start"}

    if outputLayout.topBarView == .showAlways {
      // This is apparently missed
      fadeableViews.applyVisibility(outputLayout.topBarView, to: topBarView)
    }

    switch transition.outputLayout.mode {
    case .fullScreenInteractive, .windowedInteractive:
      // Show cursor always in these modes
      setCursorToNormalAlwaysShown()
    case .windowedNormal, .fullScreenNormal, .musicMode:
      // TODO: hide cursor now if configured to always hide
      break
    }

    if transition.outputLayout.isLegacyStyle {
      // Set legacy style
      setWindowStyleToLegacy()

      if transition.outputLayout.isLegacyFullScreen {
        window.styleMask.insert(.borderless)
      } else {
        window.styleMask.remove(.borderless)
      }

      /// if `isTogglingLegacyStyle==true && isExitingFullScreen==true`, we are toggling out of legacy FS
      /// -> don't change `styleMask` to `.titled` here - it will look bad if screen has camera housing. Change at end of animation
    } else {
      // Native style
      if !transition.isEnteringFullScreen {
        setWindowStyleToNative()
      }
    }

    if transition.isWindowInitialLayout || transition.isOpeningViewport {
      if !transition.isWindowInitialLayout, pip.status == .inPIP {
        // We are about to steal its video; close it:
        exitPIP()
      }
    }

    if transition.outputGeometry.isViewportShown {
      // This adds videoView, viewportView & spacers if not already added
      addViewportAndSubviewsToWindowIfNeeded()
    }

    // Remove aspect constraint between animations (for some mode changes):
    if transition.isExitingMusicMode {
      videoView.apply(transition.outputGeometry)
    } else if transition.isOpeningViewport {
      videoView.apply(transition.outputGeometry)
      // Allow "stretch" effect when opening videoView
      videoView.videoViewConstraints?.aspectRatio.isActive = false
    } else if transition.isExitingInteractiveMode {
      videoView.apply(transition.outputGeometry)
    }

    if transition.isOpeningViewport {
      // Show default album art if no video track selected
      if let currentPlayback = player.info.currentPlayback, currentPlayback.state.isAtLeast(.loaded), !player.info.isVideoTrackSelected {
        updateDefaultArtVisibility(to: true)
      }
    }

    if !transition.isExitingFullScreen && !transition.isEnteringInteractiveMode && transition.needsMpvKeepaspectUpdate {
      player.updateMpvKeepaspectWindowSynchronously()
    }

    // - Bottom Bar
    let needsBottomBarUpdate = transition.isWindowInitialLayout || transition.isBottomBarPlacementOrStyleChanging
    if needsBottomBarUpdate {
      rebuildBottomBarView(style: transition.outputLayout.effectiveOSCColorScheme)
      // Just add the new view now. It will have its Z order corrected in `rebuildPanelConstraints`.
      window.contentView!.addSubview(bottomBarView)
    }

    // Title bar views

    // Allow for showing/hiding each button individually
    let onTopButtonVisibility = transition.outputLayout.computeOnTopButtonVisibility(isOnTop: isOnTop)

    // For some reason, transitioning to/from interactive mode messes up the alignment of CustomTitleBar's title text.
    // Removing the whole CustomTitleBar view hierarchy & recreating it seems to be a valid workaround.
    if outputLayout.titleBar == .hidden || transition.isTopBarPlacementOrStyleChanging || (transition.inputLayout.mode != transition.outputLayout.mode) {
      /// Even if exiting FS, still don't want to show title & buttons until after panel open animation:
      hideNativeTitleBarViews(andSetAlpha: true)

      if let customTitleBar {
        customTitleBar.removeAndCleanUp()
        self.customTitleBar = nil
      }
    }

    if outputLayout.titleBar.isShowable, transition.outputLayout.isLegacyStyle {
      let legacyTitleBar: CustomTitleBarViewController
      // Custom title bar
      if let customTitleBar {
        legacyTitleBar = customTitleBar
      } else {
        legacyTitleBar = CustomTitleBarViewController()
        legacyTitleBar.pwc = self
        customTitleBar = legacyTitleBar
        legacyTitleBar.view.alphaValue = 0  // prep it to fade in later
      }

      legacyTitleBar.addViewTo(superview: topBarView.titleBarView)
      legacyTitleBar.updateTrackingAreas()  // call this *after* attaching to superview
      fadeableViews.applyOnlyIfHidden(outputLayout.leadingSidebarToggleButton, to: legacyTitleBar.leadingSidebarToggleButton)
      fadeableViews.applyOnlyIfHidden(outputLayout.trailingSidebarToggleButton, to: legacyTitleBar.trailingSidebarToggleButton)
      fadeableViews.applyOnlyIfHidden(onTopButtonVisibility, to: legacyTitleBar.onTopButton)
    }

    fadeableViews.applyOnlyIfHidden(outputLayout.leadingSidebarToggleButton, to: leadingSidebarToggleButton)
    fadeableViews.applyOnlyIfHidden(outputLayout.trailingSidebarToggleButton, to: trailingSidebarToggleButton)
    fadeableViews.applyOnlyIfHidden(onTopButtonVisibility, to: onTopButton)

    /// These should all be either 0 height or unchanged from `transition.inputLayout`.
    /// But may need to add or remove from fadeableViews
    fadeableViews.applyVisibility(outputLayout.bottomBarView, to: bottomBarView)
    // Note: hiding top bar here when entering FS with "top outside" OSC will cause it to go black too soon.
    // But we do need it when tranitioning from music mode → FS, or top bar may never be shown
    if !transition.isEnteringFullScreen || transition.isExitingMusicMode {
      fadeableViews.applyOnlyIfHidden(outputLayout.topBarView, to: topBarView)
    }

    /// Show dividing line only for `.outsideViewport` bottom bar. Don't show in music mode as it doesn't look good
    let showBottomBarTopBorder = outputLayout.bottomBarPlacement == .outsideViewport || (outputLayout.hasBottomOSC && !outputLayout.oscBackgroundIsClear)
    bottomBarTopBorder.isHidden = !showBottomBarTopBorder

    // Need to add additionalInfo, OSD before changing sidebars
    addOrRemoveOSDViews(transition.outputGeometry)

    if !transition.isWindowInitialLayout && !transition.isTogglingFullScreen {
      rebuildPanelConstraints(transition, stage: .midTransitionHiddenUpdates)
    }

    // - Sidebars

    // Leading Sidebar
    if let visibleTab = transition.outputLayout.leadingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
    }

    // Trailing Sidebar
    if let visibleTab = transition.outputLayout.trailingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
    }

    // Update bottom bar constraints *after* sidebars are added
    if transition.isOpeningAnySidebar {
      log.verbose{"\(logPre) Sidebars will be open: LeadingSidebar=\(outputLayout.leadingSidebar.isVisible.yn) TrailingSidebar=\(outputLayout.trailingSidebar.isVisible.yn)"}

      if outputLayout.leadingSidebar.isVisible {
        if outputLayout.leadingSidebarPlacement == .insideViewport {
          leadingSidebarView.material = .menu
        } else {
          leadingSidebarView.material = .toolTip
        }
      }

      if outputLayout.trailingSidebar.isVisible {
        if outputLayout.trailingSidebarPlacement == .insideViewport {
          trailingSidebarView.material = .menu
        } else {
          trailingSidebarView.material = .toolTip
        }
      }
    }

    // - Music mode: entering or continuing)

    if (transition.isEnteringMusicMode || transition.isTogglingPlaylistInMusicMode) && transition.outputGeometry.isMusicModePlaylistShown {
      // move playist view
      miniPlayer.loadIfNeeded()
      miniPlayer.addPlaylistViewIfMissing()
    }

    // If initial layout, bottomBar has been rebuilt, so we need to repopulate it
    if transition.isWindowInitialLayout || transition.isTogglingMusicMode {
      pip.showOrHidePipOverlayView()

      if transition.isEnteringMusicMode {
        log.verbose{"\(logPre) Entering music mode: adding miniPlayer view to bottomBarView"}
        miniPlayer.loadIfNeeded()
        bottomBarView.addSubview(miniPlayer.view, positioned: .below, relativeTo: bottomBarTopBorder)
        miniPlayer.view.addAllConstraintsToFillSuperview()

        playSlider.customCell.knobHeight = Constants.Distance.Slider.musicModeKnobHeight

        // move playback buttons
        if !miniPlayer.playbackBtnsWrapperView.subviews.contains(fragPlaybackBtnsView) {
          miniPlayer.playbackBtnsWrapperView.addSubview(fragPlaybackBtnsView)
          miniPlayer.playbackBtnsWrapperView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor).isActive = true
          miniPlayer.playbackBtnsWrapperView.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor).isActive = true
        }

        if !miniPlayer.volumeSliderView.subviews.contains(fragVolumeView) {
          miniPlayer.volumeSliderView.addSubview(fragVolumeView)
          fragVolumeView.centerYAnchor.constraint(equalTo: miniPlayer.volumeSliderView.centerYAnchor).isActive = true
          volumeSlider.leadingAnchor.constraint(equalTo: miniPlayer.volumeSliderView.leadingAnchor, constant: 40).isActive = true
          miniPlayer.volumeSliderView.trailingAnchor.constraint(equalTo: volumeSlider.trailingAnchor, constant: 40).isActive = true
          muteButton.target = self
          muteButton.action = #selector(muteButtonAction(_:))
        }

        seekPreview.timeLabel.font = NSFont.systemFont(ofSize: 9)

        // Update music mode UI
        updateTitle()

        // move playback position slider & time labels
        let wasAlreadyPresent = miniPlayer.positionSliderWrapperView.subviews.contains(playSliderAndTimeLabelsView)
        miniPlayer.positionSliderWrapperView.addSubview(playSliderAndTimeLabelsView)
        addSubviewsToPlaySliderAndTimeLabelsView(using: transition.outputLayout.controlBarGeo)
        if !wasAlreadyPresent {
          playSliderAndTimeLabelsView.addAllConstraintsToFillSuperview()
          playSliderAndTimeLabelsView.isHidden = false
        }

      } else if transition.isExitingMusicMode {
        // If exiting music mode, need to restore views early in this step
        log.verbose{"\(logPre) Cleaning up for music mode exit"}
        miniPlayer.loadIfNeeded()
        miniPlayer.view.removeFromSuperview()

        // Make sure to reset constraints for OSD
        miniPlayer.hideControllerButtons()
      }
    }  // End toggling music mode

    if transition.outputLayout.isMusicMode {
      // Need to call this for initial layout also, or if toggling video:
      updateMusicModeButtonsVisibility(using: transition.outputGeometry)

      if !transition.outputGeometry.isViewportShown && pip.status == .notInPIP {
        videoView.apply(nil)  // remove constraints
        videoView.removeFromSuperview()
        viewportView.removeSpacers()
        updateDefaultArtVisibility(to: false)  // hide defaultAlbumArt

        player.setVideoTrackDisabled()
      }
    }

    // OSC

    // [Re-]add OSC:
    if outputLayout.enableOSC {
      let newGeo = outputLayout.controlBarGeo
      log.verbose{"\(logPre) Setting up OSC: pos=\(outputLayout.oscPosition) musicMode=\(outputLayout.isMusicMode.yn) playIconSize=\(newGeo.playIconSize) playIconSpacing=\(newGeo.playIconSpacing)"}

      rebuildOSCToolbar(transition, .midTransitionHiddenUpdates)

      switch outputLayout.oscPosition {
      case .top:
        currentControlBar = topBarView.controlBarTop


        let oscContentView: NSView
        if newGeo.isTwoRowBarOSC {
          oscContentView = oscTwoRowView
          log.verbose{"\(logPre) Adding subviews to oscTwoRowView for top bar, topBarHeight=\(outputLayout.topBarHeight)"}
          oscTwoRowView.updateSubviews(from: self, newGeo)
        } else {
          oscContentView = oscOneRowView
          log.verbose{"\(logPre) Adding subviews to oscOneRowView for top bar"}
          oscOneRowView.updateSubviews(from: self, newGeo)
        }

        if !topBarView.controlBarTop.subviews.contains(oscContentView) {
          topBarView.controlBarTop.addSubview(oscContentView, positioned: .below, relativeTo: topBarView.bottomBorder)
          // Match leading/trailing spacing of title bar icons above
          oscContentView.addConstraintsToFillSuperview(top: 0, bottom: 0,
                                                       leading: Constants.Distance.titleBarIconHSpacing,
                                                       trailing: Constants.Distance.titleBarIconHSpacing)
        }

      case .bottom:
        currentControlBar = bottomBarView

        let oscContentView: NSView
        if newGeo.isTwoRowBarOSC {
          oscContentView = oscTwoRowView
          log.verbose{"\(logPre) Adding subviews to oscTwoRowView for bottom bar, bottomBarHeight=\(outputLayout.bottomBarHeight)"}
          oscTwoRowView.updateSubviews(from: self, newGeo)
        } else {
          oscContentView = oscOneRowView
          log.verbose{"\(logPre) Adding subviews to oscOneRowView for bottom bar"}
          oscOneRowView.updateSubviews(from: self, newGeo)
        }

        if !bottomBarView.subviews.contains(oscContentView) {
          bottomBarView.addSubview(oscContentView, positioned: .below, relativeTo: bottomBarTopBorder)
          // Match leading/trailing spacing of title bar icons above
          oscContentView.addConstraintsToFillSuperview(top: 0, bottom: 0,
                                                       leading: Constants.Distance.titleBarIconHSpacing,
                                                       trailing: Constants.Distance.titleBarIconHSpacing)
        }

      case .floating:
        currentControlBar = controlBarFloating
        if !viewportView.containsSubview(controlBarFloating) {
          log.verbose{"\(logPre) Adding controlBarFloating to contentView"}
          viewportView.addSubview(controlBarFloating)
          sortViewportViewSubviews()

          controlBarFloating.xConstraint?.isActive = false
          controlBarFloating.yConstraint?.isActive = false

          let newY = viewportView.bottomAnchor.constraint(equalTo: controlBarFloating.bottomAnchor, constant: 60)
          newY.identifier = "FloatingOSC-BtmY-Con"
          newY.priority = .defaultHigh
          controlBarFloating.yConstraint = newY

          let newX = controlBarFloating.centerXAnchor.constraint(equalTo: viewportView.leadingAnchor, constant: 330)
          newX.identifier = "FloatingOSC-CenterX-Con"
          newX.priority = .init(450)
          controlBarFloating.xConstraint = newX

          adjustFloatingControllerOrigin(for: transition.outputGeometry)

          newY.isActive = true
          newX.isActive = true
        }

        controlBarFloating.addOrUpdateMarginConstraints(for: transition.outputLayout)

        let floatingUpperView = controlBarFloating.topRowView
        if !floatingUpperView.views.contains(fragToolbarView) {
          floatingUpperView.addView(fragToolbarView, in: .trailing)
          floatingUpperView.setVisibilityPriority(.detachEarlier, for: fragToolbarView)
          fragToolbarView.isHidden = false
        }
      }

      seekPreview.updateTimeLabelFontSize(to: newGeo.seekPreviewTimeLabelFontSize)

    } else if outputLayout.isMusicMode {

      // Music mode always has a control bar
      currentControlBar = miniPlayer.musicModeControlBarView

    } else {  // No OSC & not music mode
      currentControlBar = nil
    }

    if !outputLayout.hasFloatingOSC {
      controlBarFloating.removeMarginConstraints()
      controlBarFloating.removeFromSuperview()
    }

    if outputLayout.hasControlBar {
      // Has OSC, or music mode
      let newGeo = outputLayout.controlBarGeo

      // Update arrow buttons layout (but not width: that will be animated in the next step)
      leftArrowButton.replaceSymbolImage(with: newGeo.leftArrowImage)
      rightArrowButton.replaceSymbolImage(with: newGeo.rightArrowImage)

      rightTimeLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

      let hideArrowBtns = newGeo.arrowIconWidth == 0
      leftArrowButton.isHidden = hideArrowBtns
      rightArrowButton.isHidden = hideArrowBtns

      let timeLabelFont: NSFont = newGeo.timeLabelFont
      leftTimeLabel.font = timeLabelFont
      rightTimeLabel.font = timeLabelFont
      oscTwoRowView.timeSlashLabel.font = timeLabelFont

      // Not floating OSC!
      if !transition.outputLayout.hasFloatingOSC {
        updateSpeedLabelFont(for: transition)
      }

      let sliderKnobWidth = newGeo.sliderKnobWidth
      let sliderKnobHeight = newGeo.sliderKnobHeight
      playSlider.customCell.knobWidth = sliderKnobWidth
      playSlider.customCell.knobHeight = sliderKnobHeight
      playSlider.abLoopA.updateKnobImage(to: .loopKnob)
      playSlider.abLoopB.updateKnobImage(to: .loopKnob)
      playSlider.needsDisplay = true

      let volumeSliderCell = volumeSlider.cell as! VolumeSliderCell
      volumeSliderCell.knobWidth = sliderKnobWidth
      volumeSliderCell.knobHeight = sliderKnobHeight
      volumeSlider.needsDisplay = true

      if transition.isWindowInitialLayout || transition.isOSCStyleChanging || transition.inputLayout.controlBarGeo.barHeight != transition.outputLayout.controlBarGeo.barHeight {
        let hasClearBG = transition.outputLayout.oscBackgroundIsClear
        log.verbose{"\(logPre) Updating OSC colors: hasClearBG=\(hasClearBG.yn)"}

        playButton.setOSCColors(hasClearBG: hasClearBG)
        leftArrowButton.setOSCColors(hasClearBG: hasClearBG)
        rightArrowButton.setOSCColors(hasClearBG: hasClearBG)
        muteButton.setOSCColors(hasClearBG: hasClearBG)

        let textAlpha: CGFloat
        let timeLabelTextColor: NSColor?
        if transition.outputLayout.oscBackgroundIsClear {
          textAlpha = 0.8
          timeLabelTextColor = .white

          let blurRadiusConstant = Constants.Distance.oscClearBG_TextShadowBlurRadius_Constant
          let blurRadiusMultiplier = Constants.Distance.oscClearBG_TextShadowBlurRadius_Multiplier
          leftTimeLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)
          rightTimeLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)
          oscTwoRowView.timeSlashLabel.addShadow(blurRadiusMultiplier: blurRadiusMultiplier, blurRadiusConstant: blurRadiusConstant)

          knobFactory.mainKnobColor = NSColor.controlForClearBG
        } else {
          // Default alpha for text labels is 0.5. They don't change their text color.
          textAlpha = 0.5
          timeLabelTextColor = nil

          leftTimeLabel.shadow = nil
          rightTimeLabel.shadow = nil
          oscTwoRowView.timeSlashLabel.shadow = nil

          knobFactory.mainKnobColor = NSColor.mainSliderKnob
        }

        leftTimeLabel.textColor = timeLabelTextColor
        rightTimeLabel.textColor = timeLabelTextColor
        oscTwoRowView.timeSlashLabel.textColor = timeLabelTextColor
        leftTimeLabel.alphaValue = textAlpha
        rightTimeLabel.alphaValue = textAlpha
        oscTwoRowView.timeSlashLabel.alphaValue = textAlpha

        // Invalidate all cached knob images so they are rebuilt with new style
        knobFactory.invalidateCachedKnobs()
      }
    }

    // Interactive mode

    if transition.isTogglingInteractiveMode {
      // Even if entering IM, may have a prev crop due to a bug elsewhere. Remove if found
      removeCropControls()

      if transition.isEnteringInteractiveMode {
        // Need videoView to have superview before adding shadow
        videoView.addShadowForInteractiveMode()

        // Entering interactive mode
        setEmptySpaceColor(to: Constants.Color.interactiveModeBackground)

        // Add crop settings at bottom
        let cropController = self.cropSettingsView ?? transition.outputLayout.interactiveMode!.viewController()
        cropController.pwc = self
        self.cropSettingsView = cropController
        bottomBarView.addSubview(cropController.view, positioned: .below, relativeTo: bottomBarTopBorder)
        cropController.view.addAllConstraintsToFillSuperview()
        cropController.view.alphaValue = 0
        let videoSizeRaw = transition.outputGeometry.video.videoSizeRaw
        // Hide for now, to prepare for a nice fade-in animation
        cropController.cropBoxView.isHidden = true
        cropController.cropBoxView.alphaValue = 0
        cropController.cropBoxView.needsLayout = true

        /// `selectedRect` should be subrect of`actualSize`
        let selectedRect: NSRect
        switch currentLayout.interactiveMode {
        case .crop:
          if let prevCropFilter = player.info.videoFiltersDisabled[Constants.FilterLabel.crop] {
            selectedRect = prevCropFilter.cropRect(origVideoSize: videoSizeRaw, flipY: true)
            log.verbose{"\(logPre) Setting crop box selectedRect from prevFilter: \(selectedRect)"}
          } else {
            selectedRect = NSRect(origin: .zero, size: videoSizeRaw)
            log.verbose{"\(logPre) Setting crop box selectedRect to default whole videoSize: \(selectedRect)"}
          }
        case .freeSelecting, .none:
          selectedRect = .zero
        }
        cropController.cropBoxView.selectedRect = selectedRect

      } else if transition.isExitingInteractiveMode {
        // Exiting interactive mode
        setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)
        removeCropControls()
      }
    }

    if transition.outputGeometry.mode.isInteractiveMode {
      if let cropController = cropSettingsView {
        let videoSizeRaw = transition.outputGeometry.video.videoSizeRaw
        addOrReplaceCropBoxSelection(rawVideoSize: videoSizeRaw, videoViewSize: transition.outputGeometry.videoSize)

        // Native FS seems to change frame sizes on its own in some undocumented way, so just measure whatever is displayed for that.
        // But all other modes should use precalculated values because NSView bounds is sometimes not reliable depending on timing
        let cropBoxBounds = outputLayout.isNativeFullScreen ? videoView.bounds : NSRect(origin: CGPointZero, size: transition.outputGeometry.videoSize)
        cropController.cropBoxView.resized(with: cropBoxBounds)
        cropController.cropBoxView.needsLayout = true
      } else if !player.isRestoring, player.info.isFileLoaded, !player.info.isVideoTrackSelected {
        // if restoring, there will be a brief delay before getting player info, which is ok
        Utility.showAlert("no_video_track")
      }
    }

    prepareDepthOrderOfOutsideSidebarsForToggle(transition)

    // So that panels toggling between "inside" and "outside" don't change until they need to (but FS is OK)
    if !transition.isTogglingFullScreen {
      updatePanelBlendingModes(to: outputLayout)
    }

    // Do this here so that BarFactory regenerates close enough to mid-animation (so bar thickness changes pleasantly)
    if let screen = window.screen {
      applyThemeMaterial(using: transition.outputLayout, window, screen)
    } else {
      // In some rare cases, window might be off screen its frame size is zero (the latter can happen when exiting music mode with no
      // playlist & no video), in which case window.screen will be nil. Just log & continue. In principle, applyThemeMaterial will still
      // be called via windowDidChangeScreen.
      log.verbose{"\(logPre) Skipped applyThemeMaterial due to missing window or screen"}
    }


    // Other misc views
    updateVolumeUI()
    playSlider.needsDisplay = true

    log.verbose{"\(logPre) Done"}
  }  /// end `updateHiddenViewsAndConstraints`

  /// -------------------------------------------------
  /// OPEN PANELS & FINALIZE OFFSETS
  func openNewPanelsAndFinalizeOffsets(_ transition: LayoutTransition) {
    let outputLayout = transition.outputLayout
    let logPre = transition.logPreamble(for: .openNewPanels)
    log.verbose{"\(logPre) Start: TitleBar_H=\(outputLayout.titleBarHeight) TopOSC_H=\(outputLayout.topOSCHeight)"}

    if transition.isExitingLegacyFullScreen {
      /// Seems this needs to be called before the final `setFrame` call, or else the window can end up incorrectly sized at the end
      updatePresentationOptions(windowIsLegacyFS: false)
    }

    // Need to update OSD vertical offset when exiting from legacy FS due to previous special animations
    updateOSDTopOffsetConstraints(for: transition.outputGeometry)

    if outputLayout.hasControlBar {
      // Increase size of icons if they are larger
      let newGeo = outputLayout.controlBarGeo

      // Weaken constraints temporarily
      leftArrowBtn_CenterXOffsetConstraint.priority = .defaultLow
      rightArrowBtn_CenterXOffsetConstraint.priority = .defaultLow
      fragPlaybackBtnsHeightConstraint.priority = .defaultLow
      fragPlaybackBtnsWidthConstraint.priority = .defaultLow

      playSliderHeightConstraint.animateToConstant(newGeo.playSliderHeight)

      volumeIconHeightConstraint.animateToConstant(newGeo.volumeIconHeight)
      volumeSliderWidthConstraint.animateToConstant(newGeo.volumeSliderWidth)
      if let img = muteButton.image {
        volumeIconAspectConstraint.isActive = false
        volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: img.aspect)
        volumeIconAspectConstraint.isActive = true
      }
      log.verbose("TotalPlayControls.width=\(newGeo.totalPlayControlsWidth), leftArrowXOffset=\(newGeo.leftArrowCenterXOffset) rightArrowXOffset=\(newGeo.rightArrowCenterXOffset)")

      arrowBtnWidthConstraint.animateToConstant(newGeo.arrowIconWidth)
      playBtnHeightConstraint.animateToConstant(newGeo.playIconSize)
      fragPlaybackBtnsWidthConstraint.animateToConstant(newGeo.totalPlayControlsWidth)
      fragPlaybackBtnsHeightConstraint.animateToConstant(newGeo.fullIconHeight)
      leftArrowBtn_CenterXOffsetConstraint.animateToConstant(newGeo.leftArrowCenterXOffset)
      rightArrowBtn_CenterXOffsetConstraint.animateToConstant(newGeo.rightArrowCenterXOffset)

      // Finalize
      leftArrowBtn_CenterXOffsetConstraint.priority = .required
      rightArrowBtn_CenterXOffsetConstraint.priority = .required
      fragPlaybackBtnsWidthConstraint.priority = .required
      fragPlaybackBtnsHeightConstraint.priority = .required

      // Animate toolbar icons to full size now
      for toolbarItem in fragToolbarView.views {
        (toolbarItem as! OSCToolbarButton).setStyle(using: transition.outputLayout)
      }
      // FIXME: add toolbar height constraint
      updateToolbarHStack(iconSpacing: newGeo.toolIconSpacing)
    }

    rebuildPanelConstraints(transition, stage: .openNewPanels)

    let openNewPanelsGeo: PWinGeometry = transition.geometry(for: .openNewPanels)
    log.verbose("\(logPre) Calling setFrame from OpenNewPanels (\(openNewPanelsGeo.mode)): \(openNewPanelsGeo.windowFrame)")
    setFrameAndUpdateWindowSubviews(using: openNewPanelsGeo, updateVideoView: openNewPanelsGeo.mode != .musicMode)

    if outputLayout.hasFloatingOSC {
      // Wait until now to set up floating OSC views. Doing this in prev or next task while animating results in visibility bugs
      let topRowView = controlBarFloating.topRowView
      if transition.isWindowInitialLayout || !transition.inputLayout.hasFloatingOSC {
        controlBarFloating.playButtonsContainerView.addView(fragPlaybackBtnsView, in: .center)
        // There sweems to be a race condition when adding to these StackViews.
        // Sometimes it still contains the old view, and then trying to add again will cause a crash.
        // Must check if it already contains the view before adding.
        if !topRowView.views(in: .leading).contains(fragVolumeView) {
          topRowView.addView(fragVolumeView, in: .leading)
          fragVolumeView.isHidden = false
        }
        topRowView.setVisibilityPriority(.detachEarly, for: fragVolumeView)

        topRowView.setClippingResistancePriority(.defaultLow, for: .horizontal)

        addSubviewsToPlaySliderAndTimeLabelsView(using: transition.outputLayout.controlBarGeo)
        controlBarFloating.bottomRowView.addSubview(playSliderAndTimeLabelsView)
        playSliderAndTimeLabelsView.isHidden = false
        playSliderAndTimeLabelsView.addAllConstraintsToFillSuperview()
      }
      updateSpeedLabelFont(for: transition)

      // Update floating control bar position
      controlBarFloating.moveToLocationRatio(parentGeo: transition.outputGeometry)
    }

  }

  /// -------------------------------------------------
  /// FADE IN NEW VIEWS
  /// Expected to be animated.
  func fadeInNewViews(_ transition: LayoutTransition) {
    guard let window = window else { return }
    let logPre = "[\(transition.name):FadeInNewViews"
    let outputLayout = transition.outputLayout
    log.verbose("\(logPre) Start")

    fadeableViews.applyVisibility(outputLayout.controlBarFloating, to: controlBarFloating)
    fadeableViews.applyVisibility(outputLayout.topBarView, to: topBarView)

    if outputLayout.isFullScreen {
      if !outputLayout.isInteractiveMode && Preference.bool(for: .displayTimeAndBatteryInFullScreen) {
        fadeableViews.applyVisibility(.showFadeableNonTopBar, to: additionalInfoView)
      }
    }

    // If exiting FS, the openNewPanels and fadInNewViews steps are combined. Wait till later
    if outputLayout.titleBar.isShowable {
      if !transition.isExitingFullScreen {
        if outputLayout.isLegacyStyle {  // Legacy windowed mode
          for view in [customTitleBar?.view] {
            if let view {
              view.alphaValue = 1
              view.isHidden = false
            }
          }
        } else {  // Native windowed mode
          showNativeTitleBarViews()
          window.titleVisibility = .visible

          /// Title bar accessories get removed by fullscreen or if window `styleMask` did not include `.titled`.
          /// Add them back:
          addTitleBarAccessoryViews()
        }
      }
      // covers both native & custom variants
      updateTitleBarUI(from: outputLayout)
    }

    if let cropController = cropSettingsView {
      if transition.outputLayout.isInteractiveMode {
        // show crop settings view
        cropController.view.alphaValue = 1
        cropController.cropBoxView.isHidden = false
        cropController.cropBoxView.alphaValue = 1
      }
    }

    if transition.isExitingInteractiveMode {
      if !isPausedPriorToInteractiveMode {
        player.resume()
      }
    }

    if transition.isExitingFullScreen && !transition.outputLayout.isLegacyStyle && transition.outputLayout.titleBar.isShowable {
      // MUST put this in prev task to avoid race condition!
      window.titleVisibility = .visible
    }

    if !transition.isWindowInitialLayout || transition.outputLayout.isFullScreen {
      updateWindowBorderAndOpacity(using: transition.outputLayout)
    }
  }

  /// -------------------------------------------------
  /// POST TRANSITION: UPDATE INVISIBLES
  /// Cleanup & variable state updates. Always instantaneous (not animated).
  func doPostTransitionWork(_ transition: LayoutTransition) {
    let logPre = transition.logPreamble(for: .postTransition)
    log.verbose{"\(logPre) Start"}

    // Update blending mode:
    updatePanelBlendingModes(to: transition.outputLayout)

    fadeableViews.animationState = .shown
    fadeableViews.topBarAnimationState = .shown

    // Invalidate all old fadeable views actions as they are probably stale.
    fadeableViews.$showHideTicketCount.withLock { $0 += 1 }
    hideCursorTimer.restart()  // may need to re-evaluate
    fadeableViews.hideTimer.restart()  // start new fadeable countdown

    log.verbose{
      let fadeableIDs = fadeableViews.fadeables.map{$0.idString}
      let fadeablesTopBarIDs = fadeableViews.fadeablesInTopBar.map{$0.idString}
      return "\(logPre) FadeableViews=\(fadeableIDs) InTopBar=\(fadeablesTopBarIDs)"
    }

    guard let window else { return }

    if transition.isEnteringFullScreen {
      // Entered FS

      if transition.outputLayout.isNativeFullScreen {
        /// Special case: need to wait until now to call `trafficLightButtons.isHidden = false` due to their quirks
        for button in trafficLightButtons {
          button.isHidden = false
        }
      }

      if Preference.bool(for: .blackOutMonitor) {
        blackOutOtherMonitors()
      }

      if player.info.isPaused {
        if !player.isRestoring && Preference.bool(for: .playWhenEnteringFullScreen) {
          player.resume()
        } else {
          // When playback is paused the display link is stopped in order to avoid wasting energy on
          // needless processing. It must be running while transitioning to full screen mode. Now that
          // the transition has completed it can be stopped.
          videoView.displayIdle()
        }
      }

      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)

      // Exit PIP when entering full screen
      if pip.status == .inPIP {
        exitPIP()
      }

      player.events.emit(.windowFullscreenChanged, data: true)

    } else if transition.isExitingFullScreen {
      // Exited FS

      if transition.needsMpvKeepaspectUpdate {
        player.updateMpvKeepaspectWindowSynchronously()
      }

      if transition.inputLayout.isLegacyFullScreen {
        if #available(macOS 10.16, *) {
          window.level = .normal
        } else {
          window.styleMask.remove(.fullScreen)
        }

        window.styleMask.insert(.resizable)
      }

      if transition.outputLayout.isLegacyStyle {  // legacy windowed
        setWindowStyleToLegacy()
        window.styleMask.remove(.borderless)
        if let customTitleBar {
          customTitleBar.view.alphaValue = 1
        }
      } else {  // native windowed
        /// Same logic as in `fadeInNewViews()`
        if transition.outputLayout.isMusicMode {
          hideNativeTitleBarViews(andSetAlpha: false)
        } else {
          showNativeTitleBarViews()   /// do this again after adding `titled` style
          addTitleBarAccessoryViews() /// Need to make sure this executes after styleMask is `.titled`
        }
        updateTitle()
      }

      if Preference.bool(for: .blackOutMonitor) {
        removeBlackWindows()
      }

      // Restore ontop status / set proper window level
      setWindowFloatingOnTop(isOnTop, from: transition.outputLayout, updateOnTopStatus: false)

      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)

      if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.isPlaying {
        player.pause()
      }

      if player.info.isPaused {
        // When playback is paused the display link is stopped in order to avoid wasting energy on
        // needless processing. It must be running while transitioning from full screen mode. Now that
        // the transition has completed it can be stopped.
        videoView.displayIdle()
      }

      player.events.emit(.windowFullscreenChanged, data: false)
    }

    if transition.isExitingMusicMode || transition.isClosingPlaylistInMusicMode {
      // move playist view
      miniPlayer.removePlaylistViewIfPresent()
    }

    rebuildPanelConstraints(transition, stage: .postTransition)
    setFrameAndUpdateWindowSubviews(using: transition.outputGeometry)

    if transition.isTogglingMusicMode {
      if Preference.bool(for: .playlistShowMetadataInMusicMode) {
        /// Need to toggle music metadata due to music mode switch.
        /// Do this even if playlist is not visible now, because it will not be be reloaded when toggled.
        playlistView.needsScrollToCurrentItem = true
        playlistView.reloadPlaylistRows()
      } else if transition.outputLayout.isMusicMode && transition.outputGeometry.isMusicModePlaylistShown {
        // Music mode playlist is visible: need to scroll to current item again due to size change
        playlistView.scrollPlaylistToCurrentItem()
      } else if transition.outputLayout.playlistShown {
        // Playlist sidebar is visible: need to scroll to current item again due to size change
        playlistView.scrollPlaylistToCurrentItem()
      }
    }

    refreshHidesOnDeactivateStatus()

    if !transition.isWindowInitialLayout {
      window.layoutIfNeeded()

      // Do not run sanity checks for initial layout, because in that case all task funcs combined into a single
      // animation task, which means that frames will not be updated yet & can't be measured correctly
      if Logger.isEnabled(.error) && pip.status == .notInPIP && player.state.isNotYet(.stopping) && player.info.isVideoTrackSelected {
        let vidSizeA = videoView.frame.size
        let vidSizeE = transition.outputGeometry.videoSize
        let viewportSizeA = viewportView.frame.size
        let viewportSizeE = transition.outputGeometry.viewportSize
        let winSizeA = window.frame.size
        let winSizeE = transition.outputGeometry.windowFrame.size

        let enableVidCheck = !player.info.currentMediaAudioStatus.isAudio
        let isWrongVidSize = enableVidCheck && (vidSizeE.area > 0 && vidSizeA.area > 0) &&
          ((vidSizeE.width != vidSizeA.width) || (vidSizeE.height != vidSizeA.height))
        let isWrongWinSize = (winSizeE.width != winSizeA.width) || (winSizeE.height != winSizeA.height)

        if isWrongVidSize || isWrongWinSize {
          /// Now that the transition is done and layout is complete, it is useful to check that our calculations are consistent with the result.
          /// In AppKit, `NSWindow` is the root object for the view hierarchy, so its size is easiest to get right. We start our calculations with
          /// the outermost panels & build inward (see `PWinGeometry`), so errors accumulate along the way & will result in `videoView.frame.size`
          /// (i.e. actual video size) since it is innermost.
          /// NOTE: this verifies (A) the AppKit NSView hierarchy with (B) `VideoGeometry` & `PWinGeometry`' layout calculations, but does not
          /// verify them against (C) mpv's internal video size calculations. Those are checked in `PWin_Resize.swift`
          /// (search for another instance of the UTF "X" like the one below).
          let wrong = "ⓧ"
          let lines = ["[\(transition.name)] ❌ SanityCheck-C failed!",
                       "  VidAspect: Expect=\(vidSizeE.mpvAspect) Actual=\(vidSizeA.mpvAspect) Constraint=\(videoView.videoViewAspect?.logStr ?? "nil")",
                       "  VideoSize: Expect=\(enableVidCheck ? vidSizeE.description : "NA") Actual=\(vidSizeA)  \(isWrongVidSize ? wrong : "")",
                       "  Viewport:  Expect=\(viewportSizeE) Actual=\(viewportSizeA)",
                       "  WinFrame:  Expect=\(transition.outputGeometry.windowFrame) Actual=\(window.frame)  \(isWrongWinSize ? wrong : "")",
                       "  VidMargins: \(transition.outputGeometry.viewportMargins)",  // Size should == viewport - video. (Unless video is wrong)
                       ]
          log.error(lines.joined(separator: "\n"))
        }
      }

    }

    if transition.outputGeometry.mode.isWindowed || transition.isTogglingFullScreen || transition.isTogglingMusicMode {
      sendWindowScaleToMPV(basedOn: transition.outputGeometry)
    }

    // abort any queued screen updates
    screenChangedDebouncer.invalidate()
    screenParamsChangedDebouncer.invalidate()
    isAnimatingLayoutTransition = false

    log.verbose("[\(transition.name)] Done with transition: isLegacy=\(transition.outputLayout.isLegacyStyle.yn) mode=\(currentLayout.mode)")

    player.saveState()
  }

  // MARK: - Support Functions: Title Bar

  private func addTitleBarAccessoryViews() {
    guard let window = window else { return }
    guard window.styleMask.contains(.titled) else { return }

    if leadingTitlebarAccesoryViewController == nil {
      let controller = NSTitlebarAccessoryViewController()
      leadingTitlebarAccesoryViewController = controller
      controller.view = leadingTitleBarAccessoryView
      controller.layoutAttribute = .leading
    }
    if trailingTitlebarAccesoryViewController == nil {
      let controller = NSTitlebarAccessoryViewController()
      trailingTitlebarAccesoryViewController = controller
      controller.view = trailingTitleBarAccessoryView
      controller.layoutAttribute = .trailing
    }

    if !window.titlebarAccessoryViewControllers.contains(leadingTitlebarAccesoryViewController!) {
      window.addTitlebarAccessoryViewController(leadingTitlebarAccesoryViewController!)
      leadingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
      leadingTitleBarAccessoryView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
    }

    if !window.titlebarAccessoryViewControllers.contains(trailingTitlebarAccesoryViewController!) {
      window.addTitlebarAccessoryViewController(trailingTitlebarAccesoryViewController!)
      trailingTitleBarAccessoryView.translatesAutoresizingMaskIntoConstraints = false
      trailingTitleBarAccessoryView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
    }
  }

  /// Either legacy FS or windowed
  private func setWindowStyleToLegacy() {
    guard let window = window else { return }
    if window.styleMask.contains(.titled) {
      log.verbose("Removing window styleMask.titled")
      window.styleMask.remove(.titled)
    }
    window.styleMask.insert(.closable)
    window.styleMask.insert(.miniaturizable)
  }

  /// "Native" == `.titled` style mask
  private func setWindowStyleToNative() {
    guard let window = window else { return }

    if !window.styleMask.contains(.titled) {
      log.verbose("Inserting window styleMask.titled")
      window.styleMask.remove(.borderless)
      window.styleMask.insert(.titled)
    }
  }

  // MARK: - Support Functions: Interactive Mode Controls

  /// Call this when `origVideoSize` is known.
  /// Assumes `videoRect == videoView.frame`
  private func addOrReplaceCropBoxSelection(rawVideoSize: NSSize, videoViewSize: NSSize) {
    guard let cropController = self.cropSettingsView else { return }

    if !videoView.subviews.contains(cropController.cropBoxView) {
      videoView.addSubview(cropController.cropBoxView)
      cropController.cropBoxView.addAllConstraintsToFillSuperview()
    }

    cropController.cropBoxView.actualSize = rawVideoSize
    cropController.cropBoxView.resized(with: NSRect(origin: .zero, size: videoViewSize))
  }

  private func removeCropControls() {
    guard let cropController = self.cropSettingsView else { return }

    cropController.cropBoxView.removeFromSuperview()
    cropController.view.removeFromSuperview()
    self.cropSettingsView = nil
  }

  // MARK: - Support Functions: OSC Layout

  private func updateSpeedLabelFont(for transition: LayoutTransition) {
    let oscGeo = transition.outputLayout.controlBarGeo
    let speedLabelFontSize = oscGeo.speedLabelFontSize
    log.trace("Updating speed label fontSize=\(speedLabelFontSize)")
    speedLabel.font = .messageFont(ofSize: speedLabelFontSize)
  }

  /// Recreates the toolbar with the latest icons with the latest sizes & padding from prefs
  private func rebuildOSCToolbar(_ transition: LayoutTransition, _ stage: LayoutTransition.Stage) {
    let oldGeo = transition.inputLayout.controlBarGeo
    let newGeo = transition.outputLayout.controlBarGeo
    let newButtonTypes = newGeo.toolbarItems

    let hasSizeChange = oldGeo.toolIconSize != newGeo.toolIconSize || oldGeo.toolIconSpacing != newGeo.toolIconSpacing
    let hasColorChange = transition.inputLayout.oscBackgroundIsClear != transition.outputLayout.oscBackgroundIsClear
    var needsButtonsUpdate = hasSizeChange || hasColorChange

    let isOpeningBarOSCFromZero = transition.isOpeningBarOSCFromZero
    let zeroOut = isOpeningBarOSCFromZero && !transition.isWindowInitialLayout
    let iconSize: CGFloat = zeroOut ? 0 : newGeo.toolIconSize
    let iconSpacing: CGFloat = zeroOut ? 0 : newGeo.toolIconSpacing
    if isOpeningBarOSCFromZero || !oldGeo.toolbarItemsAreSame(as: newGeo) {
      fragToolbarView.views.forEach { fragToolbarView.removeView($0) }

      if newButtonTypes.count > 0 {
        log.verbose("\(transition.logPreamble(for: stage)) Updating OSC toolbar: iconSize=\(iconSize) iconSpacing=\(iconSpacing) barHeight=\(newGeo.barHeight) fullIconHeight=\(newGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]")
        for buttonType in newButtonTypes {
          let button = OSCToolbarButton()
          button.setStyle(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing)
          button.setOSCColors(hasClearBG: transition.outputLayout.oscBackgroundIsClear)
          button.action = #selector(self.toolBarButtonAction(_:))
          fragToolbarView.addView(button, in: .trailing)
          fragToolbarView.setVisibilityPriority(.detachOnlyIfNecessary, for: button)
        }
        needsButtonsUpdate = false
      }
    }

    if needsButtonsUpdate {
      log.verbose("\(transition.logPreamble(for: stage)) Updating OSC toolbar: iconSize=\(newGeo.toolIconSize) iconSpacing=\(newGeo.toolIconSpacing) barHeight=\(newGeo.barHeight) fullIconHeight=\(newGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]")
      for button in fragToolbarView.views.compactMap({ $0 as? OSCToolbarButton }) {
        button.setStyle(iconSize: iconSize, iconSpacing: iconSpacing)
        button.setOSCColors(hasClearBG: transition.outputLayout.oscBackgroundIsClear)
      }
    }

    // Do not zero this out:
    updateToolbarHStack(iconSpacing: newGeo.toolIconSpacing)
    log.verbose("\(transition.logPreamble(for: stage)) Toolbar spacing=\(fragToolbarView.spacing) edgeInsets=\(fragToolbarView.edgeInsets)")
  }

  // It's not possible to control the icon padding from inside the buttons in all cases.
  // Instead we can get the same effect with a little more work, by using the stack view's features.
  private func updateToolbarHStack(iconSpacing: CGFloat) {
    log.verbose("Updating toolbar hstack using spacing=\(iconSpacing)")
    fragToolbarView.spacing = 2 * iconSpacing
    let sideInset = (iconSpacing * 0.5).rounded()
    fragToolbarView.edgeInsets = .init(top: iconSpacing, left: sideInset,
                                       bottom: iconSpacing, right: sideInset)
    fragToolbarView.needsUpdateConstraints = true
  }

  // MARK: - Support Functions: Style


  /// This fixes an edge case when both sidebars are shown and are `.outsideViewport`. When one is toggled, and width of
  /// `videoView` is smaller than that of the sidebar being toggled, must ensure that the sidebar being animated is below
  /// the other one, otherwise it will be briefly seen popping out on top of the other one.
  private func prepareDepthOrderOfOutsideSidebarsForToggle(_ transition: LayoutTransition) {
    guard transition.isOpeningOrClosingAnySidebar,
          transition.outputLayout.leadingSidebar.placement == .outsideViewport,
          transition.outputLayout.trailingSidebar.placement == .outsideViewport else { return }
    guard let contentView = window?.contentView else { return }

    if transition.isOpeningLeadingSidebar {
      contentView.addSubview(leadingSidebarView, positioned: .below, relativeTo: trailingSidebarView)
    } else if transition.isOpeningTrailingSidebar {
      contentView.addSubview(trailingSidebarView, positioned: .below, relativeTo: leadingSidebarView)
    }
  }

  private func updatePanelBlendingModes(to outputLayout: LayoutState) {
    if outputLayout.topBarHeight > 0 {
      // Full screen + "behindWindow" doesn't blend properly and looks ugly
      if outputLayout.topBarPlacement == .insideViewport || outputLayout.isFullScreen {
        topBarView.blendingMode = .withinWindow
      } else {
        topBarView.blendingMode = .behindWindow
      }
    }

    if outputLayout.bottomBarHeight > 0 {
      if let bottomBarView = bottomBarView as? NSVisualEffectView {
        // Full screen + "behindWindow" doesn't blend properly and looks ugly
        if outputLayout.bottomBarPlacement == .insideViewport || outputLayout.isFullScreen {
          bottomBarView.blendingMode = .withinWindow
        } else {
          bottomBarView.blendingMode = .behindWindow
        }
      }
    }

    if outputLayout.leadingSidebar.isVisible {
      updateSidebarBlendingMode(.leadingSidebar, layout: outputLayout)
    }

    if outputLayout.trailingSidebar.isVisible {
      updateSidebarBlendingMode(.trailingSidebar, layout: outputLayout)
    }
  }
}
