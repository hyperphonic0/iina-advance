//
//  ThreeButtonPrompt.swift
//  iina
//
//  Created by Matt Svoboda on 2026-01-09.
//  Copyright © 2026 lhc. All rights reserved.
//

import SwiftUI

fileprivate let spacing1x = 12.0
fileprivate let spacing2x = spacing1x * 2

fileprivate func makeThreeButtonPromptContent(_ key: String, msgArgs: [String], middleBtnArgs: [String],
                                          okAction: @escaping Callback, middleAction: @escaping Callback, cancelAction: @escaping Callback) -> ThreeButtonPromptContent {

  let middleBtnFormat = NSLocalizedString("alert.\(key).middle", comment: "Middle")
  let middleBtnString = String(format: middleBtnFormat, arguments: middleBtnArgs)

  // Dialog title
  let titleKey = "alert.\(key).title"
  let titleFormat = NSLocalizedString(titleKey, comment: titleKey)
  let title = String(format: titleFormat)

  // Dialog body text
  let messageKey = "alert.\(key).message"
  let messageFormat = NSLocalizedString(messageKey, comment: messageKey)
  let message = String(format: messageFormat, arguments: msgArgs)

  // Dialog body text
  let okKey = "alert.\(key).ok"
  let okFormat = NSLocalizedString(okKey, comment: okKey)
  let okString = String(format: okFormat, arguments: [])

  let cancelBtnFormat = NSLocalizedString("alert.\(key).cancel", comment: "Cancel")
  let cancelBtnString = String(format: cancelBtnFormat, arguments: [])

  return ThreeButtonPromptContent(
    title: title,
    message: message,
    primaryTitle: okString,
    middleTitle: middleBtnString,
    cancelTitle: cancelBtnString,
    primaryAction: okAction,
    middleAction: middleAction,
    cancelAction: cancelAction,
  )
}

class ThreeButtonPromptWindow: NSWindow, NSWindowDelegate, ObservableObject {

  init(_ key: String, msgArgs: [String], middleBtnArgs: [String],
       okAction: @escaping Callback, middleAction: @escaping Callback, cancelAction: @escaping Callback) {
    let content = makeThreeButtonPromptContent(key, msgArgs: msgArgs, middleBtnArgs: middleBtnArgs,
                                               okAction: okAction, middleAction: middleAction, cancelAction: cancelAction)
    let hostingView = NSHostingView(rootView: content)

    // Ask SwiftUI for its best fitting size.
    let desiredSize = hostingView.fittingSize
    // Add title bar height and window chrome insets.
    let contentRect = NSRect(origin: .zero, size: desiredSize)

    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered, defer: true)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isReleasedWhenClosed = false  // make it reusable
    self.initialFirstResponder = nil
    self.autorecalculatesKeyViewLoop = false

    self.contentView = hostingView
    hostingView.autoresizesSubviews = false
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    hostingView.addAllConstraintsToFillSuperview()

    // Hide window for now
    self.orderOut(nil)
    self.center()
  }

  func update(_ key: String, msgArgs: [String], middleBtnArgs: [String],
              okAction: @escaping Callback, middleAction: @escaping Callback, cancelAction: @escaping Callback) {
    let content = makeThreeButtonPromptContent(key, msgArgs: msgArgs, middleBtnArgs: middleBtnArgs,
                                               okAction: okAction, middleAction: middleAction, cancelAction: cancelAction)
    let hostingView = NSHostingView(rootView: content)
    self.contentView = hostingView
    hostingView.autoresizesSubviews = false
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    hostingView.addAllConstraintsToFillSuperview()

    self.orderOut(nil)
    self.setContentSize(hostingView.fittingSize)
    self.center()
  }

  override var firstResponder: NSResponder? { nil }
}


fileprivate struct ThreeButtonPromptContent: View {
  let title: String
  let message: String
  let primaryTitle: String
  let middleTitle: String
  let cancelTitle: String
  let primaryAction: Callback
  let middleAction: Callback
  let cancelAction: Callback

  var body: some View {
    VStack(alignment: .leading, spacing: spacing2x) {
      HStack(alignment: .top, spacing: spacing1x) {
        // Alert icon
        Group {
          if let nsImage = NSImage(named: NSImage.cautionName) {
            Image(nsImage: nsImage)
              .resizable()
              .accessibilityHidden(true)
          } else if let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
            Image(nsImage: symbol)
              .resizable()
              .foregroundStyle(.yellow)
              .accessibilityHidden(true)
          } else {
            Image(systemName: "exclamationmark.triangle.fill")
              .resizable()
              .foregroundStyle(.yellow)
              .accessibilityHidden(true)
          }
        }
        .padding(.all, 0)
        .frame(width: 44, height: 44, alignment: .top)

        VStack(alignment: .leading, spacing: spacing2x) {
          Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text(message)
            .font(.body)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

          HStack(alignment: .bottom, spacing: 8) {
            Button(cancelTitle, role: .cancel) {
              cancelAction()
            }
            .fixedSize()
            .controlSize(.large)
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .frame(maxWidth: .infinity)

            Spacer().frame(maxWidth: .infinity)

            Button(middleTitle, role: .destructive) {
              middleAction()
            }
            .fixedSize()
            .controlSize(.large)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button(primaryTitle) {
              primaryAction()
            }
            .fixedSize()
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
          }
          .padding(.all, 0)
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.all, 0)
    }
    .padding(.vertical, spacing1x)
    .padding(.horizontal, spacing2x)
    .frame(minWidth: 550, maxWidth: 550, maxHeight: .infinity, alignment: .center)
    .ignoresSafeArea() // Removes safe area for title bar
  }
}


#Preview {
  ThreeButtonPromptContent(
    title: "Problem Restoring Windows",
    message: "Test Message",
    primaryTitle: "No, Quit",
    middleTitle: "Discard 2 Windows",
    cancelTitle: "Keep Waiting",
    primaryAction: {},
    middleAction: {},
    cancelAction: {}
  )
}
