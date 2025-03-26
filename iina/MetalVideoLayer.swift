//
//  MetalVideoLayer.swift
//  iina
//
//  Created by Matt Svoboda on 2025-03-25.
//  Copyright © 2025 lhc. All rights reserved.
//

class MetalLayer: CAMetalLayer {

  override init() {
    super.init()

    pixelFormat = .rgba16Float
    backgroundColor = NSColor.black.cgColor
  }

  // necessary for when the layer containing window changes the screen
  override init(layer: Any) {
    let oldLayer = layer as! MetalLayer
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
