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
    super.init(desiredStyle)
    wantsLayer = true
    cornerRadius = 0
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
@MainActor final class TopBar {
  /// The top bar root view. Needs to be rebuilt if the style changes, due each style inheriting from different classes.
  var view: NSView

  var contentView: NSView {
    if #available(macOS 26.0, *), let glassView = view as? TopBarGlassEffectView {
      return glassView.contentView!
    }
    return view
  }

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

  fileprivate static func buildView(targetLayout: LayoutState, subviews: [NSView]) -> NSView {
    let topBarColorScheme: Preference.PanelColorScheme = targetLayout.topBarColorScheme

    let view: NSView
    switch topBarColorScheme {
    case .clearGlass, .tintedGlass:
      if #available(macOS 26.0, *) {
        let style: NSGlassEffectView.Style = topBarColorScheme == .clearGlass ? .clear : .regular
        let glassView = TopBarGlassEffectView(style: style)
        glassView.contentView!.subviews = subviews
        view = glassView
      } else {
        fallthrough
      }
    case .clearGradient:
      view = TopBarGradientView()
      view.subviews = subviews
    case .visualEffectView, .none:
      // Default to NSVisualEffectView
      view = TopBarVisualEffectView()
      view.subviews = subviews
    }

    return view
  }

  /// Returns `true` if view needed to be rebuilt
  func rebuildTopBarViewIfNeeded(targetLayout: LayoutState,
                                 force: Bool, _ log: any Logger.Subsystem) {
    guard #available(macOS 26.0, *) else { return }

    if !force {
      let topBarColorScheme: Preference.PanelColorScheme = targetLayout.topBarColorScheme
      switch topBarColorScheme {
      case .clearGlass:
        if let glassView = view as? TopBarGlassEffectView, glassView.style == .clear, glassView.effectiveAppearance.isDark {
          // good
          return
        }
      case .tintedGlass:
        // Workaround for race condition when changing Glass theme (MacOS 26): rebuild the view if appearance is different
        if let glassView = view as? TopBarGlassEffectView, glassView.style == .regular {
          return
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
    }

    log.verbose("[Load] Rebuilding topBarView: colorScheme=\(targetLayout.topBarColorScheme)")
    view.removeFromSuperview()
    let subviews = [titleBarView, controlBarTop, bottomBorder]
    view = TopBar.buildView(targetLayout: targetLayout, subviews: subviews)
    configureView()
  }

  fileprivate func configureView() {
    view.idString = "TopBarView"
    view.clipsToBounds = true  // for better animations when toggling OSC position/placement
    view.translatesAutoresizingMaskIntoConstraints = false

    /// `titleBarView`
    titleBarView.translatesAutoresizingMaskIntoConstraints = false
    titleBarView.idString = "TitleBarView"

    titleBarView.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)

    titleBarHeightConstraint = titleBarView.bottomAnchor.constraint(equalTo: view.topAnchor, constant: Constants.standardTitleBarHeight)
    titleBarHeightConstraint.identifier = "TitleBarView-HeightConstraint"
    titleBarHeightConstraint.isActive = true

    controlBarTop.addConstraintsToFillSuperview(bottom: 0, leading: 0, trailing: 0)

    let titleBarBottom_ToControlBarTop_Constraint = titleBarView.bottomAnchor.constraint(equalTo: controlBarTop.topAnchor, constant: 0)
    titleBarBottom_ToControlBarTop_Constraint.identifier = "TitleBar-Bottom_ToControlBarTop_Constraint"
    titleBarBottom_ToControlBarTop_Constraint.isActive = true

    bottomBorder.addConstraintsToFillSuperview(bottom: -0.5, leading: 0, trailing: 0)

    // Want to make a 0.5px border. But it seems that in some display modes, that is not only not possible,
    // but it will trigger an auto-layout constraint error. So use defaultHigh and be prepared to accept a 1px border.
    let topBarBottomBorder_HeightConstraint = bottomBorder.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -0.5)
    topBarBottomBorder_HeightConstraint.identifier = "TopBarBottomBorder-HeightConstraint"
    topBarBottomBorder_HeightConstraint.priority = .defaultHigh
    topBarBottomBorder_HeightConstraint.isActive = true
  }

}
