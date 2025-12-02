//
//  AppInputConfigBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

final class AppInputConfigBuilder {
  @MainActor
  static let shared = AppInputConfigBuilder()

  private let log = Logger.input

  // Needs to be on main for MenuController
  @MainActor
  func build(_ allBindingCandidates: [InputBinding], playerLabel: String, version: Int) -> AppInputConfig {
    if DebugConfig.logBindingsRebuild {
      log.verbose("Starting rebuild of AppInputConfig v\(version) (player-\(playerLabel))")
    }

    var bindingCandidateList = allBindingCandidates
    var resolverDict: [String: Int] = [:]
    var duplicateKeys = Set<String>()
    var anyUnicodeBindingIndex: Int? = nil
    var unmappedBindingIndex: Int? = nil

    /// See `AppInputConfig.userConfSectionStartIndex`
    var userConfSectionStartIndex: Int? = nil
    /// See `AppInputConfig.userConfSectionEndIndex`
    var userConfSectionEndIndex: Int? = nil

    // Now build the resolverDict, disabling redundant key bindings along the way.
    for (candidateIndex, binding) in bindingCandidateList.enumerated() {
      guard binding.isEnabled else { continue }

      // Set these variables here for improved lookup speed later. TODO: consider deleting...
      // Remember, all weak bindings precede the default section, and all strong bindings come after it.
      // But any section may have zero bindings.
      if userConfSectionStartIndex ==  nil {
        if binding.origin == .confFile, binding.srcSectionName == MPVInputSection.Shared.USER_CONF_SECTION_NAME {
          userConfSectionStartIndex = candidateIndex
        }
      } else if userConfSectionEndIndex == nil {
        if (binding.origin != .confFile) || (binding.srcSectionName != MPVInputSection.Shared.USER_CONF_SECTION_NAME) {
          userConfSectionEndIndex = candidateIndex
        }
      }

      let key = binding.keyMapping.normalizedMpvKey

      // Ignore empty bindings added by the prefs UI:
      guard !key.isEmpty else { continue }

      let prevSameKeyBindingIndex: Int?

      if key == Constants.anyUnicodeKey {
        // Wildcard binding: ANY_UNICODE
        prevSameKeyBindingIndex = anyUnicodeBindingIndex
        if let prevSameKeyBindingIndex {
          let prevSameKeyBinding = bindingCandidateList[prevSameKeyBindingIndex]
          log.warn("Multiple ANY_UNICODE bindings found in input conf! Overriding action \(prevSameKeyBinding.keyMapping.rawAction?.quoted ?? "nil") with \(binding.keyMapping.rawAction?.quoted ?? "nil")")
        }
        anyUnicodeBindingIndex = candidateIndex

        // Go back and disable all previous candidates which match ANY_UNICODE
        for prevBindingIndex in 0..<candidateIndex {
          let prevBinding = bindingCandidateList[prevBindingIndex]
          guard prevBinding.isEnabled else { continue }
          let bindingKey = prevBinding.keyMapping.normalizedMpvKey
          if KeyCodeHelper.isTypedUnicodeChar(normalizedMpvKey: bindingKey) {
            let disabledBinding = prevBinding.shallowClone(isEnabled: false, displayMessage: "This binding is overridden by the ANY_UNICODE binding below.")
            duplicateKeys.insert(bindingKey)
            bindingCandidateList[prevBindingIndex] = disabledBinding
          }
        }

      } else if key == Constants.unmappedKey {
        // Wildcard binding: UNMAPPED
        prevSameKeyBindingIndex = unmappedBindingIndex
        if let prevSameKeyBindingIndex {
          let prevSameKeyBinding = bindingCandidateList[prevSameKeyBindingIndex]
          log.warn("Multiple UNMAPPED bindings found in input conf! Overriding action \(prevSameKeyBinding.keyMapping.rawAction?.quoted ?? "nil") with \(binding.keyMapping.rawAction?.quoted ?? "nil")")
        }
        unmappedBindingIndex = candidateIndex

      } else {
        // Regular binding (not wildcard)
        prevSameKeyBindingIndex = resolverDict[key]

        // Store it, overwriting any previous entry:
        resolverDict[key] = candidateIndex
      }

      // If multiple bindings map to the same key, favor the last one always.
      if let prevSameKeyBindingIndex {
        duplicateKeys.insert(key)
        let displayMessage: String
        let prevSameKeyBinding = bindingCandidateList[prevSameKeyBindingIndex]
        if prevSameKeyBinding.origin == .iinaPlugin {
          displayMessage = "\(key.quoted) is overridden by \(binding.keyMapping.actionDescription().quoted). Plugins must use key bindings which have not already been used."
        } else {
          displayMessage = "This binding is overridden by a binding below it which also uses \(key.quoted)"
        }

        let disabledBinding = prevSameKeyBinding.shallowClone(isEnabled: false, displayMessage: displayMessage)
        bindingCandidateList[prevSameKeyBindingIndex] = disabledBinding
      }
    }

    // Do this last, after everything has been inserted, so that there is no risk of blocking other bindings from being inserted.
    let partialSequenceDict = buildPartialSequences(resolverDict, bindingCandidateList)

    let menuController = AppDelegate.shared.menuController!

    // This will update all standard menu item bindings, and also update the isMenuItem status of each:
    menuController.updateKeyEquivalents(in: &bindingCandidateList)

    if userConfSectionStartIndex == nil {
      userConfSectionStartIndex = bindingCandidateList.count
      userConfSectionEndIndex = bindingCandidateList.count
    } else if userConfSectionEndIndex == nil {
      userConfSectionEndIndex = bindingCandidateList.count
    }

    let appInputConfig = AppInputConfig(version: version, playerLabel: playerLabel,
                                        bindingCandidateList: bindingCandidateList, resolverDict: resolverDict,
                                        partialSequenceDict: partialSequenceDict,
                                        anyUnicode: anyUnicodeBindingIndex, unmapped: unmappedBindingIndex, duplicateKeys: duplicateKeys,
                                        userConfSectionStartIndex: userConfSectionStartIndex!, userConfSectionEndIndex: userConfSectionEndIndex!)
    if DebugConfig.logBindingsRebuild {
      log.verbose("Finished AppInputConfig rebuild with \(appInputConfig.resolverDict.count) bindings")
    }
    appInputConfig.logEnabledBindings()

    return appInputConfig
  }

