//
//  FreeSelectingViewController.swift
//  iina
//
//  Created by lhc on 5/9/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

/** Currently only for adding delogo filters. */
class FreeSelectingViewController: CropBoxViewController {

  @IBAction func doneBtnAction(_ sender: AnyObject) {
    let player = pwc.player

    let filter = MPVFilter.init(lavfiName: "delogo", label: Constants.FilterLabel.delogo, paramDict: [
      "x": String(self.cropx),
      "y": String(self.cropy),
      "w": String(self.cropw),
      "h": String(self.croph)
    ])
    player.mpv.queue.async {
      if let existingFilter = player.info.delogoFilter {
        player.removeVideoFilter(existingFilter)
      }
      guard player.addVideoFilter(filter) else {
        DispatchQueue.main.async {
          Utility.showAlert("filter.incorrect")
        }
        return
      }
      player.info.delogoFilter = filter
      DispatchQueue.main.async { [self] in
        pwc.exitInteractiveMode()
      }
    }
  }

  @IBAction func cancelBtnAction(_ sender: AnyObject) {
    pwc.exitInteractiveMode()
  }

  override func handleKeyDown(mpvKeyCode: String) {
    switch mpvKeyCode {
    case "ESC":
      cancelBtnAction(self)
    case "ENTER":
      doneBtnAction(self)
    default:
      break
    }
  }

}
