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
      viewportMinW = Constants.InteractiveMode.minWindowWidth
      // assume viewport aspect is same as video for now
      return NSSize(width: viewportMinW, height: Constants.Window.minViewportSize.height)
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
      return screen.frame
    case .nativeFullScreen:
      return screen.frameWithoutCameraHousing
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
    let videoWidthNew = (usableViewportSize.height * videoAspect).rounded()
    if videoWidthNew <= usableViewportSize.width {  // video aspect is taller than viewport: shrink its width
      videoSize = NSSize(width: videoWidthNew, height: usableViewportSize.height)
    } else {  // video is wider, shrink to meet width
              // Make sure to end up with whole numbers here! Decimal values can be interpreted differently by
              // mpv, Core Graphics, AppKit, which will cause animation glitches
      let videoHeight = (usableViewportSize.width / videoAspect).rounded()
      videoSize = NSSize(width: usableViewportSize.width, height: videoHeight)
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

  static func computeBestViewportMargins(viewportSize: NSSize, videoSize: NSSize, insideBars: MarginQuad, mode: PlayerWindowMode) -> MarginQuad {
    guard viewportSize.width > 0 && viewportSize.height > 0 else {
      return MarginQuad.zero
    }
    if mode == .musicMode {
      // Viewport size is always equal to video size in music mode
      return MarginQuad.zero
    }
    var leadingMargin: CGFloat = 0
    var trailingMargin: CGFloat = 0

    var unusedWidth = max(0, viewportSize.width - videoSize.width)
    if unusedWidth > 0 {

      if mode == .fullScreenNormal {
        leadingMargin += (unusedWidth * 0.5)
        trailingMargin += (unusedWidth * 0.5)
      } else {
        let leadingSidebarWidth = insideBars.leading
        let trailingSidebarWidth = insideBars.trailing

        let viewportMidpointX = viewportSize.width * 0.5
        let leadingVideoIdealX = viewportMidpointX - (videoSize.width * 0.5)
        let trailingVideoIdealX = viewportMidpointX + (videoSize.width * 0.5)

        let leadingSidebarClearance = leadingVideoIdealX - leadingSidebarWidth
        let trailingSidebarClearance = viewportSize.width - trailingVideoIdealX - trailingSidebarWidth
        let freeViewportWidthTotal = viewportSize.width - videoSize.width - leadingSidebarWidth - trailingSidebarWidth

        if leadingSidebarClearance >= 0 && trailingSidebarClearance >= 0 {
          /*
           Ideal case: there is enough width to center video in viewport while clearing both inside sidebars.
           Just center the video in the viewport. L==T (+/- 1pt)

           Leading margin (L)           Window Center          Trailing margin (T)
           |◄────────────────────►|             |             |◄────────────────────►|
           ┌───────────┬────────────────────────|─────────────────┬──────────────────┐
           │           │                        |                 │                  │
           │           │          ┌─────────────|─────────────┐   │                  │
           │Leading    │          │                           │   │ Trailing         │
           │ InsideBar │          │         VideoView         │   │  InsideBar       │
           │           │          │    (centered in window)   │   │                  │
           │           │          │                           │   │                  │
           │           │          │                           │   │                  │
           │           │          └─────────────|─────────────┘   │                  │
           │           │                        |                 │                  │
           └───────────┴────────────────────────|─────────────────┴──────────────────┘
           |◄─────────────────────────────Viewport─width────────────────────────────►|

           */
          leadingMargin += (unusedWidth * 0.5)
          trailingMargin += (unusedWidth * 0.5)
        } else if freeViewportWidthTotal >= 0 {
          // We have enough space to realign video to fit within sidebars
          leadingMargin += leadingSidebarWidth
          trailingMargin += trailingSidebarWidth
          unusedWidth = unusedWidth - (leadingSidebarWidth + trailingSidebarWidth)
          let differenceBetweenLeadingAndTrailing = leadingSidebarWidth - trailingSidebarWidth
          if differenceBetweenLeadingAndTrailing > 0 {
            // Leading is wider. Give extra width to trailing to ideally even them out
            let extraForTrailing = min(unusedWidth, differenceBetweenLeadingAndTrailing)
            trailingMargin += extraForTrailing
            unusedWidth -= extraForTrailing
          } else if differenceBetweenLeadingAndTrailing < 0 {
            // Trailing is wider. Give extra width to leading to ideally even them out
            let extraForLeading = min(unusedWidth, -differenceBetweenLeadingAndTrailing)
            leadingMargin += extraForLeading
            unusedWidth -= extraForLeading
          }
          // If sidebars are equal widths, then margins are equal. Now just distribute remaining space equally to keep video centered.
          leadingMargin += (unusedWidth * 0.5)
          trailingMargin += (unusedWidth * 0.5)

        } else if leadingSidebarWidth == 0 {
          // Not enough margin to fit both sidebar and video, & only trailing sidebar visible.
          // Allocate all margin to trailing sidebar
          trailingMargin += unusedWidth
        } else if trailingSidebarWidth == 0 {
          // Not enough margin to fit both sidebar and video, & only leading sidebar visible.
          // Allocate all margin to leading sidebar
          leadingMargin += unusedWidth
        } else {
          // Not enough space for everything. Just center video between sidebars
          let leadingSidebarTrailingX = leadingSidebarWidth
          let trailingSidebarLeadingX = viewportSize.width - trailingSidebarWidth
          let midpointBetweenSidebarsX = ((trailingSidebarLeadingX - leadingSidebarTrailingX) * 0.5) + leadingSidebarTrailingX
          var leadingMarginNeededToCenter = midpointBetweenSidebarsX - (videoSize.width * 0.5)
          var trailingMarginNeededToCenter = viewportSize.width - (midpointBetweenSidebarsX + (videoSize.width * 0.5))
          // Do not allow negative margins. They would cause the video to move outside the viewport bounds
          if leadingMarginNeededToCenter < 0 {
            // Give the margin back to the other sidebar
            trailingMarginNeededToCenter -= leadingMarginNeededToCenter
            leadingMarginNeededToCenter = 0
          }
          if trailingMarginNeededToCenter < 0 {
            leadingMarginNeededToCenter -= trailingMarginNeededToCenter
            trailingMarginNeededToCenter = 0
          }
          // Allocate the scarce amount of unusedWidth proportionately to the demand:
          let allocationFactor = unusedWidth / (leadingMarginNeededToCenter + trailingMarginNeededToCenter)

          leadingMargin += leadingMarginNeededToCenter * allocationFactor
          trailingMargin += trailingMarginNeededToCenter * allocationFactor
        }
      }

      // Round to integers for a smoother animation
      let leadingMarginRounded = leadingMargin.rounded(.down)
      let trailingMarginRounded = trailingMargin.rounded()
      let excessWidth = leadingMarginRounded + trailingMarginRounded - leadingMargin - trailingMargin
      assert(excessWidth <= 1.0, "Excess width (\(excessWidth)) cardinality <= 1.0! LeadingMargin=\(leadingMargin) TrailingMargin=\(trailingMargin)")
      leadingMargin = leadingMarginRounded
      trailingMargin = trailingMarginRounded
      trailingMargin -= excessWidth
    }

    Logger.log.trace {
      let remainingWidthForVideo = viewportSize.width - (leadingMargin + trailingMargin)
      return "[geo] Viewport width=\(viewportSize.width): Sidebars=[lead:\(insideBars.leading) trail:\(insideBars.trailing)] Margins=[lead:\(leadingMargin) trail:\(trailingMargin)] remainingWidthForVideo: \(remainingWidthForVideo), videoWidth: \(videoSize.width)"
    }
    let unusedHeight = viewportSize.height - videoSize.height
    var topMargin = (unusedHeight * 0.5).rounded()
    let btmMargin = topMargin
    let excessHeight = topMargin + btmMargin - unusedHeight
    if excessHeight != 0 {
      topMargin -= excessHeight
    }
    let computedMargins = MarginQuad(top: topMargin, trailing: trailingMargin,
                                     bottom: btmMargin, leading: leadingMargin)
    assert(videoSize.height + computedMargins.totalHeight == viewportSize.height, "Bad VP margin height! V-Size=\(videoSize) + VP-width(computed)=\(computedMargins) != VP-width(actual)=\(viewportSize.height)")
    assert(videoSize.width + computedMargins.totalWidth == viewportSize.width,
           "Bad VP margin width! V-width=\(videoSize.width) + VP-Margins[leading=\(computedMargins.leading), trailing=\(computedMargins.trailing)] → VP-width(computed)=\(videoSize.width + computedMargins.totalWidth) != VP-width(actual)=\(viewportSize.width)")
    return computedMargins
  }

}
