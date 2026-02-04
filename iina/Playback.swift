//
//  Playback.swift
//  iina
//
//  Created by Matt Svoboda on 2024-07-08.
//

import Foundation

/// Encapsulates the load status & other runtime metadata relating to a single playback of a given media.
///
/// An instance of this class should be created as soon as the user indicates their intent to play the media,
/// and should not be reused for subsequent play(s).
struct Playback: CustomStringConvertible, Sendable {

  /// State of the individual playack
  enum LifecycleState: Int, StateEnum, CustomStringConvertible {
    case notYetStarted = 1    /// set as soon as we are aware of file, but before mpv is aware of it
    case started              /// set after mpv sends `fileStarted` notification
    case loaded               /// set after mpv sends `fileLoaded` notification & IINA has processed it
    case loadedButNeedsSizing /// special kludge only used for the "FileLoaded" GTF
    case loadedAndSized       /// set after IINA has finished layout & display for it
    case ended                /// Not used at present

    var description: String {
      switch self {
      case .notYetStarted:
        return "notYetStarted"
      case .started:
        return "started"
      case .loaded:
        return "loaded"
      case .loadedButNeedsSizing:
        return "loadedButNeedsSizing"
      case .loadedAndSized:
        return "loadedAndSized"
      case .ended:
        return "ended"
      }
    }

    func isAtLeast(_ minStatus: LifecycleState) -> Bool { rawValue >= minStatus.rawValue }
    func isNotYet(_ status: LifecycleState) -> Bool { rawValue < status.rawValue }
  }  /// end `enum Playback.LifecycleState`


  /// Lifecycle state of this playback
  let state: LifecycleState

  let id: PlaybackID

  let playlistPos: Int

  let parentPlaylist: String

  // TODO: refactor to move this outside of Playback object
  let thumbnails: SingleMediaThumbnailsLoader?

  // Properties from PlaybackID
  var url: URL { id.url}
  var mpvMD5: String { id.mpvMD5 }
  var path: String { id.path }
  var isNetworkResource: Bool { id.isNetworkResource }
  var isMediaOnRemoteDrive: Bool { id.isMediaOnRemoteDrive }
  var displayName: String { id.displayName }

  var description: String {
    return "Playback(plPos:\(String(playlistPos)) status:\(state) path:\(path.pii.quoted))"
  }

  init(_ id: PlaybackID, playlistPos: Int, parentPlaylist: String = "",
       state: LifecycleState = .notYetStarted, thumbnails: SingleMediaThumbnailsLoader? = nil) {
    self.id = id
    self.playlistPos = playlistPos
    self.parentPlaylist = parentPlaylist
    self.state = state
    self.thumbnails = thumbnails
  }

  /// if `url` is `nil`, assumed to be `stdin`
  init(url: URL?, playlistPos: Int, parentPlaylist: String = "",
       state: LifecycleState = .notYetStarted) {
    let id = PlaybackID(url)
    self.init(id, playlistPos: playlistPos, parentPlaylist: parentPlaylist, state: state)
  }

  init?(urlPath: String, playlistPos: Int, parentPlaylist: String = "",
        state: LifecycleState = .notYetStarted) {
    guard let id = PlaybackID(path: urlPath) else { return nil }
    self.init(id, playlistPos: playlistPos, parentPlaylist: parentPlaylist, state: state)
  }

  func clone(id: PlaybackID? = nil,
             playlistPos: Int? = nil, parentPlaylist: String? =  nil,
             state: LifecycleState? = nil,
             thumbnails: SingleMediaThumbnailsLoader? = nil,
             clearThumbnails: Bool = false) -> Playback {
    let thumbnailsOut = clearThumbnails ? nil : thumbnails ?? self.thumbnails
    return Playback(id ?? self.id, playlistPos: playlistPos ?? self.playlistPos,
                    parentPlaylist: parentPlaylist ?? self.parentPlaylist,
                    state: state ?? self.state,
                    thumbnails: thumbnailsOut)
  }

  func changingState(to newState: LifecycleState) -> Playback {
    return clone(state: newState)
  }
}

/// `PlaybackID`
struct PlaybackID: Sendable, Equatable, Hashable {
  /// Equivalent to `PlaybackID.url(fromPath: mpvFilename)`.
  /// Deprecated! Use `url` instead, which will first try to resolve bookmark data.
  let staticURL: URL
  let mpvMD5: String
  let bookmark: Data?

  /// If `url` is `nil`, assumed to be `stdin`.
  init(_ url: URL?, bookmark: Data? = nil) {
    let url = url ?? URL(string: "stdin")!
    self.staticURL = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.bookmark = bookmark
  }

  init?(path: String, bookmark: Data? = nil) {
    guard let url = PlaybackID.url(fromPath: path) else { return nil }
    self.staticURL = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.bookmark = bookmark
  }

  var url: URL { staticURL }

  var path: String {
    return PlaybackID.path(from: url)
  }

  var filePath: String? {
    let urlPath = url.path
    return urlPath.isEmpty ? nil : urlPath
  }

  var networkPath: String? { isNetworkResource ? path : nil }

  var isFile: Bool { url.isFileURL }

  var isNetworkResource: Bool { url.isNetworkResource }

  var isMediaOnRemoteDrive: Bool {
    if let attrs = try? url.resourceValues(forKeys: Set([.volumeIsLocalKey])), !attrs.volumeIsLocal! {
      return true
    }
    return false
  }

  var pathExtension: String { url.pathExtension }

  var displayName: String { PlaybackID.displayName(from: url) }

  var needsBookmark: Bool { !isNetworkResource && bookmark == nil }

  /// Hashable protocol conformance, to enable diffing
  var hash: Int {
    var hasher = Hasher()
    hasher.combine(url)
    return hasher.finalize()
  }

  /// Equatable protocol conformance, to enable diffing
  func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? PlaybackID else {
      return false
    }
    return other.url == url
  }

  static func == (lhs: PlaybackID, rhs: PlaybackID) -> Bool {
    return lhs.url == rhs.url
  }

  /// Returns the name of this resource as it should be displayed in the UI. Does not account for its `title` or other metadata.
  static func displayName(from url: URL?) -> String {
    guard let url else { return "-" }
    let urlPath = PlaybackID.path(from: url)
    let isNetworkResource = !url.isFileURL
    return isNetworkResource ? urlPath : NSString(string: urlPath).lastPathComponent
  }

  /// Do not use `url.path` for a playback URL of unknown origin. Use this instead. It will handle both files and network URLs,
  /// and notably IINA's nonstandard use of the string "stdin" to represent a `stdin` socket stream.
  static func path(from url: URL?) -> String {
    let url = url ?? URL(string: "stdin")!
    if url.absoluteString == "stdin" {
      return "-"
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }

  /// Warning: this can be expensive! Use strategically.
  static func url(fromBookmark bookmarkData: Data, _ log: any Logger.Subsystem) -> URL? {
    var isStale = false
    do {
      return try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
    } catch {
      log.error("Failed to resolve URL from bookmark: \(error)")
      return nil
    }
  }


  /// Converts `urlPath` from what mpv calls `filename` in its APIs.
  ///
  /// This is a string which follows one of the following formats:
  /// 1. If a file resource, a file path in slash notation
  /// 2. If a network resource, a URL string in protocol://domain/resource/etc notation
  static func url(fromPath path: String) -> URL? {
    if path.contains("://") {
      return URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path)
    } else {
      return URL(fileURLWithPath: path)
    }
  }
}
