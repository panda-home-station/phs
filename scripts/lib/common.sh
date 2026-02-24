#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then SUDO="sudo"; fi
TARGET_USER="${SUDO_USER:-$USER}"
if [ -t 1 ] || [ "${FORCE_COLOR:-}" = "1" ]; then
  RED="$(printf '\\033[31m')"
  GREEN="$(printf '\\033[32m')"
  YELLOW="$(printf '\\033[33m')"
  BLUE="$(printf '\\033[34m')"
  MAGENTA="$(printf '\\033[35m')"
  BOLD="$(printf '\\033[1m')"
  RESET="$(printf '\\033[0m')"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  BOLD=""
  RESET=""
fi
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
require_cmd() { command -v "$1" >/dev/null 2>&1; }
apt_update() { $SUDO apt-get update -y; }
apt_install() { $SUDO apt-get install -y "$@"; }
