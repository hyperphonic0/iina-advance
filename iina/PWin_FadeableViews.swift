//
//  PWin_FadeableViews.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// This file encapsulates logic to:
/// - Show/hide fadeable views (AKA "fadeables", AKA "inside panels").
/// - Show/hide default album art
extension PlayerWindowController {

  class FadeableViewsHandler {

    /// Views that will show/hide when cursor moving in/out of the window
    var fadeables = Set<NSView>()
    /// Similar to `fadeables`, but may fade in differently depending on configuration of top bar.
    var fadeablesInTopBar = Set<NSView>()
    var animationState: UIAnimationState = .shown
    var topBarAnimationState: UIAnimationState = .shown

    var isShowingFadeableViewsForSeek = false

    /// For auto hiding UI after a timeout.
    /// Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    let hideTimer = TimeoutTimer(timeout: max(Constants.TimeInterval.fadeableViewsTimeoutMin, Double(Preference.float(for: .controlBarAutoHideTimeout))))

    @Atomic fileprivate(set) var showHideTicketCount: Int = 0
    /// Need to carry an extra bit of info for this
    fileprivate var pendingShowTopPanel: Bool = false

    func applyVisibility(_ visibility: VisibilityMode, to fadeableView: NSView) {
      switch visibility {
      case .hidden:
        fadeableView.alphaValue = 0
        fadeableView.isHidden = true
        fadeables.remove(fadeableView)
        fadeablesInTopBar.remove(fadeableView)
      case .showAlways:
        fadeableView.alphaValue = 1
        fadeableView.isHidden = false
        fadeables.remove(fadeableView)
        fadeablesInTopBar.remove(fadeableView)
      case .showFadeableTopBar:
        fadeableView.alphaValue = 1
        fadeableView.isHidden = false
        fadeablesInTopBar.insert(fadeableView)
      case .showFadeableNonTopBar:
        fadeableView.alphaValue = 1
        fadeableView.isHidden = false
        fadeables.insert(fadeableView)
      }
    }

    func applyVisibility(_ visibility: VisibilityMode, _ views: NSView?...) {
      for fadeableView in views {
        if let fadeableView {
          applyVisibility(visibility, to: fadeableView)
        }
      }
    }

    func applyOnlyIfHidden(_ visibility: VisibilityMode, to fadeableView: NSView, isTopBar: Bool = true) {
      guard visibility == .hidden else { return }
      applyVisibility(visibility, fadeableView)
    }

    func applyOnlyIfShowable(_ visibility: VisibilityMode, to fadeableView: NSView, isTopBar: Bool = true) {
      guard visibility != .hidden else { return }
      applyVisibility(visibility, fadeableView)
    }

  }  // end class FadeableViewsHandler


  // MARK: - PlayerWindowController

  /// Shows fadeables via fade-in animation
  func showFadeableViews(thenRestartFadeTimer restartFadeTimer: Bool = true,
                         duration: CGFloat = Constants.AnimationDuration.standard,
                         forceShowTopBar: Bool = false) {
    guard !player.disableUI && !isInInteractiveMode else { return }

    /// Default `showTopBarTrigger` setting to `.windowHover` if advanced settings not enabled
    let wantsTopBarVisible = forceShowTopBar || (!Preference.isAdvancedEnabled || Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.windowHover)

    guard wantsTopBarVisible || fadeableViews.animationState == .hidden else {
      if restartFadeTimer {
        fadeableViews.hideTimer.restart()
      } else {
        fadeableViews.hideTimer.cancel()
      }
      return
    }

    let currentTicket = fadeableViews.$showHideTicketCount.withLock {
      $0 += 1
      return $0
    }

    let firstTask = IINAAnimation.Task.instantTask { [self] in
      if log.isTraceEnabled {
        log.trace("SHOW fadeables: currentTicket=\(currentTicket), latest=\(fadeableViews.showHideTicketCount)")
      }
      guard currentTicket == fadeableViews.showHideTicketCount else {
        if wantsTopBarVisible {
          fadeableViews.pendingShowTopPanel = true
        }
        throw IINAError.cancelAnimationTransaction
      }
    }

    let moreTasks = buildAnimationToShowFadeableViews(restartFadeTimer: restartFadeTimer,
                                                      duration: duration,
                                                      forceShowTopBar: wantsTopBarVisible)


    animationPipeline.submit([firstTask] + moreTasks)
  }

