#!/bin/bash
# build.sh — Build, install, and relaunch MemoryHealth menu bar app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/MemoryHealth.app"
APP_BUNDLE="$SCRIPT_DIR/build/MemoryHealth.app"
INSTALL_PATH="/Applications/MemoryHealth.app"
BUILD_TIME=$(date '+%Y-%m-%d %H:%M:%S')
VERSION="1.3"

echo "Building MemoryHealth v${VERSION} (${BUILD_TIME})..."
cd "$SRC_DIR"
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/MemoryHealth" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist — LSUIElement makes it menu-bar-only (no dock icon)
# Build timestamp is embedded so the app can display it
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MemoryHealth</string>
    <key>CFBundleDisplayName</key>
    <string>Memory Health</string>
    <key>CFBundleIdentifier</key>
    <string>com.gj.memory-health</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>MemoryHealth</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>BuildTimestamp</key>
    <string>${BUILD_TIME}</string>
</dict>
</plist>
EOF

# Install to /Applications and relaunch
echo "Installing to ${INSTALL_PATH}..."
killall MemoryHealth 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALL_PATH"
cp -r "$APP_BUNDLE" "$INSTALL_PATH"
open "$INSTALL_PATH"

echo ""
echo "Installed and launched: v${VERSION} (${BUILD_TIME})"
