//
//  CommandLineState.swift
//  iina
//
//  Created by Matt Svoboda on 2025-04-23.
//

class CommandLineState {
  var isStdin = false
  var openSeparateWindows = false
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var filenames: [String] = []

  init?(_ arguments: ArraySlice<String>) {
    guard !arguments.isEmpty else { return nil }

    var dropNextArg = false
    for arg in arguments {
      if dropNextArg {
        Logger.log.verbose{"Ignoring arg: \(arg)"}
        continue
      } else if arg == "-" {
        // single '-'
        isStdin = true
      } else if arg == "-w" {
        // Alternate form of --separate-windows
        openSeparateWindows = true
      } else if arg == "--" {
        // ignore
        continue
      } else if arg.hasPrefix("--") {
        parseDoubleDashedArg(arg)
      } else if arg.hasPrefix("-") {
        // MacOS runtime arg names are prefixed with a single dash & a space to separate name from value.
        /// Example: `-NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints YES`
        Logger.log.verbose{"Ignoring arg: \(arg)"}
        dropNextArg = true
      } else {
        // assume arg with no starting dashes is a filename
        filenames.append(arg)
      }
    }

    Logger.log.debug{"Parsed IINA CLI args: stdin=\(isStdin.yn) separateWindows=\(openSeparateWindows.yn), musicMode=\(enterMusicMode.yn) pip=\(enterPIP.yn). Filenames from arguments: \(filenames.map{$0.pii})"}
    Logger.log.debug{"Derived mpv properties from args: \(mpvArguments)"}

    guard !filenames.isEmpty || isStdin else {
      print("This binary is not intended for being used as a command line tool. Please use the bundled iina-cli.")
      print("Please ignore this message if you are running in a debug environment.")
      return nil
    }
  }

  private func parseDoubleDashedArg(_ arg: String) {
    let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 1)
    let name = String(splitted[0])
    if name.hasPrefix("mpv-") {
      // mpv args
      let strippedName = String(name.dropFirst(4))
      if strippedName == "-" {
        Logger.log.debug{"Found single-dash arg; setting isStdin=YES"}
        isStdin = true
      } else if splitted.count <= 1 {
        if strippedName.hasPrefix("no-") {
          let optName = String(strippedName.dropFirst(3))
          mpvArguments.append((optName, Constants.String.mpvNo))
        } else {
          mpvArguments.append((strippedName, Constants.String.mpvYes))
        }
      } else {
        mpvArguments.append((strippedName, String(splitted[1])))
      }
    } else {
      // Check for IINA args. If an arg is not recognized, assume it is an mpv arg.
      // (The names here should match the "Usage" message in main.swift)
      switch name {
      case "stdin":
        isStdin = true
      case "separate-windows":
        openSeparateWindows = true
      case "music-mode":
        enterMusicMode = true
      case "pip":
        enterPIP = true
      default:
        if splitted.count <= 1 {
          if name.hasPrefix("no-") {
            let optName = String(name.dropFirst(3))
            mpvArguments.append((optName, Constants.String.mpvNo))
          } else {
            mpvArguments.append((name, Constants.String.mpvYes))
          }
        } else {
          mpvArguments.append((name, String(splitted[1])))
        }
      }
    }
  }

  private func parseSingleDashedArg(_ arg: String) {
    if arg == "-" {
      // single '-'
      isStdin = true
    }
    // else ignore all single-dashed args
  }

  func startFromCommandLine() {
    var lastPlayerCore: PlayerCore? = nil
    if isStdin {
      lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
      lastPlayerCore?.openURLString("-")
    } else {
      let validFileURLs: [URL] = filenames.compactMap { filename in
        if Regex.url.matches(filename) {
          return URL(string: filename.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? filename)
        } else {
          return FileManager.default.fileExists(atPath: filename) ? URL(fileURLWithPath: filename) : nil
        }
      }
      guard !validFileURLs.isEmpty else {
        Logger.log.error("No valid file URLs provided via command line! Nothing to do")
        return
      }

      if openSeparateWindows {
        Logger.log.verbose{"Opening separate windows for \(validFileURLs.count) URLs"}
        for url in validFileURLs {
          lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
          lastPlayerCore?.openURL(url)
        }
      } else {
        lastPlayerCore = getOrCreatePlayerWithCmdLineArgs()
        lastPlayerCore?.openURLs(validFileURLs)
      }
    }

    if let pc = lastPlayerCore {
      if enterMusicMode {
        Logger.log.verbose("Entering music mode as specified via command line")
        if enterPIP {
          // PiP is not supported in music mode. Combining these options is not permitted and is
          // rejected by iina-cli. The IINA executable must have been invoked directly with
          // arguments.
          Logger.log.error("Cannot specify both --music-mode and --pip")
          // Command line usage error.
          exit(EX_USAGE)
        }
        pc.enterMusicMode()
      } else if enterPIP {
        Logger.log.verbose("Entering PIP as specified via command line")
        pc.windowController.enterPIP()
      }
    }
  }

  func getOrCreatePlayerWithCmdLineArgs() -> PlayerCore {
    let playerCore = PlayerManager.shared.getIdleOrCreateNew()
    Logger.log.debug{"Setting mpv properties from arguments: \(mpvArguments)"}
    var cmdLineArgs: [(String, String)] = []
    for argPair in mpvArguments {
      if argPair.0 == MPVOption.PlaybackControl.shuffle && argPair.1 == Constants.String.mpvYes {
        // Special handling for this one
        Logger.log.debug{"Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist"}
        playerCore.addShufflePlaylistHook()
      } else {
        cmdLineArgs.append(argPair)
      }
    }

    if Logger.isDebugEnabled {
      for cmdLineArgPair in cmdLineArgs {
        if playerCore.userOptions.contains(where: { $0.0 == cmdLineArgPair.0 }) {
          playerCore.log.debug{"Command-line mpv arg has the same name as user option and may override it: \(cmdLineArgPair.0)=\(cmdLineArgPair.1)"}
        }
      }
    }
    playerCore.userOptions.append(contentsOf: cmdLineArgs)
    return playerCore
  }

}
