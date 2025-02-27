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
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
  }

  /// Convenience property
  var aspectMultiplier: CGFloat? {  videoViewConstraints?.aspectRatio.multiplier }


  // MARK: - VideoViewConstraints

  struct VideoViewConstraints {
    let topSpacerConnection: NSLayoutConstraint
    let bottomSpacerConnection: NSLayoutConstraint
    let leadingSpacerConnection: NSLayoutConstraint
    let trailingSpacerConnection: NSLayoutConstraint

    // Margins should most want to equal 0:
    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    let gtOffsetTop: NSLayoutConstraint
    let gtOffsetTrailing: NSLayoutConstraint
    let gtOffsetBottom: NSLayoutConstraint
    let gtOffsetLeading: NSLayoutConstraint

    let ltOffsetTop: NSLayoutConstraint
    let ltOffsetTrailing: NSLayoutConstraint
    let ltOffsetBottom: NSLayoutConstraint
    let ltOffsetLeading: NSLayoutConstraint

    let widthMax: NSLayoutConstraint
    let heightMax: NSLayoutConstraint

    let widthMin: NSLayoutConstraint
    let heightMin: NSLayoutConstraint

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
  }

  func removeVideoConstraints() {
    guard let cons = videoViewConstraints else {
      log.verbose("VideoView: all video constraints already removed")
      return
    }

    log.verbose("VideoView: removing all video constraints")
    cons.topSpacerConnection.isActive = false
    cons.bottomSpacerConnection.isActive = false
    cons.leadingSpacerConnection.isActive = false
    cons.trailingSpacerConnection.isActive = false
    
    cons.eqOffsetTop.isActive = false
    cons.eqOffsetTrailing.isActive = false
    cons.eqOffsetBottom.isActive = false
    cons.eqOffsetLeading.isActive = false

    cons.gtOffsetTop.isActive = false
    cons.gtOffsetTrailing.isActive = false
    cons.gtOffsetBottom.isActive = false
    cons.gtOffsetLeading.isActive = false

    cons.ltOffsetTop.isActive = false
    cons.ltOffsetTrailing.isActive = false
    cons.ltOffsetBottom.isActive = false
    cons.ltOffsetLeading.isActive = false

    cons.widthMax.isActive = false
    cons.heightMax.isActive = false

    cons.widthMin.isActive = false
    cons.heightMin.isActive = false

    cons.centerX.isActive = false
    cons.centerY.isActive = false

    cons.centerX2.isActive = false
    cons.centerY2.isActive = false

    cons.aspectRatio.isActive = false
    videoViewConstraints = nil
  }

  /// Add, update, or remove all constraints, based on the given geometry (or lack thereof).
  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

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

    let topSpacer = player.windowController.viewportTopSpacer
    let bottomSpacer = player.windowController.viewportBottomSpacer
    let leadingSpacer = player.windowController.viewportLeadingSpacer
    let trailingSpacer = player.windowController.viewportTrailingSpacer

    let cons = VideoViewConstraints(
      topSpacerConnection: existing?.topSpacerConnection ?? topAnchor.constraint(equalTo: topSpacer.bottomAnchor),
      bottomSpacerConnection: existing?.bottomSpacerConnection ?? bottomAnchor.constraint(equalTo: bottomSpacer.topAnchor),
      leadingSpacerConnection: existing?.leadingSpacerConnection ?? leadingAnchor.constraint(equalTo: leadingSpacer.trailingAnchor),
      trailingSpacerConnection: existing?.trailingSpacerConnection ?? trailingAnchor.constraint(equalTo: trailingSpacer.leadingAnchor),

      // If need to create new, just use 0 for all constants now; may update below
      eqOffsetTop: existing?.eqOffsetTop ?? topSpacer.heightAnchor.constraint(equalToConstant: 0),
      eqOffsetTrailing: existing?.eqOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(equalToConstant: 0),
      eqOffsetBottom: existing?.eqOffsetBottom ?? bottomSpacer.heightAnchor.constraint(equalToConstant: 0),
      eqOffsetLeading: existing?.eqOffsetLeading ?? leadingSpacer.widthAnchor.constraint(equalToConstant: 0),

      gtOffsetTop: existing?.gtOffsetTop ?? topSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      gtOffsetTrailing: existing?.gtOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),
      gtOffsetBottom: existing?.gtOffsetBottom ?? bottomSpacer.heightAnchor.constraint(equalTo: superview.heightAnchor),
      gtOffsetLeading: existing?.gtOffsetLeading ?? leadingSpacer.widthAnchor.constraint(equalTo: superview.widthAnchor),

      ltOffsetTop: existing?.ltOffsetTop ?? topSpacer.heightAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetTrailing: existing?.ltOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetBottom: existing?.ltOffsetBottom ?? bottomSpacer.heightAnchor.constraint(lessThanOrEqualToConstant: 0),
      ltOffsetLeading: existing?.ltOffsetLeading ?? leadingSpacer.widthAnchor.constraint(lessThanOrEqualToConstant: 0),

      widthMax: existing?.widthMin ?? widthAnchor.constraint(equalTo: superview.widthAnchor),
      heightMax: existing?.heightMin ?? heightAnchor.constraint(equalTo: superview.heightAnchor),

      widthMin: existing?.widthMin ?? widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      heightMin: existing?.heightMin ?? heightAnchor.constraint(greaterThanOrEqualToConstant: 0),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      centerX2: existing?.centerX2 ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY2: existing?.centerY2 ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      aspectRatio: aspect
    )

    // Update constants

    let inside = geometry.insideBars
    let keepVideoAwayFromBars = Preference.bool(for: .keepVideoAwayFromBars)
    if keepVideoAwayFromBars {
      let centerOffsetX = (inside.leading - inside.trailing) * 0.5
      let centerOffsetY = (inside.top - inside.bottom) * 0.5
      cons.centerX.animateToConstant(centerOffsetX)
      cons.centerY.animateToConstant(centerOffsetY)
    } else {
      cons.centerX.animateToConstant(0)
      cons.centerY.animateToConstant(0)
    }

    // Priorities

    let connectSpacers = true

    // The desired aspect must always be honored. All constraints are secondary to this.
    let aspectPriority: NSLayoutConstraint.Priority = .required
    let aspectActive = aspectMultiplier > 0.0

    // TODO: not max. rename

    // Margin should ideally be 0, causing the video to expand to fill the window as much as possible while keeping aspect.
    let eqPriority: NSLayoutConstraint.Priority = .init(8)
    let eqIsActive = false

    let whMaxPriority: NSLayoutConstraint.Priority = .init(322)
    let whMaxActive = true

    let marginGT_Priority: NSLayoutConstraint.Priority = .init(312)
    let marginGT_Active = true

    let marginLT_Priority: NSLayoutConstraint.Priority = .init(311)
    let marginLT_Active = false

    let whMaximize_Priority: NSLayoutConstraint.Priority = .init(499)
    let whMinActive = false

    // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
    let centerPriority: NSLayoutConstraint.Priority = .init(301)
    let centerActive = true

    let center2Priority: NSLayoutConstraint.Priority = .init(300)
    let center2Active = false

    cons.aspectRatio.priority = aspectPriority

    cons.eqOffsetTop.priority = eqPriority
    cons.eqOffsetTrailing.priority = eqPriority
    cons.eqOffsetBottom.priority = eqPriority
    cons.eqOffsetLeading.priority = eqPriority

    cons.gtOffsetTop.priority = marginGT_Priority
    cons.gtOffsetTrailing.priority = marginGT_Priority
    cons.gtOffsetBottom.priority = marginGT_Priority
    cons.gtOffsetLeading.priority = marginGT_Priority

    cons.ltOffsetTop.priority = marginLT_Priority
    cons.ltOffsetTrailing.priority = marginLT_Priority
    cons.ltOffsetBottom.priority = marginLT_Priority
    cons.ltOffsetLeading.priority = marginLT_Priority

    cons.widthMin.priority = whMaximize_Priority
    cons.heightMin.priority = whMaximize_Priority
    cons.widthMax.priority = whMaxPriority
    cons.heightMax.priority = whMaxPriority

    cons.centerX.priority = centerPriority
    cons.centerY.priority = centerPriority

    cons.centerX2.priority = center2Priority
    cons.centerY2.priority = center2Priority

    // Enablement

    cons.topSpacerConnection.isActive = connectSpacers
    cons.bottomSpacerConnection.isActive = connectSpacers
    cons.leadingSpacerConnection.isActive = connectSpacers
    cons.trailingSpacerConnection.isActive = connectSpacers

    cons.eqOffsetTop.isActive = eqIsActive
    cons.eqOffsetTrailing.isActive = eqIsActive
    cons.eqOffsetBottom.isActive = eqIsActive
    cons.eqOffsetLeading.isActive = eqIsActive

    cons.gtOffsetTop.isActive = marginGT_Active
    cons.gtOffsetTrailing.isActive = marginGT_Active
    cons.gtOffsetBottom.isActive = marginGT_Active
    cons.gtOffsetLeading.isActive = marginGT_Active

    cons.ltOffsetTop.isActive = marginLT_Active
    cons.ltOffsetTrailing.isActive = marginLT_Active
    cons.ltOffsetBottom.isActive = marginLT_Active
    cons.ltOffsetLeading.isActive = marginLT_Active

    cons.widthMin.isActive = false
    cons.heightMin.isActive = false
    cons.widthMax.isActive = false
    cons.heightMax.isActive = whMaxActive

    cons.centerX.isActive = centerActive
    cons.centerY.isActive = centerActive

    cons.centerX2.isActive = center2Active
    cons.centerY2.isActive = center2Active

    cons.aspectRatio.isActive = aspectActive

    videoViewConstraints = cons

    needsUpdateConstraints = true
    superview.layout()
  }
}
