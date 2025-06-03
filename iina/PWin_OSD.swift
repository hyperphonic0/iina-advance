//
//  PWin_OSD.swift
//  iina
//
//  Created by Matt Svoboda on 6/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation
import Mustache

/// Encapsulates all of the window's OSD state vars
class OSDState {
  let log: Logger.Subsystem

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
  func didShowLastMsgRecently() -> Bool {
    return Date().timeIntervalSince1970 - lastDisplayedMsgTS < 0.25
  }

  fileprivate var topOffsetConstraint: NSLayoutConstraint? = nil
  fileprivate var additionalInfoTopOffsetConstraint: NSLayoutConstraint? = nil
  fileprivate var bottomOffsetConstraint: NSLayoutConstraint? = nil
  fileprivate var additionalInfoBottomOffsetConstraint: NSLayoutConstraint? = nil
  fileprivate var leadingSide_LeadingConstraint: NSLayoutConstraint? = nil
  fileprivate var leadingSide_TrailingConstraint: NSLayoutConstraint? = nil
  fileprivate var trailingSide_LeadingConstraint: NSLayoutConstraint? = nil
  fileprivate var trailingSide_TrailingConstraint: NSLayoutConstraint? = nil

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

  init(log: Logger.Subsystem) {
    self.log = log
  }

  static func osdTimeoutFromPrefs() -> Double {
    // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    return max(Constants.TimeInterval.osdTimeoutMin, Double(Preference.float(for: .osdAutoHideTimeout)))
  }

}

/// The Additional Info view displays a battery time indicator & the media title when in full screen.
class AdditionalInfoView: MouseIgnoringVisualEffectView {
  let additionalInfoTitle = ResizableTextView(lineBreakMode: .byTruncatingMiddle)
  let additionalInfoStackView = NSStackView()
  let additionalInfoLabel = NSTextField(labelWithString: "99:99")
  let additionalInfoBatteryView = NSView()
  let additionalInfoBattery = NSTextField(labelWithString: "100%")

  init() {
    super.init(frame: .zero)
    blendingMode = .withinWindow
    material = .popover
    state = .active
    idString = "AdditionalInfoView"
    translatesAutoresizingMaskIntoConstraints = false

    subviews = [additionalInfoTitle, additionalInfoStackView]

    additionalInfoTitle.setContentHuggingPriority(.init(900), for: .horizontal)
    additionalInfoTitle.idString = "AdditionalInfo-Title"
    additionalInfoTitle.font = NSFont.systemFont(ofSize: 18, weight: .medium)
    additionalInfoTitle.alignment = .right
    additionalInfoTitle.setContentCompressionResistancePriority(.init(499), for: .horizontal)
    additionalInfoTitle.translatesAutoresizingMaskIntoConstraints = false
    additionalInfoTitle.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
    additionalInfoTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16).isActive = true
    trailingAnchor.constraint(equalTo: additionalInfoTitle.trailingAnchor, constant: 16).isActive = true

    let labelContainerView = NSView()
    labelContainerView.translatesAutoresizingMaskIntoConstraints = false
    labelContainerView.heightAnchor.constraint(equalToConstant: 30).isActive = true
    labelContainerView.subviews = [additionalInfoLabel]

    additionalInfoLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
    additionalInfoLabel.textColor = .secondaryLabelColor
    additionalInfoLabel.backgroundColor = .textBackgroundColor
    additionalInfoLabel.idString = "AdditionalInfo-Label"
    additionalInfoLabel.translatesAutoresizingMaskIntoConstraints = false
    additionalInfoLabel.leadingAnchor.constraint(equalTo: labelContainerView.leadingAnchor, constant: 6).isActive = true
    labelContainerView.trailingAnchor.constraint(equalTo: additionalInfoLabel.trailingAnchor).isActive = true
    additionalInfoLabel.centerYAnchor.constraint(equalTo: labelContainerView.centerYAnchor, constant: -1).isActive = true

