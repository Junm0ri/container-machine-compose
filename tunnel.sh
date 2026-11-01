#!/usr/bin/env bash
# Mac の localhost:<port> を VM の localhost:<port> へ SSH で中継する。
# あわせて VM の Docker ソケットを Mac 側に転送し、Mac の docker コマンドから VM の Docker を使えるようにする。
# VM の IP や転送ポートが前回と変わっていれば張り直し、同じなら何もしない。
# usage: ./tunnel.sh [start] / ./tunnel.sh stop / ./tunnel.sh status
#        TUNNEL_PORTS="8080 5173" ./tunnel.sh
set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"

mkdir -p "$STATE_DIR"
sock="$STATE_DIR/$MACHINE_NAME.sock"
state="$STATE_DIR/$MACHINE_NAME.state"
docker_sock="$STATE_DIR/$MACHINE_NAME-docker.sock"
docker_context="cm-$MACHINE_NAME"

tunnel_alive() { [[ -S "$sock" ]] && ssh -S "$sock" -O check "$SSH_USER@tunnel" 2>/dev/null; }
stop_tunnel() {
  tunnel_alive && ssh -S "$sock" -O exit "$SSH_USER@tunnel" 2>/dev/null || true
  rm -f "$sock" "$state" "$docker_sock"
}

case "${1:-start}" in
  stop)
    stop_tunnel; echo "トンネルを停止しました"; exit 0 ;;
  status)
    if tunnel_alive; then echo "稼働中: $(cat "$state")"; else echo "停止中"; fi; exit 0 ;;
  start) ;;
  *) die "usage: $0 [start|stop|status]" ;;
esac

ensure_container_system
ip="$(ensure_machine_running)"
want="$ip ports=$TUNNEL_PORTS docker=$docker_sock"

if tunnel_alive && [[ "$(cat "$state" 2>/dev/null)" == "$want" ]]; then
  echo "トンネルは稼働中です: $want"
  exit 0
fi
stop_tunnel

forwards=()
for p in $TUNNEL_PORTS; do forwards+=(-L "127.0.0.1:$p:localhost:$p"); done
# Unix ソケットも -L で転送できる(Colima と同じ方式)。VM 側は docker グループのユーザーで接続する
forwards+=(-L "$docker_sock:/var/run/docker.sock")

# ホスト鍵の検証は無効化しない。VM 作り直しで鍵が変わったら ssh-keygen -R <ip> で消す
ssh -f -N -M -S "$sock" \
  -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=5 \
  -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 \
  -o StreamLocalBindUnlink=yes \
  "${forwards[@]}" "$SSH_USER@$ip" \
  || die "トンネルを張れませんでした(ポートが使用中、またはホスト鍵が変わった場合は ssh-keygen -R $ip)"
echo "$want" > "$state"

for p in $TUNNEL_PORTS; do echo "http://localhost:$p -> $ip:$p"; done
echo "docker: unix://$docker_sock -> $ip:/var/run/docker.sock"

# Mac に docker CLI があれば、ソケットを指す context を用意しておく(切り替えはしない)
if command -v docker >/dev/null; then
  docker context inspect "$docker_context" >/dev/null 2>&1 \
    || docker context create "$docker_context" --description "container machine $MACHINE_NAME" \
         --docker "host=unix://$docker_sock" >/dev/null 2>&1
  echo
  echo "Mac の docker コマンドで VM の Docker を使うには:"
  echo "  docker context use $docker_context   # 戻すときは docker context use default"
fi
