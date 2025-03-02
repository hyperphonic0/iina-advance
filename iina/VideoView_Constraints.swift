//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

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
    let topSpacerConnection: NSLayoutConstraint
    let bottomSpacerConnection: NSLayoutConstraint
    let leadingSpacerConnection: NSLayoutConstraint
    let trailingSpacerConnection: NSLayoutConstraint

    let topSpacerMax: NSLayoutConstraint
    let trailingSpacerMax: NSLayoutConstraint
    let bottomSpacerMax: NSLayoutConstraint
    let leadingSpacerMax: NSLayoutConstraint

    let topSpacerGT: NSLayoutConstraint
    let trailingSpacerGT: NSLayoutConstraint
    let bottomSpacerGT: NSLayoutConstraint
    let leadingSpacerGT: NSLayoutConstraint

    let widthMax: NSLayoutConstraint
    let heightMax: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
    // These can be adjusted to keep VideoView away from "inside" bars.
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint

    let centerX2: NSLayoutConstraint
    let centerY2: NSLayoutConstraint

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

    let widthMin: NSLayoutConstraint
    let heightMin: NSLayoutConstraint
#endif

    func disableAll() {
      topSpacerConnection.isActive = false
      bottomSpacerConnection.isActive = false
      leadingSpacerConnection.isActive = false
      trailingSpacerConnection.isActive = false

      topSpacerMax.isActive = false
      trailingSpacerMax.isActive = false
      bottomSpacerMax.isActive = false
      leadingSpacerMax.isActive = false

      widthMax.isActive = false
      heightMax.isActive = false

      centerX.isActive = false
      centerY.isActive = false

      centerX2.isActive = false
      centerY2.isActive = false

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
#endif
    }

    func update(connectSpacers_Active: Bool, connectSpacers_Priority: NSLayoutConstraint.Priority,
                aspect_Active: Bool, aspect_Priority: NSLayoutConstraint.Priority,
                whMax_Active: Bool, whMax_Priority: NSLayoutConstraint.Priority,
                marginGT_Active: Bool, marginGT_Priority: NSLayoutConstraint.Priority,
                center_Active: Bool, center_Priority: NSLayoutConstraint.Priority) {

//      let center2Priority: NSLayoutConstraint.Priority = .init(481)
//      let center2Active = true

#if TEST_VIDEO_CONSTRAINTS
      // Margin should ideally be 0, causing the video to expand to fill the window as much as possible while keeping aspect.
      let eqPriority: NSLayoutConstraint.Priority = .init(8)
      let eqIsActive = false

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

#endif
      // - Priorities

      topSpacerConnection.priority = connectSpacers_Priority
      bottomSpacerConnection.priority = connectSpacers_Priority
      leadingSpacerConnection.priority = connectSpacers_Priority
      trailingSpacerConnection.priority = connectSpacers_Priority

      aspectRatio.priority = aspect_Priority

      topSpacerMax.priority = marginGT_Priority
      trailingSpacerMax.priority = marginGT_Priority
      bottomSpacerMax.priority = marginGT_Priority
      leadingSpacerMax.priority = marginGT_Priority

      widthMax.priority = whMax_Priority
      heightMax.priority = whMax_Priority

      centerX.priority = center_Priority
      centerY.priority = center_Priority

//      centerX2.priority = center2Priority
//      centerY2.priority = center2Priority

      // - Enablement

      topSpacerConnection.isActive = connectSpacers_Active
      bottomSpacerConnection.isActive = connectSpacers_Active
      leadingSpacerConnection.isActive = connectSpacers_Active
      trailingSpacerConnection.isActive = connectSpacers_Active

      aspectRatio.isActive = aspect_Active

      topSpacerMax.isActive = marginGT_Active
      trailingSpacerMax.isActive = marginGT_Active
      bottomSpacerMax.isActive = marginGT_Active
      leadingSpacerMax.isActive = marginGT_Active

      // TODO: improvements for music mode
      widthMax.isActive = false// whMax_Active  // not needed due to aspect...
      heightMax.isActive = whMax_Active

      centerX.isActive = center_Active
      centerY.isActive = center_Active

//      centerX2.isActive = center2Active
//      centerY2.isActive = center2Active
    }
  }

  func removeVideoConstraints() {
    guard let cons = videoViewConstraints else {
      log.verbose("VideoView: all video constraints already removed")
      return
    }

    log.verbose("VideoView: removing all video constraints")
    cons.disableAll()
    videoViewConstraints = nil
  }

  func loosenConstraints() {
    guard let cons = videoViewConstraints else { return }

    cons.update(connectSpacers_Active: true, connectSpacers_Priority: .init(100),
                aspect_Active: true, aspect_Priority: .init(50),
                whMax_Active: true, whMax_Priority: .init(99),
                marginGT_Active: true, marginGT_Priority: .init(98),
                center_Active: true, center_Priority: .init(97))
  }

  /// Add, update, or remove all constraints, based on the given geometry (or lack thereof).
  func apply(_ geometry: PWinGeometry?, updateAspect: Bool = true) {
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
    let existing = videoViewConstraints
    let margins = geometry.viewportMargins
    let aspectMultiplier = geometry.videoViewAspect
    log.verbose{"VideoView: updating constraints to margins=\(margins), aspect=\(aspectMultiplier)"}

    guard player.windowController.pip.status == .notInPIP else {
      log.verbose("VideoView: currently in PiP; skipping constraints")
      return
    }

    guard let superview else {
      // Can happen when in music mode with video disabled
      log.verbose("VideoView: not adding constraints: no superview")
      return
    }

    let aspect: NSLayoutConstraint
    if let existing {
      if aspectMultiplier != existing.aspectRatio.multiplier, updateAspect {
        // cannot reuse aspect constraint
        existing.aspectRatio.isActive = false
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
      } else {
        aspect = existing.aspectRatio
      }
    } else {
      aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
    }

    let topSpacer = player.windowController.viewportTopSpacer
    let bottomSpacer = player.windowController.viewportBottomSpacer
    let leadingSpacer = player.windowController.viewportLeadingSpacer
    let trailingSpacer = player.windowController.viewportTrailingSpacer

    let cons = VideoViewConstraints(
      topSpacerConnection: existing?.topSpacerConnection ?? topAnchor.constraint(equalTo: topSpacer.bottomAnchor),
      bottomSpacerConnection: existing?.bottomSpacerConnection ?? bottomAnchor.constraint(equalTo: bottomSpacer.topAnchor),
      leadingSpacerConnection: existing?.leadingSpacerConnection ?? leadingAnchor.constraint(equalTo: leadingSpacer.trailingAnchor),
      trailingSpacerConnection: existing?.trailingSpacerConnection ?? trailingAnchor.constraint(equalTo: trailingSpacer.leadingAnchor),

      topSpacerMax: existing?.topSpacerMax ?? topSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      trailingSpacerMax: existing?.trailingSpacerMax ?? trailingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),
      bottomSpacerMax: existing?.bottomSpacerMax ?? bottomSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      leadingSpacerMax: existing?.leadingSpacerMax ?? leadingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),

      topSpacerGT: existing?.topSpacerGT ?? topSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      trailingSpacerGT: existing?.trailingSpacerGT ?? trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      bottomSpacerGT: existing?.bottomSpacerGT ?? bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      leadingSpacerGT: existing?.leadingSpacerGT ?? leadingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),

      widthMax: existing?.widthMax ?? widthAnchor.constraint(equalTo: superview.widthAnchor),
      heightMax: existing?.heightMax ?? heightAnchor.constraint(equalTo: superview.heightAnchor),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      centerX2: existing?.centerX2 ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY2: existing?.centerY2 ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

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

      widthMin: existing?.widthMin ?? widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      heightMin: existing?.heightMin ?? heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      #endif
 */
    )

    cons.topSpacerGT.animateToConstant(geometry.insideBars.top)
    cons.trailingSpacerGT.animateToConstant(geometry.insideBars.trailing)
    cons.bottomSpacerGT.animateToConstant(geometry.insideBars.bottom)
    cons.leadingSpacerGT.animateToConstant(geometry.insideBars.leading)

    // Update constants

