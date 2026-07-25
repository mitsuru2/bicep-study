# syntax=docker/dockerfile:1

# 最新のDebian環境を使用。Bicepの勉強目的なのでNode.js版ではない素のDebian。
# - Docker Hub (Debian): https://hub.docker.com/_/debian
# - Debian: https://wiki.debian.org/DebianReleases#Current_Debian_Releases_and_repositories
# FROM debian:trixie
FROM node:24-bookworm

# OSへのツールインストール (apt)
# - Git: DevContainer環境でのgit操作のため。
# - JQ: JSONメッセージの処理のため。
# - CURL: CLIダウンロードのため。
# - locales: ロケール設定警告回避のため。
# - libicudev: Bicep CLIで必要。
# - wget: Terraform CLIのインストールに必要。
# Note: インストール後にキャッシュを削除。イメージサイズ抑制のため。
RUN apt-get update && apt-get install -y \
    sudo \
    git \
    jq \
    curl \
    locales \
    libicu-dev \
    wget \
    zip \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# 環境変数設定
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Azure CLIのインストール。
# https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Azure Functions Core Tools to enable local development of Azure Functions in the container.
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg \
    && mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg \
    && . /etc/os-release && sudo echo "deb [arch=amd64] https://packages.microsoft.com/debian/$VERSION_ID/prod $VERSION_CODENAME main" > /etc/apt/sources.list.d/dotnetdev.list \
    && apt-get update && apt-get install -y \
    azure-functions-core-tools-4 \
    jq

# Terraformのインストール
# https://developer.hashicorp.com/terraform/install
RUN wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y terraform \
    && rm -rf /var/lib/apt/lists/*

# sudoコマンドを許可するために/etc/sudoers.dフォルダ以下にユーザー名のファイルを追加。
RUN mkdir -p /etc/sudoers.d \
    && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# ユーザー切り替え
USER node
WORKDIR /home/node

# Bicepのインストール
RUN az bicep install

# 実行コマンド上書き。Do nothing.
CMD ["sleep", "infinity"]
