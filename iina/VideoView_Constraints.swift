//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

fileprivate let musicMode = false // TODO: improvements for music mode (search for this)

extension VideoView {

  /// Only called once, at VideoView init
  func initConstraints() {
    translatesAutoresizingMaskIntoConstraints = false
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentHuggingPriority(.defaultLow, for: .vertical)
  }

  /// Convenience property
  var aspectMultiplier: CGFloat? {  videoViewConstraints?.aspectRatio.multiplier }


  // MARK: - VideoViewConstraints

  struct VideoViewConstraints {
    let log: Logger.Subsystem

    let topSpacerConnection: NSLayoutConstraint
    let bottomSpacerConnection: NSLayoutConstraint
    let leadingSpacerConnection: NSLayoutConstraint
    let trailingSpacerConnection: NSLayoutConstraint

    let topSpacerMax: NSLayoutConstraint
    let trailingSpacerMax: NSLayoutConstraint
    let bottomSpacerMax: NSLayoutConstraint
    let leadingSpacerMax: NSLayoutConstraint

    // these allow for minimum or required margins
    let topSpacerMin: NSLayoutConstraint
    let trailingSpacerMin: NSLayoutConstraint
    let bottomSpacerMin: NSLayoutConstraint
    let leadingSpacerMin: NSLayoutConstraint

    // these are weaker than the above, and can be used to suggest video avoids sidebars
    let topSpacerPreferred: NSLayoutConstraint
    let trailingSpacerPreferred: NSLayoutConstraint
    let bottomSpacerPreferred: NSLayoutConstraint
    let leadingSpacerPreferred: NSLayoutConstraint

    let widthMax: NSLayoutConstraint
    let heightMax: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
    // These can be adjusted to keep VideoView away from "inside" bars.
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint

    let aspectRatio: NSLayoutConstraint

#if TEST_VIDEO_CONSTRAINTS
    // Margins should most want to equal 0:
    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    let ltOffsetTop: NSLayoutConstraint
    let ltOffsetTrailing: NSLayoutConstraint
    let ltOffsetBottom: NSLayoutConstraint
    let ltOffsetLeading: NSLayoutConstraint

    let centerX2: NSLayoutConstraint
    let centerY2: NSLayoutConstraint

    let widthMin: NSLayoutConstraint
    let heightMin: NSLayoutConstraint
#endif

