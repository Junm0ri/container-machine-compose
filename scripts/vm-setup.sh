#!/bin/bash
# VM の中で root として実行される初期設定。setup.sh から呼ばれる。
# usage: vm-setup.sh <username> <public-key-path>
set -euo pipefail

user="$1"
pubkey="$2"
home="$(getent passwd "$user" | cut -d: -f6)"
[[ -n "$home" ]] || { echo "user $user が VM にいません" >&2; exit 1; }

# sudo は /etc/sudoers.d の中の「.」を含むファイル名を無視する。
# ユーザー名に「.」があると自動生成された sudoers が効かないので、ドット無しの名前にする。
for f in /etc/sudoers.d/*.*; do
  [[ -e "$f" ]] || continue
  mv "$f" "/etc/sudoers.d/zz-$(basename "$f" | tr '.' '-')"
done

# sudo なしで docker を使えるようにする(SSH で入ったとき用)
usermod -aG docker "$user"
systemctl enable --now docker

# SSH 公開鍵を登録(重複登録しない)
install -d -m 700 -o "$user" -g "$(id -g "$user")" "$home/.ssh"
touch "$home/.ssh/authorized_keys"
grep -qxF "$(cat "$pubkey")" "$home/.ssh/authorized_keys" || cat "$pubkey" >> "$home/.ssh/authorized_keys"
chmod 600 "$home/.ssh/authorized_keys"
chown "$user:$(id -g "$user")" "$home/.ssh/authorized_keys"
systemctl enable --now ssh
systemctl restart ssh

docker --version
docker compose version
