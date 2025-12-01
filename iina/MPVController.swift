//
//  MPVController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore
import VideoToolbox

extension mpv_event_id: CustomStringConvertible {
  // Generated code from mpv is objc and does not have Swift's built-in enum name introspection.
  // We provide that here using mpv_event_name()
  public var description: String {
    get {
      String(cString: mpv_event_name(self))
    }
  }
}

extension mpv_event_end_file {
  // For help with debugging
  var reasonString: String {
    let reason = self.reason
    var reasonString: String
    switch reason {
    case MPV_END_FILE_REASON_EOF:
      reasonString = "EOF"
    case MPV_END_FILE_REASON_STOP:
      reasonString = "STOP"
    case MPV_END_FILE_REASON_QUIT:
      reasonString = "QUIT"
    case MPV_END_FILE_REASON_ERROR:
      reasonString = "ERROR"
    case MPV_END_FILE_REASON_REDIRECT:
      reasonString = "REDIRECT"
    default:
      reasonString = "???"
    }
    if reason == MPV_END_FILE_REASON_ERROR {
      let errStr = String(cString: mpv_error_string(error))
      reasonString += " \(error) (\(errStr))"
    }
    return reasonString
  }
}

/// Encapsulates the mpv handle for a single PlayerCore and its supporting functions.
///
/// To help make size more manageable, this class is broken up into multiple files grouped by functionality:
/// `MPVController.swift`: the class definition with init/deinit and various functions for options & property
/// handling.
///
/// See also:
/// - `MPV_Init.swift`: contains `mpvInit()` & its support functions, which call `mpv_create` & `mpv_initialize`,
///   and set initial mpv options.
/// - `MPV_EventHandling.swift`: calls `mpv_set_wakeup_callback` & `mpv_observe_property` to set up for asynchronous
///   callbacks, and encapsulates property changes for `handleEvent` & `handlePropertyChange` for subscribed events
///   & property changes, respectively.
/// - `MPVLogScanner.swift`: contains logic to parse certain `MPV_EVENT_LOG_MESSAGE` events to extract information which
///   cannot be determined elsewhere, and react appropriately.
class MPVController: NSObject {
  // Cached for prefs display. TODO: use ad hoc call using demo player instead
  static var watchLaterOptions: String = ""

  struct UserData {
    static let screenshot: UInt64 = 1000000
    static let screenshotRaw: UInt64 = 1000001
  }

  /// The mpv_handle
  var mpv: OpaquePointer!

  var mpvVersion: String!

  /// The DispatchQueue which is used to process events & (ideally) should be used to send all mpv commands.
  let queue: DispatchQueue

  unowned let player: PlayerCore
  let mpvLogScanner: MPVLogScanner!

  var needRecordSeekTime: Bool = false
  var recordedSeekStartTime: CFTimeInterval = 0
  var recordedSeekTimeListener: ((Double) -> Void)?

  @Atomic var hooks: [UInt64: MPVHookValue] = [:]
  private var hookCounter: UInt64 = 1

  var thumbfastInfo: ThumbfastInfo? {
    didSet {
      DispatchQueue.main.async {
        NotificationCenter.default.post(Notification(name: .thumbfastInfoDidChange, object: nil))
      }
    }
  }

  /// Running list of `window-scale` values which were sent to mpv but not yet received back from mpv as
  /// property change events. This helps to distinguish actual changes coming from mpv (which we care
  /// about) vs. the changes we already made which are getting echoed back at us (which we don't care about).
  var windowScalesExpected = LinkedList<CGFloat>([1.0])

  var log: any Logger.Subsystem { mpvLogScanner.mpvLogSubsystem }

  /// Creates a `MPVController` object.
  /// - Parameters:
  ///   - playerCore: The player this `MPVController` will be associated with.
  init(playerCore: PlayerCore) {
    self.player = playerCore
    self.queue = DispatchQueue.newDQ(label: "com.iina-advance.mpv.\(playerCore.label)", qos: .userInitiated)
    self.mpvLogScanner = MPVLogScanner(player: playerCore)
    super.init()
  }

  deinit {
    removeObservers()
  }

  // MARK: - Shutdown

  /// Remove observers for IINA preferences and mpv properties.
  /// - Important: Observers **must** be removed before sending a `quit` command to mpv. Accessing a mpv core after it
  ///     has shutdown is not permitted by mpv and can trigger a crash. During shutdown mpv will emit property change events,
  ///     thus it is critical that observers be removed, otherwise they may access the core and trigger a crash.
  func removeObservers() {
    // Remove observers for IINA preferences. Must not attempt to change a mpv setting in response
    // to an IINA preference change while mpv is shutting down.
    removeOptionObservers()
    // Remove observers for mpv properties. Because 0 was passed for reply_userdata when registering
    // mpv property observers all observers can be removed in one call.
    guard let mpv else {
      player.log.debug("Skipping call to mpv_unobserve_property: mpv handle is nil")
      return
    }
    player.log.verbose("Calling mpv_unobserve_property")
    mpv_unobserve_property(mpv, 0)
  }