    /// UPDATE FUNC
    fileprivate func update(connectSpacers_Active: Bool, connectSpacers_Priority: NSLayoutConstraint.Priority,
                            aspectMultiplier: CGFloat, aspect_Priority: NSLayoutConstraint.Priority,
                            wMax: CGFloat? = nil, hMax: CGFloat? = nil, whMax_Priority: NSLayoutConstraint.Priority,
                            spacerMax_Active: Bool, spacerMax_Priority: NSLayoutConstraint.Priority,
                            spacerMin: MarginQuad?, spacerMin_Priority: NSLayoutConstraint.Priority,
                            spacerPreferred: MarginQuad?, spacerPreferred_Priority: NSLayoutConstraint.Priority,
                            center_Active: Bool, center_Priority: NSLayoutConstraint.Priority) {

      let aspect_Active = aspectMultiplier > 0.0
      log.verbose{"Δ VideoView constraints ≔ maxSize: {w=\(wMax?.description ?? "nil") from super.w, h=\(hMax?.description ?? "nil") from super.h}@\(whMax_Priority.rawValue) spacers:{max=\(spacerMax_Active.yn)@\(spacerMax_Priority.rawValue) min=\(spacerMin?.description ?? "nil")@\(spacerMin_Priority.rawValue) pref=\(spacerPreferred?.description ?? "nil")@\(spacerPreferred_Priority.rawValue)} aspect=\(aspect_Active.yn)|\(aspectRatio.multiplier)@\(aspect_Priority.rawValue)"}

#if TEST_VIDEO_CONSTRAINTS
      // Margin should ideally be 0, causing the video to expand to fill the window as much as possible while keeping aspect.
      let eqPriority: NSLayoutConstraint.Priority = .init(8)
      let eqIsActive = false

      let center2Priority: NSLayoutConstraint.Priority = .init(481)
      let center2Active = true

      let marginLT_Priority: NSLayoutConstraint.Priority = .init(311)
      let marginLT_Active = false

      let whMin_Priority: NSLayoutConstraint.Priority = .init(499)
      let whMinActive = false

      widthMin.priority = whMin_Priority
      heightMin.priority = whMin_Priority
      widthMin.isActive = whMinActive
      heightMin.isActive = whMinActive

      eqOffsetTop.priority = eqPriority
      eqOffsetTrailing.priority = eqPriority
      eqOffsetBottom.priority = eqPriority
      eqOffsetLeading.priority = eqPriority
      eqOffsetTop.isActive = eqIsActive
      eqOffsetTrailing.isActive = eqIsActive
      eqOffsetBottom.isActive = eqIsActive
      eqOffsetLeading.isActive = eqIsActive

      ltOffsetTop.priority = marginLT_Priority
      ltOffsetTrailing.priority = marginLT_Priority
      ltOffsetBottom.priority = marginLT_Priority
      ltOffsetLeading.priority = marginLT_Priority
      ltOffsetTop.isActive = marginLT_Active
      ltOffsetTrailing.isActive = marginLT_Active
      ltOffsetBottom.isActive = marginLT_Active
      ltOffsetLeading.isActive = marginLT_Active

      centerX2.priority = center2Priority
      centerY2.priority = center2Priority
      centerX2.isActive = center2Active
      centerY2.isActive = center2Active
#endif
      // - Priorities, Constants

      topSpacerConnection.priority = connectSpacers_Priority
      bottomSpacerConnection.priority = connectSpacers_Priority
      leadingSpacerConnection.priority = connectSpacers_Priority
      trailingSpacerConnection.priority = connectSpacers_Priority

      aspectRatio.priority = aspect_Priority

      topSpacerMax.priority = spacerMax_Priority
      trailingSpacerMax.priority = spacerMax_Priority
      bottomSpacerMax.priority = spacerMax_Priority
      leadingSpacerMax.priority = spacerMax_Priority

      if let spacerPreferred {
        topSpacerPreferred.animateToConstant(spacerPreferred.top)
        bottomSpacerPreferred.animateToConstant(spacerPreferred.bottom)
        leadingSpacerPreferred.animateToConstant(spacerPreferred.leading)
        trailingSpacerPreferred.animateToConstant(spacerPreferred.trailing)

        topSpacerPreferred.priority = spacerPreferred_Priority
        bottomSpacerPreferred.priority = spacerPreferred_Priority
        trailingSpacerPreferred.priority = spacerPreferred_Priority
        leadingSpacerPreferred.priority = spacerPreferred_Priority
      }

      if let wMax {
        widthMax.animateToConstant(wMax)
        widthMax.priority = whMax_Priority //+ (aspectMultiplier > 1 ? 1 : 0)
      }
      if let hMax {
        heightMax.animateToConstant(hMax)
        heightMax.priority = whMax_Priority //+ (aspectMultiplier > 1 ? 0 : 1)
      }

      centerX.priority = center_Priority
      centerY.priority = center_Priority

      // - Enablement

      topSpacerConnection.isActive = connectSpacers_Active
      bottomSpacerConnection.isActive = connectSpacers_Active
      leadingSpacerConnection.isActive = connectSpacers_Active
      trailingSpacerConnection.isActive = connectSpacers_Active

      aspectRatio.isActive = aspect_Active

      topSpacerMax.isActive = spacerMax_Active
      trailingSpacerMax.isActive = spacerMax_Active
      bottomSpacerMax.isActive = spacerMax_Active
      leadingSpacerMax.isActive = spacerMax_Active

      let spacerPreferred_Active = spacerPreferred != nil
      topSpacerPreferred.isActive = spacerPreferred_Active
      bottomSpacerPreferred.isActive = spacerPreferred_Active
      trailingSpacerPreferred.isActive = spacerPreferred_Active
      leadingSpacerPreferred.isActive = spacerPreferred_Active

      // TODO: improvements for music mode
      widthMax.isActive = wMax != nil
      heightMax.isActive = hMax != nil

      centerX.isActive = center_Active
      centerY.isActive = center_Active

      updateSpacerMin(to: spacerMin, spacerMin_Priority: spacerMin_Priority)
    }

    func updateSpacerMin(to spacerMin: MarginQuad?, spacerMin_Priority: NSLayoutConstraint.Priority) {
      if let spacerMin {
        topSpacerMin.animateToConstant(spacerMin.top)
        bottomSpacerMin.animateToConstant(spacerMin.bottom)
        leadingSpacerMin.animateToConstant(spacerMin.leading)
        trailingSpacerMin.animateToConstant(spacerMin.trailing)

        topSpacerMin.priority = spacerMin_Priority
        bottomSpacerMin.priority = spacerMin_Priority
        trailingSpacerMin.priority = spacerMin_Priority
        leadingSpacerMin.priority = spacerMin_Priority
      }

      let spacerMin_Active = spacerMin != nil
      topSpacerMin.isActive = spacerMin_Active
      bottomSpacerMin.isActive = spacerMin_Active
      trailingSpacerMin.isActive = spacerMin_Active
      leadingSpacerMin.isActive = spacerMin_Active
    }

