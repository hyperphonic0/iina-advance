//
//  PWin_LayoutConstraints.swift
//  iina
//
//  Created by Matt Svoboda on 8/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// This file contains support functions for the transition tasks found in `PWin_LayoutTxSteps.swift`.
extension PlayerWindowController {
  /// Add, remove, or modify each of the bars & their constraints based on the given stage of the layout transition.
  ///
  /// # Diagram: Vertical contraints in relation to `PWinGeometry` panels
  /// Note the consistent direction between anchors. (Created with https://asciip.dev/, then hand-edited.)
  ///```
  /// ┌─ Top                                                                ┬  ┬  ┬  ┬
  /// │                                                                     │  │  │  │
  /// │window                                                               │  │  │  │vpTopOffsetFromCVTop¹
  /// │contentView      ┌───────────┐  ┬                                    │  │  │  │
  /// │                 │  TopBar   │  │vpTopOffsetFromTopBarTop            │  │  │  │
  /// │        ┌────────│────┐      │  ▼  ┬                                 │  │  │  ▼
  /// │        │        │    │      │     │topBarBtmOffsetFromVPTop         │  │  │
  /// │        │        └───────────┘     ▼                                 │  │  │
  /// │        │   Viewport  │                                              │  │  │bottomBarTopOffsetFromCVTop⁴
  /// │  ┌─────────────┐     │      ┬                                       │  │  ▼
  /// │  │     │       │     │      │vpBtmOffsetFromTopOfBottomBar          │  │vpBtmOffsetFromCVTop¹
  /// │  │     └───────│─────┘   ┬  ▼                                    ┬  │  ▼
  /// │  │  BottomBar  │         │bottomBarBtmOffsetFromVPBtm¹           │  │bottomBarBtmOffsetFromCVTop⁵
  /// │  └─────────────┘      ┬  ▼                                       │  ▼
  /// │                       │                                          │
  /// │                       │cvBtmOffsetFromBottomBarBtm               │
  /// │                       │                                          │
  /// │                       │                                          │cvBtmOffsetFromVPBtm
  /// └─ Bottom               ▼                                          ▼
  ///```
  /// - ¹Used for opening/closing viewport animation.
  /// - ⁴Only used when bottomBar is shown & viewport is hidden.
  /// - ⁵Only used in music mode when both video & playlist are hidden.
  struct PanelConstraints {
    // - Top bar (title bar and/or top OSC) constraints
    let topBarBtmOffsetFromVPTop = OptionalConstraint("TopBar.btm-offset-from-VP.top")
    let vpTopOffsetFromTopBarTop = OptionalConstraint("VP.top-offset-from-TopBar.top")
    let vpTopOffsetFromCVTop = OptionalConstraint("VP.top-offset-from-CV.top")
    let vpBtmOffsetFromCVTop = OptionalConstraint("VP.btm-offset-from-CV.top")

    // - Bottom bar constraints
    let cvBtmOffsetFromVPBtm = OptionalConstraint("CV.btm-offset-from-VP.btm")
    let vpBtmOffsetFromTopOfBottomBar = OptionalConstraint("VP.btm-offset-from-BottomBar.top")
    let bottomBarBtmOffsetFromVPBtm = OptionalConstraint("BottomBar.btm-offset-from-VP.btm")
    /// Only active when video is hidden
    let bottomBarTopOffsetFromCVTop = OptionalConstraint("BottomBar.top-offset-from-CV.top")
    /// Only active when video is hidden
    let bottomBarBtmOffsetFromCVTop = OptionalConstraint("BottomBar.btm-offset-from-CV.top")
    let cvBtmOffsetFromBottomBarBtm = OptionalConstraint("BottomBar.btm-offset-from-CV.btm")
    // Needs to be changed to align with either sidepanel or leading edge of window:
    let bottomBarLeadingSpace = OptionalConstraint("BottomBar.leading-space")
    // Needs to be changed to align with either sidepanel or trailing edge of window:
    let bottomBarTrailingSpace = OptionalConstraint("BottomBar.trailing-space")

