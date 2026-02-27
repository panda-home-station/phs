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

install_docker() {
  log_info "Installing Docker..."

  # Check if Docker is already installed
  if require_cmd docker; then
    log_ok "Docker already installed, skipping..."
    return 0
  fi

  # Install Docker dependencies
  log_info "Installing Docker dependencies..."
  apt_install ca-certificates curl gnupg lsb-release

  # Add Docker's official GPG key
  log_info "Adding Docker GPG key..."
  $SUDO install -m 0755 -d /etc/apt/keyrings

  # Try to download GPG key from official source first, then try Alibaba Cloud mirror
  if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
    log_info "Downloaded GPG key from official Docker repository"
    DOCKER_MIRROR_BASE="https://download.docker.com/linux/ubuntu"
  elif curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
    log_info "Downloaded GPG key from Alibaba Cloud mirror"
    DOCKER_MIRROR_BASE="https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
  else
    log_err "Failed to download Docker GPG key from both sources"
    return 1
  fi
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

  # Set up Docker repository
  log_info "Setting up Docker repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_MIRROR_BASE} \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine
  log_info "Installing Docker Engine..."
  apt_update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Enable and start Docker service
  log_info "Starting Docker service..."
  $SUDO systemctl enable docker
  $SUDO systemctl start docker

  # Add current user to docker group
  log_info "Adding current user to docker group..."
  $SUDO usermod -aG docker "$USER"

  log_ok "Docker installed successfully"

  # Check for NVIDIA GPU
  log_info "Checking for NVIDIA GPU..."
  if command -v lspci >/dev/null 2>&1 && lspci | grep -i nvidia >/dev/null 2>&1; then
    log_info "NVIDIA GPU detected, installing NVIDIA Container Toolkit..."

    # Add NVIDIA Container Toolkit repository
    $SUDO apt-get install -y ca-certificates curl gnupg

    # Try to download NVIDIA GPG key
    if curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | $SUDO gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
      log_info "Downloaded NVIDIA GPG key from official repository"
    else
      log_warn "Failed to download NVIDIA GPG key, skipping NVIDIA Container Toolkit installation"
      return 0
    fi

    # Download and configure NVIDIA repository list
    if curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null; then
      log_info "Configured NVIDIA repository list"
    else
      log_warn "Failed to configure NVIDIA repository list, skipping NVIDIA Container Toolkit installation"
      return 0
    fi

    # Install NVIDIA Container Toolkit
    apt_update
    if apt_install nvidia-container-toolkit 2>/dev/null; then
      # Configure Docker to use NVIDIA runtime
      log_info "Configuring Docker NVIDIA runtime..."
      $SUDO nvidia-ctk runtime configure --runtime=docker

      # Restart Docker to apply changes
      $SUDO systemctl restart docker

      log_ok "NVIDIA Container Toolkit installed and configured"
      log_warn "You may need to log out and log back in for group changes to take effect"
    else
      log_warn "Failed to install NVIDIA Container Toolkit, but Docker will still work without GPU support"
    fi
  else
    log_info "No NVIDIA GPU detected, skipping NVIDIA Container Toolkit installation"
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
  log_info "install Docker"
  install_docker
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
