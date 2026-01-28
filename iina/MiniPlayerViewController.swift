//
//  MiniPlayerViewController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class MiniPlayerViewController: NSViewController, NSPopoverDelegate {
  fileprivate class PlaylistWrapperView: NSVisualEffectView {
    init() {
      super.init(frame: .zero)
      idString = "PlaylistWrapperView"
      blendingMode = .behindWindow
      material = .underWindowBackground
      state = .active
      wantsLayer = true
      translatesAutoresizingMaskIntoConstraints = false
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }

  fileprivate class VolumePopoverContentViewController: NSViewController {
    unowned let volumeSliderView: VolumeSliderView

    init(volumeSliderView: VolumeSliderView) {
      self.volumeSliderView = volumeSliderView
      super.init(nibName: nil, bundle: nil)
      view = volumeSliderView
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }

  fileprivate class VolumeSliderView: NSView {
    unowned let volumeLabel: NSTextField

    init(volumeLabel: NSTextField) {
      self.volumeLabel = volumeLabel
      super.init(frame: .zero)
      idString = "VolumeSliderView"
      translatesAutoresizingMaskIntoConstraints = false
      heightAnchor.constraint(equalToConstant: 36).isActive = true

      volumeLabel.translatesAutoresizingMaskIntoConstraints = false
      volumeLabel.setContentHuggingPriority(.init(249), for: .horizontal)
      volumeLabel.textColor = .labelColor
      volumeLabel.font = .systemFont(ofSize: 13)
      addSubview(volumeLabel)
      volumeLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
      let trailingEqCon = trailingAnchor.constraint(equalTo: volumeLabel.leadingAnchor, constant: 32)
      trailingEqCon.priority = .defaultHigh
      trailingEqCon.isActive = true
      let trailingGTCon = trailingAnchor.constraint(greaterThanOrEqualTo: volumeLabel.trailingAnchor)
      trailingGTCon.isActive = true
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  }

  override var nibName: NSNib.Name { NSNib.Name("MiniPlayerViewController") }

  @IBOutlet weak var playbackBtnsWrapperView: NSView!
  @IBOutlet weak var positionSliderWrapperView: NSView!

  @IBOutlet weak var volumeButton: SymButton!
  let volumePopover: NSPopover
  fileprivate let volumeLabel = NSTextField(labelWithString: "50")
  let volumeSliderView: NSView
  fileprivate let volumePopoverViewController: VolumePopoverContentViewController
  @IBOutlet weak var volumePopoverAlignmentView: NSView!
  @IBOutlet weak var musicModeControlBarView: NSVisualEffectView!
  fileprivate let playlistWrapperView = PlaylistWrapperView()
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controllerButtonsPanelView: NSView!
  @IBOutlet weak var titleLabel: ScrollingTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: ScrollingTextField!
  @IBOutlet weak var togglePlaylistButton: SymButton!
  @IBOutlet weak var toggleAlbumArtButton: SymButton!
  /// This is adjusted when the viewport is open/closed
  @IBOutlet weak var volumeButtonLeadingConstraint: NSLayoutConstraint!

  let playlistWrapperTopBorder = BorderLineView(id: "MusicMode-PL-Wrapper-TopBorder", fillColor: .quaternaryLabelColor)

  private var hideVolumePopoverTimer: Timer?

  unowned var pwc: PlayerWindowController!
  var player: PlayerCore {  pwc.player }
  var window: NSWindow? { pwc.window }
  var log: any Logger.Subsystem {  pwc.log }

  var playlistShown: Bool { pwc.musicModeGeo.isMusicModePlaylistShown }
  var isViewportShown: Bool {  pwc.musicModeGeo.isViewportShown }

  // MARK: - Initialization

  init() {
    let volumeSliderView = VolumeSliderView(volumeLabel: volumeLabel)
    self.volumeSliderView = volumeSliderView
    volumePopoverViewController = VolumePopoverContentViewController(volumeSliderView: volumeSliderView)
    volumePopover = NSPopover()
    super.init(nibName: nil, bundle: nil)
    volumePopover.contentViewController = volumePopoverViewController
  }
  
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()

    titleLabel.idString = "TitleLabel"
    artistAlbumLabel.idString = "ArtistAlbumLabel"

    /// `musicModeControlBarView` is always the same height
    musicModeControlBarView.heightAnchor.constraint(equalToConstant: Constants.MusicMode.oscHeight).isActive = true
    musicModeControlBarView.idString = "MusicModeControlBarView"
    positionSliderWrapperView.idString = "PositionSliderWrapperView"
    controllerButtonsPanelView.idString = "ControllerButtonsPanelView"

    mediaInfoView.idString = "MediaInfoView"
    // Clip scrolling text at the margins so it doesn't touch the sides of the window
    mediaInfoView.clipsToBounds = true
    mediaInfoView.translatesAutoresizingMaskIntoConstraints = false

    // hide controls initially
    controllerButtonsPanelView.alphaValue = 0

    // tool tips
    togglePlaylistButton.identifier = .init("TogglePlaylistButton")
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.displayString
    togglePlaylistButton.image = Preference.ToolBarButton.playlist.image()

    toggleAlbumArtButton.identifier = .init("ToggleAlbumArtButton")
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    toggleAlbumArtButton.image = Images.toggleAlbumArt

    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    volumeButton.identifier = .init("VolumeButton")
    pwc.exitMusicModeButton.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    view.addSubview(playlistWrapperView, positioned: .above, relativeTo: musicModeControlBarView)
    // Bottom constraint of playlist wrapper must be lower priority than window resize, to avoid constraint violations
    playlistWrapperView.addConstraintsToFillSuperview(bottom: 0, .init(499),
                                                      leading: 0, trailing: 0)
    playlistWrapperView.topAnchor.constraint(equalTo: musicModeControlBarView.bottomAnchor).isActive = true

    view.addSubview(playlistWrapperTopBorder, positioned: .above, relativeTo: playlistWrapperView)
    playlistWrapperTopBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    playlistWrapperTopBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    let playlistSeparator_TopConstraint = playlistWrapperTopBorder.topAnchor.constraint(equalTo: playlistWrapperView.topAnchor)
    playlistSeparator_TopConstraint.isActive = true
    let playlistSeparator_BtmConstraint = playlistWrapperTopBorder.bottomAnchor.constraint(equalTo: playlistWrapperView.topAnchor, constant: 0.5)
    playlistSeparator_BtmConstraint.isActive = true

    volumePopover.delegate = self

    log.verbose("MiniPlayer viewDidLoad done")
  }

  func updatePopupVolumeUI(volume: Double, _ volumeImage: NSImage?) {
    loadIfNeeded()
    volumeLabel.intValue = Int32(volume)
    volumeButton.image = volumeImage
  }

  // MARK: - UI: Controller

  func addPlaylistViewIfMissing() {
    // move playist view
    let playlistView = pwc.playlistView.view
    guard !playlistWrapperView.containsSubview(playlistView) else { return }
    log.verbose("MiniPlayer: adding playlistView")
    // Place below horizontal separator line
    playlistWrapperView.addSubview(playlistView, positioned: .below, relativeTo: nil)
    playlistView.addAllConstraintsToFillSuperview()
    playlistWrapperTopBorder.isHidden = false
  }

  func removePlaylistViewIfPresent() {
    let playlistView = pwc.playlistView.view
    guard playlistWrapperView.containsSubview(playlistView) else { return }
    log.verbose("MiniPlayer: removing playlistView")
    playlistView.removeFromSuperview()
    playlistWrapperTopBorder.isHidden = true
  }

  func showOrHideControls() {
    if pwc.isMouseCurrentlyInside(anyOf: [musicModeControlBarView, pwc.viewportView]) {
      showControls()
    } else {
      hideControls()
    }
  }

  private func showControlsInPipeline() {
    pwc.animationPipeline.submitTask(duration: Constants.AnimationDuration.musicModeShowButtons, { [self] in
      showControls()
    })
  }

  private func showControls() {
    log.trace("MiniPlayer: showing OSC controls / hiding media info")

    if let customTitleBar = pwc.customTitleBar {
      for btn in customTitleBar.trafficLightButtons {
        btn.alphaValue = 1
        btn.isHidden = false
      }
    }

    let trafficLightButtons = pwc.trafficLightButtons
    if trafficLightButtons.count >= 2 {
      for btn in trafficLightButtons[0...1] {
        btn.alphaValue = 1
        btn.isHidden = false
      }
    }

    pwc.exitMusicModeButton.isHidden = false
    pwc.exitMusicModeButton.alphaValue = 1

    controllerButtonsPanelView.alphaValue = 1
    mediaInfoView.alphaValue = 0
  }

  /// Hides media info, shows OSC controls (runs as async task in animationPipeline)
  private func hideControlsInPipeline() {
    guard pwc.isInMiniPlayer else { return }
    pwc.animationPipeline.submitTask(duration: Constants.AnimationDuration.musicModeShowButtons, { [self] in
      hideControls()
    })
  }

  /// Hides media info, shows OSC controls (synchronous version)
  func hideControls() {
    log.trace("MiniPlayer: hiding OSC controls / showing media info")

    if let customTitleBar = pwc.customTitleBar {
      for btn in customTitleBar.trafficLightButtons {
        btn.alphaValue = 0
        btn.isHidden = true
      }
    }

    for btn in pwc.trafficLightButtons {
      btn.alphaValue = 0
      btn.isHidden = true
    }

    pwc.exitMusicModeButton.isHidden = true
    pwc.exitMusicModeButton.alphaValue = 0

    controllerButtonsPanelView.alphaValue = 0
    mediaInfoView.alphaValue = 1
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
  @objc func hideVolumePopover() {
    volumePopover.animates = true
    volumePopover.performClose(self)
  }

  /// From `NSPopoverDelegate`: close volume popover
  func popoverWillClose(_ notification: Notification) {
    hideVolumePopoverTimer?.invalidate()
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControlsInPipeline()
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
      pwc.updateVolumeUI()
      volumePopover.show(relativeTo: volumePopoverAlignmentView.bounds, of: volumePopoverAlignmentView,
                         preferredEdge: .minY)
    }
  }

  /// Action: Show/Hide playlist
  @IBAction func togglePlaylist(_ sender: AnyObject?) {
    pwc.animationPipeline.submitInstantTask({ [self] in
      let gtf = GeometryTransform("TogglePlaylist", player,
                                  windowed: { [self] ctx -> PWinGeometry? in
        // music mode only. Other modes should fall back to default
        guard ctx.inputLayout.mode == .musicMode, ctx.outputLayout.mode == .musicMode else { return nil }

        let inputMusicModeGeo = ctx.inputGeoSet.musicMode
        let outputMusicModeGeo = inputMusicModeGeo.withPlaylistShown(!inputMusicModeGeo.isMusicModePlaylistShown)
        log.verbose("MusicMode: toggling playlist visibility: \(inputMusicModeGeo.isMusicModePlaylistShown.yesno) → \(outputMusicModeGeo.isMusicModePlaylistShown.yesno), H=\(outputMusicModeGeo.musicModePlaylistHeight)")
        return outputMusicModeGeo
      })
      gtf.submit()
    })
  }

  /// Action: Show/Hide `videoView` (same as hiding `viewportView`)
  @IBAction func toggleVideoViewVisibleState(_ sender: AnyObject?) {
    pwc.animationPipeline.submitInstantTask({ [self] in
      let showViewport = !isViewportShown
      log.verbose("MusicMode: user clicked btn: toggling viewport visibility: \((!showViewport).yn) → \(showViewport.yn)")

      if showViewport {
        /// If showing video, call `setVideoTrackEnabled()`, then do animations, for a nicer effect.
        player.setVideoTrackEnabled(thenDoAction: .showViewportInMusicMode)
      } else {
        // Hiding video.

        /// This will call `applyPWinGeometry`, which will call `setVideoTrackDisabled`
        /// (we want to wait until the animation is done before disabling video).
        /// Use `GeometryTransform` to stay consistent with "ShowVideo" which needs a GTF.
        // TODO: develop a nicer sliding animation if possible. Will need a lot of changes to constraints :/
        let gtf = GeometryTransform("HideViewport", player,
                                    windowed: { [self] ctx -> PWinGeometry? in
          // music mode only. Other modes should fall back to default
          guard ctx.inputLayout.mode == .musicMode, ctx.outputLayout.mode == .musicMode else { return nil }

          let inputMusicModeGeo = ctx.inputGeoSet.musicMode
          let outputMusicModeGeo = inputMusicModeGeo.withViewportVisible(false)
          log.verbose("MusicMode: changing viewport visibility: \(inputMusicModeGeo.isViewportShown.yesno) → \(outputMusicModeGeo.isViewportShown.yesno), H=\(outputMusicModeGeo.videoHeight)")
          return outputMusicModeGeo
        })
        gtf.submit()
      }
    })
  }

  // MARK: - Window size & layout

  static func buildMusicModeGeometryFromPrefs(screen: NSScreen, video: VideoGeometry) -> PWinGeometry {
    // Default to left-top of screen. Try to use last-saved playlist height and visibility settings.
    let playlistShown = Preference.bool(for: .musicModeShowPlaylist)
    let isViewportShown = Preference.bool(for: .musicModeShowAlbumArt)
    let desiredPlaylistHeight = CGFloat(Preference.float(for: .musicModePlaylistHeight))
    let desiredWindowWidth = Constants.MusicMode.defaultWindowWidth
    let desiredVideoHeight = isViewportShown ? round(desiredWindowWidth / video.videoAspectCAR) : 0
    let desiredWindowHeight = desiredVideoHeight + Constants.MusicMode.oscHeight + (playlistShown ? desiredPlaylistHeight : 0)

    let screenFrame = screen.visibleFrame
    let windowSize = NSSize(width: desiredWindowWidth, height: desiredWindowHeight)
    let windowOrigin = NSPoint(x: screenFrame.origin.x, y: screenFrame.maxY - windowSize.height)
    let windowFrame = NSRect(origin: windowOrigin, size: windowSize)
    let desiredGeo = PWinGeometry.forMusicMode(windowFrame: windowFrame, screenID: screen.screenID, video: video,
                                               isViewportShown: isViewportShown, playlistShown: playlistShown)
    // Resize as needed to fit on screen:
    return desiredGeo.refitted()
  }
}