    let vpLeadingOffsetFromCVLeading = OptionalConstraint("VP.leading-offset-from-CV.leading")
    let vpTrailingOffsetFromCVTrailing = OptionalConstraint("CV.trailing-offset-from-VP.trailing")
  }

  // MARK: - Bars Layout

  func rebuildPanelConstraints(_ transition: LayoutTransition, stage: LayoutTransition.Stage) {
    let contentView = window!.contentView!
    let p = panelConstraints
    let logPre = transition.logPreamble(for: stage)
    let log = self.log.withPreamble(logPre)
    let outputGeo = transition.outputGeometry
    let stageGeo = transition.geometry(for: stage)

    var useViewport = outputGeo.isViewportShown
    var useBottomBar = transition.outputLayout.hasBottomBar
    var useTopBar = transition.outputLayout.hasTopBar
    var useLeadingSidebar = transition.outputLayout.isLeadingSidebarVisible
    var useTrailingSidebar = transition.outputLayout.isTrailingSidebarVisible
    let isFinalStage = stage == .postTransition

    let layout: LayoutState
    switch stage {
    case .preTransitionSetup, .closeOldPanels, .moveAndScale:
      // Closing or preparing to close: use existing layout
      layout = transition.inputLayout
      useTopBar = useTopBar || transition.inputLayout.hasTopBar
      useViewport = useViewport || transition.inputGeometry.isViewportShown
    case .midTransitionHiddenUpdates, .openNewPanels:
      if transition.isTogglingFullScreen {  // need exception for FS toggle
        useTopBar = useTopBar || transition.inputLayout.hasTopBar
        useViewport = useViewport || transition.inputGeometry.isViewportShown
      }
      // About to apply output geometry, or applying output geometry: use output layout
      layout = transition.outputLayout
    case .postTransition:
      layout = transition.outputLayout
    }

    if !isFinalStage {
      useBottomBar = useBottomBar || transition.inputLayout.hasBottomBar
      useLeadingSidebar = useLeadingSidebar || transition.inputLayout.isLeadingSidebarVisible
      useTrailingSidebar = useTrailingSidebar || transition.inputLayout.isTrailingSidebarVisible
    }

    log.verbose("RebuildPanels: Viewport=\(useViewport.yn) BottomBar=\(useBottomBar.yn) TopBar=\(useTopBar.yn) LeadingSB=\(useLeadingSidebar.yn) TrailingSB=\(useTrailingSidebar.yn)")

    // - Add window subviews in a well-defined order (before adding constraints between them)

    // Add/remove viewportView if needed
    if useViewport {
      if !contentView.containsSubview(viewportView) {
        contentView.addSubview(viewportView, positioned: .below, relativeTo: seekPreview.timeLabel)
      }
    } else {
      viewportView.removeFromSuperview()
    }

    // Add/remove sidebars if needed
    if useLeadingSidebar {
      contentView.addSubview(leadingSidebarView, positioned: .above, relativeTo: viewportView)
    } else {
      leadingSidebarConstraints = nil  // disables constraints
      leadingSidebarView.removeFromSuperview()
    }
    if useTrailingSidebar {
      contentView.addSubview(trailingSidebarView, positioned: .above, relativeTo: viewportView)
    } else {
      trailingSidebarConstraints = nil  // disables constraints
      trailingSidebarView.removeFromSuperview()
    }


    // Add/remove bottomBarView if needed
    if useBottomBar {
      contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)
    } else {
      bottomBarView.removeFromSuperview()
    }

