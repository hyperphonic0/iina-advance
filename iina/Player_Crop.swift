//
//  Player_Crop.swift
//  iina
//
//  Created by Matt Svoboda on 4/9/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerCore {

  func deriveCropLabel(x: Int?, y: Int?, w: Int, h: Int, rawVideoSize: CGSize) -> String? {
    guard w != 0, h != 0 else {
      log.error("Cannot derive crop label: w or h is 0! (x=\(x?.description ?? "nil") y=\(y?.description ?? "nil") w=\(w) h=\(h))")
      return nil
    }

    let xForAspectCrop = Int((rawVideoSize.width - CGFloat(w)) * 0.5)
    let yForAspectCrop = Int((rawVideoSize.height - CGFloat(h)) * 0.5)
    log.verbose("Checking for aspect-based crop. Expect: x=\(xForAspectCrop) y=\(yForAspectCrop) | Actual: x=\(x?.description ?? "nil") y=\(y?.description ?? "nil") w=\(w) h=\(h)")
    if (x == nil && y == nil) || (xForAspectCrop == x && yForAspectCrop == y) {   // Aspect-based crop?
      // Truncate to 2 decimal places precision for comparison.
      let selectedAspect = Aspect(size: NSSize(width: w, height: h))
      log.verbose("Determined aspect=\(selectedAspect.value) from: x=\(x?.description ?? "nil") y=\(y?.description ?? "nil") w=\(w) h=\(h)")
      // Probably a selection from the Quick Settings panel. See if there are any matches.
      if let knownAspectLabel = Aspect.findLabelForAspectRatio(selectedAspect.value, isCrop: true, strict: false) {
        log.verbose("Found known aspect label \(knownAspectLabel.quoted) from: w=\(w) h=\(h)")
        return knownAspectLabel  // Known aspect-based crop
      }
      let customCropBoxLabel = MPVFilter.makeCropBoxParamString(from: NSSize(width: w, height: h))
      log.verbose("Unrecognized aspect-based crop from: w=\(w) h=\(h). Generated label: \(customCropBoxLabel.quoted)")
      return customCropBoxLabel  // Custom aspect-based crop
    } else {
      // Probably a custom crop. Use mpv formatting
      let x = x!
      let y = y!
      let cropBoxRect = NSRect(x: x, y: y, width: w, height: h)
      let customCropBoxLabel = MPVFilter.makeCropBoxParamString(from: cropBoxRect)
      log.verbose("Looks like custom crop: x=\(x) y=\(y) w=\(w) h=\(h). Generated label: \(customCropBoxLabel.quoted)")
      return customCropBoxLabel  // Custom cropBox rect crop
    }
  }

  func deriveCropLabel(from filter: MPVFilter, rawVideoSize: CGSize) -> String? {
    guard let p = filter.params,
          let wStr = p["w"], let w = Int(wStr),
          let hStr = p["h"], let h = Int(hStr) else {
      return nil
    }
    guard w != 0, h != 0 else {
      log.error("Cannot get crop from filter \(filter.label?.quoted ?? ""): w or h is 0")
      return nil
    }

    let x, y: Int?
    if let xStr = p["x"], let xInt = Int(xStr) {
      x = xInt
    } else {
      x = nil
    }

    if let yStr = p["y"], let yInt = Int(yStr) {
      y = yInt
    } else {
      y = nil
    }

    return deriveCropLabel(x: x, y: y, w: w, h: h, rawVideoSize: rawVideoSize)
  }

  func setCrop(fromLabel newCropLabel: String) {
    let videoGeo = videoGeo

    mpv.queue.async { [self] in
      if newCropLabel == AppData.noneCropIdentifier {
        log.verbose("Setting crop to None")
        removeCrop()
        return
      }

      guard let vf = videoGeo.buildCropFilter(from: newCropLabel) else {
        log.error("Failed build crop filter from \(newCropLabel.quoted); setting crop to None")
        removeCrop()
        return
      }

      /// Add the filter. Will wait for mpv to send a property change event for `dw` or `dy` before updating UI.
      let addSucceeded = addVideoFilter(vf)
      if !addSucceeded {
        log.error("Failed to add crop filter \(newCropLabel.quoted); setting crop to None")
        removeCrop()
      }
    }
  }

  /// Returns `true` if successful.
  @discardableResult
  func removeCrop() -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    // Don't care about state of videoGeo. Need to remove the crop filter if there is one.
    guard let cropFilter = getIINACropFilter() else {
      log.debug("Cannot remove crop: no filter found with label \(Constants.FilterLabel.crop.quoted). Will try to resync from mpv")
      syncVideoParamsFromMpv()
      return false
    }
    log.verbose("Setting crop to \(AppData.noneCropIdentifier.quoted) and removing crop filter")
    return removeVideoFilter(cropFilter, verify: false, notify: false)
  }

  func getIINACropFilter() -> MPVFilter? {
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    for filter in videoFilters {
      if filter.label == Constants.FilterLabel.crop {
        return filter
      }
    }
    return nil
  }

}

