//
//  BottomBar.swift
//  iina
//
//  Created by Matt Svoboda on 8/23/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// Bottom bar root view with flat blended effect
final class BottomBarVisualEffectView: NSVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .sidebar
    state = .active
    wantsLayer = true
  }

  @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Bottom bar root view with Glass effect
@available(macOS 26.0, *)
final class BottomBarGlassEffectView: ClickThroughGlassEffectView {
  override init(_ desiredStyle: Style) {
    super.init(desiredStyle)
    // Is rounded by default. Make sharp in case of custom window
    cornerRadius = 0
  }

  @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Bottom bar root view with clear-black gradient effect
final class BottomBarGradientView: NSView {
  init() {
    super.init(frame: .zero)
    wantsLayer = true
    let gradient = CAGradientLayer()
    gradient.frame = bounds
    // Top → Bottom
    gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
    // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
    gradient.colors = Constants.Color.clearBlackGradientColors
    layer = gradient
  }

  @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class BottomBar {
  /// The bottom bar view
  var view: NSView

  /// Top border of `bottomBarView`.
  let topBorder = BorderLineView(id: "BottomBar-TopBorder", fillColor: .titleBarBorder)

  init() {
    view = NSView()  // for now
  }
  
  var contentView: NSView {
    if #available(macOS 26.0, *), let glassView = view as? BottomBarGlassEffectView {
      return glassView.contentView!
    }
    return view
  }

  /// The `bottomBarView` may need to be completely rebuilt if the style changes.
  /// This also removes the previous `bottomBarView` from `contentView`.
  func rebuildBottomBarView(colorScheme: Preference.PanelColorScheme, _ log: any Logger.Subsystem) {
    log.verbose("[Load] Rebuilding bottomBarView: style=\(colorScheme)")
    view.removeAllSubviews()
    view.removeFromSuperview()

    let subviews = [topBorder]

    let bottomBarView: NSView
    let contentView: NSView
    switch colorScheme {
    case .clearGradient:
      bottomBarView = BottomBarGradientView()
      contentView = bottomBarView
      bottomBarView.subviews = subviews
    case .clearGlass, .tintedGlass:
      if #available(macOS 26.0, *) {
        let desiredStyle: NSGlassEffectView.Style = colorScheme == .clearGlass ? .clear : .regular
        let glassView = BottomBarGlassEffectView(desiredStyle)
        contentView = glassView.contentView!
        bottomBarView = glassView
      } else {
        fallthrough
      }
    default:
      bottomBarView = BottomBarVisualEffectView()
      contentView = bottomBarView
    }
    contentView.subviews = subviews

    bottomBarView.idString = "BottomBarView"  // helps with debug logging
    bottomBarView.isHidden = true
    bottomBarView.clipsToBounds = true  // for better animations when toggling OSC position/placement
    bottomBarView.translatesAutoresizingMaskIntoConstraints = false

    topBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    // Want to make a 0.5px border. But it seems that in some display modes, that is not only not possible,
    // but it will trigger an auto-layout constraint error. So use defaultHigh and be prepared to accept a 1px border.
    let bottomBarTopBorder_HeightConstraint = topBorder.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0.5)
    bottomBarTopBorder_HeightConstraint.identifier = "BottomBarTopBorder-HeightConstraint"
    bottomBarTopBorder_HeightConstraint.priority = .defaultHigh
    bottomBarTopBorder_HeightConstraint.isActive = true

    self.view = bottomBarView
  }

}