  /// Remove observers for IINA preferences.
  private func removeOptionObservers() {
    player.log.verbose("Removing option observers")
    ObjcUtils.silenced { [self] in
      for (k, _) in optionObservers {
        UserDefaults.standard.removeObserver(self, forKeyPath: k)
      }
      optionObservers = [:]
    }
  }

  /// Shut down this mpv controller.
  func mpvQuit() {
    player.log.verbose("Quitting mpv")
    // Observers must be removed to avoid accessing the mpv core after it has shutdown.
    removeOptionObservers()
    // Start mpv quitting. Even though this command is being sent using the synchronous command API
    // the quit command is special and will be executed by mpv asynchronously.
    command(.quit, checkActive: false, level: .verbose)
  }

  func mpvDestroy() {
    player.log.verbose("Destroying mpv")
    guard mpv != nil else {
      log.error("Skipping call to mpv_destroy; mpv handle is nil!")
      return
    }
    mpv_destroy(mpv)
    mpv = nil
  }

  // MARK: - Commands

  private func makeCArgs(_ command: MPVCommand, _ args: [String?]) -> [String?] {
    if args.count > 0 && args.last == nil {
      Logger.fatal("Cmd does not need a nil suffix")
    }
    var strArgs = args
    strArgs.insert(command.rawValue, at: 0)
    strArgs.append(nil)
    return strArgs
  }

