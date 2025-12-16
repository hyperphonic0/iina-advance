//
//  MediaMetaCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-09-22.
//

/// Additional meta for the video track of a given media, if it has any video tracks.
struct VideoMeta : CustomStringConvertible {
  var description: String {
    "VideoMeta(w=\(rawWidth) h=\(rawHeight) rot=\(streamRotation))"
  }

  /// The native ("raw") stored dimensions of the video, before any transformation is applied.
  /// From the mpv manual:
  /// ```
  /// width, height
  ///   Video size. This uses the size of the video as decoded, or if no video frame has been decoded yet,
  ///   the (possibly incorrect) container indicated size.
  /// ```
  /// NOTE: Unlike mpv's usage, neither of these values should ever be `0`.
  let rawWidth: Int
  let rawHeight: Int

  /// The "inherent" aspect of the video as specified in its stream headers, transport data, etc., not including
  /// any overrides.
  let decodedAspectLabel: String

  /// Should match mpv's `video-params/rotate`
  let streamRotation: Int
}

struct MediaMeta: CustomStringConvertible {
  let id: PlaybackID

  let duration: Double?
  let progress: Double?
  let title: String?
  let album: String?
  let artist: String?

  /// Only a single video geometry per media is supported at present.
  let video: VideoMeta?

  /// Sometimes ffmpeg fails to read the file's meta. But we need to know it tried, so we don't keep retrying forever.
  ///
  /// We only use ffmpeg to read the text meta fields above, not `video`.
  // TODO: use mpv alone to probe all fields
  let triedFFmpeg: Bool

  init(_ id: PlaybackID,
       duration: Double? = nil, progress: Double? = nil,
       title: String? = nil, album: String? = nil, artist: String? = nil,
       video: VideoMeta? = nil,
       triedFFmpeg: Bool = false) {
    self.id = id
    self.duration = duration
    self.progress = progress
    // Sometimes newlines end up in the metadata (and on Windows these also include "\r" as well). Strip them for better visibility:
    self.title = title?.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
    self.album = album
    self.artist = artist
    self.video = video
    self.triedFFmpeg = triedFFmpeg
  }

  /// Use a negative value for `progress` to overwrite with `nil`.
  func clone(duration: Double? = nil, progress: Double? = nil,
             title: String? = nil, album: String? = nil, artist: String? = nil,
             video: VideoMeta? = nil,
             triedFFmpeg: Bool = false) -> MediaMeta {

    let newProgress: Double?
    if let progress {
      if progress < 0.0 {
        newProgress = nil
      } else {
        newProgress = progress
      }
    } else {
      newProgress = self.progress
    }

    return MediaMeta(id, duration: duration ?? self.duration, progress: newProgress,
                     title: title ?? self.title, album: album ?? self.album, artist: artist ?? self.artist,
                     video: video ?? self.video,
                     triedFFmpeg: triedFFmpeg || self.triedFFmpeg)
  }

  var description: String {
    "Media{dur=\(duration?.description ?? "␀") prog=\(progress?.description ?? "␀") title=\(title?.description.quoted ?? "␀") album=\(album?.description.quoted ?? "␀") artist=\(artist?.description.quoted ?? "␀") tried=\(triedFFmpeg.yn) vid=\(video?.description ?? "␀")}"
  }
}

/// Singleton for all app meta.
///
/// But currently separates meta categories into different lists.
/// Not retained across app launches.
class MediaMetaCache {
  static let shared = MediaMetaCache()

  private let log: any Logger.Subsystem = Logger.makeSubsystem("metaCache")
  private let metaLock = Lock()
  private var cachedMeta: [URL: MediaMeta] = [:]

  func fillInVideoSizes(_ videoFiles: [FileInfo], onBehalfOf player: PlayerCore) {
    guard Preference.bool(for: .prefetchPlaylistVideoGeometry) else {
      log.verbose("Prefetching video sizes is disabled (prefetchPlaylistVideoGeometry=NO), skipping…")
      return
    }
    log.verbose("Prefetching video sizes for \(videoFiles.count) files for player \(player.label)…")
    let sw = Utility.Stopwatch()
    var updateCount = 0
    for fileInfo in videoFiles {
      guard player.state.isNotYet(.stopping) else {
        log.verbose("Stopping after \(updateCount)/\(videoFiles.count) video sizes due to player \(player.label) stopping")
        return
      }
      if getOrReadVideoMeta(id: fileInfo.id, player.log) != nil {
        updateCount += 1
      }
    }
    log.verbose("Filled in \(updateCount)/\(videoFiles.count) video sizes for \(player.label) in \(sw) ms")
  }


