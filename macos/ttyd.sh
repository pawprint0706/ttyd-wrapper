#!/usr/bin/env bash
# Manual run: relay a persistent tmux session (or a login zsh) over the web.
# Optional env overrides:
#   TTYD_PORT      listen port           (default 33322)
#   TTYD_CRED      basic auth user:pass  (default: disabled)
#   TTYD_SSL_CERT  TLS certificate path  ) both required
#   TTYD_SSL_KEY   TLS private key path  ) to enable HTTPS
#   TTYD_SESSION   tmux session name     (default ttyd)
#   TTYD_TMUX=0    force a plain login shell (no persistence)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${TTYD_PORT:-33322}"
CRED="${TTYD_CRED:-}"
SSL_CERT="${TTYD_SSL_CERT:-}"
SSL_KEY="${TTYD_SSL_KEY:-}"
SESSION="${TTYD_SESSION:-ttyd}"

if ! command -v ttyd >/dev/null 2>&1; then
    echo "[ERROR] ttyd not found. Install it first:" >&2
    echo "        brew install ttyd" >&2
    exit 1
fi

opts=(--writable -t platform=macos -p "$PORT" -I "$ROOT/public/index.html" --cwd "$HOME")
[[ -n "$CRED" ]] && opts+=(-c "$CRED")
[[ -n "$SSL_CERT" && -n "$SSL_KEY" ]] && opts+=(-S -C "$SSL_CERT" -K "$SSL_KEY")

# Persistent session: tmux keeps the shell (and its programs) alive across
# disconnects and mirrors it to every connected device. Falls back to a
# login shell when tmux is absent or TTYD_TMUX=0.
if [[ "${TTYD_TMUX:-1}" != "0" ]] && command -v tmux >/dev/null 2>&1; then
    cmd=(tmux new -A -s "$SESSION")
else
    cmd=(zsh -l)
fi

exec ttyd "${opts[@]}" "${cmd[@]}"
