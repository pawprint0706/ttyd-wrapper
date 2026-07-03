#!/usr/bin/env bash
# Manual run: relay a login bash over the web on port 33322.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${TTYD_PORT:-33322}"

if ! command -v ttyd >/dev/null 2>&1; then
    echo "[ERROR] ttyd not found. Install it first:" >&2
    echo "        sudo apt install ttyd" >&2
    echo "        (or download a release: https://github.com/tsl0922/ttyd/releases)" >&2
    exit 1
fi

exec ttyd --writable -t platform=linux -p "$PORT" -I "$ROOT/public/index.html" --cwd "$HOME" bash -l
