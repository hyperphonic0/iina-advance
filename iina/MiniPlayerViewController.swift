//
//  MiniPlayerViewController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class MiniPlayerViewController: NSViewController, NSPopoverDelegate {

  override var nibName: NSNib.Name {
    return NSNib.Name("MiniPlayerViewController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .mini)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  @IBOutlet weak var playbackBtnsWrapperView: NSView!
  @IBOutlet weak var positionSliderWrapperView: NSView!

  @IBOutlet weak var volumeButton: SymButton!
  @IBOutlet var volumePopover: NSPopover!
  @IBOutlet weak var volumeSliderView: NSView!
  @IBOutlet weak var volumePopoverAlignmentView: NSView!
  @IBOutlet weak var musicModeControlBarView: NSVisualEffectView!
  @IBOutlet weak var playlistWrapperView: NSVisualEffectView!
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controllerButtonsPanelView: NSView!
  @IBOutlet weak var titleLabel: ScrollingTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: ScrollingTextField!
  @IBOutlet weak var volumeLabel: NSTextField!
  @IBOutlet weak var togglePlaylistButton: SymButton!
  @IBOutlet weak var toggleAlbumArtButton: SymButton!
  @IBOutlet weak var volumeButtonLeadingConstraint: NSLayoutConstraint!

  private var hideVolumePopoverTimer: Timer?

  unowned var windowController: PlayerWindowController!
  var player: PlayerCore {  windowController.player }
  var window: NSWindow? { windowController.window }
  var log: Logger.Subsystem {  windowController.log }

  var playlistShown: Bool { windowController.musicModeGeo.isMusicModePlaylistVisible }
  var videoShown: Bool {  windowController.musicModeGeo.videoShown }
  var windowWidthForScrollingLabels: CGFloat = 0

  static var maxWindowWidth: CGFloat { CGFloat(Preference.float(for: .musicModeMaxWidth)) }

  var currentDisplayedPlaylistHeight: CGFloat {
    let playlistVC = windowController.playlistView
    guard playlistVC.isViewLoaded && !playlistVC.view.isHidden else { return 0.0 }
    let playlistHeight = playlistVC.view.frame.height
    return playlistHeight
  }

  // MARK: - Initialization

  override func viewDidLoad() {
    super.viewDidLoad()

    /// `musicModeControlBarView` is always the same height
    musicModeControlBarView.heightAnchor.constraint(equalToConstant: Constants.Distance.MusicMode.oscHeight).isActive = true
    musicModeControlBarView.idString = "MusicModeControlBarView"
    positionSliderWrapperView.idString = "PositionSliderWrapperView"
    controllerButtonsPanelView.idString = "ControllerButtonsPanelView"
    mediaInfoView.idString = "MediaInfoView"

    // Clip scrolling text at the margins so it doesn't touch the sides of the window
    mediaInfoView.clipsToBounds = true

    /// Set up tracking area to show controller when hovering over it
    windowController.viewportView.addTrackingArea(NSTrackingArea(rect: windowController.viewportView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))
    musicModeControlBarView.addTrackingArea(NSTrackingArea(rect: musicModeControlBarView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // close button
    windowController.closeButtonVE.action = #selector(windowController.close)
    windowController.closeButtonBox.action = #selector(windowController.close)
    windowController.closeButtonBackgroundViewVE.roundCorners()

    // hide controls initially
    controllerButtonsPanelView.alphaValue = 0

    // tool tips
    togglePlaylistButton.identifier = .init("TogglePlaylistButton")
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.description()
    togglePlaylistButton.image = Preference.ToolBarButton.playlist.image()
    togglePlaylistButton.bounceOnClick = true

    toggleAlbumArtButton.identifier = .init("ToggleAlbumArtButton")
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    toggleAlbumArtButton.image = Images.toggleAlbumArt
    toggleAlbumArtButton.bounceOnClick = true

    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    volumeButton.identifier = .init("VolumeButton")
    volumeButton.bounceOnClick = true
    windowController.closeButtonVE.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    windowController.backButtonVE.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    playlistWrapperView.identifier = .init("PlaylistWrapperView")

    volumePopover.delegate = self

    log.verbose("MiniPlayer viewDidLoad done")
  }

  // MARK: - UI: Controller

  /// Shows Controller on hover
  override func mouseEntered(with event: NSEvent) {
    guard player.isInMiniPlayer else { return }
    showControl()
  }

  /// Hides Controller when hover leaves controller area
  override func mouseExited(with event: NSEvent) {
    guard player.isInMiniPlayer else { return }

    /// The goal is to always show the control when the cursor is hovering over either of the 2 tracking areas.
    /// Although they are adjacent to each other, `mouseExited` can still be called when moving from one to the other.
    /// Detect and ignore this case.
    guard !windowController.isMouseEvent(event, inAnyOf: [musicModeControlBarView, windowController.viewportView]) else {
      return
    }

    hideControllerButtonsInPipeline()
  }

  private func showControl() {
    windowController.animationPipeline.submitTask(duration: Constants.AnimationDuration.musicModeShowButtons, { [self] in
      log.trace("MiniPlayer: showing OSC controls / hiding media info")
      windowController.osd.osdLeadingToMiniPlayerButtonsTrailingConstraint?.priority = .required
      windowController.closeButtonView.isHidden = false
      windowController.closeButtonView.animator().alphaValue = 1
      controllerButtonsPanelView.animator().alphaValue = 1
      mediaInfoView.animator().alphaValue = 0
    })
  }

  /// Hides media info, shows OSC controls (runs as async task in animationPipeline)
  private func hideControllerButtonsInPipeline() {
    guard windowController.isInMiniPlayer else { return }
    windowController.animationPipeline.submitTask(duration: Constants.AnimationDuration.musicModeShowButtons, { [self] in
      hideControllerButtons()
    })
  }

  /// Hides media info, shows OSC controls (synchronous version)
  func hideControllerButtons() {
    log.trace("MiniPlayer: hiding OSC controls / showing media info")
    windowController.osd.osdLeadingToMiniPlayerButtonsTrailingConstraint?.priority = .defaultLow
    windowController.closeButtonView.isHidden = true
    windowController.closeButtonView.animator().alphaValue = 0
    controllerButtonsPanelView.animator().alphaValue = 0
    mediaInfoView.animator().alphaValue = 1
  }

  // MARK: - UI: Media Info

  func updateScrollingLabels() {
    loadIfNeeded()
    let isPaused = player.info.isPaused
    titleLabel.requestRedraw(paused: isPaused)
    artistAlbumLabel.requestRedraw(paused: isPaused)
  }

  func updateTitle(mediaTitle: String, mediaAlbum: String, mediaArtist: String) {
    titleLabel.stringValue = mediaTitle
    // hide artist & album label when info not available
    if mediaArtist.isEmpty && mediaAlbum.isEmpty {
      titleLabelTopConstraint.constant = 6 + 10
      artistAlbumLabel.stringValue = ""
    } else {
      titleLabelTopConstraint.constant = 6
      if mediaArtist.isEmpty || mediaAlbum.isEmpty {
        artistAlbumLabel.stringValue = "\(mediaArtist)\(mediaAlbum)"
      } else {
        artistAlbumLabel.stringValue = "\(mediaArtist) - \(mediaAlbum)"
      }
    }
  }

  // MARK: - Volume UI

  /// Executed when `hideVolumePopoverTimer` fires.
  @objc private func hideVolumePopover() {
    volumePopover.animates = true
    volumePopover.performClose(self)
  }

  /// From `NSPopoverDelegate`: close volume popover
  func popoverWillClose(_ notification: Notification) {
    hideVolumePopoverTimer?.invalidate()
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControllerButtonsInPipeline()
    }
  }

  /// From `NSPopoverDelegate`: open volume popover
  func showVolumePopover() {
    hideVolumePopoverTimer?.invalidate()

    // if it's a mouse, simply show popover then hide after a while when user stops scrolling
    if !volumePopover.isShown {
      volumePopover.animates = false
      volumePopover.show(relativeTo: volumePopoverAlignmentView.bounds, of: volumePopoverAlignmentView, preferredEdge: .minY)
    }

    let timeout = max(Preference.double(for: .osdAutoHideTimeout), Constants.TimeInterval.musicModePopoverMinTimeout)
    hideVolumePopoverTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self,
                                                  selector: #selector(self.hideVolumePopover), userInfo: nil, repeats: false)
  }

  // MARK: - IBActions

  @IBAction func volumeBtnAction(_ sender: NSButton) {
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      windowController.updateVolumeUI()
      volumePopover.show(relativeTo: volumePopoverAlignmentView.bounds, of: volumePopoverAlignmentView,
                         preferredEdge: .minY)
    }
  }

  /// Action: Show/Hide playlist
  @IBAction func togglePlaylist(_ sender: AnyObject?) {
    windowController.animationPipeline.submitInstantTask({ [self] in
      let inputMusicModeGeo = windowController.musicModeGeo
      // Use MusicModeState as an adapter from PWinGeometry & LayoutState paradigms
      let inputMusicModeState = MusicModeState(playlistShown: inputMusicModeGeo.isMusicModePlaylistVisible,
                                               videoShown: inputMusicModeGeo.videoShown)
      let inputSpec = windowController.currentLayout.spec.clone(musicModeState: inputMusicModeState)
      guard inputSpec.mode == .musicMode else { return }
      let inputLayout = LayoutState(spec: inputSpec)
      let outputMusicModeState = MusicModeState(playlistShown: !inputMusicModeState.playlistShown,
                                                videoShown: inputMusicModeState.videoShown)
      let outputSpec = inputSpec.clone(musicModeState: outputMusicModeState)
      let name = outputMusicModeState.playlistShown ? "ShowMusicModePlaylist" : "HideMusicModePlaylist"
      windowController.buildLayoutTransition(named: name, from: inputLayout, to: outputSpec, thenRun: true)
    })
  }

  /// Action: Show/Hide `videoView`
  @IBAction func toggleVideoViewVisibleState(_ sender: AnyObject?) {
    windowController.animationPipeline.submitInstantTask({ [self] in
      let showVideoView = !videoShown
      log.verbose{"MusicMode: user clicked video toggle btn. Changing videoView visibility: \((!showVideoView).yn) → \(showVideoView.yn)"}

      if showVideoView {
        /// If showing video, call `setVideoTrackEnabled()`, then do animations, for a nicer effect.
        player.setVideoTrackEnabled(thenShowMiniPlayerVideo: true)
      } else {
        // Hiding video.

        /// This will call `setFrameAndUpdateWindowSubviews`, which will call `setVideoTrackDisabled`.
        /// We want to wait until the animation is done before disabling video.
        // TODO: develop a nicer sliding animation if possible. Will need a lot of changes to constraints :/
        let gtf = GeometryTransform("HideVideoView", player,
                                    windowed: { [self] ctx -> PWinGeometry? in
          // music mode only. Other modes should fall back to default
          guard ctx.outputLayout.mode == .musicMode else { return nil }

          let inputMusicModeGeo = ctx.inputGeoSet.musicMode
          let outputMusicModeGeo = inputMusicModeGeo.withVideoViewVisible(false)
          log.verbose{"MusicMode: changing videoView visibility: \(inputMusicModeGeo.videoShown.yesno) → \(outputMusicModeGeo.videoShown.yesno), H=\(outputMusicModeGeo.videoHeight)"}
          return outputMusicModeGeo
        })
        gtf.submit()
      }
    })
  }

  // MARK: - Window size & layout

  func updateVideoViewHeightConstraint(videoShown: Bool) {
    if videoShown {
      log.verbose{"Deactivating ViewportView-HeightContraint for video=SHOWN"}
      // Remove zero-height constraint
      windowController.viewportViewHeightContraint?.isActive = false
    } else {
      log.verbose{"Activating ViewportView-HeightContraint for video=HIDDEN"}
      // Add or reactivate zero-height constraint
      if let heightConstraint = windowController.viewportViewHeightContraint {
        heightConstraint.isActive = true
      } else {
        let heightConstraint = windowController.viewportView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.identifier = "ViewportView-HeightContraint"
        heightConstraint.isActive = true
        windowController.viewportViewHeightContraint = heightConstraint
      }
    }
    windowController.viewportView.needsUpdateConstraints = true
    windowController.viewportView.layout()
  }

  static func buildMusicModeGeometryFromPrefs(screen: NSScreen, video: VideoGeometry) -> PWinGeometry {
    // Default to left-top of screen. Try to use last-saved playlist height and visibility settings.
    let playlistShown = Preference.bool(for: .musicModeShowPlaylist)
    let videoShown = Preference.bool(for: .musicModeShowAlbumArt)
    let desiredPlaylistHeight = CGFloat(Preference.float(for: .musicModePlaylistHeight))
    let desiredWindowWidth = Constants.Distance.MusicMode.defaultWindowWidth
    let desiredVideoHeight = videoShown ? round(desiredWindowWidth / video.videoAspectCAR) : 0
    let desiredWindowHeight = desiredVideoHeight + Constants.Distance.MusicMode.oscHeight + (playlistShown ? desiredPlaylistHeight : 0)

    let screenFrame = screen.visibleFrame
    let windowSize = NSSize(width: desiredWindowWidth, height: desiredWindowHeight)
    let windowOrigin = NSPoint(x: screenFrame.origin.x, y: screenFrame.maxY - windowSize.height)
    let windowFrame = NSRect(origin: windowOrigin, size: windowSize)
    let desiredGeo = PWinGeometry.forMusicMode(windowFrame: windowFrame, screenID: screen.screenID, video: video,
                                               videoShown: videoShown, playlistShown: playlistShown)
    // Resize as needed to fit on screen:
    return desiredGeo.refitted()
  }
}
