//
//  PWinGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 7/11/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/**
`PWinGeometry`
 Data structure which describes the basic layout configuration of a player window (`PlayerWindowController`).

 For `let wc = PlayerWindowController()`, an instance of this class describes:
 1. The size & position (`windowFrame`) of an IINA player `NSWindow`.
 2. The size of the window's viewport (`viewportView` in a `PlayerWindowController` instance).
    The viewport contains the `videoView` and all of the `Preference.PanelPlacement.inside` views (`viewportSize`).
    Size is inferred by subtracting the bar sizes from `windowFrame`.
 3. Either the height or width of each of the 4 `outsideViewport` bars, measured as the distance between the
    outside edge of `viewportView` and the outermost edge of the bar. This is the minimum needed to determine
    its size & position; the rest can be inferred from `windowFrame` and `viewportSize`.
    If instead the bar is hidden or is shown as `insideViewport`, its outside value will be `0`.
 4. Either  height or width of each of the 4 `insideViewport` bars. These are measured from the nearest outside wall of
    `viewportView`.  If instead the bar is hidden or is shown as `outsideViewport`, its inside value will be `0`.
 5. The size of the video itself (`videoView`), which may or may not be equal to the size of `viewportView`,
    depending on whether empty space is allowed around the video.
 6. The video aspect ratio. This is stored here mainly to create a central reference for it, to avoid differing
    values which can arise if calculating it from disparate sources.

 Below is an example of a player window with letterboxed video, where the viewport is taller than `videoView`.
 All 4 bars in this example are in the `outsideViewport` placement.
 • Identifiers beginning with `wc.` refer to fields in the `PlayerWindowController` instance.
 • Identifiers beginning with `geo.` are `PWinGeometry` fields.
 • The window's frame (`windowFrame`) is the outermost rectangle.
 • The frame of `wc.videoView` is the innermost dotted-lined rectangle.
 • The frame of `wc.viewportView` contains `wc.videoView` and additional space for black bars.
 ```
                                 `geo.viewportSize.width`
                                  (of `wc.viewportView`)
                               ◄--------------------------►
 ┌────────────────────────────────────────────────────────────────────────────────────────┐`geo.windowFrame`
 │ Top Margin                                   ▲                                         │
 │ (only nonzero when covering Macbook notch)   │`geo.topMarginHeight`                    │
 │                                              ▼                                         │
 ├────────────────────────────────────────────────────────────────────────────────────────┤
 │ Top Bar (outside)                        ▲                                             │
 │                                          │`geo.outsideBars.top`                        │
 │                                          ▼  (`wc.topBar.view`)                         │
 ├────────────────────────────┬────────────────────────────┬──────────────────────────────┤ ─ ◄--- `geo.insideBars.top == 0`
 │ Leading Sidebar (outside)  │   `viewportMargins.top`    │ Trailing Sidebar (outside)   │ ▲
 │                            ├─────┬────────────────┬─────┤                              │ │ `geo.viewportSize.height`
 │                            │ [€] │ `geo.videoSize`│ [¥] │◄----------------------------►│ │  (of `wc.viewportView`)
 │◄--------------------------►│     │(`wc.videoView`)│     │  `geo.outsideBars.trailing`  │ │
 │  `geo.outsideBars.leading` ├─────┴────────────────┴─────┤ (of `wc.trailingSidebarView`)│ │
 │(of `wc.leadingSidebarView`)│  `viewportMargins.bottom`  │                              │ ▼
 ├────────────────────────────┴────────────────────────────┴──────────────────────────────┤ ─ ◄--- `geo.insideBars.bottom == 0`
 │ Bottom Bar (outside)                 ▲                                                 │
 │                                      │`geo.outsideBars.bottom`                         │  [€] = `viewportMargins.leading`
 │                                      ▼ (of `wc.bottomBar.view`)                         │  [¥] = `viewportMargins.trailing`
 └────────────────────────────────────────────────────────────────────────────────────────┘
 ```
 */
struct PWinGeometry: Equatable, CustomStringConvertible, Sendable {

  // MARK: Stored properties

  // - Screen:

  /// The ID of the screen on which this window is displayed
  let screenID: String
  /// Describes how a given `PlayerWindow` must fit inside its given screen (corresponding to `screenID`).
  let screenFit: ScreenFit
  /// The mode affects lockViewportToVideo behavior and size calculations.
  let mode: PlayerWindowMode

  // - Window dimensions, outermost → innermost

  /// The size & position (`window.frame`) of the `PlayerWindow`.
  let windowFrame: NSRect

  /// The height of extra black space (if any) above `outsideBars.top`, used for covering MacBook's
  /// magic camera housing while in legacy fullscreen.
  let topMarginHeight: CGFloat

  /// 4 values, representing the thickness of each of the 4 "outside" panels.
  /// A value of `0` indicates the given panel is closed/hidden.
  let outsideBars: MarginQuad

  /// 4 values, representing the thickness of each of the 4 "inside" panels.
  /// A value of `0` indicates the given panel is closed/hidden.
  let insideBars: MarginQuad

  let viewportMargins: MarginQuad
  let video: VideoGeometry

  /// Can be used to associate this geometry to the value of the window's`video-zoom` mpv property.
  /// Only used for pinch-to-zoom in windowed mode with `lockViewportToVideoSize` enabled.
  /// In all other cases this should be set to `1.0`..
  ///
  /// When the window is maximized within its screen, having a zoom > 1.0 allow the window's `videoView`
  /// to expand beyond its inherent aspect ratio even if `lockViewportToVideoSize` is enabled.
  let videoZoom: CGFloat

  // MARK: Initializers / Factory Methods

  /// Derives `viewportSize` and `videoSize` from `windowFrame`, `viewportMargins` and `videoAspect`.
  init(windowFrame: NSRect, screenID: String, screenFit: ScreenFit,
       mode: PlayerWindowMode, topMarginHeight: CGFloat,
       outsideBars: MarginQuad, insideBars: MarginQuad,
       viewportMargins: MarginQuad? = nil, video: VideoGeometry,
       videoZoom: CGFloat) {

    self.windowFrame = windowFrame
    self.screenID = screenID
    self.screenFit = screenFit
    self.mode = mode
    self.topMarginHeight = topMarginHeight
    self.outsideBars = outsideBars
    self.insideBars = insideBars
    self.video = video

    let viewportSize = GeoUtil.deriveViewportSize(from: windowFrame, topMarginHeight: topMarginHeight, outsideBars: outsideBars)
    assert(viewportSize.width >= 0 && viewportSize.height >= 0, "viewportSize must not be negative! Found: \(viewportSize)")

    let targetVideoSize = video.videoSizeDisplay
    let videoSize = GeoUtil.computeVideoViewSize(forVideoDisplaySize: targetVideoSize, toFillIn: viewportSize,
                                                 minViewportMargins: viewportMargins, videoZoom: videoZoom, mode: mode)
    self.videoSize = videoSize

    if let viewportMargins {
      self.viewportMargins = viewportMargins
    } else {
      self.viewportMargins = GeoUtil.computeBestViewportMargins(viewportSize: viewportSize, videoSize: videoSize,
                                                                insideBars: insideBars, mode: mode)
    }
    assert(videoZoom >= 1.0, "videoZoom must not be less than 1.0!")
    self.videoZoom = videoZoom

    assert(!mode.isFullScreen || screenFit.isFullScreen, "screenFit must be fullScreen when mode is fullScreen")
  }

