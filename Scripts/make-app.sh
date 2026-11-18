#!/bin/sh
# Build MacAlphaTrack.app from the SwiftPM products.
# usage: Scripts/make-app.sh [debug|release]   (default release) -> build/MacAlphaTrack.app
set -e
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# The default (swiftbuild) build system intermittently drops objects from the link and
# trips on new files; the classic one is dependable.
swift build --build-system native -c "$CONFIG" --product MacAlphaTrack
BIN="$(swift build --build-system native -c "$CONFIG" --show-bin-path)/MacAlphaTrack"
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

# App icon: compile the Icon Composer package (layered Liquid Glass icon) into Assets.car,
# which also yields AppIcon.icns for older systems, plus the Info.plist keys it needs.
ICON_PLIST="$(mktemp -t macalphatrack-icon).plist"
xcrun actool "$ROOT/Design/icons/AppIcon.icon" --compile "$APP/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target "$MIN_OS" \
  --output-partial-info-plist "$ICON_PLIST" --output-format human-readable-text >/dev/null
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$ICON_PLIST")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$ICON_PLIST")"
rm -f "$ICON_PLIST"
# Menu bar template glyph (1x/2x), loaded by name from the bundle.
cp "$ROOT"/Design/icons/menubar/MenuBarIcon.png "$ROOT"/Design/icons/menubar/MenuBarIcon@2x.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacAlphaTrack</string>
  <key>CFBundleDisplayName</key><string>MacAlphaTrack</string>
  <key>CFBundleIdentifier</key><string>com.macalphatrack.MacAlphaTrack</string>
  <key>CFBundleExecutable</key><string>MacAlphaTrack</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconName</key><string>$ICON_NAME</string>
  <key>CFBundleIconFile</key><string>$ICON_FILE</string>
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
</dict></plist>
PLIST
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "built $APP ($VERSION, $CONFIG, SDK $SDK_VERSION): $(xcrun vtool -show-build "$APP/Contents/MacOS/MacAlphaTrack" | grep -E 'sdk' | xargs)"
