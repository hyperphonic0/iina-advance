//
//  BottomBarView.swift
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

/// Bottom bar root view with Liquid Glass effect
@available(macOS 26.0, *)
final class BottomBarGlassEffectView: ClickThroughGlassEffectView {
  init(_ desiredStyle: Style) {
    super.init(frame: .zero)
    setStyle(desiredStyle)
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