    let verticalLine = NSBox()
    verticalLine.boxType = .separator
    verticalLine.translatesAutoresizingMaskIntoConstraints = false
    verticalLine.heightAnchor.constraint(equalToConstant: 12).isActive = true

    additionalInfoStackView.idString = "AdditionalInfo-HStackView"
    additionalInfoStackView.orientation = .horizontal
    additionalInfoStackView.alignment = .centerY
    additionalInfoStackView.distribution = .fill
    additionalInfoStackView.spacing = 8
    additionalInfoStackView.wantsLayer = true
    additionalInfoStackView.detachesHiddenViews = true
    additionalInfoStackView.translatesAutoresizingMaskIntoConstraints = false

    additionalInfoStackView.topAnchor.constraint(equalTo: additionalInfoTitle.bottomAnchor, constant: 4).isActive = true
    additionalInfoStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16).isActive = true
    trailingAnchor.constraint(equalTo: additionalInfoStackView.trailingAnchor, constant: 16).isActive = true
    bottomAnchor.constraint(equalTo: additionalInfoStackView.bottomAnchor, constant: 4).isActive = true

    // - Battery

    additionalInfoBatteryView.idString = "AdditionalInfoBatteryView"
    additionalInfoBatteryView.wantsLayer = true
    additionalInfoBatteryView.translatesAutoresizingMaskIntoConstraints = false
    additionalInfoBatteryView.heightAnchor.constraint(equalToConstant: 30).isActive = true
    additionalInfoBatteryView.widthAnchor.constraint(equalToConstant: 56).isActive = true

    additionalInfoBattery.idString = "AdditionalInfoBattery-Text"
    additionalInfoBattery.font = NSFont.systemFont(ofSize: 13, weight: .bold)
    additionalInfoBattery.textColor = .secondaryLabelColor
    additionalInfoBattery.backgroundColor = .textBackgroundColor
    additionalInfoBattery.setContentHuggingPriority(.init(251), for: .horizontal)
    additionalInfoBattery.translatesAutoresizingMaskIntoConstraints = false

    let batteryImage = NSImage(named: "battery")!
    let batteryImageView = NSImageView(image: batteryImage)
    batteryImageView.imageScaling = .scaleProportionallyUpOrDown
    batteryImageView.wantsLayer = true
    batteryImageView.setContentHugging(h: 251, v: 251)
    batteryImageView.translatesAutoresizingMaskIntoConstraints = false

    additionalInfoBatteryView.subviews = [additionalInfoBattery, batteryImageView]
    batteryImageView.addAllConstraintsToFillSuperview()
    additionalInfoBattery.centerXAnchor.constraint(equalTo: additionalInfoBatteryView.centerXAnchor).isActive = true
    additionalInfoBattery.centerYAnchor.constraint(equalTo: additionalInfoBatteryView.centerYAnchor, constant: -0.5).isActive = true

    for subview in [labelContainerView, verticalLine, additionalInfoBatteryView] {
      additionalInfoStackView.addView(subview, in: .trailing)
      subview.autoresizesSubviews = false
    }
    additionalInfoBatteryView.autoresizesSubviews = false
    additionalInfoBattery.autoresizesSubviews = false
    batteryImageView.autoresizesSubviews = false
    additionalInfoTitle.autoresizesSubviews = false

  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// PlayerWindow UI: OSD
extension PlayerWindowController {

  func initOSDView(in contentView: NSView) {
    // Subview init
    osdAccessoryProgress.usesThreadedAnimation = false

    // Min width
    let osdMinWidthConstraint = osdVisualEffectView.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
    osdMinWidthConstraint.priority = .init(900)
    osdMinWidthConstraint.isActive = true

    // Offset from top bar
    osdTopToTopBarConstraint = osdVisualEffectView.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: 8)
    osdTopToTopBarConstraint.identifier = "OSDTopToTopBarConstraint"
    osdTopToTopBarConstraint.priority = .init(900)
    osdTopToTopBarConstraint.isActive = true

