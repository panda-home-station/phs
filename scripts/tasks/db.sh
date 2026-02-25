#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
ensure_postgres() { $SUDO systemctl enable --now postgresql || true; }
create_db() {
  db="$1"
  owner="$2"
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
    if [ -n "${owner:-}" ]; then
      sudo -u postgres createdb -O "${owner}" "${db}"
    else
      sudo -u postgres createdb "${db}"
    fi
  fi
}
ensure_role() {
  role="$1"
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${role}'" | grep -q 1; then
    sudo -u postgres psql -tAc "CREATE ROLE \"${role}\" LOGIN"
  fi
}
task_setup_db() {
  log_section "Setup Database"
  ensure_postgres
  ensure_role "${TARGET_USER}"
  create_db pnas_db "${TARGET_USER}"
  log_ok "Database ready"
}
