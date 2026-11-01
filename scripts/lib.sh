# 各スクリプト共通の設定と関数。環境変数で上書きできる。
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACHINE_NAME="${MACHINE_NAME:-devbox}"
IMAGE="${IMAGE:-local/ubuntu-machine:24.04}"
MACHINE_CPUS="${MACHINE_CPUS:-4}"
MACHINE_MEMORY="${MACHINE_MEMORY:-8G}"
TUNNEL_PORTS="${TUNNEL_PORTS:-8080}"
SSH_USER="${SSH_USER:-$USER}"
STATE_DIR="${STATE_DIR:-$HOME/.cache/container-machine-compose}"

die() { echo "error: $*" >&2; exit 1; }

# container machine run は引数のクォートを保持しないため、空白を含むパスでは動かない
require_safe_kit_dir() {
  [[ "$KIT_DIR" != *" "* ]] || die "パスに空白を含む場所では動きません: $KIT_DIR"
  [[ "$KIT_DIR" == "$HOME"/* ]] || die "VM から見えるのはホームディレクトリ配下だけです。\$HOME 配下に置いてください: $KIT_DIR"
}

ensure_container_system() {
  command -v container >/dev/null || die "container CLI が見つかりません (https://github.com/apple/container)"
  container system status >/dev/null 2>&1 || container system start
}

machine_exists() { container machine inspect "$MACHINE_NAME" >/dev/null 2>&1; }

# VM の現在の IP(DHCP なので再起動で変わりうる)
vm_ip() {
  container machine inspect "$MACHINE_NAME" 2>/dev/null | plutil -extract 0.ipAddress raw -o - - 2>/dev/null
}

# 停止中なら起動し、IP が振られるまで待つ
ensure_machine_running() {
  machine_exists || die "container machine '$MACHINE_NAME' がありません。先に ./setup.sh を実行してください"
  # 作成直後の初回起動は "Operation not supported by device" で失敗することがあるのでリトライする
  local ip i
  for i in 1 2 3 4 5; do
    container machine run -n "$MACHINE_NAME" -- true >&2 && break
    [[ $i == 5 ]] && die "container machine '$MACHINE_NAME' を起動できませんでした (container machine logs --boot $MACHINE_NAME を確認)"
    echo "起動を再試行します ($i)..." >&2
    sleep 3
  done
  for i in $(seq 1 30); do
    ip="$(vm_ip)"
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    sleep 1
  done
  die "VM の IP を取得できませんでした"
}