    osdLeadingToMiniPlayerButtonsTrailingConstraint = osdVisualEffectView.leadingAnchor.constraint(greaterThanOrEqualTo: closeButtonView.trailingAnchor, constant: 4)
    osdLeadingToMiniPlayerButtonsTrailingConstraint.priority = .defaultLow
    osdLeadingToMiniPlayerButtonsTrailingConstraint.isActive = true

    closeButtonView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4).isActive = true
  }

  /// Enforces `Preference.Key.osdPosition` pref which allows OSD to be on either left or right
  func updateOSDConstraints(hasOSD: Bool, hasAdditionalInfo: Bool,
                            leadingSidebarIsOpen: Bool, trailingSidebarIsOpen: Bool, hasTopBar: Bool) {
    log.verbose{"Updating OSD constraints: hasOSD=\(hasOSD.yn) hasAddlInfo=\(hasAdditionalInfo.yn) leadingSidebar=\(leadingSidebarIsOpen.yn) trailingSidebar=\(trailingSidebarIsOpen.yn) hasTopBar=\(hasTopBar.yn)"}
    guard let contentView = window?.contentView else { return }
    osd.leadingSide_LeadingConstraint?.isActive = false
    osd.leadingSide_TrailingConstraint?.isActive = false
    osd.trailingSide_LeadingConstraint?.isActive = false
    osd.trailingSide_TrailingConstraint?.isActive = false
    osd.topOffsetConstraint?.isActive = false
    osd.additionalInfoTopOffsetConstraint?.isActive = false
    osd.bottomOffsetConstraint?.isActive = false
    osd.additionalInfoBottomOffsetConstraint?.isActive = false

    let otherAnchorLeading = leadingSidebarIsOpen ? leadingSidebarView.trailingAnchor : viewportView.leadingAnchor
    let otherAnchorTrailing = trailingSidebarIsOpen ? trailingSidebarView.leadingAnchor : viewportView.trailingAnchor

    let osdPosition: Preference.OSDPosition = Preference.enum(for: .osdPosition)
    if hasOSD {
      switch osdPosition {
      case .topLeading:  // OSD on left, AdditionalInfo on right
        let leadingSide_LeadingConstraint = otherAnchorLeading.constraint(equalTo: osdVisualEffectView.leadingAnchor, constant: -8)
        updateOSDLeadingSide_LeadingConstraint(to: leadingSide_LeadingConstraint)

        let leadingSide_TrailingConstraint = osdVisualEffectView.trailingAnchor.constraint(lessThanOrEqualTo: otherAnchorTrailing, constant: -8)
        updateOSDLeadingSide_TrailingConstraint(to: leadingSide_TrailingConstraint)
      case .topTrailing:  // AdditionalInfo on left, OSD on right
        let trailingSide_TrailingConstraint = otherAnchorTrailing.constraint(equalTo: osdVisualEffectView.trailingAnchor, constant: 8)
        updateOSDTrailingSide_TrailingConstraint(to: trailingSide_TrailingConstraint)

        let trailingSide_LeadingConstraint = osdVisualEffectView.leadingAnchor.constraint(greaterThanOrEqualTo: otherAnchorLeading, constant: -8)
        updateOSDTrailingSide_LeadingConstraint(to: trailingSide_LeadingConstraint)
      }

      // Y coordinate for top & bottom constraints seems to be flipped. Not sure why
      let topConstraint: NSLayoutConstraint
      if hasTopBar {
        topConstraint = topBarView.bottomAnchor.constraint(equalTo: osdVisualEffectView.topAnchor, constant: -8)
      } else {
        topConstraint = viewportView.topAnchor.constraint(equalTo: osdVisualEffectView.topAnchor, constant: -8)
      }
      updateOSDTopOffsetConstraint(to: topConstraint)

      let btmConstraint = viewportView.bottomAnchor.constraint(greaterThanOrEqualTo: osdVisualEffectView.bottomAnchor, constant: 8)
      btmConstraint.identifier = "OSD_BtmOffsetConstraint"
      btmConstraint.isActive = true
      osd.bottomOffsetConstraint = btmConstraint
    }

    if hasAdditionalInfo {
      switch osdPosition {
      case .topLeading:  // OSD on left, AdditionalInfo on right
        let trailingSide_TrailingConstraint = otherAnchorTrailing.constraint(equalTo: additionalInfoView.trailingAnchor, constant: 8)
        updateOSDTrailingSide_TrailingConstraint(to: trailingSide_TrailingConstraint)

        let trailingSide_LeadingConstraint = additionalInfoView.leadingAnchor.constraint(greaterThanOrEqualTo: otherAnchorLeading, constant: -8)
        updateOSDTrailingSide_LeadingConstraint(to: trailingSide_LeadingConstraint)
      case .topTrailing:  // AdditionalInfo on left, OSD on right
        let leadingSide_LeadingConstraint = otherAnchorLeading.constraint(equalTo: additionalInfoView.leadingAnchor, constant: -8)
        updateOSDLeadingSide_LeadingConstraint(to: leadingSide_LeadingConstraint)

        let leadingSide_TrailingConstraint = additionalInfoView.trailingAnchor.constraint(lessThanOrEqualTo: otherAnchorTrailing, constant: -8)
        updateOSDLeadingSide_TrailingConstraint(to: leadingSide_TrailingConstraint)
      }

      // Y coordinate for top & bottom constraints seems to be flipped. Not sure why
      let topConstraint: NSLayoutConstraint
      if hasTopBar {
        topConstraint = topBarView.bottomAnchor.constraint(equalTo: additionalInfoView.topAnchor, constant: -8)
      } else {
        topConstraint = viewportView.topAnchor.constraint(equalTo: additionalInfoView.topAnchor, constant: -8)
      }
      updateAdditionalInfoTopOffsetConstraint(to: topConstraint)

      let btmConstraint = viewportView.bottomAnchor.constraint(greaterThanOrEqualTo: additionalInfoView.bottomAnchor, constant: 8)
      btmConstraint.identifier = "AddlInfo_BtmOffsetConstraint"
      btmConstraint.isActive = true
      osd.additionalInfoBottomOffsetConstraint = btmConstraint

      updateAdditionalInfo()  // update content
    } else {
      additionalInfoView.removeFromSuperview()
    }

    contentView.layoutSubtreeIfNeeded()
  }

  private func updateOSDLeadingSide_LeadingConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "OSD_leadingSide_LeadingConstraint"
    constraint.priority = .defaultHigh  // why?
    constraint.isActive = true
    osd.leadingSide_LeadingConstraint = constraint
  }

  private func updateOSDLeadingSide_TrailingConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "OSD_LeadingSide_TrailingConstraint"
    constraint.priority = .defaultHigh  // why?
    constraint.isActive = true
    osd.leadingSide_TrailingConstraint = constraint
  }

  private func updateOSDTrailingSide_LeadingConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "OSD_TrailingSide_LeadingConstraint"
    constraint.priority = .defaultHigh  // why?
    constraint.isActive = true
    osd.trailingSide_LeadingConstraint = constraint
  }

  private func updateOSDTrailingSide_TrailingConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "OSD_trailingSide_TrailingConstraint"
    constraint.isActive = true
    osd.trailingSide_TrailingConstraint = constraint
  }

  private func updateOSDTopOffsetConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "OSD_TopOffsetConstraint"
    constraint.isActive = true
    osd.topOffsetConstraint = constraint
  }

  private func updateAdditionalInfoTopOffsetConstraint(to constraint: NSLayoutConstraint) {
    constraint.identifier = "AddlInfo_TopOffsetConstraint"
    constraint.isActive = true
    osd.additionalInfoTopOffsetConstraint = constraint
  }

  // MARK: - Additional Info Content Updates

  func updateAdditionalInfo() {
    // Update content
    let title = window?.representedURL?.lastPathComponent ?? window?.title ?? ""
    additionalInfoView.additionalInfoTitle.string = title
    additionalInfoView.additionalInfoTitle.sizeToFit()
    additionalInfoView.additionalInfoTitle.invalidateIntrinsicContentSize()

    if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
      additionalInfoView.additionalInfoBattery.stringValue = "\(capacity)%"
      additionalInfoView.additionalInfoStackView.setVisibilityPriority(.mustHold, for: additionalInfoView.additionalInfoBatteryView)
    } else {
      additionalInfoView.additionalInfoStackView.setVisibilityPriority(.notVisible, for: additionalInfoView.additionalInfoBatteryView)
    }
    additionalInfoView.additionalInfoLabel.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
  }

  // MARK: - OSD Content Updates

  /// If `newMessage` is provided, the OSD will be updated to display it. Otherwise if the OSD is
  /// already shown and is displaying one of the message types which requires live updates, it will be updated.
  func setOSDViews(fromMessage newMessage: OSDMessage? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    let message: OSDMessage?

    if let newMessage {
      message = newMessage

    } else if let currentMsg = osd.currentlyDisplayedMsg,
              let position = player.info.playbackPositionSec,
              let duration = player.info.playbackDurationSec {
      // If the OSD is visible and is showing playback position, keep its displayed time up to date:
      switch currentMsg {
      case .pause:
        message = .pause(playbackPositionSec: position, playbackDurationSec: duration)
      case .resume:
        message = .resume(playbackPositionSec: position, playbackDurationSec: duration)
      case .seek(_, _):
        message = .seek(playbackPositionSec: position, playbackDurationSec: duration)
      default:
        message = nil
      }
    } else {
      message = nil
    }

    guard let message else {
      // Often this method was called in response to a layout change.
      // For some reason the text wrap of the following is not recomputed or the text may be smashed/stretched,
      // so mark it expclitly as needing redisplay here:
      osdLabel.needsDisplay = true
      osdAccessoryText.needsDisplay = true
      return
    }

    defer {
      osdVisualEffectView.layout()
    }

    updateOSDIcon(from: message)

    let (osdText, osdType) = message.details()
    osdLabel.stringValue = osdText

    // Most OSD messages are displayed based on the configured language direction.
    osdAccessoryProgress.userInterfaceLayoutDirection = osdVStackView.userInterfaceLayoutDirection
    osdAccessoryText.baseWritingDirection = .natural
    osdLabel.baseWritingDirection = .natural
    switch osdType {
    case .normal:
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
    case .withLeftToRightProgress(let value):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryProgress.userInterfaceLayoutDirection = .leftToRight
      osdLabel.baseWritingDirection = .leftToRight
      fallthrough
    case .withProgress(let value):
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryProgress)
      osdAccessoryProgress.doubleValue = value
    case .withLeftToRightText(let text):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryText.baseWritingDirection = .leftToRight
      fallthrough
    case .withText(let text):
      guard !player.isStopping else { return }  /// prevent crash when `mpv.getInt()` is used below
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)

      // data for mustache rendering
      let osdData: [String: String] = [
        "duration": VideoTime.string(from: player.info.playbackDurationSec),
        "position": VideoTime.string(from: player.info.playbackPositionSec),
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }

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

    if let icon {
      let finalheight = osdIconHeightConstraint.constant
      let finalWidth = round(icon.size.aspect * finalheight)
      osdIconWidthConstraint.constant = finalWidth

      osdIconImageView.image =  icon
      osdIconImageView.contentTintColor = isIconGrayedOut ? .disabledControlTextColor : .controlTextColor
    }
    let isIconVisible = icon != nil
    // Need this only for OSD messages which use the icon
    osdIconImageView.isHidden = !isIconVisible
    log.trace{"OSD icon=\(isIconVisible.yn) for msg: \(message)"}
  }

  /// If `position` and `duration` are different than their previously cached values, overwrites the cached values and
  /// returns `true`. Returns `false` if the same or one of the values is `nil`.
  ///
  /// Lots of redundant `seek` messages which are emitted at all sorts of different times, and each triggers a call to show
  /// a `seek` OSD. To prevent duplicate OSDs, call this method to compare against the previous seek position.
  private func compareAndSetIfNewPlaybackTime(position: Double?, duration: Double?) -> Bool {
    guard let position, let duration else {
      log.verbose("Ignoring request for OSD seek: position or duration is missing")
      return false
    }
    // There seem to be precision errors which break equality when comparing values beyond 6 decimal places.
    // Just round to nearest 1/1000000 sec for comparison.
    let newPosRounded = round(position * AppData.osdSeekSubSecPrecisionComparison)
    let newDurRounded = round(duration * AppData.osdSeekSubSecPrecisionComparison)
    let oldPosRounded = round((osd.lastPlaybackPosition ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    let oldDurRounded = round((osd.lastPlaybackDuration ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    guard newPosRounded != oldPosRounded || newDurRounded != oldDurRounded else {
      log.verbose("Ignoring request for OSD seek; position/duration has not changed")
      return false
    }
    osd.lastPlaybackPosition = position
    osd.lastPlaybackDuration = duration
    return true
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
        // DO NOT use animation pipeline here. It is not needed, and will cause OSD to block
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
        log.verbose("Discarding OSD '\(msg)' because a debug msg is visible")
        return
      }
    }

    var msg = msg
    switch msg {
    case .seek(_, _):
      // Many redundant messages are sent from mpv. Try to filter them out here
      if osd.didShowLastMsgRecently() {
        if case .speed = osd.lastDisplayedMsg { return }
        if case .frameStep = osd.lastDisplayedMsg { return }
        if case .frameStepBack = osd.lastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.playbackPositionSec, info.playbackDurationSec
      guard compareAndSetIfNewPlaybackTime(position: player.info.playbackPositionSec, duration: player.info.playbackDurationSec) else {
        // Is redundant msg; discard
        return
      }
    case .pause, .resume:
      // do not show pause/resume when done for seek
      // TODO: this does not cover resume after slider seek ended. Need better solution
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
        log.verbose("Ignoring request to show OSD crop 'None': looks like user starting to edit an existing crop")
        return
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

    osd.lastDisplayedMsg = msg

    if #available(macOS 11.0, *) {

      /// The pseudo-OSDMessage `seekRelative`, if present, contains the step time for a relative seek.
      /// But because it needs to be parsed from the mpv log, it is sent as a separate msg which arrives immediately
      /// prior to the `seek` msg. With some smart logic, the info from the two messages can be combined to display
      /// the most appropriate "jump" icon in the OSD in addition to the time display & progress bar.
      if case .seekRelative(let stepString) = msg, let step = Double(stepString) {
        log.verbose("Got OSD '\(msg)'")

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
      log.verbose{"Showing OSD '\(msg)' timeout=\(timeout)\(forcedTimeout != nil ? " (forced)" : "")"}
      osd.hideOSDTimer.restart(withNewTimeout: timeout)
    } else {
      log.verbose("Showing OSD '\(msg)', no timeout")
    }

    updateOSDTextSize()
    setOSDViews(fromMessage: msg)

    let existingAccessoryViews = osdVStackView.views(in: .bottom)
    if !existingAccessoryViews.isEmpty {
      for subview in osdVStackView.views(in: .bottom) {
        osdVStackView.removeView(subview)
      }
    }
    if let accessoryViewController {  // e.g., ScreenshootOSDView
      let accessoryView = accessoryViewController.view
      osd.context = accessoryViewController
      osd.isShowingPersistentOSD = true

      osdVStackView.addView(accessoryView, in: .bottom)
    }

    osdVisualEffectView.layoutSubtreeIfNeeded()
    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
  }

  @objc
  func hideOSD(immediately: Bool = false, refreshSyncUITimer: Bool = true) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded else { return }
    if osd.animationState != .hidden {
      log.trace("Hiding OSD")
    }
    osd.animationState = .willHide
    osd.isShowingPersistentOSD = false
    osd.context = nil
    osd.hideOSDTimer.cancel()

    if refreshSyncUITimer {
      player.refreshSyncUITimer()
    }

    IINAAnimation.runAsync(IINAAnimation.Task(duration: immediately ? 0 : Constants.AnimationDuration.osdAnimation, { [self] in
      osdVisualEffectView.alphaValue = 0

    }), then: { [self] in
      if osd.animationState == .willHide {
        osd.animationState = .hidden
        osdVisualEffectView.isHidden = true
        osdVStackView.views(in: .bottom).forEach { self.osdVStackView.removeView($0) }
      }
    })
  }

  func updateOSDTextSize(from geo: PWinGeometry? = nil) {
    guard player.info.isFileLoadedAndSized else { return }

    let pwGeo: PWinGeometry
    if let geo {
      pwGeo = geo
    } else {
      switch currentLayout.mode {
      case .windowedNormal, .windowedInteractive:
        pwGeo = windowedGeoForCurrentFrame()
      case .fullScreenNormal, .fullScreenInteractive:
        pwGeo = currentLayout.buildFullScreenGeometry(inScreenID: bestScreen.screenID, video: self.geo.video)
      case .musicMode:
        pwGeo = musicModeGeoForCurrentFrame().toPWinGeometry()
      }
    }

    let availableSpaceForOSD = pwGeo.widthBetweenInsideSidebars

    // Reduce text size if horizontal space is tight
    var osdTextSize = max(8.0, CGFloat(Preference.float(for: .osdTextSize)))
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

    guard osdTextSize != osd.textSizeLast else { return }

    log.verbose("Changing OSD textSize: \(osd.textSizeLast) → \(osdTextSize)")

    let osdAccessoryTextSize = (osdTextSize * 0.75).clamped(to: 11...25)
    osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: osdAccessoryTextSize, weight: .regular)

    let marginScaled = 8 + (osdTextSize * 0.06)
    osdTopMarginConstraint.animateToConstant(marginScaled)
    osdBottomMarginConstraint.animateToConstant(marginScaled)
    osdTrailingMarginConstraint.animateToConstant(marginScaled)
    osdLeadingMarginConstraint.animateToConstant(marginScaled)

    let osdLabelFont = NSFont.monospacedDigitSystemFont(ofSize: osdTextSize, weight: .regular)
    osdLabel.font = osdLabelFont

    if #available(macOS 11.0, *) {
      switch osdTextSize {
      case 32...:
        osdAccessoryProgress.controlSize = .regular
      default:
        osdAccessoryProgress.controlSize = .small
      }
    }

    if #available(macOS 11.0, *) {
      // Use dimensions of a dummy image to keep the height fixed. Because all the components are vertically aligned
      // and each icon has a different height, this is needed to prevent the progress bar from jumping up and down
      // each time the OSD message changes.
      let attachment = NSTextAttachment()
      attachment.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "")!
      let iconString = NSMutableAttributedString(attachment: attachment)
      let osdIconTextSize = osdTextSize + (osdAccessoryProgress.fittingSize.height)
      let osdIconFont = NSFont.monospacedDigitSystemFont(ofSize: osdIconTextSize, weight: .regular)
      iconString.addAttribute(.font, value: osdIconFont, range: NSRange(location: 0, length: iconString.length))
      let iconHeight = iconString.size().height

      osdIconHeightConstraint.constant = iconHeight
    }
    osd.textSizeLast = osdTextSize
  }
}
