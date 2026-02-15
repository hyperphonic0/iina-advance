//
//  CustomTitleBarViewController.swift
//  iina
//
//  Created by Matt Svoboda on 10/16/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

// Try to roughly match Apple's title bar colors:
fileprivate let activeControlOpacity: CGFloat = 1.0
fileprivate let inactiveControlOpacity: CGFloat = 0.40

/// For legacy windowed mode. Manual reconstruction of title bar is needed when not using `titled` window style.
class CustomTitleBarViewController: NSViewController {
  unowned var pwc: PlayerWindowController!

  // Leading side contains traffic light buttons + leading title bar accessories
  fileprivate let leadingStackView = TitleBarButtonsContainerView()
  let closeButton: NSButton?
  let miniaturizeButton: NSButton?
  let zoomButton: NSButton?
  let leadingSidebarToggleButton = SymButton()

  /// Center stack view: contains document icon + title text
  let titleIconAndTextStackView = NSStackView()
  fileprivate let documentIconButton: NSButton! = NSWindow.standardWindowButton(.documentIconButton, for: .titled)
  let titleText = ResizableTextView(lineBreakMode: .byTruncatingTail)

  // Trailing side contains trailing title bar accessories
  fileprivate let trailingStackView = NSStackView()
  let trailingSidebarToggleButton = SymButton()
  let onTopButton = SymButton()

  init(_ layout: LayoutState, _ pwc: PlayerWindowController) {
    closeButton = NSWindow.standardWindowButton(.closeButton, for: .titled)
    miniaturizeButton = NSWindow.standardWindowButton(.miniaturizeButton, for: .titled)
    zoomButton = layout.mode == .musicMode ? nil : NSWindow.standardWindowButton(.zoomButton, for: .titled)
    self.pwc = pwc

    super.init(nibName: nil, bundle: nil)
    let topBarColorScheme = layout.topBarColorScheme
    for btn in [leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton] {
      btn.setColors(for: topBarColorScheme)
    }
  }
  
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var isHoveringOverTrafficLights: Bool = false {
    didSet {
      leadingStackView.markButtonsDirty()
    }
  }

  /// Convenience accessor which packages the standard window buttons
  var trafficLightButtons: [NSButton] {
    return [closeButton, miniaturizeButton, zoomButton].compactMap({ $0 })
  }

  /// Convenience accessor which packages all the `SymButton` buttons.
  var symButtons: [SymButton] {
    return [leadingSidebarToggleButton, trailingSidebarToggleButton, onTopButton]
  }

