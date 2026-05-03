# syntax=docker/dockerfile:1

# 最新のDebian環境を使用。Bicepの勉強目的なのでNode.js版ではない素のDebian。
# - Docker Hub (Debian): https://hub.docker.com/_/debian
# - Debian: https://wiki.debian.org/DebianReleases#Current_Debian_Releases_and_repositories
FROM debian:trixie

# OSへのツールインストール (apt)
# - Git: DevContainer環境でのgit操作のため。
# - JQ: JSONメッセージの処理のため。
# - CURL: CLIダウンロードのため。
# - locales: ロケール設定警告回避のため。
# Note: インストール後にキャッシュを削除。イメージサイズ抑制のため。
RUN apt-get update && apt-get install -y \
    sudo \
    git \
    jq \
    curl \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# 環境変数設定
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Docker環境でパスワード無しにsudoコマンドを使用するための設定。
# mkdir: ディレクトリの作成。-pオプションにより中間フォルダも一括で作成できる。
# /etc/sudoers.d: スーパーユーザーごとの設定を保存するフォルダ。
# 0440: sudoコマンドは0440以外の設定ファイルを受け付けない。
RUN echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/passwd-sudo-rules \
    && mkdir -p /etc/sudoers.d \
    && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# Azure CLIのインストール。
# https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Bicepのインストール
RUN az bicep install

# 非rootユーザーの追加 (既存のNode.js環境と合わせてユーザー名はnode)
RUN useradd --create-home --shell /bin/bash --uid 1000 node
USER node
WORKDIR /home/node

# 実行コマンド上書き。Do nothing.
CMD ["sleep", "infinity"]
