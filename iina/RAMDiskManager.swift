//
//  RAMDiskManager.swift
//  iina
//
//  Created by IINA on 2025-03-27.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Manages creation and mounting of RAM disks for temporary file storage using APFS.
///
/// Generated via Claude Sonnet 4.5.
final class RAMDiskManager {

  enum RAMDiskError: Error {
    case creationFailed(String)
    case mountFailed(String)
    case unmountFailed(String)
    case invalidSize
  }

  struct RAMDisk {
    let devicePath: String
    let mountPoint: URL
    let sizeInMB: Int
  }

  private static let log = Logger.SimpleSubsystem(rawValue: "ramdisk")

  /// Creates and mounts a RAM disk using APFS
  /// - Parameters:
  ///   - sizeInMB: Size of the RAM disk in megabytes (minimum 32 MB for APFS)
  ///   - volumeName: Name for the volume (optional, defaults to "IINATemp")
  /// - Returns: RAMDisk info containing device path and mount point
  static func createRAMDisk(sizeInMB: Int, volumeName: String = "IINATemp") throws -> RAMDisk {
    guard sizeInMB >= 32 else {
      throw RAMDiskError.invalidSize
    }

    log.debug("Creating \(sizeInMB) MB RAM disk with APFS, name: \(volumeName.quoted)")

    // Calculate number of 512-byte sectors
    let sectors = sizeInMB * 2048

    // Create the RAM disk using hdiutil
    let createProcess = Process()
    createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    createProcess.arguments = ["attach", "-nomount", "ram://\(sectors)"]

    let createPipe = Pipe()
    let errorPipe = Pipe()
    createProcess.standardOutput = createPipe
    createProcess.standardError = errorPipe

    try createProcess.run()
    createProcess.waitUntilExit()

    guard createProcess.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw RAMDiskError.creationFailed("hdiutil attach failed: \(errorMessage)")
    }

    let createData = createPipe.fileHandleForReading.readDataToEndOfFile()
    guard let devicePath = String(data: createData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw RAMDiskError.creationFailed("Failed to parse device path")
    }

    log.debug("Created RAM disk device: \(devicePath.quoted)")

    // Format the RAM disk with APFS (Case-sensitive for better performance)
    let formatProcess = Process()
    formatProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    // Use "APFS" for case-insensitive or "Case-sensitive APFS" for case-sensitive
    formatProcess.arguments = ["erasevolume", "APFS", volumeName, devicePath]

    let formatPipe = Pipe()
    let formatErrorPipe = Pipe()
    formatProcess.standardOutput = formatPipe
    formatProcess.standardError = formatErrorPipe

    try formatProcess.run()
    formatProcess.waitUntilExit()

    guard formatProcess.terminationStatus == 0 else {
      let errorData = formatErrorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      // Try to detach the device since formatting failed
      _ = try? unmountRAMDisk(devicePath: devicePath)
      throw RAMDiskError.mountFailed("diskutil erasevolume failed: \(errorMessage)")
    }

    // The mount point will be /Volumes/<volumeName>
    let mountPoint = URL(fileURLWithPath: "/Volumes/\(volumeName)")

    // Verify the mount point exists
    guard FileManager.default.fileExists(atPath: mountPoint.path) else {
      _ = try? unmountRAMDisk(devicePath: devicePath)
      throw RAMDiskError.mountFailed("Mount point does not exist at \(mountPoint.path)")
    }

    log.debug("Successfully mounted RAM disk at \(mountPoint.path.quoted)")

    return RAMDisk(devicePath: devicePath, mountPoint: mountPoint, sizeInMB: sizeInMB)
  }

  /// Unmounts and removes a RAM disk
  /// - Parameter devicePath: The device path (e.g., "/dev/disk4")
  static func unmountRAMDisk(devicePath: String) throws {
    log.debug("Unmounting RAM disk: \(devicePath.quoted)")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["detach", devicePath, "-force"]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw RAMDiskError.unmountFailed("hdiutil detach failed: \(errorMessage)")
    }

    log.debug("Successfully unmounted RAM disk: \(devicePath.quoted)")
  }

  /// Unmounts a RAM disk using its mount point
  /// - Parameter mountPoint: The mount point URL
  static func unmountRAMDisk(mountPoint: URL) throws {
    log.debug("Finding device for mount point: \(mountPoint.path.quoted)")

    // Find the device path for this mount point
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["info", mountPoint.path]

    let pipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = pipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
      throw RAMDiskError.unmountFailed("Could not find device for mount point: \(errorMessage)")
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      throw RAMDiskError.unmountFailed("Failed to parse diskutil output")
    }

    // Parse device path from diskutil output
    let lines = output.components(separatedBy: .newlines)
    guard let deviceLine = lines.first(where: { $0.contains("Device Node:") }),
          let devicePath = deviceLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) else {
      throw RAMDiskError.unmountFailed("Could not parse device path from diskutil output")
    }

    try unmountRAMDisk(devicePath: devicePath)
  }
}
