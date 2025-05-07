//
//  GeometryTransform.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-08.
//


struct GeometryTransform {
  // MARK: - GeometryTransform Fields

  /// Name of the transform
  let name: String

  /// If `stateTransition` is `nil` (omitted), treat as no-op and continue to `videoTransform`.
  /// If `stateTransition` returns `nil`, transition should be aborted.
  let stateTransition: PWinSessionState.Transform?

  let videoTransform: VideoGeometry.Transform?
  let windowedTransform: PWinGeometry.Transform?
  let musicModeTransform: MusicModeGeometry.Transform?

  let onSuccess: (() -> Void)?

  init(name: String,
       state: ((Context) -> PWinSessionState?)? = nil,
       video: ((Context) -> VideoGeometry?)? = nil,
       windowed: ((Context) -> PWinGeometry?)? = nil,
       musicMode: ((Context) -> MusicModeGeometry?)? = nil,
       onSuccess: (() -> Void)? = nil) {
    self.name = name
    self.stateTransition = state
    self.videoTransform = video
    self.windowedTransform = windowed
    self.musicModeTransform = musicMode
    self.onSuccess = onSuccess
  }

  /// Standard `VideoGeometry.Transform` for use in response to a `vid` property change event from mpv.
  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  /// If current media's vid track changed, may need to apply new geometry
  static func trackChanged(_ context: Context) -> VideoGeometry? {
    context.vidTrackChanged()
  }

  // MARK: - Context

  /// `struct GeometryTransform.Context`
  /// Can be used for `VideoGeometry` transforms, `PWinGeometry` transforms, or `MusicModeGeometry` transforms.
  struct Context {
    let tf: GeometryTransform
    var name: String { tf.name }

    /// Contains most up-to-date version of the geometries (as well as possibly unapplied changes), which transforms should build
    /// on top of. (The `PlayerWindowController`'s `geo` field should not be referenced).
    let oldGeo: GeometrySet

    // Other state at the time of transform (immutable)

    let sessionState: PWinSessionState
    let currentPlayback: Playback
    let vidTrackID: Int
    let currentMediaAudioStatus: PlaybackInfo.CurrentMediaAudioStatus

    let player: PlayerCore

    var log: Logger.Subsystem { player.log }

    func clone(oldGeo: GeometrySet? = nil, sessionState: PWinSessionState? = nil) -> Context {
      return Context(tf: self.tf, oldGeo: oldGeo ?? self.oldGeo,
                     sessionState: sessionState ?? self.sessionState, currentPlayback: self.currentPlayback,
                     vidTrackID: self.vidTrackID, currentMediaAudioStatus: self.currentMediaAudioStatus,
                     player: player)
    }

    /// Standard `VideoGeometry.Transform` for video track change
    fileprivate func vidTrackChanged() -> VideoGeometry? {
      assert(DispatchQueue.isExecutingIn(player.mpv.queue))

      guard let videoGeo = syncVideoParamsFromMpv() else { return nil }

      if currentMediaAudioStatus.isAudio || vidTrackID == 0 {
        // Square album art
        return videoGeo
      }

      if !currentPlayback.isNetworkResource {
        // Update cache with latest video params
        MediaMetaCache.shared.updateCachedVideoMeta(id: currentPlayback.id, videoGeo, log)
      }

      log.debug{"[GeoTF:\(name)] Derived videoGeo \(videoGeo)"}
      return videoGeo
    }  // end of transform block

    // MARK: - Utils

    struct VideoParams: Decodable {
      let aspect: Double
      let par: Double
      let w: Int
      let h: Int
      let dw: Int
      let dh: Int
      let rotate: Int

      static func fromJSON(_ json: String?, _ objName: String, _ log: Logger.Subsystem) -> VideoParams? {
        do {
          guard let json else {
            log.error{"Failed to parse \(objName): obj is nil"}
            return nil
          }
          guard let jsonData = json.data(using: .utf8) else {
            log.error{"Failed create JSON data for \(objName)"}
            return nil
          }
          return try JSONDecoder().decode(VideoParams.self, from: jsonData)
        } catch {
          log.error{"Failed to get or parse \(objName) from mpv: \(error)"}
          return nil
        }
      }
    }

    /// Gets the given mpv property
    private func getWithRetries(_ mpvPropertyName: String) -> (propertyValue: String?, isError: Bool) {
      assert(DispatchQueue.isExecutingIn(player.mpv.queue))
      let retriesMax = 3
      var retryNum = 1
      while true {
        // This check seems to do a good job of determining when mpv is backed up.
        let path = player.mpv.getString(MPVProperty.path)
        guard path == currentPlayback.path else {
          log.warn{"[GeoTF:\(name)] Path mismatch! Will abort transform; mpv is likely backed up. Expected=\(currentPlayback.path.pii.quoted); Actual: \(path?.pii.quoted ?? "<nil>")"}
          return (nil, true)
        }

        if let propertyValue = player.mpv.getString(mpvPropertyName) {
          return (propertyValue, false)
        }
        retryNum += 1
        if retryNum > retriesMax { break }
        let pauseDuration = Constants.TimeInterval.videoParamsRetryInterval
        log.debug{"[GeoTF:\(name)] Could not get \(mpvPropertyName); will try again in \(pauseDuration)s (tries remaining: \(retriesMax - retryNum + 1))"}
        Thread.sleep(forTimeInterval: pauseDuration)
      }
      return (nil, false)
    }

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
      let (videoDecParamsJson, errorOccurredGettingVideoDecParams) = getWithRetries(MPVProperty.videoDecParams)
      guard !errorOccurredGettingVideoDecParams else { return nil }
      let videoDecParams = VideoParams.fromJSON(videoDecParamsJson, "videoDecParams", log)

