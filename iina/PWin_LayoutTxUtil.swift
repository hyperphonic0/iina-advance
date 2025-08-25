//
//  PWin_LayoutTxUtil.swift
//  iina
//
//  Created by Matt Svoboda on 8/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// This file contains support functions for the transition tasks found in `PWin_LayoutTxSteps.swift`.
extension PlayerWindowController {

  // MARK: - Bars Layout

  /// Add, remove, or modify each of the bars & their constraints based on the given stage of the layout
  /// transition.
  ///
  /// ┌─ Top                          ┬                                                   ┬
  /// │                               │                   ⁴bottomBarTopFromCVTopConstraint│
  /// │window                         │viewportTopOffsetFromCVTopConstraint               │
  /// │contentView      ┌───────────┐ │     ┬                                             │
  /// │                 │  TopBar   │ │     │viewportTopOffsetFromTopBarTopConstraint     │
  /// │        ┌────────│────┐      │ ▼  ┬  ▼                                             │
  /// │        │        │    │      │    │topBarBottomOffsetFromViewportTopConstraint     │
  /// │        │        └───────────┘    ▼                                                │
  /// │        │   Viewport  │                                                            │
  /// │  ┌─────────────┐     │      ┬                                                     │
  /// │  │     │       │     │      │viewportBtmOffsetFromTopOfBottomBarConstraint        │
  /// │  │     └───────│─────┘   ┬  ▼                                              ┬      │
  /// │  │  BottomBar  │         │bottomBarBtmOffsetFromViewportBtmConstraint      │      │
  /// │  └─────────────┘      ┬  ▼                                                 │      │
  /// │                       │                                                    │      │
  /// │                       │bottomBarBtmToCVBtmConstraint                       │      │
  /// │                       │                                                    │      │
  /// │                       │                cvBtmOffsetFromViewportBtmConstraint│      │
  /// └─ Bottom               ▼                                                    ▼      ▼
  ///
  /// ⁴ Only used when bottomBar is shown but viewport is not.
  /// (Diagram made with https://asciip.dev/, then hand-edited.)
  func rebuildPanelConstraints(_ transition: LayoutTransition, stage: LayoutTransition.Stage) {
    let contentView = window!.contentView!

    // TODO: expand this to include constraints for sidebars too
    let layoutForBottomBar: LayoutState
    let layoutForTopBar: LayoutState
    switch stage {
    case .preTransitionSetup:
      layoutForBottomBar = transition.inputLayout
      layoutForTopBar = transition.inputLayout
    case .closeOldPanels, .midTransitionHiddenUpdates:
      layoutForBottomBar = transition.outputLayout
      layoutForTopBar = transition.outputLayout
    case .openNewPanels, .postTransition:
      layoutForBottomBar = transition.outputLayout
      layoutForTopBar = transition.outputLayout
    }

    var useViewport = transition.outputGeometry.videoShown
    var useBottomBar = transition.outputLayout.hasBottomBar
    var useTopBar = transition.outputLayout.hasTopBar
    var useLeadingSidebar = transition.outputLayout.isLeadingSidebarVisible
    var useTrailingSidebar = transition.outputLayout.isTrailingSidebarVisible
    let isFinalStage = stage == .postTransition

    if !isFinalStage {
      useViewport = useViewport || transition.inputGeometry.videoShown
      useBottomBar = useBottomBar || transition.inputLayout.hasBottomBar
      useTopBar = useTopBar || transition.inputLayout.hasTopBar
      useLeadingSidebar = useLeadingSidebar || transition.inputLayout.isLeadingSidebarVisible
      useTrailingSidebar = useTrailingSidebar || transition.inputLayout.isTrailingSidebarVisible
    }

    log.verbose("[RebuildPanels] Stage \(stage): viewport=\(useViewport.yn) bottomBar=\(useBottomBar.yn) topBar=\(useTopBar.yn) LeadingSB=\(useLeadingSidebar.yn) TrailingSBr=\(useTrailingSidebar.yn)")

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
        topBarLeadingSpaceConstraint.identifier = "TopBarLeadingSpaceConstraint"
        topBarLeadingSpaceConstraint.isActive = true

        let topBarTrailingSpaceConstraint = topBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0)
        topBarTrailingSpaceConstraint.identifier = "TopBarTrailingSpaceConstraint"
        topBarTrailingSpaceConstraint.isActive = true
      }
    } else {
      topBarView.removeFromSuperview()
    }

    // - Add constraints between subviews
    if useTopBar {
      assert(useViewport, "Cannot use topBarView without viewportView")
      let constant1 = transition.viewportTopOffsetFromTopBarTopConstraint(for: stage)
      let constant2 = transition.topBarBottomOffsetFromViewportTopConstraint(for: stage)
      log.verbose("[RebuildPanels] Updating topBar: viewport.top<-topBar.top: \(constant1), topBar.bottom<-viewport.top: \(constant2)")
      if !isActive(viewportTopOffsetFromTopBarTopConstraint) {
        viewportTopOffsetFromTopBarTopConstraint = viewportView.topAnchor.constraint(equalTo: topBarView.topAnchor, constant: constant1)
        viewportTopOffsetFromTopBarTopConstraint.identifier = "ViewportTopOffsetFromTopBarTopConstraint"
        viewportTopOffsetFromTopBarTopConstraint.isActive = true
      } else {
        viewportTopOffsetFromTopBarTopConstraint.animateToConstant(constant1)
      }

      if !isActive(topBarBottomOffsetFromViewportTopConstraint) {
        topBarBottomOffsetFromViewportTopConstraint = topBarView.bottomAnchor.constraint(equalTo: viewportView.topAnchor, constant: constant2)
        topBarBottomOffsetFromViewportTopConstraint.identifier = "TopBarBottomOffsetFromViewportTopConstraint"
        topBarBottomOffsetFromViewportTopConstraint.isActive = true
      } else {
        topBarBottomOffsetFromViewportTopConstraint.animateToConstant(constant2)
      }

      topBarView.titleBarHeightConstraint.animateToConstant(layoutForTopBar.titleBarHeight)
    }

    // Bottom Bar
    if useBottomBar {
      // Handle leading & trailing constraints
      updateBottomBarPlacement(forLayout: layoutForBottomBar)

      // This will always have constant: 0
      if !isActive(bottomBarBtmToCVBtmConstraint) {
        bottomBarBtmToCVBtmConstraint = contentView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: 0)
        bottomBarBtmToCVBtmConstraint.identifier = "bottomBar-Btm_OffsetFrom-CV-Btm_Con"
        bottomBarBtmToCVBtmConstraint.isActive = true
      }

      if useViewport {
        bottomBarTopFromCVTopConstraint?.isActive = false
      } else {
        if !isActive(bottomBarTopFromCVTopConstraint) {
          bottomBarTopFromCVTopConstraint = bottomBarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
          bottomBarTopFromCVTopConstraint.identifier = "bottomBar-Btm_OffsetFrom-CV-Btm_Con"
          bottomBarTopFromCVTopConstraint.isActive = true
        }
      }
    }


    if useViewport && useBottomBar {
      let constant1 = transition.bottomBarBtmOffsetFromViewportBtmConstraint(for: stage)
      let constant2 = transition.viewportBtmOffsetFromTopOfBottomBarConstraint(for: stage)
      log.verbose("[RebuildPanels] Updating topBar&viewport: viewport.btm<-bottomBar.bottom: \(constant1), viewport.btm<-bottomBar.top: \(constant2)")
      if !isActive(bottomBarBtmOffsetFromViewportBtmConstraint) {
        bottomBarBtmOffsetFromViewportBtmConstraint = bottomBarView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor, constant: constant1)
        bottomBarBtmOffsetFromViewportBtmConstraint.identifier = "Viewport-Btm_OffsetFrom-BottomBar-Btm_Constraint"
        bottomBarBtmOffsetFromViewportBtmConstraint.isActive = true
      } else {
        bottomBarBtmOffsetFromViewportBtmConstraint.animateToConstant(constant1)
      }

      if !isActive(viewportBtmOffsetFromTopOfBottomBarConstraint)  {
        viewportBtmOffsetFromTopOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: constant2)
        viewportBtmOffsetFromTopOfBottomBarConstraint.identifier = "Viewport-Btm_OffsetFrom-BottomBar-Top_Constraint"
        viewportBtmOffsetFromTopOfBottomBarConstraint.isActive = true
      } else {
        viewportBtmOffsetFromTopOfBottomBarConstraint.animateToConstant(constant2)
      }
    }

    // Viewport View
    if useViewport {
      let constant1 = transition.viewportTopOffsetFromCVTopConstraint(for: stage)
      let constant2 = transition.cvBtmOffsetFromViewportBtmConstraint(for: stage)
      log.verbose("[RebuildPanels] Updating viewport: viewport.top<-CV.top: \(constant1), CV.bottom<-viewport.bottom: \(constant2)")

      if !isActive(viewportTopOffsetFromCVTopConstraint) {
        viewportTopOffsetFromCVTopConstraint = viewportView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: constant1)
        viewportTopOffsetFromCVTopConstraint.identifier = .init("Viewport-Top_OffsetFrom-CV-Top-Constraint")
        viewportTopOffsetFromCVTopConstraint.isActive = true
      } else {
        viewportTopOffsetFromCVTopConstraint.animateToConstant(constant1)
      }

      if isFinalStage && layoutForBottomBar.mode == .musicMode && transition.outputGeometry.isMusicModePlaylistShown {
        cvBtmOffsetFromViewportBtmConstraint?.isActive = false
      } else {
        if !isActive(cvBtmOffsetFromViewportBtmConstraint) {
          cvBtmOffsetFromViewportBtmConstraint = contentView.bottomAnchor.constraint(equalTo: viewportView.bottomAnchor, constant: constant2)
          cvBtmOffsetFromViewportBtmConstraint.identifier = .init("CV-Btm_OffsetFrom-Viewport-Btm-Constraint")
          cvBtmOffsetFromViewportBtmConstraint.isActive = true
        } else {
          cvBtmOffsetFromViewportBtmConstraint.animateToConstant(constant2)
        }
      }

      if !isActive(viewportLeadingOffsetFromContentViewLeadingConstraint) {
        viewportLeadingOffsetFromContentViewLeadingConstraint = viewportView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0)
        viewportLeadingOffsetFromContentViewLeadingConstraint.identifier = .init("Viewport-Leading_OffsetFrom-CV-Leading-Constraint")
        viewportLeadingOffsetFromContentViewLeadingConstraint.isActive = true
      }

      if !isActive(viewportTrailingOffsetFromContentViewTrailingConstraint) {
        viewportTrailingOffsetFromContentViewTrailingConstraint = contentView.trailingAnchor.constraint(equalTo: viewportView.trailingAnchor, constant: 0)
        viewportTrailingOffsetFromContentViewTrailingConstraint.identifier = .init("CV-Trailing_OffsetFrom-Viewport-Trailing-Constraint")
        viewportTrailingOffsetFromContentViewTrailingConstraint.isActive = true
      }
    }

    sortContentViewSubviews(for: layoutForBottomBar)
  }

  // - Top bar

  // TODO: rewrite with Stages
  func updateTopBarHeight(to topBarHeight: CGFloat, topBarPlacement: Preference.PanelPlacement,
                          cameraHousingOffset: CGFloat) {
    let isTopBarAttached = topBarView.superview != nil
    log.verbose{"Updating topBar height to: \(topBarHeight) for placement=\(topBarPlacement) cameraOffset=\(cameraHousingOffset) topBarAttached=\(isTopBarAttached.yn)"}

    switch topBarPlacement {
    case .insideViewport:
      if isTopBarAttached {
        topBarBottomOffsetFromViewportTopConstraint.animateToConstant(topBarHeight)
        viewportTopOffsetFromTopBarTopConstraint.animateToConstant(0)
      }
      viewportTopOffsetFromCVTopConstraint.animateToConstant(0 + cameraHousingOffset)
    case .outsideViewport:
      if isTopBarAttached {
        topBarBottomOffsetFromViewportTopConstraint.animateToConstant(0)
        viewportTopOffsetFromTopBarTopConstraint.animateToConstant(topBarHeight)
      }
      viewportTopOffsetFromCVTopConstraint.animateToConstant(topBarHeight + cameraHousingOffset)
    }
  }

  // - Bottom bar

  private func updateBottomBarPlacement(forLayout layout: LayoutState) {
    log.verbose{"Updating bottomBar placement to: \(layout.bottomBarPlacement) leadingSB_Shown=\(layout.isLeadingSidebarVisible.yn) trailingSB_Shown=\(layout.isTrailingSidebarVisible.yn)"}
    guard let window = window, let contentView = window.contentView else { return }

    let leadingSpacePartner: NSLayoutXAxisAnchor
    let trailingSpacePartner: NSLayoutXAxisAnchor

    if layout.bottomBarPlacement == .insideViewport && layout.isLeadingSidebarVisible {
      // Align left & right sides with sidebars (top bar will squeeze to make space for sidebars)
      assert(leadingSidebarView.superview != nil)
      leadingSpacePartner = leadingSidebarView.trailingAnchor
    } else {
      // Align left & right sides with window (sidebars go below top bar)
      leadingSpacePartner = contentView.leadingAnchor
    }

    if layout.bottomBarPlacement == .insideViewport && layout.isTrailingSidebarVisible {
      assert(trailingSidebarView.superview != nil)
      trailingSpacePartner = trailingSidebarView.leadingAnchor
    } else {
      trailingSpacePartner = contentView.trailingAnchor
    }

    let mustReplaceLeading = !isActive(bottomBarLeadingSpaceConstraint) || (bottomBarLeadingSpaceConstraint.secondAnchor != leadingSpacePartner)
    let mustReplaceTrailing = !isActive(bottomBarTrailingSpaceConstraint) || (bottomBarTrailingSpaceConstraint.secondAnchor != trailingSpacePartner)

    if mustReplaceLeading {
      bottomBarLeadingSpaceConstraint?.isActive = false
      bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: leadingSpacePartner, constant: 0)
      bottomBarLeadingSpaceConstraint.identifier = "bottomBarLeadingSpaceConstraint"
    }
    if mustReplaceTrailing {
      bottomBarTrailingSpaceConstraint?.isActive = false
      bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: trailingSpacePartner, constant: 0)
      bottomBarTrailingSpaceConstraint.identifier = "bottomBarTrailingSpaceCon"
    }
    bottomBarLeadingSpaceConstraint.isActive = true
    bottomBarTrailingSpaceConstraint.isActive = true
  }

  // TODO: rewrite with Stages
  func updateBottomBarHeight(to bottomBarHeight: CGFloat, bottomBarPlacement: Preference.PanelPlacement) {
    let isBottomBarAttached = bottomBarView.superview != nil
    log.verbose{"Updating bottomBar height to \(bottomBarHeight) for placement=\(bottomBarPlacement)  bottomBarAttached=\(isBottomBarAttached.yn)"}

    switch bottomBarPlacement {
    case .insideViewport:
      if isBottomBarAttached {
        viewportBtmOffsetFromTopOfBottomBarConstraint?.animateToConstant(bottomBarHeight)
        bottomBarBtmOffsetFromViewportBtmConstraint?.animateToConstant(0)
      }
      cvBtmOffsetFromViewportBtmConstraint?.animateToConstant(0)
    case .outsideViewport:
      if isBottomBarAttached {
        viewportBtmOffsetFromTopOfBottomBarConstraint?.animateToConstant(0)
        bottomBarBtmOffsetFromViewportBtmConstraint?.animateToConstant(bottomBarHeight)
      }
      cvBtmOffsetFromViewportBtmConstraint?.animateToConstant(bottomBarHeight)
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

  func addTitleBarAccessoryViews() {
    guard let window = window else { return }
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
    if window.styleMask.contains(.titled) {
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
  func hideBuiltInTitleBarViews(setAlpha: Bool = false) {
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
  func showBuiltInTitleBarViews() {
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

  // MARK: - Controller content layout

  func updateSpeedLabelFont(for transition: LayoutTransition) {
    let oscGeo = transition.outputLayout.controlBarGeo
    let speedLabelFontSize = oscGeo.speedLabelFontSize
    log.trace{"Updating speed label fontSize=\(speedLabelFontSize)"}
    speedLabel.font = .messageFont(ofSize: speedLabelFontSize)
  }

  /// Recreates the toolbar with the latest icons with the latest sizes & padding from prefs
  func rebuildOSCToolbar(_ transition: LayoutTransition) {
    let oldGeo = transition.inputLayout.controlBarGeo
    let newGeo = transition.outputLayout.controlBarGeo
    let newButtonTypes = newGeo.toolbarItems

    let hasSizeChange = oldGeo.toolIconSize != newGeo.toolIconSize || oldGeo.toolIconSpacing != newGeo.toolIconSpacing
    let hasColorChange = transition.inputLayout.oscHasClearBG != transition.outputLayout.oscHasClearBG
    var needsButtonsUpdate = hasSizeChange || hasColorChange

    let isOpeningBarOSCFromZero = transition.isOpeningBarOSCFromZero
    let zeroOut = isOpeningBarOSCFromZero && !transition.isWindowInitialLayout
    let iconSize: CGFloat = zeroOut ? 0 : newGeo.toolIconSize
    let iconSpacing: CGFloat = zeroOut ? 0 : newGeo.toolIconSpacing
    if isOpeningBarOSCFromZero || !oldGeo.toolbarItemsAreSame(as: newGeo) {
      fragToolbarView.views.forEach { fragToolbarView.removeView($0) }

      if newButtonTypes.count > 0 {
        log.verbose{"[\(transition.name)] Updating OSC toolbar: iconSize=\(iconSize) iconSpacing=\(iconSpacing) barHeight=\(newGeo.barHeight) fullIconHeight=\(newGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]"}
        for buttonType in newButtonTypes {
          let button = OSCToolbarButton()
          button.setStyle(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing)
          button.setOSCColors(hasClearBG: transition.outputLayout.oscHasClearBG)
          button.action = #selector(self.toolBarButtonAction(_:))
          fragToolbarView.addView(button, in: .trailing)
          fragToolbarView.setVisibilityPriority(.detachOnlyIfNecessary, for: button)
        }
        needsButtonsUpdate = false
      }
    }

    if needsButtonsUpdate {
      log.verbose{"[\(transition.name)] Updating OSC toolbar: iconSize=\(newGeo.toolIconSize) iconSpacing=\(newGeo.toolIconSpacing) barHeight=\(newGeo.barHeight) fullIconHeight=\(newGeo.fullIconHeight) btns=[\(newButtonTypes.map({$0.keyString}).joined(separator: ","))]"}
      for button in fragToolbarView.views.compactMap({ $0 as? OSCToolbarButton }) {
        button.setStyle(iconSize: iconSize, iconSpacing: iconSpacing)
        button.setOSCColors(hasClearBG: transition.outputLayout.oscHasClearBG)
      }
    }

    // Do not zero this out:
    updateToolbarHStack(iconSpacing: newGeo.toolIconSpacing)
    log.verbose{"[\(transition.name)] Toolbar spacing=\(fragToolbarView.spacing) edgeInsets=\(fragToolbarView.edgeInsets)"}
  }

  // It's not possible to control the icon padding from inside the buttons in all cases.
  // Instead we can get the same effect with a little more work, by using the stack view's features.
  func updateToolbarHStack(iconSpacing: CGFloat) {
    log.verbose{"Updating toolbar hstack using spacing=\(iconSpacing)"}
    fragToolbarView.spacing = 2 * iconSpacing
    let sideInset = (iconSpacing * 0.5).rounded()
    fragToolbarView.edgeInsets = .init(top: iconSpacing, left: sideInset,
                                       bottom: iconSpacing, right: sideInset)
    fragToolbarView.needsUpdateConstraints = true
  }

  // MARK: - Misc support functions

  /// Call this when `origVideoSize` is known.
  /// Assumes `videoRect == videoView.frame`
  func addOrReplaceCropBoxSelection(rawVideoSize: NSSize, videoViewSize: NSSize) {
    guard let cropController = self.cropSettingsView else { return }

    if !videoView.subviews.contains(cropController.cropBoxView) {
      videoView.addSubview(cropController.cropBoxView)
      cropController.cropBoxView.addAllConstraintsToFillSuperview()
    }

    cropController.cropBoxView.actualSize = rawVideoSize
    cropController.cropBoxView.resized(with: NSRect(origin: .zero, size: videoViewSize))
  }

  /// Either legacy FS or windowed
  func setWindowStyleToLegacy() {
    guard let window = window else { return }
    if window.styleMask.contains(.titled) {
      log.verbose("Removing window styleMask.titled")
      window.styleMask.remove(.titled)
    }
    window.styleMask.insert(.closable)
    window.styleMask.insert(.miniaturizable)
  }

  /// "Native" == `.titled` style mask
  func setWindowStyleToNative() {
    guard let window = window else { return }

    if !window.styleMask.contains(.titled) {
      log.verbose("Inserting window styleMask.titled")
      window.styleMask.remove(.borderless)
      window.styleMask.insert(.titled)
    }
  }

  /// Remove the tab group view associated with `group` from its parent view (also removes constraints)
  func removeSidebarTabGroupView(group: Sidebar.TabGroup) {
    log.verbose{"Removing sidebar tab group view for \(group)"}
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
  /// 
  private func sortContentViewSubviews(for layout: LayoutState) {
    let isLeadingSidebarOpen = layout.leadingSidebar.isVisible
    let isTrailingSidebarOpen = layout.trailingSidebar.isVisible

    let isBottomBarOpen = layout.hasBottomBar
    let bottomBar = layout.bottomBarPlacement
    let leadingSidebar = layout.leadingSidebarPlacement
    let trailingSidebar = layout.trailingSidebarPlacement

    var possibleSubviews: [NSView] = []

    // If a sidebar is "outsideViewport", need to put it behind the video because:
    // (1) Don't want sidebar to cast a shadow on the video
    // (2) Animate sidebar open/close with "slide in" / "slide out" from behind the video
    let leadingSidebarIsBelowViewport = isLeadingSidebarOpen && leadingSidebar == .outsideViewport
    let trailingSidebarIsBelowViewport = isTrailingSidebarOpen && trailingSidebar == .outsideViewport
    let bottomBariIsBelowSidebars = isBottomBarOpen && bottomBar == .insideViewport

    if bottomBariIsBelowSidebars && (leadingSidebarIsBelowViewport || trailingSidebarIsBelowViewport) {
      possibleSubviews.append(bottomBarView)
    }
    if leadingSidebarIsBelowViewport {
      possibleSubviews.append(leadingSidebarView)
    }
    if trailingSidebarIsBelowViewport {
      possibleSubviews.append(trailingSidebarView)
    }

    possibleSubviews.append(viewportView)

    if !leadingSidebarIsBelowViewport {
      possibleSubviews.append(leadingSidebarView)
    }
    if !trailingSidebarIsBelowViewport {
      possibleSubviews.append(trailingSidebarView)
    }
    if !bottomBariIsBelowSidebars || !(leadingSidebarIsBelowViewport || trailingSidebarIsBelowViewport) {
      possibleSubviews.append(bottomBarView)
    }

    let contentView = window!.contentView!
    possibleSubviews += [
      seekPreview.thumbnailPeekView,
      seekPreview.timeLabel,
      topBarView,
      customWindowBorderBox,
      customWindowBorderTopHighlightBox]
    let correctOrderedSubviews = possibleSubviews.filter { contentView.containsSubview($0) }
    for subview in correctOrderedSubviews {
      contentView.addSubview(subview, positioned: .above, relativeTo: nil)
    }
  }

  /// This fixes an edge case when both sidebars are shown and are `.outsideViewport`. When one is toggled, and width of
  /// `videoView` is smaller than that of the sidebar being toggled, must ensure that the sidebar being animated is below
  /// the other one, otherwise it will be briefly seen popping out on top of the other one.
  func prepareDepthOrderOfOutsideSidebarsForToggle(_ transition: LayoutTransition) {
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

  func updatePanelBlendingModes(to outputLayout: LayoutState) {
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
