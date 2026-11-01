#!/usr/bin/env bash
# VM の中で、このディレクトリを作業ディレクトリにして docker compose を実行する。
# usage: ./compose.sh up -d / ./compose.sh ps / ./compose.sh logs web / ./compose.sh down
set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"

require_safe_kit_dir
ensure_container_system
ensure_machine_running >/dev/null

# ホストのパスは virtiofs で VM にも同じ絶対パスで見えている
container machine run -n "$MACHINE_NAME" --root -w "$KIT_DIR" -- docker compose "$@"
