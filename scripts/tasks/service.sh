#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
_check_nasserver_service() {
  unit="phs-nasserver.service"
  log_section "Check NAS systemd Service"
  $SUDO systemctl daemon-reload || true
  log_info "check unit exists: ${unit}"
  if ! $SUDO systemctl cat "$unit" >/dev/null 2>&1; then
    log_err "missing unit: ${unit}"
    exit 1
  fi
  log_info "check unit enabled"
  if ! $SUDO systemctl is-enabled --quiet "$unit"; then
    log_err "not enabled: ${unit}"
    exit 1
  fi
  log_info "check unit active"
  if ! $SUDO systemctl is-active --quiet "$unit"; then
    log_err "not active: ${unit}"
    $SUDO systemctl status "$unit" --no-pager || true
    $SUDO journalctl -u "$unit" -n 20 --no-pager || true
    exit 1
  fi
  log_ok "service healthy: ${unit}"
}
task_check_nasserver_service() { _check_nasserver_service; }
task_write_nasserver_service() { _check_nasserver_service; }
