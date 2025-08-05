//
//  PWinGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 7/11/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Describes how a given player window must fit inside its given screen.
enum ScreenFit: Int {

  case noConstraints = 0

  /// Constrains inside `screen.visibleFrame`. Windowed modes only.
  case stayInside

  /// Constrains and centers inside `screen.visibleFrame`. Windowed modes only.
  case centerInside

  /// Constrains inside `screen.frame`
  case legacyFullScreen

  /// Constrains inside `screen.frameWithoutCameraHousing`. Provided here for completeness, but not used at present.
  case nativeFullScreen

  var isFullScreen: Bool {
    switch self {
    case .legacyFullScreen, .nativeFullScreen:
      return true
    default:
      return false
    }
  }

  var shouldMoveWindowToKeepInContainer: Bool {
    switch self {
    case .legacyFullScreen, .nativeFullScreen:
      return true
    case .stayInside, .centerInside:
      if Preference.bool(for: .enableAdvancedSettings) {
        return Preference.bool(for: .moveWindowIntoVisibleScreenOnResize)
      }
      return true
    default:
      return false
    }
  }
}

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
 •
 ~                               `geo.viewportSize.width`
 ~                                (of `wc.viewportView`)
 ~                             ◄--------------------------►
 ┌────────────────────────────────────────────────────────────────────────────────────────┐`geo.windowFrame`
 │                                            ▲                                           │
 │                                            │`geo.topMarginHeight`                      │
 │                                            ▼ (only nonzero when covering Macbook notch)│
 ├────────────────────────────────────────────────────────────────────────────────────────┤
 │                                          ▲                                             │
 │                                          │`geo.outsideBars.top`                        │
 │                                          ▼  (`wc.topBarView`)                          │
 ├────────────────────────────┬────────────────────────────┬──────────────────────────────┤ ─ ◄--- `geo.insideBars.top == 0`
 │                            │   `viewportMargins.top`    │                              │ ▲
 │                            ├─────┬────────────────┬─────┤                              │ │ `geo.viewportSize.height`
 │◄--------------------------►│ [€] │ `geo.videoSize`│ [¥] │◄----------------------------►│ │  (of `wc.viewportView`)
 │                            │     │(`wc.videoView`)│     │  `geo.outsideBars.trailing`  │ │
 │  `geo.outsideBars.leading` ├─────┴────────────────┴─────┤ (of `wc.trailingSidebarView`)│ │
 │(of `wc.leadingSidebarView`)│  `viewportMargins.bottom`  │                              │ ▼
 ├────────────────────────────┴────────────────────────────┴──────────────────────────────┤ ─ ◄--- `geo.insideBars.bottom == 0`
 │                                      ▲                                                 │
 │                                      │`geo.outsideBars.bottom`                         │  [€] = `viewportMargins.leading`
 │                                      ▼ (of `wc.bottomBarView`)                         │  [¥] = `viewportMargins.trailing`
 └────────────────────────────────────────────────────────────────────────────────────────┘
 */
struct PWinGeometry: Equatable, CustomStringConvertible {
  typealias Transform = (GeometryTransform.Context) -> PWinGeometry?

  // MARK: Stored properties

  let isMiddleTransition: Bool

  // - Screen:
  // The ID of the screen on which this window is displayed
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
  var insideBars: MarginQuad

  let viewportMargins: MarginQuad
  let video: VideoGeometry

  // MARK: Initializers / Factory Methods

  /// Derives `viewportSize` and `videoSize` from `windowFrame`, `viewportMargins` and `videoAspect`.
  init(windowFrame: NSRect, screenID: String, screenFit: ScreenFit,
       mode: PlayerWindowMode, topMarginHeight: CGFloat,
       outsideBars: MarginQuad, insideBars: MarginQuad,
       viewportMargins: MarginQuad? = nil, video: VideoGeometry,
       isMiddleTransition: Bool = false) {

    self.windowFrame = windowFrame
    self.screenID = screenID
    self.screenFit = screenFit
    self.mode = mode
    self.topMarginHeight = topMarginHeight
    self.outsideBars = outsideBars
    self.insideBars = insideBars
    self.video = video
    self.isMiddleTransition = isMiddleTransition

    let viewportSize = GeoUtil.deriveViewportSize(from: windowFrame, topMarginHeight: topMarginHeight, outsideBars: outsideBars)
    assert(viewportSize.width >= 0 && viewportSize.height >= 0, "viewportSize must not be negative! Found: \(viewportSize)")

    let targetVideoAspect = video.videoAspectDisplay
    let videoSize = GeoUtil.computeVideoSize(withAspectRatio: targetVideoAspect, toFillIn: viewportSize,
                                             minViewportMargins: viewportMargins, mode: mode)
    self.videoSize = videoSize

    if let viewportMargins {
      self.viewportMargins = viewportMargins
    } else {
      self.viewportMargins = GeoUtil.computeBestViewportMargins(viewportSize: viewportSize, videoSize: videoSize,
                                                                insideBars: insideBars, mode: mode)
    }
  }