  /// Send arbitrary mpv command. Returns mpv return code.
  /// Warning: if `checkError: false` is not given, and an error occurs, this mpv core will go into shutdown!
  @discardableResult
  func command(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
               checkActive: Bool = true, level: Logger.Level = .debug) -> Int32 {
    if checkActive {
      guard player.isActive else {
        log.log("Skipping cmd (player state=\(player.state) is not active): \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))", level: level)
        return MPV_ERROR_GENERIC.rawValue
      }
    }
    if Logger.isEnabled(.verbose) {
      if command == .loadfile, let filename = args[0] {
        _ = Logger.getOrCreatePII(for: filename)
      }
    }
    log.log("Run cmd: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))", level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    guard let mpv else {
      log.error("Aborting cmd: mpv is nil! Returning error")
      return MPV_ERROR_GENERIC.rawValue
    }
    let returnValue = mpv_command(mpv, &cargs)
    if checkError {
      chkErr(returnValue)
    } else {
      logError(returnValue)
    }

    return returnValue
  }

  func command(rawString: String, level: Logger.Level = .debug) -> Int32 {
    log.log("Run cmd: \(rawString)", level: level)
    let returnValue = mpv_command_string(mpv, rawString)
    return logError(returnValue)
  }

  func asyncCommand(_ command: MPVCommand, args: [String?] = [], checkError: Bool = true,
                    replyUserdata: UInt64, level: Logger.Level = .debug) {
    guard mpv != nil else { return }
    log.log("Run async cmd: \(command.rawValue) \(args.compactMap{$0}.joined(separator: " "))",
            level: level)
    var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
    defer {
      for ptr in cargs {
        if (ptr != nil) {
          free(UnsafeMutablePointer(mutating: ptr!))
        }
      }
    }
    let returnValue = mpv_command_async(self.mpv, replyUserdata, &cargs)
    if checkError {
      chkErr(returnValue)
    }
  }

  // MARK: - Properties (generic)

  // Property setters

  func setFlag(_ name: String, _ flag: Bool, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(flag.yesno)", level: level)
    var data: Int = flag ? 1 : 0
    guard mpv != nil else { log.warn("Aborting setProperty: mpv is nil"); return }
    let code = mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    if code < 0 {
      player.log.error("Failed to set mpv_property \(name.quoted) = \(flag). Error: \(errorString(code))")
    }
  }

  func setInt(_ name: String, _ value: Int, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(value)", level: level)
    var data = Int64(value)
    guard mpv != nil else { log.warn("Aborting setProperty: mpv is nil"); return }
    mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
  }

  func setDouble(_ name: String, _ value: Double, level: Logger.Level = .debug) {
    log.log("Set property: \(name)=\(value)", level: level)
    var data = value
    guard mpv != nil else { log.warn("Aborting setProperty: mpv is nil"); return }
    mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  @discardableResult
  func setString(_ name: String, _ value: String, level: Logger.Level = .debug) -> Int32 {
    log.log("Set property: \(name)=\(value)", level: level)
    guard mpv != nil else { log.warn("Aborting setProperty: mpv is nil"); return -1 }
    return mpv_set_property_string(mpv, name, value)
  }

  // Property getters

  func getEnum<T: MPVOptionValue>(_ name: String) -> T {
    guard let value = getString(name) else {
      return T.defaultValue
    }
    return T.init(rawValue: value) ?? T.defaultValue
  }

  func getInt(_ name: String) -> Int {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
    return Int(data)
  }

  func getDouble(_ name: String) -> Double {
    var data = Double()
    mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    return data
  }

  func getFlag(_ name: String) -> Bool {
    var data = Int64()
    mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
    return data > 0
  }

  func getString(_ name: String) -> String? {
    let cstr = mpv_get_property_string(mpv, name)
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
  }

  func getNode(_ name: String) -> Any? {
    guard mpv != nil else { log.warn("Aborting mpv_get_property: mpv is nil"); return nil }
    var node = mpv_node()
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &node)
    let parsed = try? MPVNode.parse(node)
    mpv_free_node_contents(&node)
    return parsed
  }

  func setNode(_ name: String, _ value: Any) {
    guard var node = try? MPVNode.create(value) else {
      log.error("setNode: cannot encode value for \(name)")
      return
    }
    log.debug("Set property: \(name)=<a mpv node>")
    mpv_set_property(mpv, name, MPV_FORMAT_NODE, &node)
    MPVNode.free(node)
  }

  private func getFromMap(_ key: String, _ map: [String: Any?]) -> String {
    if let keyOpt = map[key] as? Optional<String> {
      return keyOpt!
    }
    return ""
  }

  // MARK: - Filters

  /// Get all filters of the given type. only "af" or "vf" is supported for filterType
  func getFilters(_ filterType: String) -> [MPVFilter] {
    assert(filterType == MPVProperty.vf || filterType == MPVProperty.af, "getFilters() does not support \(filterType)!")

    var filters: [MPVFilter] = []
    var node = mpv_node()
    mpv_get_property(mpv, filterType, MPV_FORMAT_NODE, &node)
    guard let filterNodes = (try? MPVNode.parse(node)!) as? [[String: Any?]] else { return filters }
    
    filterNodes.forEach { f in
      let filter = MPVFilter(name: f["name"] as! String,
                             label: f["label"] as? String,
                             params: f["params"] as? [String: String])
      filters.append(filter)
    }
    mpv_free_node_contents(&node)

    return filters
  }

  /// Remove the audio or video filter at the given index in the list of filters.
  ///
  /// Previously IINA removed filters using the mpv `af remove` and `vf remove` commands described in the
  /// [Input Commands that are Possibly Subject to Change](https://mpv.io/manual/stable/#input-commands-that-are-possibly-subject-to-change)
  /// section of the mpv manual. The behavior of the remove command is described in the [video-filters](https://mpv.io/manual/stable/#video-filters)
  /// section of the manual under the entry for `--vf-remove-filter`.
  ///
  /// When searching for the filter to be deleted the remove command takes into consideration the order of filter parameters. The
  /// expectation is that the application using the mpv client will provide the filter to the remove command in the same way it was
  /// added. However IINA doe not always know how a filter was added. Filters can be added to mpv outside of IINA therefore it is not
  /// possible for IINA to know how filters were added. IINA obtains the filter list from mpv using `mpv_get_property`. The
  /// `mpv_node` tree returned for a filter list stores the filter parameters in a `MPV_FORMAT_NODE_MAP`. The key value pairs in a
  /// `MPV_FORMAT_NODE_MAP` are in **random** order. As a result sometimes the order of filter parameters in the filter string
  /// representation given by IINA to the mpv remove command would not match the order of parameters given when the filter was
  /// added to mpv and the remove command would fail to remove the filter. This was reported in
  /// [IINA issue #3620 Audio filters with same name cannot be removed](https://github.com/iina/iina/issues/3620).
  ///
  /// The issue of `mpv_get_property` returning filter parameters in random order even though the remove command is sensitive to
  /// filter parameter order was raised with the mpv project in
  /// [mpv issue #9841 mpv_get_property returns filter params in unordered map breaking remove](https://github.com/mpv-player/mpv/issues/9841)
  /// The response from the mpv project confirmed that the parameters in a `MPV_FORMAT_NODE_MAP` **must** be considered to
  /// be in random order even if they appear to be ordered. The recommended methods for removing filters is to use labels, which
  /// IINA does for filters it creates or removing based on position in the filter list. This method supports removal based on the
  /// position within the list of filters.
  ///
  /// The recommended implementation is to get the entire list of filters using `mpv_get_property`, remove the filter from the
  /// `mpv_node` tree returned by that method and then set the list of filters using `mpv_set_property`. This is the approach
  /// used by this method.
  /// - Parameter name: The kind of filter identified by the mpv property name, `MPVProperty.af` or `MPVProperty.vf`.
  /// - Parameter index: Index of the filter to be removed.
  /// - Returns: `true` if the filter was successfully removed, `false` if the filter was not removed.
  func removeFilter(_ name: String, _ index: Int) -> Bool {
    assert(DispatchQueue.isExecutingIn(queue))
    Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af,
                  "removeFilter() does not support \(name)!")
    guard mpv != nil else { log.warn("Aborting removeFilter: mpv is nil"); return false }

    // Get the current list of filters from mpv as a mpv_node tree.
    var oldNode = mpv_node()
    defer { mpv_free_node_contents(&oldNode) }
    mpv_get_property(mpv, name, MPV_FORMAT_NODE, &oldNode)

    let oldList = oldNode.u.list!.pointee

    // If the user uses mpv's JSON-based IPC protocol to make changes to mpv's filters behind IINA's
    // back then there is a very small window of vulnerability where the list of filters displayed
    // by IINA may be stale and therefore the index to remove may be invalid. IINA listens for
    // changes to mpv's filter properties and updates the filters displayed when changes occur, so
    // it is unlikely in practice that this method will be called with an invalid index, but we will
    // validate the index nonetheless to insure this code does not trigger a crash.
    guard index < oldList.num else {
      log.error("Found \(oldList.num) \(name) filters, index of filter to remove (\(index)) is invalid")
      return false
    }

    // The documentation for mpv_node states:
    // "If mpv writes this struct (e.g. via mpv_get_property()), you must not change the data."
    // So the approach taken is to create new top level node objects as those need to be modified in
    // order to remove the filter, and reuse the lower level node objects representing the filters.
    // First we create a new node list that is one entry smaller than the current list of filters.
    let newNum = oldList.num - 1
    let newValues = UnsafeMutablePointer<mpv_node>.allocate(capacity: Int(newNum))
    defer {
      newValues.deinitialize(count: Int(newNum))
      newValues.deallocate()
    }
    var newList = mpv_node_list()
    newList.num = newNum
    newList.values = newValues

    // Make the new list of values point to the same values in the old list, skipping the entry to
    // be removed.
    var newValuesPtr = newValues
    var oldValuesPtr = oldList.values!
    for i in 0 ..< oldList.num {
      if i != index {
        newValuesPtr.pointee = oldValuesPtr.pointee
        newValuesPtr = newValuesPtr.successor()
      }
      oldValuesPtr = oldValuesPtr.successor()
    }

    // Add the new list to a new node.
    let newListPtr = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
    defer {
      newListPtr.deinitialize(count: 1)
      newListPtr.deallocate()
    }
    newListPtr.pointee = newList
    var newNode = mpv_node()
    newNode.format = MPV_FORMAT_NODE_ARRAY
    newNode.u.list = newListPtr

    // Set the list of filters using the new node that leaves out the filter to be removed.
    log.debug("Set property: \(name)=<a mpv node>")
    let returnValue = mpv_set_property(mpv, name, MPV_FORMAT_NODE, &newNode)
    return returnValue == 0
  }

