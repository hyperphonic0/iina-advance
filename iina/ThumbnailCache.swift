//
//  ThumbnailCache.swift
//  iina
//
//  Created by lhc on 14/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let thumbCacheSubsystem = Logger.makeSubsystem("thumbcache")

class ThumbnailCache {
  static let shared = ThumbnailCache()

  let thumbnailQueue = DispatchQueue.newDQ(label: "IINA-PlayerThumbnail", qos: .utility)

  private typealias CacheVersion = UInt8
  private typealias FileSize = UInt64
  private typealias FileTimestamp = Int64

  let log = thumbCacheSubsystem
  private let version: CacheVersion = 2

  var isJobRunning = false
  var needsRefresh = true

  private var cachedContents: [URL]?
  private let sizeofMetadata = MemoryLayout<CacheVersion>.size + MemoryLayout<FileSize>.size + MemoryLayout<FileTimestamp>.size

  private let imageProperties: [NSBitmapImageRep.PropertyKey: CGFloat] = [
    .compressionFactor: 0.75
  ]

  private func fileExists(forName name: String, forWidth width: Int) -> Bool {
    return FileManager.default.fileExists(atPath: urlFor(name, width: width).path)
  }

  func fileIsCached(forName name: String, forVideo videoFilePath: String, forWidth width: Int) -> Bool {
    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoFilePath) else {
      log.error("Cannot get video file attributes")
      return false
    }

