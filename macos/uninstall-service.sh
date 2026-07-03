#!/usr/bin/env bash
# ttyd-wrapper service uninstaller (launchd LaunchAgent)
set -euo pipefail

LABEL="com.pawprint0706.ttyd-wrapper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -f "$PLIST" ]]; then
    echo "Agent \"$LABEL\" is not installed. Nothing to do."
    exit 0
fi

echo "Unloading and removing agent \"$LABEL\"..."
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "[OK] Agent uninstalled."
