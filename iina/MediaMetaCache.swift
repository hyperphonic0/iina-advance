//
//  MediaMetaCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-09-22.
//

// TODO: consider merging this with MediaMeta
struct FFVideoMeta {
  let width: Int
  let height: Int
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

  /// Sometimes ffmpeg fails to read the file's meta. But we need to know it tried, so we don't keep retrying forever.
  let triedFFmpeg: Bool

  init(_ id: PlaybackID,
       duration: Double? = nil, progress: Double? = nil,
       title: String? = nil, album: String? = nil, artist: String? = nil,
       triedFFmpeg: Bool = false) {
    self.id = id
    self.duration = duration
    self.progress = progress
    // Sometimes newlines end up in the metadata (and on Windows these also include "\r" as well). Strip them for better visibility:
    self.title = title?.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
    self.album = album
    self.artist = artist
    self.triedFFmpeg = triedFFmpeg
  }

  func clone(duration: Double? = nil, progress: Double? = nil, nilProgress: Bool = false,
             title: String? = nil, album: String? = nil, artist: String? = nil, triedFFmpeg: Bool = false) -> MediaMeta {
    return MediaMeta(id, duration: duration ?? self.duration, progress: nilProgress ? nil : (progress ?? self.progress),
                     title: title ?? self.title, album: album ?? self.album, artist: artist ?? self.artist, triedFFmpeg: triedFFmpeg || self.triedFFmpeg)
  }

  var description: String {
    "Media{dur=\(duration?.description ?? "␀") prog=\(progress?.description ?? "␀") title=\(title?.description ?? "␀") album=\(album?.description ?? "␀") artist=\(artist?.description ?? "␀")}"
  }
}

/// Singleton for all app meta.
///
/// But currently separates meta categories into different lists.
/// Not retained across app launches.
class MediaMetaCache {
  static let shared = MediaMetaCache()

  private let log: Logger.Subsystem = Logger.makeSubsystem("metaCache")
  private let metaLock = Lock()
  private var cachedMeta: [URL: MediaMeta] = [:]
  private var cachedFFMeta: [URL: FFVideoMeta] = [:]

  func fillInVideoSizes(_ videoFiles: [FileInfo], onBehalfOf player: PlayerCore) {
    guard Preference.bool(for: .prefetchPlaylistVideoGeometry) else {
      log.verbose{"Prefetching video sizes is disabled (prefetchPlaylistVideoGeometry=NO), skipping…"}
      return
    }
    log.verbose{"Prefetching video sizes for \(videoFiles.count) files for player \(player.label)…"}
    let sw = Utility.Stopwatch()
    var updateCount = 0
    for fileInfo in videoFiles {
      guard player.state.isNotYet(.stopping) else {
        log.verbose{"Stopping after \(updateCount)/\(videoFiles.count) video sizes due to player \(player.label) stopping"}
        return
      }
      if getCachedVideoMeta(id: fileInfo.id) == nil {
        if reloadCachedVideoMeta(id: fileInfo.id) != nil {
          updateCount += 1
        }
      }
    }
    log.verbose{"Filled in \(updateCount)/\(videoFiles.count) video sizes for \(player.label) in \(sw) ms"}
  }


  func calculateTotalDuration(_ urls: [URL]) -> Double {
    metaLock.withLock {
      return urls.compactMap { cachedMeta[$0]?.duration }.reduce(0, +)
    }
  }

  func getCachedMeta(for id: PlaybackID) -> MediaMeta? {
    metaLock.withLock {
      return cachedMeta[id.url]
    }
  }

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

  func setCachedMediaDuration(_ id: PlaybackID, _ duration: Double) {
    guard duration > 0.0 else { return }
    metaLock.withLock {
      let oldMeta = cachedMeta[id.url] ?? MediaMeta(id)
      cachedMeta[id.url] = oldMeta.clone(duration: duration)
    }
  }

