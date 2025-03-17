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
class Playback: CustomStringConvertible {

  /// State of the individual playack
  enum LifecycleState: Int, StateEnum, CustomStringConvertible {
    case notYetStarted = 1    /// set before mpv is aware of it
    case started              /// set after mpv sends `fileStarted` notification
    case loaded               /// set after mpv sends `fileLoaded` notification & IINA has processed it
    case loadedAndSized       /// see `vidTrackLastSized`
    case ended                /// Not used at present

    var description: String {
      switch self {
      case .notYetStarted:
        return "notYetStarted"
      case .started:
        return "started"
      case .loaded:
        return "loaded"
      case .loadedAndSized:
        return "loadedAndSized"
      case .ended:
        return "ended"
      }
    }

    func isAtLeast(_ minStatus: LifecycleState) -> Bool {
      return rawValue >= minStatus.rawValue
    }

    func isNotYet(_ status: LifecycleState) -> Bool {
      return rawValue < status.rawValue
    }
  }  /// end `enum Playback.LifecycleState`


  /// Lifecycle state of this playback
  var state: LifecycleState {
    willSet {
      if newValue != state {
        Logger.log("Δ Playback.lifecycleState: \(state) → \(newValue)")
      }
    }
  }

  let id: PlaybackID

  /// Can be `nil` if not loaded yet
  var playlistPos: Int?

  var parentPlaylist: String = ""

  /// This must match the current `vid` track for the given media when determining whether a complete update is needed to VideoGeometry.
  ///
  /// Is set to `nil` initially because such an update must always run when state transitions to `fileLoaded`.
  var vidTrackLastSized: Int? = nil

  var thumbnails: SingleMediaThumbnailsLoader? = nil

  // Properties from PlaybackID
  var url: URL { id.url}
  var mpvMD5: String { id.mpvMD5 }
  var path: String { id.path }
  var isNetworkResource: Bool { id.isNetworkResource }
  var displayName: String { id.displayName }

  var description: String {
    return "Playback(plPos:\(String(playlistPos)) status:\(state) path:\(path.pii.quoted))"
  }

  init(_ id: PlaybackID, playlistPos: Int? = nil, state: LifecycleState = .notYetStarted) {
    self.id = id
    self.playlistPos = playlistPos
    self.state = state
  }

  /// if `url` is `nil`, assumed to be `stdin`
  convenience init(url: URL?, playlistPos: Int? = nil, state: LifecycleState = .notYetStarted) {
    let id = PlaybackID(url)
    self.init(id, playlistPos: playlistPos, state: state)
  }

  convenience init?(urlPath: String, playlistPos: Int? = nil, state: LifecycleState = .notYetStarted) {
    guard let id = PlaybackID(path: urlPath) else { return nil }
    self.init(id, playlistPos: playlistPos, state: state)
  }
}

/// `PlaybackID`
struct PlaybackID: Equatable, Hashable {
  /// Equivalent to `PlaybackID.url(fromPath: mpvFilename)`
  let url: URL
  let mpvMD5: String

  /// if `url` is `nil`, assumed to be `stdin`.
  init(_ url: URL?) {
    let url = url ?? URL(string: "stdin")!
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
  }

  init?(path: String) {
    guard let url = PlaybackID.url(fromPath: path) else { return nil }
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
  }

  var path: String { PlaybackID.path(from: url) }

  var filePath: String? {
    let urlPath = url.path
    return urlPath.isEmpty ? nil : urlPath
  }

  var networkPath: String? {
    isNetworkResource ? path : nil
  }

  var pathExtension: String { url.pathExtension }

  var isFile: Bool { url.isFileURL }

  var isNetworkResource: Bool { !isFile }

  var displayName: String { PlaybackID.displayName(from: url) }

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


  /// Returns the name of this resource as it should be displayed in the UI. Does not account for its `title` or other metadata.
  static func displayName(from url: URL?) -> String {
    guard let url else { return "-" }
    let urlPath = PlaybackID.path(from: url)
    let isNetworkResource = !url.isFileURL
    return isNetworkResource ? urlPath : NSString(string: urlPath).lastPathComponent
  }

  /// Do not use `url.path` for an unknown URL. Use this instead. It will handle both files and network URLs.
  static func path(from url: URL?) -> String {
    let url = url ?? URL(string: "stdin")!
    if url.absoluteString == "stdin" {
      return "-"
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }

  static func bookmark(fromURL url: URL, _ log: Logger.Subsystem) -> Data? {
    guard url.isFileURL else { return nil }
    guard FileManager.default.fileExists(atPath: url.path) else {
      log.trace{"Cannot create bookmark data from URL \(url.path.pii.quoted): file does not exist"}
      return nil
    }
    do {
      return try url.bookmarkData(options: .securityScopeAllowOnlyReadAccess, includingResourceValuesForKeys: nil, relativeTo: nil)
    } catch {
      log.error{"Failed to create bookmark data from URL \(path(from: url).pii.quoted): \(error)"}
      return nil
    }
  }

  static func url(fromBookmark bookmarkData: Data, _ log: Logger.Subsystem) -> URL? {
    var isStale = false
    do {
      return try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
    } catch {
      log.error{"Failed to restore bookmark data: \(error)"}
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
