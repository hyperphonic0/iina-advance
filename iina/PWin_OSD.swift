//
//  PWin_OSD.swift
//  iina
//
//  Created by Matt Svoboda on 6/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation
import Mustache

// Avoid constraint violations during window resize
fileprivate let constraintPriorityInt = 400
fileprivate let lowerConstraintPriorityInt = 300
fileprivate let standardOffset: CGFloat = 8

/// Encapsulates all of the window's OSD state vars
///
/// OSD constraints: shown here in "upper-left" configuration.
/// For "upper-right" config: swap OSD & AdditionalInfo anchors in A & B, and invert all the params of B.
/// ```
/// ┌───────────────────────┐
/// │ A ┌────┐  ┌───────┐ B │  A: leadingSide_LeadingConstraint
/// │◄─►│ OSD│  │ AddNfo│◄─►│  B: trailingSide_TrailingConstraint
/// │   └────┘  └───────┘   │
/// └───────────────────────┘
/// ```
final class OSDState {
  let log: any Logger.Subsystem

  // - Views

  let osdView: OSDView
  fileprivate let osdVStackView: ClickThroughStackView
  fileprivate let osdIconImageView: NSImageView
  /// Use label constructor (even with empty string) to ensure proper styling
  fileprivate let osdLabel: NSTextField
  fileprivate let osdAccessoryText: NSTextField
  fileprivate let osdAccessoryProgress: FixedProgressBar

  // - Internal constraints (not actually optional)

  // Icon size
  fileprivate let osdIconWidthConstraint = OptionalConstraint("OSDIcon.width")
  fileprivate let osdIconHeightConstraint = OptionalConstraint("OSDIcon.height")
  // Internal padding
  fileprivate let osdTopPaddingConstraint = OptionalConstraint("OSD-TopPadding")
  fileprivate let osdTrailingPaddingConstraint = OptionalConstraint("OSD-TrailingPadding")
  fileprivate let osdLeadingPaddingConstraint = OptionalConstraint("OSD-LeadingPadding")
  fileprivate let osdBtmPaddingConstraint = OptionalConstraint("OSD-BtmPadding")

  fileprivate let osdProgressHeightConstraint = OptionalConstraint("OSDProgress.height")
  fileprivate let iconToVStackSpacingConstraint = OptionalConstraint("OSDIcon-to-VStack.hSpacing")

  // - Optional constraints

  fileprivate let leadingSide_TopOffsetConstraint = OptionalConstraint("LeadingOSD.top-offset-from-VP.top")
  fileprivate let leadingSide_BtmOffsetConstraint = OptionalConstraint("VP.btm-offset-from-LeadingOSD.btm")
  fileprivate let trailingSide_TopOffsetConstraint = OptionalConstraint("TrailingOSD-TopOffset")
  fileprivate let trailingSide_BtmOffsetConstraint = OptionalConstraint("TrailingOSD-BtmOffset")

  fileprivate let leadingSide_LeadingConstraint = OptionalConstraint("LeadingOSD-Leading")
  fileprivate let leadingSide_TrailingConstraint = OptionalConstraint("LeadingOSD-Trailing")
  fileprivate let trailingSide_LeadingConstraint = OptionalConstraint("TrailingOSD-Leading")
  fileprivate let trailingSide_TrailingConstraint = OptionalConstraint("TrailingOSD-Trailing")

  fileprivate var optionalConstraints: [OptionalConstraint] {
    [
      leadingSide_TopOffsetConstraint, leadingSide_BtmOffsetConstraint,
      trailingSide_TopOffsetConstraint, trailingSide_BtmOffsetConstraint,
      leadingSide_LeadingConstraint, leadingSide_TrailingConstraint,
      trailingSide_LeadingConstraint, trailingSide_TrailingConstraint,
    ]
  }

  /// Whether current OSD needs user interaction to be dismissed.
  var isShowingPersistentOSD = false
  var animationState: PlayerWindowController.UIAnimationState = .hidden
  /// Timeout action is `pwc.hideOSD()`
  let hideOSDTimer = TimeoutTimer(timeout: OSDState.osdTimeoutFromPrefs())
  var nextSeekIcon: NSImage? = nil
  var currentSeekIcon: NSImage? = nil
  var lastPlaybackPosition: Double? = nil
  var lastPlaybackDuration: Double? = nil
  private var lastDisplayedMsgTS: TimeInterval = 0
  var lastDisplayedMsg: OSDMessage? = nil {
    didSet {
      guard lastDisplayedMsg != nil else { return }
      lastDisplayedMsgTS = Date().timeIntervalSince1970
    }
  }
  var currentlyDisplayedMsg: OSDMessage? {
    return animationState == .shown ? lastDisplayedMsg : nil
  }
  /// "Recently" here is defined as: having been shown in the last 0.25 sec.
  func didShowLastMsgRecently() -> Bool {
    return Date().timeIntervalSince1970 - lastDisplayedMsgTS < 0.25
  }
  func didShowLastMsgSomewhatRecently() -> Bool {
    return Date().timeIntervalSince1970 - lastDisplayedMsgTS < 0.5
  }

  // Need to keep a reference to NSViewController here in order for its Objective-C selectors to work
  var context: NSViewController? = nil {
    willSet {
      guard newValue != context else { return }
      if let newValue {
        log.verbose("Updating osd.context to: \(newValue)")
      } else {
        log.verbose("Updating osd.context to: nil")
      }
    }
  }
  var textSizeLast: CGFloat = 0
  let queueLock = Lock()
  var queue = LinkedList<() -> Void>()

  func clearQueuedOSDs() {
    queueLock.withLock {
      queue.clear()
    }
  }

