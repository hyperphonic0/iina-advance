//
//  TopBar.swift
//  iina
//
//  Created by Matt Svoboda on 8/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

// MARK: - TopBar root view claases

/// Top bar root view which inherits from `NSVisualEffectView`
final fileprivate class TopBarVisualEffectView: ClickThroughVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .titlebar
    state = .followsWindowActiveState
    wantsLayer = true  // needed for shadow
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Top bar root view with Glass
@available(macOS 26.0, *)
final fileprivate class TopBarGlassEffectView: ClickThroughGlassEffectView {
  init(style desiredStyle: Style) {
    super.init(frame: .zero)
    wantsLayer = true
    setStyle(desiredStyle)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(_ targetLayout: LayoutState) {
    if targetLayout.isLegacyStyle {
      // Is rounded by default. Make sharp in case of custom window
      cornerRadius = 0
    } else {
      // try to match window corners
      cornerRadius = Constants.glassButtonCornerRadius
    }
  }
}

final fileprivate class TopBarGradientView: NSView {
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    let gradient = CAGradientLayer()
    gradient.frame = bounds
    // Top → Bottom
    gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
    // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
    gradient.colors = Constants.Color.clearBlackGradientColors + [Constants.Color.clearBlackGradientExtraTopBarColor]
    layer = gradient
  }

  @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Other support classes

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


// MARK: - TopBar

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
    view = NSView()
  }

  fileprivate static func buildView(targetLayout: LayoutState) -> NSView {
    let topBarColorScheme: Preference.PanelColorScheme = targetLayout.topBarColorScheme
    switch topBarColorScheme {
    case .clearGlass, .tintedGlass:
      if #available(macOS 26.0, *) {
        let style: NSGlassEffectView.Style = topBarColorScheme == .clearGlass ? .clear : .regular
        let glassView = TopBarGlassEffectView(style: style)
        glassView.update(targetLayout)
        return glassView
      } else {
        fallthrough
      }
    case .clearGradient:
      return TopBarGradientView()
    case .visualEffectView, .none:
      // Default to NSVisualEffectView
      return TopBarVisualEffectView()
    }
  }

  /// Returns `true` if view needed to be rebuilt
  func rebuildTopBarViewIfNeeded(targetLayout: LayoutState, superview: NSView) {
    guard #available(macOS 26.0, *) else { return }

    let topBarColorScheme: Preference.PanelColorScheme = targetLayout.topBarColorScheme
    switch topBarColorScheme {
    case .clearGlass, .tintedGlass:
      if let glassView = view as? TopBarGlassEffectView {
        let targetStyle: NSGlassEffectView.Style = topBarColorScheme == .clearGlass ? .clear : .regular
        if glassView.style == targetStyle {
          glassView.update(targetLayout)
          return
        }
        // As of MacOS 26.0, glass effect views seem to be unreliable at changing between light & dark.
        // Just rebuild it from scratch to be safe.
      }

    case .clearGradient:
      if view as? TopBarGradientView != nil {
        return
      }
    case .visualEffectView, .none:
      if view as? TopBarVisualEffectView != nil {
        return
      }
    }
    rebuildTopBarView(targetLayout: targetLayout, superview: superview)
  }

  func rebuildTopBarView(targetLayout: LayoutState, superview: NSView) {
    view.removeFromSuperview()
    view = TopBar.buildView(targetLayout: targetLayout)
    superview.addSubview(view)
    configureView()
  }

  fileprivate func configureView() {
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

}
