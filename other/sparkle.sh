#!/bin/bash

# Run this script to publish a new release to the Sparkle appcast directory.
# 0. `cd` to the directory containing this script before running.
# 1. Make sure Sparkle exists inside this directory also (see SPARKLE_HOME below).
# 2. This script will compress the latest version of the app, generate deltas, place
#    it inside the appcast directory, and write a new version of appcast.xml.
# 3. After script completes, upload new/updated files to AWS update server.

if [ "$#" -ne 2 ]; then
  echo "Usage: ./sparkle.sh newVersion_appPath newVersionNumber"
  echo "Example: ./sparkle.sh \"./IINA Advance.app\" \"1.4.3\""
  exit 1
fi

## Script params ##

# Full path to the latest version, uncompressed (*.app)
NEW_VERSION_APP_PATH="$1"
# Latest marketing version (e.g., "1.4.3"
NEW_VERSION="$2"

## Less frequently updated vars ##

# TODO: support running this script from any dir instead 
WORKING_DIR="."
SPARKLE_HOME="$WORKING_DIR/Sparkle-2.6.4"

# This is the Sparkle Appcast director
# 1. May already contain files (backup before running!):
#   - Binaries for some previosus versions ("IINA-Advance-${VER}.zip")
#   - Release notes for those versions ("IINA-Advance-${VER}.html")
#   - appcast.xml (but will be overwritten by this script!)
#   - Delta updates ("IINA-Advance-{N}-{M}.delta")
# 2. Prior to running this script, place the .html for the latest version in this dir
#    (should be named "IINA-Advance-${NEW_VERSION}.html").
APPCAST_DIR="$WORKING_DIR/AppCast"

ZIP_PATH="$WORKING_DIR/IINA-Advance-$NEW_VERSION.zip"
MAX_VERSIONS=10

# Creates Mac-friendly zip archive
ditto -c -k --sequesterRsrc --keepParent "$NEW_VERSION_APP_PATH" "$ZIP_PATH"

mv "$ZIP_PATH" "$APPCAST_DIR/"
"$SPARKLE_HOME/bin/generate_appcast" --maximum-versions $MAX_VERSIONS \
		--maximum-deltas $MAX_VERSIONS \
		"$APPCAST_DIR"
