//
//  Player_Filters.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-28.
//  Copyright © 2025 lhc. All rights reserved.
//

// mpv: Filter Operations
extension PlayerCore {

  /** Check if there are IINA filters saved in watch_later file. */
  func reloadSavedIINAfilters() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    let videoFilters = updateVideoFiltersFromMpv()
    postNotification(.iinaVFChanged)
    let audioFilters = updateAudioFiltersFromMpv()
    postNotification(.iinaAFChanged)
    log.verbose{"Total filters from mpv: \(videoFilters.count) vf, \(audioFilters.count) af"}
  }

  private func logRemoveFilter(type: String, result: Bool, name: String) {
    if !result {
      log.warn{"Failed to remove \(type) filter \(name)"}
    } else {
      log.debug{"Successfully removed \(type) filter \(name)"}
    }
  }

  // MARK: - Audio Filters

  func afChanged() {
    guard !isStopping else { return }
    _ = updateAudioFiltersFromMpv()
    saveState()
    setQuickSettingsViewNeedsUpdate()
    postNotification(.iinaAFChanged)
  }

  /// `af`: gets up-to-date list of audio filters AND updates associated state in the process
  func updateAudioFiltersFromMpv() -> [MPVFilter] {
    let audioFilters = mpv.getFilters(MPVProperty.af)
    for filter in audioFilters {
      log.verbose{"Got mpv af, name: \(filter.name.quoted), label: \(filter.label?.quoted ?? "nil"), params: \(filter.params ?? [:])"}
      guard let label = filter.label else { continue }
      if label.hasPrefix(Constants.FilterLabel.audioEq) {
        info.audioEqFilter = filter
      }
    }
    info.audioFilters = audioFilters
    return audioFilters
  }

  func setAudioEq(fromGains gains: [Double]) {
    let freqList = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let paramString = freqList.enumerated().map { (index, freq) in
      "equalizer=f=\(freq):t=h:width=\(Double(freq) / 1.224744871):g=\(gains[index])"
    }.joined(separator: ",")
    let filter = MPVFilter(name: "lavfi", label: Constants.FilterLabel.audioEq, paramString: "[\(paramString)]")
    addAudioFilter(filter)
    info.audioEqFilter = filter
  }

  func removeAudioEqFilter() {
    if let filter = info.audioEqFilter {
      removeAudioFilter(filter)
      info.audioEqFilter = nil
    }
  }

  /// Add an audio filter given as a `MPVFilter` object.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: MPVFilter) -> Bool { addAudioFilter(filter.stringFormat) }

  /// Add an audio filter given as a string.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  @discardableResult
  func addAudioFilter(_ filter: String) -> Bool {
    log.debug{"Adding audio filter \(filter)…"}
    var result = true
    result = mpv.command(.af, args: ["add", filter], checkError: false) >= 0
    log.debug{result ? "Succeeded" : "Failed"}
    return result
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    removeAudioFilter(filter.stringFormat, index)
  }

  /// Remove an audio filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeAudioFilter(_ filter: String, _ index: Int) -> Bool {
    log.debug{"Removing audio filter \(filter)…"}
    let result = mpv.removeFilter(MPVProperty.af, index)
    logRemoveFilter(type: "audio", result: result, name: filter)
    return result
  }

  /// Remove an audio filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeAudioFilter(_ filter: MPVFilter) -> Bool {
    removeAudioFilter(filter.stringFormat)
  }

  /// Remove an audio filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeAudioFilter(_ filter: String) -> Bool {
    log.debug{"Removing audio filter \(filter)…"}
    let returnCode = mpv.command(.af, args: ["remove", filter], checkError: false) >= 0
    log.debug{returnCode ? "Succeeded" : "Failed"}
    return returnCode
  }

  // MARK: - Video Filters

  /// Reloads filter list from mpv & uses it to update local state, then reload UI.
  func vfChanged() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isStopping else { return }
    _ = updateVideoFiltersFromMpv()

    postNotification(.iinaVFChanged)
    saveState()
    setQuickSettingsViewNeedsUpdate()
  }

  /// `vf`: gets up-to-date list of video filters
  /// AND updates associated state in the process
  func updateVideoFiltersFromMpv() -> [MPVFilter] {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    let videoFilters = mpv.getFilters(MPVProperty.vf)
    log.verbose{"Found \(videoFilters.count) VFs"}

    // Clear cached filters first:
    info.flipFilter = nil
    info.mirrorFilter = nil
    info.delogoFilter = nil
    for (filterIndex, filter) in videoFilters.enumerated() {
      log.verbose{"VF-\(filterIndex): name=\(filter.name.quoted) label=\(filter.label?.quoted ?? "nil") params=\(filter.params ?? [:])"}

      switch filter.label {
      case Constants.FilterLabel.flip:
        info.flipFilter = filter
      case Constants.FilterLabel.mirror:
        info.mirrorFilter = filter
      case Constants.FilterLabel.delogo:
        info.delogoFilter = filter
      default:
        break
      }
    }
    info.videoFilters = videoFilters

    return videoFilters
  }

  /// Add a video filter given as a `MPVFilter` object.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  /// Can run on either mpv or main DispatchQueue.
  // TODO: refactor to execute mpv commands only on mpv queue
  func addVideoFilter(_ filter: MPVFilter) -> Bool {
    let success = addVideoFilter(filter.stringFormat)
    if !success {
      log.verbose{"Video filter \(filter.stringFormat) was not added"}
    }
    return success
  }

  /// Add a video filter given as a string.
  ///
  /// This method will prompt the user to change IINA's video preferences if hardware decoding is set to `auto`.
  /// - Parameter filter: The filter to add.
  /// - Returns: `true` if the filter was successfully added, `false` otherwise.
  func addVideoFilter(_ filter: String) -> Bool {
    log.debug{"Adding video filter \(filter.quoted)..."}

    // check hwdec
    let hwdec = mpv.getString(MPVProperty.hwdec)
    if hwdec == "auto" {
      let askHwdec: (() -> Bool) = { [self] in
        let panel = NSAlert()
        panel.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
        panel.informativeText = NSLocalizedString("alert.filter_hwdec.message", comment: "")
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.turn_off", comment: "Turn off hardware decoding"))
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.use_copy", comment: "Switch to Auto(Copy)"))
        panel.addButton(withTitle: NSLocalizedString("alert.filter_hwdec.abort", comment: "Abort"))
        switch panel.runModal() {
        case .alertFirstButtonReturn:  // turn off
          mpv.setString(MPVProperty.hwdec, "no")
          Preference.set(Preference.HardwareDecoderOption.disabled.rawValue, for: .hardwareDecoder)
          return true
        case .alertSecondButtonReturn:
          mpv.setString(MPVProperty.hwdec, "auto-copy")
          Preference.set(Preference.HardwareDecoderOption.autoCopy.rawValue, for: .hardwareDecoder)
          return true
        default:
          return false
        }
      }

      // if not on main thread, post the alert in main thread
      if Thread.isMainThread {
        if !askHwdec() { return false }
      } else {
        var result = false
        DispatchQueue.main.sync {
          result = askHwdec()
        }
        if !result { return false }
      }
    }

    // try apply filter
    var didSucceed = true
    didSucceed = mpv.command(.vf, args: ["add", filter], checkError: false) >= 0
    log.debug{"Add filter: \(didSucceed ? "Succeeded" : "Failed")"}

    if didSucceed {
      // Bring UI up to date ASAP
      syncVideoParamsFromMpv()
    }
    return didSucceed
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: MPVFilter, _ index: Int) -> Bool {
    return removeVideoFilter(filter.stringFormat, index)
  }

  /// Remove a video filter based on its position in the list of filters.
  ///
  /// Removing a filter based on its position within the filter list is the preferred way to do it as per discussion with the mpv project.
  /// - Parameter filter: The filter to be removed, required only for logging.
  /// - Parameter index: The index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filter: String, _ index: Int) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    log.debug{"Removing video filter \(filter)..."}
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    let result = mpv.removeFilter(MPVProperty.vf, index)
    logRemoveFilter(type: "video", result: result, name: filter)
    syncVideoParamsFromMpv()
    return result
  }

  /// Remove a video filter given as a `MPVFilter` object.
  ///
  /// If the filter is not labeled then removing using a `MPVFilter` object can be problematic if the filter has multiple parameters.
  /// Filters that support multiple parameters have more than one valid string representation due to there being no requirement on the
  /// order in which those parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in
  /// the command sent to mpv does not match the order mpv expects the remove command will not find the filter to be removed. For
  /// this reason the remove methods that identify the filter to be removed based on its position in the filter list are the preferred way to
  /// remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  @discardableResult
  func removeVideoFilter(_ filter: MPVFilter, verify: Bool = true, notify: Bool = true) -> Bool {
    assert(DispatchQueue.isExecutingIn(mpv.queue))

    let filterString: String
    if let label = filter.label {
      // Has label: we care most about these
      // The vf remove command will return 0 even if the filter didn't exist in mpv. So need to do this check ourselves.
      let filterExists = mpv.getFilters(MPVProperty.vf).compactMap({$0.label}).contains(label)
      guard filterExists else {
        log.debug("Cannot remove video filter: could not find filter with label \(label.quoted) in mpv list. Will try refreshing filters & resyncing video params…")
        // Something fell out of date. Try refreshing
        vfChanged()
        syncVideoParamsFromMpv()
        return false
      }

      log.debug("Removing video filter \(label.quoted) (\(filter.stringFormat.quoted))...")
      filterString = "@" + label
    } else {
      log.debug("Removing video filter (\(filter.stringFormat.quoted))...")
      filterString = filter.stringFormat
    }

    guard removeVideoFilter(filterString) else {
      return false
    }

    let updatedFilterList = updateVideoFiltersFromMpv()
    syncVideoParamsFromMpv()  // call this *after* updating filter list
    /// `updateVideoFiltersFromMpv` will ensure various filter caches will stay up to date
    let didRemoveSuccessfully = !updatedFilterList.compactMap({$0.label}).contains(label)
    guard !verify || didRemoveSuccessfully else {
      log.error("Failed to remove video filter \(label.quoted): filter still present after vf remove!")
      return false
    }
    if notify {
      postNotification(.iinaVFChanged)
    }
    return true
  }

  /// Remove a video filter given as a string.
  ///
  /// If the filter is not labeled then removing using a string can be problematic if the filter has multiple parameters. Filters that support
  /// multiple parameters have more than one valid string representation due to there being no requirement on the order in which those
  /// parameters are given in a filter. If the order of parameters in the string representation of the filter IINA uses in the command sent to
  /// mpv does not match the order mpv expects the remove command will not find the filter to be removed. For this reason the remove
  /// methods that identify the filter to be removed based on its position in the filter list are the preferred way to remove a filter.
  /// - Parameter filter: The filter to remove.
  /// - Returns: `true` if the filter was successfully removed, `false` otherwise.
  func removeVideoFilter(_ filterString: String) -> Bool {
    // Just pretend it succeeded if no error
    let didError = mpv.command(.vf, args: ["remove", filterString], checkError: false) != 0
    log.debug(didError ? "Error executing vf-remove" : "No error returned by vf-remove")
    return !didError
  }

}
