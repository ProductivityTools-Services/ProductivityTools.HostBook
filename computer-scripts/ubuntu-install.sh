#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Uruchom ten skrypt z uprawnieniami roota: sudo ./ubuntu-install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/ubuntu.sh"
chmod +x "$SCRIPT_PATH"

SERVICE_NAME="productivitytools-hostbook"
RUN_USER="${SUDO_USER:-$USER}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=ProductivityTools.HostBook - Raportowanie lokalnych adresow IP do Firebase
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${RUN_USER}
Environment=HOME=${RUN_HOME}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/bin/bash ${SCRIPT_PATH}
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=ProductivityTools.HostBook Timer (co 5 minut i przy starcie)

[Timer]
OnBootSec=30sec
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.service"

echo "OK: Zainstalowano i uruchomiono usluge '${SERVICE_NAME}.timer' dla skryptu: ${SCRIPT_PATH}"
