//
//  MPVHookValue.swift
//  iina
//
//  Created by Matt Svoboda on 11/22/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

struct MPVHookValue {
  typealias Block = (@escaping Callback) -> Void

  var id: String?
  var isJavascript: Bool
  var block: Block?
  var jsBlock: JSManagedValue!
  var context: JSContext!

  init(withIdentifier id: String, jsContext context: JSContext, jsBlock block: JSValue, owner: JavascriptAPIMpv) {
    self.id = id
    self.isJavascript = true
    self.jsBlock = JSManagedValue(value: block)
    self.context = context
    context.virtualMachine.addManagedReference(self.jsBlock, withOwner: owner)
  }

  init(withBlock block: @escaping Block) {
    self.isJavascript = false
    self.block = block
  }

  func call(withNextBlock next: @escaping Callback) {
    if isJavascript {
      let block: @convention(block) () -> Void = { next() }
      guard let callback = jsBlock.value else {
        next()
        return
      }
      callback.call(withArguments: [JSValue(object: block, in: context)!])
      if callback.forProperty("constructor")?.forProperty("name")?.toString() != "AsyncFunction" {
        next()
      }
    } else {
      block!(next)
    }
  }
}