  /** Set filter. only "af" or "vf" is supported for name */
  func setFilters(_ name: String, filters: [MPVFilter]) {
    queue.async { [self] in
      guard !player.isStopping else { return }
      Logger.ensure(name == MPVProperty.vf || name == MPVProperty.af, "setFilters() do not support \(name)!")
      let cmd = name == MPVProperty.vf ? MPVCommand.vf : MPVCommand.af

      let str = filters.map { $0.stringFormat }.joined(separator: ",")
      let returnValue = command(cmd, args: ["set", str], checkError: false)
      if returnValue < 0 {
        DispatchQueue.main.async { [self] in
          Utility.showAlert("filter.incorrect")
          // reload data in filter setting window
          player.postNotification(.iinaVFChanged)
        }
      }
    }
  }

  // MARK: - Other

  /// Call this only after player is done loading
  func updateLoggingLevels() {
    mpvLogScanner.updateMpvEventLogLevel()

    player.mpv.queue.async { [self] in
      guard player.isActive else { return }
      player.mpv.setMpvEventLogSubscription()
    }
  }

  func setMpvEventLogSubscription() {
    // Must still subscribe to min level or above, even if not logging
    let subscriptionLevel = mpvLogScanner.mpvEventLogLevel.shouldLog(severity: Constants.minMpvEventLogLevel.rawValue) ? mpvLogScanner.mpvEventLogLevel : Constants.minMpvEventLogLevel

    // Receive MPV_EVENT_LOG messages at given level of verbosity.
    log.verbose("Updating mpv log event subscription level to \(subscriptionLevel.string.quoted)")
    chkErr(mpv_request_log_messages(mpv, subscriptionLevel.string))
  }

