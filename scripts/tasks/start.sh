#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
. "$SCRIPT_DIR/lib/common.sh"
task_start_services() {
  if [ -x "$ROOT_DIR/nas/scripts/run_dev.sh" ]; then
    bash "$ROOT_DIR/nas/scripts/run_dev.sh"
  else
    exit 1
  fi
}
