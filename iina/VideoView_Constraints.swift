//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

// MARK: - Constraints structs

fileprivate struct Constraint: CustomStringConvertible {
  let active: Bool
  let priority: NSLayoutConstraint.Priority

  init(active: Bool, priority: NSLayoutConstraint.Priority) {
    self.active = active
    self.priority = priority
  }

  init(active: Bool, priority priorityInt: Int) {
    self.init(active: active, priority: .init(rawValue: Float(priorityInt)))
  }

  var description: String {
    return "\(active ? "EN" : "Dis"):@\(priority.rawValue)"
  }
}

fileprivate struct AspectConstraint: CustomStringConvertible {
  let active: Bool
  let priority: NSLayoutConstraint.Priority
  let multiplier: CGFloat

  init(active: Bool, priority: NSLayoutConstraint.Priority, multiplier: CGFloat) {
    self.active = active
    self.priority = priority
    self.multiplier = multiplier
  }

  init(active: Bool, priority priorityInt: Int, multiplier: CGFloat) {
    self.init(active: active, priority: .init(rawValue: Float(priorityInt)), multiplier: multiplier)
  }

  var description: String {
    return "\(active ? "Yes" : "No"):\(multiplier)x@\(priority.rawValue)"
  }
}

fileprivate struct QuadConstraint: CustomStringConvertible {
  let active: Bool
  let priority: NSLayoutConstraint.Priority
  let values: MarginQuad?

  init(active: Bool, priority: NSLayoutConstraint.Priority, _ values: MarginQuad?) {
    self.active = active
    self.priority = priority
    self.values = values
  }

  init(active: Bool, priority priorityInt: Int, _ values: MarginQuad?) {
    self.init(active: active, priority: .init(rawValue: Float(priorityInt)), values)
  }

  var description: String {
    return "\(active ? "EN" : "Dis"):\(values?.description ?? "nil")x@\(priority.rawValue)"
  }
}

