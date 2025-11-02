//
//  GeoUtil.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-30.
//  Copyright © 2025 lhc. All rights reserved.
//

/// Utility functions for calculating window/view geometry.
/// See: `PWinGeometry.swift`
/// See: `MusicModeGeo.swift`
struct GeoUtil {

  static func minViewportMargins(forMode mode: PlayerWindowMode) -> MarginQuad {
    switch mode {
    case .windowedInteractive, .fullScreenInteractive:
      return Constants.InteractiveMode.viewportMargins
    default:
      return MarginQuad.zero
    }
  }

  static func minViewportSize(mode: PlayerWindowMode, videoAspect: CGFloat, insideBars: MarginQuad) -> NSSize {
    var viewportMinW: CGFloat
    switch mode {
    case .windowedNormal, .fullScreenNormal:
      // Take sidebars into account:
      viewportMinW = max(Constants.Window.minViewportSize.width, insideBars.totalWidth + Constants.Window.minWidthBetweenInsideSidebars)
      let viewportMinH = max(Constants.Window.minViewportSize.height, insideBars.totalHeight + Constants.Window.minHeightBetweenInsideSidebars)
      return NSSize(width: viewportMinW, height: viewportMinH)
    case .windowedInteractive, .fullScreenInteractive:
      return Constants.InteractiveMode.minViewportSize
    case .musicMode:
      // note that a viewport height of zero would be ok if video was disabled in music mode
      return NSSize(width: Constants.Distance.MusicMode.minWindowWidth, height: 0)
    }
  }

  static func minWindowSize(mode: PlayerWindowMode, videoAspect: CGFloat, outsideBars: MarginQuad, insideBars: MarginQuad) -> NSSize {
    let minViewportSize = minViewportSize(mode: mode, videoAspect: videoAspect, insideBars: insideBars)

    let minWinWidth = minViewportSize.width + outsideBars.totalWidth
    let minWinHeight = minViewportSize.height + outsideBars.totalHeight
    return NSSize(width: minWinWidth, height: minWinHeight)
  }

  static func areEqual(windowFrame1: NSRect? = nil, windowFrame2: NSRect? = nil, videoSize1: NSSize? = nil, videoSize2: NSSize? = nil) -> Bool {
    if let windowFrame1, let windowFrame2 {
      if !windowFrame1.equalTo(windowFrame2) {
        return false
      }
    }
    if let videoSize1, let videoSize2 {
      if !(videoSize1.width == videoSize2.width && videoSize1.height == videoSize2.height) {
        return false
      }
    }
    return true
  }

  static func fullScreenWindowFrame(in screen: NSScreen, legacy: Bool) -> NSRect {
    if legacy {
      return screen.frame
    } else {
      return screen.frameWithoutCameraHousing
    }
  }

  /// Returns the limiting frame for the given `screenFit`, inside which the player window must fit.
  /// If no fit needed, returns `nil`.
  static func getContainerFrame(forScreenID screenID: String, screenFit: ScreenFit) -> NSRect? {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)