  @MainActor
  init(log: any Logger.Subsystem) {
    self.log = log

    log.verbose("Init OSD")

    osdView = OSDView()
    osdVStackView = ClickThroughStackView()
    osdIconImageView = NSImageView()
    /// Use label constructor (even with empty string) to ensure proper styling
    osdLabel = NSTextField(labelWithString: "")
    osdAccessoryText = NSTextField(labelWithString: "")
    osdAccessoryProgress = FixedProgressBar()

    osdIconImageView.idString = "OSDIconImageView"
    osdIconImageView.imageScaling = .scaleProportionallyUpOrDown
    osdIconImageView.imageAlignment = .alignCenter
    osdIconImageView.translatesAutoresizingMaskIntoConstraints = false
    osdIconImageView.refusesFirstResponder = true
    osdIconImageView.setContentHugging(h: 1000, v: 1000)
    osdIconImageView.setCCResistance(h: 1000, v: 1000)

    osdLabel.idString = "OSD-Label"
    osdLabel.translatesAutoresizingMaskIntoConstraints = false
    osdLabel.setContentHuggingPriority(.init(251), for: .horizontal)
    osdLabel.setContentCompressionResistancePriority(.init(499), for: .horizontal)
    osdLabel.setContentCompressionResistancePriority(.init(1000), for: .vertical)
    osdLabel.focusRingType = .none
    osdLabel.lineBreakMode = .byTruncatingTail
    osdLabel.alignment = .left
    osdLabel.usesSingleLineMode = true
    osdLabel.wantsLayer = true

    osdAccessoryText.idString = "OSD-AccText"
    osdAccessoryText.wantsLayer = true
    osdAccessoryText.translatesAutoresizingMaskIntoConstraints = false
    osdAccessoryText.setContentHuggingPriority(.init(251), for: .horizontal)
    osdAccessoryText.setContentHuggingPriority(.init(750), for: .vertical)
    osdAccessoryText.setContentCompressionResistancePriority(.init(499), for: .horizontal)
    osdAccessoryText.setContentCompressionResistancePriority(.init(1000), for: .vertical)
    osdAccessoryText.focusRingType = .none
    osdAccessoryText.lineBreakMode = .byClipping
    osdAccessoryText.alignment = .justified
    osdAccessoryText.wantsLayer = true
    osdAccessoryText.font = .messageFont(ofSize: 11)
    osdAccessoryText.textColor = .disabledControlTextColor
    osdAccessoryText.backgroundColor = .controlColor

    osdAccessoryProgress.idString = "OSD-ProgressBar"
    osdAccessoryProgress.translatesAutoresizingMaskIntoConstraints = false
    osdAccessoryProgress.setContentHuggingPriority(.init(270), for: .horizontal)
    osdAccessoryProgress.setContentCompressionResistancePriority(.required, for: .vertical)

    osdView.subviews = [osdIconImageView, osdVStackView]

    osdVStackView.idString = "OSD-VStackView"
    osdVStackView.wantsLayer = true
    osdVStackView.orientation = .vertical
    osdVStackView.alignment = .leading
    osdVStackView.distribution = .fillProportionally
    osdVStackView.spacing = 0
    osdVStackView.detachesHiddenViews = true
    osdVStackView.translatesAutoresizingMaskIntoConstraints = false

    osdVStackView.addView(osdLabel, in: .leading)
    osdVStackView.addView(osdAccessoryText, in: .leading)
    osdVStackView.addView(osdAccessoryProgress, in: .leading)

    // Use initial size of 0, in case MacOS 11 code never gets executed
    let initialIconSize: CGFloat = 0
    osdIconWidthConstraint.createOrUpdate(to: initialIconSize, priorityInt: 1000, log) { [self] c in
      osdIconImageView.widthAnchor.constraint(equalToConstant: c)
    }
    osdIconHeightConstraint.createOrUpdate(to: initialIconSize, priorityInt: 1000, log) { [self] c in
      osdIconImageView.heightAnchor.constraint(equalToConstant: c)
    }

    osdTopPaddingConstraint.createOrUpdate(to: standardOffset, priorityInt: 1000, log) { [self] c in
      osdVStackView.topAnchor.constraint(equalTo: osdView.topAnchor, constant: c)
    }
    osdBtmPaddingConstraint.createOrUpdate(to: standardOffset, priorityInt: 1000, log) { [self] c in
      osdView.bottomAnchor.constraint(equalTo: osdVStackView.bottomAnchor, constant: c)
    }
    osdLeadingPaddingConstraint.createOrUpdate(to: standardOffset, priorityInt: 1000, log) { [self] c in
      osdIconImageView.leadingAnchor.constraint(equalTo: osdView.leadingAnchor, constant: c)
    }
    osdTrailingPaddingConstraint.createOrUpdate(to: standardOffset, priorityInt: 1000, log) { [self] c in
      osdView.trailingAnchor.constraint(equalTo: osdVStackView.trailingAnchor, constant: c)
    }
    // Progress bar height
    osdProgressHeightConstraint.createOrUpdate(to: 0, priorityInt: 1000, log) { [self] c in
      osdAccessoryProgress.heightAnchor.constraint(equalToConstant: c)
    }

    // Space between icon & VStack to the right of it. Start with 0, assuming icon is not shown
    // [osdIconImageView]-4-[osdVStackView]
    iconToVStackSpacingConstraint.createOrUpdate(to: 0, priorityInt: 1000, log) { [self] c in
      osdVStackView.leadingAnchor.constraint(equalTo: osdIconImageView.trailingAnchor, constant: c)
    }

    // Center the icon vertically
    osdIconImageView.centerYAnchor.constraint(equalTo: osdView.centerYAnchor).isActive = true
  }

