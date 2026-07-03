#!/usr/bin/env bash
# ttyd-wrapper service uninstaller (systemd user unit)
set -euo pipefail

SERVICE_NAME="ttyd-wrapper"
PORT="${TTYD_PORT:-33322}"
UNIT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE_NAME.service"

if [[ ! -f "$UNIT_FILE" ]] && ! systemctl --user list-unit-files 2>/dev/null | grep -q "^$SERVICE_NAME"; then
    echo "Service \"$SERVICE_NAME\" is not installed. Nothing to do."
    exit 0
fi

echo "Stopping and removing service \"$SERVICE_NAME\"..."
systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
rm -f "$UNIT_FILE"
systemctl --user daemon-reload

# Firewall rule (best effort)
if command -v ufw >/dev/null 2>&1; then
    sudo -n ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
fi

echo "[OK] Service uninstalled."
echo "[INFO] Linger was left enabled; disable with: loginctl disable-linger $USER"
