//
//  VideoGeo_Sync.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-24.
//  Copyright © 2025 lhc. All rights reserved.
//
// This file encapsulates relevant code for `syncVideoParamsFromMpv()` which is executed as part of most (all?)
// `GeometryTransform`s. See header comments for `syncVideoParamsFromMpv`.

fileprivate let maxAttemptsForGetVideoParams = 6

extension GeometryTransform.ContextStage2 {

  /// An instance of this struct holds a subset of the parsed metadata for one of the following mpv properties
  /// (all of which have the same structure):
  /// - `video-params`
  /// - `video-dec-params`
  /// - `video-out-params`.
  fileprivate struct MpvVideoParams: Decodable {
    let w: Int
    let h: Int
    let dw: Int
    let dh: Int
    let par: Double
    let sar: Double
    let aspect: Double
    let rotate: Int
    let crop_x: Int
    let crop_y: Int
    let crop_w: Int
    let crop_h: Int

    static func fromJSON(_ json: String?, _ objName: String, _ log: any Logger.Subsystem) -> MpvVideoParams? {
      guard let json else {
        log.error("Failed to parse \(objName): obj is nil")
        return nil
      }
      let jsonModified = json.replacingOccurrences(of: "crop-", with: "crop_")  // make palatable for decoder default strategy
      guard let jsonData = jsonModified.data(using: .utf8) else {
        log.error("Failed create JSON data for \(objName)")
        return nil
      }
      do {
        let decoder = JSONDecoder()
        return try decoder.decode(MpvVideoParams.self, from: jsonData)
      } catch {
        log.error("Failed to get or parse \(objName) from mpv: \(error)")
        return nil
      }
    }
  }  // end struct MpvVideoParams


  /// Overwrites fields of the given `VideoGeometry` using fresh values from mpv `video-dec-params` & `video-out-params`.
  /// Returns `nil` if something bad happened.
  ///
  /// This is useful to synchronize between:
  /// 1. mpv's internal state
  /// 2. IINA's internal state
  /// 3. IINA player window layout (`PWinGeometry`, which is often dependent on the state of its `VideoGeometry`).
  /// 4. Status elements in the UI such as Quick Settings buttons/fields; & hopefully perform this smoothly & robustly.
  ///
  /// This should be executed as soon as possible *after* sending any updates to mpv for video params relating
  /// to VideoGeometry data (though *after* confirming that the update completed), but *before* performing any UI
  /// updates.
  func syncVideoParamsFromMpv(startingWith inputVideoGeo: VideoGeometry) -> VideoGeometry? {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    log.verbose("[GTF:\(name)] Syncing videoGeo from mpv for \(currentPlayback.url.lastPathComponent.pii.quoted) vid=\(String(vidTrackID))|\(currentMediaAudioStatus)")


    let vid = Int(player.mpv.getInt(MPVOption.TrackSelection.vid))
    guard vid == vidTrackID else {
      log.verbose("[GTF:\(name)] Aborting: current mpv video track (\(vid)) does not match expected (\(vidTrackID))")
      return nil
    }

    // FIXME: audioStatus==notAudio for playlist which auto-plays audio
    if (currentMediaAudioStatus == .isAudioWithoutArt || currentMediaAudioStatus == .isAudioWithArtHidden) || vidTrackID == 0 {
      // Default album art is square
      log.debug("[GTF:\(name)] Using albumArtGeometry ∵ isAudio=\(currentMediaAudioStatus.isAudio.yn) vid=\(vidTrackID)")
      return VideoGeometry.albumArtGeometry(log)
    }

    /// `video-dec-params` == video params without applied filters / overrides
    // When mpv return nil for video-dec-params, it's backed up. When this happens it  will actually then give us stale
    // data for videoOutParams! Seems like the best option is to wait for it. But adding some guardrails...
    // Fortunately we are already in the mpv queue. So we shouldn't block the UI, but we will be blocking mpv from processing
    // more user requests which would only add to the burden.
    guard let videoDecParams: MpvVideoParams = getWithRetries(propName: MPVProperty.videoDecParams) else {
      log.verbose("[GTF:\(name)] Aborting: could not get video-dec-params for playback")
      return nil
    }

    /// `video-out-params` == final video params for display
    /// This is known to return `nil` during startup, when loading a media file on a remote volume.
    /// Just wait for it as well.
    guard let videoOutParams: MpvVideoParams = getWithRetries(propName: MPVProperty.videoOutParams) else {
      log.verbose("[GTF:\(name)] Aborting: could not get video-out-params for playback")
      return nil
    }

    player.pwc.animationPipeline.gtfLock.withLock{ [self] in
      guard player.pwc.animationPipeline.wantsVideoGeoSync else { return }
      log.verbose("Setting wantsVideoGeoSync = NO")
      player.pwc.animationPipeline.wantsVideoGeoSync = false
    }

    /// `codecAspect` should match the product `par * sar`
    let codecAspect = String(videoDecParams.aspect)

    // Sync video-aspect-override
    let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) ?? Aspect.defaultIdentifier
    let userAspectLabel = Aspect.bestLabelFor(mpvVideoAspectOverride)

