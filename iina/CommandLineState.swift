//
//  CommandLineState.swift
//  iina
//
//  Created by Matt Svoboda on 2025-04-23.
//

struct CommandLineState: Sendable {
  // TODO: refactor to use [MPVOptPair]
  let mpvArguments: [(String, String)]
  let filenames: [String]

  let isStdin: Bool
  let openSeparateWindows: Bool?
  let enterMusicMode: Bool
  let enterPIP: Bool
  let needsShufflePlaylist: Bool

  init?(_ tokens: ArraySlice<String>) {
    guard !tokens.isEmpty else { return nil }

    var mpvArguments: [(String, String)] = []
    var filenames: [String] = []
    var isStdin = false
    var openSeparateWindows: Bool? = nil
    var enterMusicMode = false
    var enterPIP = false
    var needsShufflePlaylist = false

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
          let (argName, argValue) = CommandLineState.parseDoubleDashedToken(token)
          if argName == MPVOption.PlaybackControl.shuffle {
            if argValue == Constants.String.mpvYes {
              needsShufflePlaylist = true
            } else if argValue == Constants.String.mpvNo {
              needsShufflePlaylist = false
            }
          }
          // Also add args, in case user is using 'no' to override a 'yes' from user options or other source
          mpvArguments.append((argName, argValue))
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

    self.mpvArguments = mpvArguments
    self.filenames = filenames
    self.isStdin = isStdin
    self.openSeparateWindows = openSeparateWindows
    self.enterMusicMode = enterMusicMode
    self.enterPIP = enterPIP
    self.needsShufflePlaylist = needsShufflePlaylist
  }

  // mpv args
  private static func parseDoubleDashedToken(_ token: String) -> (String, String) {
    let splitted = token.dropFirst(2).split(separator: "=", maxSplits: 1)
    var name = String(splitted[0])

    if name.hasPrefix("mpv-") {
      name = String(name.dropFirst(4))
    }

    if splitted.count <= 1 {
      if name.hasPrefix("no-") {
        let optName = String(name.dropFirst(3))
        return (optName, Constants.String.mpvNo)
      } else {
        return (name, Constants.String.mpvYes)
      }
    } else {
      return (name, String(splitted[1]))
    }
  }

  func applySpecialModeToLastPlayer(_ lastPlayer: PlayerCore) {
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
