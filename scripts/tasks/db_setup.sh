#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

_ensure_postgresql() {
  if require_cmd systemctl; then
    $SUDO systemctl enable --now postgresql || true
  fi
  if ! su - postgres -c "psql -tAc 'SELECT 1'" | grep -q 1; then
    log_err "PostgreSQL unavailable"
    exit 1
  fi
}

task_setup_nasserver_db() {
  log_section "Setup PostgreSQL for nasserver"
  _ensure_postgresql
  if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='nasserver'\"" | grep -q 1; then
    su - postgres -c "psql -tAc \"CREATE ROLE \\\"nasserver\\\" LOGIN\""
    log_info "role created: nasserver"
  else
    su - postgres -c "psql -tAc \"ALTER ROLE \\\"nasserver\\\" LOGIN\""
    log_info "role ensured: nasserver"
  fi
  if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='pnas_db'\"" | grep -q 1; then
    su - postgres -c "createdb -O \\\"nasserver\\\" \\\"pnas_db\\\""
    log_info "database created: pnas_db"
  else
    log_info "database exists: pnas_db"
  fi
  su - postgres -c "psql -tAc \"ALTER DATABASE \\\"pnas_db\\\" OWNER TO \\\"nasserver\\\"\"" || true
  su - postgres -c "psql -tAc \"GRANT ALL PRIVILEGES ON DATABASE \\\"pnas_db\\\" TO \\\"nasserver\\\"\"" || true
  su - postgres -c "psql -d pnas_db -tAc \"GRANT ALL ON SCHEMA public TO \\\"nasserver\\\"\"" || true
  log_ok "PostgreSQL initialized for nasserver"
}

task_check_nasserver_db() {
  _ensure_postgresql
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='nasserver'\"" | grep -q 1
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='pnas_db'\"" | grep -q 1
  log_ok "Database objects present"
}