//    let inside = geometry.insideBars
//    let keepVideoAwayFromBars = Preference.bool(for: .keepVideoAwayFromBars)
//    if keepVideoAwayFromBars {
//      let centerOffsetX = ((inside.leading - inside.trailing) * 0.5).rounded(.down)
//      let centerOffsetY = ((inside.top - inside.bottom) * 0.5).rounded(.down)
//      cons.centerX.animateToConstant(centerOffsetX)
//      cons.centerY.animateToConstant(centerOffsetY)
//    } else {
      cons.centerX.animateToConstant(0)
      cons.centerY.animateToConstant(0)
//    }

    let pri = NSLayoutConstraint.Priority.init(481)
    cons.topSpacerGT.priority = pri
    cons.trailingSpacerGT.priority = pri
    cons.bottomSpacerGT.priority = pri
    cons.leadingSpacerGT.priority = pri

    cons.topSpacerGT.isActive = true
    cons.trailingSpacerGT.isActive = true
    cons.bottomSpacerGT.isActive = true
    cons.leadingSpacerGT.isActive = true

    // - Configuration

    let musicMode = false // TODO: improvements for music mode (search for this)

    // The desired aspect must always be honored. All constraints are secondary to this.
    let aspect_Priority: NSLayoutConstraint.Priority = .required

    // Need to keep priorities under 500 or the window will not resize!
    let whMax_Priority: NSLayoutConstraint.Priority = .init(495)
    let marginGT_Priority: NSLayoutConstraint.Priority = .init(490)

    // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
    let center_Priority: NSLayoutConstraint.Priority = .init(480)

    cons.update(connectSpacers_Active: true, connectSpacers_Priority: .required,
                aspect_Active: aspectMultiplier > 0.0, aspect_Priority: musicMode ? .init(499) : .required,
                whMax_Active: true, whMax_Priority: musicMode ? .required : whMax_Priority,
                marginGT_Active: !musicMode, marginGT_Priority: marginGT_Priority,
                center_Active: !musicMode, center_Priority: center_Priority)
    videoViewConstraints = cons

    needsUpdateConstraints = true
    superview.layout()
  }
}
