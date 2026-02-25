#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/tasks/service.sh"
task_start_services() {
  log_section "Start NAS via deb package"
  db_url="${DATABASE_URL:-postgresql://%2Fvar%2Frun%2Fpostgresql/pnas_db?user=${TARGET_USER}}"
  ensure_nas_user_group
  deb="${NASSERVER_DEB:-}"
  if [ -z "${deb:-}" ]; then
    cand=""
    for dir in "${ROOT_DIR}/nas/nasserver/artifacts" "${ROOT_DIR}/nas/artifacts" "${ROOT_DIR}/nas/nasserver/target/debian" "${ROOT_DIR}/nas"; do
      if [ -d "$dir" ]; then
        f=$(ls -t "$dir"/*nasserver*".deb" 2>/dev/null | head -n1 || true)
        if [ -n "${f:-}" ]; then cand="$f"; break; fi
        f=$(ls -t "$dir"/*.deb 2>/dev/null | head -n1 || true)
        if [ -n "${f:-}" ]; then cand="$f"; break; fi
      fi
    done
    deb="${cand:-}"
  fi
  if [ -n "${deb:-}" ] && [ -f "${deb:-/dev/null}" ]; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y "./$(basename "$deb")" || $SUDO apt-get install -y "$deb"
    $SUDO systemctl daemon-reload || true
    if systemctl is-active --quiet phs-nasserver.service; then
      log_ok "NAS service is active"
    else
      log_warn "NAS service is not active after install; check 'systemctl status phs-nasserver.service'"
    fi
  else
    task_check_nasserver_service
    log_warn "No deb found; installed systemd unit only"
  fi
  log_info "DATABASE_URL=${db_url}"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  task_start_services
fi
