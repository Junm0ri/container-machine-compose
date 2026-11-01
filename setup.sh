#!/usr/bin/env bash
# イメージのビルド → container machine の作成 → Docker と SSH の初期設定までを行う。
# 何度実行しても大丈夫(作成済みの machine は再利用する)。
set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"

require_safe_kit_dir
ensure_container_system

pubkey=""
for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub" "$HOME/.ssh/id_rsa.pub"; do
  [[ -f "$k" ]] && { pubkey="$k"; break; }
done
[[ -n "$pubkey" ]] || die "SSH 公開鍵がありません。ssh-keygen -t ed25519 で作成してください"

if machine_exists; then
  echo "=== container machine '$MACHINE_NAME' は作成済み。再利用します ==="
else
  echo "=== イメージをビルド: $IMAGE ==="
  container build -f "$KIT_DIR/Dockerfile" -t "$IMAGE" "$KIT_DIR"
  echo "=== container machine を作成: $MACHINE_NAME (cpus=$MACHINE_CPUS, memory=$MACHINE_MEMORY) ==="
  container machine create "$IMAGE" --name "$MACHINE_NAME" --cpus "$MACHINE_CPUS" --memory "$MACHINE_MEMORY"
fi

ip="$(ensure_machine_running)"

echo "=== VM の初期設定(Docker / SSH 鍵) ==="
container machine run -n "$MACHINE_NAME" --root -- bash "$KIT_DIR/scripts/vm-setup.sh" "$USER" "$pubkey"

echo "=== SSH 疎通確認: $SSH_USER@$ip ==="
ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SSH_USER@$ip" true \
  || die "SSH で接続できません。VM を作り直して IP が再利用された場合は ssh-keygen -R $ip を実行してから再試行してください"

echo
echo "完了。次は:"
echo "  ./compose.sh up -d   # VM の中で docker compose up"
echo "  ./tunnel.sh          # Mac の localhost:$TUNNEL_PORTS を VM へ中継"