  /// This is only expected to be called by `showFadeableViews()` and by the animation transition builder. Do not call directly from elsewhere.
  func buildAnimationToShowFadeableViews(restartFadeTimer: Bool = true,
                                         duration: CGFloat = Constants.AnimationDuration.standard,
                                         forceShow: Bool = false,
                                         forceShowTopBar: Bool = false) -> [IINAAnimation.Task] {

    let currentLayout = self.currentLayout

    return [
      IINAAnimation.Task(duration: duration, { [self] in
        // Note to Future Self: stop messing with this logic! It works fine and is fast enough!
        if forceShow {
          // Invalidate any pending hides
          fadeableViews.$showHideTicketCount.withLock { $0 += 1 }
        } else {
          guard fadeableViews.animationState == .hidden || fadeableViews.animationState == .shown else {
            throw IINAError.cancelAnimationTransaction
          }
        }

        fadeableViews.animationState = .willShow
        player.refreshSyncUITimer(logMsg: "Showing fadeable views ")
        fadeableViews.hideTimer.cancel()

        for v in fadeableViews.fadeables {
          v.animator().alphaValue = 1
        }

        let pendingShowTopPanel = fadeableViews.pendingShowTopPanel
        let wantsTopBarVisible = forceShowTopBar || pendingShowTopPanel
        if wantsTopBarVisible {  // start top bar
          fadeableViews.pendingShowTopPanel = false
          fadeableViews.topBarAnimationState = .willShow
          for v in fadeableViews.fadeablesInTopBar {
            v.animator().alphaValue = 1
          }

          if currentLayout.titleBar == .showFadeableTopBar {
            if currentLayout.spec.isLegacyStyle {
              customTitleBar?.view.animator().alphaValue = 1
            } else {
              for button in trafficLightButtons {
                button.alphaValue = 1
              }
              titleTextField?.alphaValue = 1
              documentIconButton?.alphaValue = 1
            }
          }
        }  // end top bar
      }),

      // Not animated, but needs to wait until after fade is done
      .instantTask { [self] in
        fadeableViews.animationState = .shown
        // Do not cache fadeables for show. But cache them for hide (ensures additionalInfoView is shown/hidden correctly).
        for v in fadeableViews.fadeables {
          v.isHidden = false
        }

        if restartFadeTimer {
          fadeableViews.hideTimer.restart()
        }

        if fadeableViews.topBarAnimationState == .willShow {
          fadeableViews.topBarAnimationState = .shown
          for v in fadeableViews.fadeablesInTopBar {
            v.isHidden = false
          }

          if currentLayout.titleBar == .showFadeableTopBar {
            if currentLayout.spec.isLegacyStyle {
              customTitleBar?.view.isHidden = false
            } else {
              for button in trafficLightButtons {
                button.isHidden = false
              }
              titleTextField?.isHidden = false
              documentIconButton?.isHidden = false
            }
          }
        }  // end top bar
      }  // end Task

    ]
  }