  @MainActor
  fileprivate func updateIconSize(isIconVisible: Bool) {
    guard #available(macOS 11.0, *) else { return }
    let iconHeight, iconWidth: CGFloat

    // Don't want to animate the following
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setAnimationDuration(0.0)

    if isIconVisible, let icon = osdIconImageView.image {
      let osdTextSize = textSizeLast
      let sliderBarHeight = getSliderBarHeight(forOSDTextSize: osdTextSize)

      // Use dimensions of a dummy image to keep the height fixed. Because all the components are vertically aligned
      // and each icon has a different height, this is needed to prevent the progress bar from jumping up and down
      // each time the OSD message changes.
      let attachment = NSTextAttachment()
      attachment.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "")!
      let iconString = NSMutableAttributedString(attachment: attachment)
      let osdIconTextSize = ((osdTextSize + sliderBarHeight) * 1.15).rounded()
      let osdIconFont = NSFont.monospacedDigitSystemFont(ofSize: osdIconTextSize, weight: .regular)
      iconString.addAttribute(.font, value: osdIconFont, range: NSRange(location: 0, length: iconString.length))
      iconHeight = iconString.size().height
      iconWidth = (icon.size.aspect * iconHeight)

    } else {
      iconHeight = 0.0
      iconWidth = 0.0
    }

    osdIconHeightConstraint.constraint?.animateToConstant(iconHeight)
    osdIconWidthConstraint.constraint?.animateToConstant(iconWidth)
    CATransaction.commit()
  }

  @MainActor
  func updateProgressBarStyle(_ appearance: NSAppearance, effectiveOSCColorScheme: Preference.OSCColorScheme) {
    let osdTextSize = textSizeLast
    guard osdTextSize > 0 else { return }

    let sliderBarHeight = getSliderBarHeight(forOSDTextSize: osdTextSize)
    osdAccessoryProgress.barFactory = BarFactory(effectiveAppearance: appearance,
                                                 effectiveOSCColorScheme: effectiveOSCColorScheme,
                                                 sliderBarHeight_Normal: sliderBarHeight)
    osdProgressHeightConstraint.constraint!.animateToConstant(sliderBarHeight * 2)
    osdView.needsLayout = true
  }

  static func osdTimeoutFromPrefs() -> Double {
    // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    return max(Constants.TimeInterval.osdTimeoutMin, Double(Preference.float(for: .osdAutoHideTimeout)))
  }

  fileprivate func getOSDTextSize(from givenGeo: PWinGeometry) -> CGFloat {
    let availableSpaceForOSD = givenGeo.widthBetweenInsideSidebars

    // Reduce text size if horizontal space is tight
    var osdTextSize = max(Constants.OSD.minTextSize, CGFloat(Preference.float(for: .osdTextSize)))
    switch availableSpaceForOSD {
    case ..<300:
      osdTextSize = min(osdTextSize, 18)
    case 300..<400:
      osdTextSize = min(osdTextSize, 28)
    case 400..<500:
      osdTextSize = min(osdTextSize, 36)
    case 500..<700:
      osdTextSize = min(osdTextSize, 50)
    case 700..<900:
      osdTextSize = min(osdTextSize, 72)
    case 900..<1200:
      osdTextSize = min(osdTextSize, 96)
    case 1200..<1500:
      osdTextSize = min(osdTextSize, 120)
    default:
      osdTextSize = min(osdTextSize, 150)
    }

    return osdTextSize
  }

  fileprivate func getSliderBarHeight(forOSDTextSize osdTextSize: CGFloat) -> CGFloat {
    guard osdTextSize > 0 else { return 0 }

    switch osdTextSize {
    case ..<32:
      return 4
    default:
      return (osdTextSize / 8).rounded()
    }
  }

}

