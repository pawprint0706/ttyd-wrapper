#!/usr/bin/env bash
# ============================================================
#  ttyd-wrapper service installer (launchd LaunchAgent)
#  Usage:  ./install-service.sh          interactive install + start
#          ./install-service.sh --dry    print rendered plist + commands
#
#  Runs as YOUR user; starts at login (RunAtLoad) and restarts
#  on crash (KeepAlive/SuccessfulExit=false).
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

LABEL="com.pawprint0706.ttyd-wrapper"
PORT="${TTYD_PORT:-33322}"
CRED="${TTYD_CRED:-}"
SSL_CERT="${TTYD_SSL_CERT:-}"
SSL_KEY="${TTYD_SSL_KEY:-}"
SESSION="${TTYD_SESSION:-ttyd}"

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

# ---------- Detect what is installed ----------
# Absolute paths are required: launchd runs agents with a minimal PATH
# (/usr/bin:/bin:/usr/sbin:/sbin), so ttyd's execvp() cannot find bare
# command names installed under /opt/homebrew/bin.
TTYD_BIN="$(command -v ttyd || true)"
TMUX_BIN="$(command -v tmux || true)"
HAVE_TMUX=0; [[ -n "$TMUX_BIN" ]] && HAVE_TMUX=1

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
        [[ -z "$TTYD_BIN" ]] && TTYD_BIN="/opt/homebrew/bin/ttyd"
        [[ -z "$TMUX_BIN" ]] && TMUX_BIN="/opt/homebrew/bin/tmux"
    else
        echo "[ERROR] Required package(s) not installed for your choices: ${missing[*]}" >&2
        echo "        Install them first, then re-run this installer:" >&2
        echo "          brew install ${missing[*]}" >&2
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

# ---------- Compose ttyd command line from the chosen features ----------
SCHEME="http"
if [[ "$ENABLE_TMUX" == "1" ]]; then CMD="\"$TMUX_BIN\" new -A -s $SESSION"; else CMD="/bin/zsh -l"; fi
AUTH=""
[[ "$ENABLE_AUTH" == "1" && -n "$CRED" ]] && AUTH=" -c \"$CRED\""
SSL=""
if [[ "$ENABLE_HTTPS" == "1" ]]; then
    SSL=" -S -C \"$SSL_CERT\" -K \"$SSL_KEY\""
    SCHEME="https"
fi
CMDLINE="\"$TTYD_BIN\" --writable -t platform=macos$AUTH$SSL -p $PORT -I \"$INDEX\" --cwd \"$HOME\" $CMD"

render() {
    sed -e "s|__CMDLINE__|$CMDLINE|g" \
        -e "s|__LOG__|$LOG_FILE|g" \
        "$TEMPLATE"
}

echo
echo "=== ttyd-wrapper service installer (launchd LaunchAgent) ==="
echo "  Plist   : $PLIST"
echo "  ttyd    : $TTYD_BIN"
echo "  Index   : $INDEX"
echo "  Port    : $PORT"
echo "  Logs    : $LOG_FILE"
echo "  Session : $([[ "$ENABLE_TMUX" == "1" ]] && echo "tmux ($SESSION) - persistent" || echo "login shell - not persistent")"
echo "  Login   : $([[ "$ENABLE_AUTH" == "1" ]] && echo enabled || echo disabled)"
echo "  HTTPS   : $([[ "$ENABLE_HTTPS" == "1" ]] && echo "enabled ($SCHEME)" || echo disabled)"
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
        code="$(curl -sk -m 5 -o /dev/null -w '%{http_code}' "$SCHEME://localhost:$PORT/" || true)"
        if [[ "$code" == "200" ]]; then
            echo "[OK] HTTP check passed: $SCHEME://localhost:$PORT/"
        else
            echo "[WARN] HTTP check returned: $code (see $LOG_FILE)"
        fi
    fi
    echo
    echo "[INFO] macOS may show a firewall prompt on first connection - click Allow."
    echo "Access from mobile: $SCHEME://<this-machine-ip>:$PORT/"
else
    echo "[ERROR] Agent failed to load. Check $LOG_FILE" >&2
    exit 1
fi
