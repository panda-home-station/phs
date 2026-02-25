#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

_ensure_postgresql() {
  if require_cmd systemctl; then
    $SUDO systemctl enable --now postgresql || true
  fi
  if ! $SUDO su - postgres -c "psql -tAc 'SELECT 1'" | grep -q 1; then
    log_err "PostgreSQL unavailable"
    exit 1
  fi
}

task_check_nasserver_db() {
  _ensure_postgresql
  $SUDO su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='nasserver'\"" | grep -q 1
  $SUDO su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='pnas_db'\"" | grep -q 1
  log_ok "Database objects present"
}

task_setup_nasserver_db() {
  log_section "STEP 2/6: Setup PostgreSQL for nasserver"
  _ensure_postgresql
  if ! $SUDO su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='nasserver'\"" | grep -q 1; then
    $SUDO su - postgres -c "psql -tAc \"CREATE ROLE \\\"nasserver\\\" LOGIN\""
    log_info "role created: nasserver"
  else
    $SUDO su - postgres -c "psql -tAc \"ALTER ROLE \\\"nasserver\\\" LOGIN\""
    log_info "role ensured: nasserver"
  fi
  if ! $SUDO su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='pnas_db'\"" | grep -q 1; then
    $SUDO su - postgres -c "createdb -O \\\"nasserver\\\" \\\"pnas_db\\\""
    log_info "database created: pnas_db"
  else
    log_info "database exists: pnas_db"
  fi
  task_check_nasserver_db
  log_ok "PostgreSQL for nasserver ready"
}