class OSDView: ClickThroughVisualEffectView {
  init() {
    super.init(frame: .zero)
    blendingMode = .withinWindow
    material = .toolTip
    state = .active
    idString = "OSDView"
    translatesAutoresizingMaskIntoConstraints = false

    // Min width
    let osdMinWidthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
    osdMinWidthConstraint.identifier = "OSDView-MinWidthConstraint"
    osdMinWidthConstraint.priority = .init(900)
    osdMinWidthConstraint.isActive = true
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// The Additional Info view displays a battery time indicator & the media title when in full screen.
class AdditionalInfoView: MouseIgnoringVisualEffectView {
  fileprivate let titleLabel = ResizableTextView(lineBreakMode: .byTruncatingMiddle)
  fileprivate let hStackView = NSStackView()
  fileprivate let clockTimeLabel = NSTextField(labelWithString: "99:99")
  fileprivate let batteryView = NSView()
  fileprivate let batteryLabel = NSTextField(labelWithString: "100%")

  init() {
    super.init(frame: .zero)
    blendingMode = .withinWindow
    material = .popover
    state = .active
    idString = "AdditionalInfoView"
    translatesAutoresizingMaskIntoConstraints = false
    let batteryOffsetX: CGFloat = -4

    subviews = [titleLabel, hStackView]

    titleLabel.idString = "AdditionalInfo-Title"
    titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
    titleLabel.alignment = .right
    titleLabel.setContentCompressionResistancePriority(.init(499), for: .horizontal)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
    titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
    trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8).isActive = true

    let labelContainerView = NSView()
    labelContainerView.translatesAutoresizingMaskIntoConstraints = false
    labelContainerView.heightAnchor.constraint(equalToConstant: 30).isActive = true
    labelContainerView.subviews = [clockTimeLabel]

    clockTimeLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
    clockTimeLabel.alignment = .right
    clockTimeLabel.textColor = .secondaryLabelColor
    clockTimeLabel.backgroundColor = .textBackgroundColor
    clockTimeLabel.idString = "AdditionalInfo-Label"
    clockTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    clockTimeLabel.leadingAnchor.constraint(equalTo: labelContainerView.leadingAnchor, constant: 6).isActive = true
    labelContainerView.trailingAnchor.constraint(equalTo: clockTimeLabel.trailingAnchor).isActive = true
    clockTimeLabel.centerYAnchor.constraint(equalTo: labelContainerView.centerYAnchor, constant: -1).isActive = true

    let verticalLine = NSBox()
    verticalLine.boxType = .separator
    verticalLine.translatesAutoresizingMaskIntoConstraints = false
    verticalLine.heightAnchor.constraint(equalToConstant: 12).isActive = true

    hStackView.idString = "AdditionalInfo-HStackView"
    hStackView.orientation = .horizontal
    hStackView.alignment = .centerY
    hStackView.distribution = .fill
    hStackView.spacing = 6
    hStackView.wantsLayer = true
    hStackView.detachesHiddenViews = true
    hStackView.translatesAutoresizingMaskIntoConstraints = false

    hStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4).isActive = true
    hStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
    trailingAnchor.constraint(equalTo: hStackView.trailingAnchor, constant: 8).isActive = true
    bottomAnchor.constraint(equalTo: hStackView.bottomAnchor, constant: 4).isActive = true

    // - Battery

    batteryView.idString = "AdditionalInfoBatteryView"
    batteryView.wantsLayer = true
    batteryView.translatesAutoresizingMaskIntoConstraints = false
    batteryView.heightAnchor.constraint(equalToConstant: 30).isActive = true
    batteryView.widthAnchor.constraint(equalToConstant: 56).isActive = true

    batteryLabel.idString = "AdditionalInfoBattery-Text"
    batteryLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
    batteryLabel.textColor = .secondaryLabelColor
    batteryLabel.backgroundColor = .textBackgroundColor
    batteryLabel.setContentHuggingPriority(.init(251), for: .horizontal)
    batteryLabel.translatesAutoresizingMaskIntoConstraints = false

    let batteryImage = NSImage(named: "battery")!
    let batteryImageView = NSImageView(image: batteryImage)
    batteryImageView.imageScaling = .scaleProportionallyUpOrDown
    batteryImageView.wantsLayer = true
    batteryImageView.setContentHugging(h: 251, v: 251)
    batteryImageView.translatesAutoresizingMaskIntoConstraints = false

    batteryView.subviews = [batteryLabel, batteryImageView]
    batteryImageView.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: batteryOffsetX, trailing: -batteryOffsetX)
    batteryLabel.centerXAnchor.constraint(equalTo: batteryView.centerXAnchor, constant: batteryOffsetX).isActive = true
    batteryLabel.centerYAnchor.constraint(equalTo: batteryView.centerYAnchor, constant: -0.5).isActive = true

    for subview in [labelContainerView, verticalLine, batteryView] {
      hStackView.addView(subview, in: .trailing)
      subview.autoresizesSubviews = false
    }
    batteryView.autoresizesSubviews = false
    batteryLabel.autoresizesSubviews = false
    batteryImageView.autoresizesSubviews = false
    titleLabel.autoresizesSubviews = false
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// PlayerWindow UI: OSD
extension PlayerWindowController {
  fileprivate func updateCornerRoundness(fromOSDTextSize osdTextSize: CGFloat) {
    if #available(macOS 26, *) {
      // MacOS Tahoe's style favors rounder corners. Try to fit in
      let cornerRadius = 10 + (osdTextSize * 0.25).rounded()
      osd.osdView.roundCorners(withRadius: cornerRadius)
      additionalInfoView.roundCorners(withRadius: cornerRadius)
    } else {
      // Pre-Tahoe
      osd.osdView.roundCorners()
      additionalInfoView.roundCorners()
    }
  }

  func addOrRemoveOSDViews(for stage: LayoutTransition.Stage, _ stageGeo: PWinGeometry) {
    var addedSomething = false
    if stageGeo.shouldHaveOSD {
      if !viewportView.subviews.contains(osd.osdView) {
        log.verbose("[OSD] Adding osdView to viewportView")
        viewportView.addSubview(osd.osdView)  // will sort below
        addedSomething = true
      }

    } else {
      if osd.osdView.superview != nil {
        log.verbose("[OSD] Removing osdView from superview")
        osd.osdView.removeFromSuperview()
      }
    }

    if stageGeo.shouldHaveAdditionalInfo {
      if !viewportView.subviews.contains(additionalInfoView) {
        log.verbose("[OSD] Adding additionalInfoView to viewportView")
        viewportView.addSubview(additionalInfoView)  // will sort below
        fadeableViews.applyVisibility(.hidden, additionalInfoView)  // hide for now. Will show in later stage
        addedSomething = true
      }
      updateAdditionalInfoContent()  // update content

    } else {
      if additionalInfoView.superview != nil {
        log.verbose("[OSD] Removing additionalInfoView from superview")
        additionalInfoView.removeFromSuperview()
      }
    }

    if addedSomething {
      updateOSDTextSize(from: stageGeo)

      sortViewportViewSubviews()
      window?.contentView?.needsLayout = true
    }
  }

