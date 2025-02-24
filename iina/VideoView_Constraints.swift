//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

extension VideoView {
  
  struct VideoViewConstraints {
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

  var aspectMultiplier: CGFloat? {
    return videoViewConstraints?.aspectRatio.multiplier
  }

  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

    guard player.windowController.pip.status == .notInPIP else {
      log.verbose("VideoView: currently in PiP; ignoring request to set viewportMargin constraints")
      return
    }

    let margins: MarginQuad
    let videoAspect: Double
    if let geometry, geometry.isVideoVisible {
      margins = geometry.viewportMargins
      videoAspect = geometry.videoViewAspect
      log.verbose{"VideoView: updating constraints to margins=\(margins), aspect\(videoAspect)"}
    } else {
      margins = .zero
      videoAspect = -1
      log.verbose("VideoView: zeroing out constraints")
    }

    guard let superview else {
      // Should not get here
      log.error("Cannot rebuild constraints for videoView: it has no superview!")
      return
    }

    let existing = videoViewConstraints

    let aspect: NSLayoutConstraint
    let aspectIsActive = videoAspect > 0.0
    if let existing {
      existing.eqOffsetTop.isActive = false
      existing.eqOffsetTrailing.isActive = false
      existing.eqOffsetBottom.isActive = false
      existing.eqOffsetLeading.isActive = false
      existing.centerX.isActive = false
      existing.centerY.isActive = false
      existing.aspectRatio.isActive = false

      if existing.aspectRatio.isActive != aspectIsActive || aspectMultiplier != existing.aspectRatio.multiplier {
        existing.aspectRatio.isActive = false
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoAspect, constant: 0)
      } else {
        aspect = existing.aspectRatio
      }
    } else {
      aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoAspect, constant: 0)
    }
    aspect.priority = .required

    let newConstraints = VideoViewConstraints(
      eqOffsetTop: existing?.eqOffsetTop ?? topAnchor.constraint(equalTo: superview.topAnchor, constant: margins.top),
      eqOffsetTrailing: existing?.eqOffsetTrailing ?? superview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: margins.trailing),
      eqOffsetBottom: existing?.eqOffsetBottom ?? superview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: margins.bottom),
      eqOffsetLeading: existing?.eqOffsetLeading ?? leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: margins.leading),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor),
      aspectRatio: aspect
    )
    newConstraints.eqOffsetTop.animateToConstant(margins.top)
    newConstraints.eqOffsetTrailing.animateToConstant(margins.trailing)
    newConstraints.eqOffsetBottom.animateToConstant(margins.bottom)
    newConstraints.eqOffsetLeading.animateToConstant(margins.leading)

    let eqPriority: NSLayoutConstraint.Priority = .init(499)
    newConstraints.eqOffsetTop.priority = eqPriority
    newConstraints.eqOffsetTrailing.priority = eqPriority
    newConstraints.eqOffsetBottom.priority = eqPriority
    newConstraints.eqOffsetLeading.priority = eqPriority
    newConstraints.centerX.priority = .minimum
    newConstraints.centerY.priority = .minimum
    newConstraints.aspectRatio.priority = .required

    let eqIsActive = true
    newConstraints.eqOffsetTop.isActive = eqIsActive
    newConstraints.eqOffsetTrailing.isActive = eqIsActive
    newConstraints.eqOffsetBottom.isActive = eqIsActive
    newConstraints.eqOffsetLeading.isActive = eqIsActive
    newConstraints.centerX.isActive = true
    newConstraints.centerY.isActive = true
    newConstraints.aspectRatio.isActive = aspectIsActive

    videoViewConstraints = newConstraints

    // FIXME: when watching vertical video with letterbox & leading sidebar shown & resizing from side,
    // VideoView can stretch horizontally, even though it violates its aspect constraint (priority 1000),
    // and even though the View Debugger shows it is not distorted...
    superview.invalidateIntrinsicContentSize()
    self.invalidateIntrinsicContentSize()
    needsLayout = true
  }

}
