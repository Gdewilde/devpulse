#!/bin/bash
# notarize.sh — Notarize a DevPulse .dmg or .app with Apple
# Requires: Apple Developer account, xcrun notarytool credentials stored in keychain
#
# Setup (one-time):
#   xcrun notarytool store-credentials "devpulse-notary" \
#     --apple-id "you@example.com" \
#     --team-id "YOURTEAMID" \
#     --password "app-specific-password"
set -euo pipefail

ARTIFACT="${1:?Usage: notarize.sh <path-to-dmg-or-app>}"
PROFILE="${NOTARY_PROFILE:-devpulse-notary}"

if [[ ! -e "$ARTIFACT" ]]; then
    echo "Error: $ARTIFACT not found"
    exit 1
fi

echo "Notarizing: $ARTIFACT"
echo "Using keychain profile: $PROFILE"

# If it's an .app, zip it first (notarytool requires zip, dmg, or pkg)
SUBMIT_PATH="$ARTIFACT"
CLEANUP=""
if [[ "$ARTIFACT" == *.app ]]; then
    ZIP_PATH="${ARTIFACT%.app}.zip"
    echo "Zipping app bundle..."
    ditto -c -k --keepParent "$ARTIFACT" "$ZIP_PATH"
    SUBMIT_PATH="$ZIP_PATH"
    CLEANUP="$ZIP_PATH"
fi

# Submit for notarization
echo "Submitting to Apple notary service..."
xcrun notarytool submit "$SUBMIT_PATH" \
    --keychain-profile "$PROFILE" \
    --wait

# Staple the ticket to the original artifact
echo "Stapling notarization ticket..."
if [[ "$ARTIFACT" == *.dmg ]] || [[ "$ARTIFACT" == *.app ]]; then
    xcrun stapler staple "$ARTIFACT"
    echo "Stapled successfully."
fi

# Cleanup temp zip
if [[ -n "$CLEANUP" ]]; then
    rm -f "$CLEANUP"
fi

# Verify
echo ""
echo "Verification:"
if [[ "$ARTIFACT" == *.app ]]; then
    spctl --assess --type execute --verbose "$ARTIFACT" 2>&1 || true
fi
echo "Done."
