//
//  BottomBarView.swift
//  iina
//
//  Created by Matt Svoboda on 8/23/25.
//  Copyright © 2025 lhc. All rights reserved.
//

class BottomBarVisualEffectView: NSVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .sidebar
    state = .active
    wantsLayer = true
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// The bar at the very top of the window. May include title bar and/or OSC.
class BottomBarGradientView: NSView {
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

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

}