  /// Makes a clone of `self` and returns it.
  ///
  /// - Each param which is `nil` or is not given will cause the clone to reuse the corresponding field from `self`.
  ///   Otherwise any value given will be given to the clone. With one exception...
  /// - The param `viewportMargins`, if `nil`, will result in viewport margins being recomputed for the new object.
  ///   In other words, `self.viewportMargins` is never implicitly given to the clone.
  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, screenFit: ScreenFit? = nil,
             mode: PlayerWindowMode? = nil, topMarginHeight: CGFloat? = nil,
             outsideBars: MarginQuad? = nil, insideBars: MarginQuad? = nil,
             viewportMargins: MarginQuad? = nil,
             video: VideoGeometry? = nil,
             videoZoom: CGFloat? = nil) -> PWinGeometry {

    let mode = mode ?? self.mode
    if mode == .musicMode {
      // This might get ugly in the future... maybe fail instead to force developer to add explcit choice in all situations?
      return cloneMusicMode(windowFrame: windowFrame, screenID: screenID, video: video)
    }

    let clonedGeo = PWinGeometry(windowFrame: windowFrame ?? self.windowFrame,
                                 screenID: screenID ?? self.screenID,
                                 screenFit: screenFit ?? self.screenFit,
                                 mode: mode,
                                 topMarginHeight: topMarginHeight ?? self.topMarginHeight,
                                 outsideBars: outsideBars ?? self.outsideBars,
                                 insideBars: insideBars ?? self.insideBars,
                                 viewportMargins: viewportMargins,
                                 video: video ?? self.video,
                                 videoZoom: videoZoom ?? self.videoZoom)
    return clonedGeo
  }

  // MARK: - OSD

  var shouldHaveOSD: Bool {
    /// Only time we do not include `osdView` in layout is if there is no viewport.
    /// Even if OSD is disabled via pref, `osdView` is still needed for things like subtitle
    /// download.
    return isViewportShown
  }

  var shouldHaveAdditionalInfo: Bool {
    mode == .fullScreenNormal && Preference.bool(for: .displayTimeAndBatteryInFullScreen)
  }

  /// OSD offset from top of viewportView.
  ///
  ///  Needs to include topMarginHeight if it exists. We never want the OSD to overlap with the notch.
  ///  (We do allow the OSC to overlap with the notch though).
  func osdOffsetFromTopOfViewport() -> CGFloat {
    if mode == .musicMode {
      return Constants.standardTitleBarHeight
    }
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    // In native FS, the user is able to trigger a showing of the title bar, which will drop down over the window's content.
    // But so far there seems to be no good way to detect this. So just add extra space for the title bar at all times.
    let extraOffsetForTitleBar = max(0, Constants.standardTitleBarHeight - outsideBars.top - insideBars.top)
    if screenFit == .nativeFullScreen {
      return max(0, insideBars.top) + extraOffsetForTitleBar + 8
    } else {
      // Possibly entering legacy full screen
      let maxScreenUsableHeight = screen.frameWithoutCameraHousing.height
      return max(0, insideBars.top, windowFrame.height - maxScreenUsableHeight - cameraHousingOffset) + extraOffsetForTitleBar + 8
    }
  }

  /// Minimum offset from bottom of `osdView` to bottom of viewport.
  ///
  /// Should always be >= 0.
  /// Do not allow `osdView` to overlap with the `inside` bottom OSD. This is important for online subtitle selection,
  /// wherein`SubChooseViewController` is added to the OSD. It often wants more vertical space than the window's height
  /// when showing results, but its buttons at the bottom need always be reachable.
  func osdMinOffsetToBottomOfViewport() -> CGFloat {
    return max(0, insideBars.bottom) + 8
  }

  func getOSDTextSize() -> CGFloat {
    let availableSpaceForOSD = widthBetweenInsideSidebars

    // Reduce text size if horizontal space is tight
    var osdTextSize = max(Constants.OSD.minTextSize, CGFloat(Preference.float(for: .osdTextSize)))
    switch availableSpaceForOSD {
    case ..<300:
      osdTextSize = min(osdTextSize, 18)
    case 300..<400:
      osdTextSize = min(osdTextSize, 28)
    case 400..<500:
      osdTextSize = min(osdTextSize, 36)
    case 500..<700:
      osdTextSize = min(osdTextSize, 50)
    case 700..<900:
      osdTextSize = min(osdTextSize, 72)
    case 900..<1200:
      osdTextSize = min(osdTextSize, 96)
    case 1200..<1500:
      osdTextSize = min(osdTextSize, 120)
    default:
      osdTextSize = min(osdTextSize, 150)
    }

    return osdTextSize
  }

  // MARK: - Other computed properties

  var description: String {
    return "PWinGeo{\(windowFrame) \(screenID.quoted) \(mode) \(screenFit) \(isMusicModePlaylistShown ? "pListH=\(musicModePlaylistHeight.logStr)" : "pList=N") notchH=\(topMarginHeight.logStr) outBars=\(outsideBars) inBars=\(insideBars) vidSize=\(videoSize) vidMargins=\(viewportMargins) \(video) vidScale=\(videoScale.roundedTo2())}"
  }

  var log: any Logger.Subsystem { video.log }

  /// Can only be `false` while in music mode. All other modes should return `true` always.
  var isViewportShown: Bool {
    return viewportSize.height > 0
  }

  /// Only nonzero if leading sidebar is open
  var leadingSidebarWidth: CGFloat {
    assert(outsideBars.trailing == 0 || insideBars.trailing == 0)
    return outsideBars.leading + insideBars.leading
  }

  var isLeadingSidebarShown: Bool {
    return leadingSidebarWidth > 0
  }

  var leadingSidebarPlacement: Preference.PanelPlacement? {
    if insideBars.leading > 0 {
      return .insideViewport
    } else if outsideBars.leading > 0 {
      return .outsideViewport
    }
    return nil
  }

  /// Only nonzero if trailing sidebar is open
  var trailingSidebarWidth: CGFloat {
    assert(outsideBars.trailing == 0 || insideBars.trailing == 0)
    return outsideBars.trailing + insideBars.trailing
  }

  var isTrailingSidebarShown: Bool {
    return trailingSidebarWidth > 0
  }

  var trailingSidebarPlacement: Preference.PanelPlacement? {
    if insideBars.trailing > 0 {
      return .insideViewport
    } else if outsideBars.trailing > 0 {
      return .outsideViewport
    }
    return nil
  }

  /// Alias for `topMarginHeight`.
  var cameraHousingOffset: CGFloat {
    topMarginHeight
  }

  var topBarBtmOffsetFromVPTop: CGFloat {
    return insideBars.top
  }

  var vpTopOffsetFromTopBarTop: CGFloat {
    return outsideBars.top
  }

  var vpTopOffsetFromCVTop: CGFloat {
    vpTopOffsetFromTopBarTop + cameraHousingOffset
  }

  var vpBtmOffsetFromCVTop: CGFloat {
    return viewportSize.height + vpTopOffsetFromCVTop
  }

  var bottomBarTopOffsetFromCVTop: CGFloat {
    return vpBtmOffsetFromCVTop - insideBars.bottom
  }

  var bottomBarBtmOffsetFromCVTop: CGFloat {
    return windowFrame.height
  }

  var vpBtmOffsetFromTopOfBottomBar: CGFloat {
    return insideBars.bottom
  }

  var bottomBarBtmOffsetFromVPBtm: CGFloat {
    return outsideBars.bottom
  }

  /// Same as `bottomBarBtmOffsetFromVPBtm`.
  var cvBtmOffsetFromVPBtm: CGFloat {
    return bottomBarBtmOffsetFromVPBtm
  }

  /// Can only be `true` while in music mode.
  var isMusicModePlaylistShown: Bool {
    guard mode == .musicMode else { return false }
    let playlistHeight = outsideBars.totalHeight - Constants.MusicMode.oscHeight
    return playlistHeight >= Constants.MusicMode.minPlaylistHeight
  }

  /// If in music mode & playlist is visible, indicates playlist height.
  /// Will be 0 if not in music mode or playlist is not visible.
  /// Derived from other properties.
  var musicModePlaylistHeight: CGFloat {
    guard mode == .musicMode else { return 0 }
    return round(windowFrame.height - Constants.MusicMode.oscHeight - videoSize.height)
  }

  /// Final aspect ratio to be used for `videoView` aspect. It should equal `dwidth / dheight` rounded to 6 decimal places.
  ///
  /// This used as the source for the `aspectRatio` constraint in `ViewportConstraints`, to set a required aspect for `VideoView`.
  /// This rounds to 6 decimal places. Do not use higher precision because it will lead to the `aspectRatio` constraint
  /// being rebuilt & reapplied several times during window resize which can lead to choppiness.
  var videoViewAspect: CGFloat {
    return video.videoAspectDisplay
  }

  let videoSize: NSSize

  /// Calculates the margin adjustments needed to:
  /// 1. Minimize the overlap between inside bars & `videoView`, by donating unuused margin from one side to its opposite.
  /// 2. If bars on both sides overlap with `videoView`, then center `videoView` between them.
  /// Both pairs of sides are calculated independently (top/bottom & leading/trailing).
  ///
  /// Shown here is an example `PWinGeometry` with a large bottom bar which overlaps the video. But there is extra space
  /// between the top bar & the top of the video which can be donated to the bottom.
  ///
  /// See also: `VideoView_Constraints.swift`.
  /// ```
  /// windowFrame.top
  /// +--┌──────────────────┐+  ▲
  /// |  │                  │|  │vpMargins.top
  /// |  │   inside.top     │|  │
  /// |  │                  │|  │
  /// |  └──────────────────┘|  │  ▲
  /// |                      |  │  │TopSurplus = 3
  /// |                      |  │  │TopDeficit = 0
  /// | ╔═════════════════╗  |  ▼  ▼
  /// | ║                 ║  |
  /// | ║                 ║  |
  /// | ║                 ║  |
  /// | ║    VideoView    ║  |
  /// | ║                 ║  |
  /// | ║ ┌───────────────║─┐|     ▲
  /// | ║ │               ║ │|     │BtmSurplus = 0
  /// | ║ │               ║ │|     │BtmDeficit = 3
  /// | ╚═════════════════╝ │| ▲   ▼
  /// |   │                 │| │
  /// |   │   inside.btm    │| │
  /// |   │                 │| │
  /// |   │                 │| │
  /// |   │                 │| │vpMargins.btm
  /// |   │                 │| │
  /// +---└─────────────────┘+ ▼
  /// windowFrame.btm
  /// ```
  ///
  var offsetsToKeepVideoAwayFromInsideBars: MarginQuad {
    // Start with equal margins for calculation, despite whatever the actual distribution is
    let vpMarginsTotalWidth = viewportMargins.totalWidth
    let vpMarginsTotalHeight = viewportMargins.totalHeight
    let isLetterboxed = vpMarginsTotalHeight > vpMarginsTotalWidth

    if isLetterboxed {
      // Has black margins on top and bottom. No free space on the sides.
      let vpMarginForTopOrBtm = vpMarginsTotalHeight * 0.5
      let topDeficit = max(0, insideBars.top - vpMarginForTopOrBtm)
      let btmDeficit = max(0, insideBars.bottom - vpMarginForTopOrBtm)

      let needsMoreAtBtm = btmDeficit > topDeficit

      if topDeficit > 0 && btmDeficit > 0 {
        let avgDeficit = min((topDeficit + btmDeficit), vpMarginsTotalHeight) * 0.5
        if needsMoreAtBtm {
          return .init(bottom: avgDeficit)
        } else {
          return .init(top: avgDeficit)
        }
      } else if needsMoreAtBtm {
        // Adding to btm (shifting upwards). Use surplus from top
        let topSurplus = max(0, vpMarginForTopOrBtm - insideBars.top)
        return .init(bottom: min(btmDeficit, topSurplus) * 2)
      } else {
        let btmSurplus = max(0, vpMarginForTopOrBtm - insideBars.bottom)
        return .init(top: min(topDeficit, btmSurplus) * 2)
      }

    } else {  // Pillar boxed
      // Has black margins on leading & trailing. No free space on the top or bottom.
      let vpMarginForLeadingOrTrailing = vpMarginsTotalWidth * 0.5
      let leadingDeficit = max(0, insideBars.leading - vpMarginForLeadingOrTrailing)
      let trailingDeficit = max(0, insideBars.trailing - vpMarginForLeadingOrTrailing)

      let needsMoreAtTrailing = trailingDeficit > leadingDeficit

      if leadingDeficit > 0 && trailingDeficit > 0 {
        let avgDeficit = min((leadingDeficit + trailingDeficit), vpMarginsTotalWidth) * 0.5
        if needsMoreAtTrailing {
          return .init(trailing: avgDeficit)
        } else {
          return .init(leading: avgDeficit)
        }
      } else if needsMoreAtTrailing {
        // Adding to trailing (shifting leading-wards). Use surplus from leading
        let leadingSurplus = max(0, vpMarginForLeadingOrTrailing - insideBars.leading)
        return .init(trailing: min(trailingDeficit, leadingSurplus) * 2)
      } else {
        let trailingSurplus = max(0, vpMarginForLeadingOrTrailing - insideBars.trailing)
        return .init(leading: min(leadingDeficit, trailingSurplus) * 2)
      }
    }
  }

  var videoScale: CGFloat {
    videoSize.width / video.videoSizeCAR.width
  }

  /// `MPVProperty.currentWindowScale`: see `mp_property_current_window_scale()` in mpv's `player/command.c`
  func mpvWindowScale() -> CGFloat {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    let backingScaleFactor = screen.backingScaleFactor
    let viewportSize = viewportSize
    let videoSize = video.videoSizeCAR
    let mpvWindScale = (((viewportSize.width / videoSize.width) + (viewportSize.height / videoSize.height)) / 2 * backingScaleFactor).roundedTo6()
    return mpvWindScale
  }

  func scalingViewport(fromMpvWindowScale wndScale: CGFloat) -> PWinGeometry {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    let backingScaleFactor = screen.backingScaleFactor
    let videoSize = video.videoSizeCAR

    // vpW / vW + vpH / vH = S
    // But: vpW == (vpH * vpAspect), so:
    // vpH * vH * vpAspect / vW + vpH = S * vH
    // ((vpH * vpAspect) / vW) + (vpH / vH) = S
    // vpH * ((vpAspect / vW) + (1 / vH)) = S
    // vpH = S / ((vpAspect / vW) + (1 / vH))
    let vpH = (wndScale / backingScaleFactor * 2) / ((viewportSize.aspect / videoSize.width) + (1 / videoSize.height))
    let vpW = vpH * viewportSize.aspect
    let outputViewportSize = NSSize(width: vpW, height: vpH).rounded()
    return scalingViewport(to: outputViewportSize)
  }

  /// Like `videoSizeCAR`, but after applying `scale`.
  var videoSizeCARS: CGSize {
    return videoSize
  }

  /// Calculated from `windowFrame`.
  /// This will be equal to `videoSize`, unless IINA is configured to allow the window to expand beyond
  /// the bounds of the video for a letterbox/pillarbox effect (separate from anything mpv includes)
  var viewportSize: NSSize {
    return GeoUtil.deriveViewportSize(from: windowFrame, topMarginHeight: topMarginHeight, outsideBars: outsideBars)
  }

  var viewportFrameInWindowCoords: NSRect {
    let origin = CGPoint(x: outsideBars.leading,
                         y: outsideBars.bottom)
    return NSRect(origin: origin, size: viewportSize)
  }

  var viewportFrameInScreenCoords: NSRect {
    let viewportFrameInWindowCoords = viewportFrameInWindowCoords
    let origin = CGPoint(x: windowFrame.origin.x + viewportFrameInWindowCoords.origin.x,
                         y: windowFrame.origin.y + viewportFrameInWindowCoords.origin.y)
    return NSRect(origin: origin, size: viewportSize)
  }

  var videoFrameInWindowCoords: NSRect {
    assert(viewportSize.width - videoSize.width >= 0 && viewportSize.height - videoSize.height >= 0,
           "viewportSize \(viewportSize) is smaller than videoSize \(videoSize)")
    let adjustedOrigin = CGPoint(x: outsideBars.leading + viewportMargins.leading,
                                 y: outsideBars.bottom + viewportMargins.bottom)
    return NSRect(origin: adjustedOrigin, size: videoSize)
  }

  var videoFrameInScreenCoords: NSRect {
    let videoFrameInWindowCoords = videoFrameInWindowCoords
    let origin = CGPoint(x: windowFrame.origin.x + videoFrameInWindowCoords.origin.x,
                         y: windowFrame.origin.y + videoFrameInWindowCoords.origin.y)
    return NSRect(origin: origin, size: videoSize)
  }

  var widthBetweenInsideSidebars: CGFloat {
    return viewportSize.width - insideBars.totalWidth
  }

  var hasTopPaddingForCameraHousing: Bool {
    return topMarginHeight > 0
  }

  var isLegacyFullScreen: Bool {
    screenFit == .legacyFullScreen
  }

  var isNativeFullScreen: Bool {
    screenFit == .nativeFullScreen
  }

  // MARK: - Calculation Utils

  func getWidthBetweenInsideSidebars(leadingSidebarWidth: CGFloat? = nil, trailingSidebarWidth: CGFloat? = nil,
                                     in viewportWidth: CGFloat) -> CGFloat {
    let lead = leadingSidebarWidth ?? insideBars.leading
    let trail = trailingSidebarWidth ?? insideBars.trailing
    return viewportWidth - lead - trail
  }

  func getExcessSpaceBetweenInsideSidebars(leadingSidebarWidth: CGFloat? = nil, trailingSidebarWidth: CGFloat? = nil,
                                           in viewportWidth: CGFloat) -> CGFloat {
    getWidthBetweenInsideSidebars(leadingSidebarWidth: leadingSidebarWidth,
                                  trailingSidebarWidth: trailingSidebarWidth,
                                  in: viewportWidth) - Constants.Window.minWidthBetweenInsideSidebars
  }

  /// Finds minimum video size of the current geometry, assuming bars, mode, video aspect stay constant
  func minVideoSize() -> CGSize {
    return GeoUtil.minViewportSize(mode: mode, videoAspect: videoViewAspect, insideBars: insideBars)
  }

  // This also accounts for videoAspect, and space needed by inside sidebars, if any
  func minViewportSize(mode: PlayerWindowMode? = nil) -> NSSize {
    let mode = mode ?? self.mode
    return GeoUtil.minViewportSize(mode: mode, videoAspect: videoViewAspect, insideBars: insideBars)
  }

  func minWindowSize(mode: PlayerWindowMode? = nil) -> NSSize {
    let mode = mode ?? self.mode
    return GeoUtil.minWindowSize(mode: mode, videoAspect: videoViewAspect, outsideBars: outsideBars, insideBars: insideBars)
  }

  fileprivate func computeMaxViewportSize(in containerSize: NSSize) -> NSSize {
    // Resize only the video. Panels outside the video do not change size.
    // To do this, subtract the "outside" panels from the container frame
    return NSSize(width: containerSize.width - outsideBars.totalWidth,
                  height: containerSize.height - outsideBars.totalHeight - topMarginHeight)
  }

  /// Indicates height of video / album art when it is visible, or what the height should be even if
  /// it is not visible.
  /// Derived from other properties.
  var videoHeightWhenVisible: CGFloat {
    guard mode == .musicMode else {
      return videoSize.height
    }
    return PWinGeometry.MusicMode.videoHeightWhenVisible(windowFrame: windowFrame, video: video)
  }

  /// Derived from other properties.
  var videoHeight: CGFloat {
    return isViewportShown ? videoHeightWhenVisible : 0
  }

  var topBarHeight: CGFloat {
    assert(((insideBars.top == 0) || (outsideBars.top == 0)), "Cannot have both inside and outside top bars")
    return insideBars.top + outsideBars.top
  }

  var bottomBarHeight: CGFloat {
    assert(((insideBars.bottom == 0) || (outsideBars.bottom == 0)), "Cannot have both inside and outside bottom bars")
    return insideBars.bottom + outsideBars.bottom
  }

  /// Sidebar tab downshift: try to match height of inside topBar.
  ///
  /// Top bar always spans the whole width of the window (unlike the bottom bar) so we need to add space for it.
  var sidebarDownshift: CGFloat {
    return insideBars.top
  }
  /// Sidebar tab height
  ///
  /// Special case for music mode: only really applies to `playlistView` because `quickSettingView` is never shown in this mode.
  var sidebarTabHeight: CGFloat {
    mode == .musicMode ? Constants.Sidebar.musicModeTabHeight : Constants.Sidebar.defaultTabHeight
  }

  // MARK: - Other Util Functions

  func hasEqual(windowFrame windowFrame2: NSRect? = nil, videoSize videoSize2: NSSize? = nil) -> Bool {
    return GeoUtil.areEqual(windowFrame1: windowFrame, windowFrame2: windowFrame2, videoSize1: videoSize, videoSize2: videoSize2)
  }

  func getContainerFrame(screenFit: ScreenFit? = nil) -> NSRect? {
    return GeoUtil.getContainerFrame(forScreenID: screenID, screenFit: screenFit ?? self.screenFit)
  }

  /// Adjusts the window origin for given `newWindowSize` such that the window's center does not move.
  private func adjustWindowOrigin(forNewWindowSize newWindowSize: NSSize) -> NSPoint {
    // Round the results to prevent excessive window drift due to small imprecisions in calculation
    let deltaX = ((newWindowSize.width - windowFrame.size.width) / 2).rounded()
    let deltaY = ((newWindowSize.height - windowFrame.size.height) / 2).rounded()
    let newOrigin = NSPoint(x: windowFrame.origin.x - deltaX,
                            y: windowFrame.origin.y - deltaY)
    return newOrigin
  }

  // MARK: - Fitted Resize Functions
  // All of these call scalingViewport() to produce a PWinGeometry with consistent dimensions.

  /// Encapsulates logic for `windowWillResize`, but specfically for music mode.
  func resizingWindowInMusicMode(to requestedSize: NSSize, inLiveResize: Bool, isLiveResizingWidth: Bool) -> PWinGeometry {
    guard mode == .musicMode else {
      Logger.fatal("PWinGeometry.resizingWindowInMusicMode: called on non-music mode: \(self)")
    }
    return resizingWindow(to: requestedSize, lockViewportToVideoSize: true , inLiveResize: inLiveResize, isLiveResizingWidth: isLiveResizingWidth)
  }

  /// Encapsulates logic for `windowWillResize`.
  func resizingWindow(to requestedSize: NSSize,
                      lockViewportToVideoSize: Bool,
                      inLiveResize: Bool, isLiveResizingWidth: Bool) -> PWinGeometry {
    let outputGeo: PWinGeometry

    switch mode {

    case .fullScreenNormal, .fullScreenInteractive:
      log.error("[geo] PWinGeometry cannot resize window: mode (\(mode)) is not windowed or music mode!")
      return self

    case .musicMode:
      assert(lockViewportToVideoSize, "lockViewportToVideoSize must always be true in music mode")
      let containerFrame = GeoUtil.getContainerFrame(forScreenID: screenID, screenFit: .stayInside)!
      let maxWindowWidth = CGFloat(Preference.float(for: .musicModeMaxWidth))

      if inLiveResize, isViewportShown && !isMusicModePlaylistShown {
        // Special case when scaling only video without playlist: allow window height to change, similar to windowed mode.
        let nonViewportAreaSize = windowFrame.size - viewportSize
        let requestedViewportSize = requestedSize - nonViewportAreaSize

        let scaledViewportSize: NSSize
        if isLiveResizingWidth {
          // Option A: resize height based on requested width
          scaledViewportSize = NSSize(width: requestedViewportSize.width,
                                      height: 0)  // note: only width is used by scalingViewport()
        } else {
          // Option B: resize width based on requested height
          // Always need to calculate valid width first, then recalculate height based on width (to ensure video size rounding is consistent for PWinGeo constructor)
          let wndWidth = min(maxWindowWidth, containerFrame.width, round(requestedViewportSize.height * videoViewAspect))
          scaledViewportSize = NSSize(width: wndWidth,
                                      height: 0)  // note: only width is used by scalingViewport()
        }
        outputGeo = scalingViewport(to: scaledViewportSize)

      } else {
        /// __General music mode layout__
        /// When the window's width changes, the video scales to match while keeping its aspect ratio,
        /// and the control bar (`musicModeControlBarView`) and playlist are pushed down.
        /// Calculate the maximum width/height the art can grow to so that `musicModeControlBarView` is not pushed off the screen.
        let minPlaylistHeight = isMusicModePlaylistShown ? Constants.MusicMode.minPlaylistHeight : 0
        let videoAspect = videoViewAspect

        var maxWinWidth = min(maxWindowWidth, containerFrame.width)
        var maxVideoHeight: CGFloat
        if isViewportShown {
          maxVideoHeight = containerFrame.height - Constants.MusicMode.oscHeight - minPlaylistHeight
          /// `maxVideoHeight` can be negative if very short screen! Fall back to height based on `MiniPlayerMinWidth` if needed
          maxVideoHeight = max(maxVideoHeight, (Constants.MusicMode.minWindowWidth / videoAspect).rounded())
          maxWinWidth = min(maxWinWidth, maxVideoHeight * videoAspect)
        } else {
          maxVideoHeight = 0
        }

        // Determine width first
        var newWindowWidth: CGFloat = requestedSize.width.rounded()
        if Constants.MusicMode.minWindowWidth <= maxWinWidth {  // may not be true for videos with extreme aspect
          newWindowWidth = newWindowWidth.clamped(to: Constants.MusicMode.minWindowWidth...maxWinWidth)
        }

        // Now determine height. Clamp again in case rounding goes outside of bounds
        let videoHeight = (newWindowWidth / videoAspect).rounded().clamped(to: 0...maxVideoHeight)
        // Make sure height is within acceptable values
        let minWindowHeight = videoHeight + Constants.MusicMode.oscHeight + minPlaylistHeight
        let maxWindowHeight = isMusicModePlaylistShown ? containerFrame.height : minWindowHeight
        var newWindowHeight = requestedSize.height.rounded()
        if minWindowHeight <= maxWindowHeight {
          newWindowHeight = newWindowHeight.clamped(to: minWindowHeight...maxWindowHeight)
        }

        var outputWindowFrame = NSRect(origin: windowFrame.origin,
                                       size: NSSize(width: newWindowWidth, height: newWindowHeight))

        if ScreenFit.musicMode.shouldMoveWindowToKeepInContainer {
          outputWindowFrame = outputWindowFrame.constrainOrigin(in: containerFrame)
        }
        outputGeo = cloneMusicMode(windowFrame: outputWindowFrame)
        log.verbose("Resized musicMode window: reqSize=\(requestedSize) maxVideoHeight=\(maxVideoHeight) newWindowSize=\(outputWindowFrame.size) → outputGeo=\(outputGeo)")
      }

    case .windowedNormal, .windowedInteractive:
      // Need to resize window to match video aspect ratio, while taking into account any outside panels.
      if lockViewportToVideoSize && inLiveResize {
        let nonViewportAreaSize = self.windowFrame.size - self.viewportSize
        let requestedViewportSize = requestedSize - nonViewportAreaSize

        if isLiveResizingWidth {
          // Option A: resize height based on requested width
          let resizedWidthViewportSize = NSSize(width: requestedViewportSize.width,
                                                height: round(requestedViewportSize.width / videoViewAspect))
          outputGeo = scalingViewport(to: resizedWidthViewportSize)
        } else {
          // Option B: resize width based on requested height
          let resizedHeightViewportSize = NSSize(width: round(requestedViewportSize.height * videoViewAspect),
                                                 height: requestedViewportSize.height)
          outputGeo = scalingViewport(to: resizedHeightViewportSize)
        }
      } else {
        /// If `!inLiveResize`: resize request is not coming from the user. Could be BetterTouchTool, Retangle, or some window manager, or the OS.
        /// These tools seem to expect that both dimensions of the returned size are less than the requested dimensions, so check for this.
        /// If `lockViewportToVideoSize && !inLiveResize`: scale window to requested size; `refitted()` below will constrain as needed.
        outputGeo = self.scalingWindow(to: requestedSize)
      }
    }

    return outputGeo
  }

  /// Computes a new `PWinGeometry`, attempting to attain the given window size.
  func scalingWindow(to desiredWindowSize: NSSize? = nil,
                     screenID: String? = nil,
                     screenFit: ScreenFit? = nil) -> PWinGeometry {
    let requestedViewportSize: NSSize?
    if let desiredWindowSize {
      let outsideBarsTotalSize = outsideBars.totalSize
      requestedViewportSize = NSSize(width: desiredWindowSize.width - outsideBarsTotalSize.width,
                                     height: desiredWindowSize.height - outsideBarsTotalSize.height)
    } else {
      requestedViewportSize = nil
    }
    return scalingViewport(to: requestedViewportSize, screenID: screenID, screenFit: screenFit)
  }

  func refitted(using desiredScreenFit: ScreenFit? = nil, lockViewportToVideoSize: Bool? = nil) -> PWinGeometry {
    return scalingViewport(screenFit: desiredScreenFit, lockViewportToVideoSize: lockViewportToVideoSize)
  }

  /// See also: `mpvWindowScale()`
  func scalingViewport(toVideoScale mpvWindowScale: CGFloat) -> PWinGeometry {
    assert(!screenFit.isFullScreen)

    // Need to first determine the unscaled viewport size
    let videoSizeCAR = video.videoSizeCAR
    let viewportAspect = viewportSize.aspect
    let aspectRatio = videoSizeCAR.aspect / viewportAspect
    let vpSizeUnscaled: NSSize
    if aspectRatio > 1.0 {
      // Video is wider than viewport; letter boxed: need to expand height
      vpSizeUnscaled = NSSize(width: videoSizeCAR.width, height: videoSizeCAR.height * aspectRatio)
    } else {
      // Video is taller than viewport (or same size); pillar boxed: need to expand width
      vpSizeUnscaled = NSSize(width: videoSizeCAR.width / aspectRatio, height: videoSizeCAR.height)
    }

    let viewportSizeScaled = (vpSizeUnscaled * mpvWindowScale).rounded()
    return scalingViewport(to: viewportSizeScaled, screenFit: .stayInside)
  }

  /// Computes a new, valid `PWinGeometry` from this one, resized appropriately using the given params.
  ///
  /// This is the central nexus for all scaling operations - all should call this one.
  ///
  /// • If `desiredSize` is given, the `windowFrame` will be shrunk or grown as needed, as will the `videoSize` which will
  /// be resized to fit in the new `viewportSize` based on `videoAspect`.
  /// • If `mode` is provided, it will be applied to the resulting `PWinGeometry`.
  /// • If (1) `lockViewportToVideoSize` is specified, its value will be used (this should only be specified in rare cases).
  /// Otherwise (2) if `mode.alwaysLockViewportToVideoSize==true`, then `viewportSize` will be shrunk to the same size as `videoSize`,
  /// and `windowFrame` will be resized accordingly; otherwise, (3) `Preference.bool(for: .lockViewportToVideoSize)` will be used.
  /// • If `screenID` is provided, it will be associated with the resulting `PWinGeometry`; otherwise `self.screenID` will be used.
  /// • If `screenFit` is provided, it will be applied to the resulting `PWinGeometry`; otherwise `self.screenFit` will be used.
  func scalingViewport(to desiredSize: NSSize? = nil,
                       screenID: String? = nil,
                       screenFit desiredScreenFit: ScreenFit? = nil,
                       lockViewportToVideoSize: Bool? = nil,
                       mode: PlayerWindowMode? = nil,
                       videoZoom desiredVideoZoom: CGFloat? = nil) -> PWinGeometry {
    guard videoViewAspect >= 0 else {
      log.error("[geo] PWinGeometry cannot scale viewport: videoViewAspect (\(videoViewAspect)) is invalid!")
      assert(false)
      return self
    }

    let mode = mode ?? self.mode

    if mode == .musicMode {
      return scalingVideo(toWidth: desiredSize?.width ?? windowFrame.width, screenID: screenID)
    }

    // -- First, set up needed variables

    let lockViewportToVideoSize = mode.alwaysLockViewportToVideoSize || (lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize))
    let outputScreenFit = screenFit.changeDesiredFit(to: desiredScreenFit)
    let outsideBarsSize = outsideBars.totalSize
    let newScreenID = screenID ?? self.screenID
    let newVideoZoom = desiredVideoZoom ?? videoZoom

    let containerFrame: NSRect? = GeoUtil.getContainerFrame(forScreenID: newScreenID, screenFit: outputScreenFit)
    let maxViewportSize: NSSize?
    if let containerFrame {
      maxViewportSize = computeMaxViewportSize(in: containerFrame.size)
    } else {
      maxViewportSize = nil
    }
    let minViewportSize = minViewportSize(mode: mode)

    var newViewportSize = desiredSize ?? viewportSize
    log.trace("[geo] ScaleViewport start: newViewportSize=\(newViewportSize) lockViewport=\(lockViewportToVideoSize.yn) newVideoZoom=\(newVideoZoom)")

    // -- Viewport size calculation

    if lockViewportToVideoSize, !mode.isFullScreen {
      /// Make sure viewport size is at least as large as min.
      /// This is especially important when inside sidebars are taking up most of the space & `lockViewportToVideoSize` is `true`.
      /// Take min viewport margins into acocunt
      newViewportSize = NSSize(width: max(minViewportSize.width, newViewportSize.width),
                               height: max(minViewportSize.height, newViewportSize.height))

      if let maxViewportSize {
        /// Constrain `viewportSize` within `containerFrame`. Gotta do this BEFORE computing videoSize.
        /// So we do it again below. Big deal. Been mucking with this code way too long. It's fine.
        newViewportSize = NSSize(width: min(newViewportSize.width, maxViewportSize.width),
                                 height: min(newViewportSize.height, maxViewportSize.height))
      }

      /// Compute `videoSize` to fit within `viewportSize` (minus `viewportMargins`) while maintaining `videoAspect`.
      /// This is the part which reduces the viewport aspect to match the videoView aspect --
      /// *unless* video is zoomed > 1.0, in which case the aspect will match the portion of zoomed video which is
      /// able to fit within the available remaining space on screen.
      let newVideoSize = GeoUtil.computeVideoViewSize(forVideoDisplaySize: video.videoSizeDisplay,
                                                      toFillIn: newViewportSize, videoZoom: newVideoZoom,
                                                      mode: mode)
      // Add min margins back in (needed for Interactive Mode)
      let minViewportMargins = GeoUtil.minViewportMargins(forMode: mode)
      newViewportSize = NSSize(width: newVideoSize.width + minViewportMargins.totalWidth,
                               height: newVideoSize.height + minViewportMargins.totalHeight)
    }

    // Now enforce min & max viewport size [again]:
    newViewportSize = NSSize(width: max(minViewportSize.width, newViewportSize.width),
                             height: max(minViewportSize.height, newViewportSize.height))

    let oldViewportSize = viewportSize
    newViewportSize = NSSize(width: GeoUtil.snap(newViewportSize.width, to: oldViewportSize.width),
                             height: GeoUtil.snap(newViewportSize.height, to: oldViewportSize.height))

    // Enforce this AFTER snapping to old size so that we don't snap to increased size!
    if let maxViewportSize {
      newViewportSize = NSSize(width: min(newViewportSize.width, maxViewportSize.width),
                               height: min(newViewportSize.height, maxViewportSize.height))
    }

    // -- Window size calculation

    let newWindowSize = NSSize(width: round(newViewportSize.width + outsideBarsSize.width),
                               height: round(newViewportSize.height + outsideBarsSize.height + topMarginHeight))

    let adjustedOrigin = adjustWindowOrigin(forNewWindowSize: newWindowSize)
    var outputWindowFrame = NSRect(origin: adjustedOrigin, size: newWindowSize)
    if let containerFrame, outputScreenFit.shouldMoveWindowToKeepInContainer {
      outputWindowFrame = outputWindowFrame.constrainOrigin(in: containerFrame)
      if outputScreenFit == .centerInside {
        outputWindowFrame = outputWindowFrame.size.centeredRect(in: containerFrame)
      }
      log.trace("[geo] ScaleViewport: constrainedIn=\(containerFrame) → windowFrame=\(outputWindowFrame)")
    } else {
      log.trace("[geo] ScaleViewport: → windowFrame=\(outputWindowFrame)")
    }

    let refittedGeo = self.clone(windowFrame: outputWindowFrame, screenID: newScreenID, screenFit: outputScreenFit, mode: mode,
                                 videoZoom: newVideoZoom)

