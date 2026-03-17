//
//  Player_Thumbnails.swift
//  iina
//
//  Created by Matt Svoboda on 12/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

struct Thumbnail: Sendable {
  let image: CGImage
  let timestamp: Double

  var nsImage: NSImage {
    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
  }

  /// We want the requested length of thumbnail to correspond to whichever video dimension is longer, and then get the corresponding width.
  /// Example: if video's native size is 600 W x 800 H and requested thumbnail size is 100, then `thumbWidth` should be 75.
  fileprivate static func determineWidthOfThumbnail(from videoSizeRaw: NSSize, log: any Logger.Subsystem) -> Int {
    let sizeOption: Preference.ThumbnailSizeOption = Preference.enum(for: .thumbnailSizeOption)
    switch sizeOption {
    case .scaleWithViewport:
      let rawSizePercentage = CGFloat(min(max(0, Preference.integer(for: .thumbnailRawSizePercentage)), 100))
      let thumbWidth = Int(round(videoSizeRaw.width * rawSizePercentage / 100))
      log.verbose("Thumbnail native width will be \(Int(videoSizeRaw.width))px * \(Int(rawSizePercentage))% → \(thumbWidth)px")
      return thumbWidth
    case .fixedSize:
      let requestedLength = CGFloat(Preference.integer(for: .thumbnailFixedLength))
      let thumbWidth: CGFloat
      if videoSizeRaw.height > videoSizeRaw.width {
        // Match requested size to video height
        if requestedLength > videoSizeRaw.height {
          // Do not go bigger than video's native width
          thumbWidth = videoSizeRaw.width
          log.debug("Video's height is longer than its width, & thumbLength (\(requestedLength)) is larger than video's native height (\(videoSizeRaw.height)); clamping thumbWidth to \(videoSizeRaw.width)")
        } else {
          thumbWidth = round(requestedLength * videoSizeRaw.aspect)
          log.debug("Video's height (\(videoSizeRaw.height)) is longer than its width (\(videoSizeRaw.width)); scaling down thumbWidth to \(thumbWidth)")
        }
      } else {
        // Match requested size to video width
        if requestedLength > videoSizeRaw.width {
          log.debug("Requested thumblLength (\(requestedLength)) is larger than video's native width; clamping thumbWidth to \(videoSizeRaw.width)")
          thumbWidth = videoSizeRaw.width
        } else {
          thumbWidth = requestedLength
        }
      }
      let thumbWidthInt = Int(thumbWidth)
      log.verbose("Using fixed thumbnail width of \(thumbWidthInt)")
      return thumbWidthInt
    }
  }

}

final class PlayerThumbnailsLoader {
  /// Do not access this directly from outside this file. Use `PlayerCore.currentMediaThumbnails` instead.
  fileprivate var currentMediaThumbnailsLoader: SingleMediaThumbnailsLoader? = nil {
    willSet {
      if let oldThumbs = currentMediaThumbnailsLoader, oldThumbs != newValue {
        oldThumbs.$isCancelled.withLock { $0 = true }
      }
    }
  }

  /// Do not access this directly from outside this file. Use `PlayerCore.currentMediaThumbnails` instead.
  fileprivate var thumbnailsEnabled: Bool = false
}

extension PlayerCore {
  /// This should be called any time `thumbnailsLoader.currentMediaThumbnails` or `thumbnailsLoader.thumbnailsEnabled` changes.
  private func refreshCurrentMediaThumbnails() {
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    let thumbnails = thumbnailsLoader.thumbnailsEnabled ? thumbnailsLoader.currentMediaThumbnailsLoader : nil

    DispatchQueue.main.async { [self] in
      // Copy this object from mpv queue isolation to main queue isolation
      currentMediaThumbnails = thumbnails
      touchBarSupport.touchBarPlaySlider?.resetCachedThumbnails()
    }
  }

