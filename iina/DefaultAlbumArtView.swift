//
//  DefaultAlbumArtView.swift
//  iina
//
//  Created by Matt Svoboda on 7/22/25.
//  Copyright © 2025 lhc. All rights reserved.
//

class DefaultAlbumArtView: ClickThroughView {
  static let id = "DefaultAlbumArtiew"

  init() {
    super.init(frame: .zero)
    idString = DefaultAlbumArtView.id
    wantsLayer = true
    layer?.contents = #imageLiteral(resourceName: "default-album-art")
    isHidden = true
    translatesAutoresizingMaskIntoConstraints = false
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func addLayout(inside viewportView: ViewportView) {
    viewportView.addSubview(self)

    // Add 1:1 aspect ratio constraint
    let aspectConstraint = widthAnchor.constraint(equalTo: heightAnchor, multiplier: 1)
    aspectConstraint.priority = .defaultHigh
    aspectConstraint.isActive = true
    // Always fill superview
    let widthGE = widthAnchor.constraint(greaterThanOrEqualTo: viewportView.widthAnchor)
    widthGE.priority = .defaultHigh
    widthGE.isActive = true
    let heightGE = heightAnchor.constraint(greaterThanOrEqualTo: viewportView.heightAnchor)
    heightGE.priority = .defaultHigh
    heightGE.isActive = true
    let widthEq = widthAnchor.constraint(equalTo: viewportView.widthAnchor)
    widthEq.priority = .defaultLow
    widthEq.isActive = true
    let heightEq = heightAnchor.constraint(equalTo: viewportView.heightAnchor)
    heightEq.priority = .defaultLow
    heightEq.isActive = true
    // Center in superview
    centerXAnchor.constraint(equalTo: viewportView.centerXAnchor).isActive = true
    centerYAnchor.constraint(equalTo: viewportView.centerYAnchor).isActive = true
  }

}

extension PlayerWindowController {

  // MARK: - Default album art visibility

  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let showDefaultArt else { return }

    log.verbose{"\(showDefaultArt ? "Showing" : "Hiding") defaultAlbumArt"}
    // Update default album art visibility:
    defaultAlbumArtView.isHidden = !showDefaultArt
  }

}
