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

    let width: NSLayoutConstraint
    let height: NSLayoutConstraint

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

    cons.width.isActive = false
    cons.height.isActive = false

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
      eqOffsetTop: existing?.eqOffsetTop ?? topSpacer.topAnchor.constraint(equalTo: topSpacer.bottomAnchor, constant: 0),
      eqOffsetTrailing: existing?.eqOffsetTrailing ?? trailingSpacer.trailingAnchor.constraint(equalTo: trailingSpacer.leadingAnchor, constant: 0),
      eqOffsetBottom: existing?.eqOffsetBottom ?? bottomSpacer.topAnchor.constraint(equalTo: bottomSpacer.bottomAnchor, constant: 0),
      eqOffsetLeading: existing?.eqOffsetLeading ?? leadingSpacer.trailingAnchor.constraint(equalTo: leadingSpacer.leadingAnchor, constant: 0),

      gtOffsetTop: existing?.gtOffsetTop ?? topSpacer.topAnchor.constraint(greaterThanOrEqualTo: topSpacer.bottomAnchor, constant: 0),
      gtOffsetTrailing: existing?.gtOffsetTrailing ?? trailingSpacer.trailingAnchor.constraint(greaterThanOrEqualTo: trailingSpacer.leadingAnchor, constant: 0),
      gtOffsetBottom: existing?.gtOffsetBottom ?? bottomSpacer.topAnchor.constraint(greaterThanOrEqualTo: bottomSpacer.bottomAnchor, constant: 0),
      gtOffsetLeading: existing?.gtOffsetLeading ?? leadingSpacer.trailingAnchor.constraint(greaterThanOrEqualTo: leadingSpacer.leadingAnchor, constant: 0),

      ltOffsetTop: existing?.ltOffsetTop ?? topSpacer.topAnchor.constraint(lessThanOrEqualTo: topSpacer.bottomAnchor, constant: 0),
      ltOffsetTrailing: existing?.ltOffsetTrailing ?? trailingSpacer.trailingAnchor.constraint(lessThanOrEqualTo: trailingSpacer.leadingAnchor, constant: 0),
      ltOffsetBottom: existing?.ltOffsetBottom ?? bottomSpacer.topAnchor.constraint(lessThanOrEqualTo: bottomSpacer.bottomAnchor, constant: 0),
      ltOffsetLeading: existing?.ltOffsetLeading ?? leadingSpacer.trailingAnchor.constraint(lessThanOrEqualTo: leadingSpacer.leadingAnchor, constant: 0),

      width: existing?.width ?? widthAnchor.constraint(equalToConstant: 0),
      height: existing?.height ?? heightAnchor.constraint(equalToConstant: 0),

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

    // Margin should ideally be 0, causing the video to expand to fill the window as much as possible while keeping aspect.
    let eqPriority: NSLayoutConstraint.Priority = .init(280)
    let eqIsActive = false

    let gtPriority: NSLayoutConstraint.Priority = .init(289)
    let gtIsActive = true

    let ltPriority: NSLayoutConstraint.Priority = .init(290)
    let ltIsActive = false

    let widthAndHeightActive = true
    let widthAndHeightPriority: NSLayoutConstraint.Priority = .init(280)

    // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
    let centerPriority: NSLayoutConstraint.Priority = .init(290)
    let centerActive = true

    let center2Priority: NSLayoutConstraint.Priority = .init(289)
    let center2Active = true

    // The desired aspect must always be honored. All constraints are secondary to this.
    cons.aspectRatio.priority = .required

    cons.eqOffsetTop.priority = eqPriority
    cons.eqOffsetTrailing.priority = eqPriority
    cons.eqOffsetBottom.priority = eqPriority
    cons.eqOffsetLeading.priority = eqPriority

    cons.gtOffsetTop.priority = gtPriority
    cons.gtOffsetTrailing.priority = gtPriority
    cons.gtOffsetBottom.priority = gtPriority
    cons.gtOffsetLeading.priority = gtPriority

    cons.ltOffsetTop.priority = ltPriority
    cons.ltOffsetTrailing.priority = ltPriority
    cons.ltOffsetBottom.priority = ltPriority
    cons.ltOffsetLeading.priority = ltPriority

    cons.width.priority = widthAndHeightPriority
    cons.height.priority = widthAndHeightPriority

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

    cons.gtOffsetTop.isActive = gtIsActive
    cons.gtOffsetTrailing.isActive = gtIsActive
    cons.gtOffsetBottom.isActive = gtIsActive
    cons.gtOffsetLeading.isActive = gtIsActive

    cons.ltOffsetTop.isActive = ltIsActive
    cons.ltOffsetTrailing.isActive = ltIsActive
    cons.ltOffsetBottom.isActive = ltIsActive
    cons.ltOffsetLeading.isActive = ltIsActive

    cons.width.isActive = widthAndHeightActive
    cons.height.isActive = widthAndHeightActive

    cons.centerX.isActive = centerActive
    cons.centerY.isActive = centerActive

    cons.centerX2.isActive = center2Active
    cons.centerY2.isActive = center2Active

    cons.aspectRatio.isActive = aspectMultiplier > 0.0

    videoViewConstraints = cons

    needsUpdateConstraints = true
    superview.layout()
  }
}