    func disableAll() {
      topSpacerConnection.isActive = false
      bottomSpacerConnection.isActive = false
      leadingSpacerConnection.isActive = false
      trailingSpacerConnection.isActive = false

      topSpacerMin.isActive = false
      trailingSpacerMin.isActive = false
      bottomSpacerMin.isActive = false
      leadingSpacerMin.isActive = false

      topSpacerMax.isActive = false
      trailingSpacerMax.isActive = false
      bottomSpacerMax.isActive = false
      leadingSpacerMax.isActive = false

      topSpacerPreferred.isActive = false
      trailingSpacerPreferred.isActive = false
      bottomSpacerPreferred.isActive = false
      leadingSpacerPreferred.isActive = false

      widthMax.isActive = false
      heightMax.isActive = false

      centerX.isActive = false
      centerY.isActive = false

      aspectRatio.isActive = false

#if TEST_VIDEO_CONSTRAINTS
      eqOffsetTop.isActive = false
      eqOffsetTrailing.isActive = false
      eqOffsetBottom.isActive = false
      eqOffsetLeading.isActive = false

      ltOffsetTop.isActive = false
      ltOffsetTrailing.isActive = false
      ltOffsetBottom.isActive = false
      ltOffsetLeading.isActive = false

      widthMin.isActive = false
      heightMin.isActive = false

      centerX2.isActive = false
      centerY2.isActive = false
#endif
    }

  }  // end struct VideoViewConstraints

  /// Add, update, or remove all constraints, based on the given geometry (or lack thereof).
  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

    // TODO: implement a custom animation for change to aspect constraint
    if IINAAnimation.disableActionsWorkaround {
      CATransaction.setDisableActions(true)
    }

    guard let geometry, geometry.isVideoVisible else {
      log.verbose("VideoView: no geometry or video not visible; will remove constraints")
      removeVideoConstraints()
      return
    }

    if player.windowController.pip.status == .inPIP {
      log.verbose("VideoView: currently in PiP. Updating aspectRatio in PiP controller to: \(geometry.video.videoSizeCAR)")
      player.windowController.pip.controller.aspectRatio = geometry.video.videoSizeCAR
      return
    }
    guard player.windowController.pip.status == .notInPIP else {
      log.verbose("VideoView: currently in PiP; skipping constraints")
      return
    }

    guard let superview else {
      // Can happen when in music mode with video disabled
      log.verbose("VideoView: not adding constraints: no superview")
      return
    }

    let existing = videoViewConstraints
    let aspectMultiplier = geometry.videoViewAspect

    let aspect: NSLayoutConstraint
    if let existing {
      if aspectMultiplier != existing.aspectRatio.multiplier {
        // cannot reuse aspect constraint
        existing.aspectRatio.isActive = false
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
      } else {
        aspect = existing.aspectRatio
      }
    } else {
      aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
    }

    log.verbose("VideoView: updating constraints: aspect=\(aspectMultiplier) vidAspect=\(geometry.videoSize.mpvAspect) vidSize=\(geometry.videoSize)")

    let topSpacer = player.windowController.viewportTopSpacer
    let bottomSpacer = player.windowController.viewportBottomSpacer
    let leadingSpacer = player.windowController.viewportLeadingSpacer
    let trailingSpacer = player.windowController.viewportTrailingSpacer

    let cons = VideoViewConstraints(
      log: log,

      // Structural, don't need to revisit:
      topSpacerConnection: existing?.topSpacerConnection ?? topAnchor.constraint(equalTo: topSpacer.bottomAnchor),
      bottomSpacerConnection: existing?.bottomSpacerConnection ?? bottomAnchor.constraint(equalTo: bottomSpacer.topAnchor),
      leadingSpacerConnection: existing?.leadingSpacerConnection ?? leadingAnchor.constraint(equalTo: leadingSpacer.trailingAnchor),
      trailingSpacerConnection: existing?.trailingSpacerConnection ?? trailingAnchor.constraint(equalTo: trailingSpacer.leadingAnchor),

      // Maximize spacer sizes:
      topSpacerMax: existing?.topSpacerMax ?? topSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      trailingSpacerMax: existing?.trailingSpacerMax ?? trailingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),
      bottomSpacerMax: existing?.bottomSpacerMax ?? bottomSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      leadingSpacerMax: existing?.leadingSpacerMax ?? leadingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),

      // Min spacer sizes:
      topSpacerMin: existing?.topSpacerMin ?? topSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      trailingSpacerMin: existing?.trailingSpacerMin ?? trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      bottomSpacerMin: existing?.bottomSpacerMin ?? bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      leadingSpacerMin: existing?.leadingSpacerMin ?? leadingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),

      // Preferred spacer sizes:
      topSpacerPreferred: existing?.topSpacerPreferred ?? topSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      trailingSpacerPreferred: existing?.trailingSpacerPreferred ?? trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      bottomSpacerPreferred: existing?.bottomSpacerPreferred ?? bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      leadingSpacerPreferred: existing?.leadingSpacerPreferred ?? leadingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),

      // These maximize video size
      widthMax: existing?.widthMax ?? widthAnchor.constraint(equalTo: superview.widthAnchor),
      heightMax: existing?.heightMax ?? heightAnchor.constraint(equalTo: superview.heightAnchor),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      aspectRatio: aspect
