#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

task_check_postgresql_access() {
  if require_cmd systemctl; then
    if ! $SUDO systemctl is-active --quiet postgresql; then
      $SUDO systemctl start postgresql || true
    fi
  fi
  if ! su - postgres -c "psql -tAc 'SELECT 1'" | grep -q 1; then
    log_err "PostgreSQL not accessible"
    exit 1
  fi
  log_ok "PostgreSQL accessible"
}
