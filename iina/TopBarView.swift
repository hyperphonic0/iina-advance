//
//  TopBarView.swift
//  iina
//
//  Created by Matt Svoboda on 8/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// OSC at top of window, if configured.
class TopControlBarView: ClickThroughView {
  init() {
    super.init(frame: .zero)
    idString = "OSC-Top"

    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true  // for better animations when toggling OSC position/placement
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// The bar at the very top of the window. May include title bar and/or OSC.
class TopBarView: ClickThroughVisualEffectView {
  /// Reserves space for the title bar components. Can contain CustomTitleBarView *only* if using legacy
  /// windowed mode & topBarPlacement==.insideViewport
  let titleBarView = ClickThroughView()

  /// Contains the OSC if it is enabled and configured for "top" position. Located below `titleBarView`.
  let controlBarTop = TopControlBarView()

  /// Bottom border of `TopBarView`.
  let bottomBorder = BorderLineView(id: "TopBar-BottomBorder", fillColor: .titleBarBorder)

  /// Sets the size of the spacer view in the top overlay which reserves space for a title bar.
  var titleBarHeightConstraint: NSLayoutConstraint!

  init() {
    super.init(frame: .zero)
    idString = "TopBarView"

    translatesAutoresizingMaskIntoConstraints = false

    material = .titlebar
    state = .followsWindowActiveState
    wantsLayer = true  // needed for shadow
    clipsToBounds = true  // for better animations when toggling OSC position/placement
    translatesAutoresizingMaskIntoConstraints = false

    /// `titleBarView`
    titleBarView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleBarView)
    titleBarView.identifier = .init("TitleBarView")

    titleBarView.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

    titleBarHeightConstraint = titleBarView.bottomAnchor.constraint(equalTo: topAnchor, constant: Constants.standardTitleBarHeight)
    titleBarHeightConstraint.identifier = .init("TitleBarView-HeightConstraint")
    titleBarHeightConstraint.isActive = true

    /// `controlBarTop`
    addSubviewAndConstraints(controlBarTop, bottom: 0, leading: 0, trailing: 0)

    let titleBarBottom_ToControlBarTop_Constraint = titleBarView.bottomAnchor.constraint(equalTo: controlBarTop.topAnchor, constant: 0)
    titleBarBottom_ToControlBarTop_Constraint.identifier = .init("TitleBar-Bottom_ToControlBarTop_Constraint")
    titleBarBottom_ToControlBarTop_Constraint.isActive = true

    // Bottom border
    addSubview(bottomBorder)
    bottomBorder.addConstraintsToFillSuperview(bottom: -0.5, leading: 0, trailing: 0)
    // Want to make a 0.5px border. But it seems that in some display modes, that is not only not possible,
    // but it will trigger an auto-layout constraint error. So use defaultHigh and be prepared to accept a 1px border.
    let topBarBottomBorder_HeightConstraint = bottomBorder.topAnchor.constraint(equalTo: bottomAnchor, constant: -0.5)
    topBarBottomBorder_HeightConstraint.identifier = .init("TopBarBottomBorder-HeightConstraint")
    topBarBottomBorder_HeightConstraint.priority = .defaultHigh
    topBarBottomBorder_HeightConstraint.isActive = true
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