  func calculateTotalDuration(_ urls: [URL]) -> Double {
    metaLock.withLock {
      return urls.compactMap { cachedMeta[$0]?.duration }.reduce(0, +)
    }
  }

  /// Returns entry from the cache with the given `id`, or `nil` if no such entry was found in the cache.
  func getCachedMeta(for id: PlaybackID) -> MediaMeta? {
    metaLock.withLock {
      return cachedMeta[id.url]
    }
  }

  /// Returns entry from the cache with the given `id`, if found in the cache; otherwise returns a newly created
  /// bare-bones entry for the given `id` after storing it in the cache.
  func getOrAddCachedMeta(for id: PlaybackID) -> MediaMeta {
    metaLock.withLock {
      if let meta = cachedMeta[id.url] {
        return meta
      }
      let newMeta = MediaMeta(id)
      cachedMeta[id.url] = newMeta
      return newMeta
    }
  }

  /// Updates the item in the cache with the given `id` using the provided values. The item is first created if
  /// necessary. The updated item is stored back into the cache and is then returned.
  ///
  /// Use `Constants.unknownProgress` (or any negative value) for `newProgress` to overwrite with `nil`.
  @discardableResult
  func updateCacheEntry(_ id: PlaybackID, newDuration: Double? = nil, newProgress: Double? = nil) -> MediaMeta {
    return metaLock.withLock {
      let oldMeta = cachedMeta[id.url] ??  MediaMeta(id)
      let newMeta = oldMeta.clone(duration: newDuration, progress: newProgress)
      cachedMeta[id.url] = newMeta
      return newMeta
    }
  }

  // MARK: - Artist, title meta

  /**
   Updates the cached entry for the item with the given `id`.b

   1. If item is a file & `reloadFromWatchLater` is true, then saved playback progress is updated from the item's watch-later file
   (or set to `nil` if there is no saved progress)
   2. If item is a file & `reloadFromFFmpeg` is true, then video duration, title, album, & artist are read from FFmpeg & saved to cache.
   3. If any of `mpvTitle`, `mpvAlbum`, or `mpvArtist` are specified, overwrite any previous value with these.
   Items 1 & 2 are expensive operations so this method should be executed in a background queue if either of these are used.
   */
  @discardableResult
  func updateCachedMeta(_ id: PlaybackID, reloadFromWatchLater: Bool = true, reloadFromFFmpeg: Bool = true,
                        mpvTitle: String? = nil, mpvAlbum: String? = nil, mpvArtist: String? = nil) -> MediaMeta {

    var progress: Double? = nil
    var duration: Double? = nil

    var title: String? = nil
    var album: String? = nil
    var artist: String? = nil

    var triedFFmpeg = false

    if id.isFile {
      if reloadFromWatchLater {
        // If watch-later returns nil, send negative value to clone() to ensure it is nilled out.
        // This is important to do to ensure that toggling the history checkbox in Preferences ends up
        // hiding the progress bars in the UI.
        progress = HistoryController.shared.playbackProgressFromWatchLater(id.mpvMD5) ?? -1
      }

      if reloadFromFFmpeg {
        triedFFmpeg = true
        if let dict = FFmpegController.probeVideoInfo(forFile: id.path) {

          duration = dict["@iina_duration"] as? Double

          dict.forEach { (k, v) in
            guard let key = k as? String else { return }
            switch key.lowercased() {
            case "title":
              title = v as? String
            case "album":
              album = v as? String
            case "artist":
              artist = v as? String
            default:
              break
            }
          }
        }
      }
    }

    // Favor mpv properties
    if let mpvTitle {
      title = mpvTitle
    }
    if let mpvAlbum {
      album = mpvAlbum
    }
    if let mpvArtist {
      artist = mpvArtist
    }

    return metaLock.withLock {
      let existingMeta = cachedMeta[id.url]
      let oldMeta = existingMeta ?? MediaMeta(id)
      let newMeta = oldMeta.clone(duration: duration, progress: progress,
                                  title: title, album: album, artist: artist,
                                  triedFFmpeg: oldMeta.triedFFmpeg || triedFFmpeg)
      cachedMeta[id.url] = newMeta

      // Compare oldMeta to newMeta; send update notification if different
      let didUpdateExisting = existingMeta != nil
      if didUpdateExisting,
          oldMeta.duration != newMeta.duration ||
          oldMeta.progress != newMeta.progress ||
          oldMeta.title != newMeta.title ||
          oldMeta.album != newMeta.album ||
          oldMeta.artist != newMeta.artist {
        log.trace("Cache entry changed: \(id.path.pii.quoted) ≔ \(newMeta)")
        postFileHistoryUpdateNotification(forURL: newMeta.id.url)
      }

      return newMeta
    }
  }

