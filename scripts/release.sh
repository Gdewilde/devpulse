#!/bin/bash
# release.sh — Full release pipeline: build → sign → DMG → notarize → GitHub Release
# Usage: DEVELOPER_ID="Developer ID Application: ..." ./scripts/release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
DMG_NAME="DevPulse-${VERSION}-universal.dmg"
DMG_PATH="$ROOT_DIR/build/$DMG_NAME"

echo "================================================"
echo "  DevPulse Release v${VERSION}"
echo "================================================"
echo ""

# Pre-flight checks
if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not found. Install with: brew install gh"
    exit 1
fi

if [[ -z "${DEVELOPER_ID:-}" ]]; then
    echo "Warning: DEVELOPER_ID not set. Building with ad-hoc signing."
    echo "         Set DEVELOPER_ID for a proper release."
    echo ""
fi

# Step 1: Build universal binary + app bundle
echo "[1/6] Building universal binary..."
cd "$ROOT_DIR"
bash build.sh

# Step 2: Create DMG
echo ""
echo "[2/6] Creating DMG..."
bash scripts/create-dmg.sh

# Step 3: Notarize (if Developer ID is set)
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo ""
    echo "[3/6] Notarizing..."
    bash scripts/notarize.sh "$DMG_PATH"
else
    echo ""
    echo "[3/6] Skipping notarization (no Developer ID)"
fi

# Step 4: Verify
echo ""
echo "[4/6] Verifying..."
lipo -info "$ROOT_DIR/build/DevPulse.app/Contents/MacOS/DevPulse"
echo "DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# Step 5: Git tag
echo ""
echo "[5/6] Creating git tag v${VERSION}..."
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "Tag v${VERSION} already exists. Skipping."
else
    git tag -a "v${VERSION}" -m "Release v${VERSION}"
    echo "Tagged v${VERSION}"
fi

# Step 6: GitHub Release
echo ""
echo "[6/6] Creating GitHub Release..."
if gh release view "v${VERSION}" >/dev/null 2>&1; then
    echo "Release v${VERSION} already exists. Uploading DMG..."
    gh release upload "v${VERSION}" "$DMG_PATH" --clobber
else
    gh release create "v${VERSION}" "$DMG_PATH" \
        --title "DevPulse v${VERSION}" \
        --generate-notes
fi

echo ""
echo "================================================"
echo "  Release v${VERSION} complete!"
echo "================================================"
echo ""
echo "DMG: $DMG_PATH"
echo "GitHub: $(gh release view "v${VERSION}" --json url -q .url 2>/dev/null || echo 'check GitHub')"
echo ""
echo "Next steps:"
echo "  1. Update Homebrew cask with new version and sha256"
echo "  2. Update website download links"
echo "  3. Push appcast.xml for Sparkle auto-updates"