    // file size
    guard let fileSize = fileAttr[.size] as? FileSize else {
      log.error("Cannot get video file size")
      return false
    }

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      log.error("Cannot get video file modification date")
      return false
    }
    let fileTimestamp = FileTimestamp(fileModifiedDate.timeIntervalSince1970)

    // Check metadate in the cache
    guard self.fileExists(forName: name, forWidth: width) else {
      log.debug("Cache file does not exist for name=\(name.pii.quoted), width=\(width)")
      return false
    }

    guard let file = try? FileHandle(forReadingFrom: urlFor(name, width: width)) else {
      log.error("Thumbnail cache file exists but cannot be opened (for name=\(name.pii.quoted))")
      return false
    }

    let cacheVersion = file.read(type: CacheVersion.self)
    guard cacheVersion == version else {
      log.error("Wrong version in cache file! Found: \(cacheVersion ?? 0)")
      return false
    }

    let fileSizeInFile = file.read(type: FileSize.self)
    guard fileSizeInFile == fileSize else {
      log.debug("Video's file size (\(fileSize)) does not match cached size (\(fileSizeInFile ?? 0)); assuming cache is stale")
      return false
    }

    let fileTimestampInFile = file.read(type: FileTimestamp.self)
    guard fileTimestampInFile == fileTimestamp else {
      log.debug("Video's modification TS (\(fileTimestamp)) does not match cached TS (\(fileTimestampInFile ?? 0)); assuming cache is stale")
      return false
    }
    return true
  }

  /// Write thumbnail cache to file.
  /// This method is expected to be called when the file doesn't exist.
  func write(_ thumbnails: [FFThumbnail], forName name: String, forVideo videoFilePath: String, forWidth width: Int) {
    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize) * FloatingPointByteCountFormatter.PrefixFactor.mi.rawValue
    if maxCacheSize == 0 {
      log.verbose("Aborting write to thumbnail cache: maxCacheSize is 0")
      return
    }
    log.debug("Writing \(thumbnails.count) thumbnails width=\(width) to cache file \(name.pii) (videoFile=\(videoFilePath.pii))")

    let cacheSize = getCacheSize()
    if cacheSize > maxCacheSize {
      log.debug("Thumbnail cache size (\(cacheSize)) is larger than max allowed (\(maxCacheSize)) and will be cleared")
      clearOldCache()
    }

    let pathURL = urlFor(name, width: width)

    Utility.createDirIfNotExist(url: pathURL.deletingLastPathComponent())

    let path = pathURL.path
    guard FileManager.default.createFile(atPath: pathURL.path, contents: nil, attributes: nil) else {
      log.error("Cannot create thumbnail cache file: \(path.pii.quoted)")
      return
    }
    guard let file = try? FileHandle(forWritingTo: pathURL) else {
      log.error("Cannot write to thumbnail cache file: \(path.pii.quoted)")
      return
    }

    // version
    let versionData = Data(bytesOf: version)
    file.write(versionData)

    guard let fileAttr = try? FileManager.default.attributesOfItem(atPath: videoFilePath) else {
      log.error("Cannot get video file attributes (path: \(videoFilePath.pii.quoted))")
      return
    }

    // file size
    guard let fileSize = fileAttr[.size] as? FileSize else {
      log.error("Cannot get video file size from attributes")
      return
    }
    let fileSizeData = Data(bytesOf: fileSize)
    file.write(fileSizeData)

    // modified date
    guard let fileModifiedDate = fileAttr[.modificationDate] as? Date else {
      log.error("Cannot get video file modification date from attributes")
      return
    }
    let fileTimestamp = FileTimestamp(fileModifiedDate.timeIntervalSince1970)
    let fileModificationDateData = Data(bytesOf: fileTimestamp)
    file.write(fileModificationDateData)

    // data blocks
    for tb in thumbnails {
      let timestampData = Data(bytesOf: tb.realTime)
      guard let tiffData = tb.image?.tiffRepresentation else {
        log.error("Cannot generate tiff data.")
        return
      }
      guard let jpegData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: imageProperties) else {
        log.error("Cannot generate jpeg data.")
        return
      }
      let blockLength = Int64(timestampData.count + jpegData.count)
      let blockLengthData = Data(bytesOf: blockLength)
      file.write(blockLengthData)
      file.write(timestampData)
      file.write(jpegData)
    }

    if #available(macOS 10.15, *) {
      do {
        try file.close()
      } catch {
        log.error("Failed to close file: \(path.pii.quoted)")
      }
    }

    needsRefresh = true
    log.debug("Finished writing to: \(path.pii.quoted)")

    NotificationCenter.default.post(Notification(name: .iinaThumbnailCacheDidUpdate, object: nil, userInfo: nil))
  }

  /// Read thumbnail cache to file.
  /// This method is expected to be called when the file exists.
  func read(forName name: String, forWidth width: Int) -> [FFThumbnail]? {
    let pathURL = urlFor(name, width: width)
    let sw = Utility.Stopwatch()
    guard let file = try? FileHandle(forReadingFrom: pathURL) else {
      log.error("Cannot open file: \(pathURL.path.pii.quoted)")
      return nil
    }
    log.verbose("Reading from \(pathURL.path.pii.quoted)")

    defer {
      file.closeFile()
    }

    var result: [FFThumbnail] = []

    // get file length
    file.seekToEndOfFile()
    let eof = file.offsetInFile

    // skip metadata
    file.seek(toFileOffset: UInt64(sizeofMetadata))

    // data blocks
    while file.offsetInFile != eof {
      // length and timestamp
      guard let blockLength = file.read(type: Int64.self),
            let timestamp = file.read(type: Double.self) else {
        log.warn("Cannot read image header. Cache file will be deleted: \(pathURL.absoluteString.pii.quoted)")
        deleteCacheFile(at: pathURL)
        return nil
      }
      // jpeg
      let jpegData = file.readData(ofLength: Int(blockLength) - MemoryLayout.size(ofValue: timestamp))
      guard let image = NSImage(data: jpegData) else {
        log.warn("Cannot read image. Cache file will be deleted: \(pathURL.absoluteString.pii.quoted)")
        deleteCacheFile(at: pathURL)
        return nil
      }
      // construct
      let tb = FFThumbnail()
      tb.realTime = timestamp
      tb.image = image
      result.append(tb)
    }

    log.debug("Finished reading thumbnail cache: read \(result.count) thumbs in \(sw) ms")
    return result
  }

  private func deleteCacheFile(at pathURL: URL) {
    // try deleting corrupted cache
    do {
      try FileManager.default.removeItem(at: pathURL)
      NotificationCenter.default.post(Notification(name: .iinaThumbnailCacheDidUpdate, object: nil, userInfo: nil))
    } catch {
      log.error("Cannot delete corrupted cache: \(pathURL.absoluteString.pii.quoted)")
    }
  }

  // Thumbnail cache URL
  private func urlFor(_ name: String, width: Int) -> URL {
    return Utility.thumbnailCacheURL.appendingPathComponent("\(width)").appendingPathComponent(name)
  }

  // MARK: - Cache Folder

  private func cacheFolderContents() -> [URL]? {
    if needsRefresh {
      log.verbose("Refreshing cached thumbnails index")
      var updatedCache: [URL] = []
      if let thumbWidthDirs = try? FileManager.default.contentsOfDirectory(at: Utility.thumbnailCacheURL,
                                                                           includingPropertiesForKeys: [.contentAccessDateKey],
                                                                           options:
                                                                            [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
        for thumbWidthDir in thumbWidthDirs {
          if let dirThumbFiles = try? FileManager.default.contentsOfDirectory(at: thumbWidthDir,
                                                                              includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey],
                                                                              options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
            updatedCache.append(contentsOf: dirThumbFiles)
          }
        }
      }
      cachedContents = updatedCache
      needsRefresh = false
    }
    return cachedContents
  }

  func getCacheSize() -> Int {
    return cacheFolderContents()?.reduce(0 as Int) { totalSize, url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      return totalSize + size
    } ?? 0
  }

  func clearOldCache() {
    guard !isJobRunning else { return }
    isJobRunning = true

    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize)
    // if full, delete 50% of max cache
    let cacheToDelete = maxCacheSize * FloatingPointByteCountFormatter.PrefixFactor.mi.rawValue / 2

    log.verbose("Looking for \(cacheToDelete) byte to delete from thumbnail cache")

    // sort by access date
    guard let contents = cacheFolderContents()?.sorted(by: { url1, url2 in
      let date1 = (try? url1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? Date.distantPast
      let date2 = (try? url2.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? Date.distantPast
      return date1.compare(date2) == .orderedAscending
    }) else { return }

    // delete old cache
    var clearedCacheSize = 0
    for url in contents {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      if clearedCacheSize < cacheToDelete {
        try? FileManager.default.removeItem(at: url)
        clearedCacheSize += size
      } else {
        break
      }
    }
    log.verbose("Cleared \(clearedCacheSize) bytes from thumbnail cache")
  }

}
