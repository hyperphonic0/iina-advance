//
//  PWin_PIP.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-08.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

enum PIPStatus {
  case notInPIP
  case inPIP
  case intermediate
}

/// Picture in Picture handling for a single player window
extension PlayerWindowController {

  class PIPOverlayView: ClickThroughVisualEffectView {
    let pipImageView = NSImageView()
    let label = NSTextField(labelWithString: "This video is playing in Picture-in-Picture")

    init() {
      super.init(frame: .zero)
      idString = "PIPOverlay"
      blendingMode = .behindWindow
      material = .underWindowBackground
      state = .active
      translatesAutoresizingMaskIntoConstraints = false

      subviews = [pipImageView, label]

      pipImageView.imageScaling = .scaleProportionallyDown
      pipImageView.imageFrameStyle = .none
      pipImageView.refusesFirstResponder = true
      pipImageView.image = NSImage(named: "playing-in-pip")
      pipImageView.animates = true
      pipImageView.alignment = .center
      pipImageView.translatesAutoresizingMaskIntoConstraints = false
      pipImageView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
      pipImageView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

      label.idString = "PIPOverlayLabel"
      label.translatesAutoresizingMaskIntoConstraints = false
      label.setContentHuggingPriority(.required, for: .horizontal)
      label.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
      label.topAnchor.constraint(equalTo: pipImageView.bottomAnchor, constant: 8).isActive = true
    }
    
    @MainActor required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  /// `PIPState`: Encapsulates all state for PiP.
  class PIPState {
    unowned var player: PlayerCore
    var log: Logger.Subsystem { player.log }
    var pwc: PlayerWindowController { player.pwc }

    /// Needs to be retained during PiP, but cannot be reused
    var videoController: NSViewController!

    let overlayView = PIPOverlayView()

    var controller: PIPViewController { _pip }
    lazy var _pip: PIPViewController = {
      let pip = VideoPIPViewController()
      pip.delegate = pwc
      return pip
    }()

    init(_ player: PlayerCore) {
      self.player = player
    }

    /// Hide PiP overlay if in PiP and during animation. Show overlay if PiP shown.
    func showOrHidePipOverlayView() {
      let mustHide: Bool
      if pwc.currentLayout.isInPiP {
        mustHide = pwc.isInMiniPlayer && !pwc.musicModeGeo.isViewportShown
      } else {
        mustHide = true
      }

      log.verbose{"\(mustHide ? "Hiding" : "Showing") PiP overlay"}
      if mustHide {
        overlayView.removeFromSuperview()
      } else {
        guard !pwc.viewportView.containsSubview(overlayView) else { return }

        pwc.viewportView.addSubview(overlayView)
        overlayView.addAllConstraintsToFillSuperview()
        pwc.sortViewportViewSubviews()
      }
    }

  }
}

extension PlayerWindowController: PIPViewControllerDelegate {

  func enterPIP(usePipBehavior preferredPipBehavior: Preference.WindowBehaviorWhenPip? = nil, then doOnSuccess: (() -> Void)? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Exit interactive mode before even entering intermediate status
    exitInteractiveMode(then: { [self] in

      if Preference.bool(for: .lockViewportToVideoSize) {
        _enterPIP(usePipBehavior: preferredPipBehavior, then: doOnSuccess)
      } else {
        // The PiP entry animation uses the size of the VideoView to determine what to show going to PiP.
        // But if lockViewportToVideoSize==true, VideoView may also include black margins. So first silently
        // reduce the size of VideoView to the size of the video.
        let taskDuration = Constants.AnimationDuration.enterPIPTask
        let tx = IINAAnimation.Transaction()
        tx.append(duration: taskDuration) { [self] in
          videoView.activateForcedRedraws()
          let currentGeo = currentLayout.mode == .musicMode ? musicModeGeoForCurrentFrame() : windowedGeoForCurrentFrame()
          setFrameAndUpdateWindowSubviews(using: currentGeo, .enteringPIP)
        }
        tx.append(duration: taskDuration) { [self] in
          _enterPIP(usePipBehavior: preferredPipBehavior, then: doOnSuccess)
        }
        animationPipeline.submit(tx)
      }

    })
  }

  private func _enterPIP(usePipBehavior: Preference.WindowBehaviorWhenPip?, then doOnSuccess: (() -> Void)?) {
    // Must not try to enter PiP if already in PiP - will crash!
    guard let window else { return }

    if !player.info.isVideoTrackSelected {
      log.debug("Aborting request for PIP entry: no video track selected!")
      return
    }

    if isInMiniPlayer {
      miniPlayer.loadIfNeeded()
      if !miniPlayer.isViewportShown {
        log.debug("Aborting request for PIP entry: in music mode with viewport disabled")
        return
      }
    }

    let isRestoring = player.isRestoring
    if isRestoring {
      log.debug("Skipping validation & state updates prior to entering PiP due to restore")
    } else {
      let inputLayout = currentLayout
      guard !inputLayout.isInPiP else {
        log.debug("Aborting request for PIP entry: already in PiP")
        return
      }

      let outputLayout = inputLayout.clone(isInPiP: true)
      guard outputLayout.isInPiP else {
        log.debug("Aborting request for PIP entry: current layout does not support PiP")
        return
      }

      currentLayout = outputLayout
    }

    log.verbose("Entering PiP")
    PlayerManager.shared.pipPlayer = player

    do {
      videoView.lockAndSetOpenGLContext()
      defer { videoView.unlockOpenGLContext() }

      pip.videoController = NSViewController()
      pip.videoController.view = videoView

      // Remove remaining constraints. The PiP superview will manage videoView's layout.
      viewportView.removeViewportConstraints()
      videoView.layer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
      viewportView.removeSpacers()

      pip.controller.playing = player.info.isPlaying
      pip.controller.title = window.title
      let aspectRatioSize = player.videoGeo.videoSizeCAR
      log.verbose{"Setting PiP aspect to \(aspectRatioSize.aspect)"}
      pip.controller.aspectRatio = aspectRatioSize

      pip.controller.presentAsPicture(inPicture: pip.videoController)
      pip.showOrHidePipOverlayView()
    }

    if !window.styleMask.contains(.fullScreen) && !window.isMiniaturized {
      let pipBehavior = usePipBehavior ?? Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
      log.verbose{"Entering PIP with behavior: \(pipBehavior)"}
      switch pipBehavior {
      case .doNothing:
        break
      case .hide:
        isWindowHidden = true
        window.orderOut(self)
        log.verbose{"PIP entered; adding player to hidden windows list: \(window.savedStateName.quoted)"}
        if player.isRestoring, AppDelegate.shared.startupHandler.wcsToRestore.contains(self) {
          // patch logic hole here
          AppDelegate.shared.startupHandler.wcsDoneWithRestore.insert(self)
        }
        break
      case .minimize:
        isWindowMiniaturizedDueToPip = true
        /// No need to add to `AppDelegate.windowsMinimized` - it will be handled by app-wide listener
        window.miniaturize(self)
        break
      }
      if Preference.bool(for: .pauseWhenPip) {
        player.pause()
      }
    }

    videoView.forceDraw()
    player.saveState()
    player.events.emit(.pipChanged, data: true)

    if let doOnSuccess {
      doOnSuccess()
    }
  }

