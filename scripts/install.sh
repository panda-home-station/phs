#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/tasks/deps.sh"
. "$SCRIPT_DIR/tasks/service.sh"
. "$SCRIPT_DIR/tasks/build.sh"
. "$SCRIPT_DIR/tasks/install_deb.sh"

trap 'on_error $LINENO' ERR

log_section "PHS INSTALL START"
task_install_deps
task_build_nasserver_deb
task_build_webdesktop_deb
task_install_nasserver_deb
task_install_webdesktop_deb
task_check_nasserver_service
task_check_webdesktop_installation
log_section "PHS INSTALL DONE"
log_info "PHS has been installed successfully."
IP="$(hostname -I | awk '{print $1}')"
log_info "Web UI:  http://${IP}:6000"
log_info "API:     http://${IP}:8000"
