//
//  FixedProgressBar.swift
//  iina
//
//  Created by Hechen Li on 2025-09-18.
//  Copyright © 2025 lhc. All rights reserved.
//

/// A class to draw progress bars in the OSD manually since macOS 26 added animation to NSProgressIndicator
/// that can't be disabled.
class FixedProgressBar: NSView {
  var barFactory: BarRenderer? = nil

  /// Expected to be in the range [0.0, 100.0].
  var doubleValue: Double = 0.0 {
    didSet {
      setNeedsDisplay(bounds)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let bf = barFactory else { return }

    effectiveAppearance.applyAppearanceFor {
      let barRect = bounds
      let scaleFactor: CGFloat = window?.screen?.backingScaleFactor ?? Constants.defaultBackingScaleFactor
      let volBarImg = bf.buildVolumeBarImage(useFocusEffect: false,
                                             barWidth: barRect.width,
                                             scaleFactor: scaleFactor, knobRect: .zero,
                                             currentValue: doubleValue,
                                             maxValue: 1.0,  // 100%
                                             currentPreviewValue: nil)

      bf.drawBar(volBarImg, in: barRect, scaleFactor: scaleFactor,
                 tallestBarHeight: bf.maxVolBarHeightNeeded, drawShadow: true)
    }
  }
}
