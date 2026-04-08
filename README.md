<p align="center">
<img height="256" src="https://raw.githubusercontent.com/svobs/iina-advance/advance-develop/iina/Assets.xcassets/AppIcon.appiconset/icon_512x512.png">
</p>

<h1 align="center">IINA Advance</h1>

<p align="center">
<b><a href="https://github.com/iina/iina">IINA</a></b> is the modern video player for macOS.<br/>
<b>Advance</b>, as in, <i>advance preview</i> of new or experimental features.<br/>
Or maybe an attempt to <i>advance</i> IINA development more rapidly.
</p>

This project has come a long way from its beginning. But the work continues!

Stable binaries with detailed release notes can be found on the <a href="https://github.com/svobs/iina-advance/releases/">IINA Advance Releases</a> page.

A main goal of IINA Advance is to retain as many of IINA's features and options as possible, while adding new useful features or expanding existing ones. If you find something which looks missing or broken, please [report an issue](https://github.com/svobs/iina-advance/issues).


---
## Improvements from upstream IINA

* Can restore all its open windows and state when reopening the app.
* A revamped, more animated on-screen controller for a more responsive feel and fresh appearance, with more customization options such as the ability to change its size.
* The ability (when configured) to increase the window size in an arbitrary way instead of being confined to the video's aspect ratio.
* A new "custom" window mode which supports sharp corners, and seamless integration with the "custom full screen" mode.
* Can show a sidebar on the left side, instead of or in addition to the right sidebar.
* A new "inside vs. outside" layout paradigm, where the sidebars, "top", & "bottom" panels, can individually be configured to be displayed either as:
  *  "Inside": shown as a traditional overlay on top of the video, with options to control how they will be hidden again.
  *  "Outside": the panel does not overlap the video. Top and/or bottom panels do not auto-hide when in this mode.
* Smooth animations wherever possible when switching between various modes (such as to/from music mode), and window handling in general, made possible by a new window layout system.
* Improved & optimized thumbnail handling with more options, including the ability to show thumbnails of any size.
* A massive rewrite of the key bindings handling system, which supports bindings being set by Lua scripts, as well as mpv "key sequences". The Key Bindings editor is enhanced with color coding & status icons, + detection of conflicting bindings, as well as supporting copy/paste, undo/redo, & drag & drop.
* Tons of bug fixes and other enhancements under the hood.


## (Optional) How to copy history & settings from upstream IINA
At present, IINA Advance retains IINA's history database format and shares most of the same settings as IINA, so each should be able to use the other's files without harm. However, because the two apps have different bundle IDs, they store their support files in separate locations and do not share them.

For those who have been using IINA previously and want to copy over its settings, history, and other state, copy each location in the first column below to the location in the second column:

|                       | IINA                                                 | IINA Advance                                      |
|-----------------------|------------------------------------------------------|---------------------------------------------------|
| Primary settings file | `~/Library/Preferences/com.colliderli.iina.plist`    | `~/Library/Preferences/com.iina-advance.plist`    |
| Other support files   | `~/Library/Application Support/com.colliderli.iina` | `~/Library/Application Support/com.iina-advance` |


## Building
*(unchanged from the upstream IINA project)*