  /// Sets an explicit "ignore" for all partial key sequence matches. This is all done so that the player window doesn't beep.
  private func buildPartialSequences(_ activeBindingsDict: [String: Int], _ activeBindings: [InputBinding]) -> [String: InputBinding] {
    var partialSequenceDict: [String: InputBinding] = [:]

    var addedCount = 0
    for (keySequence, bindingIndex) in activeBindingsDict {
      let binding = activeBindings[bindingIndex]
      if binding.isEnabled && keySequence.contains("-") {
        let keySequenceSplit = KeyCodeHelper.splitAndNormalizeMpvString(keySequence)
        if keySequenceSplit.count >= 2 && keySequenceSplit.count <= 4 {
          var partial = ""
          for key in keySequenceSplit {
            if partial == "" {
              partial = String(key)
            } else {
              partial = "\(partial)-\(key)"
            }
            if partial != keySequence, !activeBindingsDict.keys.contains(partial), !partialSequenceDict.keys.contains(partial) {
              let partialBinding = KeyMapping(rawKey: partial, rawAction: MPVCommand.ignore.rawValue, comment: "(partial sequence)")
              partialSequenceDict[partial] = InputBinding(partialBinding, origin: binding.origin, srcSectionName: binding.srcSectionName, isEnabled: true)
              addedCount += 1
            }
          }
        }
      }
    }
    if DebugConfig.logBindingsRebuild {
      log.verbose("Added \(addedCount) `ignored` bindings for partial key sequences (resulting dict size: \(partialSequenceDict.count)")
    }
    assert(partialSequenceDict.count == addedCount, "Expected dict to contain \(addedCount) partial sequences but found \(partialSequenceDict.count)!")
    return partialSequenceDict
  }
}

extension InputSectionStack {

  /// Generates `InputBinding`s for all the bindings in all the InputSections in this stack, and combines them into a single array.
  /// Some basic individual validation is performed on each, so some will have `isEnabled` set to false.
  /// Bindings with identical keys will not be filtered or disabled here.
  func collectAllEnabledSectionBindings() -> [InputBinding] {
    InputSectionStack.lock.withLock {
      // Because each InputSection is a read-only struct, this player's copy of shared section data may have gone stale.
      // Replace ours with the latest from the shared section stack.
      // We do not overwrite the player's enablement array, so some of these could have been disabled in the player.
      let latestSharedSections = AppInputConfig.sharedSections
      for sharedSection in latestSharedSections {
        // do not use auto-disable logic; it's not mandatory and might overwrite user state
        sectionsDefined[sharedSection.name] = sharedSection
      }
      /// Build the list of `InputBinding`s, including redundancies. We're not done setting each's `isEnabled` field though.
      /// This also sets `userConfSectionStartIndex` and `userConfSectionEndIndex`.
      return collectAllEnabledSectionBindings_Unsafe()
    }
  }

