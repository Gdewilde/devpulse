#!/bin/bash
# build.sh — Build, sign, and install DevPulse menu bar app
# Supports: local dev (ad-hoc) and release (Developer ID) signing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/DevPulse"
APP_BUNDLE="$SCRIPT_DIR/build/DevPulse.app"
INSTALL_PATH="/Applications/DevPulse.app"
BUILD_TIME=$(date '+%Y-%m-%d %H:%M:%S')
VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')

# Signing identity: use DEVELOPER_ID env var for release, ad-hoc for dev
SIGN_IDENTITY="${DEVELOPER_ID:--}"
SIGN_MODE="ad-hoc"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_MODE="Developer ID"
fi

echo "Building DevPulse v${VERSION} (${BUILD_TIME})..."
echo "Signing: ${SIGN_MODE}"
cd "$SRC_DIR"

# Build binary — universal if Xcode available, native arch otherwise
if xcrun --find xcbuild &>/dev/null 2>&1; then
    echo "Building universal binary (arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64 2>&1
    BINARY_PATH=".build/apple/Products/Release/DevPulse"
else
    echo "Building native arch (Xcode required for universal)..."
    swift build -c release 2>&1
    BINARY_PATH=".build/release/DevPulse"
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/"

# Copy app icon if it exists
ICON_PATH="$SRC_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/"
fi

# Sync the shared model catalog from the website repo. The website's
# src/data/models.json is the single source of truth; we copy it into
# the app bundle so Swift can load it at launch. If the website repo
# isn't on disk locally, fall back to whatever is already in Resources.
WEBSITE_MODELS_JSON="$SCRIPT_DIR/../devpulse-website/src/data/models.json"
LOCAL_MODELS_JSON="$SRC_DIR/Resources/models.json"
if [[ -f "$WEBSITE_MODELS_JSON" ]]; then
    cp "$WEBSITE_MODELS_JSON" "$LOCAL_MODELS_JSON"
    echo "Synced model catalog from website repo ($(jq -r 'length' "$LOCAL_MODELS_JSON" 2>/dev/null || wc -l < "$LOCAL_MODELS_JSON") entries)"
fi
if [[ -f "$LOCAL_MODELS_JSON" ]]; then
    cp "$LOCAL_MODELS_JSON" "$APP_BUNDLE/Contents/Resources/models.json"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DevPulse</string>
    <key>CFBundleDisplayName</key>
    <string>DevPulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.gj.devpulse</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>DevPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>BuildTimestamp</key>
    <string>${BUILD_TIME}</string>
</dict>
</plist>
EOF

# Code sign
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Dev mode: ad-hoc signing
    codesign --force --deep --sign - "$APP_BUNDLE"
    xattr -cr "$APP_BUNDLE"
else
    # Release mode: Developer ID with hardened runtime
    codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp --deep "$APP_BUNDLE"
fi

# Install locally
echo "Installing to ${INSTALL_PATH}..."
killall DevPulse 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALL_PATH"
cp -r "$APP_BUNDLE" "$INSTALL_PATH"
open "$INSTALL_PATH"

echo ""
echo "Installed and launched: v${VERSION} (${BUILD_TIME})"

# Install CLI symlink — same binary, dispatches via argv to CLI mode.
CLI_TARGET="${INSTALL_PATH}/Contents/MacOS/DevPulse"
for CLI_DIR in /usr/local/bin "$HOME/.local/bin"; do
    if [[ -d "$CLI_DIR" && -w "$CLI_DIR" ]]; then
        ln -sf "$CLI_TARGET" "$CLI_DIR/devpulse"
        echo "CLI: $CLI_DIR/devpulse -> DevPulse.app  (try: devpulse status)"
        break
    fi
done

# Verify universal binary
echo "Architecture: $(lipo -info "$APP_BUNDLE/Contents/MacOS/DevPulse" 2>/dev/null | tail -1)"
