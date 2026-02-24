#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
ensure_postgres() { $SUDO systemctl enable --now postgresql || true; }
create_db() {
  db="$1"
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
    sudo -u postgres createdb "${db}"
  fi
}
task_setup_db() {
  log_section "STEP 2/5: Setup Database"
  log_info "enable and start PostgreSQL"
  ensure_postgres
  log_info "create database pnas_db"
  create_db pnas_db
  log_ok "Database ready"
}
