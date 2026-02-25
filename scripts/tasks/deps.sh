#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"

PACKAGES=(
  curl
  git
  ca-certificates
  build-essential
  pkg-config
  libasound2-dev
  libudev-dev
  libfuse3-dev
  libssl-dev
  postgresql
  postgresql-contrib
  libinput-dev
  libgbm-dev
  libdrm-dev
  libseat-dev
  libxkbcommon-dev
  libwayland-dev
)

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
  apt_install "${PACKAGES[@]}"
  log_info "install repo tool"
  ensure_repo_tool
  log_info "install Node.js 20"
  install_node20
  log_info "install Rust toolchain"
  install_rust
  log_ok "Dependencies installed"
}

task_repo_sync() {
  log_section "Sync Repositories"
  ensure_repo_tool
  printf "Select remote for repository sync\n"
  printf "1) github  2) gitlab  3) gitee\n"
  printf "Enter choice [1-3] (default: 1): "
  read -r _choice || true
  case "${_choice}" in
    2|gitlab|GitLab|GITLAB) _remote="gitlab" ;;
    3|gitee|Gitee|GITEE) _remote="gitee" ;;
    ""|1|github|GitHub|GITHUB|*) _remote="github" ;;
  esac
  _remote="$(printf "%s" "${_remote}" | tr 'A-Z' 'a-z')"
  manifest="repos/github.xml"
  case "${_remote}" in
    gitlab) manifest="repos/default.xml" ;;
    gitee) manifest="repos/gitee.xml" ;;
    github|"") manifest="repos/github.xml" ;;
    *) manifest="repos/github.xml" ;;
  esac
  if [ ! -f "${ROOT_DIR}/${manifest}" ]; then
    log_err "manifest not found: ${manifest}"
    exit 1
  fi
  jobs=4
  if require_cmd nproc; then
    jobs="$(nproc)"
  fi
  (
    cd "${ROOT_DIR}"
    if [ ! -d ".repo" ]; then
      repo init . -m "${manifest}"
    else
      log_info ".repo exists, skip repo init"
    fi
    repo sync -j "${jobs}"
  )
  expected_domain="github.com"
  case "${_remote}" in
    gitlab) expected_domain="gitlab.pandamicro.com" ;;
    gitee) expected_domain="gitee.com" ;;
    github|*) expected_domain="github.com" ;;
  esac
  (
    cd "${ROOT_DIR}"
    total=0
    ok_count=0
    declare -a failed=()
    while IFS= read -r line; do
      path="${line%% :*}"
      total=$((total+1))
      if [ -d "${path}/.git" ] && git -C "${path}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
        url="$(git -C "${path}" remote get-url origin 2>/dev/null || true)"
        if printf "%s" "${url}" | grep -q "${expected_domain}"; then
          ok_count=$((ok_count+1))
        else
          failed+=("${path}(remote-url)")
        fi
      else
        failed+=("${path}(git-missing)")
      fi
    done < <(repo list)
    if [ "${ok_count}" -ne "${total}" ]; then
      log_err "Repo sync check failed: ${ok_count}/${total} ok"
      for f in "${failed[@]}"; do log_err " - ${f}"; done
      exit 1
    fi
  )
  log_ok "Repositories synced"
}
