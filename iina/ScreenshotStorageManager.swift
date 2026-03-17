//
//  ScreenshotStorageManager.swift
//  iina
//
//  Created by IINA on 2025-03-27.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Manages temporary storage for screenshots, optionally using a RAM disk for improved performance
/// 
/// Generated via Claude Sonnet 4.5.
final class ScreenshotStorageManager {
  static let shared = ScreenshotStorageManager()

  private let log = Logger.SimpleSubsystem(rawValue: "screenshot-storage")
  private var ramDisk: RAMDiskManager.RAMDisk?
  private let lock = NSLock()

  /// Whether to use RAM disk for temporary screenshots
  private var useRAMDisk: Bool { Preference.bool(for: .screenshotUseRAMDisk) }

  /// Size of RAM disk in MB (if enabled)
  private var ramDiskSize: Int { Preference.integer(for: .screenshotRAMDiskSizeMB) }

  private init() {
    // Register for app termination to cleanup
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
  }

  deinit {
    cleanup()
  }

  /// Sets up storage, creating RAM disk if needed
  func setup() {
    lock.lock()
    defer { lock.unlock() }

    guard useRAMDisk else {
      log.debug("RAM disk disabled in preferences, using standard temp directory")
      return
    }

    guard ramDisk == nil else {
      log.debug("RAM disk already setup")
      return
    }

    do {
      let sw = Utility.Stopwatch()
      let size = max(32, ramDiskSize) // APFS minimum is 32 MB
      ramDisk = try RAMDiskManager.createRAMDisk(sizeInMB: size, volumeName: "IINAScreenshots")
      log.verbose("Successfully created \(size) MB RAM disk in \(sw.secElapsedString) at \(ramDisk!.mountPoint.path.quoted)")
    } catch {
      log.error("Failed to create RAM disk for screenshots: \(error). Falling back to temp directory")
    }
  }

  /// Gets the directory to use for temporary screenshots
  func getTemporaryDirectory() -> URL {
    lock.lock()
    defer { lock.unlock() }

    // If RAM disk is available, use it
    if let ramDisk = ramDisk {
      return ramDisk.mountPoint
    }

    // Fall back to standard cache directory
    return Utility.screenshotCacheURL
  }

  /// Gets a unique URL for a temporary screenshot
  func getTemporaryScreenshotURL(format: String = "png") -> URL {
    let directory = getTemporaryDirectory()
    let filename = "iina-screenshot-\(UUID().uuidString).\(format)"
    return directory.appendingPathComponent(filename)
  }

  /// Cleans up the RAM disk if it exists
  func cleanup() {
    lock.lock()
    defer { lock.unlock() }

    guard let ramDisk = ramDisk else { return }

    log.debug("Cleaning up RAM disk")

    // Try to delete any remaining files first
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: ramDisk.mountPoint,
        includingPropertiesForKeys: nil,
        options: .skipsHiddenFiles
      )
      for file in files {
        try? FileManager.default.removeItem(at: file)
      }
    } catch {
      log.warn("Failed to clean up files from RAM disk: \(error)")
    }

    // Unmount the RAM disk
    do {
      try RAMDiskManager.unmountRAMDisk(devicePath: ramDisk.devicePath)
      log.verbose("Successfully unmounted RAM disk")
      self.ramDisk = nil
    } catch {
      log.error("Failed to unmount RAM disk: \(error)")
    }
  }

  /// Recreates the RAM disk if settings changed
  func reloadIfNeeded() {
    lock.lock()
    let currentlyUsingRAMDisk = ramDisk != nil
    let shouldUseRAMDisk = useRAMDisk
    let currentSize = ramDisk?.sizeInMB ?? 0
    let desiredSize = max(32, ramDiskSize)
    lock.unlock()

    // If we should be using RAM disk but aren't, set it up
    if shouldUseRAMDisk && !currentlyUsingRAMDisk {
      log.debug("RAM disk enabled in preferences, setting up")
      setup()
    }
    // If we're using RAM disk but shouldn't, clean up
    else if !shouldUseRAMDisk && currentlyUsingRAMDisk {
      log.debug("RAM disk disabled in preferences, cleaning up")
      cleanup()
    }
    // If size changed, recreate
    else if shouldUseRAMDisk && currentSize != desiredSize {
      log.debug("RAM disk size changed from \(currentSize) MB to \(desiredSize) MB, recreating")
      cleanup()
      setup()
    }
  }

  @objc private func applicationWillTerminate(_ notification: Notification) {
    cleanup()
  }
}