    // Add/remove topBarView if needed
    if useTopBar {
      if !contentView.containsSubview(topBarView) {
        contentView.addSubview(topBarView, positioned: .above, relativeTo: viewportView)

        // These constraints don't change as long as topBarView is attached
        let topBarLeadingSpaceConstraint = topBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        topBarLeadingSpaceConstraint.identifier = "TopBar.leading-offset-from-CV.leading"
        topBarLeadingSpaceConstraint.isActive = true

        let topBarTrailingSpaceConstraint = topBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
        topBarTrailingSpaceConstraint.identifier = "TopBar.trailing-offset-from-CV.trailing"
        topBarTrailingSpaceConstraint.isActive = true
      }
    } else {
      topBarView.removeFromSuperview()
    }

    // - Add constraints between subviews
    if useTopBar {
      assert(useViewport, "Cannot use topBarView without viewportView")
      let constant1 = transition.vpTopOffsetFromTopBarTop(for: stage)
      let constant2 = transition.topBarBtmOffsetFromVPTop(for: stage)
      log.verbose("Updating topBar: vpTopOffsetFromTopBarTop=\(constant1) topBarBtmOffsetFromVPTop=\(constant2)")

      p.vpTopOffsetFromTopBarTop.createOrUpdate(to: constant1, log) { [self] c in
        viewportView.topAnchor.constraint(equalTo: topBarView.topAnchor, constant: c)
      }

      p.topBarBtmOffsetFromVPTop.createOrUpdate(to: constant2, log) { [self] c in
        topBarView.bottomAnchor.constraint(equalTo: viewportView.topAnchor, constant: c)
      }

      if stage == .closeOldPanels {
        if let middleGeo = transition.middleGeometry, middleGeo.topBarHeight == 0 {
          log.verbose("Updating titleHeight=\(0)")
          topBarView.titleBarHeightConstraint.animateToConstant(0)
        }
      } else {
        let titleHeight = min(layout.titleBarHeight, abs(constant1 - constant2))  // do not make titleBar larger than top bar
        log.verbose("Updating titleHeight=\(titleHeight)")
        topBarView.titleBarHeightConstraint.animateToConstant(titleHeight)
      }
    }