    // Sync video's raw dimensions from mpv. This is especially important for streaming videos, which won't have cached videoMeta.
    // Use video-dec-params for this, as video-out-params sometimes changes.
    let rawWidth: Int?
    let rawHeight: Int?
    if videoDecParams.w > 0, videoDecParams.h > 0 {
      rawWidth = videoDecParams.w
      rawHeight = videoDecParams.h
    } else {
      assert(vidTrackID != 0, "[GTF:\(name)]: vidTrackID is 0, but we expected it to be non-zero")
      log.warn("[GTF:\(name)]: mpv \(MPVProperty.videoDecParams) has 0 for w or h. Using cached size instead")
      rawWidth = nil
      rawHeight = nil
    }

    // No crop if full-sized. There may be an IINA filter though and we should favor that for status.
    // Make sure to use videoOutParams for all params in this comparion, as some dimensions will differ from videoDecParams.
    var isNotCropped = videoOutParams.crop_x == 0 && videoOutParams.crop_y == 0 && videoOutParams.crop_w == videoOutParams.w && videoOutParams.crop_h == videoOutParams.h

    let cropLabel: String
    // First check for IINA crop filter. Derive selected crop label directly from the filter, because x & y values are ambiguous
    // in mpv's video-params APIs (nil & 0 both show as 0)
    if let vfCrop = player.getIINACropFilter(),
       let cropLabelFromIINACrop = player.deriveCropLabel(from: vfCrop, rawVideoSize: inputVideoGeo.videoSizeRaw) {
      cropLabel = cropLabelFromIINACrop
      log.verbose("[GTF:\(name)] Determined crop label from iina_crop filter: \(cropLabel.quoted)")
      isNotCropped = false  // override this...it is still not perfect
    } else if isNotCropped {
      cropLabel = AppData.noneCropIdentifier
      log.verbose("[GTF:\(name)] Looks like video is not cropped")
    } else {
      // Check for other sources of crop.
      // Try to calculate the label from the raw values, working backwards.
      let rawVideoSize: CGSize
      if let rawWidth, let rawHeight, rawWidth > 0, rawHeight > 0 {
        rawVideoSize = CGSize(width: rawWidth, height: rawHeight)
      } else {
        rawVideoSize = inputVideoGeo.videoSizeRaw
      }

      cropLabel = player.deriveCropLabel(x: videoOutParams.crop_x, y: videoOutParams.crop_y,
                                         w: videoOutParams.crop_w, h: videoOutParams.crop_h,
                                         rawVideoSize: rawVideoSize)!
      log.verbose("[GTF:\(name)] Determined crop label from mpv params: \(cropLabel.quoted)")
    }

    let streamRotation = videoDecParams.rotate
    // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
    let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

    // If opening window, videoGeo may still have the global (default) log. Update it
    var outputVideoGeo = inputVideoGeo.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                             decodedAspectLabel: codecAspect,
                                             userAspectLabel: userAspectLabel,
                                             streamRotation: streamRotation,
                                             userRotation: userRotation,
                                             selectedCropLabel: cropLabel,
                                             videoSizeDisplayOverride: nil)

    // dw, dh: the actual displayed dimensions. Usually we can grab these from video-out-params, but sometimes it can be wrong,
    // so then try to infer from video-dec-params.
    let dwidth: Int
    let dheight: Int
    let mpvHasAspectOverride = videoDecParams.aspect != videoOutParams.aspect
    let useDSizeFromDecParams = isNotCropped && mpvHasAspectOverride && (userAspectLabel == Aspect.defaultIdentifier)
    if useDSizeFromDecParams {
      dwidth = videoDecParams.dw
      dheight = videoDecParams.dh
    } else {
      dwidth = videoOutParams.dw
      dheight = videoOutParams.dh
    }
    guard dwidth > 0, dheight > 0 else {
      player.log.errorDebugAlert("[\(name)] ❌ SanityCheck-A failed: dw (\(dwidth)) or dh (\(dheight)) is 0 in \(useDSizeFromDecParams ? "video-dec-params" : "video-out-params")! vid=\(vidTrackID) \(currentMediaAudioStatus) codecAspect=\(codecAspect)")
      return inputVideoGeo
    }
    let videoSizeDisplay: CGSize
    if outputVideoGeo.isWidthSwappedWithHeightByTotalRotation {
      videoSizeDisplay = CGSize(width: dheight, height: dwidth)
    } else {
      videoSizeDisplay = CGSize(width: dwidth, height: dheight)
    }