IINA uses mpv for media playback. To build IINA, you can either fetch copies of these libraries we have already built (using the instructions below) or build them yourself by skipping to [these instructions](#building-mpv-manually).

### Using the pre-compiled libraries

1. Download pre-compiled libraries by running

```console
./other/download_libs.sh
```

> [!TIP]
> - Change the URL in the shell script if you want to download arch-specific binaries. By default, it will download the universal ones. You can download other binaries from `https://iina.io/dylibs/${ARCH}/filelist.txt` where `ARCH` can be `universal`, `arm64` and `x86_64`.
> - If you want to build an older IINA version, make sure to download the corresponding dylibs. For example, `https://iina.io/dylibs/1.2.0/universal/filelist.txt`.

2. Open iina.xcodeproj in the [latest public version of Xcode](https://apps.apple.com/app/xcode/id497799835). *IINA may not build if you use any other version.*

3. Build the project.

### Building mpv manually

1. Build your own copy of mpv. If you're using a package manager to manage dependencies, the steps below outline the process.

	#### With Homebrew

	Use our tap as it passes in the correct flags to mpv's configure script:

	```console
	brew tap iina/homebrew-mpv-iina
	brew install --HEAD mpv-iina
	```

	#### With MacPorts

	Pass in these flags when installing:

	```console
	port install mpv +uchardet -bundle -rubberband configure.args="--enable-libmpv-shared --enable-lua --enable-libarchive --enable-libbluray --disable-swift --disable-rubberband"
	```

2. Copy the corresponding mpv and FFmpeg header files into `deps/include/`, replacing the current ones. You can find them on GitHub [(e.g. mpv)](https://github.com/mpv-player/mpv/tree/master/libmpv), but it's recommended to copy them from the Homebrew or MacPorts installation. Always make sure the header files have the same version of the dylibs.

3. Run `other/parse_doc.rb`. This script will fetch the latest mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. Copy them from `other/` to `iina/`, replacing the current files. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

4. Run `other/change_lib_dependencies.rb`. This script will deploy the dependent libraries into `deps/lib`. If you're using a package manager to manage dependencies, invoke it like so:

	#### With Homebrew

	```console
	other/change_lib_dependencies.rb "$(brew --prefix)" "$(brew --prefix mpv-iina)/lib/libmpv.dylib"
	```

	#### With MacPorts

	```console
	port contents mpv | grep '\.dylib$' | xargs other/change_lib_dependencies.rb /opt/local
	```

5. Open `iina.xcodeproj` in the [latest public version of Xcode](https://apps.apple.com/app/xcode/id497799835). *IINA may not build if you use any other version.*

6. Remove all references to `.dylib` files from the Frameworks group in the sidebar and add all the `.dylib` files in `deps/lib` to that group by clicking  "Add Files to iina..." in the context menu.

7. Add all the imported `.dylib` files into the "Copy Dylibs" phase under "Build Phases" tab of the iina target.

8. Make sure the necessary `.dylib` files are present in the "Link Binary With Libraries" phase under "Build Phases". Xcode should have already added all dylibs under this section.

9. Build the project.

## Contributing
*(Working to expand this section)*

Fixes and improvements to IINA Advance are more than welcome. For now, please feel free to file an issue, feature request, or submit a PR at the [GitHub page](https://github.com/svobs/iina-advance)

## IINA Plugins List
*(copied from upstream IINA)*

### Official Plugins
- **[More Seeking](https://github.com/iina/plugin-more-seeking)** (`iina/plugin-more-seeking`) - Advanced seeking controls.
- **[Online Media](https://github.com/iina/plugin-online-media)** (`iina/plugin-online-media`) - Enhances online streaming and downloading.
- **[OpenSubtitles](https://github.com/iina/plugin-opensub)** (`iina/plugin-opensub`) - Search and download subtitles.
- **[User Scripts](https://github.com/iina/plugin-userscript)** (`iina/plugin-userscript`) - Run custom JavaScript snippets.

### Community Plugins
- **[Bookmarks](https://github.com/wyattowalsh/iina-plugin-bookmarks)** (`wyattowalsh/iina-plugin-bookmarks`) - Save and manage video timestamps.
- **[Clickable Subtitles](https://github.com/kerim/iina-clickable-subtitles)** (`kerim/iina-clickable-subtitles`) - Click subtitles to define words (macOS Look Up).
- **[Danmaku](https://github.com/xjbeta/iina-plugin-danmaku)** (`xjbeta/iina-plugin-danmaku`) - Overlay comments/danmaku on video.
- **[Danmaku Cosmos](https://github.com/karappo-yu/iina-plugin-danmaku-cosmos)** (`karappo-yu/iina-plugin-danmaku-cosmos`) - Niconico/Bilibili danmaku with CSS/Canvas dual rendering, Comment Art support.
- **[File Viewer](https://github.com/qktechies/iina-plugin-file-viewer)** (`qktechies/iina-plugin-file-viewer`) - bookmark folders, browse directory contents, and play video files directly within IINA.
- **[Jellyfin](https://github.com/mhajder/iina-jellyfin)** (`mhajder/iina-jellyfin`) - Browse and play media from Jellyfin servers.
- **[Jump to Frame](https://github.com/bbeny123/iina-jump-to-frame)** (`bbeny123/iina-jump-to-frame`) - Navigate video by specific frame number.
- **[ListenBrainz Scrobbler](https://git.notfire.cc/notfire/iina-listenbrainz)** - Scrobble your music to ListenBrainz.
- **[Multiple Clips](https://github.com/karthisnk/multi-cutter-iina)** (`karthisnk/multi-cutter-iina`) - multiple clip of a video using ffmpeg, with Batch Clipping, Vertical Clip, Format Selection, Preview Clip.
- **[PiP Toggle for IINA](https://github.com/nastarandarjani/iina-pip-toggle)** (`nastarandarjani/iina-pip-toggle`) - Simple plugin to toggle Picture-in-Picture (PiP) to fullscreen.
- **[PolyScript](https://github.com/SammoMichael/polyplugin-release)** (`SammoMichael/polyplugin-release`) - Dual subtitles, hover dictionary, and AI-assisted translation for language learning.
- **[recorder](https://github.com/5thDimensionalVader/recorder-iina)** (`5thDimensionalVader/recorder-iina`) - to clip a video using ffmpeg.

> 💡 **Want to build your own plugin?**
> 
> Explore the existing plugins listed here to learn how they work. If you create a new plugin or improve an existing one, feel free to contribute back by adding it to this list via a pull request.

> 🚀 **Interested in creating an IINA plugin?**
> 
> Start by exploring the existing plugins here to understand patterns and best practices. Once you’ve built your own plugin, please contribute back by adding it to this README so others can discover and use it.