#if DEBUG
    if DebugConfig.validatePWinGeometry {
      refittedGeo.validate()
    }
#endif
    return refittedGeo
  }

#if DEBUG
  func validate() {
    assert(windowFrame.width >= outsideBars.totalWidth + insideBars.totalWidth,
           "Window width (\(windowFrame.width)) is too small to contain sidebars (inside=\(insideBars), outside=\(outsideBars))")
    assert(windowFrame.height >= outsideBars.totalHeight + insideBars.totalHeight,
           "Window height (\(windowFrame.height)) is too small to contain top + bottom bars (inside=\(insideBars.totalHeight), outside=\(outsideBars.totalHeight))")
    assert(viewportSize.width >= 0 && viewportSize.height >= 0,
           "Expected W ≥ 0 & H ≥ 0 for viewportSize, found \(viewportSize)")
    assert(viewportSize.width.isInteger && viewportSize.height.isInteger,
           "Expected integer W & H for viewportSize, found \(viewportSize)")

    assert(topMarginHeight >= 0, "Expected topMarginHeight ≥ 0, found \(topMarginHeight)")

    assert(outsideBars.top >= 0, "Expected outsideBars.top ≥ 0, found \(outsideBars.top)")
    assert(outsideBars.trailing >= 0, "Expected outsideBars.trailing ≥ 0, found \(outsideBars.trailing)")
    assert(outsideBars.bottom >= 0, "Expected outsideBars.bottom ≥ 0, found \(outsideBars.bottom)")
    assert(outsideBars.leading >= 0, "Expected outsideBars.leading ≥ 0, found \(outsideBars.leading)")

    assert(insideBars.top >= 0, "Expected insideBars.top ≥ 0, found \(insideBars.top)")
    assert(insideBars.trailing >= 0, "Expected insideBars.trailing ≥ 0, found \(insideBars.trailing)")
    assert(insideBars.bottom >= 0, "Expected insideBars.bottom ≥ 0, found \(insideBars.bottom)")
    assert(insideBars.leading >= 0, "Expected insideBars.leading ≥ 0, found \(insideBars.leading)")

    if videoSize.width > 0 && videoSize.height > 0 {
      let sumViewportSize = CGSize(width: self.viewportMargins.totalWidth + self.videoSize.width,
                                   height: self.viewportMargins.totalHeight + self.videoSize.height)
      assert(((sumViewportSize.width == 0 || sumViewportSize.width == 0) &&
              (viewportSize.width == 0 || viewportSize.height == 0)) ||
             ((sumViewportSize.width == viewportSize.width) && (sumViewportSize.height == viewportSize.height)),
             "videoSize \(self.videoSize) + margins \(self.viewportMargins) → sum: \(sumViewportSize) ≠ viewportSize \(viewportSize)")

      let sumWindowSize = CGSize(width: sumViewportSize.width + outsideBars.totalWidth,
                                 height: sumViewportSize.height + outsideBars.totalHeight + topMarginHeight)
      assert(sumWindowSize.width == windowFrame.width && sumWindowSize.height == windowFrame.height,
             "windowSize sum \(sumWindowSize) ≠ windowFrame.size \(windowFrame.size)")
    }
  }