  func shutDownPlayerThumbnails() {
    // need to run in mpv queue to maintain data isolation
    assert(DispatchQueue.isExecutingIn(mpv.queue))
    guard !isDemoPlayer else { return }

    log.verbose("Clearing thumbnails & cancelling thumbnail generation")
    thumbnailsLoader.currentMediaThumbnailsLoader = nil
    thumbnailsLoader.thumbnailsEnabled = false
    refreshCurrentMediaThumbnails()
  }

  private func checkThumbnailEnablement(_ currentPlayback: Playback?, vid videoTrackID: Int?) -> Bool {
    guard !isStopping else { return false }
    guard isInteractivePlayer else {
      log.verbose("Thumbnails reload stopped: player is non-interactive")
      return false
    }
    guard !Preference.bool(for: .integrateWithThumbfast) else {
      log.verbose("Thumbnails reload stopped: pref key `integrateWithThumbfast` is set")
      return false
    }
    guard let currentPlayback else {
      log.debug("Thumbnails reload stopped ∵ no current playback")
      return false
    }
    let videoTrackID = info.vid
    guard let videoTrackID, videoTrackID > 0 else {
      log.debug("Thumbnails reload stopped: invalid/missing video track: \(String(videoTrackID))")
      return false
    }
    guard !currentPlayback.isNetworkResource else {
      log.verbose("Thumbnails reload stopped: current media is network")
      return false
    }
    guard Preference.bool(for: .enableThumbnailPreview) else {
      log.verbose("Thumbnails reload stopped ∵ thumbnails are disabled by user")
      return false
    }
    if !Preference.bool(for: .enableThumbnailForRemoteFiles) && info.isMediaOnRemoteDrive {
      log.debug("Thumbnails reload stopped ∵ file is on a mounted remote drive")
      return false
    }
    if isInMiniPlayer && !Preference.bool(for: .enableThumbnailForMusicMode) {
      log.verbose("Thumbnails reload stopped ∵ user has disabled for music mode")
      return false
    }
    return true
  }

  func reloadThumbnails() {
    guard let pwc, pwc.loaded else { return }
    guard !isDemoPlayer else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.TimeInterval.thumbnailRegenerationDelay) { [self] in
      let videoGeo = pwc.geo.video

      mpv.queue.async { [self] in
        defer {
          // Always run this
          refreshCurrentMediaThumbnails()
        }

        let currentPlayback = info.currentPlayback
        let vid = info.vid
        let enabled = checkThumbnailEnablement(currentPlayback, vid: vid)
        thumbnailsLoader.thumbnailsEnabled = enabled
        guard enabled else {
          /// This means `thumbnailsLoader.thumbnailsEnabled = false`, which will cause thumbnail queries to return `nil`.
          /// Do not clear/cancel existing thumbnails (`thumbnailsLoader.currentMediaThumbnails`) here.
          /// Sometimes `info.vid` can be momentarily set to 0, which might otherwise create nasty race problems.
          return
        }
        let videoTrackID = vid!
        let playback = currentPlayback!

        // Generate thumbnails using video's original dimensions, before aspect ratio correction.
        // We will adjust aspect ratio & rotation when we display the thumbnail, similar to how mpv works.
        let videoSizeRaw = videoGeo.videoSizeRaw

        let thumbnailWidth = Thumbnail.determineWidthOfThumbnail(from: videoSizeRaw, log: log)

        if let currentMediaThumbnails = thumbnailsLoader.currentMediaThumbnailsLoader,
           currentMediaThumbnails.mediaFilePath == playback.url.path,
           currentMediaThumbnails.videoTrackID == videoTrackID,
           thumbnailWidth == currentMediaThumbnails.thumbnailWidth {
          log.debug("Already loaded thumbnails for vid\(videoTrackID) @ \(thumbnailWidth)px; nothing to do")
          return
        }

        log.verbose("Creating new thumbnails loader")
        let newMediaThumbnailLoader = SingleMediaThumbnailsLoader(self, mediaFilePath: playback.url.path,
                                                                  mediaFilePathMD5: playback.mpvMD5,
                                                                  videoTrackID: videoTrackID, thumbnailWidth: thumbnailWidth)
        // This will cancel / discard any previous thumbs for this player:
        thumbnailsLoader.currentMediaThumbnailsLoader = newMediaThumbnailLoader

        /*
        DispatchQueue.main.async { [self] in
          let demoPlayer = PlayerManager.shared.getOrCreateDemo()
          demoPlayer.mpv.queue.async {
            demoPlayer.mpv.command(.loadfile, args: [playback.url.path])
          }
          demoPlayer.seek(percent: 10.0)
          demoPlayer.mpv.queue.async { [self] in
            if let screenshotImg = demoPlayer.mpv.getScreenshot("video") {
              log.debug("Got screenshot: \(screenshotImg.size().description)")
            } else {
              log.error("Failed to get screenshot")
            }
          }
        }
        */

        // Run the following in the background (`thumbnailQueue`) at lower priority, so the UI is not slowed down.
        ThumbnailCache.shared.thumbnailQueue.async { [self] in
          log.trace("Thumbnails reload requested")
          newMediaThumbnailLoader.loadThumbnails()
        }
      }
    }

  }
}