  /// Notifies the UI (playlist panel(s) & History window that the given URL has been updated, so they can pull it & update.
  func postFileHistoryUpdateNotification(forURL url: URL) {
    DispatchQueue.main.async {
      guard !AppDelegate.shared.isTerminating else { return }
      // TODO: attach object instead, so we don't have to pull it down
      let notification = Notification(name: .iinaFileHistoryDidUpdate, object: nil, userInfo: ["url": url])
      NotificationCenter.default.post(notification)
    }
  }


  // MARK: - Video Meta

  func updateCachedVideoMeta(id: PlaybackID, _ vidGeo: VideoGeometry, _ log: any Logger.Subsystem) {
    guard id.isFile else { return }
    guard id.path != "stdin" else { return }  // do not cache stdin!
    guard Utility.playableFileExt.contains(id.path.lowercasedPathExtension) else {
      log.verbose("Cannot update videoMeta, not a playable file: \(id.path.pii.quoted)")
      return
    }

    let videoMeta = VideoMeta(rawWidth: vidGeo.rawWidth, rawHeight: vidGeo.rawHeight,
                              decodedAspectLabel: vidGeo.decodedAspectLabel,
                              streamRotation: vidGeo.streamRotation)
    metaLock.withLock {
      let existingMeta = cachedMeta[id.url]
      let oldMeta = existingMeta ?? MediaMeta(id)
      let newMeta = oldMeta.clone(video: videoMeta)
      cachedMeta[id.url] = newMeta
    }
  }

  func getCachedVideoMeta(id: PlaybackID?) -> VideoMeta? {
    guard let id else { return nil }

    let mediaMeta = getCachedMeta(for: id)
    return mediaMeta?.video
  }

  private func readVideoMetaIntoCache(id: PlaybackID?) -> VideoMeta? {
    guard let id else { return nil }
    guard id.isFile else { return nil }
    let path = id.path
    guard path != "stdin" else { return nil }  // do not cache stdin!
    guard id.isFile else {
      log.verbose("Cannot read videoMeta, not a file URL: \(id.url.absoluteString.pii.quoted)")
      return nil
    }
    guard Utility.playableFileExt.contains(path.lowercasedPathExtension) else {
      log.verbose("Cannot read videoMeta, not a playable file: \(path.pii.quoted)")
      return nil
    }

    guard FileManager.default.fileExists(atPath: path) else {
      log.verbose("Skipping videoMeta update, file does not exist: \(path.pii.quoted)")
      return nil
    }

    // FIXME: use mpv instead!

//    if let sizeArray = FFmpegController.readVideoSize(forFile: path) {
//      let ffMeta = FFVideoMeta(width: Int(sizeArray[0]), height: Int(sizeArray[1]), streamRotation: Int(sizeArray[2]))
//      metaLock.withLock {
//        // Don't let this get too big
//        if cachedFFMeta.count > Constants.maxCachedVideoSizes {
//          log.debug("Too many cached FF meta entries (count=\(cachedFFMeta.count); maximum=\(Constants.maxCachedVideoSizes)). Clearing cached FF meta...")
//          cachedFFMeta.removeAll()
//        }
//        cachedFFMeta[id.url] = ffMeta
//      }
//      return ffMeta
//    } else {
//      // Not a serious error. Can happen for audio files.
//      log.debug("FFmpeg could not read video size for \(path.pii.quoted)")
//    }
    return nil
  }

  func getOrReadVideoMeta(id: PlaybackID?, _ log: any Logger.Subsystem) -> VideoMeta? {
    guard let id else { return nil }

    var missed = false
    var videoMeta = getCachedVideoMeta(id: id)
    if videoMeta == nil {
      missed = true
      videoMeta = readVideoMetaIntoCache(id: id)
    }

    guard let videoMeta else {
      log.error("Unable to find videoMeta from either cache or probe for \(id.path.pii.quoted)")
      return nil
    }
    log.verbose("Found videoMeta via \(missed ? "probe" : "cache"): \(videoMeta), for \(id.path.pii.quoted)")
    return videoMeta
  }

}
