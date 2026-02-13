//
//  TopBarView.swift
//  iina
//
//  Created by Matt Svoboda on 8/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// OSC at top of window, if configured.
final class TopControlBarView: ClickThroughView {
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

final class TopBarVisualEffectView: ClickThroughVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .titlebar
    state = .followsWindowActiveState
    wantsLayer = true  // needed for shadow
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@available(macOS 26.0, *)
final class TopBarViewGlassEffectView: ClickThroughGlassEffectView {
  init(style desiredStyle: Style) {
    super.init(frame: .zero)
    setStyle(desiredStyle)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The bar at the very top of the window. May include title bar and/or OSC.
final class TopBar {
  var view: NSView

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
    view = TopBarVisualEffectView()
    rebuildView()
  }

  func rebuildView() {
    let topBarColorScheme: Preference.OSCColorScheme = Preference.enum(for: .topBarColorScheme)
    switch topBarColorScheme {
    case .clearLiquidGlass, .tintedLiquidGlass:
      if #available(macOS 26.0, *) {
        let style: NSGlassEffectView.Style = topBarColorScheme == .clearLiquidGlass ? .clear : .regular
        view = TopBarViewGlassEffectView(style: style)
      } else {
        fallthrough
      }
    case .clearGradient:
      // TODO: support this
      fallthrough
    case .visualEffectView:
      view = TopBarVisualEffectView()
    }
    view.idString = "TopBarView"
    view.clipsToBounds = true  // for better animations when toggling OSC position/placement
    view.translatesAutoresizingMaskIntoConstraints = false

    /// `titleBarView`
    titleBarView.translatesAutoresizingMaskIntoConstraints = false
    titleBarView.idString = "TitleBarView"
    view.addSubview(titleBarView)

    titleBarView.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

    titleBarHeightConstraint = titleBarView.bottomAnchor.constraint(equalTo: view.topAnchor, constant: Constants.standardTitleBarHeight)
    titleBarHeightConstraint.identifier = "TitleBarView-HeightConstraint"
    titleBarHeightConstraint.isActive = true

    view.addSubviewAndConstraints(controlBarTop, bottom: 0, leading: 0, trailing: 0)

    let titleBarBottom_ToControlBarTop_Constraint = titleBarView.bottomAnchor.constraint(equalTo: controlBarTop.topAnchor, constant: 0)
    titleBarBottom_ToControlBarTop_Constraint.identifier = "TitleBar-Bottom_ToControlBarTop_Constraint"
    titleBarBottom_ToControlBarTop_Constraint.isActive = true

    view.addSubview(bottomBorder)
    bottomBorder.addConstraintsToFillSuperview(bottom: -0.5, leading: 0, trailing: 0)

    // Want to make a 0.5px border. But it seems that in some display modes, that is not only not possible,
    // but it will trigger an auto-layout constraint error. So use defaultHigh and be prepared to accept a 1px border.
    let topBarBottomBorder_HeightConstraint = bottomBorder.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -0.5)
    topBarBottomBorder_HeightConstraint.identifier = "TopBarBottomBorder-HeightConstraint"
    topBarBottomBorder_HeightConstraint.priority = .defaultHigh
    topBarBottomBorder_HeightConstraint.isActive = true
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
