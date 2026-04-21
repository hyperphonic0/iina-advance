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
       state: LifecycleState = .notYetStarted) {
    self.id = id
    self.playlistPos = playlistPos
    self.parentPlaylist = parentPlaylist
    self.state = state
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
             state: LifecycleState? = nil) -> Playback {
    return Playback(id ?? self.id, playlistPos: playlistPos ?? self.playlistPos,
                    parentPlaylist: parentPlaylist ?? self.parentPlaylist,
                    state: state ?? self.state)
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
    let url = url ?? Constants.stdinURL
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
  var path: String { PlaybackID.path(from: url) }

  var filePath: String? {
    let urlPath = url.path
    return urlPath.isEmpty ? nil : urlPath
  }

  var networkPath: String? { isNetworkResource ? path : nil }
  var isStdin: Bool { url == Constants.stdinURL }
  var isFile: Bool { url.isFileURL }
  var isNetworkResource: Bool { url.isNetworkResource }
  var isMediaOnRemoteDrive: Bool { url.isMediaOnRemoteDrive }
  var pathExtension: String { url.pathExtension }
  var displayName: String { PlaybackID.displayName(from: url) }
  var needsBookmark: Bool { !isNetworkResource && bookmark == nil }

  /// If bookmark data is found, tries to resolve the URL from it. Otherwise just use its static URL.
  func resolveFileURL(_ log: any Logger.Subsystem) -> URL? {
    guard !isNetworkResource else {
      return nil
    }

    let url: URL
    if let bookmarkData = bookmark, !bookmarkData.isEmpty,
       let idFromBookmark = PlaybackID.resolvingBookmarkData(bookmarkData, updateCache: false, log) {
      url = idFromBookmark.staticURL
    } else {
      url = staticURL
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      log.error("File not found at URL: \(url.path.pii.quoted)")
      return nil
    }
    return url
  }

  /// Hashable protocol conformance, to enable diffing
  var hash: Int {
    var hasher = Hasher()
    hasher.combine(url)
    return hasher.finalize()
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }

  /// Equatable protocol conformance, to enable diffing
  func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? PlaybackID else {
      return false
    }
    return other.url == url
  }

  // MARK: - Static Methods

  static func == (lhs: PlaybackID, rhs: PlaybackID) -> Bool {
    return lhs.url == rhs.url
  }

  /// Returns the name of this resource as it should be displayed in the UI. Does not account for its `title` or other metadata.
  static func displayName(from url: URL?) -> String {
    guard let url else { return Constants.stdinPath }
    let urlPath = PlaybackID.path(from: url)
    let isNetworkResource = !url.isFileURL
    return isNetworkResource ? urlPath : NSString(string: urlPath).lastPathComponent
  }

  /// Do not use `url.path` for a playback URL of unknown origin. Use this instead. It will handle both files and network URLs,
  /// and notably IINA's nonstandard use of the string "stdin" to represent a `stdin` socket stream.
  static func path(from url: URL?) -> String {
    let url = url ?? Constants.stdinURL
    if url.absoluteString == "stdin" {
      return Constants.stdinPath
    } else {
      return url.isFileURL ? url.path : url.absoluteString
    }
  }

  /// If able to resolve a URL from the given bookmarkData, builds and returns a `PlaybackID` for it;
  /// otherwise returns `nil`.
  ///
  /// If `updateCache` is true (the default), also updates the central cache, including enqueuing any
  /// work needed to update a stale bookmark.
  /// The `staticURL` of the returned `PlaybackID` is guaranteed to be from the bookmark.
  /// Warning: this can be expensive! Use strategically.
  static func resolvingBookmarkData(_ bookmarkData: Data,
                                    updateCache: Bool = true,
                                    _ log: any Logger.Subsystem) -> PlaybackID? {
    guard !bookmarkData.isEmpty else { return nil }
    
    var isStale = false
    do {
      let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)

      let idWithBookmark = PlaybackID(bookmarkURL, bookmark: bookmarkData)

      if isStale {
        log.verbose("Resolved bookmark has gone stale; now has URL: \(bookmarkURL.absoluteString.pii.quoted)")
      }

      if updateCache {
        if isStale {

          // FIXME: enqueue task to update cached item

        } else {
          // Merge bookmark into cache
          MediaMetaCache.shared.updateCacheEntry(idWithBookmark)
        }
      }
      return idWithBookmark
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
    let url: URL?
    if path == Constants.stdinPath {
      url = Constants.stdinURL
    } else if path.first == "/" {
      url = URL(fileURLWithPath: path)
    } else {
      // For apps built with Xcode 15 or later the behavior of the URL initializer has changed when
      // running under macOS Sonoma or later. The behavior now matches URLComponents and will
      // automatically percent encode characters. Must not apply percent encoding to the string
      // passed to the URL initializer if the new new behavior is active.
      let pstr: String
      if #available(macOS 14, *) {
        pstr = path
      } else {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) else {
          Logger.log.error("Cannot add percent encoding for \(path)")
          return nil
        }
        pstr = encoded
      }
      url = URL(string: pstr)
      if url == nil {
        Logger.log.error("Cannot parse url for \(pstr)")
      }
    }
    return url
  }
}
