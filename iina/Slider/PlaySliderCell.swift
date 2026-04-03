//
//  PlaySliderCell.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

/// The cell for the play slider.
///
/// This slider adds two thumbs (referred to as knobs in code) to the progress bar slider to show the A and B loop points of the
/// [mpv](https://mpv.io/manual/stable/) A-B loop feature and allow the loop points to be adjusted. When the feature is
/// disabled the additional thumbs are hidden.
/// - Requires: The custom slider cell provided by `PlaySliderCell` **must** be used with this class.
/// - Note: Unlike `NSSlider` the `draw` method of this class will do nothing if the view is hidden.
class PlaySliderCell: ScrollableSliderCell {
  /// Knob representing the A loop point for the mpv A-B loop feature.
  var abLoopA: PlaySliderLoopKnob { abLoopAKnob! }

  /// Knob representing the B loop point for the mpv A-B loop feature.
  var abLoopB: PlaySliderLoopKnob { abLoopBKnob! }

  var knobRenderer: KnobRenderer { pwc!.oscKnobRenderer }

  var hoverIndicator: SliderHoverIndicator! {
    willSet {
      // Make sure to remove constraints & other cleanup!
      if newValue != hoverIndicator {
        hoverIndicator?.dispose()
      }
    }
  }

  var drawChapters = Preference.bool(for: .showChapterPos)

  var wasPausedBeforeSeeking = false

  var isDraggingLoopKnob: Bool {
    guard let pwc else { return false }
    return pwc.currentDragObject == abLoopA || pwc.currentDragObject == abLoopB
  }

  // MARK:- Private Properties

  private var abLoopAKnob: PlaySliderLoopKnob?

  private var abLoopBKnob: PlaySliderLoopKnob?

  override var wantsKnob: Bool {
    guard let pwc else { return false }
    let alwaysShowKnob = Preference.bool(for: .alwaysShowSliderKnob) || !pwc.currentLayout.useSliderFocusEffect
    return alwaysShowKnob || wantsFocusEffect
  }

  var wantsFocusEffect: Bool {
    guard let pwc else { return false }
    return Preference.bool(for: .useSliderFocusMagnifyEffect) && pwc.currentLayout.useSliderFocusEffect && (pwc.isScrollingOrDraggingPlaySlider || pwc.seekPreview.animationState == .shown)
  }

  func initLoopKnobs() {
    abLoopAKnob = PlaySliderLoopKnob(sliderCell: self, toolTip: "A-B loop A")
    abLoopBKnob = PlaySliderLoopKnob(sliderCell: self, toolTip: "A-B loop B")
  }

  // MARK:- Displaying the Cell

  override func drawBar(inside barRect: NSRect, flipped: Bool) {
    guard let pwc else { return }
    abLoopAKnob?.updateHorizontalPosition()
    abLoopBKnob?.updateHorizontalPosition()

    let scaleFactor: CGFloat = slider.window?.screen?.backingScaleFactor ?? Constants.defaultBackingScaleFactor
    let appearance = sliderAppearance ?? slider.effectiveAppearance
    guard let br = pwc.oscBarRenderer else { return }

    /// The position of the knob, rounded for cleaner drawing. If `width==0`, do not draw knob.
    let knobRect = knobRect(flipped: false)

    let durationSec = player.info.playbackTime.durationSec ?? 0.0
    let currentValueSec = slider.progressRatio * durationSec
    let chapters = drawChapters ? player.info.chapters : []
    let cachedRanges = player.info.cacheState.cachedRanges  // will be empty if drawing cache is disabled

    // Disable hover zoom effect & indicator while actively scrolling; looks bad
    let currentPreviewTimeSec: Double? = pwc.isScrollingOrDraggingPlaySlider ? nil : pwc.seekPreview.currentPreviewTimeSec

    appearance.performAsCurrentDrawingAppearance {
      let drawShadow = hasClearBG
      let playBarImg = br.buildPlayBarImage(useFocusEffect: wantsFocusEffect,
                                            barWidth: barRect.width,
                                            scaleFactor: scaleFactor,
                                            knobRect: knobRect,
                                            currentValueSec: currentValueSec, maxValueSec: durationSec,
                                            currentPreviewTimeSec: currentPreviewTimeSec,
                                            chapters, cachedRanges: cachedRanges)

      br.drawBar(playBarImg, in: barRect, scaleFactor: scaleFactor,
                 tallestBarHeight: br.maxPlayBarHeightNeeded, drawShadow: drawShadow)
    }
  }