  /// Need to use `force: true` when calling this from within a `LayoutTransition`, because it will independently
  /// update `currentLayout` with `isInPiP==false` prior to calling this.
  func exitPIP(force: Bool = false) {
    guard force || currentLayout.isInPiP else { return }
    guard !player.isRestoring else {
      log.verbose("Skipping PIP exit because we are still restoring")
      return
    }
    log.verbose("Exiting PIP, forced=\(force.yn)")
    prepareForPIPClosure(pip.controller)

    // Prod Swift to pick the dismiss(_ viewController: NSViewController)
    // overload over dismiss(_ sender: Any?). A change in the way implicitly
    // unwrapped optionals are handled in Swift means that the wrong method
    // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
    pip.controller.dismiss(pip.videoController!)
    player.events.emit(.pipChanged, data: false)
  }

  /// This is called right before we're about to close the PIP.
  private func prepareForPIPClosure(_ pipController: PIPViewController) {
    guard let window = window else { return }
    let inputLayout = currentLayout
    log.verbose("Preparing for PIP closure (will update currentLayout: \(inputLayout.isInPiP.yn))")
    if inputLayout.isInPiP {
      let outputLayout = inputLayout.clone(isInPiP: false)
      currentLayout = outputLayout
    }
    // Hide the overlay view preemptively, to prevent any issues where it does
    // not hide in time and ends up covering the video view (which will be added
    // to the window under everything else, including the overlay).
    pip.showOrHidePipOverlayView()

    if AppDelegate.shared.isTerminating {
      // Don't bother restoring window state past this point
      return
    }

    // Set frame to animate back to
    let currentGeo = currentLayout.mode == .musicMode ? musicModeGeoForCurrentFrame() : windowedGeoForCurrentFrame()
    pipController.replacementRect = currentGeo.videoFrameInWindowCoords
    pipController.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    if isWindowMiniturized {
      window.deminiaturize(pipController)
    } else {
      // Bring to front so it is more obvious which window is relevant:
      window.makeKeyAndOrderFront(pipController)
    }
  }

  /// Called from PiP controller?
  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  /// Called from PiP controller?
  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    prepareForPIPClosure(pip)
    return true
  }

  func pipDidClose(_ pipController: PIPViewController) {
    guard !AppDelegate.shared.isTerminating else { return }
    guard !isClosing else { return }  // if window is closing, let windowWillClose handle it
    guard let window else { return }

    // seems to require separate animation blocks to work properly
    var tasks: [IINAAnimation.Task] = []

    if isWindowHidden {
      log.verbose{"PIP did close: appending extra tasks for hidden window"}
      tasks.append(contentsOf: buildApplyPWinGeoTasks(from: windowedModeGeo, to: windowedModeGeo)) // may have skipped updates while hidden
      tasks.append(IINAAnimation.Task({ [self] in
        showWindow(self)

        log.verbose{"PIP did close; removing player from hidden windows list: \(window.savedStateName.quoted)"}
        isWindowHidden = false
      }))
    }

    tasks.append(.instantTask { [self] in
      let currentGeo = currentLayout.mode == .musicMode ? musicModeGeoForCurrentFrame() : windowedGeoForCurrentFrame()
      if currentGeo.isViewportShown {
        addViewportAndSubviewsToWindowIfNeeded()
        viewportView.apply(currentGeo)
      }

      if isInMiniPlayer {
        miniPlayer.loadIfNeeded()
        if miniPlayer.isViewportShown {
          player.setVideoTrackEnabled()
        } else {
          player.setVideoTrackDisabled()
        }

      }

      // If using legacy windowed mode, need to manually add title to Window menu & Dock
      updateTitle()
    })

    tasks.append(.instantTask { [self] in
      // Similarly, we need to run a redraw here as well. We check to make sure we
      // are paused, because this causes a janky animation in either case but as
      // it's not necessary while the video is playing and significantly more
      // noticeable, we only redraw if we are paused.
      videoView.forceDraw()

      fadeableViews.hideTimer.restart()

      isWindowMiniaturizedDueToPip = false
      player.saveState()
    })

    animationPipeline.submit(tasks)
  }

  func pipActionPlay(_ pipController: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pipController: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pipController: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }
}