  /// - Enforces `Preference.Key.osdPosition` pref which allows OSD to be on either left or right.
  /// - For many of the constraints, priority=900 will be used to avoid problems with black swan layouts
  /// which might trigger constraint violations if priority=required were used.
  /// - Setting `skipAddConstraints` to `true` is a kludge for special use during layout transitions
  func updateOSDConstraints(for stage: LayoutTransition.Stage = .postTransition, _ stageGeo: PWinGeometry) {
    for optCon in osd.optionalConstraints {
      optCon.weaken()
    }
    let offsetFromTop = stageGeo.osdOffsetFromTopOfViewport()

    let hasOSD = stageGeo.shouldHaveOSD
    let hasAdditionalInfo = stageGeo.shouldHaveAdditionalInfo
    let osdPosition: Preference.OSDPosition = Preference.enum(for: .osdPosition)
    let hasLeadingSidebar = stageGeo.insideBars.leading > 0
    let hasTrailingSidebar = stageGeo.insideBars.trailing > 0

    log.verbose("[OSD] Updating constraints: hasOSD=\(hasOSD.yn) hasAddlInfo=\(hasAdditionalInfo.yn) leadingSB=\(hasLeadingSidebar.yn) trailingSB=\(hasTrailingSidebar.yn) offsetFromTop=\(offsetFromTop)")

    let leadingView = osdPosition == .topLeading ? (hasOSD ? osd.osdView : nil) :  (hasAdditionalInfo ? additionalInfoView : nil)
    let trailingView = osdPosition == .topLeading ? (hasAdditionalInfo ? additionalInfoView : nil) :  (hasOSD ? osd.osdView : nil)

    let otherAnchorLeading = hasLeadingSidebar ? leadingSidebarView.trailingAnchor : viewportView.leadingAnchor
    let otherAnchorTrailing = hasTrailingSidebar ? trailingSidebarView.leadingAnchor : viewportView.trailingAnchor

    if let leadingView {
      osd.leadingSide_LeadingConstraint.createOrUpdate(to: standardOffset, priorityInt: constraintPriorityInt,
                                                       requiredFirstAnchor: leadingView.leadingAnchor,
                                                       requiredSecondAnchor: otherAnchorLeading, log) { c in
        leadingView.leadingAnchor.constraint(equalTo: otherAnchorLeading, constant: c)
      }

      osd.leadingSide_TrailingConstraint.createOrUpdate(to: standardOffset, priorityInt: lowerConstraintPriorityInt,
                                                        requiredFirstAnchor: otherAnchorTrailing,
                                                        requiredSecondAnchor: leadingView.trailingAnchor, log) { c in
        otherAnchorTrailing.constraint(greaterThanOrEqualTo: leadingView.trailingAnchor, constant: c)
      }

      osd.leadingSide_TopOffsetConstraint.createOrUpdate(to: offsetFromTop, priorityInt: constraintPriorityInt,
                                                 requiredFirstAnchor: leadingView.topAnchor,
                                                 requiredSecondAnchor: viewportView.topAnchor, log) { [self] c in
        leadingView.topAnchor.constraint(equalTo: viewportView.topAnchor, constant: c)
      }

      osd.leadingSide_BtmOffsetConstraint.createOrUpdate(to: standardOffset, priorityInt: constraintPriorityInt,
                                                    requiredFirstAnchor: viewportView.bottomAnchor,
                                                    requiredSecondAnchor: leadingView.bottomAnchor, log) { [self] c in
        viewportView.bottomAnchor.constraint(greaterThanOrEqualTo: leadingView.bottomAnchor, constant: c)
      }
    }

    if let trailingView {
      osd.trailingSide_TrailingConstraint.createOrUpdate(to: standardOffset, priorityInt: constraintPriorityInt,
                                                         requiredFirstAnchor: otherAnchorTrailing,
                                                         requiredSecondAnchor: trailingView.trailingAnchor, log) { c in
        otherAnchorTrailing.constraint(equalTo: trailingView.trailingAnchor, constant: c)
      }

      osd.trailingSide_LeadingConstraint.createOrUpdate(to: standardOffset, priorityInt: lowerConstraintPriorityInt,
                                                        requiredFirstAnchor: otherAnchorLeading,
                                                        requiredSecondAnchor: trailingView.leadingAnchor, log) { c in
        otherAnchorLeading.constraint(lessThanOrEqualTo: trailingView.leadingAnchor, constant: c)
      }

      osd.trailingSide_TopOffsetConstraint.createOrUpdate(to: offsetFromTop, priorityInt: constraintPriorityInt,
                                                 requiredFirstAnchor: trailingView.topAnchor,
                                                 requiredSecondAnchor: viewportView.topAnchor, log) { [self] c in
        trailingView.topAnchor.constraint(equalTo: viewportView.topAnchor, constant: c)
      }

      osd.trailingSide_BtmOffsetConstraint.createOrUpdate(to: standardOffset, priorityInt: constraintPriorityInt,
                                                    requiredFirstAnchor: viewportView.bottomAnchor,
                                                    requiredSecondAnchor: trailingView.bottomAnchor, log) { [self] c in
        viewportView.bottomAnchor.constraint(greaterThanOrEqualTo: trailingView.bottomAnchor, constant: c)
      }
    }
  }

  /// Update OSD view & Additional Info view constraints so they have the correct offset from top of screen.
  func updateOSDTopOffsetConstraints(for geometry: PWinGeometry) {
    let newOffsetFromTop = geometry.osdOffsetFromTopOfViewport()

    log.verbose("[OSD] Updating top constraint to: \(newOffsetFromTop)")
    osd.leadingSide_TopOffsetConstraint.constraint?.animateToConstant(newOffsetFromTop)
    osd.trailingSide_TopOffsetConstraint.constraint?.animateToConstant(newOffsetFromTop)
  }

  // MARK: - Additional Info Content Updates

