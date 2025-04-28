//
//  main.swift
//  iina-cli
//
//  Created by Collider LI on 6/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

let executableName = "IINA Advance"

// This is the path to this executable (iina-cli)
guard let execURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
  print("Cannot get executable path.")
  exit(1)
}

let iinaURL = execURL.deletingLastPathComponent().appendingPathComponent(executableName)

guard FileManager.default.fileExists(atPath: iinaURL.path) else {
  print("Cannot find \(executableName) binary. This command line tool only works in \(executableName).app bundle.")
  exit(1)
}

// Check arguments

var userArgs = Array(ProcessInfo.processInfo.arguments.dropFirst())

if userArgs.contains(where: { $0 == "--help" || $0 == "-h" }) {
  print(
    """
    Usage: iina-cli [arguments] [files] [-- mpv_option [...]]

    Arguments:
    --mpv-*:
            All mpv options are supported here, except those starting with "--no-".
            Example: --mpv-volume=20 --mpv-resume-playback=no
    --separate-windows | -w:
            Open all files in separate windows.
    --stdin, --no-stdin:
            You may also pipe to stdin directly. Sometimes iina-cli can detect whether
            stdin has file, but sometimes not. Therefore it's recommended to always
            supply --stdin when piping to iina, and --no-stdin when you are not intend
            to use stdin.
    --keep-running:
            Normally iina-cli launches IINA and quits immediately. Supply this option
            if you would like to keep it running until the main application exits.
    --music-mode:
            Enter music mode after opening the media.
    --pip:
            Enter Picture-in-Picture after opening the media. Music mode does not
            support Picture-in-Picture.
    --help | -h:
            Print this message.

    mpv Option:
    Raw mpv options without --mpv- prefix. All mpv options are supported here.
    Example: --volume=20 --no-resume-playback
    """)
  exit(0)
}

if userArgs.contains("--music-mode"), userArgs.contains("--pip") {
  // Music mode does not support Picture-in-Picture. Combining these options is not permitted.
  print("Cannot specify both --music-mode and --pip")
  // Command line usage error.
  exit(EX_USAGE)
}

let currentDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
var keepRunning = false
var isStdin = false
var userSpecifiedStdin = false
var passedDoubleDash = false

userArgs = userArgs.compactMap { arg in
  switch arg {
  case "--":
    passedDoubleDash = true
    return nil
  case "--keep-running":
    keepRunning = true
    return nil
  case "--stdin":
    isStdin = true
    userSpecifiedStdin = true
  case "--stdin=no", "--no-stdin",    // check for all forms
    "--terminal=no", "--no-terminal": // `--terminal=no` disables any use of the terminal and stdin/stdout/stderr.
    isStdin = false
    userSpecifiedStdin = true
  default:
    if passedDoubleDash, arg.hasPrefix("--") {
      return "--mpv-\(arg.dropFirst(2))"
    } else if !arg.hasPrefix("-"), !Regex.url.matches(arg),
       let encodedFilePath = arg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
       let fileURL = URL(string: encodedFilePath, relativeTo: currentDirURL),
       FileManager.default.fileExists(atPath: fileURL.path) {
      // Change relative file paths to absolute(?)
      return fileURL.path
    }
  }

  return arg
}

// Configure stdin

if !userSpecifiedStdin {
  guard let stdin = InputStream(fileAtPath: "/dev/stdin") else {
    print("Cannot open stdin.")
    exit(1)
  }
  stdin.open()
  isStdin = stdin.hasBytesAvailable
  if isStdin {
    print("Found stdin data, no user hint; adding --stdin")
    userArgs.insert("--stdin", at: 0)
  }
}

// Run executable as a separate process. Not sure if/why this is strictly necessary...
let task = Process()
task.executableURL = iinaURL
task.arguments = userArgs

if isStdin {
  task.standardInput = FileHandle.standardInput
  task.standardOutput = FileHandle.standardOutput
} else {
  task.standardOutput = nil
  task.standardError = nil
}

func terminateTaskIfRunning() {
  if task.isRunning {
    task.terminate()
  }
}

[SIGTERM, SIGINT].forEach { sig in
  signal(sig) { _ in
    terminateTaskIfRunning()
    exit(1)
  }
}

atexit {
  if isStdin || keepRunning {
    terminateTaskIfRunning()
  }
}

task.launch()

if isStdin || keepRunning {
  task.waitUntilExit()
}
