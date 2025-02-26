//
//  SpacerView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-26.
//  Copyright © 2025 lhc. All rights reserved.
//

class SpacerView: NSView {
  init(id: String? = nil) {
    super.init(frame: .zero)
    if let id {
      idString = id
    }
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    setContentHuggingPriority(.minimum, for: .horizontal)
    setContentHuggingPriority(.minimum, for: .vertical)
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)
  }
}
