#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then SUDO="sudo"; fi
NASSERVER_USER="${NASSERVER_USER:-nasserver}"
NAS_GROUP="${NAS_GROUP:-nas}"
TARGET_USER="${NASSERVER_USER}"
RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
MAGENTA="$(printf '\033[35m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"
log() { printf "%s\n" "$*"; }
log_info() { printf "%b\n" "${BLUE}➡️  ${*}${RESET}"; }
log_ok() { printf "%b\n" "${GREEN}✅ ${*}${RESET}"; }
log_warn() { printf "%b\n" "${YELLOW}⚠️  ${*}${RESET}"; }
log_err() { printf "%b\n" "${RED}❌ ${*}${RESET}"; }
log_section() {
  printf "\n%b\n" "${BOLD}${MAGENTA}============================================================${RESET}"
  printf "%b\n" "${BOLD}${MAGENTA}🚀 ${*}${RESET}"
  printf "%b\n" "${BOLD}${MAGENTA}============================================================${RESET}"
}
on_error() {
  local exit_code=$?
  local line_no=$1
  if [ $exit_code -ne 0 ]; then
    log_err "PHS installation failed at line $line_no with exit code $exit_code"
    log_info "Check the logs above for more details."
  fi
  exit $exit_code
}
require_cmd() { command -v "$1" >/dev/null 2>&1; }
apt_update() { $SUDO apt-get update -y; }
apt_install() { $SUDO apt-get install -y "$@"; }
ensure_nas_user_group() {
  if ! getent group "${NAS_GROUP}" >/dev/null 2>&1; then
    $SUDO groupadd --system "${NAS_GROUP}"
  fi
  if ! id -u "${NASSERVER_USER}" >/dev/null 2>&1; then
    $SUDO useradd --system --gid "${NAS_GROUP}" --home-dir /var/lib/"${NASSERVER_USER}" --no-create-home --shell /usr/sbin/nologin "${NASSERVER_USER}"
  fi
  $SUDO mkdir -p /var/lib/"${NASSERVER_USER}"
  $SUDO chown "${NASSERVER_USER}:${NAS_GROUP}" /var/lib/"${NASSERVER_USER}"
}
