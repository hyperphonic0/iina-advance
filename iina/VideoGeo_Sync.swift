//
//  VideoGeo_Sync.swift
//  iina
//
//  Created by Matt Svoboda on 2025-05-24.
//  Copyright © 2025 lhc. All rights reserved.
//

extension GeometryTransform.Context {

  /// An instance of this struct holds a subset of the parsed metadata for one of the following mpv properties
  /// (all of which have the same structure):
  /// - `video-params`
  /// - `video-dec-params`
  /// - `video-out-params`.
  fileprivate struct MpvVideoParams: Decodable {
    let aspect: Double
    let par: Double
    let w: Int
    let h: Int
    let dw: Int
    let dh: Int
    let rotate: Int

    static func fromJSON(_ json: String?, _ objName: String, _ log: Logger.Subsystem) -> MpvVideoParams? {
      guard let json else {
        log.error{"Failed to parse \(objName): obj is nil"}
        return nil
      }
      guard let jsonData = json.data(using: .utf8) else {
        log.error{"Failed create JSON data for \(objName)"}
        return nil
      }
      do {
        return try JSONDecoder().decode(MpvVideoParams.self, from: jsonData)
      } catch {
        log.error{"Failed to get or parse \(objName) from mpv: \(error)"}
        return nil
      }
    }

  }  // end struct MpvVideoParams


  /// Sync VideoGeometry from mpv `video-dec-params` & `video-out-params`
  func syncVideoParamsFromMpv() -> VideoGeometry? {
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))
    log.verbose{"[GeoTF:\(name)] Starting transform of \(currentPlayback.url.lastPathComponent.pii.quoted), vid=\(String(vidTrackID))|\(currentMediaAudioStatus), sessionState=\(sessionState)"}
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
      log.verbose{"[GeoTF:\(name)] Aborting: could not get video-dec-params"}
      return nil
    }

    /// `video-out-params` == final video params for display
    /// This is known to return `nil` during startup, when loading a media file on a remote volume.
    /// Just wait for it as well.
    guard let videoOutParams: MpvVideoParams = getWithRetries(propName: MPVProperty.videoOutParams) else {
      log.verbose{"[GeoTF:\(name)] Aborting: could not get video-out-params"}
      return nil
    }

    /// `codecAspect` should match the product `par * sar`
    let codecAspect = String(videoDecParams.aspect)

    // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
    var userAspectLabelDerived = ""
    if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
      userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
      if userAspectLabelDerived != oldGeo.video.userAspectLabel {
        // Not necessarily an error? Need to improve aspect name matching logic
        log.debug{"[GeoTF:\(name)] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(oldGeo.video.userAspectLabel.quoted))"}
      }
    }

    // Sync video's raw dimensions from mpv. This is especially important for streaming videos, which won't have cached videoMeta.
    // Fortunately the number don't seem to change between videoDecParams & videoOutParams.
    let rawWidth: Int?
    let rawHeight: Int?
    if videoOutParams.w > 0, videoOutParams.h > 0 {
      rawWidth = videoOutParams.w
      rawHeight = videoOutParams.h
    } else if videoDecParams.w > 0, videoDecParams.h > 0 {
      rawWidth = videoDecParams.w
      rawHeight = videoDecParams.h
    } else {
      if vidTrackID != 0 {
        log.warn{"[GeoTF:\(name)]: mpv returned 0 for w or h. Using cached size instead"}
      }
      rawWidth = nil
      rawHeight = nil
    }

    // TODO: sync video-crop (actually, add support for video-crop...)

    let streamRotation = player.mpv.getInt(MPVProperty.videoParamsRotate)
    // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
    let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

#if DEBUG
    // TODO: clean up these checks after doing more research
    if streamRotation != videoDecParams.rotate {
      player.log.error{"Mismatch: streamRotation (\(streamRotation)) != videoDecParams.rotate (\(videoDecParams.rotate))"}
    }
    if streamRotation != videoOutParams.rotate {
      player.log.error{"Mismatch: streamRotation (\(streamRotation)) != videoOutParams.rotate (\(videoOutParams.rotate))"}
    }
#endif

    // If opening window, videoGeo may still have the global (default) log. Update it
    var videoGeo = oldGeo.video.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                      decodedAspectLabel: codecAspect,
                                      userAspectLabel: userAspectLabelDerived,
                                      streamRotation: streamRotation,
                                      userRotation: userRotation)

    // FIXME: audioStatus==notAudio for playlist which auto-plays audio
    if !currentMediaAudioStatus.isAudio, vidTrackID != 0 {
      if videoOutParams.dw > 0, videoOutParams.dh > 0 {
        let dwidth = videoOutParams.dw
        let dheight = videoOutParams.dh

        let videoSizeDisplay: CGSize
        if videoGeo.isWidthSwappedWithHeightByTotalRotation {
          videoSizeDisplay = CGSize(width: dheight, height: dwidth)
        } else {
          videoSizeDisplay = CGSize(width: dwidth, height: dheight)
        }

        let ours = videoGeo.videoSizeCA

        // Apparently mpv can sometimes add a pixel. Not our fault...
        if (Int(ours.width) - dwidth).magnitude > 1 || (Int(ours.height) - dheight).magnitude > 1 {
          player.log.errorDebugAlert{"[\(name)] ❌ Sanity check for VideoGeometry failed: mpv dsize (\(dwidth)x\(dheight)) ≠ our videoSizeCA (\(ours)). VidTrack=\(vidTrackID) \(currentMediaAudioStatus) vidAspect=\(codecAspect)"}
        }

        videoGeo = videoGeo.clone(videoSizeDisplay: videoSizeDisplay)
      } else {
        player.log.errorDebugAlert{"[\(name)] ❌ Sanity check for VideoGeometry failed: dw or dh is nil in video-out-params! VidTrack=\(vidTrackID) \(currentMediaAudioStatus) vidAspect=\(codecAspect)"}
      }

    }

    return videoGeo
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
          log.verbose{"[GeoTF:\(name)] Vid \(vidTrackID) has mpv \(mpvPropertyName)=\(json)"}
        }
        let videoParams = MpvVideoParams.fromJSON(json, mpvPropertyName, log)
        return videoParams
      }

      retryNum += 1
      guard retryNum <= retriesMax else {
        log.verbose{"[GeoTF:\(name)] Vid \(vidTrackID) has mpv \(mpvPropertyName)=nil"}
        return nil
      }
      let pauseDuration = Constants.TimeInterval.videoParamsRetryInterval
      log.debug{"[GeoTF:\(name)] Could not get \(mpvPropertyName) from mpv; will try again in \(pauseDuration)s (tries remaining: \(retriesMax - retryNum + 1))"}
      Thread.sleep(forTimeInterval: pauseDuration)
    }
  }


}
