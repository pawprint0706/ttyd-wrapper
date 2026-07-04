#!/usr/bin/env bash
# ============================================================
#  ttyd-wrapper service installer (systemd user unit)
#  Usage:  ./install-service.sh          install + start
#          ./install-service.sh --dry    print rendered unit + commands
#
#  Runs as YOUR user (no root needed for the service itself).
#  loginctl enable-linger makes it start at boot without login.
# ============================================================
set -euo pipefail

SERVICE_NAME="ttyd-wrapper"
PORT="${TTYD_PORT:-33322}"
CRED="${TTYD_CRED:-}"
SSL_CERT="${TTYD_SSL_CERT:-}"
SSL_KEY="${TTYD_SSL_KEY:-}"
SESSION="${TTYD_SESSION:-ttyd}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INDEX="$ROOT/public/index.html"
TEMPLATE="$SCRIPT_DIR/$SERVICE_NAME.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_FILE="$UNIT_DIR/$SERVICE_NAME.service"

DRY=0
[[ "${1:-}" == "--dry" ]] && DRY=1

# ---------- Sanity checks ----------
[[ -f "$INDEX" ]]    || { echo "[ERROR] index.html not found: $INDEX" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "[ERROR] unit template not found: $TEMPLATE" >&2; exit 1; }

TTYD_BIN="$(command -v ttyd || true)"
if [[ -z "$TTYD_BIN" ]]; then
    if [[ "$DRY" == "1" ]]; then
        TTYD_BIN="/usr/bin/ttyd"
        echo "[DRY] ttyd not found; assuming $TTYD_BIN"
    else
        echo "[ERROR] ttyd not found. Install it first:" >&2
        echo "        sudo apt install ttyd" >&2
        echo "        (or download a release: https://github.com/tsl0922/ttyd/releases)" >&2
        exit 1
    fi
fi

# ---------- Compose ttyd args (auth / SSL / persistent session) ----------
SCHEME="http"
if [[ "${TTYD_TMUX:-1}" != "0" ]] && command -v tmux >/dev/null 2>&1; then
    CMD="tmux new -A -s $SESSION"
else
    CMD="bash -l"
fi
ARGS="--writable -t platform=linux"
[[ -n "$CRED" ]] && ARGS="$ARGS -c \"$CRED\""
if [[ -n "$SSL_CERT" && -n "$SSL_KEY" ]]; then
    ARGS="$ARGS -S -C \"$SSL_CERT\" -K \"$SSL_KEY\""
    SCHEME="https"
fi
ARGS="$ARGS -p $PORT -I \"$INDEX\" --cwd \"$HOME\" $CMD"

render() {
    sed -e "s|__TTYD__|$TTYD_BIN|g" \
        -e "s|__ARGS__|$ARGS|g" \
        "$TEMPLATE"
}

echo
echo "=== ttyd-wrapper service installer (systemd user unit) ==="
echo "  Unit  : $UNIT_FILE"
echo "  ttyd  : $TTYD_BIN"
echo "  Index : $INDEX"
echo "  Port  : $PORT"
echo "  Cmd   : $CMD"
echo "  Auth  : $([[ -n "$CRED" ]] && echo enabled || echo none)   SSL: $SCHEME"
echo

if [[ "$DRY" == "1" ]]; then
    echo "[DRY RUN] Rendered unit:"
    render
    echo
    echo "[DRY RUN] Commands that would be executed:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable --now $SERVICE_NAME"
    echo "  loginctl enable-linger $USER"
    exit 0
fi

command -v systemctl >/dev/null 2>&1 || { echo "[ERROR] systemctl not found (systemd required)" >&2; exit 1; }

# ---------- Install (idempotent: overwrite + restart) ----------
mkdir -p "$UNIT_DIR"
render > "$UNIT_FILE"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"

# Start at boot without an interactive login
if loginctl enable-linger "$USER" 2>/dev/null; then
    echo "Linger enabled: service starts at boot without login."
else
    echo "[WARN] Could not enable linger. Run manually: sudo loginctl enable-linger $USER"
fi

# Firewall (best effort, non-fatal)
if command -v ufw >/dev/null 2>&1 && sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo -n ufw allow "$PORT/tcp" >/dev/null 2>&1 && echo "ufw rule added for TCP $PORT"
else
    echo "[INFO] If a host firewall is active, allow TCP $PORT manually."
fi

# ---------- Verify ----------
sleep 2
if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    echo
    echo "[OK] Service is running."
    if command -v curl >/dev/null 2>&1; then
        code="$(curl -sk -m 5 -o /dev/null -w '%{http_code}' "$SCHEME://localhost:$PORT/" || true)"
        if [[ "$code" == "200" ]]; then
            echo "[OK] HTTP check passed: $SCHEME://localhost:$PORT/"
        else
            echo "[WARN] HTTP check returned: $code"
        fi
    fi
    echo
    echo "Access from mobile: $SCHEME://<this-machine-ip>:$PORT/"
else
    echo "[ERROR] Service failed to start. Logs:" >&2
    echo "        journalctl --user -u $SERVICE_NAME -n 50" >&2
    exit 1
fi