      /// `video-out-params` == final video params for display
      /// This is known to return `nil` during startup, when loading a media file on a remote volume.
      /// Just wait for it as well.
      let (videoOutParamsJson, errorOccurredGettingVideoOutParams) = getWithRetries(MPVProperty.videoOutParams)
      guard !errorOccurredGettingVideoOutParams else { return nil }
      let videoOutParams = VideoParams.fromJSON(videoOutParamsJson, "videoOutParams", log)

      if Logger.isVerboseEnabled {
        let videoParams = player.mpv.getString(MPVProperty.videoParams)
        log.verbose{"[GeoTF:\(name)] Vid \(vidTrackID) has mpv videoDecParams=\(videoDecParamsJson ?? "nil"), videoParams=\(videoParams ?? "nil"), videoOutParams=\(videoOutParamsJson ?? "nil")"}
      }

      // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
      var userAspectLabelDerived = ""
      if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
        userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
        if userAspectLabelDerived != oldGeo.video.userAspectLabel {
          // Not necessarily an error? Need to improve aspect name matching logic
          log.debug{"[GeoTF:\(name)] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(oldGeo.video.userAspectLabel.quoted))"}
        }
      }

      /// Find `codecAspect`:
      let codecAspect: String?
      if let videoDecParams {
        /// `codecAspect` should match the product `par * sar`
        codecAspect = String(videoDecParams.aspect)
      } else if let videoOutParams {
        // It looks like libmpv is not always reliable at delivering videoDecParams, even at fileLoaded... Seems more likely under heavy load?
        // Try to derive codecAspect from other variables.
        // The aspect in videoOutParams should contain the number we want, unless there is an aspect override applied.
        let aspectDisplayed = videoOutParams.aspect
        let aspectDerived: Double
        if let aspectOverride = Aspect(string: userAspectLabelDerived)?.mpvAspect {
          // Looks like mpv modifies the video's par to get to the desired aspect. Should be able to work in reverse.
          assert(Double(aspectOverride).roundedTo6() == aspectDisplayed.roundedTo6(),
                 "aspectOverride \(aspectOverride) != displayedAspect \(aspectDisplayed)")
          let par = videoOutParams.par
          aspectDerived = aspectDisplayed / par
          log.debug{"[GeoTF:\(name)] Could not get videoDecParams; aspectOverride=\(aspectOverride); derived codecAspect from displayedAspect=\(aspectDisplayed) / par=\(par) → \(aspectDerived)"}
        } else {
          aspectDerived = aspectDisplayed
          log.debug{"[GeoTF:\(name)] Could not get videoDecParams; assuming codecAspect ≍ displayedAspect=\(aspectDisplayed), ∵ ∄ aspectOverride"}
        }
        codecAspect = String(aspectDerived.roundedTo6())
      } else {
        log.errorDebugAlert{"[GeoTF:\(name)] Failed to get codecAspect from either videoDecParams or videoOutParams"}
        codecAspect = nil
      }

      // Sync video's raw dimensions from mpv. This is especially important for streaming videos, which won't have cached videoMeta.
      // Fortunately the number don't seem to change between videoDecParams & videoOutParams.
      let rawWidth: Int?
      let rawHeight: Int?
      if let videoOutParams, videoOutParams.w > 0, videoOutParams.h > 0 {
        rawWidth = videoOutParams.w
        rawHeight = videoOutParams.h
      } else if let videoDecParams, videoDecParams.w > 0, videoDecParams.h > 0 {
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
      if let videoDecParams {
        if streamRotation != videoDecParams.rotate {
          player.log.error{"Mismatch: streamRotation (\(streamRotation)) != videoDecParams.rotate (\(videoDecParams.rotate))"}
        }
      }
      if let videoOutParams {
        if streamRotation != videoOutParams.rotate {
          player.log.error{"Mismatch: streamRotation (\(streamRotation)) != videoOutParams.rotate (\(videoOutParams.rotate))"}
        }
      }
#endif

      // If opening window, videoGeo may still have the global (default) log. Update it
      let videoGeo = oldGeo.video.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                        decodedAspectLabel: codecAspect,
                                        userAspectLabel: userAspectLabelDerived,
                                        streamRotation: streamRotation,
                                        userRotation: userRotation)



      // FIXME: audioStatus==notAudio for playlist which auto-plays audio
      if !currentMediaAudioStatus.isAudio, vidTrackID != 0 {
        let dwidth = videoOutParams?.dw ?? 0
        let dheight = videoOutParams?.dh ?? 0
        let ours = videoGeo.videoSizeCA
        // Apparently mpv can sometimes add a pixel. Not our fault...
        if (Int(ours.width) - dwidth).magnitude > 1 || (Int(ours.height) - dheight).magnitude > 1 {
          player.log.errorDebugAlert{"[\(name)] ❌ Sanity check for VideoGeometry failed: mpv dsize (\(dwidth)x\(dheight)) ≠ our videoSizeCA (\(ours)). VidTrack=\(vidTrackID) \(currentMediaAudioStatus) vidAspect=\(codecAspect ?? "nil")"}
        }
      }

      return videoGeo
    }

  }  // end struct GeometryTransform.Context
}
