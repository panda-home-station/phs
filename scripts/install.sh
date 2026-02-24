#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/tasks/deps.sh"
. "$SCRIPT_DIR/tasks/db.sh"
. "$SCRIPT_DIR/tasks/repo.sh"
. "$SCRIPT_DIR/tasks/service.sh"
. "$SCRIPT_DIR/tasks/session.sh"

log_section "PHS INSTALL START"
task_install_deps
task_setup_db
task_setup_repo
task_write_nas_service
task_write_jolly_session
log_section "PHS INSTALL DONE"
log_info "NAS service enabled; JollyPad will appear after reboot in login sessions"