  func getInputBindings(filterCommandsBy filter: ((Substring) -> Bool)? = nil) -> [KeyMapping] {
    player.log.verbose("Requesting from mpv: \(MPVProperty.inputBindings)")
    let parsed = getNode(MPVProperty.inputBindings)
    return toKeyMappings(parsed)
  }

  func getInputKeyList() -> [String] {
    player.log.verbose("Requesting from mpv: \(MPVProperty.inputKeyList)")
    if let csv = getString(MPVProperty.inputKeyList) {
      return csv.split(separator: ",").map{String($0)}
    }
    return []
  }

  func toKeyMappings(_ inputBindingArray: Any?, filterCommandsBy filter: ((Substring) -> Bool)? = nil) -> [KeyMapping] {
    var keyMappingList: [KeyMapping] = []
    if let mapList = inputBindingArray as? [Any?] {
      for mapRaw in mapList {
        if let map = mapRaw as? [String: Any?] {
          let key = getFromMap("key", map)
          let cmd = getFromMap("cmd", map)
          let comment = getFromMap("comment", map)
          let cmdTokens = cmd.split(separator: " ")
          if filter == nil || filter!(cmdTokens[0]) {
            keyMappingList.append(KeyMapping(rawKey: key, rawAction: cmd, isIINACommand: false, comment: comment))
          }
        }
      }
    } else {
      player.log.error("Failed to parse mpv input bindings!")
    }
    return keyMappingList
  }

  func sendScriptMessage(to scriptName: String, args: [LosslessStringConvertible]) {
    guard mpv != nil else { log.warn("Aborting mpv_command_node: mpv is nil"); return }
    var resultNode = mpv_node()
    defer {
      mpv_free_node_contents(&resultNode)
    }
    let stringArgs: [String] = [MPVCommand.scriptMessageTo.rawValue, scriptName] + args.map{ String($0)}
    guard var argsNode = try? MPVNode.create(stringArgs) else {
      log.error("sendMsgToScript: cannot encode value for \(stringArgs)")
      return
    }
    log.verbose("Sending to script: \(stringArgs)")
    mpv_command_node(mpv, &argsNode, &resultNode)
  }

  /// For mpv, window size is always the same as video size, but this is not always true with IINA due to exterior panels.
  /// Also, mpv uses `backingScaleFactor` for calcalations. IINA Advance does not, because that has no correlation with the
  /// screen's actual scale factor and is at best an oversimplification which is less wrong on average. It is like assuming
  /// "all men have a shoe size of 10 and all women have a shoe size of 8", which is only slightly better than "all humans have a shoe size of 9".
  func getWindowScale() -> Double {
    let mpvVideoScale = getDouble(MPVProperty.windowScale)
    // Use 6 decimals to be consistent with both mpv & IINA calculations
    return mpvVideoScale.roundedTo6()
  }

  func getScreenshot(_ arg: String) -> NSImage? {
    log.verbose("Taking screenshot-raw \(arg)")
    var args = try! MPVNode.create(["screenshot-raw", arg])
    defer {
      MPVNode.free(args)
    }
    var result = mpv_node()
    mpv_command_node(self.mpv, &args, &result)
    guard let rawImage = try? MPVNode.parse(result) as? [String: Any] else { return nil }
    mpv_free_node_contents(&result)
    var pixelArray = rawImage["data"] as! [UInt8]
    // According to mpv's client.h, the pixel array mpv returns arrange
    // color data as "B8G8R8X8", whereas CGImages's data provider needs
    // RGBA, so swap each pixel at index 0 and 2.
    for i in 0 ..< pixelArray.count >> 2 {
      pixelArray.swapAt(i << 2, i << 2 | 2)
    }
    let width = Int(truncatingIfNeeded: rawImage["w"] as! Int64)
    let height = Int(truncatingIfNeeded: rawImage["h"] as! Int64)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let providerRef = CGDataProvider(data: NSData(bytes: pixelArray, length: pixelArray.count))!
    let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 4 * 8, bytesPerRow: width * 4, space: rgbColorSpace, bitmapInfo: bitmapInfo, provider: providerRef, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    return NSImage(cgImage: cgImage!, size: NSSize(width: width, height: height))
  }