  func showHoverIndicator(atSliderCoordX x: CGFloat) {
    guard let scaleFactor = slider.window?.screen?.backingScaleFactor,
          let sliderAppearance = sliderAppearance,
          let pwc else { return }

    guard let hoverIndicator else {
      // Probably init is done yet. If so, it should be soon enough to ignore for now
      pwc.player.log.verbose("PlaySlider.showHoverIndicator: hoverIndicator is nil, ignoring")
      return
    }

    // Do not draw over the main knob, or AB loop knobs
    if wantsKnob {
      let knobRect = knobRect(flipped: slider.isFlipped)
      if x.isBetweenInclusive(knobRect.minX, and: knobRect.maxX) {
        hoverIndicator.isHidden = true
        return
      }
    }

    guard !isDraggingLoopKnob else {
      hoverIndicator.isHidden = true
      return
    }

    if let abLoopAKnob, !abLoopAKnob.isHidden {
      let knobCenterX = abLoopAKnob.x
      let halfWidth = loopKnobWidth * 0.5
      if x.isBetweenInclusive(knobCenterX - halfWidth, and: knobCenterX + halfWidth) {
        hoverIndicator.isHidden = true
        return
      }
    }
    if let abLoopBKnob, !abLoopBKnob.isHidden {
      let knobCenterX = abLoopBKnob.x
      let halfWidth = loopKnobWidth * 0.5
      if x.isBetweenInclusive(knobCenterX - halfWidth, and: knobCenterX + halfWidth) {
        hoverIndicator.isHidden = true
        return
      }
    }

    if hoverIndicator.imgLayer.contentsScale != scaleFactor {
      let oscGeo = pwc.currentLayout.controlBarGeo
      hoverIndicator.update(scaleFactor: scaleFactor, oscGeo: oscGeo, isDark: sliderAppearance.isDark)
    }

    hoverIndicator.show(atSliderCoordX: x)
  }

  func syncABLoop(_ info: PlaybackInfo, a: Double, b: Double) {
    let hideA = a == 0
    abLoopA.isHidden = hideA
    abLoopA.posInSliderPercent = info.playbackTime.secondsToPercent(a)

    let hideB = b == 0
    abLoopB.isHidden = hideB
    abLoopB.posInSliderPercent = info.playbackTime.secondsToPercent(b)

    slider.needsDisplay = true
  }

  func updateHoverIndicator(scaleFactor: CGFloat, oscGeo: ControlBarGeometry, isDark: Bool) {
    if let hoverIndicator {
      hoverIndicator.update(scaleFactor: scaleFactor, oscGeo: oscGeo, isDark: isDark)
    } else {
      hoverIndicator = SliderHoverIndicator(slider: slider, oscGeo: oscGeo, scaleFactor: scaleFactor, isDark: isDark)
    }
  }

  // MARK:- Tracking the Mouse

  override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
    player.log.verbose("PlaySlider drag-to-seek began")
    wasPausedBeforeSeeking = player.info.isPaused
    let result = super.startTracking(at: startPoint, in: controlView)
    if result {
      player.pause()
    }
    slider.needsDisplay = true
    return result
  }

  override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
    player.log.verbose("PlaySlider drag-to-seek ended")
    super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    slider.needsDisplay = true
    if !wasPausedBeforeSeeking {
      player.resume()
    }
  }
}
