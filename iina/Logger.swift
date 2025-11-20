//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

/// The IINA Logger.
///
/// Logging to a file is controlled by a preference in `Advanced` preferences and by default is disabled.
///
/// The logger takes a two phase approach to handling errors. During initialization of the logger any failure while creating the log directory,
/// creating the log file and opening the file for writing, is treated as a fatal error. The user will be shown an alert and when the user
/// dismisses the alert the application will terminate. Once the logger is successfully initialized errors involving the file are only printed to
/// the console to avoid disrupting playback.
/// - Important: The `createDirIfNotExist` method in `Utilities` **must not** be used by the logger. If an error occurs
///     that method will attempt to report it using the logger. If the logger is still being initialized this will result in a crash. For that reason
///     the logger uses its own similar method.
class Logger: NSObject {

  // MARK: - Level

  enum Level: Int, Comparable, CustomStringConvertible {
    static func < (lhs: Level, rhs: Level) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    /// Don't really care about race conditions here; would rather have faster performance
    nonisolated(unsafe) static var preferred: Level = .error

    case trace = -1
    case verbose
    case debug
    case warning
    case error

    var description: String {
      switch self {
      case .trace: return "T"
      case .verbose: return "V"
      case .debug: return "D"
      case .warning: return "W"
      case .error: return "E"
      }
    }
  }

  // MARK: Vars & More!

  static let general = Logger.makeSubsystem("iina")
  static let input = Logger.makeSubsystem("input")
  static let restore = Logger.makeSubsystem("restore")
  private static let loggerSubsystem = Logger.makeSubsystem("logger")

  /// `playerID` → `Subsystem`
  nonisolated(unsafe) fileprivate static var playerLogs: [String: any Subsystem] = [:]

  /// Default Logger subsystem
  static let log = Logger.general

  /// If true, strings which are indicated to contain personally identifiable information (PII) are replaced with a
  /// unique PII token (see `piiFormat` below) when they are logged to iina.log.
  static let enablePiiMasking: Bool = Preference.bool(for: .enablePiiMaskingInLog)

  /// Is ignored unless `Preference.enablePiiMaskingInLog` is true. If `writeUnmaskedPiiToFile` is true, each PII token and its value is written to
  /// a separate file which can be used to look up the PII tokens from the log; if it is false, then the values are not logged.
  static let writeUnmaskedPiiToFile = true

  /// Try to prevent false positives during search & replace of PII, by not allowing matches which are too short to
  /// be meaningful.
  fileprivate static let minMatchLength = 4

  fileprivate static let piiFormat: String = "{pii%@}"
  fileprivate static let piiFileVersion: Int = 0
  fileprivate static let piiFirstLineFormat = "# IINA_PII \(piiFileVersion) \(sessionDirName)\n"

  /// This should be accessed only while locked via `fsLock`.
  nonisolated(unsafe) fileprivate static var piiDict: [String: Int] = [:]

  /// Must coordinate writing & closing of log files to avoid simultaneous writing, & writing to a closed file handle.
  private static let fsLock = Lock()

  private static let structuresLock = Lock()
  nonisolated(unsafe) private static var logsForLogWindow: [Logger.Log] = []
  nonisolated(unsafe) private static var subsystems: [any Subsystem] = []

  static func subsystem(forPlayerID playerID: String) -> any Subsystem {
    structuresLock.withLock {
      if let subsystem = playerLogs[playerID] {
        return subsystem
      }
      let subsystem = SimpleSubsystem(rawValue: String(format: Constants.String.iinaPlayerCategoryFmt, playerID))

      playerLogs[playerID] = subsystem
      return subsystem
    }
  }

  /// Global flag for all logs.
  ///
  /// If running in DEBUG mode, this flag is ignored, and logging is always enabled.
  /// If not running in DEBUG, and this flag is `false`, then all logging is disabled.
  /// Don't really care about race conditions here; would rather have faster performance.
  static nonisolated(unsafe) private(set) var enabled: Bool = false