#if DEBUG
    if Logger.isErrorEnabled, DebugConfig.validatePWinGeometry {
      let ours = outputVideoGeo.videoSizeCA
      // Allow for almost 1% variance from mpv due to rounding or error margin
      let wDiff = abs(1 - (ours.width / CGFloat(dwidth)))
      let hDiff = abs(1 - (ours.height / CGFloat(dheight)))
      if wDiff >= 0.01 || hDiff >= 0.01 {
        player.log.error("[\(name)] ❌ SanityCheck-B failed: mpv dsize (\(dwidth)x\(dheight)) ≠ our videoSizeCA (\(ours))! vid=\(vidTrackID) \(currentMediaAudioStatus) codecAspect=\(codecAspect) videoSizeD=\(videoSizeDisplay)|\(videoSizeDisplay.mpvAspect) (from \(useDSizeFromDecParams ? "dec-params" : "out-params"))")
      }
    }
#endif

    outputVideoGeo = outputVideoGeo.clone(videoSizeDisplayOverride: videoSizeDisplay)

    if !currentPlayback.isNetworkResource {
      // Update cache with latest video params
      MediaMetaCache.shared.updateCachedVideoMeta(id: currentPlayback.id, outputVideoGeo, log)
    }

    // Compare aspects by numbers for simplicity
    let oldCustomAspectValue = Aspect(string: inputVideoGeo.userAspectLabel)?.value ?? 0.0
    let newCustomAspectValue = Aspect(string: userAspectLabel)?.value ?? 0.0
    if oldCustomAspectValue != newCustomAspectValue {
      // FIXME: Default aspect needs i18n
      log.verbose("[GTF:\(name)] Changing userAspectLabel: \(inputVideoGeo.userAspectLabel.quoted) → \(userAspectLabel.quoted)")
      player.sendOSD(.aspect(userAspectLabel))
    } else if userRotation != inputVideoGeo.userRotation {
      // Favor rotation OSD message over crop, because rotation increments < 90° will also trigger crop
      log.verbose("[GTF:\(name)] Changing rotation: \(userRotation)")
      player.sendOSD(.rotation(userRotation))
    } else if inputVideoGeo.selectedCropLabel != cropLabel,
              !pwc.isAnimatingLayoutTransition {
      // Don't show crop OSD when disabling it for entering interactive mode (layout transition)
      log.verbose("[GTF:\(name)] Changing selectedCropLabel: \(inputVideoGeo.selectedCropLabel.quoted) → \(cropLabel.quoted)")
      let osdLabel = cropLabel.isEmpty ? AppData.customCropIdentifier : cropLabel
      player.sendOSD(.crop(osdLabel))
    }

    log.debug("[GTF:\(name)] Derived videoGeo from mpv video-params: \(outputVideoGeo)")
    return outputVideoGeo
  }

  /// Gets the given property from the given player's mpv core, retrying as needed if nil is returned.
  /// Must be one of the `video-[*]params` properties, which contain JSON capable of being parsed as a `MpvVideoParams` object.
  /// Returns nil on failure.
  fileprivate func getWithRetries(propName mpvPropertyName: String) -> MpvVideoParams? {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))

    let maxRetries = maxAttemptsForGetVideoParams
    var retryNum = 1
    guard let mpv = player.mpv else {
      return nil
    }
    let pathExpected = currentPlayback.path
    while true {
      // This check seems to do a good job of determining when mpv is backed up.
      let pathFound = mpv.getString(MPVProperty.path)

      guard pathFound == pathExpected else {
        log.warn("[GTF:\(name)] Path mismatch! Will abort transform; mpv is likely backed up. Expected=\(pathExpected.pii.quoted); Actual: \(pathFound?.pii.quoted ?? "<nil>")")
        return nil
      }

      if let json = mpv.getString(mpvPropertyName) {
        log.verbose("[GTF:\(name)] VidTrack-\(vidTrackID) mpv \(mpvPropertyName): \(json)")
        let videoParams = MpvVideoParams.fromJSON(json, mpvPropertyName, log)
        return videoParams
      }

      retryNum += 1
      guard retryNum <= maxRetries else {
        log.verbose("[GTF:\(name)] Vid \(vidTrackID) has mpv \(mpvPropertyName): nil")
        return nil
      }
      let pauseDuration = Constants.TimeInterval.videoParamsRetryInterval
      log.debug("[GTF:\(name)] Could not get \(mpvPropertyName) from mpv. Will retry in \(pauseDuration)s (tries remaining: \(maxRetries - retryNum + 1))")
      Thread.sleep(forTimeInterval: pauseDuration)
    }
  }


}