  func setCachedMediaDurationAndProgress(_ id: PlaybackID, duration: Double? = nil, progress: Double?) {
    metaLock.withLock {
      let oldMeta = cachedMeta[id.url] ??  MediaMeta(id)
      // nilProgress == kludge to force nil
      cachedMeta[id.url] = oldMeta.clone(duration: duration, progress: progress, nilProgress: progress == nil)
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
        progress = HistoryController.shared.playbackProgressFromWatchLater(id.mpvMD5)
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
      let newMeta = oldMeta.clone(duration: duration, progress: progress, nilProgress: progress == nil,
                                  title: title, album: album, artist: artist, triedFFmpeg: oldMeta.triedFFmpeg || triedFFmpeg)
      cachedMeta[id.url] = newMeta

      // Compare oldMeta to newMeta; send update notification if different
      let didUpdateExisting = existingMeta != nil
      if didUpdateExisting,
          oldMeta.duration != newMeta.duration ||
          oldMeta.progress != newMeta.progress ||
          oldMeta.title != newMeta.title ||
          oldMeta.album != newMeta.album ||
          oldMeta.artist != newMeta.artist {
        log.trace{"Cache entry changed: \(id.path.pii.quoted) ≔ \(newMeta)"}
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

  func getCachedVideoMeta(id: PlaybackID?) -> FFVideoMeta? {
    guard let id else { return nil }
    guard id.isFile else { return nil }
    guard id.path != "stdin" else { return nil }

    var ffMeta: FFVideoMeta? = nil
    metaLock.withLock {
      if let cachedMeta = cachedFFMeta[id.url] {
        ffMeta = cachedMeta
      }
    }
    return ffMeta
  }

  func reloadCachedVideoMeta(id: PlaybackID?) -> FFVideoMeta? {
    guard let id else { return nil }
    guard id.isFile else { return nil }
    let path = id.path
    guard path != "stdin" else { return nil }  // do not cache stdin!
    guard FileManager.default.fileExists(atPath: path) else {
      log.verbose{"Skipping ffMeta update, file does not exist: \(path.pii.quoted)"}
      return nil
    }

    if let sizeArray = FFmpegController.readVideoSize(forFile: path) {
      let ffMeta = FFVideoMeta(width: Int(sizeArray[0]), height: Int(sizeArray[1]), streamRotation: Int(sizeArray[2]))
      metaLock.withLock {
        // Don't let this get too big
        if cachedFFMeta.count > Constants.maxCachedVideoSizes {
          log.debug{"Too many cached FF meta entries (count=\(cachedFFMeta.count); maximum=\(Constants.maxCachedVideoSizes)). Clearing cached FF meta..."}
          cachedFFMeta.removeAll()
        }
        cachedFFMeta[id.url] = ffMeta
      }
      return ffMeta
    } else {
      // Not a serious error. Can happen for audio files.
      log.debug{"FFmpeg could not read video size for \(path.pii.quoted)"}
    }
    return nil
  }

  func ensureVideoMetaIsCached(id: PlaybackID?, _ log: Logger.Subsystem) {
    _ = getOrReadVideoMeta(id: id, log)
  }

  func getOrReadVideoMeta(id: PlaybackID?, _ log: Logger.Subsystem) -> FFVideoMeta? {
    guard let id else { return nil }

    guard id.isFile else {
      log.verbose{"Skipping ffMeta check; not a file URL: \(id.url.absoluteString.pii.quoted)"}
      return nil
    }
    let path = id.path
    guard Utility.playableFileExt.contains(path.lowercasedPathExtension) else {
      log.verbose{"Skipping ffMeta check; not a playable file: \(path.pii.quoted)"}
      return nil
    }

    var missed = false
    var ffMeta = getCachedVideoMeta(id: id)
    if ffMeta == nil {
      missed = true
      ffMeta = reloadCachedVideoMeta(id: id)
    }

    guard let ffMeta else {
      log.error{"Unable to find ffMeta from either cache or ffmpeg for \(path.pii.quoted)"}
      return nil
    }
    log.verbose{"Found ffMeta via \(missed ? "ffmpeg" : "cache"): \(ffMeta), for \(path.pii.quoted)"}
    return ffMeta
  }

}
