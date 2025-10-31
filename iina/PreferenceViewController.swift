//
//  PreferenceViewController.swift
//  iina
//
//  Created by Collider LI on 8/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PreferenceViewController: NSViewController {

  var stackView: NSStackView!

  var sectionViews: [NSView] {
    return []
  }

  func makeSymbol(_ name: String, fallbackImage: NSImage.Name) -> NSImage {
    guard #available(macOS 14, *) else { return NSImage(named: fallbackImage)! }
    let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
    return NSImage.findSFSymbol([name], withConfiguration: configuration)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let views = sectionViews.flatMap { [$0, NSBox.horizontalLine()] }.dropLast()

    if let embeddable = self as? PreferenceWindowEmbeddable, embeddable.preferenceContentIsScrollable || !sectionViews.isEmpty {
      stackView = NSStackView(views: Array(views))
      stackView.orientation = .vertical
      stackView.alignment = .leading
      stackView.spacing = 16
      stackView.distribution = .fill
      stackView.idString = "PreferenceViewController.stackView"
      view.addSubview(stackView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": stackView])
      stackView.views.forEach { Utility.quickConstraints(["H:|[v]|"], ["v": $0]) }
    }


  }

}
