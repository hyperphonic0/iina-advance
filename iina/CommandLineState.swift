//
//  CommandLineState.swift
//  iina
//
//  Created by Matt Svoboda on 2025-04-23.
//

class CommandLineState {
  var isStdin = false
  var openSeparateWindows: Bool? = nil
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var filenames: [String] = []

  init?(_ tokens: ArraySlice<String>) {
    guard !tokens.isEmpty else { return nil }
    var droppedTokens = 0

    var dropNextToken = false
    for token in tokens {
      if dropNextToken {
        // Second token in pair to ignore
        dropNextToken = false
        droppedTokens += 1
        continue
      }

      // Check for IINA args
      switch token {
      case "-", "--stdin", "--mpv--":
        isStdin = true
      case "-w", "--separate-windows":
        openSeparateWindows = true
      case "--separate-windows=no", "--no-separate-windows":
        openSeparateWindows = false
      case "--music-mode":
        enterMusicMode = true
      case "--pip":
        enterPIP = true
      case "--":
        // ignore
        droppedTokens += 1
        continue
      default:
        if token.hasPrefix("--") {
          // Assume all other double-dashed tokens are mpv args.
          parseDoubleDashedToken(token)
        } else if token.hasPrefix("-") {
          // MacOS runtime arg names are prefixed with a single dash & a space to separate name from value.
          /// Example: `-NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints YES`
          /// Ignore this token, and also the next one.
          dropNextToken = true
          droppedTokens += 1
        } else {
          // assume token with no starting dashes is a filename
          filenames.append(token)
        }
      }
    }

    if tokens.count - droppedTokens == 0 {
      // Does not qualify as a CLI launch
      return nil
    }
  }

  // mpv args
  private func parseDoubleDashedToken(_ token: String) {
    let splitted = token.dropFirst(2).split(separator: "=", maxSplits: 1)
    var name = String(splitted[0])

    if name.hasPrefix("mpv-") {
      name = String(name.dropFirst(4))
    }

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

  func applyCommandLineArgs(to playerCore: PlayerCore) {
    playerCore.log.debug{"Setting mpv properties from arguments: \(mpvArguments)"}
    var cmdLineArgs: [(String, String)] = []
    for argPair in mpvArguments {
      if argPair.0 == MPVOption.PlaybackControl.shuffle && argPair.1 == Constants.String.mpvYes {
        // Special handling for this one
        playerCore.log.debug{"Found \"shuffle\" request in command-line args. Adding mpv hook to shuffle playlist"}
        playerCore.addShufflePlaylistHook()
      } else {
        cmdLineArgs.append(argPair)
      }
    }

    if playerCore.log.isDebugEnabled {
      for cmdLineArgPair in cmdLineArgs {
        if playerCore.userOptions.contains(where: { $0.0 == cmdLineArgPair.0 }) {
          playerCore.log.debug{"CLI arg has same name as a prev option & may override it: \(cmdLineArgPair.0)=\(cmdLineArgPair.1)"}
        }
      }
    }
    playerCore.userOptions.append(contentsOf: cmdLineArgs)
  }

  func applySpecialOptionsToLastPlayer(_ lastPlayer: PlayerCore) {
    if enterMusicMode {
      DispatchQueue.main.async {
        lastPlayer.log.verbose("Player will start in music mode as specified via command line")
        lastPlayer.startInMusicModeRequested = true
      }

    } else if enterPIP {
      DispatchQueue.main.async {
        lastPlayer.log.verbose("Entering PIP as specified via command line")
        lastPlayer.pwc.enterPIP()
      }
    }
  }

}
