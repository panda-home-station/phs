#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

task_build_nasserver_deb() {
  log_section "STEP 3.1/5: Build nasserver deb package"
  (
    cd "${ROOT_DIR}/nas/nasserver"
    if [ -f .ci/package_deb.sh ]; then
      if ! bash .ci/package_deb.sh; then
        log_err "Failed to build nasserver deb package"
        exit 1
      fi
      log_ok "nasserver deb package built"
    else
      log_err "nasserver packaging script not found: ${ROOT_DIR}/nas/nasserver/.ci/package_deb.sh"
      exit 1
    fi
  )
}

task_build_webdesktop_deb() {
  log_section "STEP 3.2/5: Build webdesktop deb package"
  (
    cd "${ROOT_DIR}/nas/webdesktop"
    if [ -f .ci/package_deb.sh ]; then
      if ! bash .ci/package_deb.sh; then
        log_err "Failed to build webdesktop deb package"
        exit 1
      fi
      log_ok "webdesktop deb package built"
    else
      log_err "webdesktop packaging script not found: ${ROOT_DIR}/nas/webdesktop/.ci/package_deb.sh"
      exit 1
    fi
  )
}

task_build_jollypad_deb() {
  log_section "STEP 3.3/5: Build jollypad deb package"
  (
    cd "${ROOT_DIR}/jollypad"
    if [ -f .ci/package_deb.sh ]; then
      if ! bash .ci/package_deb.sh; then
        log_err "Failed to build jollypad deb package"
        exit 1
      fi
      log_ok "jollypad deb package built"
    else
      log_err "jollypad packaging script not found: ${ROOT_DIR}/jollypad/.ci/package_deb.sh"
      exit 1
    fi
  )
}
