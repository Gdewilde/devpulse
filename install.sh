#!/bin/bash
# install.sh — Set up automated memory health checks via launchd
# Usage: ./install.sh [--interval MINUTES] [--fix] [--uninstall]

set -euo pipefail

LABEL="com.gj.mem-check"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/mem-check.sh"
LOG_DIR="$HOME/.local/logs/mem-check"

INTERVAL=600  # Default: 10 minutes
AUTO_FIX=false

for arg in "$@"; do
    case "$arg" in
        --interval)  shift; INTERVAL=$(( $1 * 60 )); shift ;;
        --fix)       AUTO_FIX=true ;;
        --uninstall)
            echo "Uninstalling ${LABEL}..."
            launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
            rm -f "$PLIST_PATH"
            echo "Done. Removed launchd job and plist."
            exit 0
            ;;
    esac
done

# Build the script arguments
SCRIPT_ARGS="--quiet"
if [[ "$AUTO_FIX" == true ]]; then
    SCRIPT_ARGS="--quiet --fix"
fi

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$PLIST_PATH")"
chmod +x "$SCRIPT_PATH"

echo "Installing memory health check..."
echo "  Script:   $SCRIPT_PATH"
echo "  Interval: $((INTERVAL / 60)) minutes"
echo "  Auto-fix: $AUTO_FIX"
echo "  Logs:     $LOG_DIR/"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_PATH}</string>
        <string>--quiet</string>
$(if [[ "$AUTO_FIX" == true ]]; then echo "        <string>--fix</string>"; fi)
    </array>
    <key>StartInterval</key>
    <integer>${INTERVAL}</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/launchd-stderr.log</string>
    <key>RunAtLoad</key>
    <true/>
    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Unload if already running, then load
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo ""
echo "Installed and running."
echo ""
echo "Commands:"
echo "  Check status:  launchctl print gui/$(id -u)/${LABEL}"
echo "  Run manually:  ${SCRIPT_PATH}"
echo "  Run with fix:  ${SCRIPT_PATH} --fix"
echo "  View logs:     ls ${LOG_DIR}/"
echo "  Uninstall:     ${SCRIPT_DIR}/install.sh --uninstall"