  private func collectAllEnabledSectionBindings_Unsafe() -> [InputBinding] {
    var linkedList = LinkedList<InputBinding>()

    // Iterate from bottom to the top of the "stack":
    for enabledSectionMeta in sectionsEnabled {
      if DebugConfig.logBindingsRebuild {
        log.verbose("RebuildBindings: examining enabled section: \(enabledSectionMeta.name.quoted)")
      }
      guard let inputSection = sectionsDefined[enabledSectionMeta.name] else {
        // indicates serious internal error
        log.error("RebuildBindings: failed to find section: \(enabledSectionMeta.name.quoted)")
        continue
      }

      addAllBindings(from: inputSection, to: &linkedList)

      if DebugConfig.logBindingsRebuild {
        log.verbose("RebuildBindings: CandidateList in increasing priority: \(linkedList.map({$0.keyMapping.normalizedMpvKey}).joined(separator: ", "))")
      }

      if enabledSectionMeta.isExclusive {
        log.verbose("RebuildBindings: section \(inputSection.name.quoted) was enabled exclusively")
        return Array<InputBinding>(linkedList)
      }
    }

    return Array<InputBinding>(linkedList)
  }

  private func addAllBindings(from inputSection: InputSection, to linkedList: inout LinkedList<InputBinding>) {
    guard !inputSection.keyMappingList.isEmpty else {
      if DebugConfig.logBindingsRebuild {
        log.verbose("RebuildBindings: skipping section \(inputSection.name.quoted) as it has no bindings")
      }
      return
    }

    if inputSection.isForce {
      if DebugConfig.logBindingsRebuild {
        log.verbose("RebuildBindings: adding bindings from \(inputSection) to tail of list")
      }
      // Strong section: Iterate from top of section to bottom (increasing priority) and add to end of list
      for keyMapping in inputSection.keyMappingList {
        let activeBinding = buildNewInputBinding(from: keyMapping, section: inputSection)
        linkedList.append(activeBinding)
      }
    } else {
      // Weak section: Iterate from top of section to bottom (decreasing priority) and add backwards to beginning of list
      if DebugConfig.logBindingsRebuild {
        log.verbose("RebuildBindings: adding bindings from \(inputSection) to head of list, in reverse order")
      }
      for keyMapping in inputSection.keyMappingList.reversed() {
        let activeBinding = buildNewInputBinding(from: keyMapping, section: inputSection)
        linkedList.prepend(activeBinding)
      }
    }
  }

  /**
   Derive the binding's metadata from the binding, and check for certain disqualifying commands and/or syntax.
   If invalid, the returned object will have `isEnabled` set to `false`; otherwise `isEnabled` will be set to `true`.
   Note: this mey or may not also create a different `KeyMapping` object with modified contents than the one supplied,
   and put it into `binding.keyMapping`.
   */
  private func buildNewInputBinding(from keyMapping: KeyMapping, section: InputSection) -> InputBinding {

    var isEnabled: Bool = true
    var displayMessage: String = ""
    var finalMapping: KeyMapping = keyMapping

    if let action = keyMapping.action {
      if keyMapping.rawKey == "default-bindings", action.count == 1 && action[0] == "start" {
        if DebugConfig.logBindingsRebuild {
          log.verbose("Skipping line: \"default-bindings start\"")
        }
        displayMessage = "IINA does not support default-level (\"builtin\") bindings"
        isEnabled = false
      } else if let destinationSectionName = keyMapping.destinationSection {
        /// Special case: does the command contain an explicit input section using curly braces? (Example line: `Meta+K {default} screenshot`)
        if destinationSectionName == section.name {
          /// Drop "{section}" because it is unnecessary and will get in the way of libmpv command execution
          let newRawAction = Array(action.dropFirst()).joined(separator: " ")
          finalMapping = KeyMapping(rawKey: keyMapping.rawKey, rawAction: newRawAction, comment: keyMapping.comment)
          log.verbose("Modifying binding to remove redundant section specifier (\(destinationSectionName.quoted)) for key: \(keyMapping.rawKey.quoted)")
        } else {
          log.verbose("Skipping binding which specifies section \(destinationSectionName.quoted) for key: \(keyMapping.rawKey.quoted)")
          displayMessage = "Adding bindings to other input sections is not supported"  // TODO: localize
          isEnabled = false
        }
      }
    }

    if section.origin == .libmpv && displayMessage.isEmpty {
      // Set default tooltip
      displayMessage = "This key binding was set by a Lua script or via mpv RPC"  // TODO: localize
    }

    if DebugConfig.logBindingsRebuild {
      log.verbose("Adding binding for key: \(keyMapping.rawKey.quoted)")
    }
    return InputBinding(finalMapping, origin: section.origin, srcSectionName: section.name, isEnabled: isEnabled, displayMessage: displayMessage)
  }

}
