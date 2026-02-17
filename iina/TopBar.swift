//
//  TopBar.swift
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

  @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Top bar root view which inherits from `NSVisualEffectView`
final class TopBarVisualEffectView: ClickThroughVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .titlebar
    state = .followsWindowActiveState
    wantsLayer = true  // needed for shadow
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Top bar root view with Liquid Glass
@available(macOS 26.0, *)
final class TopBarViewGlassEffectView: ClickThroughGlassEffectView {
  init(style desiredStyle: Style) {
    super.init(frame: .zero)
    setStyle(desiredStyle)
    // Is rounded by default. Make sharp in case of custom window
    cornerRadius = 0
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Container & pseudo-controller for the "top" OSC. Contains the view itself (`view`), its subviews, state & logic.
final class TopBar {
  /// The top bar root view. Needs to be rebuilt if the style changes, due each style inheriting from different classes.
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
    let topBarColorScheme: Preference.PanelColorScheme = LayoutState.effectiveTopBarColorSchemeFromPrefs()
    view = TopBar.buildView(topBarColorScheme)
    configureView()
  }

  static func buildView(_ colorScheme: Preference.PanelColorScheme) -> NSView {
    switch colorScheme {
    case .clearLiquidGlass, .tintedLiquidGlass:
      if #available(macOS 26.0, *) {
        let style: NSGlassEffectView.Style = colorScheme == .clearLiquidGlass ? .clear : .regular
        return TopBarViewGlassEffectView(style: style)
      } else {
        fallthrough
      }
    case .clearGradient:
      // TODO: support this
      fallthrough
    case .visualEffectView, .none:
      // Default to NSVisualEffectView
      return TopBarVisualEffectView()
    }
  }

  /// Returns `true` if view needed to be rebuilt
  func rebuildViewIfNeeded(_ colorScheme: Preference.PanelColorScheme) -> Bool {
    guard #available(macOS 26.0, *) else { return false }
    switch colorScheme {
    case .clearLiquidGlass, .tintedLiquidGlass:
      if let glassView = view as? TopBarViewGlassEffectView {
        let style: NSGlassEffectView.Style = colorScheme == .clearLiquidGlass ? .clear : .regular
        glassView.style = style
        
        return false
      }

    case .clearGradient:
      // TODO: support this
      fallthrough
    case .visualEffectView, .none:
      if view as? TopBarVisualEffectView != nil {
        return false
      }
    }
    view.removeFromSuperview()
    rebuildView(colorScheme)
    return true
  }

  func rebuildView(_ colorScheme: Preference.PanelColorScheme) {
    view = TopBar.buildView(colorScheme)
    configureView()
  }

  func configureView() {
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

  func updateAppearance(windowAppearance: NSAppearance?) {
    // Can be nil, which means dynamic system appearance:
    let topBarColorScheme = LayoutState.effectiveTopBarColorSchemeFromPrefs()
    let topBarAppearance = topBarColorScheme.hasClearBG ? NSAppearance(iinaTheme: .dark) : windowAppearance
    view.pwc?.log.verbose("Setting top bar appearance to \(topBarAppearance?.name.rawValue ?? "system")")
    view.appearance = topBarAppearance
    view.pwc?.customTitleBar?.view.appearance = topBarAppearance
    view.needsDisplay = true
    view.needsLayout = true
  }

}
