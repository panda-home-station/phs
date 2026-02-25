#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

task_install_nasserver_deb() {
  log_section "Install nasserver deb package"
  ARTIFACTS_DIR=""
  for dir in "${ROOT_DIR}/nas/nasserver/artifacts" "${ROOT_DIR}/nas/artifacts"; do
    if [ -d "$dir" ]; then ARTIFACTS_DIR="$dir"; break; fi
  done
  
  deb=$(ls -t "${ARTIFACTS_DIR}"/nasserver_*.deb 2>/dev/null | head -n1 || true)
  if [ -n "${deb}" ]; then
    STAGE_DIR="/tmp/phs-debs"
    STAGED="${STAGE_DIR}/$(basename "${deb}")"
    $SUDO mkdir -p "${STAGE_DIR}"
    $SUDO cp -f "${deb}" "${STAGED}"
    $SUDO chmod 644 "${STAGED}"
    log_info "Installing ${STAGED}"
    if ! $SUDO apt-get install --reinstall -y "${STAGED}"; then
      log_err "Failed to install nasserver deb package"
      exit 1
    fi
    $SUDO rm -f "${STAGED}"
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable phs-nasserver.service
    log_info "Restarting phs-nasserver.service..."
    if ! $SUDO systemctl restart phs-nasserver.service; then
      log_err "Failed to restart phs-nasserver.service"
      $SUDO journalctl -u phs-nasserver.service -n 20 --no-pager
      exit 1
    fi
    log_ok "nasserver installed and service restarted"
  else
    log_err "nasserver deb package not found in ${ARTIFACTS_DIR}"
    exit 1
  fi
}

task_install_webdesktop_deb() {
  log_section "Install webdesktop deb package"
  ARTIFACTS_DIR=""
  for dir in "${ROOT_DIR}/nas/webdesktop/artifacts" "${ROOT_DIR}/nas/artifacts"; do
    if [ -d "$dir" ]; then ARTIFACTS_DIR="$dir"; break; fi
  done
  
  deb=$(ls -t "${ARTIFACTS_DIR}"/webdesktop_*.deb 2>/dev/null | head -n1 || true)
  if [ -n "${deb}" ]; then
    STAGE_DIR="/tmp/phs-debs"
    STAGED="${STAGE_DIR}/$(basename "${deb}")"
    $SUDO mkdir -p "${STAGE_DIR}"
    $SUDO cp -f "${deb}" "${STAGED}"
    $SUDO chmod 644 "${STAGED}"
    log_info "Installing ${STAGED}"
    if ! $SUDO apt-get install -y "${STAGED}"; then
      log_err "Failed to install webdesktop deb package"
      exit 1
    fi
    $SUDO rm -f "${STAGED}"
    log_ok "webdesktop installed"
  else
    log_err "webdesktop deb package not found in ${ARTIFACTS_DIR}"
    exit 1
  fi
}

task_check_webdesktop_installation() {
  log_section "Check webdesktop installation"
  if [ -d "/usr/share/phs/webdesktop" ]; then
    log_ok "webdesktop directory exists"
  else
    log_err "webdesktop directory not found: /usr/share/phs/webdesktop"
    exit 1
  fi
}