  /// Updates global enablement flag
  static func updateEnablement() {
    structuresLock.withLock {
      _updateEnablement()
    }

    // In case this was previously disabled, mask library URL in subsequent logging
    _ = getOrCreatePII(for: libraryDirectory.path)
  }

  /// Unlocked version.
  private static func _updateEnablement() {
    let isInteractiveLaunch = AppDelegate.isInteractiveLaunch
    if !isInteractiveLaunch && !Preference.bool(for: .logNonInteractiveLaunches) {
      Logger.log("Logging disabled for non-interactive launch")
      enabled = false
      return
    }
    let newValue = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .enableLogging)
    if enabled && !newValue {
      Logger.log("Logging disabled")
      enabled = newValue
    } else if !enabled && newValue {
      enabled = newValue
      Logger.log("Logging enabled")
    }

    let newLogLevel = Level(rawValue: Preference.integer(for: .logLevel).clamped(to: Level.trace.rawValue...Level.error.rawValue))!
    if Level.preferred != newLogLevel {
      Logger.log("Log level updated to \(newLogLevel)")
    }
    Level.preferred = newLogLevel
  }

  static func isEnabled(_ level: Logger.Level) -> Bool {
    enabled && (Logger.Level.preferred <= level)
  }

  static var isTraceEnabled: Bool   { Logger.isEnabled(.trace) }
  static var isVerboseEnabled: Bool {  Logger.isEnabled(.verbose) }
  static var isDebugEnabled: Bool   { Logger.isEnabled(.debug) }
  static var isWarningEnabled: Bool   { Logger.isEnabled(.warning) }
  static var isErrorEnabled: Bool   { Logger.isEnabled(.error) }

  static let stdoutLogLevel = Level(rawValue: Preference.integer(for: .stdoutLogLevel).clamped(to: Level.trace.rawValue...Level.error.rawValue))!

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  static func initLogging() {
    // Call unlocked version. This should be called at app start, on the main thread, and we haven't done any logging yet, so it should be safe.
    // Moreover we are avoiding a deadlock as all the nestled static stuff gets triggered to initialize.
    _updateEnablement()

    // In case this was previously disabled, mask library URL in subsequent logging
    _ = getOrCreatePII(for: libraryDirectory.path)
  }

  // MARK: - Log Class

  class Log: NSObject {
    @objc dynamic let subsystem: String
    @objc dynamic let level: Int
    @objc dynamic let message: String
    @objc dynamic let date: String
    let logString: String

    init(subsystem: String, level: Int, message: String, date: String, logString: String) {
      self.subsystem = subsystem
      self.level = level
      self.message = message
      self.date = date
      self.logString = logString
    }

    override var description: String { logString }
  }

  // MARK: - Subsystem

  // TODO: this is kludgey! Investigate using a thread local var when time permits
  struct DecoratedSubsystem: Subsystem {
    typealias RawValue = String
    var rawValue: String { originalSS.rawValue }

    let preamble: String
    let originalSS: any Subsystem

    var isTraceEnabled: Bool { Logger.isTraceEnabled }
    var isVerboseEnabled: Bool { Logger.isVerboseEnabled }
    var isDebugEnabled: Bool { Logger.isDebugEnabled}
    var isErrorEnabled: Bool { Logger.isErrorEnabled }

    /// Do not use this. Use the constructor which includes preamble
    init?(rawValue: String) {
      Logger.loggerSubsystem.fatalError("init(rawValue:) has not been implemented")
    }

    init(original: any Subsystem, preamble: String) {
      self.preamble = preamble
      originalSS = original
    }

    func trace(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isTraceEnabled else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: .trace)
    }

    func verbose(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isVerboseEnabled else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: .verbose)
    }

    func debug(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isDebugEnabled else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: .debug)
    }

    func warn(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isWarningEnabled else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: .warning)
    }

    func error(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isErrorEnabled else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: .error)
    }

    func fatalError(_ rawMessage: @autoclosure () -> String) -> Never {
      originalSS.fatalError("\(preamble) \(rawMessage())")
    }

    func log(_ rawMessage: @autoclosure () -> String, level: Level = .debug) {
      guard Logger.isEnabled(level) else { return }
      originalSS.log("\(preamble) \(rawMessage())", level: level)
    }

    func errorDebugAlert(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isErrorEnabled else { return }
      originalSS.errorDebugAlert("\(preamble) \(rawMessage())")
    }
  }

  protocol Subsystem: RawRepresentable<String>, Sendable {
    var isTraceEnabled: Bool { get }
    var isVerboseEnabled: Bool { get }
    var isDebugEnabled: Bool { get }
    var isErrorEnabled: Bool { get }

    func trace(_ rawMessage: @autoclosure () -> String)
    func verbose(_ rawMessage: @autoclosure () -> String)
    func debug(_ rawMessage: @autoclosure () -> String)
    func warn(_ rawMessage: @autoclosure () -> String)
    func error(_ rawMessage: @autoclosure () -> String)
    func fatalError(_ rawMessage: @autoclosure () -> String) -> Never
    func log(_ rawMessage: @autoclosure () -> String, level: Level)
    func errorDebugAlert(_ msg: @autoclosure () -> String)

    // MARK: - Closure arg variants (DEPRECATED!)
    func trace(_ msgFunc: () -> String)

  }  // end protocol Subsystem

  struct SimpleSubsystem: Subsystem {
    let rawValue: String

    var isTraceEnabled: Bool { Logger.isTraceEnabled }
    var isVerboseEnabled: Bool { Logger.isVerboseEnabled }
    var isDebugEnabled: Bool { Logger.isDebugEnabled}
    var isErrorEnabled: Bool { Logger.isErrorEnabled }

    init(rawValue: String) {
      self.rawValue = rawValue
    }

    func trace(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isTraceEnabled else { return }
      Logger.log(rawMessage(), level: .trace, subsystem: self)
    }

    func verbose(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isVerboseEnabled else { return }
      Logger.log(rawMessage(), level: .verbose, subsystem: self)
    }

    func debug(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isDebugEnabled else { return }
      Logger.log(rawMessage(), level: .debug, subsystem: self)
    }

    func warn(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isWarningEnabled else { return }
      Logger.log(rawMessage(), level: .warning, subsystem: self)
    }

    func error(_ rawMessage: @autoclosure () -> String) {
      guard Logger.isErrorEnabled else { return }
      Logger.log(rawMessage(), level: .error, subsystem: self)
    }

    func fatalError(_ rawMessage: @autoclosure () -> String) -> Never {
      Logger.fatal(rawMessage())
    }

    func log(_ rawMessage: @autoclosure () -> String, level: Level = .debug) {
      guard Logger.isEnabled(level) else { return }
      Logger.log(rawMessage(), level: level, subsystem: self)
    }

    // MARK: - Log Functions

    func errorDebugAlert(_ msg: @autoclosure () -> String) {
      guard Logger.isErrorEnabled else { return }
      let rawMessage = msg()
#if DEBUG
      DispatchQueue.main.async {
        Utility.showAlert(rawMessage, style: .critical, logAlert: false)
      }
#endif
      Logger.log(rawMessage, level: .error, subsystem: self)
    }

  }  // end class Subsystem

  static func makeSubsystem(_ player: PlayerCore, fmt: String) -> any Subsystem {
    return makeSubsystem(String(format: fmt, player.label))
  }

  static func makeSubsystem(_ rawValue: String) -> any Subsystem {
    structuresLock.withLock {
      for (index, subsystem) in subsystems.enumerated() {
        // The first subsystem will always be "iina"
        if index == 0 { continue }
        if rawValue < subsystem.rawValue {
          let newSubsystem = SimpleSubsystem(rawValue: rawValue)
          subsystems.insert(newSubsystem, at: index)
          return newSubsystem
        } else if rawValue == subsystem.rawValue {
          return subsystem
        }
      }
      let newSubsystem = SimpleSubsystem(rawValue: rawValue)
      subsystems.append(newSubsystem)
      return newSubsystem
    }
  }

  static func getSubsystems() -> [any Subsystem] {
    structuresLock.withLock {
      subsystems
    }
  }

  static func addPreamble(_ preamble: String, toSubsystem subsystem: any Subsystem) -> any Subsystem {
    return DecoratedSubsystem(original: subsystem, preamble: preamble)
  }

  // MARK: - PII Masking

  static func getOrCreatePII(for privateString: String) -> String {
    guard enabled && enablePiiMasking && !privateString.isEmpty && privateString.count >= minMatchLength else {
      return privateString
    }

    var piiToken: String = ""
    fsLock.withLock {
      if let piiID = piiDict[privateString] {
        // Reoccurrence
        piiToken = formatPIIToken(piiID)
      } else {
        // New occurrence
        let piiID = piiDict.count
        piiDict[privateString] = piiID
        let escapedString = privateString.replacingOccurrences(of: "\n", with: "\\n")
        piiToken = formatPIIToken(piiID)

        if writeUnmaskedPiiToFile {
          if piiID == 0 {
            if let data = piiFirstLineFormat.data(using: .utf8) {
              writeToFile(piiFileHandle, data)
            } else {
              print(formatMessage("Could not encode pii header for writing!", .error, Logger.loggerSubsystem, false))
            }
          }
          let line = "\(piiToken)=\(escapedString)\n"
          if let data = line.data(using: .utf8) {
            writeToFile(piiFileHandle, data)
          } else {
            print(formatMessage("Could not encode pii token (\(piiToken)) for writing!", .error, Logger.loggerSubsystem, false))
          }
        }
      }
    }
    return piiToken
  }

  fileprivate static func formatPIIToken(_ piiID: Int) -> String {
    let paddedInt = piiID < 10 ? "0\(piiID)" : "\(piiID)"
    return String(format: piiFormat, paddedInt)
  }

  static private func maskAnyPII(_ rawMessage: String) -> String {
    guard enablePiiMasking else { return rawMessage }

    var maskedMessage: String = rawMessage
    fsLock.withLock {
      for (piiString, piiID) in piiDict {
        maskedMessage = maskedMessage.replacingOccurrences(of: piiString, with: formatPIIToken(piiID))
      }
    }
    return maskedMessage
  }

  // MARK: - File System

  fileprivate static let sessionDirName: String = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let timeString  = formatter.string(from: Date())
    let launchID = UIState.shared.currentLaunchID
    return "\(timeString)_L\(launchID)"
  }()

  static let libraryDirectory: URL = {
    let libraryURLs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
    guard let libraryURL = libraryURLs.first else {
      fatalDuringInit("Cannot get path to Logs directory: \(libraryURLs)")
    }
    return libraryURL
  }()

  static let logDirectory: URL = {
    let logsUrl = libraryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let bundleID = Bundle.main.bundleIdentifier!
    let appLogsUrl = logsUrl.appendingPathComponent(bundleID, isDirectory: true)

    // MUST NOT use the similar method in Utilities as that method uses Logger methods. Logger
    // methods must not ever be called while the logger is still initializing.
    createDirIfNotExist(url: logsUrl)

    let sessionDir = appLogsUrl.appendingPathComponent(sessionDirName, isDirectory: true)

    // MUST NOT use the similar method in Utilities. See above for reason.
    createDirIfNotExist(url: sessionDir)
    return sessionDir
  }()

  private static let logFile: URL = logDirectory.appendingPathComponent("iina.log")
  // File for personally identifiable information lookup
  private static let piiFile: URL = logDirectory.appendingPathComponent("pii.txt")

  nonisolated(unsafe) private static var logFileHandle: FileHandle? = {
    FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil)
    do {
      return try FileHandle(forWritingTo: logFile)
    } catch  {
      fatalDuringInit("Cannot open log file \(logFile.path) for writing: \(error.localizedDescription)")
    }
  }()

  nonisolated(unsafe) private static var piiFileHandle: FileHandle? = {
    FileManager.default.createFile(atPath: piiFile.path, contents: nil, attributes: nil)
    do {
      return try FileHandle(forWritingTo: piiFile)
    } catch  {
      fatalDuringInit("Cannot open log file \(piiFile.path) for writing: \(error.localizedDescription)")
    }
  }()

  /// Closes the log file, if logging is enabled,
  /// - Important: Currently IINA does not coordinate threads during termination. This results in a race condition as to whether
  ///     a thread will attempt to log a message after the log file has been closed or not.  Previously this was triggering crashes due
  ///     to writing to a closed file handle. The logger now uses a lock to coordinate closing of the log file. If a log message is logged
  ///     after the log file is closed it will only be logged to the console.
  static func closeLogFiles() {
    guard enabled else { return }
    // Lock to avoid closing the log file while another thread is writing to it.
    fsLock.withLock {
      close(logFile, logFileHandle)
      /// Do not access `piiFileHandle` unless needed - will throw unnecessary error on app exit if log dir was deleted after launch
      /// (`logFileHandle` will not throw error becasue it was already opened?)
      if !piiDict.isEmpty {
        close(piiFile, piiFileHandle)
      }
    }
  }

  private static func close(_ fileURL: URL, _ fileHandle: FileHandle?) {
    guard let fileHandle = fileHandle else { return }
    do {
      // The deprecated method is used instead of the new close method that throws swift exceptions
      // because testing with the new write method found it failed to convert all objective-c
      // exceptions to swift exceptions.
      try ObjcUtils.catchException { fileHandle.closeFile() }
    } catch {
      // Unusual, but could happen if closing causes a buffer to be flushed to a full disk.
      print(formatMessage("Cannot close log file \(fileURL.path): \(error.localizedDescription)",
                          .error, Logger.loggerSubsystem, true))
    }
  }

  /// Creates a directory at the specified URL along with any nonexistent parent directories.
  ///
  /// If the directory cannot be created then this method will treat the failure as a fatal error. The user will be shown an alert and when
  /// the user dismisses the alert the application will terminate.
  /// - Parameter url: A file URL that specifies the directory to create.
  /// - Important: This method is designed to be usable during logger initialization. The similar method found in `Utilities`
  ///     **must not** be used. If an error occurs that method will attempt to report it using the logger. As the logger is still being
  ///     initialized this will result in a crash.
  private static func createDirIfNotExist(url: URL) {
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalDuringInit("Cannot create directory \(url): \(error.localizedDescription)")
    }
  }

  private static func writeToFile(_ fileHandle: FileHandle?, _ data: Data) {
    // The logger may be called after it has been closed.
    guard let fileHandle = fileHandle else { return }
    do {
      // The deprecated write method is used instead of the replacement method that throws swift
      // exceptions because testing the new method with macOS 12.5.1 showed that method failed to
      // turn all objective-c exceptions into swift exceptions. The exception thrown for writing
      // to a closed channel was not picked up by the catch block.
      try ObjcUtils.catchException { fileHandle.write(data) }
    } catch {
      print(formatMessage("Cannot write to log file: \(error.localizedDescription)", .error,
                          Logger.loggerSubsystem, false))
    }
  }

  // MARK: - Message Formatting

  private static func formatMessage(_ message: String, _ level: Level, _ subsystem: any Subsystem,
                                    _ appendNewlineAtTheEnd: Bool, _ date: Date = Date()) -> String {
    let time = dateFormatter.string(from: date)
    return "\(time) |\(subsystem.rawValue) \(level.description)| \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
  }

  /// Log a message.
  ///
  /// Emit a message to the log file if logging is enabled and logging is configured to log messages at the given level.
  /// - Important: The message is passed as a closure instead of a `String` so that if the message includes string interpolations
  ///     the evaluation of the expressions and construction of the string can be delayed until it is known that the message will be
  ///     written to the log file and not discarded due to logging either being disabled or configured to not emit messages at the given
  ///     level. This method uses [autoclosure](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/closures/#Autoclosures) so that
  ///     callers do not to need to supply an explicit closure.
  /// - Parameters:
  ///   - message: A closure that when executed gives the message to log.
  ///   - level: The log level of the message.
  ///   - subsystem: The subsystem emitting this message.
  static func log(_ message: @autoclosure () -> String, level: Level = .debug,
                  subsystem: any Subsystem = Logger.general) {
    log(message, level: level, subsystem: subsystem)
  }

  /// Log a message.
  ///
  /// Emit a message to the log file if logging is enabled and logging is configured to log messages at the given level.
  /// - Important: The message is passed as a closure instead of a `String` so that if the message includes string interpolations
  ///     the evaluation of the expressions and construction of the string can be delayed until it is known that the message will be
  ///     written to the log file and not discarded due to logging either being disabled or configured to not emit messages at the given
  ///     level.
  /// - Note: This method is intended to only be called by the above `log` method and utility `log` methods used in some
  ///     classes to supply the subsystem associated with that class.
  /// - Parameters:
  ///   - message: A closure that when executed gives the message to log.
  ///   - level: The log level of the message.
  ///   - subsystem: The subsystem emitting this message.
  static func log(_ message: () -> String, level: Level = .debug, subsystem: any Subsystem = Logger.general) {
    #if !DEBUG
    guard enabled else { return }
    #endif

    // Now that we know the message will not be discarded, call the closure to construct the message
    // string to log.
    let message = maskAnyPII(message())

    // Record the log line for use in the Logs window...j/
    let date = Date()
    let string = formatMessage(message, level, subsystem, true, date)
    let log = Log(subsystem: subsystem.rawValue, level: level.rawValue, message: message, date: dateFormatter.string(from: date), logString: string)
    structuresLock.withLock {
      logsForLogWindow.append(log)
    }

#if DEBUG
    print(string, terminator: "")
#else
    if level >= stdoutLogLevel {
      print(string, terminator: "")
    }
#endif

    guard let data = string.data(using: .utf8) else {
      print(formatMessage("Cannot encode log string!", .error, Logger.loggerSubsystem, false))
      return
    }
    // Lock to prevent the log file from being closed by another thread while writing to it.
    fsLock.withLock() {
      writeToFile(logFileHandle, data)
    }
  }

  static func popNewestLinesForLogWindow() -> [Log] {
    structuresLock.withLock {
      let latestLogs = logsForLogWindow
      logsForLogWindow.removeAll()
      return latestLogs
    }
  }


  // MARK: - Failure

  static func ensure(_ condition: @autoclosure () -> Bool, _ errorMessage: String = "Assertion failed in \(#line):\(#file)", _ cleanup: () -> Void = {}) {
    guard condition() else {
      log(errorMessage, level: .error)
      showAlertAndExit(errorMessage, cleanup)
    }
  }

  static func fatal(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    log(message, level: .error)
    log(Thread.callStackSymbols.joined(separator: "\n"))
    showAlertAndExit(message, cleanup)
  }

  /// Reports a fatal error during logger initialization and stops execution.
  ///
  /// This method will print the given error message to the console and then show an alert to the user. When the user dismisses the
  /// alert this method will terminate the process with an exit code of one.
  /// - Parameter message: The fatal error to report.
  /// - Important: This method differs from the method `fatal` in that it is designed to be safe to call during logger initialization
  ///     and therefore intentionally avoids attempting to log the fatal error message.
  private static func fatalDuringInit(_ message: String) -> Never {
    print(formatMessage(message, .error, Logger.loggerSubsystem, true))
    showAlertAndExit(message)
  }

  private static func showAlertAndExit(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    // Ensure we are on the main thread so that we display the alert instead of crashing
    DispatchQueue.main.execOrSync {
      // Set logAlert to false to avoid recursion
      Utility.showAlert("fatal_error", arguments: [message], logAlert: false)
      cleanup()
      exit(1)
    }
    // execOrSync above will always call exit() synchronously, but need this anyway to keep compiler happy:
    exit(1)
  }
}