  func hideFadeableViews(hideCursorToo: Bool = false) {
    // Don't hide overlays when in PIP or when they are not actually shown
    let isWindowMinimized = window?.isMiniaturized ?? false
    guard pip.status == .notInPIP, !isWindowMinimized else {
      log.trace{"Aborting hide of fadeable views: pipStatus=\(pip.status), windowMinimized=\(isWindowMinimized)"}
      return
    }

    // Don't hide UI when auto hide control bar is disabled
    assert(Preference.bool(for: .enableControlBarAutoHide)
           || Preference.bool(for: .hideFadeableViewsWhenOutsideWindow)
           || Preference.enum(for: .singleClickAction) == Preference.MouseClickAction.hideOSC)

    let currentTicket = fadeableViews.$showHideTicketCount.withLock {
      $0 += 1
      return $0
    }

    // Seek time & thumbnail can only be shown if the OSC is visible.
    // Need to hide them because the OSC is being hidden:
    let mustHideSeekPreview = !currentLayout.hasPermanentControlBar
    var fadeables: Set<NSView> = []
    var fadeablesInTopBar: Set<NSView> = []

    let preTask = IINAAnimation.Task.instantTask{ [self] in
      if log.isTraceEnabled {
        log.trace{"HIDE fadeables: currentTicket=\(currentTicket), latest=\(fadeableViews.showHideTicketCount)"}
      }

      // Ensure we are the most current ticket
      guard currentTicket == fadeableViews.showHideTicketCount else {
        throw IINAError.cancelAnimationTransaction
      }
      guard fadeableViews.animationState == .shown else { return }

      // Do not allow more tasks to be enqueued between now & the first task execution:
      fadeableViews.hideTimer.cancel()
    }

    let fadeTask = IINAAnimation.Task(duration: Constants.AnimationDuration.standard) { [self] in
      if hideCursorToo {
        hideCursor()
      }
      fadeableViews.animationState = .willHide
      fadeableViews.topBarAnimationState = .willHide
      player.refreshSyncUITimer(logMsg: "Hiding fadeable views ")

      // Wait until here to build set! To avoid race
      fadeables = fadeableViews.fadeables
      fadeablesInTopBar = fadeableViews.fadeablesInTopBar

      for v in fadeables {
        v.animator().alphaValue = 0
      }
      for v in fadeablesInTopBar {
        v.animator().alphaValue = 0
      }
      /// Quirk 1: special handling for `trafficLightButtons`
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.alphaValue = 0
        } else {
          documentIconButton?.alphaValue = 0
          titleTextField?.alphaValue = 0
          for button in trafficLightButtons {
            button.alphaValue = 0
          }
        }
      }

      if mustHideSeekPreview {
        // Hide seek preview & thumbnail
        seekPreview.hideTimer.cancel()
        seekPreview.animationState = .willHide
        seekPreview.thumbnailPeekView.animator().alphaValue = 0
        seekPreview.timeLabel.animator().alphaValue = 0
      }
    }

    let postTask = IINAAnimation.Task.instantTask { [self] in
      // if no interrupt then hide animation
      guard fadeableViews.animationState == .willHide else {
        assert(false, "Expected fadeableViews.animationState to be .willHide; but found \(fadeableViews.animationState)")
        return
      }

      fadeableViews.animationState = .hidden
      fadeableViews.topBarAnimationState = .hidden
      for v in fadeables {
        v.isHidden = true
      }
      for v in fadeablesInTopBar {
        v.isHidden = true
      }
      /// Quirk 1: need to set `alphaValue` back to `1` so that each button's corresponding menu items still work
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.isHidden = true
        } else {
          hideBuiltInTitleBarViews(setAlpha: false)
        }
      }

      if mustHideSeekPreview, seekPreview.animationState == .willHide {
        log.trace("Hiding SeekPreview from fadeable views timeout")
        hideSeekPreviewImmediately()
      }
    }

    animationPipeline.submit([preTask, fadeTask, postTask])
  }

  /// Executed when `fadeableViews.hideTimer` fires
  @objc func hideFadeableViewsAndCursor() {
    // don't hide UI when dragging control bar
    if currentDragObject != nil {
      log.trace{"Aborting hide of fadeable views: dragObject != nil"}
      return
    }

    hideFadeableViews(hideCursorToo: true)
  }

  // MARK: - Default album art visibility

  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let showDefaultArt else { return }

    log.verbose{"\(showDefaultArt ? "Showing" : "Hiding") defaultAlbumArt, state=\(player.info.currentPlayback?.state.description ?? "nil")"}
    // Update default album art visibility:
    defaultAlbumArtView.isHidden = !showDefaultArt
  }

}
