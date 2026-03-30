#!/bin/bash
# create-dmg.sh — Create a professional .dmg installer for DevPulse
# Requires: brew install create-dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
APP_BUNDLE="$ROOT_DIR/build/DevPulse.app"
DMG_OUTPUT="$ROOT_DIR/build/DevPulse-${VERSION}-universal.dmg"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: $APP_BUNDLE not found. Run build.sh first."
    exit 1
fi

# Check for create-dmg
if ! command -v create-dmg &>/dev/null; then
    echo "Installing create-dmg..."
    brew install create-dmg
fi

echo "Creating DMG for DevPulse v${VERSION}..."

# Prepare staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "$APP_BUNDLE" "$STAGING_DIR/"

# Remove any existing DMG
rm -f "$DMG_OUTPUT"

# Create DMG with drag-to-Applications layout
create-dmg \
    --volname "DevPulse ${VERSION}" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 80 \
    --icon "DevPulse.app" 180 170 \
    --hide-extension "DevPulse.app" \
    --app-drop-link 480 170 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$STAGING_DIR/" \
    || true  # create-dmg exits 2 on "DMG created" which is fine

# Cleanup
rm -rf "$STAGING_DIR"

if [[ -f "$DMG_OUTPUT" ]]; then
    echo ""
    echo "DMG created: $DMG_OUTPUT"
    echo "Size: $(du -h "$DMG_OUTPUT" | cut -f1)"

    # Sign DMG if Developer ID is available
    if [[ -n "${DEVELOPER_ID:-}" ]]; then
        echo "Signing DMG..."
        codesign --sign "$DEVELOPER_ID" --timestamp "$DMG_OUTPUT"
        echo "DMG signed."
    fi
else
    echo "Error: DMG creation failed"
    exit 1
fi
