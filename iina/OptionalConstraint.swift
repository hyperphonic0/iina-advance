//
//  OptionalConstraint.swift
//  iina
//
//  Created by Matt Svoboda on 9/30/25.
//  Copyright © 2025 lhc. All rights reserved.
//

/// Decoarates a single, optional `NSLayoutConstraint` with functions which make it easier to work with given its optional nature.
class OptionalConstraint {
  let identifier: String
  var constraint: NSLayoutConstraint? = nil
  var priorityInt: Int = 1000

  init(_ identifier: String) {
    self.identifier = identifier
  }

  func createIfMissing(_ log: Logger.Subsystem?,_ creationFunc: () -> NSLayoutConstraint) {
    guard !isActive else { return }

    let newConstraint = creationFunc()
    newConstraint.identifier = identifier
    newConstraint.isActive = true
    constraint = newConstraint
  }

  /// This overload exists solely to fix a compiler error complaining about an ambiguous generic type
  func createOrUpdate(to constantToSet: CGFloat = 0, priorityInt: Int? = nil,
                      _ log: Logger.Subsystem?,
                      _ creationFunc: (CGFloat) -> NSLayoutConstraint) {
    let requiredFirstAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor>? = nil  // needed to keep compiler happy
    createOrUpdate(to: constantToSet, priorityInt: priorityInt, requiredFirstAnchor: requiredFirstAnchor, requiredSecondAnchor: nil, log, creationFunc)
  }

  func createOrUpdate<AnchorType>(to constantToSet: CGFloat = 0, priorityInt: Int? = nil,
                                  requiredFirstAnchor: NSLayoutAnchor<AnchorType>? = nil,
                                  requiredSecondAnchor: NSLayoutAnchor<AnchorType>? = nil,
                                  _ log: Logger.Subsystem?,
                                  _ creationFunc: (CGFloat) -> NSLayoutConstraint) {
    if let priorityInt {
      self.priorityInt = priorityInt
    } else {
      self.priorityInt = 1000
    }

    if let constraint, isActive,
       requiredFirstAnchor == nil || (constraint.firstAnchor == requiredFirstAnchor),
       requiredSecondAnchor == nil || (constraint.secondAnchor == requiredSecondAnchor) {
      log?.verbose("Updating constraint \(identifier.quoted) to \(constantToSet) pri=\(self.priorityInt)")
      constraint.priorityInt = self.priorityInt
      constraint.animateToConstant(constantToSet)
    } else {
      remove(log)
      log?.verbose("Creating constraint \(identifier.quoted) const=\(constantToSet) pri=\(self.priorityInt)")
      let newConstraint = creationFunc(constantToSet)
      newConstraint.identifier = identifier
      newConstraint.priorityInt = self.priorityInt
      newConstraint.isActive = true
      constraint = newConstraint
    }
  }

  func remove(_ log: Logger.Subsystem?) {
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
