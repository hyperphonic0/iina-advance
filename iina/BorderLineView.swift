//
//  BorderLineView.swift
//  iina
//
//  Created by Matt Svoboda on 8/15/25.
//  Copyright © 2025 lhc. All rights reserved.
//

class BorderLineView: NSBox {

  init(id: String, fillColor: NSColor) {
    super.init(frame: .zero)
    configureSelf(id: id, fillColor: fillColor)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configureSelf()
  }

  private func configureSelf(id: String? = nil, fillColor: NSColor? = nil) {
    if let id {
      idString = id  // helps with debug logging
    }
    boxType = .custom
    titlePosition = .noTitle
    borderWidth = 0
    borderColor = .clear
    if let fillColor {
      self.fillColor = fillColor
    }
    translatesAutoresizingMaskIntoConstraints = false
    setContentHugging(h: 1, v: 1000)
    setCCResistance(h: 1, v: 1000)
  }
}
