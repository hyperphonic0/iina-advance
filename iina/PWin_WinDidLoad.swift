//
//  PWin_WinDidLoad.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-23.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {

  /// Called when window is initially loaded. Add all subviews here.
  override func windowDidLoad() {
    log.verbose("[Load] PWin_WinDidLoad starting")
    super.windowDidLoad()

    guard let window else { return }
    guard let contentView = window.contentView else { return }

    miniPlayer = MiniPlayerViewController()
    miniPlayer.pwc = self

    undoHelper = PlayerWindowUndoHelper(self, window.undoManager)

    viewportView.player = player

    notiHandler = buildObservers()

    // The fade timer is only used if auto-hide is enabled
    fadeableViews.hideTimer.action = hideTimeoutAction
    fadeableViews.hideTimer.startCondition = { _ in Preference.bool(for: .enableControlBarAutoHide) }

    // Cursor hide timer
    hideCursorTimer.action = hideCursorAsConfigured
    hideCursorTimer.startCondition = { [self] timer in
      guard player.canHideCursor else {
        log.trace("HideCursorTimer: aborting start (cannot hide cursor)")
        return false
      }
      let newTimeout = max(Constants.TimeInterval.hideCursorMinTimeoutMS, Double(player.info.cursorAutoHideTimeoutMs))
      timer.timeout = newTimeout / 1000.0
      log.trace("HideCursorTimer: [re-]starting timeout=\(timer.timeout)s")
      return true
    }

    /// Set base options for `collectionBehavior` here, and then insert/remove full screen options
    /// using `resetCollectionBehavior`. Do not mess with the base options again because doing so seems
    /// to cause flickering while animating.
    /// Always use option `.fullScreenDisallowsTiling`. As of MacOS 14.2.1, tiling is at best glitchy &
    /// at worst results in an infinite loop with our code.
    // FIXME: support tiling for at least native full screen
    window.collectionBehavior = [.managed, .fullScreenDisallowsTiling]

    window.initialFirstResponder = nil

    shouldCascadeWindows = false

    window.minSize = Constants.Window.minWindowSize
    contentView.idString = "WindowCV"

    leftTimeLabel.mode = .current
    rightTimeLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    // gesture recognizers
    rotationHandler.pwc = self
    magnificationHandler.pwc = self
    contentView.addGestureRecognizer(magnificationHandler.magnificationGestureRecognizer)
    contentView.addGestureRecognizer(rotationHandler.rotationGestureRecognizer)

    // scroll wheel
    playSlider.scrollWheelDelegate = PlaySliderScrollWheel(slider: playSlider, log)
    volumeSlider.scrollWheelDelegate = VolumeSliderScrollWheel(slider: volumeSlider, log)
    windowScrollWheel = PWinScrollWheel(self)

    playlistView.pwc = self
    playlistView.view.idString = "PlaylistView"
    pluginView.pwc = self
    pluginView.view.idString = "PluginView"
    quickSettingView.pwc = self

    /// This will init mpv, but we will not add `videoView` until setting the initial layout (see updateHiddenViewsAndConstraints)
    player.start()

    /// Use an animation task to init views, to hopefully prevent partial/redundant draws.
    /// NOTE: this will likely execute *after* `_openWindow()`
    animationPipeline.submitInstantTask{ [self] in

      /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
      /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
      /// notch and the preference `allowVideoToOverlapCameraHousing` is false. Also needed so that sidebars don't
      /// bleed through during their show/hide animations.
      setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

      window.preservesContentDuringLiveResize = false

      let oscGeo = currentLayout.controlBarGeo
      initViewportView()
      initSeekPreview(in: contentView)
      initTitleBar()
      initOSCToolbar()
      initPlaybackBtnsView(using: oscGeo)
      initPlaySliderAndTimeLabelsView()
      initVolumeView(using: oscGeo)
      initSidebars()

      closeButtonView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4).isActive = true
      closeButtonView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4).isActive = true

      initBufferIndicatorView()

      log.verbose("[Load] Configuring window for CoreAnimation")
      contentView.configureSubtreeForCoreAnimation()

      // Make sure to set this inside the animation task! See note above
      loaded = true

      // Update to correct values before displaying. Only useful when restoring at launch
      player.mpv.queue.async { [self] in
        player.updatePlaybackTimeInfo()
        DispatchQueue.main.async { [self] in
          updateUI()
        }
      }

      if let priorState = priorStateIfRestoring {
        if let layoutSpec = priorState.layoutSpec {
          // Preemptively set window frames to prevent windows from "jumping" during restore
          let pwinGeo = layoutSpec.mode == .musicMode ? priorState.geoSet.musicMode : priorState.geoSet.windowed
          setFrameAndUpdateWindowSubviews(using: pwinGeo, animate: false)
        }

        updateDefaultArtVisibility(to: player.info.isVideoTrackSelected)
      }

      if player.disableUI { hideFadeableViews() }

      // Must wait until *after* loaded==true to load plugins!
      player.loadPlugins()

      log.verbose("[Load] PWin_WinDidLoad done")
      player.events.emit(.windowLoaded)
    }
  }

  // MARK: - Building Components

  private func initViewportView() {
    viewportView.idString = "ViewportView"
    viewportView.clipsToBounds = true
    viewportView.translatesAutoresizingMaskIntoConstraints = false
    viewportView.autoresizesSubviews = false
    // These don't seem to matter. But set to reasonable values:
    viewportView.setContentHugging(h: 250, v: 250)
    viewportView.setCCResistance(h: 250, v: 250)

    // These don't seem to matter. But set to reasonable values:
    let ch: Float = 250
    viewportView.trailingSpacer.setContentHugging(h: ch, v: ch)
    viewportView.leadingSpacer.setContentHugging(h: ch, v: ch)
    viewportView.topSpacer.setContentHugging(h: ch, v: ch)
    viewportView.bottomSpacer.setContentHugging(h: ch, v: ch)
    let ccr: Float = 250
    viewportView.trailingSpacer.setCCResistance(h: ccr, v: ccr)
    viewportView.leadingSpacer.setCCResistance(h: ccr, v: ccr)
    viewportView.topSpacer.setCCResistance(h: ccr, v: ccr)
    viewportView.bottomSpacer.setCCResistance(h: ccr, v: ccr)
  }

  private func initSeekPreview(in contentView: NSView) {
    seekPreview.player = player
    contentView.addSubview(seekPreview.thumbnailPeekView, positioned: .above, relativeTo: viewportView)
    contentView.addSubview(seekPreview.timeLabel, positioned: .above, relativeTo: seekPreview.thumbnailPeekView)
    // This is above the play slider and by default, will swallow clicks. Send events to play slider instead
    seekPreview.timeLabel.nextResponder = playSlider

    // Yes, left, not leading!
    seekPreview.timeLabelHorizontalCenterConstraint = seekPreview.timeLabel.centerXAnchor.constraint(equalTo: contentView.leftAnchor, constant: 0) // dummy value for now
    seekPreview.timeLabelHorizontalCenterConstraint.identifier = .init("SeekTimeHoverLabelHSpaceConstraint")
    seekPreview.timeLabelHorizontalCenterConstraint.isActive = true

    // This is a bit confusing but the constant here can be thought of as the X value in window,
    // not flipped (so, larger values toward the top)
    seekPreview.timeLabelVerticalSpaceConstraint = contentView.bottomAnchor.constraint(equalTo: seekPreview.timeLabel.bottomAnchor, constant: 0)
    seekPreview.timeLabelVerticalSpaceConstraint.identifier = .init("SeekTimeHoverLabelVSpaceConstraint")
    seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true

    seekPreview.hideTimer.action = self.seekPreviewTimeout
  }

  private func initTitleBar() {
    let builder = CustomTitleBar.shared
    let iconSpacingH = Constants.Distance.titleBarIconHSpacing
    // - LEADING

    let leadingTB = leadingTitleBarAccessoryView
    leadingTB.idString = "leadingTitleBarAccessoryView"

    builder.configureTitleBarButton(leadingSidebarToggleButton,
                                    Images.sidebarLeading,
                                    identifier: "LeadingSidebarBtn_Native",
                                    target: self,
                                    action: #selector(toggleLeadingSidebarVisibility(_:)),
                                    bounceOnClick: true)

    leadingTB.orientation = .horizontal
    leadingTB.alignment = .centerY
    leadingTB.distribution = .fill
    leadingTB.spacing = 0
    leadingTB.detachesHiddenViews = true
    leadingTB.setHuggingPriority(.init(500), for: .horizontal)

    leadingTB.addArrangedSubview(leadingSidebarToggleButton)

    // - TRAILING

    let trailingTB = trailingTitleBarAccessoryView
    trailingTB.idString = "trailingTitleBarAccessoryView"

    builder.configureTitleBarButton(onTopButton,
                                    Images.onTopOff,
                                    identifier: "OnTopButton_Native",
                                    target: self, action: #selector(toggleOnTop(_:)),
                                    bounceOnClick: false) // Do not bounce (looks weird)

    builder.configureTitleBarButton(trailingSidebarToggleButton,
                                    Images.sidebarTrailing,
                                    identifier: "TrailingSidebarBtn_Native",
                                    target: self,
                                    action: #selector(toggleTrailingSidebarVisibility(_:)),
                                    bounceOnClick: true)

    trailingTB.orientation = .horizontal
    trailingTB.alignment = .centerY
    trailingTB.detachesHiddenViews = true
    trailingTB.distribution = .fill
    trailingTB.spacing = iconSpacingH
    trailingTB.setHuggingPriority(.init(500), for: .horizontal)
    trailingTB.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)

    trailingTB.addArrangedSubview(trailingSidebarToggleButton)
    trailingTB.addArrangedSubview(onTopButton)
  }

  private func initOSCToolbar() {
    fragToolbarView.idString = "OSC-ToolbarView"
    fragToolbarView.translatesAutoresizingMaskIntoConstraints = false
    fragToolbarView.orientation = .horizontal
    fragToolbarView.distribution = .fill
  }

  /// The `bottomBarView` may need to be completely rebuilt if the style changes.
  /// This also removes the previous `bottomBarView` from `contentView`.
  func rebuildBottomBarView(style: Preference.OSCColorScheme) {
    log.verbose{"[Load] Rebuilding bottomBarView: style=\(style)"}
    bottomBarView.removeAllSubviews()
    bottomBarView.removeFromSuperview()

    let bottomBarView: NSView
    switch style {
    case .visualEffectView:
      bottomBarView = BottomBarVisualEffectView()
    case .clearGradient:
      bottomBarView = BottomBarGradientView()
    }

    bottomBarView.idString = "BottomBarView"  // helps with debug logging
    bottomBarView.isHidden = true
    bottomBarView.clipsToBounds = true  // for better animations when toggling OSC position/placement
    bottomBarView.translatesAutoresizingMaskIntoConstraints = false

    bottomBarView.addSubview(bottomBarTopBorder)
    bottomBarTopBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    // Want to make a 0.5px border. But it seems that in some display modes, that is not only not possible,
    // but it will trigger an auto-layout constraint error. So use defaultHigh and be prepared to accept a 1px border.
    let bottomBarTopBorder_HeightConstraint = bottomBarTopBorder.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0.5)
    bottomBarTopBorder_HeightConstraint.identifier = "BottomBarTopBorder-HeightConstraint"
    bottomBarTopBorder_HeightConstraint.priority = .defaultHigh
    bottomBarTopBorder_HeightConstraint.isActive = true

    self.bottomBarView = bottomBarView
  }

  func isActive(_ con: NSLayoutConstraint?) -> Bool {
    if let con {
      return con.isActive
    }
    return false
  }

  private func initSidebars() {
    log.verbose{"[Load] Init sidebars"}

    // - Leading sidebar

    leadingSidebarView.idString = "LeadingSidebarView"
    leadingSidebarView.state = .active
    leadingSidebarView.translatesAutoresizingMaskIntoConstraints = false
    leadingSidebarView.autoresizesSubviews = false

    // Leading sidebar border
    leadingSidebarView.addSubview(leadingSidebarTrailingBorder)
    leadingSidebarTrailingBorder.addConstraintsToFillSuperview(top: 0, bottom: 0, trailing: 0)
    // Avoid constraint error by setting priority = .defaultHigh (see similar notes for bottomBarTopBorder_HeightConstraint, et al.)
    let leadingSidebarTrailingBorder_WidthConstraint = leadingSidebarTrailingBorder.leadingAnchor.constraint(equalTo: leadingSidebarView.trailingAnchor, constant: -0.5)
    leadingSidebarTrailingBorder_WidthConstraint.identifier = .init("LeadingSidebarTrailingBorder-WidthConstraint")
    leadingSidebarTrailingBorder_WidthConstraint.priority = .defaultHigh
    leadingSidebarTrailingBorder_WidthConstraint.isActive = true

    // - Trailing sidebar

    trailingSidebarView.idString = "TrailingSidebarView"
    trailingSidebarView.state = .active
    trailingSidebarView.translatesAutoresizingMaskIntoConstraints = false
    trailingSidebarView.autoresizesSubviews = false

    // Trailing sidebar border
    trailingSidebarView.addSubview(trailingSidebarLeadingBorder)
    trailingSidebarLeadingBorder.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
    // Avoid constraint error by setting priority = .defaultHigh (see similar notes for bottomBarTopBorder_HeightConstraint, et al.)
    let trailingSidebarLeadingBorder_WidthConstraint = trailingSidebarLeadingBorder.trailingAnchor.constraint(equalTo: trailingSidebarView.leadingAnchor, constant: 0.5)
    trailingSidebarLeadingBorder_WidthConstraint.identifier = .init("TrailingSidebarLeadingBorder-WidthConstraint")
    trailingSidebarLeadingBorder_WidthConstraint.priority = .defaultHigh
    trailingSidebarLeadingBorder_WidthConstraint.isActive = true
  }

  /// Init `fragPlaybackBtnsView` & its subviews
  private func initPlaybackBtnsView(using oscGeo: ControlBarGeometry) {
    log.verbose{"[Load] Init playback buttons"}

    // Play button
    playButton.image = Images.play
    playButton.target = self
    playButton.action = #selector(playButtonAction(_:))
    playButton.refusesFirstResponder = true
    playButton.idString = "PlayBtn"  // helps with debug logging
    // Set to 0 at load time to be safe:
    let playAspectConstraint = playButton.widthAnchor.constraint(equalTo: playButton.heightAnchor)
    playAspectConstraint.isActive = true

    playBtnHeightConstraint = playButton.heightAnchor.constraint(equalToConstant: 0)
    playBtnHeightConstraint.identifier = "PlayBtnVStack-HeightConstraint"
    playBtnHeightConstraint.priority = .init(900)
    playBtnHeightConstraint.isActive = true

    let enableAcceleration = Preference.bool(for: .useForceTouchForSpeedArrows)
    // Left Arrow button
    leftArrowButton.image = oscGeo.leftArrowImage
    leftArrowButton.target = self
    leftArrowButton.action = #selector(leftArrowButtonAction(_:))
    leftArrowButton.identifier = .init("LeftArrowBtn")
    leftArrowButton.refusesFirstResponder = true
    leftArrowButton.enableAcceleration = enableAcceleration
    leftArrowButton.bounceOnClick = true

    // Right Arrow button
    rightArrowButton.image = oscGeo.rightArrowImage
    rightArrowButton.target = self
    rightArrowButton.action = #selector(rightArrowButtonAction(_:))
    rightArrowButton.identifier = .init("RightArrowBtn")
    rightArrowButton.refusesFirstResponder = true
    rightArrowButton.enableAcceleration = enableAcceleration
    rightArrowButton.bounceOnClick = true

    initSpeedLabel()

    fragPlaybackBtnsView.identifier = .init("fragPlaybackBtnsView")
    fragPlaybackBtnsView.addSubview(leftArrowButton)
    fragPlaybackBtnsView.addSubview(playButton)
    fragPlaybackBtnsView.addSubview(speedLabel)
    fragPlaybackBtnsView.addSubview(rightArrowButton)

    let playBtnHorizOffsetConstraint = playButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor)
    playBtnHorizOffsetConstraint.isActive = true

    speedLabel.centerXAnchor.constraint(equalTo: playButton.centerXAnchor).isActive = true
    // Snip off 2 pts from top & btm to reduce margin:
    let speedLabelTopConstraint = fragPlaybackBtnsView.topAnchor.constraint(equalTo: speedLabel.topAnchor, constant: 2)
    speedLabelTopConstraint.identifier = "SpeedLabel-TopConstraint"
    speedLabelTopConstraint.isActive = true
    speedLabelBtmConstraint = speedLabel.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: 2)
    speedLabelBtmConstraint.identifier = "SpeedLabel-BtmConstraint"
    speedLabelBtmConstraint.isActive = false

    fragPlaybackBtnsView.translatesAutoresizingMaskIntoConstraints = false

    fragPlaybackBtnsHeightConstraint = fragPlaybackBtnsView.heightAnchor.constraint(equalToConstant: 0)
    fragPlaybackBtnsHeightConstraint.identifier = "fragPlaybackBtns-HeightConstraint"
    fragPlaybackBtnsHeightConstraint.isActive = true

    fragPlaybackBtnsWidthConstraint = fragPlaybackBtnsView.widthAnchor.constraint(equalToConstant: oscGeo.totalPlayControlsWidth)
    fragPlaybackBtnsWidthConstraint.identifier = "fragPlaybackBtns-WidthConstraint"
    fragPlaybackBtnsWidthConstraint.isActive = true

    // Try to make sure the buttons' bounding boxes reach the full height, for activation
    // (their images will be limited by the width constraint & will stop scaling before this)
    let leftArrowAspectConstraint = leftArrowButton.heightAnchor.constraint(equalTo: leftArrowButton.widthAnchor)
    leftArrowAspectConstraint.identifier = .init("leftArrowBtn-AspectConstraint")
    leftArrowAspectConstraint.isActive = true
    let rightArrowAspectConstraint = rightArrowButton.heightAnchor.constraint(equalTo: rightArrowButton.widthAnchor)
    rightArrowAspectConstraint.identifier = .init("rightArrowBtn-AspectConstraint")
    rightArrowAspectConstraint.isActive = true

    // Video controllers and timeline indicators should not flip in a right-to-left language.
    fragPlaybackBtnsView.userInterfaceLayoutDirection = .leftToRight

    let playBtnVertOffsetConstraint = playButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    playBtnVertOffsetConstraint.isActive = true

    leftArrowBtn_CenterXOffsetConstraint = leftArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                    constant: oscGeo.leftArrowCenterXOffset)
    leftArrowBtn_CenterXOffsetConstraint.identifier = .init("leftArrowBtn-HorizOffsetConstraint")
    leftArrowBtn_CenterXOffsetConstraint.isActive = true

    arrowBtnWidthConstraint = leftArrowButton.widthAnchor.constraint(equalToConstant: 0)
    arrowBtnWidthConstraint.identifier = .init("arrowBtn-WidthConstraint")
    arrowBtnWidthConstraint.isActive = true

    rightArrowBtn_CenterXOffsetConstraint = rightArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                      constant: oscGeo.rightArrowCenterXOffset)
    rightArrowBtn_CenterXOffsetConstraint.identifier = .init("rightArrowBtn_CenterXOffsetConstraint")
    rightArrowBtn_CenterXOffsetConstraint.isActive = true

    // Left & Right arrow buttons are always same size
    let arrowBtnsEqualWidthConstraint = leftArrowButton.widthAnchor.constraint(equalTo: rightArrowButton.widthAnchor, multiplier: 1)
    arrowBtnsEqualWidthConstraint.identifier = .init("arrowBtnsEqualWidthConstraint")
    arrowBtnsEqualWidthConstraint.isActive = true

    let leftArrowBtnVertCenterConstraint = leftArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    leftArrowBtnVertCenterConstraint.isActive = true
    let rightArrowBtnVertCenterConstraint = rightArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    rightArrowBtnVertCenterConstraint.isActive = true
  }

  private func initSpeedLabel() {
    speedLabel.idString = "SpeedLabel"  // helps with debug logging
    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    speedLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    speedLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    speedLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    speedLabel.setContentHuggingPriority(.required, for: .vertical)
    speedLabel.font = NSFont.messageFont(ofSize: 10)
    speedLabel.textColor = .textColor
    speedLabel.alphaValue = 0.75
    speedLabel.isBordered = false
    speedLabel.drawsBackground = false
    speedLabel.isBezeled = false
    speedLabel.isEditable = false
    speedLabel.isSelectable = false
    speedLabel.isEnabled = true
    speedLabel.refusesFirstResponder = true
    speedLabel.alignment = .center
  }

  private func initPlaySliderAndTimeLabelsView() {
    log.verbose{"[Load] Init play slider & time labels"}
    // - Configure playSliderAndTimeLabelsView
    playSliderAndTimeLabelsView.idString = "PlaySliderAndTimeLabelsView"
    playSliderAndTimeLabelsView.translatesAutoresizingMaskIntoConstraints = false
    playSliderAndTimeLabelsView.userInterfaceLayoutDirection = .leftToRight
    playSliderAndTimeLabelsView.setContentHuggingPriority(.init(249), for: .horizontal)
    playSliderAndTimeLabelsView.setContentCompressionResistancePriority(.init(249), for: .horizontal)
    playSliderAndTimeLabelsView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150.0).isActive = true

    // - Configure subviews

    leftTimeLabel.idString = "PlayPos-LeftTimeLabel"
    leftTimeLabel.alignment = .right
    leftTimeLabel.isBordered = false
    leftTimeLabel.drawsBackground = false
    leftTimeLabel.isEditable = false
    leftTimeLabel.refusesFirstResponder = true
    leftTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    leftTimeLabel.setContentHuggingPriority(.init(501), for: .horizontal)
    leftTimeLabel.setContentCompressionResistancePriority(.init(501), for: .horizontal)

    playSlider.idString = "PlaySlider"
    playSlider.customCell.pwc = self
    playSlider.target = self
    playSlider.action = #selector(playSliderAction(_:))
    playSlider.minValue = 0
    playSlider.maxValue = 100
    playSlider.isContinuous = true
    playSlider.refusesFirstResponder = true
    playSlider.translatesAutoresizingMaskIntoConstraints = false
    let widthConstraint = playSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
    widthConstraint.identifier = "PlaySlider-MinWidthConstraint"
    widthConstraint.isActive = true

    playSliderHeightConstraint = playSlider.heightAnchor.constraint(equalToConstant: 20)
    playSliderHeightConstraint.identifier = "PlaySlider-HeightConstraint"
    playSliderHeightConstraint.priority = .init(900)
    playSliderHeightConstraint.isActive = true

    rightTimeLabel.idString = "PlayPos-RightTimeLabel"
    rightTimeLabel.alignment = .left
    rightTimeLabel.isBordered = false
    rightTimeLabel.drawsBackground = false
    rightTimeLabel.isEditable = false
    rightTimeLabel.refusesFirstResponder = true
    rightTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    rightTimeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    rightTimeLabel.setContentCompressionResistancePriority(.init(749), for: .horizontal)
  }

  /// Can be called redundantly without ill effect
  func addSubviewsToPlaySliderAndTimeLabelsView(using oscGeo: ControlBarGeometry) {
    // Assume that if all subviews are inside, the constraints are properly configured as well, & no more work is needed.
    playSliderAndTimeLabelsView.removeAllSubviews()

    playSliderAndTimeLabelsView.subviews = [leftTimeLabel, playSlider, rightTimeLabel]
    // In case these were detached while in a stack view, restore their visibility:
    leftTimeLabel.isHidden = false
    playSlider.isHidden = false
    rightTimeLabel.isHidden = false

    // - Add constraints to subviews

    let hSpacing = oscGeo.hSpacingAroundSliders
    leftTimeLabel.leadingAnchor.constraint(equalTo: playSliderAndTimeLabelsView.leadingAnchor).isActive = true
    playSlider.leadingAnchor.constraint(equalTo: leftTimeLabel.trailingAnchor, constant: hSpacing).isActive = true

    // See also: playSliderHeightConstraint
    playSlider.addConstraintsToFillSuperview(top: 0, bottom: 0)

    playSlider.centerYAnchor.constraint(equalTo: leftTimeLabel.centerYAnchor).isActive = true
    playSlider.centerYAnchor.constraint(equalTo: rightTimeLabel.centerYAnchor).isActive = true

    rightTimeLabel.leadingAnchor.constraint(equalTo: playSlider.trailingAnchor, constant: hSpacing).isActive = true
    rightTimeLabel.trailingAnchor.constraint(equalTo: playSliderAndTimeLabelsView.trailingAnchor).isActive = true
  }

  private func initVolumeView(using oscGeo: ControlBarGeometry) {
    let hSpacing: CGFloat = 2

    // Volume view
    fragVolumeView.idString = "fragVolumeView"
    fragVolumeView.translatesAutoresizingMaskIntoConstraints = false
    fragVolumeView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    // Mute button
    muteButton.idString = "MuteBtn"
    let volImage = Images.volume3
    muteButton.image = Images.volume3
    muteButton.target = self
    muteButton.action = #selector(muteButtonAction(_:))
    muteButton.toolTip = "Toggle mute"
    fragVolumeView.addSubview(muteButton)
    muteButton.translatesAutoresizingMaskIntoConstraints = false
    muteButton.addConstraintsToFillSuperview(leading: 0)
    muteButton.centerYAnchor.constraint(equalTo: fragVolumeView.centerYAnchor).isActive = true
    volumeIconHeightConstraint = muteButton.heightAnchor.constraint(equalToConstant: oscGeo.volumeIconHeight)
    volumeIconHeightConstraint.priority = .init(900)
    volumeIconHeightConstraint.isActive = true
    volumeIconAspectConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: volImage.aspect)
    volumeIconAspectConstraint.isActive = true

    // Volume slider
    fragVolumeView.addSubview(volumeSlider)
    volumeSlider.cell = volumeSliderCell
    volumeSliderCell.pwc = self
    // For some reason this needs to be set here, instead of in volumeSliderCell init.
    // Otherwise action will continue to be nil...
    volumeSliderCell.hoverTimer.action = volumeSliderCell.refreshVolumeSliderHoverEffect
    volumeSlider.idString = "VolSlider"
    volumeSlider.controlSize = .regular
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSliderWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: oscGeo.volumeSliderWidth)
    volumeSliderWidthConstraint.identifier = .init("VolSlider-WidthConstraint")
    volumeSliderWidthConstraint.isActive = true
    volumeSlider.addConstraintsToFillSuperview(top: 0, bottom: 0)
    volumeSlider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: hSpacing).isActive = true
    volumeSlider.superview!.trailingAnchor.constraint(equalTo: volumeSlider.trailingAnchor).isActive = true
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeSliderAction(_:))
  }

  private func initBufferIndicatorView() {
    bufferIndicatorView.roundCorners()
    let bufIndicatorWidthCon = bufferIndicatorView.widthAnchor.constraint(equalToConstant: 160)
    bufIndicatorWidthCon.priority = .defaultLow
    bufIndicatorWidthCon.isActive = true
  }

}
