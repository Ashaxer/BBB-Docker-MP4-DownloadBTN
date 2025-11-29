#!/bin/bash
set -e

SERVICE_NAME="bbb-mp4-monitor"
SCRIPT_INSTALL_PATH="/usr/local/bin/${SERVICE_NAME}.sh"
SERVICE_INSTALL_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found. Install gettext first (e.g. apt install gettext)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/example.env"
SCRIPT_TEMPLATE="${SCRIPT_DIR}/${SERVICE_NAME}.sh.template"
SERVICE_TEMPLATE="${SCRIPT_DIR}/${SERVICE_NAME}.service.template"

if [ ! -f "$ENV_FILE" ]; then
  echo "example.env not found at ${ENV_FILE}." >&2
  echo "Please copy/edit example.env first, then re-run install.sh." >&2
  exit 1
fi

if [ ! -f "$SCRIPT_TEMPLATE" ]; then
  echo "Script template not found: ${SCRIPT_TEMPLATE}" >&2
  exit 1
fi

if [ ! -f "$SERVICE_TEMPLATE" ]; then
  echo "Service template not found: ${SERVICE_TEMPLATE}" >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

envsubst < "$SCRIPT_TEMPLATE" | sudo tee "$SCRIPT_INSTALL_PATH" >/dev/null
sudo chmod +x "$SCRIPT_INSTALL_PATH"
echo "Generated script at $SCRIPT_INSTALL_PATH"

envsubst < "$SERVICE_TEMPLATE" | sudo tee "$SERVICE_INSTALL_PATH" >/dev/null
sudo chmod 644 "$SERVICE_INSTALL_PATH"
echo "Installed systemd unit at $SERVICE_INSTALL_PATH"

sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME".service

echo
echo "Service ${SERVICE_NAME}.service has been enabled and started."
echo "Check status with:  sudo systemctl status ${SERVICE_NAME}.service"
