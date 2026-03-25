//
//  Untitled.swift
//  iina
//
//  Created by Yuze Jiang on 2024/06/29.
//  Copyright © 2024 lhc. All rights reserved.
//

protocol EQProfile: Codable {
  /// Should have 10 elements
  var gains: [Double] { get }
}

struct UserEQProfile: EQProfile {
  /// Should have 10 elements
  let gains: [Double]

  init(_ values: [Double]) {
    gains = values
  }

  @MainActor
  init(fromCurrentSliders sliders: [NSSlider]) {
    gains = sliders.map { $0.doubleValue }
  }
}

struct PresetEQProfile: EQProfile {
  let localizationKey: String
  let name: String
  let gains: [Double]

  init(_ name: String, _ values: [Double]) {
    self.localizationKey = "eq.preset." + name
    self.name = NSLocalizedString(localizationKey, comment: localizationKey)
    gains = values
  }
}

class Equalizations {

  static let presetEQs: [PresetEQProfile] = [
    .init("flat", [0,0,0,0,0,0,0,0,0,0]),
    .init("acoustic", [5.0, 4.9, 3.95,1.05,2.15,1.75,3.5,4.1,3.55,2.15]),
    .init("classical", [4.75,3.75,3,2.5,-1.5,-1.5,0,2.25,3.25,3.75]),
    .init("dance", [3.57,6.55,4.99,0,1.92,3.65,5.15,4.54,3.59,0]),
    .init("deep",[4.95,3.55,1.75,1.00,2.85,2.50,1.45,-2.15,-3.55,-4.60]),
    .init("electronic", [4.25,3.8,1.2,0,-2.15,2.25,0.85,1.25,3.95,4.8]),
    .init("hip_hop", [5,4.25,1.5,3,-1,-1,1.5,-0.5,2,3]),
    .init("increase_bass", [5.5,4.25,3.5,2.5,1.25,0,0,0,0,0]),
    .init("increase_treble", [0,0,0,0,0,1.25,2.5,3.5,4.25,5.5]),
    .init("increase_vocal",[-1.50,-3.00,-3.00,1.50,3.75,3.75,3.00,1.50,0,-1.50]),
    .init("jazz", [4,3,1.5,2.25,-1.5,-1.5,0,1.5,3,3.75]),
    .init("latin",[4.5,3,0,0,-1.5,-1.5,-1.5,0,3,4.5]),
    .init("loundness",[6,4,0,0,-2,0,-1,-5,5,1]),
    .init("lounge",[-3.00,-1.50,-0.50,1.50,4.00,2.50,0,-1.50,2.00,1.00]),
    .init("piano", [3,2,0,2.5,3,1.5,3.5,4.5,3,3.5]),
    .init("pop", [-1.5,-1,0,2,4,4,2,0,-1,-1.5]),
    .init("rnb", [2.62,6.92,5.65,1.33,-2.19,-1.50,2.32,2.65,3.0,3.75]),
    .init("reduce_bass", [-5.5,-4.25,-3.5,-2.5,-1.25,0,0,0,0,0]),
    .init("reduce_treble", [0,0,0,0,0,-1.25,-2.5,-3.5,-4.25,-5.5]),
    .init("rock",[5,4,3,1.5,-0.5,-1,0.5,2.5,3.5,4.5]),
    .init("small_speaker",[5.5,4.25,3.5,2.5,1.25,0,-1.25,-2.5,-3.5,-4.25]),
    .init("spoken_word", [-3.46,-0.47,0,0.69,3.46,4.61,4.84,4.28,2.54,0]),
  ]

  @MainActor
  static var userEQs: Dictionary<String, UserEQProfile> = [:] {
    didSet {
      let encoder = JSONEncoder()
      if let encoded = try? encoder.encode(userEQs) {
        UserDefaults.standard.set(encoded, forKey: Preference.Key.userEQPresets.rawValue)
      }
    }
  }
}