  /// Returns true if mpv's state has fallen behind the current user intention and it is currently operating on an entry
  /// which IINA doesn't care about anymore.
  ///
  /// mpv's `playlist-current-pos` tracks the lifecycle of a playlist entry from start to end.
  /// Should not be confused with `playlist-playing-pos`, which is used for the "playing" highlighted row in the playlist.
  func isStale() -> Bool {
    assert(DispatchQueue.isExecutingIn(queue))
    let mpv = getInt(MPVProperty.playlistCurrentPos)
    guard let iina = player.info.currentPlayback?.playlistPos else {
      // Note: not current if both are nil
      player.log.verbose("The current playlistPos from mpv (\(mpv)) is stale because there should be no media loaded")
      return true
    }
    let isStale = mpv != iina
    player.log.verbose("IINA \(iina), mpv \(mpv) → isStale=\(isStale.yesno)")
    return isStale
  }

  func updateKeepOpenOptionFromPrefs() {
    setUserOption(PK.keepOpenOnFileEnd, type: .other, forName: MPVOption.Window.keepOpen,
                  sync: false, level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? Constants.String.mpvYes : Constants.String.mpvNo)
    }

    setUserOption(PK.playlistAutoPlayNext, type: .other, forName: MPVOption.Window.keepOpen,
                  sync: false, level: .verbose) { key in
      let keepOpen = Preference.bool(for: PK.keepOpenOnFileEnd)
      let keepOpenPl = !Preference.bool(for: PK.playlistAutoPlayNext)
      return keepOpenPl ? "always" : (keepOpen ? Constants.String.mpvYes : Constants.String.mpvNo)
    }
  }

  func updateUsingMpvOSDFromPrefs() {
    queue.async { [self] in
      _updateUsingMpvOSDFromPrefs()
    }
  }

  func _updateUsingMpvOSDFromPrefs() {
    // This can be called during init
    guard !player.isStopping else { return }
    let useMpvOSD = !player.isDemoPlayer && Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .useMpvOsd)
    log.verbose("Derived isUsingMpvOSD: \(useMpvOSD.yn)")
    player.isUsingMpvOSD = useMpvOSD
    if useMpvOSD {
      // If using mpv OSD, then disable IINA's OSD
      player.hideOSD()
    } else {
      // Otherwise disable mpv OSD
      chkErr(mpv_set_option_string(mpv, MPVOption.OSD.osdLevel, "0"))
    }
  }

  // MARK: - Thumbfast

  struct ThumbfastInfo: Decodable {
    let width: Int
    let height: Int
    let available: Bool
    let disabled: Bool
    let scale_factor: Double

    var isReady: Bool { available && !disabled }

    static func fromJSON(_ json: String?, _ log: any Logger.Subsystem) -> ThumbfastInfo? {
      do {
        guard let json else {
          log.error("Failed to parse thumbfast-info: obj is nil")
          return nil
        }
        guard let jsonData = json.data(using: .utf8) else {
          log.error("Failed create JSON data for thumbfast-info")
          return nil
        }
        return try JSONDecoder().decode(ThumbfastInfo.self, from: jsonData)
      } catch {
        log.error("Failed to get or parse thumbfast-info from mpv: \(error)")
        return nil
      }
    }
  }

  /// Sends a message to the thumbfast script to show a thumbnail with the given timestamp at the given coordinates.
  func showThumbfast(hoveredSecs: Double, x: Double, y: Double) {
    guard let thumbfastInfo, thumbfastInfo.isReady else { return }
    sendScriptMessage(to: "thumbfast", args: ["thumb", hoveredSecs, x, y])
  }

  func clearThumbfast() {
    guard let thumbfastInfo, thumbfastInfo.isReady else { return }
    sendScriptMessage(to: "thumbfast", args: ["clear"])
  }

  // MARK: - Hooks

  func addHook(_ name: MPVHook, priority: Int32 = 0, hook: MPVHookValue) {
    $hooks.withLock {
      mpv_hook_add(mpv, hookCounter, name.rawValue, priority)
      $0[hookCounter] = hook
      hookCounter += 1
    }
  }

  func removeHooks(withIdentifier id: String) {
    $hooks.withLock { hooks in
      hooks.filter { (k, v) in v.isJavascript && v.id == id }.keys.forEach { hooks.removeValue(forKey: $0) }
    }
  }

  // MARK: - User Options

  enum UserOptionType {
    case bool, int, float, string, color, other
  }

  struct OptionObserverInfo {
    typealias Transformer = (Preference.Key) -> String?

    var prefKey: Preference.Key
    var optionName: String
    var valueType: UserOptionType
    /** input a pref key and return the option value (as string) */
    var transformer: Transformer?

    init(_ prefKey: Preference.Key, _ optionName: String, _ valueType: UserOptionType, _ transformer: Transformer?) {
      self.prefKey = prefKey
      self.optionName = optionName
      self.valueType = valueType
      self.transformer = transformer
    }
  }

  private var optionObservers: [String: [OptionObserverInfo]] = [:]

  func setOptionFlag(_ name: String, _ flag: Bool, level: Logger.Level = .debug,
                     verboseIfDefault: Bool = false) -> Int32 {
    let value = flag ? Constants.String.mpvYes : Constants.String.mpvNo
    return setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
  }

  func setOptionFloat(_ name: String, _ value: Float, level: Logger.Level = .debug,
                      verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = {
      guard verboseIfDefault, let defaultValue = MPVOptionDefaults.shared.getDouble(name),
            abs(Double(value).distance(to: defaultValue)) <= Double.leastNonzeroMagnitude else {
        return level
      }
      return .verbose
    }()
    log.log("Set option: \(name)=\(value)", level: levelToUse)
    var data = Double(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_DOUBLE, &data)
  }

  func setOptionInt(_ name: String, _ value: Int, level: Logger.Level = .debug,
                    verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = verboseIfDefault &&
    MPVOptionDefaults.shared.getInt(name) == value ? .verbose  : level
    log.log("Set option: \(name)=\(value)", level: levelToUse)
    var data = Int64(value)
    return mpv_set_option(mpv, name, MPV_FORMAT_INT64, &data)
  }

  @discardableResult
  func setOptionString(_ name: String, _ value: String, level: Logger.Level = .debug,
                       verboseIfDefault: Bool = false) -> Int32 {
    let levelToUse: Logger.Level = verboseIfDefault &&
    MPVOptionDefaults.shared.getString(name) == value ? .verbose  : level
    log.log("Set option: \(name)=\(value)", level: levelToUse)
    return mpv_set_option_string(mpv, name, value)
  }

  func setOptionalOptionColor(_ name: String, _ value: String?,
                              level: Logger.Level = .debug,
                              verboseIfDefault: Bool = false) -> Int32 {
    guard let value = value else { return 0 }
    let levelToUse: Logger.Level = {
      // The default value for options of type color is currently returned by mpv in the alternative
      // string format that specifies component values in hex. Must convert to the form that uses
      // floating point to be able to compare the strings.
      guard verboseIfDefault, let defaultValue = MPVOptionDefaults.shared.getString(name),
            hexColorToFloat(defaultValue) == value else {
        return level
      }
      return .verbose
    }()
    return setOptionString(name, value, level: levelToUse)
  }

  func setOptionalOptionString(_ name: String, _ value: String?, level: Logger.Level = .debug,
                               verboseIfDefault: Bool = false) -> Int32 {
    guard let value = value else { return 0 }
    return setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
  }

  /// Set the given mpv option to the value of the given IINA setting.
  ///
  /// To reduce the amount of logging that occurs when `MPVController` initializes a mpv core this method provides a
  /// `verboseIfDefault` parameter. If this parameter is set to `true` then the value to set the mpv option to is compared to the
  /// default value for the mpv option and if the values match then the value of the `level` parameter will be ignored and the
  /// message will be logged using the `verbose` level.
  /// - Parameters:
  ///   - key: Key for the IINA setting.
  ///   - type: Type of the value of the mpv option.
  ///   - name: Name of the mpv option.
  ///   - sync: Whether to add an observer for the IINA setting that updates the mpv option when the IINA setting changes.
  ///   - level: Log level to use when logging the setting of the option.
  ///   - verboseIfDefault: Whether to use log level `verbose` if the value matches the default for the mpv option.
  ///   - transformer: Optional transformer that changes the IINA setting value to be usable as the mpv option value.
  func setUserOption(_ key: Preference.Key, type: UserOptionType, forName name: String,
                     sync: Bool = true, level: Logger.Level = .debug,
                     verboseIfDefault: Bool = false,
                     transformer: OptionObserverInfo.Transformer? = nil) {
    var code: Int32 = 0

    let keyRawValue = key.rawValue

    switch type {
    case .int:
      code = setOptionInt(name, Preference.integer(for: key), level: level,
                          verboseIfDefault: verboseIfDefault)

    case .float:
      code = setOptionFloat(name, Preference.float(for: key), level: level,
                            verboseIfDefault: verboseIfDefault)

    case .bool:
      code = setOptionFlag(name, Preference.bool(for: key), level: level,
                           verboseIfDefault: verboseIfDefault)

    case .string:
      code = setOptionalOptionString(name, Preference.string(for: key), level: level,
                                     verboseIfDefault: verboseIfDefault)

    case .color:
      let value = Preference.string(for: key)
      code = setOptionalOptionColor(name, value, level: level, verboseIfDefault: verboseIfDefault)
      // Random error here (perhaps a Swift or mpv one), so set it twice
      // 「没有什么是 set 不了的；如果有，那就 set 两次」
      if code < 0 {
        code = setOptionalOptionColor(name, value, level: level, verboseIfDefault: verboseIfDefault)
      }

    case .other:
      guard let tr = transformer else {
        log.error("setUserOption: no transformer!")
        return
      }
      if let value = tr(key) {
        code = setOptionString(name, value, level: level, verboseIfDefault: verboseIfDefault)
      } else {
        code = 0
      }
    }

    if code < 0 {
      let message = errorString(code)
      /// We may be on the main DQ already. Must async out of it to avoid deadlocking!
      DispatchQueue.main.async {
        Utility.showAlert("mpv_error", arguments: [message, "\(code)", name], disableMenus: true)
      }
    }

    if sync {
      UserDefaults.standard.addObserver(self, forKeyPath: keyRawValue, options: [.new, .old], context: nil)
      if optionObservers[keyRawValue] == nil {
        optionObservers[keyRawValue] = []
      }
      optionObservers[keyRawValue]!.append(OptionObserverInfo(key, name, type, transformer))
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard !(change?[NSKeyValueChangeKey.oldKey] is NSNull) else { return }

    guard let keyPath = keyPath else { return }
    guard let infos = optionObservers[keyPath] else { return }

    for info in infos {
      switch info.valueType {
      case .int:
        let value = Preference.integer(for: info.prefKey)
        setInt(info.optionName, value)

      case .float:
        let value = Preference.float(for: info.prefKey)
        setDouble(info.optionName, Double(value))

      case .bool:
        let value = Preference.bool(for: info.prefKey)
        setFlag(info.optionName, value)

      case .string:
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .color:
        if let value = Preference.string(for: info.prefKey) {
          setString(info.optionName, value)
        }

      case .other:
        guard let tr = info.transformer else {
          log.error("observeValue: no transformer!")
          return
        }
        if let value = tr(info.prefKey) {
          setString(info.optionName, value)
        }
      }
    }
  }

  // MARK: - Utils

  func errorString(_ code: Int32) -> String {
    return String(cString: mpv_error_string(code))
  }

  /**
   Utility function for checking mpv api error
   */
  func chkErr(_ returnCode: Int32!) {
    guard returnCode < 0 else { return }
    let message = "mpv API error: \"\(errorString(returnCode))\", Return value: \(returnCode!)."
    player.log.error(message)

    DispatchQueue.main.async { [self] in
      Utility.showAlert("fatal_error", arguments: [message])
      player.shutdown()
      player.pwc.close()
    }
  }

  @discardableResult
  func logError(_ returnCode: Int32) -> Int32 {
    guard returnCode < 0 else { return returnCode }
    guard player.log.isErrorEnabled else { return returnCode }
    player.log.error("mpv API error: \"\(errorString(returnCode))\", Return value: \(returnCode)")
    return returnCode
  }

  /// Convert the given mpv color string containing color components specified in hex to floating point.
  ///
  /// Normally color is specified in the form r/g/b, where each color component is specified as number in the range 0.0 to 1.0. It's also
  /// possible to specify the transparency by using r/g/b/a, where the alpha value 0 means fully transparent, and 1.0 means opaque.
  /// If the alpha component is not given, the color is 100% opaque. Alternatively, the color can be specified as a RGB hex triplet in the
  /// form #RRGGBB, where each 2-digit group expresses a color value in the range 0 (00) to 255 (FF). Alpha is given with #AARRGGBB.
  /// This method converts from the hex based alternative form to the floating point form.
  /// - Parameter color: Color with components specified in hex.
  /// - Returns: Color with components specified in floating point.
  private func hexColorToFloat(_ color: String) -> String {
    guard color.starts(with: "#"), color.count == 7 || color.count == 9 else {
      log.error("Invalid mpv hex color string: \(color)")
      return color
    }
    var components: [String] = []
    for offset in stride(from: 1, to: color.count, by: 2) {
      let range = color.index(color.startIndex, offsetBy: offset)...color.index(color.startIndex, offsetBy: offset + 1)
      let value = Double(Int(color[range], radix: 16)!)
      components.append(String(value / 255))
    }
    guard components.count == 4 else {
      return components.joined(separator: "/")
    }
    // The alpha component comes first in the hex based form, last in the floating point form.
    let alpha = components[0]
    components.remove(at: 0)
    return "\(components.joined(separator: "/"))/\(alpha)"
  }

}
