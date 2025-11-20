//
//  FilterPresets.swift
//  iina
//
//  Created by lhc on 25/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias PM = FilterParameter

/**
 A filter preset or template, which contains the filter name and definitions of all parameters.
 */
struct FilterPreset {
  typealias Transformer = @Sendable (FilterPresetInstance) -> MPVFilter

  private static let defaultTransformer: Transformer = { instance in
    return MPVFilter(lavfiFilterFromPresetInstance: instance)
  }

  let name: String
  let params: [String: FilterParameter]

  /// Order of the filter parameters.
  ///
  /// This dictates the order of parameters when the filter string is assembled as well as the order of controls presented to the user
  /// when adding a filter.
  let paramOrder: [String]
  /** Given an instance, create the corresponding `MPVFilter`. */
  let transformer: Transformer

  var localizedName: String {
    return FilterPreset.l10nDic[name] ?? name
  }

  init(_ name: String,
       params: [String: FilterParameter],
       paramOrder: String,
       transformer: @escaping Transformer = FilterPreset.defaultTransformer) {
    self.name = name
    self.params = params
    self.paramOrder = paramOrder.isEmpty ? [] : paramOrder.components(separatedBy: ":")
    self.transformer = transformer
  }

  func localizedParamName(_ param: String) -> String {
    return FilterPreset.l10nDic["\(name).\(param)"] ?? param
  }
}

/**
 An instance of a filter preset, with concrete values for each parameter.
 */
struct FilterPresetInstance {
  let preset: FilterPreset
  let params: [String: FilterParameterValue]

  init(from preset: FilterPreset, params: [String: FilterParameterValue] = [:]) {
    self.preset = preset
    self.params = params
  }

  func value(for name: String) -> FilterParameterValue {
    return params[name] ?? preset.params[name]!.defaultValue
  }
}

/**
 Definition of a filter parameter. It can be one of several types:
 - `text`: A generic string value.
 - `int`: An int value with range. It will be rendered as a slider.
 - `float`: A float value with range. It will be rendered as a slider.
 */
struct FilterParameter {
  enum ParamType {
    case text, int, float, choose
  }
  let type: ParamType
  let defaultValue: FilterParameterValue
  // for float
  let min: Float?
  let max: Float?
  // for int
  let minInt: Int?
  let maxInt: Int?
  let step: Int?
  // for choose
  let choices: [String]

  static func text(defaultValue: String = "") -> FilterParameter {
    return FilterParameter(.text, defaultValue: FilterParameterValue(string: defaultValue))
  }

  static func int(min: Int, max: Int, step: Int = 1, defaultValue: Int = 0) -> FilterParameter {
    FilterParameter(.int, defaultValue: FilterParameterValue(int: defaultValue), minInt: min, maxInt: max, step: step)
  }

  static func float(min: Float, max: Float, defaultValue: Float = 0) -> FilterParameter {
    FilterParameter(.float, defaultValue: FilterParameterValue(float: defaultValue), min: min, max: max)
  }

  static func choose(from choices: [String], defaultChoiceIndex: Int = 0) -> FilterParameter {
    guard !choices.isEmpty else { fatalError("FilterParameter: Choices cannot be empty") }
    return FilterParameter(.choose, defaultValue: FilterParameterValue(string: choices[defaultChoiceIndex]), choices: choices)
  }

  private init(_ type: ParamType, defaultValue: FilterParameterValue, min: Float? = nil, max: Float? = nil, minInt: Int? = nil, maxInt: Int? = nil, step: Int? = nil, choices: [String] = []) {
    self.type = type
    self.defaultValue = defaultValue
    self.min = min
    self.max = max
    self.minInt = minInt
    self.maxInt = maxInt
    self.step = step
    self.choices = choices
  }
}

/**
 The structure to store values of different param types.
 */
struct FilterParameterValue {
  private let _stringValue: String?
  private let _intValue: Int?
  private let _floatValue: Float?

  var stringValue: String {
    return _stringValue ?? _intValue?.description ?? _floatValue?.description ?? ""
  }

  var intValue: Int {
    return _intValue ?? 0
  }

  var floatValue: Float {
    return _floatValue ?? 0
  }

  init(string: String) {
    self._stringValue = string
    self._intValue = nil
    self._floatValue = nil
  }

  init(int: Int) {
    self._stringValue = nil
    self._intValue = int
    self._floatValue = nil
  }

  init(float: Float) {
    self._stringValue = nil
    self._intValue = nil
    self._floatValue = float
  }
}

