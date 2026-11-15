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
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MIN_OS="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/LiveRemoteScript/AlphaTrack"
cp "$BIN" "$APP/Contents/MacOS/MacAlphaTrack"
# SwiftPM links against the current SDK but records the deployment target as the SDK
# version in LC_BUILD_VERSION. AppKit decides whether an app gets the current design
# (Liquid Glass window chrome, new window controls) from that recorded SDK version, so
# stamp the real one or the app runs in pre-macOS-26 compatibility mode.
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/MacAlphaTrack" "$APP/Contents/MacOS/MacAlphaTrack"
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
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>DTSDKName</key><string>macosx$SDK_VERSION</string>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MacAlphaTrack contributors</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.macalphatrack.MacAlphaTrack</string>
    <key>CFBundleURLSchemes</key><array><string>macalphatrack</string></array>
  </dict></array>
</dict></plist>
PLIST
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "built $APP ($VERSION, $CONFIG, SDK $SDK_VERSION): $(xcrun vtool -show-build "$APP/Contents/MacOS/MacAlphaTrack" | grep -E 'sdk' | xargs)"
