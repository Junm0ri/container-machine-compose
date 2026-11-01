# container machine 用の Ubuntu 24.04 イメージ
# 素の ubuntu:24.04 には init(systemd) が無く VM としてブートできないため、
# systemd / openssh-server / Docker Engine / Docker Compose を組み込む。
FROM ubuntu:24.04

ENV container=container

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      dbus systemd systemd-sysv openssh-server sudo \
      iproute2 iputils-ping curl ca-certificates \
      docker.io docker-compose-v2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# machine-id はブート時に生成させる
RUN : > /etc/machine-id && : > /var/lib/dbus/machine-id

# コンテナ環境では不要・失敗するユニットを止める
RUN systemctl set-default multi-user.target && \
    systemctl mask \
      dev-hugepages.mount \
      sys-fs-fuse-connections.mount \
      systemd-update-utmp.service \
      systemd-tmpfiles-setup.service \
      console-getty.service && \
    systemctl enable ssh docker

# ホストの LANG/LC_* を持ち込まない(ロケール未設定の警告を避ける)
RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config
