//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

extension VideoView {
  
  struct VideoViewConstraints {
    let leadingSpacerConnection: NSLayoutConstraint
    let trailingSpacerConnection: NSLayoutConstraint

    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
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
    guard let existing = videoViewConstraints else {
      log.verbose("VideoView: all video constraints already removed")
      return
    }

    log.verbose("VideoView: removing all video constraints")
    existing.leadingSpacerConnection.isActive = false
    existing.trailingSpacerConnection.isActive = false
    
    existing.eqOffsetTop.isActive = false
    existing.eqOffsetTrailing.isActive = false
    existing.eqOffsetBottom.isActive = false
    existing.eqOffsetLeading.isActive = false
    existing.centerX.isActive = false
    existing.centerY.isActive = false
    existing.aspectRatio.isActive = false
    videoViewConstraints = nil
  }

  var aspectMultiplier: CGFloat? {
    return videoViewConstraints?.aspectRatio.multiplier
  }

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
    let aspectIsActive = aspectMultiplier > 0.0
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
    aspect.priority = .required

    let leadingSpacer = player.windowController.viewportLeadingSpacer
    let trailingSpacer = player.windowController.viewportTrailingSpacer

    let newConstraints = VideoViewConstraints(
      leadingSpacerConnection: existing?.leadingSpacerConnection ?? leadingAnchor.constraint(equalTo: leadingSpacer.trailingAnchor),
      trailingSpacerConnection: existing?.trailingSpacerConnection ?? trailingAnchor.constraint(equalTo: trailingSpacer.leadingAnchor),

      eqOffsetTop: existing?.eqOffsetTop ?? topAnchor.constraint(equalTo: superview.topAnchor, constant: margins.top),
      eqOffsetTrailing: existing?.eqOffsetTrailing ?? trailingSpacer.widthAnchor.constraint(equalToConstant: margins.trailing),
      eqOffsetBottom: existing?.eqOffsetBottom ?? superview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: margins.bottom),
      eqOffsetLeading: existing?.eqOffsetLeading ?? leadingSpacer.widthAnchor.constraint(equalToConstant: margins.leading),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: (margins.leading - margins.trailing) * 0.5),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor),
      aspectRatio: aspect
    )

    newConstraints.centerX.animateToConstant((margins.leading - margins.trailing) * 0.5)
    newConstraints.eqOffsetTop.animateToConstant(margins.top)
    newConstraints.eqOffsetTrailing.animateToConstant(0)//margins.trailing)
    newConstraints.eqOffsetBottom.animateToConstant(margins.bottom)
    newConstraints.eqOffsetLeading.animateToConstant(0)//margins.leading)

    let eqPriority: NSLayoutConstraint.Priority = .init(499)
    newConstraints.eqOffsetTop.priority = eqPriority
    newConstraints.eqOffsetTrailing.priority = eqPriority
    newConstraints.eqOffsetBottom.priority = eqPriority
    newConstraints.eqOffsetLeading.priority = eqPriority
    newConstraints.centerX.priority = .minimum
    newConstraints.centerY.priority = .minimum
    newConstraints.aspectRatio.priority = .required

    newConstraints.leadingSpacerConnection.isActive = true
    newConstraints.trailingSpacerConnection.isActive = true
    let eqIsActive = true
    newConstraints.eqOffsetTop.isActive = eqIsActive
    newConstraints.eqOffsetTrailing.isActive = false
    newConstraints.eqOffsetBottom.isActive = eqIsActive
    newConstraints.eqOffsetLeading.isActive = false
    newConstraints.centerX.isActive = true
    newConstraints.centerY.isActive = true
    newConstraints.aspectRatio.isActive = aspectIsActive

    videoViewConstraints = newConstraints

    // FIXME: when watching vertical video with letterbox & leading sidebar shown & resizing from side,
    // VideoView can stretch horizontally, even though it violates its aspect constraint (priority 1000),
    // and even though the View Debugger shows it is not distorted...
  }
}
