<p align="center">
<img height="256" src="https://github.com/iina/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/iina-icon-256.png">
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

  - Tips:
    - Change the URL in the shell script if you want to download architecture-specific binaries. By default, it will download the universal ones. You can download other binaries by using `--arch <ARCH>` (universal, arm64, or amd64).
    - The script downloads files using parallel downloads to speed up the process (5 parallel downloads by default). You can change this by using `--parallel <X>` (from 1 to...).
    - If you want to build an older IINA version, make sure to download the corresponding dylibs. For example, `https://iina.io/dylibs/1.2.0/universal/fileList.txt`.

2. Open iina.xcodeproj in the [latest public version of Xcode](https://apps.apple.com/app/xcode/id497799835). *IINA may not build if you use any other version.*

3. Build the project.

### Building mpv manually

1. Build your own copy of mpv. If you're using a package manager to manage dependencies, the steps below outline the process.

	#### With Homebrew

	Use our tap as it passes in the correct flags to mpv's configure script:

	```console
	brew tap iina/homebrew-mpv-iina
	brew install mpv-iina
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

Contributions to IINA Advance are absolutely welcome. For now, please feel free to file an issue, feature request, or submit a PR at the [GitHub page](https://github.com/svobs/iina-advance)
