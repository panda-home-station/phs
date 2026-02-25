#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
ensure_repo_tool() {
  if ! require_cmd repo; then
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/.local/bin/repo"
    chmod a+x "$HOME/.local/bin/repo"
    export PATH="$HOME/.local/bin:$PATH"
  fi
}
install_node20() {
  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
  apt_install nodejs
}
install_rust() {
  if ! require_cmd cargo; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
  fi
}
task_install_deps() {
  log_section "STEP 1/5: Install Base Dependencies"
  log_info "apt update"
  apt_update
  apt_install curl git ca-certificates build-essential pkg-config libasound2-dev libudev-dev libfuse3-dev libssl-dev postgresql postgresql-contrib libinput-dev libgbm-dev libdrm-dev libseat-dev libxkbcommon-dev libwayland-dev
  log_info "install repo tool"
  ensure_repo_tool
  log_info "install Node.js 20"
  install_node20
  log_info "install Rust toolchain"
  install_rust
  log_ok "Dependencies installed"
}
