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
    let cvBtmOffsetFromBottomBarBtm = OptionalConstraint("CV.btm-offset-from-BottomBar.btm")

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
    let isFinalStage = stage.isFinalStage
    let useLeadingSidebar = isFinalStage ? transition.outputLayout.isLeadingSidebarVisible : transition.inputLayout.isLeadingSidebarVisible || transition.outputLayout.isLeadingSidebarVisible
    let useTrailingSidebar = isFinalStage ? transition.outputLayout.isTrailingSidebarVisible : transition.inputLayout.isTrailingSidebarVisible || transition.outputLayout.isTrailingSidebarVisible
    let useBottomBar = isFinalStage ? transition.outputLayout.hasBottomBar : transition.inputLayout.hasBottomBar || transition.outputLayout.hasBottomBar
    let useTopBar = isFinalStage ? transition.outputLayout.hasTopBar : transition.inputLayout.hasTopBar || transition.outputLayout.hasTopBar

    log.verbose("RebuildPanels: VP=\(useViewport.yn) Bottom=\(useBottomBar.yn) Top=\(useTopBar.yn) Leading=\(useLeadingSidebar.yn) Trailing=\(useTrailingSidebar.yn)")

    // - Add window subviews in a well-defined order (before adding constraints between them)
    addOrRemoveViews(for: stage, stageGeo: stageGeo, log,
                     useViewport: useViewport,
                     useTopBar: useTopBar,
                     useBottomBar: useBottomBar,
                     useLeadingSidebar: useLeadingSidebar,
                     useTrailingSidebar: useTrailingSidebar)

    // - Constraints

    let outputGeo = transition.outputGeometry

    // Weaken constraints while modifying them to avoid violation errors
    p.vpTopOffsetFromTopBarTop.weaken()
    p.topBarBtmOffsetFromVPTop.weaken()
    p.bottomBarTopOffsetFromCVTop.weaken()
    p.vpBtmOffsetFromTopOfBottomBar.weaken()
    p.bottomBarBtmOffsetFromVPBtm.weaken()
    topBar.titleBarHeightConstraint.priority = .minimum
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
      log.verbose("TopBar: vpTopOffsetFromTopBarTop=\(outsideTopBarHeight) topBarBtmOffsetFromVPTop=\(insideTopBarHeight)")

      p.vpTopOffsetFromTopBarTop.createOrUpdate(to: outsideTopBarHeight, log) { [self] c in
        viewportView.topAnchor.constraint(equalTo: topBar.view.topAnchor, constant: c)
      }

      // Don't use required priority, as sometimes this causes constraint violations
      p.topBarBtmOffsetFromVPTop.createOrUpdate(to: insideTopBarHeight, log) { [self] c in
        topBar.view.bottomAnchor.constraint(equalTo: viewportView.topAnchor, constant: c)
      }

      if stage == .openNewPanels, transition.isExitingNativeFullScreen {
        log.verbose("Updating titleBarHeight=\(0) for exiting native FS")
        topBar.titleBarHeightConstraint.animateToConstant(0)
      } else {
        let titleHeight = min(stageLayout.titleBarHeight, stageGeo.topBarHeight)  // do not make titleBar larger than top bar
        log.verbose("Updating titleBarHeight=\(Int(titleHeight))")
        topBar.titleBarHeightConstraint.animateToConstant(titleHeight)
      }

      // Not sure why when we make this `.required`, we get a bogus constraint violation
      topBar.titleBarHeightConstraint.priority = .defaultHigh
    }

    let isAnimatingViewportOpen = transition.isOpeningViewport && !stage.isFinalStage  // Music Mode: opening video
    if useBottomBar && (!outputGeo.isViewportShown || isAnimatingViewportOpen) {
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
    if useBottomBar && useViewport && !isAnimatingViewportOpen {
      let constant1 = stageGeo.vpBtmOffsetFromTopOfBottomBar
      let constant2 = stageGeo.bottomBarBtmOffsetFromVPBtm
      log.verbose("BottomBar & Viewport: vpBtmOffsetFromTopOfBottomBar=\(Int(constant1)) bottomBarBtmOffsetFromVPBtm=\(Int(constant2))")

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
      let bottomBarPlacement = stageLayout.bottomBarPlacement
      log.verbose("Updating bottomBar placement to \(bottomBarPlacement), HasLeadingSB=\(useLeadingSidebar.yn) HasTrailingSB=\(useTrailingSidebar.yn)")

      // - Leading

      let leadingSpacePartner: NSLayoutXAxisAnchor
      if bottomBarPlacement == .insideViewport && useLeadingSidebar {
        // Align left & right sides with sidebars (bottom bar will squeeze to make space for sidebars)
        leadingSpacePartner = leadingSidebarView.trailingAnchor
      } else {
        // Left side of bottomBar is flush with left edge of window (leading sidebar is behind bottom bar visually)
        leadingSpacePartner = contentView.leadingAnchor
      }

      p.bottomBarLeadingSpace.createOrUpdate(to: 0, requiredSecondAnchor: leadingSpacePartner, log) { [self] c in
        bottomBarView.leadingAnchor.constraint(equalTo: leadingSpacePartner, constant: c)
      }

      // - Trailing

      let trailingSpacePartner: NSLayoutXAxisAnchor
      if bottomBarPlacement == .insideViewport && useTrailingSidebar {
        trailingSpacePartner = trailingSidebarView.leadingAnchor
      } else {
        trailingSpacePartner = contentView.trailingAnchor
      }

      p.bottomBarTrailingSpace.createOrUpdate(to: 0, requiredSecondAnchor: trailingSpacePartner, log) { [self] c in
        bottomBarView.trailingAnchor.constraint(equalTo: trailingSpacePartner, constant: c)
      }

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

      contentView.needsLayout = true
      bottomBarView.needsLayout = true
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

    // This constraint is needed for:
    // 1. Ensuring "toggle viewport" & "toggle playlist" animations work properly in music mode.
    // 2. Workaround for bug in music mode where viewport closes unexpectedly.
    // - Do not use priority=1000 because it may be off by a pixel.
    // - Do not use priority >= 500 because it will prevent window resize.
    if useViewport, !stage.isFinalStage,
       (transition.isTogglingViewport || transition.isTogglingPlaylistInMusicMode) {
      let constant3 = stageGeo.vpBtmOffsetFromCVTop

      p.vpBtmOffsetFromCVTop.createOrUpdate(to: constant3, priorityInt: 499, log) { [self] c in
        viewportView.bottomAnchor.constraint(equalTo: contentView.topAnchor, constant: c)
      }
    } else {
      p.vpBtmOffsetFromCVTop.remove(log)
    }

    if useViewport {
      let constant1 = stageGeo.vpTopOffsetFromCVTop
      let constant2 = stageGeo.cvBtmOffsetFromVPBtm
      log.verbose("Viewport: vpTopOffsetFromCVTop=\(Int(constant1)) cvBtmOffsetFromVPBtm=\(Int(constant2)) vpLeadingOffsetFromCVLeading=0 vpTrailingOffsetFromCVTrailing=0")

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
    updateConstraintsForFloatingViews(stageGeo: stageGeo, hasLeadingSidebar: useLeadingSidebar, hasTrailingSidebar: useTrailingSidebar)

    // Must execute this *before* sidebars logic below, which may alter their orders
    sortContentViewSubviews(for: stageLayout, in: transition)

    updateWindowFrameIfNeeded(for: stage, stageGeo, in: transition, log)
  }

  private func addOrRemoveViews(for stage: LayoutTransition.Stage, stageGeo: PWinGeometry, _ log: any Logger.Subsystem,
                                useViewport: Bool,
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
      if !contentView.containsSubview(topBar.view) {
        log.verbose("Adding topBarView to window contentView")
        contentView.addSubview(topBar.view, positioned: .above, relativeTo: viewportView)

        // These constraints don't change as long as topBarView is attached
        let topBarLeadingSpaceConstraint = topBar.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        topBarLeadingSpaceConstraint.identifier = "TopBar.leading-offset-from-CV.leading"
        topBarLeadingSpaceConstraint.isActive = true

        let topBarTrailingSpaceConstraint = topBar.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
        topBarTrailingSpaceConstraint.identifier = "TopBar.trailing-offset-from-CV.trailing"
        topBarTrailingSpaceConstraint.isActive = true
      }
    } else {
      if topBar.view.superview != nil {
        log.verbose("Removing topBarView from superview")
        topBar.view.removeFromSuperview()
      }
    }

    // Need to add additionalInfo, OSD before changing sidebars
    addOrRemoveFloatingViews(for: stage, stageGeo)
  }

  private func updateSidebarConstraints(for stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry,
                                        in transition: LayoutTransition,
                                        _ log: any Logger.Subsystem) {
    let hasSidebarAtAnyStage = transition.inputGeometry.isMusicModePlaylistShown || transition.outputGeometry.isMusicModePlaylistShown
    || transition.inputLayout.isAnySidebarVisible || transition.outputLayout.isAnySidebarVisible
    guard hasSidebarAtAnyStage else { return }

    var sidebarUpdateGeo: PWinGeometry? = nil
    if transition.isTogglingNativeFullScreen {
      sidebarUpdateGeo = transition.outputGeometry
    }

    // - Sidebars
    switch stage {
    case .preTransitionSetup:
      sidebarUpdateGeo = sidebarUpdateGeo ?? stageGeo
      // Need this immediately becuase sometimes (e.g. when opening sidebar) other constraints may expect sidebar(s)
      // to be attached already:
      if !transition.inputLayout.isMusicMode {
        prepareSidebarsForOpening(transition, stage, stageGeo, log)
      }

    case .closeOldPanels:
      assert(!transition.isWindowInitialLayout)
      // Sidebars (if closing)
      animateShowOrHideSidebars(from: transition.inputGeometry,
                                to: stageGeo,
                                isInitialLayout: transition.isWindowInitialLayout, log)

      if sidebarUpdateGeo == nil {
        if transition.isExitingMusicMode {
          // Use music mode tab height
          sidebarUpdateGeo = transition.inputGeometry
        } else {
          // Update sidebar vertical alignments to match top bar:
          sidebarUpdateGeo = stageGeo
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

      prepareSidebarsForOpening(transition, stage, stageGeo, log)

      if sidebarUpdateGeo == nil {
        if transition.isEnteringMusicMode {
          // Use music mode tab height
          sidebarUpdateGeo = transition.outputGeometry
        } else {
          // Update sidebar vertical alignments to match top bar:
          sidebarUpdateGeo = stageGeo
        }
      }

    case .extraAnimationBeforeOpenNewPanels:
      sidebarUpdateGeo = sidebarUpdateGeo ?? stageGeo

    case .openNewPanels:
      if transition.isWindowInitialLayout {
        // Need to run this now because intiial layout doesn't run the midTransitionHiddenUpdates step
        prepareSidebarsForOpening(transition, stage, stageGeo, log)
      }

      // Sidebars (if opening)
      animateShowOrHideSidebars(from: transition.geometry(for: .midTransitionHiddenUpdates),
                                to: transition.outputGeometry,
                                isInitialLayout: transition.isWindowInitialLayout, log)

      sidebarUpdateGeo = sidebarUpdateGeo ?? stageGeo

    case .postTransition:
      break
    }

    if let sidebarUpdateGeo {
      updateSidebarVerticalConstraints(using: sidebarUpdateGeo)
    }
  }

  /// Make sure this is called AFTER `windowController.setupTitleBarAndOSC()` has updated its variables
  private func updateSidebarVerticalConstraints(using targetGeo: PWinGeometry) {
    let downshift = targetGeo.sidebarDownshift
    let tabHeight = targetGeo.sidebarTabHeight
    log.verbose("Updating sidebars: downshift=\(downshift) tabHeight=\(tabHeight)")
    quickSettingView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
    playlistView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
    pluginView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
  }


  private func updateWindowFrameIfNeeded(for stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry,
                                         in transition: LayoutTransition,
                                         _ log: any Logger.Subsystem) {
    let updateVP: Bool
    var category: TransitionCategory = .none
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
      if transition.isExitingMusicMode {
        updateVP = true
      } else {
        // For some reason, updating videoView constraints here causes a visual glich, so skip it (updateVP: false).
        // It's not needed until the next step anyway.
        updateVP = false
      }
    case .midTransitionHiddenUpdates:
      if transition.isTogglingFullScreen {
        // Wait until next stage
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
      if stageGeo.mode == .musicMode, transition.outputGeometry.isViewportShown {
        updateVP = true
      } else {
        // Not needed for this stage
        return
      }
    }

    log.verbose("Calling setFrame with \(stageGeo.windowFrame) mode=\(stageGeo.mode) updateVP=\(updateVP.yn) category=\(category)")
    applyPWinGeometry(stageGeo,
                      updateViewportConstraints: updateVP && !transition.isTogglingFullScreen,
                      category)
  }

  private func prepareSidebarsForOpening(_ transition: LayoutTransition,
                                         _ stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry,
                                         _ log: any Logger.Subsystem) {
    // Make sure we do not step on any animations to clse sidebars
    let isPastClosingStage = stage.isAtLeast(.midTransitionHiddenUpdates)

    let outputLayout = transition.outputLayout

    if transition.isOpeningLeadingSidebar, isPastClosingStage || !transition.isClosingLeadingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(leadingSidebar: transition.outputLayout.leadingSidebar,
                              layout: transition.outputLayout,
                              isWindowWidthChanging: transition.ΔWindowWidth != 0,
                              addTabGroupView: isPastClosingStage,
                              log)
    }
    if transition.isOpeningTrailingSidebar, isPastClosingStage || !transition.isClosingTrailingSidebar {
      // Opening sidebar from closed state
      prepareLayoutForOpening(trailingSidebar: transition.outputLayout.trailingSidebar,
                              layout: transition.outputLayout,
                              isWindowWidthChanging: transition.ΔWindowWidth != 0,
                              addTabGroupView: isPastClosingStage,
                              log)
    }

    guard isPastClosingStage else { return }

    // I already showing but need to change tab group
    if let visibleTab = outputLayout.leadingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
    }

    // If already showing but need to change tab group
    if let visibleTab = outputLayout.trailingSidebar.visibleTab {
      switchToTabInTabGroup(tab: visibleTab)
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
  }

  // - Top bar

  func updateTopBarHeight(using geometry: PWinGeometry) {
    log.verbose("Updating topBar height to: inside=\(geometry.insideBars.top) outside=\(geometry.outsideBars.top) cameraOffset=\(geometry.topMarginHeight)")

    let p = panelConstraints
    p.topBarBtmOffsetFromVPTop.constraint?.animateToConstant(geometry.insideBars.top)
    p.vpTopOffsetFromTopBarTop.constraint?.animateToConstant(geometry.outsideBars.top)
    p.vpTopOffsetFromCVTop.constraint?.animateToConstant(geometry.outsideBars.top + geometry.topMarginHeight)
  }

  func updateOnTopButton(from layout: LayoutState, showIfFadeable: Bool = false) {
    let onTopButtonVisibility = layout.computeOnTopButtonVisibility(isOnTop: isOnTop)
    let image = isOnTop ? Images.onTopOn : Images.onTopOff
    log.trace("Updating onTopButton: visible=\(onTopButtonVisibility) selected=\(isOnTop.yn)")

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
      topBar.view
    ]
    if let customTitleBar {  // only for music mode
      possibleSubviews.append(customTitleBar.view)
    }
    possibleSubviews += [
      exitMusicModeButton,
      customWindowBorderBox,
      customWindowBorderTopHighlightBox,
      hdrWorkaroundView  // this must always be topmost!
    ]

    let contentView = window!.contentView!
    let correctOrderedSubviews = possibleSubviews.filter { contentView.containsSubview($0) }

    log.verbose("ContentView panels: \(correctOrderedSubviews.map{$0.idString})")
    for subview in correctOrderedSubviews {
      contentView.addSubview(subview, positioned: .above, relativeTo: nil)
    }
  }

}