  /// Use `loadView` instead of `viewDidLoad` because controller is not using storyboard
  override func loadView() {
    super.loadView()
    
    view = NSView()
    view.identifier = .init("CustomTitleBarView")
    view.wantsLayer = true
    view.layer?.backgroundColor = .clear
    let builder = CustomTitleBar.shared
    let iconSpacingH = Constants.titleBarIconHSpacing

    // - Leading views

    // Add leading title bar accessory view

    builder.configureTitleBarButton(leadingSidebarToggleButton,
                                    Images.sidebarLeading,
                                    identifier: "LeadingSidebarBtn",
                                    target: pwc,
                                    action: #selector(pwc.toggleLeadingSidebarVisibility(_:)),
                                    actionSymbolEffectFunc: SymButton.bounceEffectFunc(_:))

    // Add fake traffic light buttons:
    let trafficLightButtons = trafficLightButtons
    leadingStackView.setViews(trafficLightButtons + [leadingSidebarToggleButton], in: .center)
    leadingStackView.identifier = .init("TitleBar-LeadingStackView")
    leadingStackView.orientation = .horizontal
    leadingStackView.detachesHiddenViews = true
    leadingStackView.alignment = .centerY
    leadingStackView.spacing = iconSpacingH
    leadingStackView.distribution = .fill
    leadingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    leadingStackView.setHuggingPriority(.init(500), for: .horizontal)
    leadingStackView.customTitleBar = self

    for btn in trafficLightButtons {
      btn.alphaValue = 1
      btn.isHidden = false
      // Never expand in size, even if there is extra space:
      btn.setContentHuggingPriority(.required, for: .horizontal)
      btn.setContentHuggingPriority(.required, for: .vertical)
      // Never collapse in size:
      btn.setContentCompressionResistancePriority(.required, for: .horizontal)
      btn.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    // - Center views

    let currentURL = pwc.player.info.currentPlayback?.url

    // See https://github.com/indragiek/INAppStoreWindow/blob/master/INAppStoreWindow/INAppStoreWindow.m
    pwc.window!.representedURL = currentURL
    // Show document icon only for files, not URLs, to match the behavior of the native title bar
    if let currentURL, currentURL.isFileURL {
      documentIconButton.image = Utility.icon(for: currentURL,
                                              optimizingForHeight: documentIconButton.frame.height)
      documentIconButton.alphaValue = 1
    } else {
      // Sloppy fix here. Using isHidden messes up the layout. Just use alpha value
      documentIconButton.alphaValue = 0
    }

    titleText.identifier = .init("TitleBar-TextView")
    titleText.font = NSFont.titleBarFont(ofSize: NSFont.systemFontSize(for: .regular))
    titleText.textColor = .labelColor

    titleIconAndTextStackView.setViews([documentIconButton, titleText], in: .center)
    titleIconAndTextStackView.detachesHiddenViews = true
    titleIconAndTextStackView.identifier = .init("TitleBar-CenterStackView")
    titleIconAndTextStackView.orientation = .horizontal
    titleIconAndTextStackView.alignment = .centerY
    titleIconAndTextStackView.spacing = 0
    titleIconAndTextStackView.distribution = .fill
    titleIconAndTextStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    // - Trailing views

    builder.configureTitleBarButton(onTopButton,
                                    Images.onTopOff,
                                    identifier: "OnTopButton",
                                    target: pwc,
                                    action: #selector(pwc.toggleOnTop(_:)),
                                    actionSymbolEffectFunc: SymButton.nullEffectFunc(_:)) // Do not bounce (looks weird)

    builder.configureTitleBarButton(trailingSidebarToggleButton,
                                    Images.sidebarTrailing,
                                    identifier: "TrailingSidebarBtn",
                                    target: pwc,
                                    action: #selector(pwc.toggleTrailingSidebarVisibility(_:)),
                                    actionSymbolEffectFunc: SymButton.bounceEffectFunc(_:))
    trailingStackView.setViews([trailingSidebarToggleButton, onTopButton], in: .center)
    trailingStackView.detachesHiddenViews = true
    trailingStackView.identifier = .init("TitleBar-TrailingStackView")
    trailingStackView.orientation = .horizontal
    trailingStackView.alignment = .centerY
    trailingStackView.spacing = iconSpacingH
    trailingStackView.distribution = .fill
    trailingStackView.edgeInsets = NSEdgeInsets(top: 0, left: iconSpacingH, bottom: 0, right: iconSpacingH)
    trailingStackView.setHuggingPriority(.init(500), for: .horizontal)

    initConstraints()

    view.configureSubtreeForCoreAnimation()
    updateAppearance()

    pwc.log.verbose("CustomTitleBar viewDidLoad done")
  }

  func updateAppearance() {
    let windowAppearance: NSAppearance = pwc.window!.effectiveAppearance
    let topBarColorScheme: Preference.PanelColorScheme = Preference.enum(for: .topBarColorScheme)
    let topBarAppearance = topBarColorScheme.hasClearBG ? NSAppearance(iinaTheme: .dark)! : windowAppearance
    topBarAppearance.applyAppearanceFor {
      view.appearance = topBarAppearance
      titleText.textColor = .labelColor
    }
  }

  private func initConstraints() {
    // Root view:
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Constants.standardTitleBarHeight).isActive = true

    // Stack views:
    view.addSubview(leadingStackView)
    view.addSubview(titleIconAndTextStackView)
    view.addSubview(trailingStackView)
    initConstraintsForStackViews()

    initConstraintsForCenterStackViewItems()
  }

