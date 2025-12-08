//
//  PreferenceViewController.swift
//  iina
//
//  Created by Collider LI on 8/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate let stackViewVertSpacing: CGFloat = 16

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
    guard let embeddable = self as? PreferenceWindowEmbeddable else { return }
    
    if embeddable.preferenceContentIsScrollable || !sectionViews.isEmpty {
      var views = sectionViews.flatMap { [$0, NSBox.horizontalLine()] }.dropLast()

      stackView = NSStackView(views: Array(views))
      stackView.orientation = .vertical
      stackView.alignment = .leading
      stackView.spacing = stackViewVertSpacing
      stackView.distribution = .fill
      stackView.idString = "PreferenceViewController.stackView"
      view.addSubview(stackView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": stackView])
      stackView.views.forEach { Utility.quickConstraints(["H:|[v]|"], ["v": $0]) }
    }


  }

}
