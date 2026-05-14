#!/bin/bash
# Abort on error, undefined variable, or error in pipeline.
set -euo pipefail

# スクリプトディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 定数定義
RG_NAME='rg-tech-portfolio'
APP_NAME='github-mitsuru2-docker-nodejs-study'
GITHUB_ORG='mitsuru2'
GITHUB_REPO='docker-nodejs-study'

# Azureログイン確認
# az account show コマンドを実行して、Azure CLIにログインしているか確認します。結果はnullにリダイレクトして表示しない。
if ! az account show > /dev/null 2>&1; then
  echo "Please login to Azure CLI using 'az login' command."
  exit 1
fi

# リソースグループの作成
# すでに存在する場合はエラーになりますが、--output none で出力を抑制しているため、エラーが発生しません。
az group create --name "$RG_NAME" --location japaneast --output none

# Terraformでアプリ登録
cd "$SCRIPT_DIR/terraform"
terraform init
terraform apply -auto-approve \
  -var="app_name=$APP_NAME" \
  -var="github_org=$GITHUB_ORG" \
  -var="github_repo=$GITHUB_REPO"

# TerraformのoutputをBicepのparamに渡す
PRINCIPAL_ID=$(terraform output -raw principal_id)

# オーナーユーザーのオブジェクトIDを取得
OWNER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
echo "owner_principal_id = \"$OWNER_PRINCIPAL_ID\""
echo ""

# デフォルトのコンテナイメージ
CONTAINER_IMAGE=mcr.microsoft.com/azuredocs/containerapps-helloworld:latest
# CONTAINER_IMAGE=b5lamds6tm4ioacr.azurecr.io/app-runtime:sha-0e055eb

# Bicepでリソースをデプロイ
cd "$SCRIPT_DIR/bicep"
DEPLOYMENT_NAME="main-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RG_NAME" \
  --template-file main.bicep \
  --parameters principalId="$PRINCIPAL_ID" ownerPrincipalId="$OWNER_PRINCIPAL_ID" containerImage="$CONTAINER_IMAGE" \

echo "Deploy completed."
echo ""
