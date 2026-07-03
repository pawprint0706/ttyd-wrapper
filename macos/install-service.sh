#!/usr/bin/env bash
# ============================================================
#  ttyd-wrapper service installer (launchd LaunchAgent)
#  Usage:  ./install-service.sh          install + start
#          ./install-service.sh --dry    print rendered plist + commands
#
#  Runs as YOUR user; starts at login (RunAtLoad) and restarts
#  on crash (KeepAlive/SuccessfulExit=false).
# ============================================================
set -euo pipefail

LABEL="com.pawprint0706.ttyd-wrapper"
PORT="${TTYD_PORT:-33322}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INDEX="$ROOT/public/index.html"
TEMPLATE="$SCRIPT_DIR/ttyd-wrapper.plist"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/$LABEL.plist"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/ttyd.log"

DRY=0
[[ "${1:-}" == "--dry" ]] && DRY=1

# ---------- Sanity checks ----------
[[ -f "$INDEX" ]]    || { echo "[ERROR] index.html not found: $INDEX" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "[ERROR] plist template not found: $TEMPLATE" >&2; exit 1; }

TTYD_BIN="$(command -v ttyd || true)"
if [[ -z "$TTYD_BIN" ]]; then
    if [[ "$DRY" == "1" ]]; then
        TTYD_BIN="/opt/homebrew/bin/ttyd"
        echo "[DRY] ttyd not found; assuming $TTYD_BIN"
    else
        echo "[ERROR] ttyd not found. Install it first:" >&2
        echo "        brew install ttyd" >&2
        exit 1
    fi
fi

render() {
    sed -e "s|__TTYD__|$TTYD_BIN|g" \
        -e "s|__PORT__|$PORT|g" \
        -e "s|__INDEX__|$INDEX|g" \
        -e "s|__HOME__|$HOME|g" \
        -e "s|__LOG__|$LOG_FILE|g" \
        "$TEMPLATE"
}

echo
echo "=== ttyd-wrapper service installer (launchd LaunchAgent) ==="
echo "  Plist : $PLIST"
echo "  ttyd  : $TTYD_BIN"
echo "  Index : $INDEX"
echo "  Port  : $PORT"
echo "  Logs  : $LOG_FILE"
echo

if [[ "$DRY" == "1" ]]; then
    echo "[DRY RUN] Rendered plist:"
    render
    echo
    echo "[DRY RUN] Commands that would be executed:"
    echo "  launchctl unload \"$PLIST\"   (if loaded)"
    echo "  launchctl load -w \"$PLIST\""
    exit 0
fi

# ---------- Install (idempotent: unload + overwrite + load) ----------
mkdir -p "$AGENT_DIR" "$LOG_DIR"
launchctl unload "$PLIST" 2>/dev/null || true
render > "$PLIST"
launchctl load -w "$PLIST"

# ---------- Verify ----------
sleep 2
if launchctl list | grep -q "$LABEL"; then
    echo
    echo "[OK] Agent is loaded."
    if command -v curl >/dev/null 2>&1; then
        code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" || true)"
        if [[ "$code" == "200" ]]; then
            echo "[OK] HTTP check passed: http://localhost:$PORT/"
        else
            echo "[WARN] HTTP check returned: $code (see $LOG_FILE)"
        fi
    fi
    echo
    echo "[INFO] macOS may show a firewall prompt on first connection - click Allow."
    echo "Access from mobile: http://<this-machine-ip>:$PORT/"
else
    echo "[ERROR] Agent failed to load. Check $LOG_FILE" >&2
    exit 1
fi
