#!/usr/bin/env bash
# Manual run: relay a login zsh over the web on port 33322.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${TTYD_PORT:-33322}"

if ! command -v ttyd >/dev/null 2>&1; then
    echo "[ERROR] ttyd not found. Install it first:" >&2
    echo "        brew install ttyd" >&2
    exit 1
fi

exec ttyd --writable -p "$PORT" -I "$ROOT/public/index.html" --cwd "$HOME" zsh -l