  private func initConstraintsForStackViews() {
    leadingStackView.translatesAutoresizingMaskIntoConstraints = false
    titleIconAndTextStackView.translatesAutoresizingMaskIntoConstraints = false
    trailingStackView.translatesAutoresizingMaskIntoConstraints = false

    // Vertical constraints:

    leadingStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)
    titleIconAndTextStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)
    trailingStackView.addConstraintsToFillSuperview(top: 0, bottom: 0)

    // Horizontal constraints:

    leadingStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true

    let centerStackLeadingEqCon = titleIconAndTextStackView.leadingAnchor.constraint(equalTo: leadingStackView.trailingAnchor)
    centerStackLeadingEqCon.priority = .init(400)
    centerStackLeadingEqCon.isActive = true
    titleIconAndTextStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStackView.trailingAnchor).isActive = true

    let centerStackTrailingEqCon = titleIconAndTextStackView.trailingAnchor.constraint(equalTo: trailingStackView.trailingAnchor)
    centerStackTrailingEqCon.priority = .init(400)
    centerStackTrailingEqCon.isActive = true
    titleIconAndTextStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingStackView.leadingAnchor).isActive = true

    trailingStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
  }

  private func initConstraintsForCenterStackViewItems() {
    titleText.translatesAutoresizingMaskIntoConstraints = false
    // Priorities: CenterX < CompressionResistance < Equals(leading & trailing titles) < ContentHugging < 500
    // (>= 500 would interfere with window resize).
    // We want text's horizontal center to align with window's center, but more importantly it should use up
    // all available horizontal space.
    let cenXCon = titleIconAndTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0)
    cenXCon.priority = .init(401)  // make priority greater than leading & trailing EQ constraints above
    cenXCon.isActive = true
    titleText.setContentCompressionResistancePriority(.init(499), for: .horizontal)  // allow truncation
    titleText.setContentHuggingPriority(.init(499), for: .horizontal)

    documentIconButton.translatesAutoresizingMaskIntoConstraints = false
    documentIconButton.setContentHuggingPriority(.required, for: .horizontal)
    documentIconButton.setContentHuggingPriority(.required, for: .vertical)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    documentIconButton.setContentCompressionResistancePriority(.required, for: .vertical)

    // Make titleText expand to fill all available space
    let leadTitleCon = documentIconButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStackView.trailingAnchor)
    leadTitleCon.isActive = true
    let leadTitleConEQ = documentIconButton.leadingAnchor.constraint(equalTo: leadingStackView.trailingAnchor)
    leadTitleConEQ.priority = .init(498)
    leadTitleConEQ.isActive = true
    let trailTitleCon = trailingStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleText.trailingAnchor)
    trailTitleCon.isActive = true
    let trailTitleConEQ = trailingStackView.leadingAnchor.constraint(equalTo: titleText.trailingAnchor)
    trailTitleConEQ.priority = .init(498)
    trailTitleConEQ.isActive = true
  }

  /// Add to [different] superview and add constraints
  func addViewTo(superview: NSView) {
    superview.addSubview(view)
    view.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    pwc.updateTitle()
  }

  override func viewWillAppear() {
    // Need to call this here to patch case where window is not active, but title bar is
    // "inside" & is made visible by mouse hover:
    pwc.updateTitle()
  }

  /// Should be called by `pwc.updateTitle()` only.
  func updateTitle(to newTitle: String) {
    // - Update title text content

    if titleText.string != newTitle {
      titleText.string = newTitle
      titleText.sizeToFit()
      titleText.invalidateIntrinsicContentSize()
    }

    // - Update colors

    let drawAsKeyWindow = titleText.window?.isKeyWindow ?? false

    // TODO: apply colors to buttons in inactive windows when toggling fadeable views!
    let alphaValue = drawAsKeyWindow ? activeControlOpacity : inactiveControlOpacity

    for view in [titleText] {
      // Skip if not visible
      guard view.alphaValue > 0.0 else { continue }
      view.alphaValue = alphaValue
    }

    for btn in symButtons {
      // Skip buttons which are not visible
      guard btn.alphaValue > 0.0 else { continue }
      if drawAsKeyWindow {
        btn.regularColor = nil
      } else {
        btn.regularColor = .disabledControlTextColor
      }
      btn.contentTintColor = btn.regularColor
    }

    // We may have been called due to key window status change.
    // Redraw the traffic light buttons to change to active/inactive
    leadingStackView.markButtonsDirty()
  }

  func removeAndCleanUp() {
    // Remove fake traffic light buttons & other custom title bar buttons (if any)
    for subview in view.subviews {
      for subSubview in subview.subviews {
        subSubview.removeFromSuperview()
      }
      subview.removeFromSuperview()
    }
    view.removeFromSuperview()
  }
}

// MARK: - Support Classes

/// Leading stack view for custom title bar. Needed to subclass parent view of traffic light buttons
/// in order to get their highlight working properly. See: https://stackoverflow.com/a/30417372/1347529
final class TitleBarButtonsContainerView: NSStackView {
  var customTitleBar: CustomTitleBarViewController? = nil

  @objc func _mouseInGroup(_ button: NSButton) -> Bool {
    guard let customTitleBar else { return false }
    return customTitleBar.isHoveringOverTrafficLights
  }

  func markButtonsDirty() {
    for btn in views {
      btn.needsLayout = true  // is crucial to set this in MacOS Tahoe
      btn.needsDisplay = true
    }
  }
}

@MainActor
final class CustomTitleBar {
  static let shared = CustomTitleBar()

  func configureTitleBarButton(_ button: SymButton, _ image: NSImage, identifier: String, target: AnyObject, action: Selector,
                               actionSymbolEffectFunc: @escaping (SymButton) -> Void) {
    button.image = image
    button.target = target
    button.action = action
    button.identifier = .init(identifier)
    button.refusesFirstResponder = true
    button.isHidden = true
    // Avoid expanding in size, even if there is extra space.
    // Use `defaultHigh` instead of `required`: this looks like it helps prevent title bar buttons from getting slightly clipped
    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    button.setContentHuggingPriority(.defaultHigh, for: .vertical)
    // Never get compressed:
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .vertical)

    button.imageScaling = .scaleProportionallyUpOrDown

    if #unavailable (macOS 11.0) {
      // Needed for older versions of MacOS which use the legacy icons, which do not expand on their own
      let iconHeight = Constants.standardTitleBarHeight - 10 // 18
      let iconWidth = image.deriveWidth(fromHeight: iconHeight)
      button.heightAnchor.constraint(equalToConstant: iconHeight).isActive = true
      button.widthAnchor.constraint(equalToConstant: iconWidth).isActive = true
    }

    button.actionSymbolEffectFunc = actionSymbolEffectFunc
  }
}
