#!/bin/bash
# release.sh — Cut a new DevPulse release
# Usage: ./release.sh <major|minor|patch>
# Example: ./release.sh patch   →  1.0.0 → 1.0.1
#          ./release.sh minor   →  1.0.1 → 1.1.0
#          ./release.sh major   →  1.1.0 → 2.0.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CURRENT=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# --- Parse bump type ---
BUMP="${1:-}"
if [[ -z "$BUMP" ]]; then
    echo "Usage: ./release.sh <major|minor|patch>"
    echo "Current version: $CURRENT"
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *)     echo "Invalid bump type: $BUMP (use major, minor, or patch)"; exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEW_VERSION}"

echo "=== DevPulse Release ==="
echo "  $CURRENT → $NEW_VERSION"
echo ""

# --- Pre-flight checks ---
echo "Running pre-flight checks..."

# Clean working tree?
if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
    echo "ERROR: Working tree is dirty. Commit or stash changes first."
    git -C "$SCRIPT_DIR" status --short
    exit 1
fi

# On main branch?
BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
    echo "WARNING: You're on '$BRANCH', not 'main'. Continue? (y/N)"
    read -r CONFIRM
    [[ "$CONFIRM" == "y" ]] || exit 1
fi

# Tag doesn't already exist?
if git -C "$SCRIPT_DIR" tag -l "$TAG" | grep -q "$TAG"; then
    echo "ERROR: Tag $TAG already exists."
    exit 1
fi

# --- Build test ---
echo ""
echo "Building to verify compilation..."
cd "$SCRIPT_DIR/DevPulse"
swift build -c release 2>&1 | tail -3
cd "$SCRIPT_DIR"
echo "Build OK."

# --- Bump version ---
echo ""
echo "Bumping VERSION file: $NEW_VERSION"
echo "$NEW_VERSION" > "$VERSION_FILE"

# --- Commit + tag ---
git -C "$SCRIPT_DIR" add VERSION
git -C "$SCRIPT_DIR" commit -m "Release $TAG"
git -C "$SCRIPT_DIR" tag -a "$TAG" -m "DevPulse $NEW_VERSION"

echo ""
echo "Created commit and tag: $TAG"
echo ""

# --- Push ---
echo "Push to origin and trigger release? (y/N)"
read -r CONFIRM
if [[ "$CONFIRM" == "y" ]]; then
    git -C "$SCRIPT_DIR" push origin "$BRANCH"
    git -C "$SCRIPT_DIR" push origin "$TAG"
    echo ""
    echo "Pushed. GitHub Actions will build and publish the release."
    echo "Watch: https://github.com/$(git -C "$SCRIPT_DIR" remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
else
    echo ""
    echo "Not pushed. When ready, run:"
    echo "  git push origin $BRANCH && git push origin $TAG"
fi

echo ""
echo "Done: DevPulse $NEW_VERSION"
