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
    return "\(active ? "Yes" : "No"):@\(priority.rawValue)"
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
    return "\(active ? "Yes" : "No"):\(values?.description ?? "nil")x@\(priority.rawValue)"
  }
}


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

  let topSpacerExact: NSLayoutConstraint
  let trailingSpacerExact: NSLayoutConstraint
  let bottomSpacerExact: NSLayoutConstraint
  let leadingSpacerExact: NSLayoutConstraint

  let widthMax: NSLayoutConstraint
  let heightMax: NSLayoutConstraint

  // Use aspect ratio constraint + weak center constraints to improve the video resize animation when tiling the window while
  // lockViewportToVideoSize is enabled.
  // Previously the video would get squeezed during resize. This became more noticable with the introduction of MacOS Sequoia 15.0.
  // These can be adjusted to keep VideoView away from "inside" bars.
  let centerX: NSLayoutConstraint
  let centerY: NSLayoutConstraint

  let aspectRatio: NSLayoutConstraint

  /// UPDATE FUNC
  fileprivate func update(connectSpacers: Constraint,
                          aspect: AspectConstraint,
                          wMax: CGFloat? = nil, hMax: CGFloat? = nil, whMax_Priority: NSLayoutConstraint.Priority,
                          spacerMax: Constraint,
                          spacerMin: QuadConstraint,
                          spacerPreferred: QuadConstraint,
                          spacerExact: QuadConstraint,
                          center: Constraint) {
    /*
    let topSpacersSame = (topSpacerConnection.isActive == connectSpacers.active) && (!topSpacerConnection.isActive || (topSpacerConnection.priority == connectSpacers.priority))
    let aspectSame = (aspectRatio.isActive == aspect.active) && (!aspect.active || (aspectRatio.priority.rawValue == aspect.priority.rawValue))
    let spacersMaxSame = (topSpacerMax.isActive == spacerMax.active) && (!spacerMax.active || (topSpacerMax.priority == spacerMax.priority))
    let whMaxSame = (widthMax.isActive == (wMax != nil)) && (heightMax.isActive == (hMax != nil)) && ((wMax == nil) || (whMax_Priority == widthMax.priority))
    let centerSame = centerX.isActive == center.active && (!center.active || (centerX.priority == center.priority))
    let spacerPreferredSame = (topSpacerPreferred.isActive == spacerPreferred.active) && (!spacerPreferred.active || (topSpacerPreferred.priority == spacerPreferred.priority))
    && ((spacerPreferred.values == nil) || (
      spacerPreferred.values!.top == topSpacerPreferred.constant ||
      spacerPreferred.values!.bottom == bottomSpacerPreferred.constant ||
      spacerPreferred.values!.leading == leadingSpacerPreferred.constant ||
      spacerPreferred.values!.trailing == trailingSpacerPreferred.constant))
    let spacerMinSame = (spacerMin.active == topSpacerMin.isActive) && (!spacerMin.active || (spacerMin.priority == topSpacerMin.priority)) &&
    ((spacerMin.values == nil) || (
      spacerMin.values!.top == topSpacerMin.constant ||
      spacerMin.values!.bottom == bottomSpacerMin.constant ||
      spacerMin.values!.leading == leadingSpacerMin.constant ||
      spacerMin.values!.trailing == trailingSpacerMin.constant))

    if topSpacersSame,
       aspectSame,
       spacersMaxSame,
       whMaxSame,
       centerSame,
       spacerPreferredSame,
       spacerMinSame {
      log.verbose{"Δ VideoViewConstraints: all same; aborting"}
      return
    }*/

    log.verbose{"Δ VideoViewConstraints ≔ MaxSize:{W=super.w-\(wMax?.description ?? "nil") H=super.h-\(hMax?.description ?? "nil")}@\(whMax_Priority.rawValue) SpcMax=\(spacerMax) SpcMin=\(spacerMin) SpcPref=\(spacerPreferred) Center=\(center) Aspect=\(aspect)"}

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

    if let spacerExactQuad = spacerExact.values {
      topSpacerExact.animateToConstant(spacerExactQuad.top)
      bottomSpacerExact.animateToConstant(spacerExactQuad.bottom)
      leadingSpacerExact.animateToConstant(spacerExactQuad.leading)
      trailingSpacerExact.animateToConstant(spacerExactQuad.trailing)
    }
    topSpacerExact.priority = spacerExact.priority
    bottomSpacerExact.priority = spacerExact.priority
    trailingSpacerExact.priority = spacerExact.priority
    leadingSpacerExact.priority = spacerExact.priority

    if let wMax {
      widthMax.animateToConstant(wMax)
      widthMax.priority = whMax_Priority
    }
    if let hMax {
      heightMax.animateToConstant(hMax)
      heightMax.priority = whMax_Priority
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

    topSpacerExact.isActive = spacerExact.active
    bottomSpacerExact.isActive = spacerExact.active
    trailingSpacerExact.isActive = spacerExact.active
    leadingSpacerExact.isActive = spacerExact.active

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

    topSpacerExact.isActive = false
    trailingSpacerExact.isActive = false
    bottomSpacerExact.isActive = false
    leadingSpacerExact.isActive = false

    widthMax.isActive = false
    heightMax.isActive = false

    centerX.isActive = false
    centerY.isActive = false

    aspectRatio.isActive = false
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
    guard let pwc else { return }

    guard let geometry, geometry.isViewportShown else {
      log.verbose{"VideoView: \(geometry == nil ? "no geometry" : "video not visible"); will remove constraints"}
      removeVideoConstraints()
      return
    }

    guard pwc.pip.status == .notInPIP else {
      if pwc.pip.status == .inPIP {
        log.verbose("VideoView: currently in PiP. Skipping constraints update & setting aspectRatio in PiP controller ≔ \(geometry.video.videoSizeCAR)")
        pwc.pip.controller.aspectRatio = geometry.video.videoSizeCAR
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
      if videoViewAspect == existing.aspectRatio.multiplier {
        aspect = existing.aspectRatio
      } else {
        // cannot reuse aspect constraint
        existing.aspectRatio.isActive = false
        aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoViewAspect, constant: 0)
      }
    } else {
      aspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: videoViewAspect, constant: 0)
    }

    log.verbose("VideoView updating constraints: aspect=\(videoViewAspect) vidAspect=\(geometry.videoSize.mpvAspect) vidSize=\(geometry.videoSize) vidSizeIdeal=\(geometry.videoSizeIdeal) mode=\(geometry.mode)")

    let topSpacer = pwc.viewportView.topSpacer
    let bottomSpacer = pwc.viewportView.bottomSpacer
    let leadingSpacer = pwc.viewportView.leadingSpacer
    let trailingSpacer = pwc.viewportView.trailingSpacer

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

      // Exact spacer sizes:
      topSpacerExact: existing?.topSpacerExact ?? topSpacer.heightAnchor.constraint(equalToConstant: 0),
      trailingSpacerExact: existing?.trailingSpacerExact ?? trailingSpacer.widthAnchor.constraint(equalToConstant: 0),
      bottomSpacerExact: existing?.bottomSpacerExact ?? bottomSpacer.heightAnchor.constraint(equalToConstant: 0),
      leadingSpacerExact: existing?.leadingSpacerExact ?? leadingSpacer.widthAnchor.constraint(equalToConstant: 0),

      // These maximize video size
      widthMax: existing?.widthMax ?? widthAnchor.constraint(equalTo: superview.widthAnchor),
      heightMax: existing?.heightMax ?? heightAnchor.constraint(equalTo: superview.heightAnchor),

      centerX: existing?.centerX ?? centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: 0),
      centerY: existing?.centerY ?? centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: 0),

      aspectRatio: aspect
    )

    // - Configuration

    let interactiveMode = geometry.mode.isInteractiveMode
    let musicMode = geometry.mode == .musicMode && geometry.isViewportShown

    // spacerMin == viewport min margins
    let spacerMinValues: MarginQuad = interactiveMode && !geometry.isMiddleTransition ? GeoUtil.minViewportMargins(forMode: geometry.mode) : .zero

    /// Special case if `keepVideoAwayFromBars` is enabled: keep video away from bars if possible
    let keepVideoAwayFromBars = !interactiveMode && !musicMode && Preference.bool(for: .keepVideoAwayFromBars) && !Preference.bool(for: .lockViewportToVideoSize)
    let spacerExactValues: MarginQuad? = keepVideoAwayFromBars ? geometry.offsetsToKeepVideoAwayFromInsideBars : nil

    // Need to keep priorities under 500 or the window will not resize!
    cons.update(connectSpacers: Constraint(active: true, priority: 1000),
                // The desired aspect must always be honored. All constraints are secondary to this.
                aspect: AspectConstraint(active: (interactiveMode || musicMode) && !geometry.isMiddleTransition,
                                         priority: .required,
                                         multiplier: videoViewAspect),

                /// For interactive mode, max width should equal superview's width minus minMargins
                wMax: -spacerMinValues.totalWidth,
                hMax: -spacerMinValues.totalHeight,
                whMax_Priority: musicMode ? .required : .init(495),

                spacerMax: Constraint(active: !interactiveMode && !musicMode, priority: 490),

                // For interactive mode, these need to be higher priority than video max
                spacerMin: QuadConstraint(active: true, priority: 496, spacerMinValues),

                // Need to calculate these values ourselves now that we are relying on mpv to calculate margins for us via keepaspect=yes
                spacerPreferred: QuadConstraint(active: false, priority: 481, spacerExactValues),

                // Need to calculate these values ourselves now that we are relying on mpv to calculate margins for us via keepaspect=yes
                spacerExact: QuadConstraint(active: keepVideoAwayFromBars, priority: 497, spacerExactValues),

                // Try to prevent overlap with the inner bars, if possible. But this is a lower priority.
                center: Constraint(active: (interactiveMode || musicMode) && !geometry.isMiddleTransition, priority: 480)
                )


    videoViewConstraints = cons
    needsUpdateConstraints = true
    superview.needsLayout = true
  }

}