  static func fullScreenWindowFrame(in screen: NSScreen, legacy: Bool) -> NSRect {
    if legacy {
      return screen.frame
    } else {
      return screen.frameWithoutCameraHousing
    }
  }

  /// See also `LayoutState.buildFullScreenGeometry()`.
  static func forFullScreen(in screen: NSScreen, legacy: Bool, mode: PlayerWindowMode,
                            outsideBars: MarginQuad, insideBars: MarginQuad,
                            video: VideoGeometry,
                            allowVideoToOverlapCameraHousing: Bool) -> PWinGeometry {

    let windowFrame = fullScreenWindowFrame(in: screen, legacy: legacy)
    let screenFit: ScreenFit
    let topMarginHeight: CGFloat
    if legacy {
      topMarginHeight = allowVideoToOverlapCameraHousing ? 0 : screen.cameraHousingHeight ?? 0
      screenFit = .legacyFullScreen
    } else {
      topMarginHeight = 0
      screenFit = .nativeFullScreen
    }

    return PWinGeometry(windowFrame: windowFrame, screenID: screen.screenID, screenFit: screenFit, mode: mode,
                        topMarginHeight: topMarginHeight, outsideBars: outsideBars, insideBars: insideBars, video: video)
  }

  func clone(windowFrame: NSRect? = nil, screenID: String? = nil, screenFit: ScreenFit? = nil,
             mode: PlayerWindowMode? = nil, topMarginHeight: CGFloat? = nil,
             outsideBars: MarginQuad? = nil, insideBars: MarginQuad? = nil,
             viewportMargins: MarginQuad? = nil,
             video: VideoGeometry? = nil,
             isMiddleTransition: Bool? = nil) -> PWinGeometry {

    let mode = mode ?? self.mode
    if mode == .musicMode {
      // This might get ugly in the future... maybe fail instead to force developer to add explcit choice in all situations?
      return cloneMusicMode(windowFrame: windowFrame, screenID: screenID, video: video)
    }

    let newGeo = PWinGeometry(windowFrame: windowFrame ?? self.windowFrame,
                              screenID: screenID ?? self.screenID,
                              screenFit: screenFit ?? self.screenFit,
                              mode: mode,
                              topMarginHeight: topMarginHeight ?? self.topMarginHeight,
                              outsideBars: outsideBars ?? self.outsideBars,
                              insideBars: insideBars ?? self.insideBars,
                              viewportMargins: viewportMargins,
                              video: video ?? self.video,
                              isMiddleTransition: isMiddleTransition ?? self.isMiddleTransition)
    return newGeo
  }

  // MARK: - Computed properties

  var description: String {
    return "PWinGeo{\(windowFrame) \(screenID.quoted) \(mode) \(screenFit) \(videoShown ? "vidH=\(videoHeight.logStr)" : "vid=NO") \(isMusicModePlaylistVisible ? "pListH=\(musicModePlaylistHeight.logStr)" : "pList=NO") notchH=\(topMarginHeight.logStr) outBars=\(outsideBars) inBars=\(insideBars) vidMargins=\(viewportMargins) \(video)}"
  }

  var log: Logger.Subsystem { video.log }

  /// Can only be `false` while in music mode. All other modes should return `true` always.
  var videoShown: Bool {
    return viewportSize.height > 0
  }

  /// Can only be `true` while in music mode.
  var isMusicModePlaylistVisible: Bool {
    guard mode == .musicMode else { return false }
    let playlistHeight = outsideBars.totalHeight - Constants.Distance.MusicMode.oscHeight
    return playlistHeight > 0
  }

  /// If in music mode & playlist is visible, indicates playlist height.
  /// Will be 0 if not in music mode or playlist is not visible.
  /// Derived from other properties.
  var musicModePlaylistHeight: CGFloat {
    guard mode == .musicMode else { return 0 }
    return round(windowFrame.height - Constants.Distance.MusicMode.oscHeight - videoSize.height)
  }

  /// Final aspect ratio of `videoView`. Very close to `video.videoAspectCAR`, except it is calculated from the actual pixels
  /// of the final `videoSize`. Very limited utility. In most cases `video.videoAspectDisplay` should be used, as it is the target.
  var videoViewAspect: CGFloat {
    // Just use videoAspectDisplay for now because it's a consistent value
    return videoSize.mpvAspect
  }

  let videoSize: NSSize

  var videoSizeIdeal: NSSize {
    return NSSize(width: videoSize.width, height: (videoSize.width / videoViewAspect).rounded())
  }

