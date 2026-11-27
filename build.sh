#!/bin/bash
# Builds "THOC Wall.app" into ./build. Pass "install" to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/THOC Wall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos15 \
  -o "$APP/Contents/MacOS/THOC Wall" Sources/*.swift

cp Resources/logo.svg "$APP/Contents/Resources/"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>THOC Wall</string>
  <key>CFBundleDisplayName</key><string>THOC Wall</string>
  <key>CFBundleIdentifier</key><string>be.thehouseofcoaching.wall</string>
  <key>CFBundleExecutable</key><string>THOC Wall</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Steff Vanhaverbeke. Free software under the GNU GPL v3 or later.</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocationUsageDescription</key><string>THOC Wall uses your approximate location to match the colours to sunrise and sunset where you are.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>THOC Wall uses your approximate location to match the colours to sunrise and sunset where you are.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x "THOC Wall" || true
  rm -rf ~/Applications/"THOC Wall.app"
  cp -R "$APP" ~/Applications/
  open ~/Applications/"THOC Wall.app"
  echo "Installed to ~/Applications and launched"
fi
