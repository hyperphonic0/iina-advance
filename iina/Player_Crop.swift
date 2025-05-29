//
//  Player_Crop.swift
//  iina
//
//  Created by Matt Svoboda on 4/9/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerCore {

  func deriveCropLabel(x: Int, y: Int, w: Int, h: Int) -> String? {
    guard w != 0, h != 0 else {
      log.error{"Cannot derive crop label: w or h is 0! (x=\(x) y=\(y) w=\(w) h=\(h))"}
      return nil
    }
    if x == 0 && y == 0 {  // Aspect-based crop?
      // Truncate to 2 decimal places precision for comparison.
      let selectedAspect = Aspect(size: NSSize(width: w, height: h))
      log.verbose{"Determined aspect=\(selectedAspect.value) from: x=\(x) y=\(y) w=\(w) h=\(h)"}
      // Probably a selection from the Quick Settings panel. See if there are any matches.
      if let knownAspectLabel = Aspect.findLabelForAspectRatio(selectedAspect.value, isCrop: true, strict: false) {
        log.verbose{"Found known aspect label \(knownAspectLabel.quoted) from: x=\(x) y=\(y) w=\(w) h=\(h)"}
        return knownAspectLabel  // Known aspect-based crop
      }
      let customCropBoxLabel = MPVFilter.makeCropBoxParamString(from: NSSize(width: w, height: h))
      log.verbose{"Unrecognized aspect-based crop from: x=\(x) y=\(y) w=\(w) h=\(h). Generated label: \(customCropBoxLabel.quoted)"}
      return customCropBoxLabel  // Custom aspect-based crop
    } else {
      // Probably a custom crop. Use mpv formatting
      let cropBoxRect = NSRect(x: x, y: y, width: w, height: h)
      let customCropBoxLabel = MPVFilter.makeCropBoxParamString(from: cropBoxRect)
      log.verbose{"Looks like custom crop: x=\(x) y=\(y) w=\(w) h=\(h). Generated label: \(customCropBoxLabel.quoted)"}
      return customCropBoxLabel  // Custom cropBox rect crop
    }
  }

  func deriveCropLabel(from filter: MPVFilter) -> String? {
    guard let p = filter.params,
          let wStr = p["w"], let w = Int(wStr),
          let hStr = p["h"], let h = Int(hStr) else {
      return nil
    }
    guard w != 0, h != 0 else {
      log.error{"Cannot get crop from filter \(filter.label?.quoted ?? ""): w or h is 0"}
      return nil
    }

    let x, y: Int
    if let xStr = p["x"], let xInt = Int(xStr) {
      x = xInt
    } else {
      x = 0
    }

    if let yStr = p["y"], let yInt = Int(yStr) {
      y = yInt
    } else {
      y = 0
    }

    return deriveCropLabel(x: x, y: y, w: w, h: h)
  }

  func setCrop(fromLabel newCropLabel: String) {
    let videoGeo = videoGeo

    mpv.queue.async { [self] in
      guard let vf = videoGeo.buildCropFilter(from: newCropLabel) else {
        removeCrop()
        return
      }

      /// Do not call `updateSelectedCrop` - it will be called in response to `vf` property change event.
      /// Let mpv change it first.
      let addSucceeded = addVideoFilter(vf)
      if !addSucceeded {
        log.error{"Failed to add crop filter \(newCropLabel.quoted); setting crop to None"}
        removeCrop()
      }
    }
  }

  /// Returns `true` if successful.
  @discardableResult
  func removeCrop(updateFiltersListFirst: Bool = true) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    // special kludge when removing crop while entering interactive mode
    guard !info.videoFiltersDisabled.keys.contains(Constants.FilterLabel.crop) else {
      log.verbose("Ignoring request to remove crop because looks like we are transitioning to interactive mode")
      return false
    }

    if updateFiltersListFirst {
      // Ensure our state is up-to-date with mpv.
      // If no crop filter found, this will clean up the state for us & we will not need to do anything after.
      _ = updateVideoFiltersFromMpv()
    }

    // If VideoGeometry specifies a crop, remove the crop filter.
    // At this point, we know a crop filter is enabled, so removeVideoFilter will remove it & then clean up the state.
    let oldVideoGeo = windowController.geo.video
    guard let cropFilter = oldVideoGeo.cropFilter else { return false }
    guard oldVideoGeo.selectedCropLabel != AppData.noneCropIdentifier else { return false }
    log.verbose{"Setting crop to \(AppData.noneCropIdentifier.quoted) and removing crop filter"}
    return removeVideoFilter(cropFilter, verify: false, notify: false)
  }

  /// Call this after confirming the given crop has been added to mpv. Sets the window & video geometry & other state
  /// based on the given crop.
  func updateSelectedCrop(to newCropLabel: String) {
    guard !isRestoring else { return }

    // TODO: remove this
  }

  func getCropFilter() -> MPVFilter? {
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    for filter in videoFilters {
      if filter.label == Constants.FilterLabel.crop {
        return filter
      }
    }
    return nil
  }

}