/*
      #if TEST_VIDEO_CONSTRAINTS
      // If need to create new, just use 0 for all constants now; may update below
      eqOffsetTop: existing?.eqOffsetTop ?? topSpacer.heightAnchor.constraint(equalToConstant: 0),
      eqOffsetTrailing: existing?.eqOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(equalToConstant: 0),
      eqOffsetBottom: existing?.eqOffsetBottom ?? bottomSpacer.heightAnchor.constraint(equalToConstant: 0),
      eqOffsetLeading: existing?.eqOffsetLeading ?? leadingSpacer.widthAnchor.constraint(equalToConstant: 0),

      ltOffsetTop: existing?.ltOffsetTop ?? topSpacer.heightAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetTrailing: existing?.ltOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetBottom: existing?.ltOffsetBottom ?? bottomSpacer.heightAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetLeading: existing?.ltOffsetLeading ?? leadingSpacer.widthAnchor.constraint(lessThanOrEqualToConstant: 0),

      centerX2: existing?.centerX2 ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY2: existing?.centerY2 ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      widthMin: existing?.widthMin ?? widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      heightMin: existing?.heightMin ?? heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      #endif
 */
    )

    // - Configuration

    let interactiveMode = geometry.mode.isInteractiveMode

    let spacerMin: MarginQuad = interactiveMode ? Constants.InteractiveMode.viewportMargins : .zero

    /// Special case if `keepVideoAwayFromBars` is enabled: keep video away from bars if possible
    let keepVideoAwayFromBars = Preference.bool(for: .keepVideoAwayFromBars) && !Preference.bool(for: .lockViewportToVideoSize)

    // Need to keep priorities under 500 or the window will not resize!
    cons.update(connectSpacers_Active: true, connectSpacers_Priority: .required,
                // The desired aspect must always be honored. All constraints are secondary to this.
                aspectMultiplier: aspectMultiplier,
                aspect_Priority: musicMode ? .init(499) : .required,

                /// For interactive mode, max width should equal superview's width minus minMargins
                wMax: -spacerMin.totalWidth,
                hMax: -spacerMin.totalHeight,
                whMax_Priority: musicMode ? .required : .init(495),

                spacerMax_Active: !musicMode && !interactiveMode,
                spacerMax_Priority: .init(490),

                // For interactive mode, these need to be higher priority than video max
                spacerMin: spacerMin,
                spacerMin_Priority: .init(496),

                spacerPreferred: keepVideoAwayFromBars ? geometry.insideBars : nil,
                spacerPreferred_Priority: .init(481),

                // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
                center_Active: !musicMode,
                center_Priority: .init(480))


    videoViewConstraints = cons
    needsUpdateConstraints = true
    superview.layout()
  }

  /// Need to remove all constraints when in PiP: it will do layout based on the layer's `autoresizingMask`.
  func removeVideoConstraints() {
    guard let cons = videoViewConstraints else {
      log.verbose("VideoView: all video constraints already removed")
      return
    }

    log.verbose("VideoView: removing all video constraints")
    cons.disableAll()
    videoViewConstraints = nil
  }

#if TEST_VIDEO_CONSTRAINTS
  func loosenConstraints() {
    guard let cons = videoViewConstraints else { return }

    cons.update(connectSpacers_Active: true, connectSpacers_Priority: .init(100),
                aspectMultiplier: cons.aspectRatio.multiplier, aspect_Priority: .init(50),
                wMax: 0, hMax: 0, whMax_Priority: .init(99),
                spacerMax_Active: true, spacerMax_Priority: .init(98),
                spacerMin: nil, spacerMin_Priority: .init(97),
                spacerPreferred: nil, spacerPreferred_Priority: .init(97),
                center_Active: true, center_Priority: .init(96))
  }
#endif

}