    let isAnimatingVideoViewOpen = transition.isOpeningViewport && !isFinalStage  // Music Mode: opening video
    if useBottomBar && (!outputGeo.isViewportShown || isAnimatingVideoViewOpen) {
      let constant1 = transition.bottomBarTopOffsetFromCVTop(for: stage)
      p.bottomBarTopOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
        bottomBarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }
    } else {
      // Need to manually remove this one because it doesn't depend on viewportView, & thus won't get removed if/when viewport gets removed.
      p.bottomBarTopOffsetFromCVTop.remove(log)
    }

    // BottomBar + Viewport
    if useBottomBar && useViewport && !isAnimatingVideoViewOpen {
      let constant1 = transition.vpBtmOffsetFromTopOfBottomBar(for: stage)
      let constant2 = transition.bottomBarBtmOffsetFromVPBtm(for: stage)
      log.verbose("Updating bottomBar & viewport: vpBtmOffsetFromTopOfBottomBar=\(Int(constant1)) bottomBarBtmOffsetFromVPBtm=\(Int(constant2))")

      p.vpBtmOffsetFromTopOfBottomBar.createOrUpdate(to: constant1, log) { [self] c in
        viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: c)
      }

      p.bottomBarBtmOffsetFromVPBtm.createOrUpdate(to: constant2, log) { [self] c in
        let con = bottomBarView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor, constant: c)
        // In music mode, need to be lower priority than VideoView constraints. Otherwise live resize of window will break.
        // Leave as lower priority always - doesn't seem to hurt, and prevent conflicting constraints
        con.priorityInt = 260
        return con
      }
    }

    // - Bottom Bar
    if useBottomBar {
      // Handle leading & trailing constraints
      updateBottomBarHorizontalContraints(bottomBarPlacement: layout.bottomBarPlacement,
                                          useLeadingSidebar: useLeadingSidebar, useTrailingSidebar: useTrailingSidebar, log)

      // enable for animations or if in music mode & neither playlist nor video is open
      if !isFinalStage || (outputGeo.mode == .musicMode && !outputGeo.isMusicModePlaylistShown && !outputGeo.isViewportShown) {
        let constant1 = transition.bottomBarBtmOffsetFromCVTop(for: stage)
        p.bottomBarBtmOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
          bottomBarView.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
        }
      } else {
        // remove
        if p.bottomBarBtmOffsetFromCVTop.isActive {
          p.bottomBarBtmOffsetFromCVTop.remove(log)
        }
      }

      // This will always have constant: 0
      p.cvBtmOffsetFromBottomBarBtm.createOrUpdate(to: 0, log) { [self] c in
        contentView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: c)
      }

    }


    // - Viewport View
    if useViewport {
      let constant1 = transition.vpTopOffsetFromCVTop(for: stage)
      let constant2 = transition.cvBtmOffsetFromVPBtm(for: stage)
      log.verbose("Updating viewport: vpTopOffsetFromCVTop=\(Int(constant1)) cvBtmOffsetFromVPBtm=\(Int(constant2)) vpLeadingOffsetFromCVLeading=0 vpTrailingOffsetFromCVTrailing=0")

      p.vpTopOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
        viewportView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }

      if (transition.isTogglingViewport || transition.isTogglingPlaylistInMusicMode), !isFinalStage {
        let constant3 = transition.vpBtmOffsetFromCVTop(for: stage)

        p.vpBtmOffsetFromCVTop.createOrUpdate(to: constant3, log) { [self] c in
          viewportView.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
        }
      } else {
        p.vpBtmOffsetFromCVTop.remove(log)
      }

      if isFinalStage && outputGeo.mode == .musicMode && outputGeo.isMusicModePlaylistShown {
        p.cvBtmOffsetFromVPBtm.remove(log)
      } else {
        p.cvBtmOffsetFromVPBtm.createOrUpdate(to: constant2, log) { [self] c in
          contentView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor, constant: c)
        }
      }

      // Leading
      p.vpLeadingOffsetFromCVLeading.createIfMissing(log) { [self] in
        viewportView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
      }

      // Trailing
      p.vpTrailingOffsetFromCVTrailing.createIfMissing(log) { [self] in
        contentView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor, constant: 0)
      }
    }

    // - Sidebars
    switch stage {
    case .preTransitionSetup:
      if transition.isWindowInitialLayout || transition.inputLayout.isMusicMode || transition.outputLayout.isMusicMode {
        updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
      }

    case .closeOldPanels:
      if let middleGeo = transition.middleGeometry, !transition.isWindowInitialLayout {
        if useLeadingSidebar || useTrailingSidebar {
          // Sidebars (if closing)
          let ΔWindowWidth = middleGeo.windowFrame.width - transition.inputGeometry.windowFrame.width
          animateShowOrHideSidebars(transition: transition, layout: layout,
                                    setLeadingTo: transition.isClosingLeadingSidebar ? .closed : nil,
                                    setTrailingTo: transition.isClosingTrailingSidebar ? .closed : nil,
                                    ΔWindowWidth: ΔWindowWidth)

        }

        if useLeadingSidebar || useTrailingSidebar, !transition.isExitingMusicMode && !transition.isExitingInteractiveMode {
          // Update sidebar vertical alignments to match top bar:
          updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
        }
      }

    case .moveAndScale:
      break

    case .midTransitionHiddenUpdates:
      /// Remove views for closed sidebars *BEFORE* doing logic for opening: the same transition can be doing both
      if transition.isClosingLeadingSidebar, let tabToHide = transition.inputLayout.leadingSidebar.visibleTab {
        /// Finish closing (if closing)
        removeSidebarTabGroupView(group: tabToHide.group)
      }
      if transition.isClosingTrailingSidebar, let tabToHide = transition.inputLayout.trailingSidebar.visibleTab {
        /// Finish closing (if closing).
        /// If entering music mode, make sure to do this BEFORE moving `playlistView` down below:
        removeSidebarTabGroupView(group: tabToHide.group)
      }

      if prepareSidebarsForOpening(transition) {
        updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
      }

    case .openNewPanels:
      if transition.isWindowInitialLayout {
        // Need to run this now because intiial layout doesn't run the midTransitionHiddenUpdates step
        if prepareSidebarsForOpening(transition) {
          updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
        }
      }
      if transition.inputGeometry.isMusicModePlaylistShown || transition.outputGeometry.isMusicModePlaylistShown
          || transition.inputLayout.isAnySidebarVisible || transition.outputLayout.isAnySidebarVisible {
        // Sidebars (if opening)
        let ΔWindowWidth = transition.ΔWindowWidth
        animateShowOrHideSidebars(transition: transition,
                                  layout: transition.outputLayout,
                                  setLeadingTo: transition.isOpeningLeadingSidebar ? layout.leadingSidebar.visibility : nil,
                                  setTrailingTo: transition.isOpeningTrailingSidebar ? layout.trailingSidebar.visibility : nil,
                                  ΔWindowWidth: ΔWindowWidth)

        updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
      }
    case .postTransition:
      break
    }

    // OSD constraints. Call this after calls to prepareLayoutForOpening(*Sidebar)
    updateOSDConstraints(stageGeo, hasLeadingSidebar: useLeadingSidebar, hasTrailingSidebar: useTrailingSidebar)

    sortContentViewSubviews(for: layout)
  }

  private func prepareSidebarsForOpening(_ transition: LayoutTransition) -> Bool {
    var didSomething = false
    if transition.isOpeningLeadingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(leadingSidebar: transition.outputLayout.leadingSidebar,
                              layout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
      didSomething = true
    }
    if transition.isOpeningTrailingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(trailingSidebar: transition.outputLayout.trailingSidebar,
                              layout: transition.outputLayout, ΔWindowWidth: transition.ΔWindowWidth)
      didSomething = true
    }
    return didSomething
  }

  // - Top bar

  func updateTopBarHeight(using geometry: PWinGeometry) {
    log.verbose("Updating topBar height to: inside=\(geometry.insideBars.top) outside=\(geometry.outsideBars.top) cameraOffset=\(geometry.topMarginHeight)")

    let p = panelConstraints
    p.topBarBtmOffsetFromVPTop.constraint?.animateToConstant(geometry.insideBars.top)
    p.vpTopOffsetFromTopBarTop.constraint?.animateToConstant(geometry.outsideBars.top)
    p.vpTopOffsetFromCVTop.constraint?.animateToConstant(geometry.outsideBars.top + geometry.topMarginHeight)
  }

  // - Bottom bar

  private func updateBottomBarHorizontalContraints(bottomBarPlacement: Preference.PanelPlacement,
                                                   useLeadingSidebar: Bool, useTrailingSidebar: Bool, _ log: Logger.Subsystem) {
    guard let window = window, let contentView = window.contentView else { return }
    let p = panelConstraints

    log.verbose("Updating bottomBar placement to: \(bottomBarPlacement) leadingSB=\(useLeadingSidebar.yn) trailingSB=\(useTrailingSidebar.yn)")

    // - Leading

    let leadingSpacePartner: NSLayoutXAxisAnchor
    if bottomBarPlacement == .insideViewport && useLeadingSidebar {
      // Align left & right sides with sidebars (bottom bar will squeeze to make space for sidebars)
      assert(leadingSidebarView.superview != nil)
      leadingSpacePartner = leadingSidebarView.trailingAnchor
    } else {
      // Left side of bottomBar is flush with left edge of window (leading sidebar is behind bottom bar visually)
      leadingSpacePartner = contentView.leadingAnchor
    }

    p.bottomBarLeadingSpace.createOrUpdate(to: 0, requiredSecondAnchor: leadingSpacePartner, log) { [self] c in
      return bottomBarView.leadingAnchor.constraint(equalTo: leadingSpacePartner, constant: c)
    }

    // - Trailing

    let trailingSpacePartner: NSLayoutXAxisAnchor
    if bottomBarPlacement == .insideViewport && useTrailingSidebar {
      assert(trailingSidebarView.superview != nil)
      trailingSpacePartner = trailingSidebarView.leadingAnchor
    } else {
      trailingSpacePartner = contentView.trailingAnchor
    }

    p.bottomBarTrailingSpace.createOrUpdate(to: 0, requiredSecondAnchor: trailingSpacePartner, log) { [self] c in
      return bottomBarView.trailingAnchor.constraint(equalTo: trailingSpacePartner, constant: c)
    }
  }

  // MARK: - Title bar items

  func updateTitleBarUI(from layoutState: LayoutState) {
    guard let window else { return }
    updateColorsForKeyWindowStatus(isKey: window.isKeyWindow)
    let enableGlow = Preference.bool(for: .titleBarBtnsGlow)
    // Leading sidebar toggle button
    for button in [leadingSidebarToggleButton, customTitleBar?.leadingSidebarToggleButton].compactMap({$0}) {
      if layoutState.leadingSidebarToggleButton.isShowable {
        button.setGlowForTitleBar(enabled: enableGlow && layoutState.leadingSidebar.isVisible)
      }
      fadeableViews.applyVisibility(layoutState.leadingSidebarToggleButton, button)
    }
    // Trailing sidebar toggle button
    for button in [trailingSidebarToggleButton, customTitleBar?.trailingSidebarToggleButton].compactMap({$0}) {
      if layoutState.trailingSidebarToggleButton.isShowable {
        button.setGlowForTitleBar(enabled: enableGlow && layoutState.trailingSidebar.isVisible)
      }
      fadeableViews.applyVisibility(layoutState.trailingSidebarToggleButton, button)
    }

    updateOnTopButton(from: layoutState, showIfFadeable: false)

    // Title bar accessories (to cover native windowed mode):
    fadeableViews.applyVisibility(layoutState.titlebarAccessoryViewControllers, to: leadingTitleBarAccessoryView)
    fadeableViews.applyVisibility(layoutState.titlebarAccessoryViewControllers, to: trailingTitleBarAccessoryView)
  }

  /// Hides all the various buttons of the built-in title bar, some of which can have strange quirks.
  ///
  /// Note: there is an Apple bug (as of MacOS 13.3.1) where setting `alphaValue=0` on `miniaturizeButton` will
  /// cause `window.performMiniaturize()` to be ignored. So to hide these, use `isHidden=true` + `alphaValue=1`
  /// (except for temporary animations).
  ///
  /// Note 2: do not touch `titleVisibility` if at all possible. There seems to be no reliable way to toggle it
  /// while also guaranteeing that `documentIcon` & `titleTextField` are shown/hidden consistently.
  /// Setting `isHidden=true` on `titleTextField` and `documentIcon` do not animate and do not always work.
  /// We can use `alphaValue=0` to fade out in `fadeOutOldViews()`, but `titleVisibility` is needed to remove them.
  /// We can work around the problem by (1) inserting or removing `.titled` from the window's style mask, which
  /// effectively swaps the whole title bar in or out), and (2) in native windowed mode, *always* show the title bar when
  /// the mouse hovers over it, because even if we set the document icon's alpha to 0, the user can still click on it.
  func hideNativeTitleBarViews(andSetAlpha setAlpha: Bool) {
    if setAlpha {
      documentIconButton?.alphaValue = 0
      titleTextField?.alphaValue = 0
    }
    documentIconButton?.isHidden = true
    titleTextField?.isHidden = true
    for button in trafficLightButtons {
      /// Special case for fullscreen transition due to quirks of `trafficLightButtons`.
      /// In most cases it's best to avoid setting `alphaValue = 0` for these because doing so will disable their menu items,
      /// but should be ok for brief animations
      if setAlpha {
        button.alphaValue = 0
      }
      button.isHidden = false
    }
  }

  /// Special case for these because their instances may change. Do not use `fadeableViews`. Always set `alphaValue = 1`.
  func showNativeTitleBarViews() {
    for button in trafficLightButtons {
      button.alphaValue = 1
      button.isHidden = false
    }
    titleTextField?.isHidden = false
    titleTextField?.alphaValue = 1
    documentIconButton?.isHidden = false
    documentIconButton?.alphaValue = 1
  }

  func updateOnTopButton(from layout: LayoutState, showIfFadeable: Bool = false) {
    let onTopButtonVisibility = layout.computeOnTopButtonVisibility(isOnTop: isOnTop)
    let image = isOnTop ? Images.onTopOn : Images.onTopOff
    log.trace{"Updating onTopButton: visible=\(onTopButtonVisibility) selected=\(isOnTop.yn)"}

    for button in [onTopButton, customTitleBar?.onTopButton].compactMap({$0}) {
      button.replaceSymbolImage(with: image, effect: nil)
      button.setGlowForTitleBar(enabled: Preference.bool(for: .titleBarBtnsGlow) && isOnTop)
      fadeableViews.applyVisibility(onTopButtonVisibility, to: button)
    }

    // Indicate button change
    if showIfFadeable, onTopButtonVisibility == .showFadeableTopBar {
      showFadeableViews(forceShowTopBar: true)
    }
  }

  // MARK: - Private support functions

  /// Remove the tab group view associated with `group` from its parent view (also removes constraints)
  private func removeSidebarTabGroupView(group: Sidebar.TabGroup) {
    log.verbose("Removing sidebar tab group view for \(group)")
    let viewController: NSViewController
    switch group {
    case .playlist:
      viewController = playlistView
    case .settings:
      viewController = quickSettingView
    case .plugins:
      viewController = pluginView
    }
    viewController.view.removeFromSuperview()
  }

  /// Need to call this after adding a new subview to `window.contentView` to ensure ordering of subviews is correct.
  ///
  /// After bars are shown or hidden, or their placement changes, this ensures that their shadows appear in the correct places.
  /// • Outside bars never cast shadows or have shadows cast on them.
  /// • Inside sidebars cast shadows over inside top bar & inside bottom bar, and over `viewportView`.
  /// • Inside top & inside bottom bars do not cast shadows over `viewportView`.
  private func sortContentViewSubviews(for layout: LayoutState) {
    var possibleSubviews: [NSView] = []

    // If a sidebar is "outsideViewport", need to put it behind the video because:
    // (1) Don't want sidebar to cast a shadow on the video
    // (2) Animate sidebar open/close with "slide in" / "slide out" from behind the video
    if layout.leadingSidebarPlacement == .outsideViewport {
      possibleSubviews.append(leadingSidebarView)
    }
    if layout.trailingSidebarPlacement == .outsideViewport {
      possibleSubviews.append(trailingSidebarView)
    }

    possibleSubviews.append(viewportView)

    if layout.bottomBarPlacement == .insideViewport {
      possibleSubviews.append(bottomBarView)
    }
    if layout.leadingSidebarPlacement == .insideViewport {
      possibleSubviews.append(leadingSidebarView)
    }
    if layout.trailingSidebarPlacement == .insideViewport {
      possibleSubviews.append(trailingSidebarView)
    }

    if layout.bottomBarPlacement == .outsideViewport {
      possibleSubviews.append(bottomBarView)
    }

    possibleSubviews += [
      seekPreview.thumbnailPeekView,
      seekPreview.timeLabel,
      topBarView,
      closeButtonView,
      customWindowBorderBox,
      customWindowBorderTopHighlightBox]

    let contentView = window!.contentView!
    let correctOrderedSubviews = possibleSubviews.filter { contentView.containsSubview($0) }

    log.verbose("ContentView panels: \(correctOrderedSubviews.map{$0.idString})")
    for subview in correctOrderedSubviews {
      contentView.addSubview(subview, positioned: .above, relativeTo: nil)
    }
  }

}
