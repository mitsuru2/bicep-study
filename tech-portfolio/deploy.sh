#!/bin/bash
# Abort on error, undefined variable, or error in pipeline.
set -euo pipefail

# スクリプトディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RG_NAME='rg-tech-portfolio-ioc'
APP_NAME='github-mitsuru2-docker-nodejs-study'
GITHUB_ORG='mitsuru2'
GITHUB_REPO='docker-nodejs-study'

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
OWNER_PRINCIPAL_ID=$(az ad user show --id "mitsuru.takahashi.biz_gmail.com#EXT#@mitsurutakahashibizgmail.onmicrosoft.com" --query id -o tsv)
echo "owner_principal_id = \"$OWNER_PRINCIPAL_ID\""
echo ""

# Bicepでリソースをデプロイ
cd "$SCRIPT_DIR/bicep"
DEPLOYMENT_NAME="main-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RG_NAME" \
  --template-file main.bicep \
  --parameters principalId="$PRINCIPAL_ID" ownerPrincipalId="$OWNER_PRINCIPAL_ID"

echo "Deploy completed."