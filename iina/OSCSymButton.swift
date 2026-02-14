//
//  OSCSymButton.swift
//  iina
//
//  Created by Matt Svoboda on 2025-02-03.
//  Copyright © 2025 lhc. All rights reserved.
//

/// A `SymButton` which is in an OSC.
class OSCSymButton: SymButton {
  override func configureSelf() {
    super.configureSelf()
    useDefaultColors()
  }
  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  private func useDefaultColors() {
    regularColor = nil
    highlightColor = .controlTextColor
    shadow = nil
    updateHighlight(isInsideBounds: false)
  }

  /// Sets current tint as a side effect! Do not use if currently between mouseDown & mouseUp.
  func setColors(for colorScheme: Preference.PanelColorScheme) {
    switch colorScheme {
    case .clearGradient:
      regularColor = .controlForClearBG
      highlightColor = .white
      if shadow == nil {
        addShadow(blurRadiusConstant: Constants.oscClearBG_ButtonShadowBlurRadius,
                  xOffsetConstant: 0, yOffsetConstant: 0, color: .black)
      }
      updateHighlight(isInsideBounds: false)
    case .clearLiquidGlass:
      regularColor = .controlForClearBG
      highlightColor = .white
      if shadow == nil {
        addShadow(blurRadiusConstant: Constants.oscClearBG_ButtonShadowBlurRadius,
                  xOffsetConstant: 0.4, yOffsetConstant: -0.4, color: .black)
      }
      updateHighlight(isInsideBounds: false)
    default:
      useDefaultColors()
    }
  }

}
