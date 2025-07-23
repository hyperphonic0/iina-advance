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
    translatesAutoresizingMaskIntoConstraints = false
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Akin to hiding the `DefaultAlbumArtView`.
  ///
  /// Can be run successive times without failing, but is not reentrant.
  fileprivate func addToThenLayout(inside viewportView: ViewportView) {
    removeFromLayout()
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

  /// Akin to showing the `DefaultAlbumArtView`.
  fileprivate func removeFromLayout() {
    guard superview != nil else { return }
    NSLayoutConstraint.deactivate(constraints)
    removeFromSuperview()
  }

}

extension PlayerWindowController {

  // MARK: - Default album art visibility

  /// Update default album art visibility to the given value, or do nothing if `nil`.
  ///
  /// This actually adds or removes `defaultAlbumArtView` from `viewportView`, along with the associated constraints, rather than changing `defaultAlbumArtView.isHidden`,
  /// which should always be false.
  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))  // Should actually be inside of an IINAAnimation.Task
    guard let showDefaultArt else { return }

    if showDefaultArt {
      log.verbose{"Showing defaultAlbumArt"}
      defaultAlbumArtView.addToThenLayout(inside: viewportView)
      sortViewportViewSubviews()
    } else {
      log.verbose{"Hiding defaultAlbumArt"}
      defaultAlbumArtView.removeFromLayout()
    }
  }

}
