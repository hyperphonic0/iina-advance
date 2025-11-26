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
  /// Note the consistent direction between anchors. (Created with https://asciip.dev/.)
  ///```
  /// ┌─ Top                                                                ┬  ┬  ┬  ┬
  /// │                                                                     │  │  │  │
  /// │window                                                               │  │  │  │vpTopOffsetFromCVTop¹
  /// │contentView      ┌─────────────┐  ┬                                  │  │  │  │
  /// │                 │ TopBar (TB) │  │vpTopOffsetFromTopBarTop          │  │  │  │
  /// │        ┌────────│──────┐      │  ▼  ┬                               │  │  │  ▼
  /// │        │        │      │      │     │topBarBtmOffsetFromVPTop       │  │  │
  /// │        │        └─────────────┘     ▼                               │  │  │
  /// │        │ Viewport (VP) │                                            │  │  │bottomBarTopOffsetFromCVTop⁴
  /// │  ┌─────────────┐       │     ┬                                ┬     │  │  ▼
  /// │  │     │       │       │     │vpBtmOffsetFromTopOfBottomBar   │     │  │vpBtmOffsetFromCVTop¹
  /// │  │     └───────│───────┘  ┬  ▼                                │  ┬  │  ▼
  /// │  │  BottomBar  │          │bottomBarBtmOffsetFromVPBtm¹       │  │  │bottomBarBtmOffsetFromCVTop⁵
  /// │  └─────────────┘    ┬     ▼                                   │  │  ▼
  /// │                     │                                         │  │
  /// │                     │cvBtmOffsetFromBottomBarBtm              │  │
  /// │                     │                                         │  │
  /// │                     │              cvBtmOffsetFromBottomBarTop│  │cvBtmOffsetFromVPBtm
  /// └─ Bottom             ▼                                         ▼  ▼
  ///```
  /// - ¹Equals `outsideBars.top + topMarginHeight`
  /// - ⁴Only used when bottomBar is shown & viewport is hidden.
  /// - ⁵Only used when animating music mode when both video & playlist are hidden.
  struct PanelConstraints {
    // - Viewport + TopBar (V)
    let topBarBtmOffsetFromVPTop = OptionalConstraint("TopBar.btm-offset-from-VP.top")
    let vpTopOffsetFromTopBarTop = OptionalConstraint("VP.top-offset-from-TopBar.top")

    // - Viewport (V)
    let vpTopOffsetFromCVTop = OptionalConstraint("VP.top-offset-from-CV.top")
    let vpBtmOffsetFromCVTop = OptionalConstraint("VP.btm-offset-from-CV.top")
    let cvBtmOffsetFromVPBtm = OptionalConstraint("CV.btm-offset-from-VP.btm")

    // - Viewport (H)
    let vpLeadingOffsetFromCVLeading = OptionalConstraint("VP.leading-offset-from-CV.leading")
    let vpTrailingOffsetFromCVTrailing = OptionalConstraint("CV.trailing-offset-from-VP.trailing")

    // - Viewport + BottomBar (V)
    let vpBtmOffsetFromTopOfBottomBar = OptionalConstraint("VP.btm-offset-from-BottomBar.top")
    let bottomBarBtmOffsetFromVPBtm = OptionalConstraint("BottomBar.btm-offset-from-VP.btm")

    // - BottomBar (V)
    let cvBtmOffsetFromBottomBarTop = OptionalConstraint("CV.btm-offset-from-BottomBar.top")
    let bottomBarTopOffsetFromCVTop = OptionalConstraint("BottomBar.top-offset-from-CV.top")
    let bottomBarBtmOffsetFromCVTop = OptionalConstraint("BottomBar.btm-offset-from-CV.top")
    let cvBtmOffsetFromBottomBarBtm = OptionalConstraint("BottomBar.btm-offset-from-BottomBar.btm")

    // - BottomBar (H)
    // Needs to be changed to align with either sidepanel or leading edge of window:
    let bottomBarLeadingSpace = OptionalConstraint("BottomBar.leading-space")
    // Needs to be changed to align with either sidepanel or trailing edge of window:
    let bottomBarTrailingSpace = OptionalConstraint("BottomBar.trailing-space")
  }

  // MARK: - Bars Layout

  func rebuildPanelConstraints(_ transition: LayoutTransition, stage: LayoutTransition.Stage) {
    let contentView = window!.contentView!
    let p = panelConstraints
    let log = Logger.addPreamble(transition.logPreamble(for: stage), toSubsystem: self.log)
    let stageGeo = transition.geometry(for: stage)

    // Need to always have viewportView during animations (when toggling music mode with video off)
    let useViewport = transition.outputGeometry.isViewportShown || (!stage.isFinalStage && transition.inputGeometry.isViewportShown)

    let stageLayout: LayoutState = transition.targetLayout(for: stage)
    // We need to include constraints for some panels in multiple stages if they are open at any point
    let useLeadingSidebar = stageLayout.isLeadingSidebarVisible
    let useTrailingSidebar = stageLayout.isTrailingSidebarVisible
    let useBottomBar: Bool = stageLayout.hasBottomBar
    let useTopBar: Bool
    if transition.isTogglingFullScreen {
      // FIXME: there is a bug in an offset somewhere in native FS
      useTopBar = transition.outputLayout.hasTopBar || (!stage.isFinalStage && transition.inputLayout.hasTopBar)
    } else {
      useTopBar = stageLayout.hasTopBar
    }

    log.verbose("RebuildPanels: VP=\(useViewport.yn) Bottom=\(useBottomBar.yn) Top=\(useTopBar.yn) Leading=\(useLeadingSidebar.yn) Trailing=\(useTrailingSidebar.yn)")

    // - Add window subviews in a well-defined order (before adding constraints between them)
    addOrRemoveViews(for: stage, stageGeo: stageGeo,
                     useViewport: useViewport,
                     useTopBar: useTopBar,
                     useBottomBar: useBottomBar,
                     useLeadingSidebar: useLeadingSidebar,
                     useTrailingSidebar: useTrailingSidebar)

    // - Constraints

    log.verbose("RebuildPanels: VP=\(Int(viewportView.frame.height)) BottomH=\(Int(bottomBarView.frame.height)) Top=\(Int(topBarView.frame.height))")
    let outputGeo = transition.outputGeometry

    // Weaken constraints while modifying them to avoid violation errors
    p.vpTopOffsetFromTopBarTop.weaken()
    p.topBarBtmOffsetFromVPTop.weaken()
    p.bottomBarTopOffsetFromCVTop.weaken()
    p.vpBtmOffsetFromTopOfBottomBar.weaken()
    p.bottomBarBtmOffsetFromVPBtm.weaken()
    topBarView.titleBarHeightConstraint.priority = .minimum
    p.bottomBarBtmOffsetFromCVTop.weaken()
    p.cvBtmOffsetFromBottomBarBtm.weaken()
    p.vpBtmOffsetFromCVTop.weaken()
    p.cvBtmOffsetFromBottomBarTop.weaken()
    p.vpTopOffsetFromCVTop.weaken()
    p.cvBtmOffsetFromVPBtm.weaken()

    if useTopBar {

      assert(useViewport, "Cannot use topBarView without viewportView")
      let outsideTopBarHeight = stageGeo.vpTopOffsetFromTopBarTop
      let insideTopBarHeight = stageGeo.topBarBtmOffsetFromVPTop
      log.verbose("Updating topBar: vpTopOffsetFromTopBarTop=\(outsideTopBarHeight) topBarBtmOffsetFromVPTop=\(insideTopBarHeight)")

      p.vpTopOffsetFromTopBarTop.createOrUpdate(to: outsideTopBarHeight, log) { [self] c in
        viewportView.topAnchor.constraint(equalTo: topBarView.topAnchor, constant: c)
      }

      // Don't use required priority, as sometimes this causes constraint violations
      p.topBarBtmOffsetFromVPTop.createOrUpdate(to: insideTopBarHeight, log) { [self] c in
        topBarView.bottomAnchor.constraint(equalTo: viewportView.topAnchor, constant: c)
      }

      if stage == .closeOldPanels, let middleGeo = transition.closeOldPanelsGeometry, middleGeo.topBarHeight == 0 {
        log.verbose("Updating titleHeight=\(0)")
        topBarView.titleBarHeightConstraint.animateToConstant(0)
      } else {
        let titleHeight = min(stageLayout.titleBarHeight, stageGeo.topBarHeight)  // do not make titleBar larger than top bar
        log.verbose("Updating titleHeight=\(Int(titleHeight))")
        topBarView.titleBarHeightConstraint.animateToConstant(titleHeight)
      }
    }

    let isAnimatingVideoViewOpen = transition.isOpeningViewport && !stage.isFinalStage  // Music Mode: opening video
    if useBottomBar && (!outputGeo.isViewportShown || isAnimatingVideoViewOpen) {
      let constant1 = stageGeo.bottomBarTopOffsetFromCVTop
      // Do not use "required" priority - can cause errors leaving music mode when video was hidden
      p.bottomBarTopOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
        bottomBarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }
    } else {
      // Need to manually remove this one because it doesn't depend on viewportView, & thus won't get removed if/when viewport gets removed.
      p.bottomBarTopOffsetFromCVTop.remove(log)
    }

    // BottomBar + Viewport
    if useBottomBar && useViewport && !isAnimatingVideoViewOpen {
      let constant1 = stageGeo.vpBtmOffsetFromTopOfBottomBar
      let constant2 = stageGeo.bottomBarBtmOffsetFromVPBtm
      log.verbose("Updating bottomBar & viewport: vpBtmOffsetFromTopOfBottomBar=\(Int(constant1)) bottomBarBtmOffsetFromVPBtm=\(Int(constant2))")

      p.vpBtmOffsetFromTopOfBottomBar.createOrUpdate(to: constant1, log) { [self] c in
        viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: c)
      }

      // In music mode, need to be lower priority than VideoView constraints. Otherwise live resize of window will break.
      // Leave as lower priority always - doesn't seem to hurt, and prevent conflicting constraints
      p.bottomBarBtmOffsetFromVPBtm.createOrUpdate(to: constant2, priorityInt: 260, log) { [self] c in
        bottomBarView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor, constant: c)
      }
    }

    // - Bottom Bar
    if useBottomBar {
      // Handle leading & trailing constraints
      updateBottomBarHorizontalContraints(bottomBarPlacement: stageLayout.bottomBarPlacement,
                                          useLeadingSidebar: useLeadingSidebar,
                                          useTrailingSidebar: useTrailingSidebar, log)

      // enable for animations or if in music mode & neither playlist nor video is open
      if outputGeo.mode == .musicMode && !stage.isFinalStage && !outputGeo.isMusicModePlaylistShown && !outputGeo.isViewportShown {
        let constant1 = stageGeo.bottomBarBtmOffsetFromCVTop
        p.bottomBarBtmOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
          bottomBarView.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
        }
      } else {
        // remove
        p.bottomBarBtmOffsetFromCVTop.remove(log)
      }

      // This will always have constant: 0
      p.cvBtmOffsetFromBottomBarBtm.createOrUpdate(to: 0, log) { [self] c in
        contentView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: c)
      }

    }

    // - Viewport View

    if useBottomBar,
       (stage.isFinalStage && !stageGeo.isViewportShown && !stageGeo.isMusicModePlaylistShown)  // Is only showing music mode OSC. Keep height fixed
        || (transition.isTogglingViewport && !stage.isFinalStage) // Is animating show/hide of viewport in music mode. Keep OSC & playlist height fixed
    {
      let bottomBarHeight = stageGeo.bottomBarHeight
      p.cvBtmOffsetFromBottomBarTop.createOrUpdate(to: bottomBarHeight, log) { [self] c in
        contentView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: c)
      }
    } else {
      p.cvBtmOffsetFromBottomBarTop.remove(log)
    }

    // This constraint is only used during the animation. Do not use priority=1000 because it may be off by a pixel...
    if useViewport, (transition.isTogglingViewport || transition.isTogglingPlaylistInMusicMode), !stage.isFinalStage {
      let constant3 = stageGeo.vpBtmOffsetFromCVTop

      p.vpBtmOffsetFromCVTop.createOrUpdate(to: constant3, log) { [self] c in
        viewportView.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }
    } else {
      p.vpBtmOffsetFromCVTop.remove(log)
    }

    if useViewport {
      let constant1 = stageGeo.vpTopOffsetFromCVTop
      let constant2 = stageGeo.cvBtmOffsetFromVPBtm
      log.verbose("Updating viewport: vpTopOffsetFromCVTop=\(Int(constant1)) cvBtmOffsetFromVPBtm=\(Int(constant2)) vpLeadingOffsetFromCVLeading=0 vpTrailingOffsetFromCVTrailing=0")

      p.vpTopOffsetFromCVTop.createOrUpdate(to: constant1, log) { [self] c in
        viewportView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }

      if stage.isFinalStage && outputGeo.mode == .musicMode && outputGeo.isMusicModePlaylistShown {
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

    updateSidebarConstraints(for: stage, stageGeo, in: transition, log)

    // OSD constraints. Call this after calls to prepareLayoutForOpening(*Sidebar)
    updateOSDConstraints(for: stage, stageGeo)

    updateWindowFrameIfNeeded(for: stage, stageGeo, in: transition, log)

    // Must execute this *before* sidebars logic below, which may alter their orders
    sortContentViewSubviews(for: stageLayout, in: transition)
  }

  private func addOrRemoveViews(for stage: LayoutTransition.Stage, stageGeo: PWinGeometry, useViewport: Bool,
                                useTopBar: Bool, useBottomBar: Bool,
                                useLeadingSidebar: Bool, useTrailingSidebar: Bool) {
    let contentView = window!.contentView!

    // Add/remove viewportView if needed
    if useViewport {
      // This adds videoView, viewportView & spacers if not already added
      addViewportAndSubviewsToWindowIfNeeded()

    } else {
      if viewportView.superview != nil {
        log.verbose("Removing viewportView from superview")
        viewportView.removeFromSuperview()
      }
    }

    // Add/remove sidebars if needed
    if useLeadingSidebar {
      if !contentView.containsSubview(leadingSidebarView) {
        log.verbose("Adding leadingSidebarView to window contentView")
        contentView.addSubview(leadingSidebarView, positioned: .above, relativeTo: viewportView)
      }
    } else {
      leadingSidebarConstraints = nil  // disables constraints
      if leadingSidebarView.superview != nil {
        log.verbose("Removing leadingSidebarView from superview")
        leadingSidebarView.removeFromSuperview()
      }
    }
    if useTrailingSidebar {
      if !contentView.containsSubview(trailingSidebarView) {
        log.verbose("Adding trailingSidebarView to window contentView")
        contentView.addSubview(trailingSidebarView, positioned: .above, relativeTo: viewportView)
      }
    } else {
      trailingSidebarConstraints = nil  // disables constraints
      if trailingSidebarView.superview != nil {
        log.verbose("Removing trailingSidebarView from superview")
        trailingSidebarView.removeFromSuperview()
      }
    }


    // Add/remove bottomBarView if needed
    if useBottomBar {
      if !contentView.containsSubview(bottomBarView) {
        log.verbose("Adding bottomBarView to window contentView")
        contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)
      }
    } else {
      if bottomBarView.superview != nil {
        log.verbose("Removing bottomBarView from superview")
        bottomBarView.removeFromSuperview()
      }
    }

    // Add/remove topBarView if needed
    if useTopBar {
      if !contentView.containsSubview(topBarView) {
        log.verbose("Adding topBarView to window contentView")
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
      if topBarView.superview != nil {
        log.verbose("Removing topBarView from superview")
        topBarView.removeFromSuperview()
      }
    }

    // Need to add additionalInfo, OSD before changing sidebars
    addOrRemoveOSDViews(for: stage, stageGeo)
  }

  private func updateSidebarConstraints(for stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry, in transition: LayoutTransition, _ log: any Logger.Subsystem) {
    let hasSidebarAtAnyStage = transition.inputGeometry.isMusicModePlaylistShown || transition.outputGeometry.isMusicModePlaylistShown
    || transition.inputLayout.isAnySidebarVisible || transition.outputLayout.isAnySidebarVisible

    // - Sidebars
    switch stage {
    case .preTransitionSetup:
      updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)

    case .closeOldPanels:
      assert(!transition.isWindowInitialLayout)
      if hasSidebarAtAnyStage {
        // Sidebars (if closing)
        let ΔWindowWidth = stageGeo.windowFrame.width - transition.inputGeometry.windowFrame.width
        animateShowOrHideSidebars(transition.inputGeometry,
                                  leadingVisible: transition.isClosingLeadingSidebar ? false : nil,
                                  trailingVisible: transition.isClosingTrailingSidebar ? false : nil,
                                  ΔWindowWidth: ΔWindowWidth, log)

        if transition.isExitingMusicMode {
          // Use music mode tab height
          updateSidebarVerticalConstraints(tabHeight: transition.inputGeometry.sidebarTabHeight, downshift: transition.inputGeometry.sidebarDownshift)
        } else {
          // Update sidebar vertical alignments to match top bar:
          updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
        }
      }

    case .moveAndScale:
      break

    case .midTransitionHiddenUpdates:
      /// Remove views for closed sidebars *BEFORE* doing logic for opening: the same transition can be doing both
      if transition.isClosingLeadingSidebar, let tabGroupToHide = transition.inputLayout.leadingSidebar.visibleTabGroup {
        /// Finish closing (if closing)
        removeSidebarTabGroupView(group: tabGroupToHide)
      }
      if transition.isClosingTrailingSidebar, let tabGroupToHide = transition.inputLayout.trailingSidebar.visibleTabGroup {
        /// Finish closing (if closing).
        /// If entering music mode, make sure to do this BEFORE moving `playlistView` down below:
        removeSidebarTabGroupView(group: tabGroupToHide)
      }

      prepareSidebarsForOpening(transition, stageGeo)

    case .extraAnimationBeforeOpenNewPanels:
      if hasSidebarAtAnyStage {
        updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
      }

    case .openNewPanels:
      if transition.isWindowInitialLayout {
        // Need to run this now because intiial layout doesn't run the midTransitionHiddenUpdates step
        prepareSidebarsForOpening(transition, stageGeo)
      }
      if hasSidebarAtAnyStage {
        // Sidebars (if opening)
        let ΔWindowWidth = transition.ΔWindowWidth
        animateShowOrHideSidebars(transition.outputGeometry,
                                  leadingVisible: transition.isOpeningLeadingSidebar ? true : nil,
                                  trailingVisible: transition.isOpeningTrailingSidebar ? true : nil,
                                  ΔWindowWidth: ΔWindowWidth, log)

        updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
      }

    case .postTransition:
      break
    }
  }

  private func updateWindowFrameIfNeeded(for stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry, in transition: LayoutTransition, _ log: any Logger.Subsystem) {
    let updateVP: Bool
    var category: TransitionCategory = .noTransition
    switch stage {
    case .preTransitionSetup:
      // #InteractiveModeAnimationKludge
      // Needs to be no op for the Exit Interactive Mode kludge to work properly.
      return
    case .closeOldPanels:
      assert(!transition.isWindowInitialLayout)
      updateVP = true
      if transition.isExitingInteractiveMode {
        category = .exitingInteractiveMode
      }
    case .moveAndScale:
      // For some reason, updating videoView constraints here causes a visual glich, so skip it (updateVP: false).
      // It's not needed until the next step anyway.
      updateVP = false
    case .midTransitionHiddenUpdates:
      if transition.isEnteringFullScreen {
        // If entering FS, wait until next stage
        return
      }

      updateVP = true
      if transition.isEnteringMusicMode {
        category = .enteringMusicMode
      } else if transition.isExitingMusicMode {
        category = .exitingMusicMode
      } else if transition.isOpeningViewport {
        category = .openingViewportInMusicMode
      } else if transition.isClosingViewport {
        category = .closingViewportInMusicMode
      } else if transition.isEnteringInteractiveMode {
        category = .enteringInteractiveMode
      } else if transition.isExitingInteractiveMode {
        category = .exitingInteractiveMode
      }
    case .extraAnimationBeforeOpenNewPanels:
      updateVP = true
    case .openNewPanels:
      updateVP = stageGeo.mode != .musicMode
    case .postTransition:
      updateVP = true
    }

    log.verbose("Calling setFrame with \(stageGeo.windowFrame) mode=\(stageGeo.mode) updateVP\(updateVP.yn) cat=\(category)")
    setFrameAndUpdateWindowSubviews(using: stageGeo, updateViewportConstraints: updateVP && !transition.isTogglingFullScreen, category)
  }

  @discardableResult
  private func prepareSidebarsForOpening(_ transition: LayoutTransition, _ stageGeo: PWinGeometry) -> Bool {
    let outputLayout = transition.outputLayout
    // Leading Sidebar - if already showing but need to change tab group
    if let visibleTab = outputLayout.leadingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
    }
    // Trailing Sidebar - if already showing but need to change tab group
    if let visibleTab = outputLayout.trailingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
    }

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

    if transition.isEnteringMusicMode {
      updateSidebarVerticalConstraints(tabHeight: transition.outputGeometry.sidebarTabHeight, downshift: transition.outputGeometry.sidebarDownshift)
    } else {
      updateSidebarVerticalConstraints(tabHeight: stageGeo.sidebarTabHeight, downshift: stageGeo.sidebarDownshift)
    }

    // Update bottom bar constraints *after* sidebars are added
    if transition.isOpeningAnySidebar {
      log.verbose("Sidebars will be open: LeadingSidebar=\(outputLayout.leadingSidebar.isVisible.yn) TrailingSidebar=\(outputLayout.trailingSidebar.isVisible.yn)")

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
                                                   useLeadingSidebar: Bool, useTrailingSidebar: Bool, _ log: any Logger.Subsystem) {
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
  private func sortContentViewSubviews(for layout: LayoutState, in transition: LayoutTransition) {
    var possibleSubviews: [NSView] = []

    var placedTrailingOutsideSidebar = false

    // If a sidebar is "outsideViewport", need to put it behind the video because:
    // (1) Don't want sidebar to cast a shadow on the video
    // (2) Animate sidebar open/close with "slide in" / "slide out" from behind the video
    if layout.leadingSidebarPlacement == .outsideViewport {
      /// This fixes an edge case when both sidebars are shown and are `.outsideViewport`. When one is toggled, and width of
      /// `videoView` is smaller than that of the sidebar being toggled, we must ensure that the sidebar being animated is below
      /// the other one. Otherwise it will be briefly seen popping out on top of the other one.
      if layout.trailingSidebarPlacement == .outsideViewport, transition.isOpeningTrailingSidebar || transition.isClosingTrailingSidebar {
        possibleSubviews.append(trailingSidebarView)
        placedTrailingOutsideSidebar = true
      }
      possibleSubviews.append(leadingSidebarView)
    }
    if layout.trailingSidebarPlacement == .outsideViewport, !placedTrailingOutsideSidebar {
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
      exitMusicModeButton,
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