    switch screenFit {
    case .noConstraints:
      return nil
    case .stayInside, .centerInside:
      return screen.visibleFrame
    case .legacyFullScreen:
      return fullScreenWindowFrame(in: screen, legacy: true)
    case .nativeFullScreen:
      return fullScreenWindowFrame(in: screen, legacy: false)
    }
  }

  static func deriveViewportSize(from windowFrame: NSRect, topMarginHeight: CGFloat, outsideBars: MarginQuad) -> NSSize {
    return NSSize(width: windowFrame.width - outsideBars.trailing - outsideBars.leading,
                  height: windowFrame.height - outsideBars.top - outsideBars.bottom - topMarginHeight)
  }

  /// Snap `value` to `otherValue` if they are less than or equal to 1 px apart. If it can't snap, the number is
  /// rounded to the nearest integer.
  ///
  /// This helps smooth out division imprecision. The goal is to end up with whole numbers in calculation results
  /// without having to distort things. Fractional values will be interpreted differently by mpv, Core Graphics,
  /// AppKit, which can ultimately result in jarring visual glitches during Core animations.
  ///
  /// It is the requestor's responsibility to ensure that `otherValue` is already a whole number.
  static func snap(_ value: CGFloat, to otherValue: CGFloat) -> CGFloat {
    if abs(value - otherValue) <= 1 {
      return otherValue
    } else {
      return round(value)
    }
  }

  static func computeVideoSize(withAspectRatio videoAspect: CGFloat, toFillIn viewportSize: NSSize,
                               minViewportMargins: MarginQuad? = nil, mode: PlayerWindowMode) -> NSSize {
    assert(mode != .musicMode || (minViewportMargins == nil || minViewportMargins == .zero), "minViewportMargins must be nil or .zero in music mode")
    assert(viewportSize.width >= 0 && viewportSize.height >= 0, "viewportSize must not be negative! Found: \(viewportSize)")
    if viewportSize.width == 0 || viewportSize.height == 0 {
      return NSSize.zero
    }

    let minMargins = minViewportMargins ?? self.minViewportMargins(forMode: mode)
    let usableViewportSize = NSSize(width: viewportSize.width - minMargins.totalWidth,
                                    height: viewportSize.height - minMargins.totalHeight)
    let videoSize: NSSize
    /// Compute `videoSize` to fit within `viewportSize` while maintaining `videoAspect`:
    // Make sure to end up with whole numbers here! Decimal values can be interpreted differently by
    // mpv, Core Graphics, AppKit, which will cause animation glitches
    let videoHeightComputed = (usableViewportSize.width / videoAspect).rounded()
    if videoHeightComputed <= usableViewportSize.height {
      // Video aspect is taller than viewport: shrink its width
      videoSize = NSSize(width: usableViewportSize.width, height: videoHeightComputed)
    } else {
      // Video is wider, shrink to meet width
      let videoWidthComputed = (usableViewportSize.height * videoAspect).rounded()
      videoSize = NSSize(width: videoWidthComputed, height: usableViewportSize.height)
    }

#if DEBUG
    let sumViewportSize = CGSize(width: minMargins.totalWidth + videoSize.width,
                                 height: minMargins.totalHeight + videoSize.height)
    assert(((sumViewportSize.width == 0 || sumViewportSize.height == 0) && (viewportSize.width == 0 || viewportSize.height == 0)) ||
           ((sumViewportSize.width <= viewportSize.width) && (sumViewportSize.height <= viewportSize.height)),
           "videoSize \(videoSize) + minMargins \(minMargins) → sum: \(sumViewportSize) > viewportSize \(viewportSize)")

    assert((usableViewportSize.width - videoSize.width >= 0) && (usableViewportSize.height - videoSize.height >= 0),
           "Derived videoSize \(videoSize) > usableViewportSize \(usableViewportSize)! (videoAspect: \(videoAspect), viewportSize: \(viewportSize), minViewportMargins: \(minMargins))")

    assert(videoSize.width >= 0 && videoSize.height >= 0, "Expected W ≥ 0 & H ≥ 0 for videoSize, found \(videoSize)")
    assert(videoSize.width.isInteger && videoSize.height.isInteger, "Expected integer W & H for videoSize, found \(videoSize)")
#endif
    return videoSize
  }

  /// These do not respect `Preference.bool(for: .keepVideoAwayFromBars)`. For that see `PWinGeometry.offsetsToKeepVideoAwayFromInsideBars`.
  /// The values returned here will be (nearly) symmetrical between leading & trailing & between top & bottom, but may be different by 1.
  static func computeBestViewportMargins(viewportSize: NSSize, videoSize: NSSize, insideBars: MarginQuad, mode: PlayerWindowMode) -> MarginQuad {
    guard viewportSize.width > 0 && viewportSize.height > 0 else {
      return MarginQuad.zero
    }
    if mode == .musicMode {
      // Viewport size is always equal to video size in music mode
      return MarginQuad.zero
    }

    let unusedWidth = max(0, viewportSize.width - videoSize.width)
    let unusedHeight = max(0, viewportSize.height - videoSize.height)
    let leadingMargin = (unusedWidth * 0.5).rounded(.down)
    let topMargin = (unusedHeight * 0.5).rounded(.down)
    // We need to return full integer values.
    // Use difference from total for remaining dimensions to avoid losing/gaining a point due to the rounding above.
    return MarginQuad(top: topMargin,
                      trailing: unusedWidth - leadingMargin,
                      bottom: unusedHeight - topMargin,
                      leading: leadingMargin)
  }

}
