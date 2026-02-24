#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
task_write_jolly_session() {
  log_section "STEP 5/5: Install JollyPad Wayland Session"
  wrapper="/usr/local/bin/jollypad-session.sh"
  session="/usr/share/wayland-sessions/JollyPad.desktop"
  tmpw=$(mktemp)
  cat >"$tmpw" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:${HOME}/.cargo/bin"
cd "${ROOT_DIR}/jollypad"
cargo run --release --bin jolly-launcher
EOF
  $SUDO mv "$tmpw" "$wrapper"
  $SUDO chmod +x "$wrapper"
  tmps=$(mktemp)
  cat >"$tmps" <<EOF
[Desktop Entry]
Name=JollyPad
Comment=Panda Home Station Wayland session
Exec=${wrapper}
Type=Application
DesktopNames=JollyPad
EOF
  $SUDO mv "$tmps" "$session"
  $SUDO chmod 644 "$session"
  log_ok "JollyPad session installed"
}
