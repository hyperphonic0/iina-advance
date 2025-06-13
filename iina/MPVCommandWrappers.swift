//
//  MPVCommandWrappers.swift
//  iina
//
//  Created by Yuze Jiang on 2025/05/25.
//  Copyright © 2025 lhc. All rights reserved.
//

extension MPVController {
  func playlistInsert(_ path: String, index: Int) -> Int32 {
    command(.loadfile, args: [path, "insert-at", index.description], level: .verbose)
  }

  func playlistAppend(_ path: String) -> Int32 {
    command(.loadfile, args: [path, "append"], level: .verbose)
  }

  func playlistMove(_ from: Int, to: Int) -> Int32 {
    command(.playlistMove, args: ["\(from)", "\(to)"], level: .verbose)
  }

  func playlistRemove(_ index: Int) -> Int32 {
    command(.playlistRemove, args: [index.description], level: .verbose)
  }

}
