//
//  OptionalConstraint.swift
//  iina
//
//  Created by Matt Svoboda on 9/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

fileprivate let defaultPriority: Int = 1000

/// Decoarates a single, optional `NSLayoutConstraint` with functions which make it easier to work with given its optional nature.
class OptionalConstraint {
  let identifier: String
  var constraint: NSLayoutConstraint? = nil

  init(_ identifier: String) {
    self.identifier = identifier
  }

  @MainActor
  func weaken() {
    constraint?.priorityInt = 1
  }

  @MainActor
  func createIfMissing(_ log: (any Logger.Subsystem)?,_ creationFunc: () -> NSLayoutConstraint) {
    guard !isActive else { return }

    let newConstraint = creationFunc()
    newConstraint.identifier = identifier
    newConstraint.isActive = true
    constraint = newConstraint
  }

  /// This overload exists solely to fix a compiler error complaining about an ambiguous generic type
  @MainActor
  func createOrUpdate(to constantToSet: CGFloat = 0, priorityInt: Int = defaultPriority,
                      _ log: (any Logger.Subsystem)?,
                      _ creationFunc: (CGFloat) -> NSLayoutConstraint) {
    let requiredFirstAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor>? = nil  // needed to keep compiler happy
    createOrUpdate(to: constantToSet, priorityInt: priorityInt, requiredFirstAnchor: requiredFirstAnchor, requiredSecondAnchor: nil, log, creationFunc)
  }

  @MainActor
  func createOrUpdate<AnchorType>(to constantToSet: CGFloat = 0, priorityInt: Int = defaultPriority,
                                  requiredFirstAnchor: NSLayoutAnchor<AnchorType>? = nil,
                                  requiredSecondAnchor: NSLayoutAnchor<AnchorType>? = nil,
                                  _ log: (any Logger.Subsystem)?,
                                  _ creationFunc: (CGFloat) -> NSLayoutConstraint) {

    if let constraint, isActive,
       requiredFirstAnchor == nil || (constraint.firstAnchor == requiredFirstAnchor),
       requiredSecondAnchor == nil || (constraint.secondAnchor == requiredSecondAnchor) {
      log?.verbose("Updating constraint \(identifier.quoted): pri=\(priorityInt) const=\(Int(constantToSet))")
      constraint.priorityInt = priorityInt
      constraint.animateToConstant(constantToSet)
    } else {
      remove(log)  // Remove previous constraint if required anchors do not match
      log?.verbose("Creating constraint \(identifier.quoted): pri=\(priorityInt) const=\(Int(constantToSet))")
      let newConstraint = creationFunc(constantToSet)
      newConstraint.identifier = identifier
      newConstraint.priorityInt = priorityInt
      newConstraint.isActive = true
      constraint = newConstraint
    }
  }

  func remove(_ log: (any Logger.Subsystem)?) {
    guard let constraint, constraint.isActive else { return }
    log?.verbose("Removing constraint \(identifier.quoted)")
    constraint.isActive = false
  }

  var isActive: Bool {
    get {
      if let constraint {
        return constraint.isActive
      }
      return false
    }
  }
  
}
