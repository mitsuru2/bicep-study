#!/bin/bash
# Abort on error, undefined variable, or error in pipeline.
set -euo pipefail

# スクリプトディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 定数定義
RG_NAME='rg-tech-portfolio-runner'
LOCATION='japaneast'
ACR_RG_NAME='rg-tech-portfolio' # 既存ACRが属するリソースグループ (tech-portfolioプロジェクト)
ACR_NAME='b5lamds6tm4ioacr'     # 既存ACR名 (tech-portfolio/deploy.sh参照)
GITHUB_APP_ID='4374525'
GITHUB_INSTALLATION_ID='148492753'
GITHUB_REPO_FULL_NAME='mitsuru2/docker-nodejs-study'

# Azureログイン確認
if ! az account show > /dev/null 2>&1; then
  echo "Please login to Azure CLI using 'az login' command."
  exit 1
fi

# リソースグループの作成 (既存の場合はエラーになるが --output none で抑制)
az group create --name "$RG_NAME" --location "$LOCATION" --output none

# オーナーユーザーのオブジェクトIDを取得
OWNER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# 既存ACRのログインサーバーを取得
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$ACR_RG_NAME" --query loginServer -o tsv)

# Bicepでリソースをデプロイ
cd "$SCRIPT_DIR/bicep"
DEPLOYMENT_NAME="main-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RG_NAME" \
  --template-file main.bicep \
  --parameters \
    ownerPrincipalId="$OWNER_PRINCIPAL_ID" \
    acrLoginServer="$ACR_LOGIN_SERVER" \
    githubAppId="$GITHUB_APP_ID" \
    githubInstallationId="$GITHUB_INSTALLATION_ID" \
    githubRepoFullName="$GITHUB_REPO_FULL_NAME"

# デプロイ結果(出力値)の取得
query_output() {
  az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RG_NAME" \
    --query "properties.outputs.$1.value" -o tsv
}
ACI_PULL_IDENTITY_PRINCIPAL_ID=$(query_output aciPullIdentityPrincipalId)
KEY_VAULT_NAME=$(query_output keyVaultName)
FUNCTION_APP_NAME=$(query_output functionAppName)
FUNCTION_APP_HOST=$(query_output functionAppDefaultHostName)
LAW_NAME=$(query_output logAnalyticsWorkspaceName)

echo ""
echo "Bicep deployment completed."
echo "  Function App: $FUNCTION_APP_NAME"
echo "  Key Vault:    $KEY_VAULT_NAME"
echo ""

# ACI Pull用マネージドIDに、別リソースグループにある既存ACRへのAcrPullロールを付与する。
# ACRがBicepのデプロイスコープ(rg-tech-portfolio-runner)外にあるため、CLIで別途実行する。
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$ACR_RG_NAME" --query id -o tsv)
az role assignment create \
  --assignee-object-id "$ACI_PULL_IDENTITY_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPull" \
  --scope "$ACR_ID" \
  --output none
echo "Granted AcrPull on $ACR_NAME to the ACI pull identity."

# Log Analyticsワークスペースの共有キーを取得し、Key Vaultへ格納する。
# ACIコンテナグループの診断ログ送信設定(logAnalytics.workspaceKey)に使用する。
LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RG_NAME" \
  --workspace-name "$LAW_NAME" \
  --query primarySharedKey -o tsv)
az keyvault secret set \
  --vault-name "$KEY_VAULT_NAME" \
  --name "log-analytics-shared-key" \
  --value "$LAW_KEY" \
  --output none
echo "Stored Log Analytics shared key in Key Vault."

echo ""
echo "=== 残りの手動セットアップ ==="
echo ""
echo "1. GitHub Appのシークレットを Key Vault ($KEY_VAULT_NAME) に設定:"
echo "   az keyvault secret set --vault-name $KEY_VAULT_NAME --name github-app-private-key --file <docker-nodejs-study-aci-runner.YYYY-MM-DD.private-key.pemのパス>"
echo "   az keyvault secret set --vault-name $KEY_VAULT_NAME --name github-app-webhook-secret --value <GitHub App作成時に設定したwebhook secret>"
echo ""
echo "2. Function Appのデプロイ (functions/ ディレクトリから):"
echo "   cd ../functions && npm install && func azure functionapp publish $FUNCTION_APP_NAME"
echo ""
echo "3. GitHub Appの Webhook URL を以下に更新 (GitHub App設定画面 > General > Webhook URL):"
echo "   https://$FUNCTION_APP_HOST/api/webhook"
echo ""
