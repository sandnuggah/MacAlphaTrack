#!/bin/sh
# Build the distributable zip for a GitHub release: a universal MacAlphaTrack.app.
# usage: Scripts/make-release.sh 0.1.0   -> build/MacAlphaTrack-0.1.0.zip
set -e
VERSION="${1:?usage: make-release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACALPHATRACK_VERSION="$VERSION" UNIVERSAL=1 "$ROOT/Scripts/make-app.sh" release
ZIP="$ROOT/build/MacAlphaTrack-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle's symlinks, permissions and signature intact.
ditto -c -k --keepParent "$ROOT/build/MacAlphaTrack.app" "$ZIP"
echo "release zip: $ZIP ($(du -h "$ZIP" | cut -f1 | xargs))"
echo "sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
