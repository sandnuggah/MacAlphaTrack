#!/bin/sh
# Build MacAlphaTrack.app from the SwiftPM products.
# usage: Scripts/make-app.sh [debug|release]   (default release) -> build/MacAlphaTrack.app
set -e
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c "$CONFIG" --product MacAlphaTrack
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacAlphaTrack"
APP="$ROOT/build/MacAlphaTrack.app"
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1.0)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/LiveRemoteScript/AlphaTrack"
cp "$BIN" "$APP/Contents/MacOS/MacAlphaTrack"
cp "$ROOT"/LiveRemoteScript/AlphaTrack/*.py "$APP/Contents/Resources/LiveRemoteScript/AlphaTrack/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacAlphaTrack</string>
  <key>CFBundleDisplayName</key><string>MacAlphaTrack</string>
  <key>CFBundleIdentifier</key><string>com.macalphatrack.MacAlphaTrack</string>
  <key>CFBundleExecutable</key><string>MacAlphaTrack</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MacAlphaTrack contributors</string>
</dict></plist>
PLIST
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "built $APP ($VERSION, $CONFIG)"