  /// Update `additionalInfoView` with battery status & media title
  func updateAdditionalInfoContent() {
    log.trace{"[OSD] Updating additionalInfoView content with URL: \(player.info.currentPlayback?.url.lastPathComponent ?? "nil")"}
    guard let title = player.info.currentPlayback?.url.lastPathComponent else { return }
    additionalInfoView.titleLabel.string = title
    additionalInfoView.titleLabel.sizeToFit()
    additionalInfoView.titleLabel.invalidateIntrinsicContentSize()
    additionalInfoView.needsLayout = true  // Need this for titleLabel to update

    if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
      additionalInfoView.batteryLabel.stringValue = "\(capacity)%"
      additionalInfoView.hStackView.setVisibilityPriority(.mustHold, for: additionalInfoView.batteryView)
    } else {
      additionalInfoView.hStackView.setVisibilityPriority(.notVisible, for: additionalInfoView.batteryView)
    }
    additionalInfoView.clockTimeLabel.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
  }

  // MARK: - OSD Content Updates

  /// If `newMessage` is provided, the OSD will be updated to display it. Otherwise if the OSD is
  /// already shown and is displaying one of the message types which requires live updates, it will be updated.
  @MainActor
  func setOSDViews(fromMessage newMessage: OSDMessage? = nil) {
    let message: OSDMessage?

    if let newMessage {
      message = newMessage

    } else if let currentMsg = osd.currentlyDisplayedMsg,
              let position = player.info.playbackPositionSec,
              let duration = player.info.playbackDurationSec {
      // If the OSD is visible and is showing playback position, keep its displayed time up to date:
      switch currentMsg {
      case .pause:
        message = .pause(posSec: position, durSec: duration)
      case .resume:
        message = .resume(posSec: position, durSec: duration)
      case .seek(_, _):
        message = .seek(posSec: position, durSec: duration)
      default:
        message = nil
      }
    } else {
      message = nil
    }

    defer {
      osd.osdView.needsLayout = true
      osd.osdView.needsDisplay = true
    }

    if let displayedMesg = message ?? osd.lastDisplayedMsg {
      updateOSDIcon(from: displayedMesg)
    }

    guard let message else {
      // Often this method was called in response to a layout change.
      // For some reason the text wrap of the following is not recomputed or the text may be smashed/stretched,
      // so mark it expclitly as needing layout above before returning.
      return
    }


    let (osdText, osdType) = message.details()
    osd.osdLabel.stringValue = osdText

    // Most OSD messages are displayed based on the configured language direction.
    osd.osdAccessoryProgress.userInterfaceLayoutDirection = osd.osdVStackView.userInterfaceLayoutDirection
    osd.osdAccessoryText.baseWritingDirection = .natural
    osd.osdLabel.baseWritingDirection = .natural
    switch osdType {
    case .normal:
      osd.osdVStackView.setVisibilityPriority(.notVisible, for: osd.osdAccessoryText)
      osd.osdVStackView.setVisibilityPriority(.notVisible, for: osd.osdAccessoryProgress)
    case .withLeftToRightProgress(let value):
      // OSD messages displaying the playback position must always be displayed left to right.
      osd.osdAccessoryProgress.userInterfaceLayoutDirection = .leftToRight
      osd.osdLabel.baseWritingDirection = .leftToRight
      fallthrough
    case .withProgress(let value):
      osd.osdVStackView.setVisibilityPriority(.notVisible, for: osd.osdAccessoryText)
      osd.osdVStackView.setVisibilityPriority(.mustHold, for: osd.osdAccessoryProgress)
      osd.osdAccessoryProgress.doubleValue = value
      osd.osdAccessoryProgress.needsDisplay = true
    case .withLeftToRightText(let text):
      // OSD messages displaying the playback position must always be displayed left to right.
      osd.osdAccessoryText.baseWritingDirection = .leftToRight
      fallthrough
    case .withText(let text):
      guard !player.isStopping else { return }  /// prevent crash when `mpv.getInt()` is used below
      osd.osdVStackView.setVisibilityPriority(.mustHold, for: osd.osdAccessoryText)
      osd.osdVStackView.setVisibilityPriority(.notVisible, for: osd.osdAccessoryProgress)

      // data for mustache rendering
      let osdData: [String: String] = [
        "duration": VideoTime.string(from: player.info.playbackDurationSec),
        "position": VideoTime.string(from: player.info.playbackPositionSec),
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      osd.osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }

  @MainActor
  private func updateOSDIcon(from message: OSDMessage) {
    guard #available(macOS 11.0, *) else { return }

    var icon: NSImage? = nil
    var isIconGrayedOut = false

    if message.isSoundRelated {
      // Add sound icon which indicates current audio status.
      // Gray color == disabled. Slash == muted. Can be combined

      let isAudioDisabled = !player.info.isAudioTrackSelected
      let currentVolume = player.info.volume
      let isMuted = player.info.isMuted
      isIconGrayedOut = isAudioDisabled
      if isAudioDisabled {
        icon = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "No audio track is selected")!
      } else {
        icon = volumeIcon(volume: currentVolume, isMuted: isMuted)
      }
    } else {
      switch message {
      case .resume:
        icon = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!
      case .pause:
        icon = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")!
      case .stop:
        icon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")!
      case .seek:
        icon = osd.currentSeekIcon
      default:
        break
      }
    }

    let isIconVisible = icon != nil
    // This will set icon width to 0 if it should not be visible so that VStackView can use its space.
    osd.updateIconSize(isIconVisible: isIconVisible)
    osd.osdIconImageView.isHidden = !isIconVisible

    if let icon {
      osd.osdIconImageView.image = icon
      osd.osdIconImageView.contentTintColor = isIconGrayedOut ? .disabledControlTextColor : .controlTextColor
      osd.iconToVStackSpacingConstraint.constraint?.constant = 4
    } else {
      // Need this only for OSD messages which use the icon
      osd.iconToVStackSpacingConstraint.constraint?.constant = 0
    }
    log.trace("[OSD] Icon visible=\(isIconVisible.yn) for msg: \(message)")
  }

  /// Do not call `displayOSD` directly. Call `PlayerCore.sendOSD` instead.
  ///
  /// There is a timing issue that can occur when the user holds down a key to rapidly repeat a key binding or menu item equivalent,
  /// which should result in an OSD being displayed for each keypress. But for some reason, the task to update the OSD,
  /// which is enqueued via `DispatchQueue.main.async` (or even `sync`), does not run at all while the key events continue to come in.
  /// To work around this issue, we instead enqueue the tasks to display OSD using a simple LinkedList and Lock. Then we call
  /// `updateUI()` both from here (as before), and inside the key event callbacks in `PlayerWindow` so that that the key events
  /// themselves process the display of any enqueued OSD messages.
  func displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                  accessoryViewController: NSViewController? = nil, isExternal: Bool = false) {
    guard player.canShowOSD() || msg.alwaysEnabled else { return }
    guard !msg.isDisabled else { return }
    
    // Enqueue first, in case main queue is blocked
    osd.queueLock.withLock {
      osd.queue.append({ [self] in
        // DO NOT use animationPipeline here. It is not needed, and will cause OSD to block
        _displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController)
      })
    }
    // Need to do the UI sync in the main queue
    DispatchQueue.main.async { [self] in
      if !isScrollingOrDraggingPlaySlider {
        player.updatePlaybackTimeInfo()
      }
      updateUI()
    }
  }

  private func _displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                           accessoryViewController: NSViewController? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Check again. May have been enqueued a while
    guard player.canShowOSD() else { return }

    // Filter out unwanted OSDs first
    guard !osd.isShowingPersistentOSD || accessoryViewController != nil else { return }

    // If showing debug OSD, do not allow any other OSD type to replace it
    if case .debug = osd.currentlyDisplayedMsg {
      if case .debug = msg {
      } else {
        log.verbose("[OSD] Discarding '\(msg)' because a debug msg is visible")
        return
      }
    }

    if case .fileStart = osd.lastDisplayedMsg {
      if case .fileStart = msg {
        // Allow replacement if changing playbacks quickly
      } else {
        // Lots of junk messages are spewed at start. Ignore all but other .fileStart messages
        if !player.info.isFileLoaded
            || osd.didShowLastMsgSomewhatRecently() { return }
      }
    }

    var msg = msg
    switch msg {

    case .seek(_, _):
      /// Ignore `seek` in favor of these more important messages:
      if osd.didShowLastMsgRecently() {
        if case .speed = osd.lastDisplayedMsg { return }
        if case .frameStep = osd.lastDisplayedMsg { return }
        if case .frameStepBack = osd.lastDisplayedMsg { return }
      }
      /// Call this first to update `info.playbackPositionSec`, `info.playbackDurationSec`, needed below.
      player.updatePlaybackTimeInfo()

      /// Many redundant `MPV_EVENT_SEEK` messages are emitted from mpv at different times, and each triggers a call to
      /// show a `seek` OSD message. Show it only if either `position` or `duration` actually changed from their
      /// previously cached values.
      guard let position = player.info.playbackPositionSec,
            let duration = player.info.playbackDurationSec else {
        log.verbose("[OSD] Ignoring request for 'seek': position or duration is missing")
        return
      }
      let positionDelta = abs(position - (osd.lastPlaybackPosition ?? Double.infinity))
      let durationDelta = abs(duration - (osd.lastPlaybackDuration ?? Double.infinity))
      guard positionDelta > Constants.OSD.osdSeekMinDeltaSec ||
            durationDelta > Constants.OSD.osdSeekMinDeltaSec else {
        log.verbose("[OSD] Ignoring redundant request for 'seek'; neither position or duration has changed (\(positionDelta), \(durationDelta))")
        return
      }
      osd.lastPlaybackPosition = position
      osd.lastPlaybackDuration = duration

    case .pause, .resume:
      // Do not show pause/resume during seek
      if isScrollingOrDraggingPlaySlider { return }

      if osd.didShowLastMsgRecently() {
        if case .speed = osd.lastDisplayedMsg, case .resume = msg { return }
        if case .frameStep = osd.lastDisplayedMsg { return }
        if case .frameStepBack = osd.lastDisplayedMsg { return }
      }

      player.updatePlaybackTimeInfo()  // need to call this to update info.playbackPositionSec, info.playbackDurationSec
      osd.lastPlaybackPosition = player.info.playbackPositionSec
      osd.lastPlaybackDuration = player.info.playbackDurationSec

    case .crop(let newCropLabel):
      if newCropLabel == AppData.noneCropIdentifier && !isInInteractiveMode && player.info.videoFiltersDisabled[Constants.FilterLabel.crop] != nil {
        log.verbose("[OSD] Ignoring request for Crop 'None': looks like user starting to edit an existing crop")
        return
      }
      if osd.didShowLastMsgRecently() {
        // As of v1.4, partial rotations can trigger "crop" messages as a side effect. Show rotation msg only.
        if case .rotation = osd.lastDisplayedMsg { return }
      }

    case .resumeFromWatchLater:
      if case .fileStart(let filename, _) = osd.lastDisplayedMsg {
        // Append details msg indicating restore state to existing msg
        let detailsMsg = msg.details().0
        msg = .fileStart(filename, detailsMsg)
      }

    default:
      break
    }

    // End filtering

    log.verbose("[OSD] Setting lastDisplayedMsg = \(msg)")
    osd.lastDisplayedMsg = msg

    if #available(macOS 11.0, *) {
      /// The pseudo-OSDMessage `seekRelative`, if present, contains the step time for a relative seek.
      /// But because it needs to be parsed from the mpv log, it is sent as a separate msg which arrives immediately
      /// prior to the `seek` msg. With some smart logic, the info from the two messages can be combined to display
      /// the most appropriate "jump" icon in the OSD in addition to the time display & progress bar.
      if case .seekRelative(let stepString) = msg, let step = Double(stepString) {
        log.verbose("[OSD] Showing '\(msg)'")

        let isBackward = step < 0
        let accDescription = "Relative Seek \(isBackward ? "Backward" : "Forward")"
        var name: String
        switch abs(step) {
        case 5, 10, 15, 30, 45, 60, 75, 90:
          let absStep = Int(abs(step))
          name = isBackward ? "gobackward.\(absStep)" : "goforward.\(absStep)"
        default:
          name = isBackward ? "gobackward.minus" : "goforward.plus"
        }
        /// Set icon for next msg, which is expected to be a `seek`
        osd.nextSeekIcon = NSImage(systemSymbolName: name, accessibilityDescription: accDescription)!
        /// Done with `seekRelative` msg. It is not used for display.
        return
      } else if case .seek(_, _) = msg {
        /// Shift next icon into current icon, which will be used until the next call to `displayOSD()`
        /// (although note that there can be subsequent calls to `setOSDViews()` to update the OSD's displayed time while playing,
        /// but those do not count as "new" OSD messages, and thus will continue to use `osd.currentSeekIcon`).
        if isScrollingOrDraggingPlaySlider {
          // give up on fancy OSD for scroll wheel seek (for now)
          osd.currentSeekIcon = nil
          osd.nextSeekIcon = nil
        } else if osd.nextSeekIcon != nil {
          osd.currentSeekIcon = osd.nextSeekIcon
          osd.nextSeekIcon = nil
        }
      } else {
        osd.currentSeekIcon = nil
      }
    }

    // Restart timer
    osd.hideOSDTimer.cancel()
    if osd.animationState != .shown {
      osd.animationState = .shown  /// set this before calling `refreshSyncUITimer()`
      DispatchQueue.main.async { [self] in  /// launch async task to avoid recursion, which `osdQueueLock` doesn't like
        player.refreshSyncUITimer()
      }
    } else {
      osd.animationState = .shown
    }

    if autoHide {
      let timeout: Double = forcedTimeout ?? OSDState.osdTimeoutFromPrefs()
      log.verbose("[OSD] Showing '\(msg)' timeout=\(timeout)\(forcedTimeout != nil ? " (forced)" : "")")
      osd.hideOSDTimer.restart(withNewTimeout: timeout)
    } else {
      log.verbose("[OSD] Showing '\(msg)', no timeout")
    }

    let existingAccessoryViews = osd.osdVStackView.views(in: .bottom)
    if !existingAccessoryViews.isEmpty {
      for subview in osd.osdVStackView.views(in: .bottom) {
        osd.osdVStackView.removeView(subview)
      }
    }
    if let accessoryViewController {  // e.g., ScreenshootOSDView
      let accessoryView = accessoryViewController.view
      osd.context = accessoryViewController
      osd.isShowingPersistentOSD = true

      osd.osdVStackView.addView(accessoryView, in: .bottom)
    }

    osd.osdView.alphaValue = 1
    osd.osdView.isHidden = false
    updateOSDTextSize(andSetViewsFrom: msg)
  }

  @objc
  func hideOSD(immediately: Bool = false, refreshSyncUITimer: Bool = true) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded else { return }
    if osd.animationState != .hidden {
      log.trace("[OSD] Will hide")
    }
    osd.animationState = .willHide
    osd.hideOSDTimer.cancel()

    IINAAnimation.runAsync(IINAAnimation.Task(duration: immediately ? 0 : Constants.AnimationDuration.osdAnimation, { [self] in
      osd.osdView.alphaValue = 0

    }), then: { [self] in
      if osd.animationState == .willHide {
        osd.animationState = .hidden
        osd.osdView.isHidden = true
        osd.isShowingPersistentOSD = false
        osd.context = nil
        for subview in osd.osdVStackView.views(in: .bottom) {
          osd.osdVStackView.removeView(subview)
        }

        if refreshSyncUITimer {
          player.refreshSyncUITimer()
        }
      }
    })
  }

  func updateOSDTextSize(from givenGeo: PWinGeometry? = nil, andSetViewsFrom msg: OSDMessage? = nil) {
    guard let window else { return }
    let currentLayout = currentLayout
    let pwGeo: PWinGeometry
    if let givenGeo {
      pwGeo = givenGeo
    } else {
      // TODO: Consolidate duplicate code [#PWinGeoForAnyMode]
      switch currentLayout.mode {
      case .windowedNormal, .windowedInteractive:
        pwGeo = windowedGeoForCurrentFrame()
      case .fullScreenNormal, .fullScreenInteractive:
        pwGeo = currentLayout.buildFullScreenGeometry(inScreenID: bestScreen.screenID, geo.video)
      case .musicMode:
        pwGeo = musicModeGeoForCurrentFrame()
      }
    }

    let osdTextSize = osd.getOSDTextSize(from: pwGeo)
    if osdTextSize != osd.textSizeLast {
      osd.textSizeLast = osdTextSize
      log.verbose("[OSD] Δ textSize: \(osd.textSizeLast) → \(osdTextSize)")

      // Update rounded corners
      player.pwc.updateCornerRoundness(fromOSDTextSize: osdTextSize)

      // Also update progress bar height based on text size
      osd.updateProgressBarStyle(window.effectiveAppearance, effectiveOSCColorScheme: currentLayout.effectiveOSCColorScheme)

      let osdAccessoryTextSize = (osdTextSize * 0.75).rounded().clamped(to: 11...25)
      osd.osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: osdAccessoryTextSize, weight: .regular)

      // Update padding around edges
      let marginScaled = 8 + (osdTextSize * 0.15).rounded()
      osd.osdTopPaddingConstraint.constraint?.animateToConstant(marginScaled)
      osd.osdBtmPaddingConstraint.constraint?.animateToConstant(marginScaled)
      osd.osdTrailingPaddingConstraint.constraint?.animateToConstant(marginScaled)
      osd.osdLeadingPaddingConstraint.constraint?.animateToConstant(marginScaled)

      // Update OSD label
      let osdLabelFont = NSFont.monospacedDigitSystemFont(ofSize: osdTextSize, weight: .regular)
      osd.osdLabel.font = osdLabelFont
    }

    // Always call this afterwards
    setOSDViews(fromMessage: msg)
  }
}
