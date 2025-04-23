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
        continue
      } else if arg == "-" {
        // single '-'
        isStdin = true
      } else if arg == "--" {
        // ignore
        continue
      } else if arg.hasPrefix("--") {
        parseDoubleDashedArg(arg)
      } else if arg.hasPrefix("-") {
        Logger.log.verbose{"Ignoring arg: \(arg)"}
        dropNextArg = true
      } else {
        // assume arg with no starting dashes is a filename
        filenames.append(arg)
      }
    }

    Logger.log.debug{"Parsed command-line args: isStdin=\(isStdin.yn) separateWindows=\(openSeparateWindows.yn), enterMusicMode=\(enterMusicMode.yn), enterPIP=\(enterPIP.yn)"}
    Logger.log.debug{"Filenames from arguments: \(filenames.map{$0.pii.quoted})"}
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
        isStdin = true
      } else if splitted.count <= 1 {
        mpvArguments.append((strippedName, "yes"))
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
          mpvArguments.append((name, "yes"))
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
    Logger.log("Setting mpv properties from arguments: \(mpvArguments)")
    for argPair in mpvArguments {
      if argPair.0 == "shuffle" && argPair.1 == "yes" {
        // Special handling for this one
        Logger.log("Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist")
        playerCore.addShufflePlaylistHook()
      } else {
        playerCore.mpv.setString(argPair.0, argPair.1)
      }
    }
    return playerCore
  }

}
