//
//  TwoRowBarOSCView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-30.
//  Copyright © 2025 lhc. All rights reserved.
//

class TwoRowBarOSCView: ClickThroughView {
  static let id = "OSC_2RowView"
  let hStackView = ClickThroughStackView()
  let centralSpacerView = SpacerView(id: "\(TwoRowBarOSCView.id)-CentralSpacer")
  var hStackView_HeightConstraint: NSLayoutConstraint!
  /// This subtracts from the height of the icons, but is needed to balance out the space above
  var hStackView_BottomMarginConstraint: NSLayoutConstraint!
  var hStackViewLeadingConstraint: NSLayoutConstraint!
  var hStackViewTrailingConstraint: NSLayoutConstraint!

  /// Used only if `PK.oscTimeLabelsAlwaysWrapSlider` is enabled.
  let timeSlashLabel = ClickThroughTextField()

  init() {
    super.init(frame: .zero)
    idString = TwoRowBarOSCView.id
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = .clear

    hStackView.idString = "\(TwoRowBarOSCView.id)-HStackView"
    hStackView.orientation = .horizontal
    hStackView.alignment = .centerY
    hStackView.translatesAutoresizingMaskIntoConstraints = false
    hStackView.setClippingResistancePriority(.defaultLow, for: .horizontal)

    addSubview(hStackView)

    hStackView_HeightConstraint = hStackView.topAnchor.constraint(equalTo: self.bottomAnchor, constant: 0)
    hStackView_HeightConstraint.identifier = "\(hStackView.idString)_HeightConstraint"
    hStackView_HeightConstraint.isActive = true

    hStackViewLeadingConstraint = hStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0)
    hStackViewLeadingConstraint.identifier = "\(hStackView.idString)_Lead-Offset"
    hStackViewLeadingConstraint.isActive = true

    hStackViewTrailingConstraint = self.trailingAnchor.constraint(equalTo: hStackView.trailingAnchor, constant: 0)
    hStackViewTrailingConstraint.identifier = "\(hStackView.idString)_Trail-Offset"
    hStackViewTrailingConstraint.isActive = true

    hStackView_BottomMarginConstraint = bottomAnchor.constraint(equalTo: hStackView.bottomAnchor, constant: 0)
    hStackView_BottomMarginConstraint.identifier = "\(TwoRowBarOSCView.id)-HStackView-BtmOffset"
    hStackView_BottomMarginConstraint.isActive = true
    relaxConstraints()

    timeSlashLabel.idString = "PlayPos-TimeSlashLabel"
    timeSlashLabel.isBordered = false
    timeSlashLabel.drawsBackground = false
    timeSlashLabel.isEditable = false
    timeSlashLabel.refusesFirstResponder = true
    timeSlashLabel.baseWritingDirection = .leftToRight
    timeSlashLabel.stringValue = "/"
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Should be called when no longer needed (for now anyway).
  /// Discards enough of the state to prevent this view & its constraints from causing problems with other layout.
  func dispose() {
    relaxConstraints()
    if let pwc {
      if subviews.contains(pwc.playSliderAndTimeLabelsView) {
        pwc.playSliderAndTimeLabelsView.removeFromSuperview()
      }
    }
    hStackView.removeAllSubviews()
    removeFromSuperview()
  }

