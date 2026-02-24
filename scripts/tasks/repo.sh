#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
task_setup_repo() {
  log_section "STEP 3/5: Setup Subrepositories"
  default_remote="github"
  if [ -t 0 ]; then
    log_info "Select remote: 1) gitlab  2) github (default)  3) gitee"
    read -r -p "Enter 1/2/3 or name [${default_remote}]: " sel || sel=""
    case "${sel,,}" in
      "") remote="${default_remote}" ;;
      "1"|"gitlab") remote="gitlab" ;;
      "2"|"github") remote="github" ;;
      "3"|"gitee") remote="gitee" ;;
      "default") remote="${default_remote}" ;;
      *) log_warn "Invalid input, using default ${default_remote}"; remote="${default_remote}";;
    esac
  else
    remote="${default_remote}"
  fi
  case "$remote" in
    gitlab|default) manifest="repos/default.xml"; remote="gitlab" ;;
    github) manifest="repos/github.xml" ;;
    gitee) manifest="repos/gitee.xml" ;;
    *) manifest="repos/default.xml"; remote="gitlab" ;;
  esac
  if [ ! -f "$ROOT_DIR/$manifest" ]; then
    log_err "Manifest not found: $manifest"
    exit 1
  fi
  log_info "repo init with manifest: ${remote} (${manifest})"
  pushd "$ROOT_DIR" >/dev/null
  if ! git config --global user.email >/dev/null 2>&1 || ! git config --global user.name >/dev/null 2>&1; then
    log_warn "Git global identity is not set. You may need to run:"
    log_warn "  git config --global user.email \"you@example.com\""
    log_warn "  git config --global user.name \"Your Name\""
  fi
  if ! "$HOME/.local/bin/repo" init . -m "$manifest"; then
    log_err "repo init failed. Please configure git and try again."
    exit 1
  fi
  log_info "repo sync"
  if ! "$HOME/.local/bin/repo" sync; then
    log_err "repo sync failed"
    exit 1
  fi
  popd >/dev/null
  log_ok "Subrepositories synced"
}
