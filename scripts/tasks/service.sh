#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
task_write_nas_service() {
  log_section "STEP 4/5: Install NAS systemd Service"
  svc="/etc/systemd/system/phs-nas.service"
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
[Unit]
Description=Panda Home Station NAS (backend + web dev)
After=network.target

[Service]
Type=simple
User=${TARGET_USER}
WorkingDirectory=${ROOT_DIR}
Environment=PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/.cargo/bin
ExecStart=/bin/bash -lc 'cd "${ROOT_DIR}" && ./nas/scripts/run_dev.sh'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  $SUDO mv "$tmp" "$svc"
  $SUDO chmod 644 "$svc"
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now phs-nas.service
  log_ok "Service phs-nas.service installed and enabled"
}
