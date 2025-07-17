//
//  VideoGeo_Sync.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-24.
//  Copyright © 2025 lhc. All rights reserved.
//

extension GeometryTransform {

  /// Standard `VideoGeometry.Transform` for use in response to a `vid` property change event from mpv.
  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  /// If current media's vid track changed, may need to apply new geometry
  static func syncVideoParamsFromMpv(_ context: Context) -> VideoGeometry? {
    context.syncVideoParamsFromMpv()
  }

}

extension GeometryTransform.Context {

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

    static func fromJSON(_ json: String?, _ objName: String, _ log: Logger.Subsystem) -> MpvVideoParams? {
      guard let json else {
        log.error{"Failed to parse \(objName): obj is nil"}
        return nil
      }
      let jsonModified = json.replacingOccurrences(of: "crop-", with: "crop_")  // make palatable for decoder default strategy
      guard let jsonData = jsonModified.data(using: .utf8) else {
        log.error{"Failed create JSON data for \(objName)"}
        return nil
      }
      do {
        let decoder = JSONDecoder()
        return try decoder.decode(MpvVideoParams.self, from: jsonData)
      } catch {
        log.error{"Failed to get or parse \(objName) from mpv: \(error)"}
        return nil
      }
    }
  }  // end struct MpvVideoParams


  /// Sync VideoGeometry from mpv `video-dec-params` & `video-out-params`
  func syncVideoParamsFromMpv(startingWith videoGeo: VideoGeometry? = nil) -> VideoGeometry? {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    log.verbose{"[GeoTF:\(name)] Syncing videoGeo from mpv for \(currentPlayback.url.lastPathComponent.pii.quoted) vid=\(String(vidTrackID))|\(currentMediaAudioStatus) sessState=\(sessionState)"}
    let vid = Int(player.mpv.getInt(MPVOption.TrackSelection.vid))
    guard vidTrackID == vid else {
      log.debug{"[GeoTF:\(name)] Aborting transform, vid=\(String(vidTrackID)) != actual vid \(vidTrackID)"}
      return nil
    }

    if currentMediaAudioStatus.isAudio || vidTrackID == 0 {
      // Square album art
      log.debug{"[GeoTF:\(name)] Using albumArtGeometry ∵ isAudio=\(currentMediaAudioStatus.isAudio.yn) vid=\(vidTrackID)"}
      return VideoGeometry.albumArtGeometry(log)
    }

    /// `video-dec-params` == video params without applied filters / overrides
    // When mpv return nil for video-dec-params, it's backed up. When this happens it  will actually then give us stale
    // data for videoOutParams! Seems like the best option is to wait for it. But adding some guardrails...
    // Fortunately we are already in the mpv queue. So we shouldn't block the UI, but we will be blocking mpv from processing
    // more user requests which would only add to the burden.
    guard let videoDecParams: MpvVideoParams = getWithRetries(propName: MPVProperty.videoDecParams) else {
      log.verbose{"[GeoTF:\(name)] Aborting: could not get video-dec-params for playback"}
      return nil
    }

    /// `video-out-params` == final video params for display
    /// This is known to return `nil` during startup, when loading a media file on a remote volume.
    /// Just wait for it as well.
    guard let videoOutParams: MpvVideoParams = getWithRetries(propName: MPVProperty.videoOutParams) else {
      log.verbose{"[GeoTF:\(name)] Aborting: could not get video-out-params for playback"}
      return nil
    }

    let oldVideoGeo = videoGeo ?? oldGeo.video

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
      assert(vidTrackID != 0, "[GeoTF:\(name)]: vidTrackID is 0, but we expected it to be non-zero")
      log.warn{"[GeoTF:\(name)]: mpv \(MPVProperty.videoDecParams) has 0 for w or h. Using cached size instead"}
      rawWidth = nil
      rawHeight = nil
    }

    // Derive crop label from video-out-params (is none if full-sized)
    let isNotCropped = videoOutParams.crop_x == 0 && videoOutParams.crop_y == 0 &&
                    videoOutParams.crop_w == rawWidth && videoOutParams.crop_h == rawHeight

    let cropLabel: String
    if isNotCropped {
      cropLabel = AppData.noneCropIdentifier
    } else {
      // First check for IINA crop filter. Derive selected crop label directly from the filter, because x & y values are ambiguous
      // in mpv's video-params APIs (nil & 0 both show as 0)
      if let vfCrop = player.getIINACropFilter(),
         let cropLabelFromIINACrop = player.deriveCropLabel(from: vfCrop, rawVideoSize: player.windowController.geo.video.videoSizeRaw) {
        cropLabel = cropLabelFromIINACrop
      } else {
        // If no IINA crop filter, the crop must have come from somewhere else.
        // Try to calculate the label from the raw values, working backwards.
        // FIXME: this generates false positives from non-right-angled video rotations. Need a better solution!
        let rawVideoSize: CGSize
        if let rawWidth, let rawHeight, rawWidth > 0, rawHeight > 0 {
          rawVideoSize = CGSize(width: rawWidth, height: rawHeight)
        } else {
          rawVideoSize = oldVideoGeo.videoSizeRaw
        }

        if let cropLabelFromVideoParams = player.deriveCropLabel(x: videoOutParams.crop_x, y: videoOutParams.crop_y,
                                                                 w: videoOutParams.crop_w, h: videoOutParams.crop_h,
                                                                 rawVideoSize: rawVideoSize) {
          cropLabel = cropLabelFromVideoParams
        } else {
          cropLabel = AppData.noneCropIdentifier
        }
      }
    }
    log.warn{"[GeoTF:\(name)] Determined crop label from mpv params: \(cropLabel.quoted)"}

    let streamRotation = videoDecParams.rotate
    // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
    let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

    // If opening window, videoGeo may still have the global (default) log. Update it
    var newVideoGeo = oldVideoGeo.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                        decodedAspectLabel: codecAspect,
                                        userAspectLabel: userAspectLabel,
                                        streamRotation: streamRotation,
                                        userRotation: userRotation,
                                        selectedCropLabel: cropLabel,
                                        videoSizeDisplayOverride: nil)

    // FIXME: audioStatus==notAudio for playlist which auto-plays audio
    assert(!currentMediaAudioStatus.isAudio && (vidTrackID != 0),
           "Unexpected currentMediaAudioStatus=\(currentMediaAudioStatus) for vidTrackID=\(vidTrackID)")

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
      player.log.errorDebugAlert{"[\(name)] ❌ SanityCheck-A failed: dw (\(dwidth)) or dh (\(dheight)) is 0 in \(useDSizeFromDecParams ? "video-dec-params" : "video-out-params")! vid=\(vidTrackID) \(currentMediaAudioStatus) codecAspect=\(codecAspect)"}
      return videoGeo
    }
    let videoSizeDisplay: CGSize
    if newVideoGeo.isWidthSwappedWithHeightByTotalRotation {
      videoSizeDisplay = CGSize(width: dheight, height: dwidth)
    } else {
      videoSizeDisplay = CGSize(width: dwidth, height: dheight)
    }

    if Logger.isErrorEnabled {
      let ours = newVideoGeo.videoSizeCA
      // Allow for almost 1% variance from mpv due to rounding or error margin
      let wDiff = abs(1 - (ours.width / CGFloat(dwidth)))
      let hDiff = abs(1 - (ours.height / CGFloat(dheight)))
      if wDiff >= 0.01 || hDiff >= 0.01 {
        player.log.errorDebugAlert{"[\(name)] ❌ SanityCheck-B failed: mpv dsize (\(dwidth)x\(dheight)) ≠ our videoSizeCA (\(ours))! vid=\(vidTrackID) \(currentMediaAudioStatus) codecAspect=\(codecAspect) videoSizeD=\(videoSizeDisplay)|\(videoSizeDisplay.mpvAspect) (from \(useDSizeFromDecParams ? "dec-params" : "out-params"))"}
      }
    }

    newVideoGeo = newVideoGeo.clone(videoSizeDisplayOverride: videoSizeDisplay)

    if !currentPlayback.isNetworkResource {
      // Update cache with latest video params
      MediaMetaCache.shared.updateCachedVideoMeta(id: currentPlayback.id, newVideoGeo, log)
    }

    // Compare aspects by numbers for simplicity
    let oldCustomAspectValue = Aspect(string: oldVideoGeo.userAspectLabel)?.value ?? 0.0
    let newCustomAspectValue = Aspect(string: userAspectLabel)?.value ?? 0.0
    if oldCustomAspectValue != newCustomAspectValue {
      // FIXME: Default aspect needs i18n
      log.verbose{"[GeoTF:\(name)] Changing userAspectLabel: \(oldVideoGeo.userAspectLabel.quoted) → \(userAspectLabel.quoted)"}
      player.sendOSD(.aspect(userAspectLabel))
    } else if userRotation != oldVideoGeo.userRotation {
      // Favor rotation OSD message over crop, because rotation increments < 90° will also trigger crop
      log.verbose{"[GeoTF:\(name)] Changing rotation: \(userRotation)"}
      player.sendOSD(.rotation(userRotation))
    } else if oldVideoGeo.selectedCropLabel != cropLabel {
      log.verbose{"[GeoTF:\(name)] Changing selectedCropLabel: \(oldVideoGeo.selectedCropLabel.quoted) → \(cropLabel.quoted)"}
      let osdLabel = cropLabel.isEmpty ? AppData.customCropIdentifier : cropLabel
      player.sendOSD(.crop(osdLabel))
    }

    log.debug{"[GeoTF:\(name)] Derived videoGeo from mpv video-params: \(newVideoGeo)"}
    return newVideoGeo
  }

  /// Gets the given property from the given player's mpv core, retrying as needed.
  /// Must be one of the `video-[*]params` properties, which contain JSON capable of being parsed as a `MpvVideoParams` object.
  /// Returns nil on failure.
  fileprivate func getWithRetries(propName mpvPropertyName: String) -> MpvVideoParams? {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))

    let retriesMax = 3
    var retryNum = 1
    guard let mpv = player.mpv else {
      return nil
    }
    let pathExpected = currentPlayback.path
    while true {
      // This check seems to do a good job of determining when mpv is backed up.
      let pathFound = mpv.getString(MPVProperty.path)

      guard pathFound == pathExpected else {
        log.warn{"[GeoTF:\(name)] Path mismatch! Will abort transform; mpv is likely backed up. Expected=\(pathExpected.pii.quoted); Actual: \(pathFound?.pii.quoted ?? "<nil>")"}
        return nil
      }

      if let json = mpv.getString(mpvPropertyName) {
        if Logger.isVerboseEnabled {
          log.verbose{"[GeoTF:\(name)] VidTrack-\(vidTrackID) mpv \(mpvPropertyName): \(json)"}
        }
        let videoParams = MpvVideoParams.fromJSON(json, mpvPropertyName, log)
        return videoParams
      }

      retryNum += 1
      guard retryNum <= retriesMax else {
        log.verbose{"[GeoTF:\(name)] Vid \(vidTrackID) has mpv \(mpvPropertyName): nil"}
        return nil
      }
      let pauseDuration = Constants.TimeInterval.videoParamsRetryInterval
      log.debug{"[GeoTF:\(name)] Could not get \(mpvPropertyName) from mpv; will try again in \(pauseDuration)s (tries remaining: \(retriesMax - retryNum + 1))"}
      Thread.sleep(forTimeInterval: pauseDuration)
    }
  }


}