/// `SingleMediaThumbnailsLoader`: loads & retains in-memory thumbnails for a single video track of a single media file with a given size
///  (`thumbnailWidth`). An instance of this class should be discarded as soon as any of the previously listed variables change (after setting
///  `isCancelled` to `true`).
final class SingleMediaThumbnailsLoader: NSObject, FFmpegControllerDelegate {
  unowned let player: PlayerCore!
  let mediaFilePath: String
  let mediaFilePathMD5: String
  let videoTrackID: Int
  let thumbnailWidth: Int

  @Atomic var isCancelled = false
  @MainActor var thumbnailsProgress: Double = 0
  @MainActor var ffThumbnails: [FFThumbnail] = []
  @MainActor var thumbnails: [Thumbnail] = []

  var currentDisplayedThumbFFTimestamp: Double = -1

  lazy var ffmpegController: FFmpegController = {
    let controller = FFmpegController()
    controller.delegate = self
    return controller
  }()

  var log: any Logger.Subsystem {
    return player.log
  }

  init(_ player: PlayerCore, mediaFilePath: String, mediaFilePathMD5: String, videoTrackID: Int, thumbnailWidth: Int) {
    self.player = player
    self.mediaFilePath = mediaFilePath
    self.mediaFilePathMD5 = mediaFilePathMD5
    self.videoTrackID = videoTrackID
    self.thumbnailWidth = thumbnailWidth
  }

  func loadThumbnails() {
    assert(DispatchQueue.isExecutingIn(ThumbnailCache.shared.thumbnailQueue))

    guard FileManager.default.fileExists(atPath: mediaFilePath) else {
      log.debug("Aborting thumbnails load. File does not exist: \(mediaFilePath.pii.quoted)")
      return
    }

    let cacheName = mediaFilePathMD5
    if ThumbnailCache.shared.fileIsCached(forName: cacheName, forVideo: mediaFilePath, forWidth: thumbnailWidth) {
      log.trace("Found matching thumbnail cache name=\(cacheName.quoted), \(thumbnailWidth)px width for: \(mediaFilePath.pii.quoted)")
      if let thumbnails = ThumbnailCache.shared.read(forName: cacheName, forWidth: thumbnailWidth) {
        if thumbnails.count >= Constants.minThumbnailsPerFile {
          // Already done
          DispatchQueue.main.async { [self] in
            addThumbnails(thumbnails)
            thumbnailsProgress = 1
            player.refreshTouchBarSlider()
          }
          return
        } else {
          log.error("Expected at least \(Constants.minThumbnailsPerFile) thumbnails, but found only \(thumbnails.count) (width \(thumbnailWidth)px). Will try to regenerate")
        }
      } else {
        log.error("Cannot read thumbnails from cache \(cacheName.quoted), width \(thumbnailWidth)px. Will try to regenerate")
      }
    }

    log.debug("Generating new thumbnails for file \(mediaFilePath.pii.quoted), width=\(thumbnailWidth)")
    ffmpegController.generateThumbnail(forFile: mediaFilePath, thumbWidth:Int32(thumbnailWidth))
  }

