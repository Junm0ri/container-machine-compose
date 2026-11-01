# container-machine-compose

Docker Desktop を使わずに、Apple 純正の [`container`](https://github.com/apple/container) の **container machine** 上で `docker compose` を動かし、Mac の `localhost` からアクセスするための最小キットです。

```
Mac (localhost:8080)
  │  SSH ローカルポートフォワード (tunnel.sh)
  ▼
container machine "devbox"(Ubuntu 24.04 VM)
  └─ Docker Engine + Docker Compose
       ├─ web  (nginx, :8080)  ── /api/ ──▶ api (traefik/whoami)
       └─ ./html は virtiofs で Mac と共有(編集が即反映)
```

## 前提

- Apple silicon の Mac、macOS 26
- [`container`](https://github.com/apple/container/releases) CLI がインストール済み
- SSH の鍵ペア(`~/.ssh/id_ed25519.pub` など。無ければ `ssh-keygen -t ed25519`)
- このディレクトリを **ホームディレクトリ配下の、空白を含まないパス** に置くこと(VM から見えるのはホーム配下だけで、`container machine run` は空白入りのパスを扱えないため)

動作確認環境: macOS 26.6.2 / container CLI 1.0.0

## 使い方

```bash
./setup.sh          # 1. イメージをビルドして VM を作成、Docker と SSH 鍵を設定(初回数分)
./compose.sh up -d  # 2. VM の中で docker compose up
./tunnel.sh         # 3. Mac の localhost:8080 を VM へ中継
open http://localhost:8080
```

`html/index.html` を Mac 側で編集してリロードすると、そのまま反映されます。

### よく使うコマンド

```bash
./compose.sh ps            # 状態確認
./compose.sh logs web      # ログ
./compose.sh down          # 停止
./tunnel.sh status         # トンネルの状態
./tunnel.sh stop           # トンネルを停止
container machine stop devbox   # VM を停止
```

VM を再起動すると IP が変わることがありますが、`./tunnel.sh` を実行し直せば新しい IP に張り直します(同じ IP・同じポートで稼働中なら何もしません)。

### Mac の `docker` コマンドから使う

`tunnel.sh` は、VM の Docker ソケット(`/var/run/docker.sock`)も SSH で Mac 側(`~/.cache/container-machine-compose/<MACHINE_NAME>-docker.sock`)に転送し、それを指す docker context `cm-<MACHINE_NAME>` を作ります(Colima と同じ方式)。Mac に docker CLI があれば、`compose.sh` を使わずに Mac から直接操作できます。

```bash
brew install docker docker-compose   # CLI だけ。Docker Desktop は不要
./tunnel.sh
docker context use cm-devbox         # 戻すときは docker context use default
docker compose up -d                 # Mac から実行して、VM の中で動く
docker ps
```

- context の切り替えはしません。`docker --context cm-devbox ps` のように都度指定してもかまいません
- ソケットのパスは固定なので、VM の IP が変わっても `./tunnel.sh` で張り直せば context はそのまま使えます
- `-v` でマウントするパスは VM から見たパスとして解釈されます。ホームディレクトリ配下は同じパスで見えるのでそのまま動きますが、ホームの外(`/tmp` など)は VM から見えないため空になります
- コンテナが公開したポートは自動では Mac に来ません。`TUNNEL_PORTS` に並べてください

## 設定

環境変数で上書きできます。

| 変数 | 既定値 | 内容 |
|---|---|---|
| `MACHINE_NAME` | `devbox` | container machine の名前 |
| `MACHINE_CPUS` / `MACHINE_MEMORY` | `4` / `8G` | VM の CPU 数とメモリ(作成時のみ有効) |
| `TUNNEL_PORTS` | `8080` | 中継するポート(空白区切り。例: `TUNNEL_PORTS="3000 5173" ./tunnel.sh`) |
| `IMAGE` | `local/ubuntu-machine:24.04` | ビルドする VM イメージのタグ |

自分のプロジェクトで使う場合は、`docker-compose.yml` を置き換えて、公開するポートを `TUNNEL_PORTS` に並べてください。

## ファイル

| ファイル | 内容 |
|---|---|
| `Dockerfile` | VM 用の Ubuntu 24.04 イメージ(systemd / openssh-server / Docker / Compose 入り) |
| `setup.sh` | ビルド → VM 作成 → 初期設定 → SSH 疎通確認(何度実行しても大丈夫) |
| `scripts/vm-setup.sh` | VM の中で root として実行される初期設定 |
| `compose.sh` | VM の中でこのディレクトリを作業ディレクトリにして `docker compose` を実行 |
| `tunnel.sh` | SSH のローカルポートフォワードと Docker ソケットの転送を張る・張り直す・止める |
| `docker-compose.yml` / `nginx.conf` / `html/` | サンプルアプリ |

## なぜ SSH トンネルなのか

`container` には `--publish` でホストの `localhost` にポートを公開する機能がありますが、これは単発コンテナの `container run` 用で、`container machine` には同等のオプションがありません。VM には専用の IP が振られるので IP 直打ちならアクセスできますが、多くの Web アプリの開発設定は「アクセス元は localhost」を前提にしています(ホスト許可、Cookie のドメイン、リダイレクト先 URL など)。

VM で動いている sshd を使って `ssh -L` で中継すれば、ブラウザからは本物の `localhost` に見えるので、アプリ側の設定を変えずに済みます。

## ハマりどころ

- **素の `ubuntu:24.04` では VM がブートしない**: init(systemd)が無いため。`Dockerfile` で systemd を入れています。
- **作成直後の初回起動が `Operation not supported by device` で失敗することがある**: 再試行すると起動します。スクリプト側でリトライしています。
- **ユーザー名に `.` があると sudo が効かない**: sudo は `/etc/sudoers.d` 内のドットを含むファイル名を無視します。`vm-setup.sh` がドット無しの名前にリネームします。
- **`container machine run` は引数のクォートを保持しない**: 空白を含む引数を渡したいときは、スクリプトファイルにして実行してください。
- **VM を作り直して同じ IP が再利用されると SSH のホスト鍵警告が出る**: `ssh-keygen -R <IP>` で古い鍵を消してください(`StrictHostKeyChecking=no` にはしないでください)。

## 片付け

```bash
./compose.sh down
./tunnel.sh stop
container machine stop devbox
container machine delete devbox
container image delete local/ubuntu-machine:24.04
docker context rm cm-devbox   # Mac の docker から使っていた場合
```

## 注意

個人の検証用キットです。`container` はまだ発展途上のツールで、将来 `container machine` にポート公開機能が入れば SSH トンネルは不要になるかもしれません。
