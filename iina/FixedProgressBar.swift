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
  var barRenderer: BarRenderer? = nil

  /// Expected to be in the range [0.0, 100.0].
  var doubleValue: Double = 0.0 {
    didSet {
      setNeedsDisplay(bounds)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let br = barRenderer else { return }

    effectiveAppearance.performAsCurrentDrawingAppearance {
      let barRect = bounds
      let scaleFactor: CGFloat = window?.screen?.backingScaleFactor ?? Constants.defaultBackingScaleFactor
      let volBarImg = br.buildVolumeBarImage(useFocusEffect: false,
                                             barWidth: barRect.width,
                                             scaleFactor: scaleFactor, knobRect: .zero,
                                             currentValue: doubleValue,
                                             maxValue: 1.0,  // 100%
                                             currentPreviewValue: nil)

      br.drawBar(volBarImg, in: barRect, scaleFactor: scaleFactor,
                 tallestBarHeight: br.maxVolBarHeightNeeded, drawShadow: true)
    }
  }
}
