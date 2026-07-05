#!/usr/bin/env bash
# ============================================================
#  ttyd-wrapper service installer (systemd user unit)
#  Usage:  ./install-service.sh          interactive install + start
#          ./install-service.sh --dry    print rendered unit + commands
#
#  Runs as YOUR user (no root needed for the service itself).
#  loginctl enable-linger makes it start at boot without login.
#
#  Interactive: you are asked whether to enable each optional feature
#  (persistent session / HTTPS / login). Non-interactive runs (piped
#  stdin or --dry) fall back to env vars:
#    TTYD_TMUX=0            disable persistent session
#    TTYD_CRED=user:pass    enable login (basic auth)
#    TTYD_SSL_CERT=...  TTYD_SSL_KEY=...   enable HTTPS
#  Required packages are checked against your choices BEFORE install;
#  if missing, the script tells you what to install and exits.
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

# ---------- Detect what is installed ----------
TTYD_BIN="$(command -v ttyd || true)"
HAVE_TMUX=0; command -v tmux >/dev/null 2>&1 && HAVE_TMUX=1

# ---------- Feature selection ----------
ask_yn() {  # $1=prompt  $2=default(Y|N) -> returns 0 for yes
    local ans hint
    if [[ "$2" == "Y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
    read -r -p "$1 $hint " ans || true
    ans="${ans:-$2}"
    [[ "$ans" =~ ^[Yy] ]]
}

if [[ "$DRY" == "0" && -t 0 ]]; then
    echo
    echo "=== Configure ttyd-wrapper (Enter = default) ==="
    echo
    echo "[Session persistence] tmux keeps your shell (and running programs) alive"
    echo "  across disconnects; reconnecting restores it and multiple devices mirror"
    echo "  the same session. Requires the 'tmux' package."
    if ask_yn "  Enable persistent session?" Y; then ENABLE_TMUX=1; else ENABLE_TMUX=0; fi
    echo
    echo "[HTTPS/TLS] Encrypts traffic. Required for safe public exposure and for PWA"
    echo "  home-screen install. Needs a certificate + key (e.g. Let's Encrypt via"
    echo "  acme.sh/certbot with a DDNS domain)."
    if ask_yn "  Enable HTTPS?" N; then
        ENABLE_HTTPS=1
        read -r -p "    Certificate (fullchain) path: " SSL_CERT || true
        read -r -p "    Private key path: " SSL_KEY || true
    else ENABLE_HTTPS=0; fi
    echo
    echo "[Login] Single account (HTTP basic auth), usable from several devices at once."
    echo "  Credentials are sent base64 (effectively plaintext) - pair with HTTPS."
    if ask_yn "  Enable login?" N; then
        ENABLE_AUTH=1
        read -r -p "    Username: " _lu || true
        read -r -s -p "    Password: " _lp || true; echo
        CRED="${_lu:-}:${_lp:-}"
    else ENABLE_AUTH=0; fi
    echo
else
    # Non-interactive / --dry: derive from environment.
    ENABLE_TMUX=1; [[ "${TTYD_TMUX:-1}" == "0" ]] && ENABLE_TMUX=0
    ENABLE_HTTPS=0; [[ -n "$SSL_CERT" && -n "$SSL_KEY" ]] && ENABLE_HTTPS=1
    ENABLE_AUTH=0;  [[ -n "$CRED" ]] && ENABLE_AUTH=1
fi

# ---------- Pre-flight: required packages for the chosen features ----------
missing=()
[[ -z "$TTYD_BIN" ]] && missing+=("ttyd")
[[ "$ENABLE_TMUX" == "1" && "$HAVE_TMUX" == "0" ]] && missing+=("tmux")
if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ "$DRY" == "1" ]]; then
        echo "[DRY] missing package(s): ${missing[*]} (a real install would stop here)"
        [[ -z "$TTYD_BIN" ]] && TTYD_BIN="/usr/bin/ttyd"
    else
        echo "[ERROR] Required package(s) not installed for your choices: ${missing[*]}" >&2
        echo "        Install them first, then re-run this installer:" >&2
        echo "          sudo apt install ${missing[*]}     # (or your distro's package manager)" >&2
        [[ " ${missing[*]} " == *" ttyd "* ]] && echo "          ttyd releases: https://github.com/tsl0922/ttyd/releases" >&2
        exit 1
    fi
fi

# ---------- Pre-flight: HTTPS certificate files ----------
if [[ "$ENABLE_HTTPS" == "1" ]]; then
    if [[ -z "$SSL_CERT" || -z "$SSL_KEY" ]]; then
        echo "[ERROR] HTTPS enabled but certificate/key path was not provided." >&2
        exit 1
    fi
    if [[ "$DRY" == "0" && ( ! -f "$SSL_CERT" || ! -f "$SSL_KEY" ) ]]; then
        echo "[ERROR] Certificate or key file not found:" >&2
        [[ ! -f "$SSL_CERT" ]] && echo "          cert: $SSL_CERT" >&2
        [[ ! -f "$SSL_KEY"  ]] && echo "          key : $SSL_KEY"  >&2
        echo "        Obtain a cert first (e.g. acme.sh/certbot + a DDNS domain), then re-run." >&2
        exit 1
    fi
fi

# ---------- Compose ttyd args from the chosen features ----------
SCHEME="http"
if [[ "$ENABLE_TMUX" == "1" ]]; then CMD="tmux new -A -s $SESSION"; else CMD="bash -l"; fi
ARGS="--writable -t platform=linux"
[[ "$ENABLE_AUTH" == "1" && -n "$CRED" ]] && ARGS="$ARGS -c \"$CRED\""
if [[ "$ENABLE_HTTPS" == "1" ]]; then
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
echo "  Unit    : $UNIT_FILE"
echo "  ttyd    : $TTYD_BIN"
echo "  Index   : $INDEX"
echo "  Port    : $PORT"
echo "  Session : $([[ "$ENABLE_TMUX" == "1" ]] && echo "tmux ($SESSION) - persistent" || echo "login shell - not persistent")"
echo "  Login   : $([[ "$ENABLE_AUTH" == "1" ]] && echo enabled || echo disabled)"
echo "  HTTPS   : $([[ "$ENABLE_HTTPS" == "1" ]] && echo "enabled ($SCHEME)" || echo disabled)"
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
