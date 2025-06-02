//
//  BufferIndicatorView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-06-01.
//  Copyright © 2025 lhc. All rights reserved.
//

class BufferIndicatorView: MouseIgnoringVisualEffectView {
  let bufferSpin = NSProgressIndicator()
  let bufferProgressLabel = NSTextField(labelWithString: "Buffering... 100%")
  let bufferDetailLabel = NSTextField()

  init() {
    super.init(frame: .zero)
    idString = "BufferIndicatorView"
    material = .popover
    blendingMode = .withinWindow
    state = .active

    subviews = [bufferSpin, bufferProgressLabel, bufferDetailLabel]
    translatesAutoresizingMaskIntoConstraints = false

    bufferSpin.idString = "BufferSpinner"
    bufferSpin.maxValue = 100
    bufferSpin.isIndeterminate = true
    bufferSpin.style = .spinning
    bufferSpin.translatesAutoresizingMaskIntoConstraints = false
    bufferSpin.topAnchor.constraint(equalTo: topAnchor, constant: 20).isActive = true
    bufferSpin.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
    bufferSpin.widthAnchor.constraint(equalToConstant: 48).isActive = true
    bufferSpin.heightAnchor.constraint(equalToConstant: 48).isActive = true

    bufferProgressLabel.idString = "BufferProgressLabel"
    bufferProgressLabel.translatesAutoresizingMaskIntoConstraints = false
    bufferProgressLabel.topAnchor.constraint(equalTo: bufferSpin.bottomAnchor, constant: 4).isActive = true
    bufferProgressLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor).isActive = true
    trailingAnchor.constraint(greaterThanOrEqualTo: bufferProgressLabel.trailingAnchor).isActive = true
    bufferProgressLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true

    bufferDetailLabel.idString = "BufferDetailLabel"
    bufferDetailLabel.controlSize = .mini
    bufferDetailLabel.font = .menuFont(ofSize: 9)
    bufferDetailLabel.textColor = .disabledControlTextColor
    bufferDetailLabel.translatesAutoresizingMaskIntoConstraints = false
    bufferDetailLabel.setContentHuggingPriority(.init(251), for: .horizontal)
    bufferDetailLabel.topAnchor.constraint(equalTo: bufferProgressLabel.bottomAnchor).isActive = true
    bottomAnchor.constraint(equalTo: bufferDetailLabel.bottomAnchor, constant: 8).isActive = true
    bufferDetailLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
  }
  
  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