/** Related data. */

extension FilterPreset {
  /** Preloaded localization. */
  static let l10nDic: [String: String] = {
    guard let filePath = Bundle.main.path(forResource: "FilterPresets", ofType: "strings"),
      let dic = NSDictionary(contentsOfFile: filePath) as? [String : String] else {
        return [:]
    }
    return dic
  }()

  static private let customMPVFilterPreset = FilterPreset("custom_mpv", params: ["name": PM.text(defaultValue: ""), "string": PM.text(defaultValue: "")], paramOrder: "name:string") { instance in
      return MPVFilter(rawString: instance.value(for: "name").stringValue + "=" + instance.value(for: "string").stringValue)!
  }
  // custom ffmpeg
  static private let customFFmpegFilterPreset = FilterPreset("custom_ffmpeg", params: [ "name": PM.text(defaultValue: ""), "string": PM.text(defaultValue: "") ], paramOrder: "name:string") { instance in
    return MPVFilter(name: "lavfi", label: nil, paramString: "[\(instance.value(for: "name").stringValue)=\(instance.value(for: "string").stringValue)]")
  }

  /** All filter presets. */
  static let vfPresets: [FilterPreset] = [
    // crop
    FilterPreset("crop", params: [
      "x": PM.text(), "y": PM.text(),
      "w": PM.text(), "h": PM.text()
    ], paramOrder: "w:h:x:y") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // expand
    FilterPreset("expand", params: [
      "x": PM.text(), "y": PM.text(),
      "w": PM.text(), "h": PM.text(),
      "aspect": PM.text(defaultValue: "0"),
      "round": PM.text(defaultValue: "1")
    ], paramOrder: "w:h:x:y:aspect:round") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // From the FFmpeg 6.0 documentation for the unsharp filter you would expect the luma matrix
    // horizontal and vertical size parameters to be limited to a maximum of 23. This is clearly
    // spelled out in the documentation. However FFmpeg imposes an additional restriction on the
    // combined size of these two parameters that is not currently mentioned in the documentation.
    // If this size is exceeded FFmpeg will reject the filter reporting the error message
    // "luma or chroma or alpha matrix size too big". To adhere to this restriction the matrix size
    // maximum must be 13. See issue #4259 for details.
    // sharpen
    FilterPreset("sharpen", params: [
      "amount": PM.float(min: 0, max: 1.5),
      "msize": PM.int(min: 3, max: 13, step: 2, defaultValue: 5)
    ], paramOrder: "msize:amount") { instance in
      return MPVFilter.unsharp(amount: instance.value(for: "amount").floatValue,
                               msize: instance.value(for: "msize").intValue)
    },
    // blur
    FilterPreset("blur", params: [
      "amount": PM.float(min: 0, max: 1.5),
      "msize": PM.int(min: 3, max: 13, step: 2, defaultValue: 5)
    ], paramOrder: "msize:amount") { instance in
      return MPVFilter.unsharp(amount: -instance.value(for: "amount").floatValue,
                               msize: instance.value(for: "msize").intValue)
    },
    // delogo
    FilterPreset("delogo", params: [
      "x": PM.text(defaultValue: "1"),
      "y": PM.text(defaultValue: "1"),
      "w": PM.text(defaultValue: "1"),
      "h": PM.text(defaultValue: "1")
    ], paramOrder: "x:y:w:h"),
    // invert color
    FilterPreset("negative", params: [:], paramOrder: "") { instance in
      return MPVFilter(lavfiName: "lutrgb", label: nil, paramDict: [
          "r": "negval", "g": "negval", "b": "negval"
        ])
    },
    // flip
    FilterPreset("vflip", params: [:], paramOrder: "") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // mirror
    FilterPreset("hflip", params: [:], paramOrder: "") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // 3d lut
    FilterPreset("lut3d", params: [
      "file": PM.text(),
      "interp": PM.choose(from: ["nearest", "trilinear", "tetrahedral"], defaultChoiceIndex: 0)
    ], paramOrder: "file:interp") { instance in
      return MPVFilter(lavfiName: "lut3d", label: nil, paramDict: [
        "file": instance.value(for: "file").stringValue,
        "interp": instance.value(for: "interp").stringValue,
        ])
    },
    // custom
    customMPVFilterPreset,
    customFFmpegFilterPreset
  ]

  static let afPresets: [FilterPreset] = [
    customMPVFilterPreset,
    customFFmpegFilterPreset
  ]
}
