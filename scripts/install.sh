#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/tasks/deps.sh"
. "$SCRIPT_DIR/tasks/service.sh"
. "$SCRIPT_DIR/tasks/build.sh"
. "$SCRIPT_DIR/tasks/db_setup.sh"
. "$SCRIPT_DIR/tasks/install_deb.sh"

trap 'on_error $LINENO' ERR

# Display installation summary and ask for confirmation
show_install_summary() {
  cat << EOF
================================================================================
                   Panda Home Station Installation Summary
================================================================================

This installation will install the following components:

  System Dependencies:
    - curl, git, build-essential
    - pkg-config, libasound2-dev, libudev-dev, libfuse3-dev
    - libssl-dev, postgresql, postgresql-contrib
    - libinput-dev, libgbm-dev, libdrm-dev, libseat-dev
    - libxkbcommon-dev, libwayland-dev

  Development Tools:
    - Node.js 20
    - Rust toolchain (cargo)
    - repo tool

  Docker:
    - Docker Engine (docker-ce, docker-ce-cli, containerd.io)
    - Docker Buildx and Compose plugins
    - NVIDIA Container Toolkit (if NVIDIA GPU detected)

  PHS Components:
    - NAS Server (Rust backend)
    - Web Desktop (React frontend)
    - JollyPad (Game console)

================================================================================
NOTES:
    - This installation requires ${YELLOW}root privileges${RESET} (sudo)
    - Docker installation requires system-level changes
    - PostgreSQL database will be configured
    - Services will be registered with systemd
================================================================================
EOF
}

# Ask for user confirmation
confirm_install() {
  printf "\n${YELLOW}Do you want to proceed with the installation?${RESET} [Y/n]: "
  read -r response
  case "$response" in
    ""|[Yy]|[Yy][Ee][Ss]) return 0 ;;
    [Nn]|[Nn][Oo]) return 1 ;;
    *) printf "${YELLOW}Invalid input. Please enter Y or N.${RESET}\n"; confirm_install ;;
  esac
}

show_install_summary
if ! confirm_install; then
  log_info "Installation cancelled by user."
  exit 0
fi

log_section "PHS INSTALL START"
task_install_deps
task_repo_sync
task_setup_nasserver_db
task_build_nasserver_deb
task_build_webdesktop_deb
task_build_jollypad_deb
task_install_nasserver_deb
task_install_webdesktop_deb
task_install_jollypad_deb
task_check_nasserver_service
task_check_webdesktop_installation

log_section "PHS INSTALL DONE"
log_info "PHS has been installed successfully."
IP="$(hostname -I | awk '{print $1}')"
log_info "API:     http://${IP}:8000"
log_info "--------------------------------------"
log_info "🎉 Web UI deployed successfully!"
log_info ""
log_info "Visit ${YELLOW}http://${IP}:8080${RESET} to access the Web UI."
log_info "--------------------------------------"