#endif

  /// Recalculates the layout for the current player window by attempting to scale its video proportionately to the given width.
  /// (Only the desired width is required. The video height will be calculated from the width and the video's known aspect ratio).
  func scalingVideo(toWidth desiredVideoWidth: CGFloat,
                    screenID: String? = nil,
                    screenFit desiredScreenFit: ScreenFit? = nil,
                    lockViewportToVideoSize: Bool? = nil,
                    mode: PlayerWindowMode? = nil) -> PWinGeometry {

    let mode = mode ?? self.mode

    if mode == .musicMode {
      /// Separate logic for music mode window.
      /// The MiniPlayerWindow's width must be between `MiniPlayerMinWidth` and `Preference.musicModeMaxWidth`.
      /// It is composed of up to 3 vertical sections:
      /// 1. `viewportView`: Visible if `isViewportShown` is true. Scales with the aspect ratio of its video.
      /// 2. `musicModeControlBarView`: Visible always. Fixed height.
      /// 3. `playlistWrapperView`: Visible if `playlistShown` is true. Height is user resizable, and must be >= `PlaylistMinHeight`.
      /// Must also ensure that window stays within the bounds of the screen it is in. Almost all of the time the window  will be
      /// height-bounded instead of width-bounded.
      let newScreenID = screenID ?? self.screenID
      let containerFrame: NSRect = GeoUtil.getContainerFrame(forScreenID: newScreenID, screenFit: .stayInside)!

      // Constrain desired width within min and max allowed, then recalculate height from new value
      let maxWindowWidth: CGFloat = min(containerFrame.width, CGFloat(Preference.float(for: .musicModeMaxWidth)))
      var newWindowWidth = desiredVideoWidth.clamped(to: Constants.MusicMode.minWindowWidth...maxWindowWidth)

      // Window height should not change. Only video size should be scaled
      var newVideoHeight: CGFloat = 0  // will stay 0 if !isViewportShown
      if isViewportShown {
        let videoAspect = videoViewAspect
        // Need to calculate height from with to keep rounding consistent with PwinGeometry.forMusicMode()
        newVideoHeight = (newWindowWidth / videoAspect).rounded()

        let maxVideoHeight: CGFloat
        if isMusicModePlaylistShown {
          // If playlist is visible, keep the window height fixed.
          // The video will only be able to expand until the playlist is at its min height
          let desiredWindowHeight = min(containerFrame.height, windowFrame.height)
          maxVideoHeight = desiredWindowHeight - Constants.MusicMode.oscHeight - Constants.MusicMode.minPlaylistHeight
        } else {
          // If playlist not visible, window height can grow up to the size of the screen
          maxVideoHeight = containerFrame.height - Constants.MusicMode.oscHeight
        }

        /// Due to rounding errors and the fact that both `videoHeight` & `playlistHeight` are calculated
        /// (kind of backed into a corner with this one. Oops...) need to make sure that the calculation of
        /// `videoHeight` from `window.frame.width` & video aspect will not result in 1 too many pixels.
        /// This only appears to show up when scaling video to fill the screen & playlist is shown.
        /// Don't want to just distort the video for even 1 pixel to make it fit, as that will cause a
        /// validation error in various sanity checks.
        var trialHeight: CGFloat = newVideoHeight + 1 // add 1 initially because we subtract it below. Try to equal max at first.
        while (newVideoHeight > maxVideoHeight) || (newWindowWidth > maxWindowWidth) {
          trialHeight -= 1
          newWindowWidth = (trialHeight * videoAspect).rounded()
          newVideoHeight = (newWindowWidth / videoAspect).rounded()
        }
      }

      var newWindowHeight: CGFloat
      if isMusicModePlaylistShown {
        newWindowHeight = windowFrame.height
      } else {
        newWindowHeight = newVideoHeight + Constants.MusicMode.oscHeight
      }

      newWindowHeight = min(containerFrame.height, windowFrame.height)

      // Determine which X direction to scale towards by checking which side of the screen it's closest to
      var newOriginX = windowFrame.origin.x
      let distanceToLeadingSideOfScreen = abs(abs(windowFrame.minX) - abs(containerFrame.minX))
      let distanceToTrailingSideOfScreen = abs(abs(windowFrame.maxX) - abs(containerFrame.maxX))
      if distanceToTrailingSideOfScreen < distanceToLeadingSideOfScreen {
        // Closer to trailing side. Keep trailing side fixed by adjusting the window origin by the width changed
        let widthChange = windowFrame.width - newWindowWidth
        newOriginX += widthChange
      }
      // else (closer to leading side): keep leading side fixed

      let newWindowOrigin = NSPoint(x: newOriginX, y: windowFrame.origin.y)
      let newWindowSize = NSSize(width: newWindowWidth, height: newWindowHeight)

      var outputWindowFrame = NSRect(origin: newWindowOrigin, size: newWindowSize)
      if ScreenFit.musicMode.shouldMoveWindowToKeepInContainer {
        outputWindowFrame = outputWindowFrame.constrainOrigin(in: containerFrame)
      }

      let outputGeo = cloneMusicMode(windowFrame: outputWindowFrame)
      assert(isViewportShown == outputGeo.isViewportShown,
             "Scaling musicMode video: isViewportShown mismatch: \(isViewportShown.yesno) → \(outputGeo.isViewportShown.yesno)")
      assert(isMusicModePlaylistShown == outputGeo.isMusicModePlaylistShown,
             "Scaling musicMode video: playlistShown mismatch: \(isMusicModePlaylistShown.yesno) → \(outputGeo.isMusicModePlaylistShown.yesno)")

      log.verbose("[geo] Scaled video (MusicMode): desiredWidth=\(desiredVideoWidth) maxWidth=\(maxWindowWidth) isViewportShown=\(isViewportShown.yn) playlistShown=\(isMusicModePlaylistShown.yn) newWndWidth=\(newWindowWidth) newWndSize=\(outputWindowFrame.size) → \(outputGeo)")
      return outputGeo
    }  // end music mode logic

    let lockViewportToVideoSize = lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize) || mode.alwaysLockViewportToVideoSize
    log.trace("[geo] ScaleVideo start, desiredVideoWidth: \(desiredVideoWidth), videoViewAspect: \(videoViewAspect), lockViewportToVideoSize: \(lockViewportToVideoSize)")

    let outputScreenFit = screenFit.changeDesiredFit(to: desiredScreenFit)

    let minVideoSize = minVideoSize()
    let newWidth = max(minVideoSize.width, desiredVideoWidth)
    /// Enforce `videoView` aspectRatio: Recalculate height using width
    var newVideoSize = NSSize(width: newWidth, height: round(newWidth / videoViewAspect))

    let containerFrame: NSRect? = GeoUtil.getContainerFrame(forScreenID: screenID ?? self.screenID, screenFit: outputScreenFit)
    if let containerFrame {
      // Scale down to fit in bounds of container
      if newVideoSize.width > containerFrame.width {
        newVideoSize = NSSize(width: containerFrame.width, height: round(containerFrame.width / videoViewAspect))
      }

      if newVideoSize.height > containerFrame.height {
        newVideoSize = NSSize(width: round(containerFrame.height * videoViewAspect), height: containerFrame.height)
      }
    }

    let minViewportMargins = GeoUtil.minViewportMargins(forMode: mode)
    let newViewportSize: NSSize
    if lockViewportToVideoSize {
      /// Use `videoSize` for `desiredViewportSize`:
      newViewportSize = NSSize(width: newVideoSize.width + minViewportMargins.totalWidth,
                               height: newVideoSize.height + minViewportMargins.totalHeight)
    } else {
      // Scale existing viewport
      let scaleRatio = newVideoSize.width / videoSize.width
      let viewportSizeWithoutMinMargins = NSSize(width: viewportSize.width - minViewportMargins.totalWidth,
                                                 height: viewportSize.height - minViewportMargins.totalHeight)
      let scaledViewportWithoutMargins = viewportSizeWithoutMinMargins * scaleRatio
      newViewportSize = NSSize(width: scaledViewportWithoutMargins.width + minViewportMargins.totalWidth,
                               height: scaledViewportWithoutMargins.height + minViewportMargins.totalHeight)
    }

    return scalingViewport(to: newViewportSize, screenID: screenID, screenFit: screenFit, mode: mode)
  }

  /// Adjusts the window frame (& possibly its subviews) as needed to accomodate the given `VideoGeometry`.
  ///
  /// - Param `newVidGeo` will be used as the `video` field in the returned `PWinGeometry`S.
  /// - The viewport will only change size when `lockViewportToVideoSize` is enabled.
  func resizeMinimally(forNewVideoGeo newVidGeo: VideoGeometry) -> PWinGeometry {
    let targetViewportSize: NSSize
    let log = newVidGeo.log

    if Preference.bool(for: .lockViewportToVideoSize) {
      // Try to avoid shrinking the window too much if the aspect changes dramatically.
      let containerSize = NSScreen.getScreenOrDefault(screenID: screenID).visibleFrame.size
      let useRatioW = (viewportSize.width / containerSize.width).clamped(to: 0...1)
      let useRatioH = (viewportSize.height / containerSize.height).clamped(to: 0...1)
      let useRatioMax = max(useRatioW, useRatioH)

      targetViewportSize = (containerSize * useRatioMax).rounded()
    } else {
      // Try to keep current viewportSize
      targetViewportSize = viewportSize
    }

    log.verbose("[geo] Minimal resize: applying desiredViewportSize \(targetViewportSize)")
    return clone(video: newVidGeo).scalingViewport(to: targetViewportSize)
  }

  // MARK: - Naive Resize Functions
  // These do not call scalingViewport, and can produce an invalid PWinGeometry if given an invalid one.

  /// Resizes the window appropriately to add or subtract from outside bar sizes (a bar in its "closed" state == 0).
  /// Adjusts window origin to prevent the viewport from moving (but clamps each dimension's size to the container/screen, if any).
  ///
  /// If `pinWidthOrHeightIfAtMax` is `true` and the window's width or height, independently, is at max, that dimension will stay at max.
  /// This way the window will seem to "stick" to the screen edges when already maximized.
  /// But if the window is already smaller, the window will be allowed to shrink or grow normally.
  /// This should be more intuitive to the user which is expecting "near" full screen behavior when maximized.
  func withResizedOutsideBars(top: CGFloat? = nil, trailing: CGFloat? = nil,
                              bottom: CGFloat? = nil, leading: CGFloat? = nil,
                              pinWidthOrHeightIfAtMax: Bool) -> PWinGeometry {
    assert((top ?? 0) >= 0)
    assert((trailing ?? 0) >= 0)
    assert((bottom ?? 0) >= 0)
    assert((trailing ?? 0) >= 0)

    let newOutsideBars = MarginQuad(top: top ?? outsideBars.top,
                                    trailing: trailing ?? outsideBars.trailing,
                                    bottom: bottom ?? outsideBars.bottom,
                                    leading: leading ?? outsideBars.leading)

    guard !mode.isFullScreen else {
      let outputGeo = clone(outsideBars: newOutsideBars)
      log.verbose("[ResizeBars] Mode is FS (\(mode)): Returning same windowFrame but with closed bars")
      return outputGeo
    }

    let ΔTop = (top ?? self.outsideBars.top) - self.outsideBars.top
    let ΔTrailing = (trailing ?? self.outsideBars.trailing) - self.outsideBars.trailing
    let ΔBottom = (bottom ?? self.outsideBars.bottom) - self.outsideBars.bottom
    let ΔLeading = (leading ?? self.outsideBars.leading) - self.outsideBars.leading

    let ΔX = -ΔLeading
    let ΔY = -ΔBottom

    let ΔW = ΔLeading + ΔTrailing
    let ΔH = ΔTop + ΔBottom

    var newX = windowFrame.origin.x + ΔX
    var newY = windowFrame.origin.y + ΔY
    var newWindowWidth = windowFrame.width + ΔW
    var newWindowHeight = windowFrame.height + ΔH

    let outputWindowFrame: CGRect
    // Special logic if output has reached out the size of the screen.
    // Do not allow it to get bigger than the screen.
    if screenFit.shouldMoveWindowToKeepInContainer, let screenFrame = getContainerFrame() {
      if (newWindowWidth > screenFrame.width) || (pinWidthOrHeightIfAtMax && (abs(screenFrame.width - windowFrame.width) <= 1)) {
        // Window will be too wide, or window is already at max width & we want to stay pinned to that width:
        newWindowWidth = screenFrame.width
        newX = screenFrame.origin.x  // Move to fit in screen

        // Corner case if closing an outside bar while lockViewportToVideoSize is enabled: need to scale up other dimension
        if ΔW < 0, Preference.bool(for: .lockViewportToVideoSize) {
          let heightAdjustment = (abs(ΔW) * video.videoAspectDisplay).rounded()
          newWindowHeight += heightAdjustment
          newY -= (heightAdjustment * 0.5).rounded()
        }
      } else if pinWidthOrHeightIfAtMax {
        if abs(screenFrame.minX - windowFrame.minX) <= 1 {
          // Was aligned to screen's LEADING edge
          newX = screenFrame.minX
        } else if abs(screenFrame.maxX - windowFrame.maxX) <= 1 {
          // Was aligned to screen's TRAILING edge
          newX = screenFrame.maxX - newWindowWidth
        }
      }

      if (newWindowHeight > screenFrame.height) || (pinWidthOrHeightIfAtMax && (abs(screenFrame.height - windowFrame.height) <= 1)) {
        // Window will be too tall, or window is already at max height & we want to stay pinned to that height:
        newWindowHeight = screenFrame.height
        newY = screenFrame.origin.y  // Move to fit in screen

        if ΔH < 0, Preference.bool(for: .lockViewportToVideoSize) {
          let widthAdjustment = (abs(ΔH) / video.videoAspectDisplay).rounded()
          newWindowWidth += widthAdjustment
          newX -= (widthAdjustment * 0.5).rounded()
        }
      } else if pinWidthOrHeightIfAtMax {
        if abs(screenFrame.minY - windowFrame.minY) <= 1 {
          // Was aligned to screen's BOTTOM edge
          newY = screenFrame.minY
        } else if abs(screenFrame.maxY - windowFrame.maxY) <= 1 {
          // Was aligned to screen's TOP edge
          newY = screenFrame.maxY - newWindowHeight
        }
      }

      let unconstrainedWindowFrame = CGRect(x: newX, y: newY, width: newWindowWidth, height: newWindowHeight)
      outputWindowFrame = unconstrainedWindowFrame.constrainOrigin(in: screenFrame)
    } else {
      outputWindowFrame = CGRect(x: newX, y: newY, width: newWindowWidth, height: newWindowHeight)
    }
    // If new windowFrame is slightly off screen, so fall back to current screenID.
    // Also fall back to default screen if current screenID is defunct:
    let newScreenID = NSScreen.getOwnerOrDefaultScreenID(forViewRect: outputWindowFrame, fallbackScreenID: screenID)

    let outputGeo = clone(windowFrame: outputWindowFrame, screenID: newScreenID, outsideBars: newOutsideBars)
    log.verbose("[ResizeBars] ΔW=\(ΔW.logStr) ΔH=\(ΔH.logStr) pinMax=\(pinWidthOrHeightIfAtMax.yn) moveToKeepInScreen:\(screenFit.shouldMoveWindowToKeepInContainer.yesno)")
    return outputGeo
  }

  /// Like `withResizedOutsideBars`, but can resize the inside bars at the same time.
  func withResizedBars(screenFit: ScreenFit? = nil, mode: PlayerWindowMode? = nil,
                       outsideTop: CGFloat? = nil, outsideTrailing: CGFloat? = nil,
                       outsideBottom: CGFloat? = nil, outsideLeading: CGFloat? = nil,
                       insideTop: CGFloat? = nil, insideTrailing: CGFloat? = nil,
                       insideBottom: CGFloat? = nil, insideLeading: CGFloat? = nil,
                       video: VideoGeometry? = nil,
                       pinWidthOrHeightIfAtMax: Bool = false) -> PWinGeometry {

    // Inside bars
    let newInsideBars = MarginQuad(top: insideTop ?? insideBars.top,
                                   trailing: insideTrailing ?? insideBars.trailing,
                                   bottom: insideBottom ?? insideBars.bottom,
                                   leading: insideLeading ?? insideBars.leading)
    let resizedInsideBarsGeo = clone(screenFit: screenFit, mode: mode, insideBars: newInsideBars, video: video)

    // Outside bars
    return resizedInsideBarsGeo.withResizedOutsideBars(top: outsideTop,
                                                       trailing: outsideTrailing,
                                                       bottom: outsideBottom,
                                                       leading: outsideLeading,
                                                       pinWidthOrHeightIfAtMax: pinWidthOrHeightIfAtMax)
  }

  /// After changing to a new `PWinGeometry` with a different aspect ratio, we usually want to keep the
  /// window at "roughly" the same size as before. This can be surprisingly difficult to do if
  /// `lockViewportToVideoSize` is enabled, because the window may be forced to change from horizontal to vertical.
  /// We also want to avoid shrinking the viewport to less than its minimum size, which can differ based the current
  /// `mode`. This method uses a heuristic which does a decent job at meeting these goals.
  func scalingViewport(toSimilarSizeAs referenceGeo: PWinGeometry) -> PWinGeometry {
    var targetViewportSize: CGSize
    if Preference.bool(for: .lockViewportToVideoSize) {
      // Try to avoid shrinking the window too much if the aspect changes dramatically.
      let containerSize = NSScreen.getScreenOrDefault(screenID: referenceGeo.screenID).visibleFrame.size
      let useRatioW = (referenceGeo.viewportSize.width / containerSize.width).clamped(to: 0...1)
      let useRatioH = (referenceGeo.viewportSize.height / containerSize.height).clamped(to: 0...1)
      let useRatioMax = max(useRatioW, useRatioH)

      targetViewportSize = containerSize * useRatioMax  // not rounded. Need to round below.
    } else {
      // Try to keep current viewportSize
      targetViewportSize = referenceGeo.viewportSize
    }

    let minViewportSize = minViewportSize()
    while (targetViewportSize.width < minViewportSize.width) || (targetViewportSize.height < minViewportSize.height) {
      targetViewportSize = targetViewportSize * 2.0
    }
    targetViewportSize = targetViewportSize.rounded()

    return scalingViewport(to: targetViewportSize)
  }

  /// Calculate the window frame from a parsed struct of mpv's `geometry` option.
  func apply(mpvGeometry: MPVGeometryDef, desiredWindowSize: NSSize) -> PWinGeometry {
    guard let screenFrame: NSRect = getContainerFrame() else {
      log.error("Cannot apply mpv geometry: no container frame found (screenFit: \(screenFit))")
      return self
    }
    let maxWindowSize = screenFrame.size
    let minWindowSize = minWindowSize(mode: .windowedNormal)

    var newWindowSize = desiredWindowSize
    var isWidthSet = false
    var isHeightSet = false
    var isXSet = false
    var isYSet = false

    if let strw = mpvGeometry.w, let wInt = Int(strw), wInt > 0 {
      var w = CGFloat(wInt)
      if mpvGeometry.wIsPercentage {
        w = w * 0.01 * Double(maxWindowSize.width)
      }
      newWindowSize.width = max(minWindowSize.width, w)
      isWidthSet = true
    }

    if let strh = mpvGeometry.h, let hInt = Int(strh), hInt > 0 {
      var h = CGFloat(hInt)
      if mpvGeometry.hIsPercentage {
        h = h * 0.01 * Double(maxWindowSize.height)
      }
      newWindowSize.height = max(minWindowSize.height, h)
      isHeightSet = true
    }

    // 1. If both width & height are set, video will scale to fit inside it, but there may be empty margins.
    // 2. If only width or height is set, but not both: derive the other from the aspect ratio.
    // 3. Otherwise default to desiredVideoSize.
    if isWidthSet && !isHeightSet {
      // Calculate height based on width and aspect
      let newViewportWidth = newWindowSize.width - outsideBars.totalWidth
      let newViewportHeight = round(newViewportWidth / videoViewAspect)
      newWindowSize.height = newViewportHeight + (outsideBars.totalHeight + topMarginHeight)

      var mustRecomputeWidth = false
      if newWindowSize.height > maxWindowSize.height {
        // Shrink if exceeded max height
        newWindowSize.height = maxWindowSize.height
        mustRecomputeWidth = true
      } else if newWindowSize.height < minWindowSize.height {
        newWindowSize.height = minWindowSize.height
        mustRecomputeWidth = true
      }
      if mustRecomputeWidth {
        // Recalculate width based on height and aspect
        let newViewportHeight = newWindowSize.height - (outsideBars.totalHeight + topMarginHeight)
        let newViewportWidth = round(newViewportHeight * videoViewAspect)
        newWindowSize.width = newViewportWidth + outsideBars.totalWidth
      }
    } else if !isWidthSet && isHeightSet {
      // Calculate width based on height and aspect
      let newViewportHeight = newWindowSize.height - (outsideBars.totalHeight + topMarginHeight)
      let newViewportWidth = round(newViewportHeight * videoViewAspect)
      newWindowSize.width = newViewportWidth + outsideBars.totalWidth

      var mustRecomputeHeight = false
      if newWindowSize.width > maxWindowSize.width {
        // Shrink if exceeded max width
        newWindowSize.width = maxWindowSize.width
        mustRecomputeHeight = true
      } else if newWindowSize.width < minWindowSize.width {
        newWindowSize.width = minWindowSize.width
        mustRecomputeHeight = true
      }
      if mustRecomputeHeight {
        // Recalculate height based on width and aspect
        let newViewportWidth = newWindowSize.width - outsideBars.totalWidth
        let newViewportHeight = round(newViewportWidth / video.videoAspectDisplay)
        newWindowSize.height = newViewportHeight + (outsideBars.totalHeight + topMarginHeight)
      }
    }

    var newOrigin = screenFrame.origin
    // x
    if let strx = mpvGeometry.x, let xInt = Int(strx), let xSign = mpvGeometry.xSign {
      let unusedScreenWidth = max(0, screenFrame.width - newWindowSize.width)
      var xOffset = CGFloat(xInt)
      if mpvGeometry.xIsPercentage {
        xOffset = xOffset * 0.01 * Double(screenFrame.width)
      }
      // Reduce/eliminate offset if not enough space on screen
      xOffset = min(unusedScreenWidth, xOffset)
      // If xSign == "-", interpret as offset of right side of window from right side of screen
      if xSign == "-" {  // Offset from RIGHT
        newOrigin.x += (screenFrame.width - newWindowSize.width)
        newOrigin.x -= xOffset
      } else {  // Offset from LEFT
        newOrigin.x += xOffset
      }
      isXSet = true
    }

    // y
    if let stry = mpvGeometry.y, let yInt = Int(stry), let ySign = mpvGeometry.ySign {
      let unusedScreenHeight = max(0, screenFrame.height - newWindowSize.height)
      var yOffset = CGFloat(yInt)
      if mpvGeometry.yIsPercentage {
        yOffset = yOffset * 0.01 * Double(screenFrame.height)
      }
      // Reduce/eliminate offset if not enough space on screen
      yOffset = min(unusedScreenHeight, yOffset)

      if ySign == "-" {  // Offset from BOTTOM
        newOrigin.y += yOffset
      } else {  // Offset from TOP
        newOrigin.y += (screenFrame.height - newWindowSize.height)
        newOrigin.y -= yOffset
      }
      isYSet = true
    }

    // If X or Y are not set, just adjust the previous values according to the change in window width or height, respectively
    let adjustedOrigin = adjustWindowOrigin(forNewWindowSize: newWindowSize)
    if !isXSet {
      newOrigin.x = adjustedOrigin.x
    }
    if !isYSet {
      newOrigin.y = adjustedOrigin.y
    }

    let outputWindowFrame = NSRect(x: newOrigin.x.rounded(), y: newOrigin.y.rounded(), width: newWindowSize.width.rounded(), height: newWindowSize.height.rounded())
    log.debug("Calculated windowFrame from mpv geometry: \(outputWindowFrame)")
    return self.clone(windowFrame: outputWindowFrame)
  }

  // MARK: - Interactive mode

  static func buildInteractiveModeWindow(windowFrame: NSRect, screenID: String, video: VideoGeometry) -> PWinGeometry {
    let outsideBars = MarginQuad(top: Constants.InteractiveMode.outsideTopBarHeight, trailing: 0,
                                 bottom: Constants.InteractiveMode.outsideBottomBarHeight, leading: 0)
    return PWinGeometry(windowFrame: windowFrame, screenID: screenID, screenFit: .stayInside,
                        mode: .windowedInteractive, topMarginHeight: 0,
                        outsideBars: outsideBars,
                        insideBars: MarginQuad.zero,
                        video: video, videoZoom: 1.0)
  }

  /// Transition windowed mode geometry to Interactive Mode geometry.
  /// Note that this is not a direct conversion; it will modify the viewport size.
  func toInteractiveMode() -> PWinGeometry {
    assert(screenFit != .legacyFullScreen && screenFit != .nativeFullScreen)
    assert(mode == .windowedNormal)
    /// Close the sidebars. Top and bottom bars are resized for interactive mode controls.
    let resizedGeo = withResizedBars(mode: .windowedInteractive,
                                     outsideTop: Constants.InteractiveMode.outsideTopBarHeight,
                                     outsideTrailing: 0,
                                     outsideBottom: Constants.InteractiveMode.outsideBottomBarHeight,
                                     outsideLeading: 0,
                                     insideTop: 0, insideTrailing: 0,
                                     insideBottom: 0, insideLeading: 0,
                                     pinWidthOrHeightIfAtMax: true)
    return resizedGeo.refitted()
  }

  /// Transition `windowedInteractive` mode geometry to `windowed` geometry.
  /// Note that this is not a direct conversion; it will modify the view sizes.
  func fromWindowedInteractiveMode() -> PWinGeometry {
    assert(screenFit != .legacyFullScreen && screenFit != .nativeFullScreen)
    assert(mode == .windowedInteractive)
    /// Close the sidebars. Top and bottom bars are resized for interactive mode controls.
    let resizedGeo = withResizedBars(mode: .windowedNormal,
                                     outsideTop: 0, outsideTrailing: 0,
                                     outsideBottom: 0, outsideLeading: 0,
                                     insideTop: 0, insideTrailing: 0,
                                     insideBottom: 0, insideLeading: 0,
                                     pinWidthOrHeightIfAtMax: true)
    return resizedGeo
  }

  // MARK: - VideoGeometry changes

  /// Here, `videoSizeUnscaled` and `cropBox` must be the same scale, which may be different than `self.videoSize`.
  /// The cropBox is the section of the video rect which remains after the crop. Its origin is the lower left of the video.
  /// This func assumes that the currently displayed video (`videoSize`) is uncropped. Returns a new geometry which expanding the margins
  /// while collapsing the viewable video down to the cropped portion. The window size does not change.
  func cropVideo(using newVidGeo: VideoGeometry) -> PWinGeometry {
    // First scale the cropBox to the current window scale
    let scaleRatio = videoSize.width / newVidGeo.videoSizeRaw.width
    guard let cropRect = newVidGeo.cropRect else {
      log.debug("[geo] No crop provided; returning self")
      return self
    }

    /// We have `croppedVideoViewSize` which is most consistent with `PWinGeometry` constructor.
    /// Now need to find x & y offsets to determine how much margin to add to each of the 4 sides.
    /// Need to round each value to integers to satisfy various sanity checks.
    var cropRectScaledToWindow = NSRect(x: (cropRect.origin.x * scaleRatio).rounded(),
                                        y: (cropRect.origin.y * scaleRatio).rounded(),
                                        width: (cropRect.width * scaleRatio).rounded(),
                                        height: (cropRect.height * scaleRatio).rounded())

    // This will use .mpvAspect - need to be consistent with rounding!
    let croppedVideoSize = newVidGeo.videoSizeC
    let croppedVideoViewSize = GeoUtil.computeVideoViewSize(forVideoDisplaySize: croppedVideoSize,
                                                            toFillIn: cropRectScaledToWindow.size,
                                                            minViewportMargins: .zero,
                                                            videoZoom: 1.0,
                                                            mode: mode)


    /// Note that size of `cropRectScaledToWindow` can differ from `croppedVideoViewSize` due to being rounded
    /// less. This can cause a validation error in the sanity checks.
    /// Account for this by computing the difference between the values and redistributing it.
    let excessWidth = croppedVideoViewSize.width - cropRectScaledToWindow.width
    let excessHeight = croppedVideoViewSize.height - cropRectScaledToWindow.height
    // These are the final numbers: round them:
    cropRectScaledToWindow = NSRect(x: round(cropRectScaledToWindow.origin.x + (excessWidth * 0.5)),
                                    y: round(cropRectScaledToWindow.origin.y + (excessHeight * 0.5)),
                                    width: round(cropRectScaledToWindow.width + excessWidth),
                                    height: round(cropRectScaledToWindow.height + excessHeight))

    if cropRectScaledToWindow.origin.x > videoSize.width || cropRectScaledToWindow.origin.y > videoSize.height {
      log.error("[geo] Cannot crop video: the cropBox is completely outside the video! CropBoxScaled: \(cropRectScaledToWindow), videoSize: \(videoSize)")
      return self
    }

    // Collapse the viewable video without changing the window size. Do this by expanding the margins
    let bottomHeightOutsideCropBox = cropRectScaledToWindow.origin.y
    let topHeightOutsideCropBox = max(0, videoSize.height - cropRectScaledToWindow.height - bottomHeightOutsideCropBox)    // cannot be < 0
    let leadingWidthOutsideCropBox = cropRectScaledToWindow.origin.x
    let trailingWidthOutsideCropBox = max(0, videoSize.width - cropRectScaledToWindow.width - leadingWidthOutsideCropBox)  // cannot be < 0

    let newViewportMargins = MarginQuad(top: viewportMargins.top + topHeightOutsideCropBox,
                                        trailing: viewportMargins.trailing + trailingWidthOutsideCropBox,
                                        bottom: viewportMargins.bottom + bottomHeightOutsideCropBox,
                                        leading: viewportMargins.leading + leadingWidthOutsideCropBox)

    log.debug("[geo] Cropping from cropRect \(cropRect) x videoScale (\(scaleRatio)), windowSize=\(windowFrame.size), → newVideoSize:\(cropRectScaledToWindow.size), newVideoAspect:\(croppedVideoSize.aspect), newViewportMargins:\(newViewportMargins)")
    let outputScreenFit = screenFit.changeDesiredFit()
    log.debug("[geo] Cropped PWinGeometry using: \(newVidGeo), screenID: \(screenID), screenFit: \(outputScreenFit)")
    return self.clone(screenFit: outputScreenFit, viewportMargins: newViewportMargins, video: newVidGeo)
  }

  // MARK: - Music Mode

  /**
   Factory method to create a `PWinGeometry` instance in music mode.

   Because the music mode window reuses the existing player window, it:
   * Uses the viewport to display video or album art, but can be turned off, in which case it is given a height of zero. The viewport has 0 margins on all sides when in music mode.
   * Uses the outside bottom bar for:
   * 1. Either current media info, or OSC on hover. This is always displayed in music mode and has constant height.
   * 2. Playlist if shown. Playlist has 0 height if hidden, otherwise is bounded by `minPlaylistHeight` and remaining height on screen.
   *  Never has any inside bars, outside sidebars or top bar (the views exist but are reduced to zero area).

   This function will always return a `PWinGeometry` object which has `mode: .musicMode`.
   */
  static func forMusicMode(windowFrame: NSRect, screenID: String, video: VideoGeometry,
                           isViewportShown: Bool, playlistShown: Bool) -> PWinGeometry {
    let log = video.log
    var windowFrame = NSRect(origin: windowFrame.origin, size:
                              CGSize(width: windowFrame.width.rounded(), height: windowFrame.height.rounded()))
    let videoHeight = PWinGeometry.MusicMode.videoHeight(windowFrame: windowFrame, video: video, isViewportShown: isViewportShown)
    var musicModePlaylistHeight = windowFrame.height - videoHeight - Constants.MusicMode.oscHeight

    let extraWidthNeeded = Constants.MusicMode.minWindowWidth - windowFrame.width
    if extraWidthNeeded > 0 {
      log.verbose("MusicModeGeoInit: width too small; adding: \(extraWidthNeeded)")
      windowFrame = NSRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width + extraWidthNeeded, height: windowFrame.height))
    }

    if playlistShown {
      let extraHeightNeeded = Constants.MusicMode.minPlaylistHeight - musicModePlaylistHeight
      if extraHeightNeeded > 0 {
        log.verbose("MusicModeGeoInit: height too small for playlist; adding: \(extraHeightNeeded)")
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    }
    assert(windowFrame.origin.x.isInteger && windowFrame.origin.y.isInteger && windowFrame.width.isInteger && windowFrame.height.isInteger,
           "All windowFrame dimensions must be integers: \(windowFrame)")

    musicModePlaylistHeight = windowFrame.height - videoHeight - Constants.MusicMode.oscHeight  // recalculate this var
    let winGeo = PWinGeometry(windowFrame: windowFrame,
                              screenID: screenID,
                              screenFit: .stayInside,
                              mode: .musicMode,
                              topMarginHeight: 0,
                              outsideBars: MarginQuad(bottom: Constants.MusicMode.oscHeight + musicModePlaylistHeight),
                              insideBars: MarginQuad.zero,
                              video: video,
                              videoZoom: 1.0)

    let isValidHeight = playlistShown ? (musicModePlaylistHeight >= Constants.MusicMode.minPlaylistHeight) : (musicModePlaylistHeight == 0)
    if !isValidHeight {
      if !playlistShown {
        log.warn("[geo] MusicMode: playlistHeight (\(musicModePlaylistHeight)) is invalid (will try to correct); playlistShown=\(playlistShown.yn) minPlaylistH=\(Constants.MusicMode.minPlaylistHeight)")
        let heightDiff = musicModePlaylistHeight
        let outputWindowFrame = NSRect(origin: NSPoint(x: windowFrame.origin.x, y: windowFrame.origin.y + heightDiff), size: NSSize(width: windowFrame.width, height: windowFrame.height - heightDiff))
        return forMusicMode(windowFrame: outputWindowFrame, screenID: screenID, video: video,
                            isViewportShown: isViewportShown, playlistShown: playlistShown)
      }
    } else {
      assert(isViewportShown == winGeo.isViewportShown,
             "Expected isViewportShown to match: \(isViewportShown.yesno) → \(winGeo.isViewportShown.yesno)")
      assert(playlistShown == winGeo.isMusicModePlaylistShown,
             "Expected playlistShown to match: \(playlistShown.yesno) → \(winGeo.isMusicModePlaylistShown.yesno)")
    }
    return winGeo
  }

  func cloneMusicMode(windowFrame: NSRect? = nil, screenID: String? = nil, video: VideoGeometry? = nil,
                      isViewportShown: Bool? = nil, playlistShown: Bool? = nil) -> PWinGeometry {
    guard mode == .musicMode else {
      log.error("Cannot call PWinGeometry.cloneMusicMode when mode ≠ music mode: \(self)")
      assert(false, "Cannot call PWinGeometry.cloneMusicMode when mode ≠ music mode: \(self)")  // fail fast when debugging
      return self
    }
    let showVideo = isViewportShown ?? self.isViewportShown
    let showPlaylist = playlistShown ?? self.isMusicModePlaylistShown
    log.trace("Cloning musicMode geo: \(self) → showVideo=\(showVideo.yn) showPlaylist=\(showPlaylist.yn)")
    return PWinGeometry.forMusicMode(windowFrame: windowFrame ?? self.windowFrame,
                                     screenID: screenID ?? self.screenID,
                                     video: video ?? self.video,
                                     isViewportShown: showVideo,
                                     playlistShown: showPlaylist)
  }

  /// Music mode only!
  func withViewportVisible(_ visible: Bool) -> PWinGeometry {
    guard mode == .musicMode else {
      log.error("Cannot call PWinGeometry.withViewportVisible when mode ≠ music mode: \(self)")
      assert(false, "Cannot call PWinGeometry.withViewportVisible when mode ≠ music mode: \(self)")  // fail fast when debugging
      return self
    }
    guard self.isViewportShown != visible else { return self }

    var outputWindowFrame = windowFrame
    if visible {
      outputWindowFrame.size.height += videoHeightWhenVisible
    } else {
      // If playlist is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      outputWindowFrame.size.height = max(Constants.MusicMode.oscHeight, outputWindowFrame.size.height - videoHeightWhenVisible)
    }
    return cloneMusicMode(windowFrame: outputWindowFrame, isViewportShown: visible)
  }

  func withPlaylistShown(_ shown: Bool) -> PWinGeometry {
    guard shown != self.isMusicModePlaylistShown else { return self }
    guard mode == .musicMode else {
      log.error("Cannot toggle playlist visibility: not in music mode: \(self)")
      return self
    }

    let inputPlistHeight = musicModePlaylistHeight
    let showPlaylist = !isMusicModePlaylistShown
    log.verbose("Toggling playlist visibility: \((!showPlaylist).yn) → \(showPlaylist.yn)")

    let outputWindowHeight: CGFloat
    if showPlaylist {
      // Try to show playlist using stored height
      let savedPlistHeight = CGFloat(Preference.integer(for: .musicModePlaylistHeight))
      // The window may be in the middle of a previous toggle, so we can't just assume window's current frame
      // represents a state where the playlist is fully shown or fully hidden. Instead, start by computing the height
      // we want to set, and then figure out the changes needed to the window's existing frame.
      let targetHeightToAdd = savedPlistHeight - inputPlistHeight
      // Fill up screen if needed
      outputWindowHeight = windowFrame.height + targetHeightToAdd
    } else {
      // Hiding playlist
      let playlistHeightRounded = Int(round(inputPlistHeight))
      if playlistHeightRounded >= Int(Constants.MusicMode.minPlaylistHeight) {
        log.trace("Saving prev playlist height: \(playlistHeightRounded)")
        Preference.set(playlistHeightRounded, for: .musicModePlaylistHeight)
      }

      // If video is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      outputWindowHeight = max(Constants.MusicMode.oscHeight, windowFrame.height - inputPlistHeight)
    }

    // adjust window origin to expand downwards
    let heightChange = outputWindowHeight - windowFrame.height
    let outputWindowFrame = NSRect(x: windowFrame.origin.x,
                                   y: windowFrame.origin.y - heightChange,
                                   width: windowFrame.width, height: outputWindowHeight)

    // Constrain window so that it doesn't expand below bottom of screen, or fall offscreen
    let unconstrainedOutputGeo = cloneMusicMode(windowFrame: outputWindowFrame, playlistShown: showPlaylist)
    let outputGeo = unconstrainedOutputGeo.scalingVideo(toWidth: outputWindowFrame.width)
    return outputGeo
  }

  struct MusicMode {
    static func playlistHeight(windowFrame: CGRect, video: VideoGeometry, isViewportShown: Bool, playlistShown: Bool) -> CGFloat {
      guard playlistShown else {
        return 0
      }
      let videoHeight = videoHeight(windowFrame: windowFrame, video: video, isViewportShown: isViewportShown)
      return windowFrame.height - videoHeight - Constants.MusicMode.oscHeight
    }

    static func videoHeight(windowFrame: CGRect, video: VideoGeometry, isViewportShown: Bool) -> CGFloat {
      guard isViewportShown else {
        return 0
      }
      let vidHeight = videoHeightWhenVisible(windowFrame: windowFrame, video: video)
      return vidHeight
    }

    static func videoHeightWhenVisible(windowFrame: CGRect, video: VideoGeometry) -> CGFloat {
      // Round down (toward zero) *always* to hopefully reduce inconsistencies due to rounding
      return (windowFrame.width / video.videoAspectDisplay).rounded()
    }

  }  // end struct MusicMode

}