  func updateSubviews(from pwc: PlayerWindowController, _ oscGeo: ControlBarGeometry) {
    // Avoid constraint violations while we change things below
    relaxConstraints()

    hStackView.spacing = oscGeo.hStackSpacing

    // Start building replacement views list
    var viewsForHStack: [NSView] = [pwc.fragPlaybackBtnsView]

    // Choose either playSlider or playSliderAndTimeLabelsView based on pref
    let playSliderTypeView: NSView
    if oscGeo.timeLabelsWrapSlider {
      // Option 2: Both PlaySlider & time labels go in Row 1 (via playSliderAndTimeLabelsView)
      pwc.addSubviewsToPlaySliderAndTimeLabelsView(oscGeo)
      playSliderTypeView = pwc.playSliderAndTimeLabelsView
    } else {
      // Option 1: PlaySlider goes in Row 1; time labels in Row 2
      pwc.playSliderAndTimeLabelsView.removeFromSuperview()
      if !Preference.bool(for: .showRemainingTime) {
        viewsForHStack.append(pwc.leftTimeLabel)
        viewsForHStack.append(timeSlashLabel)
      }
      viewsForHStack.append(pwc.rightTimeLabel)
      playSliderTypeView = pwc.playSlider
    }

    playSliderTypeView.removeFromSuperview()
    // Make sure to put PlaySlider below other controls. Older MacOS versions may clip overlapping views
    addSubview(playSliderTypeView, positioned: .below, relativeTo: hStackView)
    playSliderTypeView.addConstraintsToFillSuperview(top: 0, leading: oscGeo.leadingSpace_Row1,
                                                     trailing: oscGeo.trailingSpace_Row1)
    hStackView_HeightConstraint.priority = .defaultLow  // for now

    let bottomMargin = ControlBarGeometry.twoRowOSC_BottomMargin(playSliderHeight: oscGeo.playSliderHeight)
    let hStackViewHeight = oscGeo.fullIconHeight + bottomMargin
    hStackView_HeightConstraint.animateToConstant(hStackViewHeight)

    hStackViewLeadingConstraint.animateToConstant(oscGeo.leadingSpace_Row2)  // TODO: fix play icon spacing
    hStackViewTrailingConstraint.animateToConstant(oscGeo.trailingSpace_Row2)

    viewsForHStack.append(centralSpacerView)
    viewsForHStack.append(pwc.fragVolumeView)
    // Exclude toolbar if it has no items. Otherwise it will still be padded on both sides & will look bad
    let hasToolbar = !pwc.fragToolbarView.subviews.isEmpty
    if hasToolbar {
      viewsForHStack.append(pwc.fragToolbarView)
    }

    // - [Re-]add views to hStack

    hStackView.setViews(viewsForHStack, in: .leading)
    // In case any were previously hidden via stack view clip, restore:
    for view in viewsForHStack {
      view.isHidden = false
    }

    // - Set visibility priorities

    if hasToolbar {
      hStackView.setVisibilityPriority(.detachEarlier, for: pwc.fragToolbarView)
    }

    hStackView.setVisibilityPriority(.detachEarly, for: pwc.fragVolumeView)

    if viewsForHStack.contains(pwc.leftTimeLabel) {
      hStackView.setVisibilityPriority(.detachLessEarly, for: pwc.rightTimeLabel)
      hStackView.setVisibilityPriority(.detachLessEarly, for: timeSlashLabel)
    }

    pwc.log.verbose{"TwoRowOSC barH=\(oscGeo.barHeight) sliderH=\(oscGeo.playSliderHeight) btmMargin=\(bottomMargin) hStackH=\(hStackViewHeight) toolIconH=\(oscGeo.toolIconSize)"}
    // Although space is stolen from the icons to give to the bottom margin, it is given right back by adding to the top
    // (and overlapping with the btm of the play slider, but that is just empty space not being used anyway).
    hStackView_BottomMarginConstraint.animateToConstant(bottomMargin * 2)

    // Restore enforcement of consraints now that we're done. Do not use .required: the superiew may not be updated at
    // exactly the same time and can result in constraint conflict errors.
    hStackView_BottomMarginConstraint.priority = .required
    hStackView_HeightConstraint.priority = .init(900)

    pwc.fragToolbarView.updateConstraints()
    pwc.osd.osdHStackView.updateConstraints()
    pwc.osd.osdHStackView.layout()
  }

  func relaxConstraints() {
    hStackView_BottomMarginConstraint.priority = .defaultLow
    hStackView_HeightConstraint?.priority = .defaultLow
  }
}