  /// `MPVProperty.currentWindowScale`: see `mp_property_current_window_scale()` in mpv's `player/command.c`
  func mpvWindowScale() -> CGFloat {
    let screen = NSScreen.getScreenOrDefault(screenID: screenID)
    let backingScaleFactor = screen.backingScaleFactor
    let viewportSize = viewportSize
    let videoSize = video.videoSizeCAR
    let mpvWindScale = (((viewportSize.width / videoSize.width) + (viewportSize.height / videoSize.height)) / 2 * backingScaleFactor).roundedTo6()
    log.verbose("[geo] Derived mpv window-scale from cached vidGeo: Viewport=\(viewportSize) * [screen=\(screen.displayId)] BSF=\(backingScaleFactor) / videoSizeCAR=\(videoSize) → \(mpvWindScale)")
    return mpvWindScale
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
    let viewportSize = viewportSize
    assert(viewportSize.width - videoSize.width >= 0 && viewportSize.height - videoSize.height >= 0,
           "viewportSize \(viewportSize) is smaller than videoSize \(videoSize)")
    let origin = CGPoint(x: outsideBars.leading + viewportMargins.leading,
                         y: outsideBars.bottom + viewportMargins.bottom)
    return NSRect(origin: origin, size: videoSize)
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

  // MARK: - Calculation Utils

  /// Finds minimum video size of the current geometry, assuming bars, mode, video aspect stay constant
  func minVideoSize() -> CGSize {
    return GeoUtil.minViewportSize(mode: mode, videoAspect: video.videoAspectCAR, insideBars: insideBars)
  }

  // This also accounts for videoAspect, and space needed by inside sidebars, if any
  func minViewportSize(mode: PlayerWindowMode? = nil) -> NSSize {
    let mode = mode ?? self.mode
    return GeoUtil.minViewportSize(mode: mode, videoAspect: video.videoAspectCAR, insideBars: insideBars)
  }

  func minWindowSize(mode: PlayerWindowMode? = nil) -> NSSize {
    let mode = mode ?? self.mode
    return GeoUtil.minWindowSize(mode: mode, videoAspect: video.videoAspectCAR, outsideBars: outsideBars, insideBars: insideBars)
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
    return videoShown ? videoHeightWhenVisible : 0
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
    let deltaX = ((newWindowSize.width - windowFrame.size.width) / 2).rounded(.down)
    let deltaY = ((newWindowSize.height - windowFrame.size.height) / 2).rounded(.down)
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
    var newGeo: PWinGeometry

    switch mode {

    case .fullScreenNormal, .fullScreenInteractive:
      log.error("[geo] PWinGeometry cannot resize window: mode (\(mode)) is not windowed or music mode!")
      return self

    case .musicMode:
      assert(lockViewportToVideoSize, "lockViewportToVideoSize must always be true in music mode")

      if inLiveResize, videoShown && !isMusicModePlaylistVisible {
        // Special case when scaling only video without playlist: allow window height to change, similar to windowed mode.
        let nonViewportAreaSize = windowFrame.size - viewportSize
        let requestedViewportSize = requestedSize - nonViewportAreaSize

        let scaledViewportSize: NSSize
        if isLiveResizingWidth {
          // Option A: resize height based on requested width
          scaledViewportSize = NSSize(width: requestedViewportSize.width,
                                      height: round(requestedViewportSize.width / video.videoAspectCAR))
        } else {
          // Option B: resize width based on requested height
          scaledViewportSize = NSSize(width: round(requestedViewportSize.height * video.videoAspectCAR),
                                      height: requestedViewportSize.height)
        }
        newGeo = scalingViewport(to: scaledViewportSize)

      } else { // General music mode layout
        let containerFrame = GeoUtil.getContainerFrame(forScreenID: screenID, screenFit: .stayInside)!

        /// When the window's width changes, the video scales to match while keeping its aspect ratio,
        /// and the control bar (`musicModeControlBarView`) and playlist are pushed down.
        /// Calculate the maximum width/height the art can grow to so that `musicModeControlBarView` is not pushed off the screen.
        let minPlaylistHeight = isMusicModePlaylistVisible ? Constants.Distance.MusicMode.minPlaylistHeight : 0
        let videoAspect = video.videoAspectCAR

        var maxWinWidth = min(MiniPlayerViewController.maxWindowWidth, containerFrame.width)
        var maxVideoHeight: CGFloat
        if videoShown {
          maxVideoHeight = containerFrame.height - Constants.Distance.MusicMode.oscHeight - minPlaylistHeight
          /// `maxVideoHeight` can be negative if very short screen! Fall back to height based on `MiniPlayerMinWidth` if needed
          maxVideoHeight = max(maxVideoHeight, (Constants.Distance.MusicMode.minWindowWidth / videoAspect).rounded())
          maxWinWidth = min(maxWinWidth, maxVideoHeight * videoAspect)
        } else {
          maxVideoHeight = 0
        }
        maxWinWidth = min(MiniPlayerViewController.maxWindowWidth, containerFrame.width)

        // Determine width first
        let newWindowWidth: CGFloat = requestedSize.width.rounded().clamped(to: Constants.Distance.MusicMode.minWindowWidth...maxWinWidth)

        // Now determine height. Clamp again in case rounding goes outside of bounds
        let videoHeight = (newWindowWidth / videoAspect).rounded().clamped(to: 0...maxVideoHeight)
        // Make sure height is within acceptable values
        let minWindowHeight = videoHeight + Constants.Distance.MusicMode.oscHeight + minPlaylistHeight
        let maxWindowHeight = isMusicModePlaylistVisible ? containerFrame.height : minWindowHeight
        let newWindowHeight = requestedSize.height.rounded().clamped(to: minWindowHeight...maxWindowHeight)

        var newWindowFrame = NSRect(origin: windowFrame.origin,
                                    size: NSSize(width: newWindowWidth, height: newWindowHeight))

        if ScreenFit.stayInside.shouldMoveWindowToKeepInContainer {
          newWindowFrame = newWindowFrame.constrainOrigin(in: containerFrame)
        }
        let outputGeo = cloneMusicMode(windowFrame: newWindowFrame)
        log.verbose("Resized musicMode window: reqSize=\(requestedSize) maxVideoHeight=\(maxVideoHeight) newWindowSize=\(newWindowFrame.size) → outputGeo=\(outputGeo)")
        return outputGeo
      }
      // fall through

    case .windowedNormal, .windowedInteractive:
      // Need to resize window to match video aspect ratio, while taking into account any outside panels.
      if lockViewportToVideoSize && inLiveResize {
        let nonViewportAreaSize = self.windowFrame.size - self.viewportSize
        let requestedViewportSize = requestedSize - nonViewportAreaSize

        if isLiveResizingWidth {
          // Option A: resize height based on requested width
          let resizedWidthViewportSize = NSSize(width: requestedViewportSize.width,
                                                height: round(requestedViewportSize.width / video.videoAspectCAR))
          newGeo = scalingViewport(to: resizedWidthViewportSize)
        } else {
          // Option B: resize width based on requested height
          let resizedHeightViewportSize = NSSize(width: round(requestedViewportSize.height * video.videoAspectCAR),
                                                 height: requestedViewportSize.height)
          newGeo = scalingViewport(to: resizedHeightViewportSize)
        }
      } else {
        /// If `!inLiveResize`: resize request is not coming from the user. Could be BetterTouchTool, Retangle, or some window manager, or the OS.
        /// These tools seem to expect that both dimensions of the returned size are less than the requested dimensions, so check for this.
        /// If `lockViewportToVideoSize && !inLiveResize`: scale window to requested size; `refitted()` below will constrain as needed.
        newGeo = self.scalingWindow(to: requestedSize)
      }
    }

    return newGeo
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

  func refitted(using newFit: ScreenFit? = nil, lockViewportToVideoSize: Bool? = nil) -> PWinGeometry {
    return scalingViewport(screenFit: newFit, lockViewportToVideoSize: lockViewportToVideoSize)
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
                       screenFit: ScreenFit? = nil,
                       lockViewportToVideoSize: Bool? = nil,
                       mode: PlayerWindowMode? = nil) -> PWinGeometry {
    guard video.videoAspectCAR >= 0 else {
      log.error{"[geo] PWinGeometry cannot scale viewport: videoAspectCAR (\(video.videoAspectCAR)) is invalid!"}
      assert(false)
      return self
    }

    let mode = mode ?? self.mode

    if mode == .musicMode {
      return scalingVideo(toWidth: desiredSize?.width ?? windowFrame.width, screenID: screenID)
    }

    // -- First, set up needed variables

    let lockViewportToVideoSize = mode.alwaysLockViewportToVideoSize || (lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize))
    // do not center in screen again unless explicitly requested
    let newFitOption = screenFit ?? (self.screenFit == .centerInside ? .stayInside : self.screenFit)
    let outsideBarsSize = outsideBars.totalSize
    let newScreenID = screenID ?? self.screenID
    let containerFrame: NSRect? = GeoUtil.getContainerFrame(forScreenID: newScreenID, screenFit: newFitOption)
    let maxViewportSize: NSSize?
    if let containerFrame {
      maxViewportSize = computeMaxViewportSize(in: containerFrame.size)
    } else {
      maxViewportSize = nil
    }
    let minViewportSize = minViewportSize(mode: mode)

    var newViewportSize = desiredSize ?? viewportSize
    log.trace{"[geo] ScaleViewport start, newViewportSize=\(newViewportSize), lockViewport=\(lockViewportToVideoSize.yn)"}

    // -- Viewport size calculation

    if lockViewportToVideoSize {
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

      /// Compute `videoSize` to fit within `viewportSize` (minus `viewportMargins`) while maintaining `videoAspect`:
      let newVideoSize = GeoUtil.computeVideoSize(withAspectRatio: video.videoAspectCAR, toFillIn: newViewportSize, mode: mode)
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
                               height: round(newViewportSize.height + outsideBarsSize.height))

    let adjustedOrigin = adjustWindowOrigin(forNewWindowSize: newWindowSize)
    var newWindowFrame = NSRect(origin: adjustedOrigin, size: newWindowSize)
    if let containerFrame, newFitOption.shouldMoveWindowToKeepInContainer {
      newWindowFrame = newWindowFrame.constrainOrigin(in: containerFrame)
      if newFitOption == .centerInside {
        newWindowFrame = newWindowFrame.size.centeredRect(in: containerFrame)
      }
      log.trace{"[geo] ScaleViewport: constrainedIn=\(containerFrame) → windowFrame=\(newWindowFrame)"}
    } else {
      log.trace{"[geo] ScaleViewport: → windowFrame=\(newWindowFrame)"}
    }

    let refittedGeo = self.clone(windowFrame: newWindowFrame, screenID: newScreenID, screenFit: newFitOption, mode: mode)

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
                    screenFit: ScreenFit? = nil,
                    lockViewportToVideoSize: Bool? = nil,
                    mode: PlayerWindowMode? = nil) -> PWinGeometry {

    let mode = mode ?? self.mode

    if mode == .musicMode {
      /// Separate logic for music mode window.
      /// The MiniPlayerWindow's width must be between `MiniPlayerMinWidth` and `Preference.musicModeMaxWidth`.
      /// It is composed of up to 3 vertical sections:
      /// 1. `viewportView`: Visible if `videoShown` is true. Scales with the aspect ratio of its video.
      /// 2. `musicModeControlBarView`: Visible always. Fixed height.
      /// 3. `playlistWrapperView`: Visible if `playlistShown` is true. Height is user resizable, and must be >= `PlaylistMinHeight`.
      /// Must also ensure that window stays within the bounds of the screen it is in. Almost all of the time the window  will be
      /// height-bounded instead of width-bounded.
      let newScreenID = screenID ?? self.screenID
      let containerFrame: NSRect = GeoUtil.getContainerFrame(forScreenID: newScreenID, screenFit: .stayInside)!

      // Constrain desired width within min and max allowed, then recalculate height from new value
      let maxWindowWidth: CGFloat = min(containerFrame.width, MiniPlayerViewController.maxWindowWidth)
      var newWindowWidth = desiredVideoWidth.clamped(to: Constants.Distance.MusicMode.minWindowWidth...maxWindowWidth)

      // Window height should not change. Only video size should be scaled
      let newWindowHeight = min(containerFrame.height, windowFrame.height)

      var newVideoHeight: CGFloat = 0
      if videoShown {
        let videoAspect = video.videoAspectCAR
        newVideoHeight = (newWindowWidth / videoAspect).rounded()

        let maxVideoHeight: CGFloat
        if isMusicModePlaylistVisible {
          // If playlist is visible, keep the window height fixed.
          // The video will only be able to expand until the playlist is at its min height
          maxVideoHeight = newWindowHeight - Constants.Distance.MusicMode.oscHeight - Constants.Distance.MusicMode.minPlaylistHeight
        } else {
          // If playlist not visible, window height can grow up to the size of the screen
          maxVideoHeight = containerFrame.height - Constants.Distance.MusicMode.oscHeight
        }
        /// Due to rounding errors and the fact that both `videoHeight` & `playlistHeight` are calculated
        /// (kind of backed into a corner with this one. Oops...) need to make sure that the calculation of
        /// `videoHeight` from `window.frame.width` & video aspect will not result in 1 too many pixels.
        /// This only appears to show up when scaling video to fill the screen & playlist is shown.
        /// Don't want to just distort the video for even 1 pixel to make it fit, as that will cause a
        /// validation error in various sanity checks.
        var trialHeight: CGFloat = newVideoHeight
        while (newVideoHeight > maxVideoHeight) || (newWindowWidth > maxWindowWidth) {
          trialHeight = min(maxVideoHeight, trialHeight - 1)
          newWindowWidth = (trialHeight * videoAspect).rounded()
          newVideoHeight = (newWindowWidth / videoAspect).rounded()
        }
      }
      let newWindowSize = NSSize(width: newWindowWidth, height: newWindowHeight)

      var newOriginX = windowFrame.origin.x

      // Determine which X direction to scale towards by checking which side of the screen it's closest to
      let distanceToLeadingSideOfScreen = abs(abs(windowFrame.minX) - abs(containerFrame.minX))
      let distanceToTrailingSideOfScreen = abs(abs(windowFrame.maxX) - abs(containerFrame.maxX))
      if distanceToTrailingSideOfScreen < distanceToLeadingSideOfScreen {
        // Closer to trailing side. Keep trailing side fixed by adjusting the window origin by the width changed
        let widthChange = windowFrame.width - newWindowWidth
        newOriginX += widthChange
      }
      // else (closer to leading side): keep leading side fixed

      let newWindowOrigin = NSPoint(x: newOriginX, y: windowFrame.origin.y)

      var newWindowFrame = NSRect(origin: newWindowOrigin, size: newWindowSize)
      if ScreenFit.stayInside.shouldMoveWindowToKeepInContainer {
        newWindowFrame = newWindowFrame.constrainOrigin(in: containerFrame)
      }

      let outputGeo = cloneMusicMode(windowFrame: newWindowFrame)
      assert(videoShown == outputGeo.videoShown,
             "Scaling musicMode video: videoShown mismatch: \(videoShown.yesno) → \(outputGeo.videoShown.yesno)")
      assert(isMusicModePlaylistVisible == outputGeo.isMusicModePlaylistVisible,
             "Scaling musicMode video: playlistShown mismatch: \(isMusicModePlaylistVisible.yesno) → \(outputGeo.isMusicModePlaylistVisible.yesno)")

      log.verbose("[geo] Scaled video (MusicMode): desiredWidth=\(desiredVideoWidth) maxWidth=\(maxWindowWidth) videoShown=\(videoShown.yn) playlistShown=\(isMusicModePlaylistVisible.yn) newWndWidth=\(newWindowWidth) newWndSize=\(newWindowFrame.size) → \(outputGeo)")
      return outputGeo
    }  // end music mode logic

    let lockViewportToVideoSize = lockViewportToVideoSize ?? Preference.bool(for: .lockViewportToVideoSize) || mode.alwaysLockViewportToVideoSize
    log.trace{"[geo] ScaleVideo start, desiredVideoWidth: \(desiredVideoWidth), videoAspectCAR: \(video.videoAspectCAR), lockViewportToVideoSize: \(lockViewportToVideoSize)"}

    // do not center in screen again unless explicitly requested
    var newFitOption = screenFit ?? (self.screenFit == .centerInside ? .stayInside : self.screenFit)
    if newFitOption == .legacyFullScreen || newFitOption == .nativeFullScreen {
      // Programmer screwed up
      log.error{"[geo] ScaleVideo: invalid fit option: \(newFitOption). Defaulting to 'none'"}
      newFitOption = .noConstraints
    }

    let minVideoSize = minVideoSize()
    let newWidth = max(minVideoSize.width, desiredVideoWidth)
    /// Enforce `videoView` aspectRatio: Recalculate height using width
    var newVideoSize = NSSize(width: newWidth, height: round(newWidth / video.videoAspectCAR))

    let containerFrame: NSRect? = GeoUtil.getContainerFrame(forScreenID: screenID ?? self.screenID, screenFit: newFitOption)
    if let containerFrame {
      // Scale down to fit in bounds of container
      if newVideoSize.width > containerFrame.width {
        newVideoSize = NSSize(width: containerFrame.width, height: round(containerFrame.width / video.videoAspectCAR))
      }

      if newVideoSize.height > containerFrame.height {
        newVideoSize = NSSize(width: round(containerFrame.height * video.videoAspectCAR), height: containerFrame.height)
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
  /// - Param `intendedViewportSize` is only used when `lockViewportToVideoSize` is enabled.
  /// When the user is navigating in playlist or changes crop or aspect, try to retain same window width.
  /// This often isn't possible for vertical videos, which will end up shrinking the width.
  /// So try to remember the preferred width so it can be restored when possible.
  /// (If not locking viewport, don't need this. We can just reuse the existing viewport size.)
  func resizeMinimally(forNewVideoGeo newVidGeo: VideoGeometry, intendedViewportSize: NSSize? = nil) -> PWinGeometry {
    var desiredViewportSize = viewportSize
    let log = newVidGeo.log

    if Preference.bool(for: .lockViewportToVideoSize) {
      if let intendedViewportSize  {
        // Just use existing size in this case:
        desiredViewportSize = intendedViewportSize
        log.verbose("[geo] Using intendedViewportSize \(intendedViewportSize)")
      }

      let minNewViewportHeight = round(desiredViewportSize.width / newVidGeo.videoAspectCAR)
      if desiredViewportSize.height < minNewViewportHeight {
        // Try to increase height if possible, though it may still be shrunk to fit screen
        desiredViewportSize = NSSize(width: desiredViewportSize.width, height: minNewViewportHeight)
      }
    }

    log.verbose("[geo] Minimal resize: applying desiredViewportSize \(desiredViewportSize)")
    return clone(video: newVidGeo).scalingViewport(to: desiredViewportSize)
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

    // Special logic if output has reached out the size of the screen.
    // Do not allow it to get bigger than the screen.
    if let screenFrame = getContainerFrame(), screenFit.shouldMoveWindowToKeepInContainer {
      if newWindowWidth > screenFrame.width || (pinWidthOrHeightIfAtMax && (abs(screenFrame.width - windowFrame.width) <= 1)) {
        newWindowWidth = screenFrame.width
        newX = screenFrame.origin.x  // Move to fit in screen
      } else if pinWidthOrHeightIfAtMax {
        if abs(screenFrame.minX - windowFrame.minX) <= 1 {
          // Was aligned to screen's LEADING edge
          newX = screenFrame.minX
        } else if abs(screenFrame.maxX - windowFrame.maxX) <= 1 {
          // Was aligned to screen's TRAILING edge
          newX = screenFrame.maxX - newWindowWidth
        }
      }

      if newWindowHeight > screenFrame.height || (pinWidthOrHeightIfAtMax && (abs(screenFrame.height - windowFrame.height) <= 1)) {
        newWindowHeight = screenFrame.height
        newY = screenFrame.origin.y  // Move to fit in screen
      } else if pinWidthOrHeightIfAtMax {
        if abs(screenFrame.minY - windowFrame.minY) <= 1 {
          // Was aligned to screen's BOTTOM edge
          newY = screenFrame.minY
        } else if abs(screenFrame.maxY - windowFrame.maxY) <= 1 {
          // Was aligned to screen's TOP edge
          newY = screenFrame.maxY - newWindowHeight
        }
      }
    }

    let newWindowFrame = CGRect(x: newX, y: newY, width: newWindowWidth, height: newWindowHeight)
    // If new windowFrame is slightly off screen, so fall back to current screenID.
    // Also fall back to default screen if current screenID is defunct:
    let newScreenID = NSScreen.getOwnerOrDefaultScreenID(forViewRect: newWindowFrame, fallbackScreenID: screenID)
    let newOutsideBars = MarginQuad(top: top ?? outsideBars.top,
                                    trailing: trailing ?? outsideBars.trailing,
                                    bottom: bottom ?? outsideBars.bottom,
                                    leading: leading ?? outsideBars.leading)

    let resizedBarsGeo = clone(windowFrame: newWindowFrame, screenID: newScreenID, outsideBars: newOutsideBars)
    log.verbose{"[ResizeBars] ΔW=\(ΔW.logStr) ΔH=\(ΔH.logStr) pinMax=\(pinWidthOrHeightIfAtMax.yn) moveToKeepInScreen:\(resizedBarsGeo.screenFit.shouldMoveWindowToKeepInContainer.yesno)"}
    return resizedBarsGeo
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
      let newViewportHeight = round(newViewportWidth / video.videoAspectCAR)
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
        let newViewportWidth = round(newViewportHeight * video.videoAspectCAR)
        newWindowSize.width = newViewportWidth + outsideBars.totalWidth
      }
    } else if !isWidthSet && isHeightSet {
      // Calculate width based on height and aspect
      let newViewportHeight = newWindowSize.height - (outsideBars.totalHeight + topMarginHeight)
      let newViewportWidth = round(newViewportHeight * video.videoAspectCAR)
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
        let newViewportHeight = round(newViewportWidth / video.videoAspectCAR)
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

    let newWindowFrame = NSRect(x: newOrigin.x.rounded(), y: newOrigin.y.rounded(), width: newWindowSize.width.rounded(), height: newWindowSize.height.rounded())
    log.debug("Calculated windowFrame from mpv geometry: \(newWindowFrame)")
    return self.clone(windowFrame: newWindowFrame)
  }

  // MARK: - Interactive mode

  static func buildInteractiveModeWindow(windowFrame: NSRect, screenID: String, video: VideoGeometry) -> PWinGeometry {
    let outsideBars = MarginQuad(top: Constants.InteractiveMode.outsideTopBarHeight, trailing: 0,
                                 bottom: Constants.InteractiveMode.outsideBottomBarHeight, leading: 0)
    return PWinGeometry(windowFrame: windowFrame, screenID: screenID, screenFit: .stayInside,
                        mode: .windowedInteractive, topMarginHeight: 0,
                        outsideBars: outsideBars,
                        insideBars: MarginQuad.zero,
                        video: video)
  }

  // Transition windowed mode geometry to Interactive Mode geometry. Note that this is not a direct conversion; it will modify the view sizes
  func toInteractiveMode() -> PWinGeometry {
    assert(screenFit != .legacyFullScreen && screenFit != .nativeFullScreen)
    assert(mode == .windowedNormal)
    // TODO: preserve window size better when lockViewportToVideoSize==false
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
    let croppedVideoAspect = newVidGeo.videoAspectC
    let croppedVideoViewSize = GeoUtil.computeVideoSize(withAspectRatio: croppedVideoAspect,
                                                        toFillIn: cropRectScaledToWindow.size,
                                                        minViewportMargins: .zero, mode: mode)


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

    log.debug("[geo] Cropping from cropRect \(cropRect) x videoScale (\(scaleRatio)), windowSize=\(windowFrame.size), → newVideoSize:\(cropRectScaledToWindow.size), newVideoAspect:\(croppedVideoAspect), newViewportMargins:\(newViewportMargins)")
    let newFitOption = self.screenFit == .centerInside ? .stayInside : self.screenFit
    log.debug("[geo] Cropped to new cropLabel: \(newVidGeo.selectedCropLabel.quoted), screenID: \(screenID), screenFit: \(newFitOption)")
    return self.clone(screenFit: newFitOption, viewportMargins: newViewportMargins, video: newVidGeo)
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
                           videoShown: Bool, playlistShown: Bool) -> PWinGeometry {
    let log = video.log
    var windowFrame = NSRect(origin: windowFrame.origin, size:
                              CGSize(width: windowFrame.width.rounded(), height: windowFrame.height.rounded()))
    let videoHeight = PWinGeometry.MusicMode.videoHeight(windowFrame: windowFrame, video: video, videoShown: videoShown, playlistShown: playlistShown)
    var musicModePlaylistHeight = windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight

    let extraWidthNeeded = Constants.Distance.MusicMode.minWindowWidth - windowFrame.width
    if extraWidthNeeded > 0 {
      log.verbose{"MusicModeGeoInit: width too small; adding: \(extraWidthNeeded)"}
      windowFrame = NSRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width + extraWidthNeeded, height: windowFrame.height))
    }

    if playlistShown {
      let extraHeightNeeded = Constants.Distance.MusicMode.minPlaylistHeight - musicModePlaylistHeight
      if extraHeightNeeded > 0 {
        log.verbose{"MusicModeGeoInit: height too small for playlist; adding: \(extraHeightNeeded)"}
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    } else {
      let extraHeightNeeded = -musicModePlaylistHeight
      if extraHeightNeeded != 0 {
        log.verbose{"MusicModeGeoInit: height is invalid; adding: \(extraHeightNeeded)"}
        windowFrame = NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y - extraHeightNeeded,
                             width: windowFrame.width, height: windowFrame.height + extraHeightNeeded)
      }
    }
    assert(windowFrame.origin.x.isInteger && windowFrame.origin.y.isInteger && windowFrame.width.isInteger && windowFrame.height.isInteger,
           "All windowFrame dimensions must be integers: \(windowFrame)")

    musicModePlaylistHeight = windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight  // recalculate this var
    let winGeo = PWinGeometry(windowFrame: windowFrame,
                              screenID: screenID,
                              screenFit: .stayInside,
                              mode: .musicMode,
                              topMarginHeight: 0,
                              outsideBars: MarginQuad(bottom: Constants.Distance.MusicMode.oscHeight + musicModePlaylistHeight),
                              insideBars: MarginQuad.zero,
                              video: video)

    let isValidHeight = playlistShown ? (musicModePlaylistHeight >= Constants.Distance.MusicMode.minPlaylistHeight) : (musicModePlaylistHeight == 0)
    if !isValidHeight {
      log.errorDebugAlert{"Music mode window: playlist height is invalid (will attempt to fix): playlistShown=\(playlistShown.yn) but playlistHeight (\(musicModePlaylistHeight)) is less than minimum (\(Constants.Distance.MusicMode.minPlaylistHeight))."}
      return winGeo.refitted()
    }
    assert(videoShown == winGeo.videoShown,
           "Expected videoShown to match: \(videoShown.yesno) → \(winGeo.videoShown.yesno)")
    assert(playlistShown == winGeo.isMusicModePlaylistVisible,
           "Expected playlistShown to match: \(playlistShown.yesno) → \(winGeo.isMusicModePlaylistVisible.yesno)")
    return winGeo
  }

  func cloneMusicMode(windowFrame: NSRect? = nil, screenID: String? = nil, video: VideoGeometry? = nil,
                      videoShown: Bool? = nil, playlistShown: Bool? = nil) -> PWinGeometry {
    guard mode == .musicMode else {
      log.error("Cannot call PWinGeometry.cloneMusicMode when mode ≠ music mode: \(self)")
      assert(false, "Cannot call PWinGeometry.cloneMusicMode when mode ≠ music mode: \(self)")  // fail fast when debugging
      return self
    }
    let showVideo = videoShown ?? self.videoShown
    let showPlaylist = playlistShown ?? self.isMusicModePlaylistVisible
    log.verbose("Cloning music mode geometry from \(self), showVideo=\(showVideo.yn), showPlaylist=\(showPlaylist.yn)")
    return PWinGeometry.forMusicMode(windowFrame: windowFrame ?? self.windowFrame,
                                     screenID: screenID ?? self.screenID,
                                     video: video ?? self.video,
                                     videoShown: showVideo,
                                     playlistShown: showPlaylist)
  }

  /// Music mode only!
  func withVideoViewVisible(_ visible: Bool) -> PWinGeometry {
    guard mode == .musicMode else {
      log.error("Cannot call PWinGeometry.withVideoViewVisible when mode ≠ music mode: \(self)")
      assert(false, "Cannot call PWinGeometry.withVideoViewVisible when mode ≠ music mode: \(self)")  // fail fast when debugging
      return self
    }
    guard self.videoShown != visible else { return self }

    var newWindowFrame = windowFrame
    if visible {
      newWindowFrame.size.height += videoHeightWhenVisible
    } else {
      // If playlist is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      newWindowFrame.size.height = max(Constants.Distance.MusicMode.oscHeight, newWindowFrame.size.height - videoHeightWhenVisible)
    }
    return cloneMusicMode(windowFrame: newWindowFrame, videoShown: visible)
  }

  struct MusicMode {
    static func playlistHeight(windowFrame: CGRect, video: VideoGeometry, videoShown: Bool, playlistShown: Bool) -> CGFloat {
      guard playlistShown else {
        return 0
      }
      let videoHeight = videoHeight(windowFrame: windowFrame, video: video, videoShown: videoShown, playlistShown: playlistShown)
      return windowFrame.height - videoHeight - Constants.Distance.MusicMode.oscHeight
    }

    static func videoHeight(windowFrame: CGRect, video: VideoGeometry, videoShown: Bool, playlistShown: Bool) -> CGFloat {
      guard videoShown else {
        return 0
      }
      let vidHeight = videoHeightWhenVisible(windowFrame: windowFrame, video: video)
      return vidHeight
    }

    static func videoHeightWhenVisible(windowFrame: CGRect, video: VideoGeometry) -> CGFloat {
      return (windowFrame.width / video.videoAspectCAR).rounded()
    }

  }  // end struct MusicMode

}