  @MainActor
  private func addThumbnails(_ ffThumbnailsNew: [FFThumbnail]) {
    // FFmpegController can send duplicates. Weed them out by timestamp
    var existingTimestamps = Set(self.thumbnails.compactMap{ $0.timestamp })

    var addedCount: Int = 0
    for ffThumbnailNew in ffThumbnailsNew {
      guard !existingTimestamps.contains(ffThumbnailNew.realTime) else { continue }
      guard let rawImage = ffThumbnailNew.image?.cgImage else { continue }

      self.ffThumbnails.append(ffThumbnailNew)
      let thumb = Thumbnail(image: rawImage, timestamp: ffThumbnailNew.realTime)
      self.thumbnails.append(thumb)
      existingTimestamps.insert(ffThumbnailNew.realTime)
      addedCount += 1
    }
  }

  @MainActor
  func getThumbnail(forSecond sec: Double) -> Thumbnail? {
    guard !thumbnails.isEmpty else { return nil }
    var tb = thumbnails.last!
    for i in 0..<thumbnails.count {
      if thumbnails[i].timestamp >= sec {
        tb = thumbnails[(i == 0 ? i : i - 1)]
        break
      }
    }
    return tb
  }

  func invalidateDisplayedThumbnail() {
    currentDisplayedThumbFFTimestamp = -1
  }

  // MARK: - FFmpegControllerDelegate implementation

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, thumbWidth width: Int32, withProgress progress: Int) {
    ThumbnailCache.shared.thumbnailQueue.async { [self] in
      // quick & dirty workaround for indexing method discrepancy: just add 1
      let progress = progress + 1
      guard !isCancelled else {
        log.debug("Discarding thumbnails update (\(width)px width, progress \(progress)) due to cancel")
        return
      }
      guard mediaFilePath == filename, width == thumbnailWidth else {
        log.errorDebugAlert("Discarding thumbnails update (\(width)px width, progress \(progress)): either sourcePath or thumbnailWidth does not match expected")
        return
      }
      let targetCount = ffmpegController.thumbnailCount + 1

      guard !isCancelled else { return }

      DispatchQueue.main.async { [self] in
        if let thumbnails, thumbnails.count > 0 {
          addThumbnails(thumbnails)
        }
        log.debug("Got \(thumbnails?.count ?? 0) more \(width)px thumbs (\(self.thumbnails.count) so far), progress: \(progress) / \(targetCount)")
        thumbnailsProgress = Double(progress) / Double(targetCount)
      }
    }
  }

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, thumbWidth width: Int32, succeeded: Bool) {
    guard !isCancelled else {
      log.debug("Discarding thumbnails (\(width)px), due to cancel")
      return
    }
    guard mediaFilePath == filename, width == thumbnailWidth else {
      log.error("Ignoring generated thumbnails (\(width)px width): either filePath or thumbnailWidth does not match expected")
      return
    }

    guard !isCancelled else { return }

    DispatchQueue.main.async { [self] in
      if thumbnails.count > 0 {
        log.trace("Got final count of \(thumbnails.count) thumbs, width=\(width)px")
        addThumbnails(thumbnails)
      }
      log.debug("Done generating thumbnails, success=\(succeeded.yn) count=\(self.thumbnails.count) width=\(width)px")
      guard succeeded else { return }

      player.refreshTouchBarSlider()
      guard !ffThumbnails.isEmpty else {
        log.verbose("No thumbnails to write")
        return
      }
      let ffThumbnailsToWrite = ffThumbnails
      ffThumbnails = []  // clear reference - not needed anymore

      ThumbnailCache.shared.thumbnailQueue.async { [self] in
        ThumbnailCache.shared.write(ffThumbnailsToWrite, forName: mediaFilePathMD5,
                                    forVideo: mediaFilePath, forWidth: Int(width))
      }

      player.events.emit(.thumbnailsReady)
    }

  }
}