/// struct VideoViewConstraints
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
  fileprivate func update(connectSpacers: Constraint,
                          aspect: AspectConstraint,
                          wMax: CGFloat? = nil, hMax: CGFloat? = nil, whMax_Priority: NSLayoutConstraint.Priority,
                          spacerMax: Constraint,
                          spacerMin: QuadConstraint,
                          spacerPreferred: QuadConstraint,
                          center: Constraint) {

    log.verbose{"Δ VideoView constraints ≔ maxSize:{w=\(wMax?.description ?? "nil") from super.w, h=\(hMax?.description ?? "nil") from super.h}@\(whMax_Priority.rawValue) spacers:{max=\(spacerMax) min=\(spacerMin) pref=\(spacerPreferred) center=\(center)} aspect=\(aspect)"}

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

    topSpacerConnection.priority = connectSpacers.priority
    bottomSpacerConnection.priority = connectSpacers.priority
    leadingSpacerConnection.priority = connectSpacers.priority
    trailingSpacerConnection.priority = connectSpacers.priority

    aspectRatio.priority = aspect.priority

    topSpacerMax.priority = spacerMax.priority
    trailingSpacerMax.priority = spacerMax.priority
    bottomSpacerMax.priority = spacerMax.priority
    leadingSpacerMax.priority = spacerMax.priority

    if let spacerPreferredQuad = spacerPreferred.values {
      topSpacerPreferred.animateToConstant(spacerPreferredQuad.top)
      bottomSpacerPreferred.animateToConstant(spacerPreferredQuad.bottom)
      leadingSpacerPreferred.animateToConstant(spacerPreferredQuad.leading)
      trailingSpacerPreferred.animateToConstant(spacerPreferredQuad.trailing)
    }
    topSpacerPreferred.priority = spacerPreferred.priority
    bottomSpacerPreferred.priority = spacerPreferred.priority
    trailingSpacerPreferred.priority = spacerPreferred.priority
    leadingSpacerPreferred.priority = spacerPreferred.priority

    if let wMax {
      widthMax.animateToConstant(wMax)
      widthMax.priority = whMax_Priority //+ (videoViewAspect > 1 ? 1 : 0)
    }
    if let hMax {
      heightMax.animateToConstant(hMax)
      heightMax.priority = whMax_Priority //+ (videoViewAspect > 1 ? 0 : 1)
    }

    centerX.priority = center.priority
    centerY.priority = center.priority

    // - Enablement

    topSpacerConnection.isActive = connectSpacers.active
    bottomSpacerConnection.isActive = connectSpacers.active
    leadingSpacerConnection.isActive = connectSpacers.active
    trailingSpacerConnection.isActive = connectSpacers.active

    aspectRatio.isActive = aspect.active

    topSpacerMax.isActive = spacerMax.active
    trailingSpacerMax.isActive = spacerMax.active
    bottomSpacerMax.isActive = spacerMax.active
    leadingSpacerMax.isActive = spacerMax.active

    topSpacerPreferred.isActive = spacerPreferred.active
    bottomSpacerPreferred.isActive = spacerPreferred.active
    trailingSpacerPreferred.isActive = spacerPreferred.active
    leadingSpacerPreferred.isActive = spacerPreferred.active

    // TODO: improvements for music mode
    widthMax.isActive = wMax != nil
    heightMax.isActive = hMax != nil

    centerX.isActive = center.active
    centerY.isActive = center.active

    updateSpacerMin(to: spacerMin.values, spacerMin.priority, active: spacerMin.active)
  }

  func updateSpacerMin(to quad: MarginQuad?, _ priority: NSLayoutConstraint.Priority, active: Bool = true) {
    if let quad {
      topSpacerMin.animateToConstant(quad.top)
      bottomSpacerMin.animateToConstant(quad.bottom)
      leadingSpacerMin.animateToConstant(quad.leading)
      trailingSpacerMin.animateToConstant(quad.trailing)

      topSpacerMin.priority = priority
      bottomSpacerMin.priority = priority
      trailingSpacerMin.priority = priority
      leadingSpacerMin.priority = priority
    }

    topSpacerMin.isActive = active
    bottomSpacerMin.isActive = active
    trailingSpacerMin.isActive = active
    leadingSpacerMin.isActive = active
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


extension VideoView {
  /// Convenience property
  var videoViewAspect: CGFloat? {  videoViewConstraints?.aspectRatio.multiplier }

  /// INIT constraints: Only called once, at VideoView init
  func initVideoConstraints() {
    translatesAutoresizingMaskIntoConstraints = false
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentHuggingPriority(.defaultLow, for: .vertical)
  }

  /// REMOVE constraints: Need to remove all constraints when in PiP: it will do layout based on the layer's `autoresizingMask`.
  func removeVideoConstraints() {
    guard let cons = videoViewConstraints else {
      log.verbose("VideoView: all video constraints already removed")
      return
    }

    log.verbose("VideoView: removing all video constraints")
    cons.disableAll()
    videoViewConstraints = nil
  }

  /// APPLY constraints: Add, update, or remove all constraints, based on the given geometry (or lack thereof).
  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

    guard let geometry, geometry.videoShown else {
      log.verbose{"VideoView: \(geometry == nil ? "no geometry" : "video not visible"); will remove constraints"}
      removeVideoConstraints()
      return
    }

    guard player.windowController.pip.status == .notInPIP else {
      if player.windowController.pip.status == .inPIP {
        log.verbose("VideoView: currently in PiP. Skipping constraints update & setting aspectRatio in PiP controller ≔ \(geometry.video.videoSizeCAR)")
        player.windowController.pip.controller.aspectRatio = geometry.video.videoSizeCAR
      } else {
        log.debug("VideoView: currently in PiP; skipping constraints update")
      }
      return
    }

    guard let superview else {
      // Can happen when in music mode with video disabled
      log.verbose("VideoView: no superview; skipping constraints update")
      return
    }

    let existing = videoViewConstraints
    let videoViewAspect = geometry.videoViewAspect

    let aspect: NSLayoutConstraint
    if let existing {
      if videoViewAspect != existing.aspectRatio.multiplier {
        // cannot reuse aspect constraint
        existing.aspectRatio.isActive = false
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoViewAspect, constant: 0)
      } else {
        aspect = existing.aspectRatio
      }
    } else {
      aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoViewAspect, constant: 0)
    }

    log.verbose("VideoView updating constraints: aspect=\(videoViewAspect) vidAspect=\(geometry.videoSize.mpvAspect) vidSize=\(geometry.videoSize) mode=\(geometry.mode)")

    let topSpacer = player.windowController.viewportView.topSpacer
    let bottomSpacer = player.windowController.viewportView.bottomSpacer
    let leadingSpacer = player.windowController.viewportView.leadingSpacer
    let trailingSpacer = player.windowController.viewportView.trailingSpacer

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

    let spacerMinValues: MarginQuad = (interactiveMode && !geometry.isMiddleTransition) ? Constants.InteractiveMode.viewportMargins : .zero

    // FIXME: keepVideoAwayFromBars is broken with keepaspect-window=no
    /// Special case if `keepVideoAwayFromBars` is enabled: keep video away from bars if possible
    let keepVideoAwayFromBars = Preference.bool(for: .keepVideoAwayFromBars) && !Preference.bool(for: .lockViewportToVideoSize)

    Logger.log("GEO: aspect=\(videoViewAspect) videoSize=\(geometry.videoSize) videoSizeIdeal=\(geometry.videoSizeIdeal)")
    let musicMode = geometry.mode == .musicMode && geometry.videoShown // TODO: improvements for music mode (search for this)
    // Need to keep priorities under 500 or the window will not resize!
    cons.update(connectSpacers: Constraint(active: true, priority: 1000),
                // The desired aspect must always be honored. All constraints are secondary to this.
                aspect: AspectConstraint(active: (interactiveMode || musicMode) && !geometry.isMiddleTransition,
                                         priority: .required,
                                         multiplier: videoViewAspect),

                /// For interactive mode, max width should equal superview's width minus minMargins
                wMax: -spacerMinValues.totalWidth,
                hMax: -spacerMinValues.totalHeight,
                whMax_Priority: .init(495),

                spacerMax: Constraint(active: !interactiveMode && !musicMode, priority: 490),

                // For interactive mode, these need to be higher priority than video max
                spacerMin: QuadConstraint(active: true, priority: 496, spacerMinValues),

                // TODO: split into vertical & horizontal components. Enable only when aspect goes above/below certain value
                spacerPreferred: QuadConstraint(active: false, priority: 481, keepVideoAwayFromBars ? geometry.insideBars : nil),

                // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
                center: Constraint(active: interactiveMode || musicMode, priority: 480)
                )


    videoViewConstraints = cons
    needsUpdateConstraints = true
    superview.layout()
  }

#if TEST_VIDEO_CONSTRAINTS
  func loosenConstraints() {
    guard let cons = videoViewConstraints else { return }

    cons.update(connectSpacers_Active: true, connectSpacers_Priority: .init(100),
                videoViewAspect: cons.aspectRatio.multiplier, aspect_Priority: .init(50),
                wMax: 0, hMax: 0, whMax_Priority: .init(99),
                spacerMax_Active: true, spacerMax_Priority: .init(98),
                spacerMin: nil, spacerMin_Priority: .init(97),
                spacerPreferred: nil, spacerPreferred_Priority: .init(97),
                center_Active: true, center_Priority: .init(96))
  }
#endif

}
