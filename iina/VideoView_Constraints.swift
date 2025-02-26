//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

extension VideoView {
  
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

    // Margins should be willing to expand if they can't equal 0:
    let gtOffsetTop: NSLayoutConstraint
    let gtOffsetTrailing: NSLayoutConstraint
    let gtOffsetBottom: NSLayoutConstraint
    let gtOffsetLeading: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
    // These can be adjusted to keep VideoView away from "inside" bars.
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint
    let aspectRatio: NSLayoutConstraint
  }

  func initConstraints() {
    translatesAutoresizingMaskIntoConstraints = false
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setContentHuggingPriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
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

    cons.centerX.isActive = false
    cons.centerY.isActive = false
    cons.aspectRatio.isActive = false
    videoViewConstraints = nil
  }

  var aspectMultiplier: CGFloat? {
    return videoViewConstraints?.aspectRatio.multiplier
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

      gtOffsetTop: existing?.gtOffsetTop ?? topSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      gtOffsetTrailing: existing?.gtOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
      gtOffsetBottom: existing?.gtOffsetBottom ?? bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
      gtOffsetLeading: existing?.gtOffsetLeading ?? leadingSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

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

    // The desired aspect must always be honored. All constraints are secondary to this.
    cons.aspectRatio.priority = .required

    // Margin should ideally be 0, causing the video to expand to fill the window as much as possible,
    // while keeping aspect.
    let eqPriority: NSLayoutConstraint.Priority = .init(300)
    cons.eqOffsetTop.priority = eqPriority
    cons.eqOffsetTrailing.priority = eqPriority
    cons.eqOffsetBottom.priority = eqPriority
    cons.eqOffsetLeading.priority = eqPriority

    // GT constraints exist to prevent overlap with the inner bars, if possible. But this is a lower priority.
    let gtPriority: NSLayoutConstraint.Priority = .init(299)
    cons.gtOffsetTop.priority = gtPriority
    cons.gtOffsetTrailing.priority = gtPriority
    cons.gtOffsetBottom.priority = gtPriority
    cons.gtOffsetLeading.priority = gtPriority

    // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
    let centerPriority: NSLayoutConstraint.Priority = .init(10)
    cons.centerX.priority = centerPriority
    cons.centerY.priority = centerPriority

    // Enablement

    cons.topSpacerConnection.isActive = true
    cons.bottomSpacerConnection.isActive = true
    cons.leadingSpacerConnection.isActive = true
    cons.trailingSpacerConnection.isActive = true

    let eqIsActive = true
    cons.eqOffsetTop.isActive = eqIsActive
    cons.eqOffsetTrailing.isActive = eqIsActive
    cons.eqOffsetBottom.isActive = eqIsActive
    cons.eqOffsetLeading.isActive = eqIsActive

    let gtIsActive = true
    cons.gtOffsetTop.isActive = gtIsActive
    cons.gtOffsetTrailing.isActive = gtIsActive
    cons.gtOffsetBottom.isActive = gtIsActive
    cons.gtOffsetLeading.isActive = gtIsActive

    cons.centerX.isActive = true
    cons.centerY.isActive = true

    cons.aspectRatio.isActive = aspectMultiplier > 0.0

    videoViewConstraints = cons

    needsUpdateConstraints = true
    superview.layout()
  }
}
