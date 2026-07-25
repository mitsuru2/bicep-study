#!/bin/bash
# Azure Functions (Receiver/Controller/Cleanup) のデプロイスクリプト。
#
# Linux Consumption プランでは `func azure functionapp publish` /
# `az functionapp deployment source config-zip` が使えない(AzureWebJobsStorageの
# マネージドID接続に未対応、かつzip pushデプロイ自体が非対応)ため、
# WEBSITE_RUN_FROM_PACKAGE にBlob URLを設定する方式を使う。
# アップロード先のBlobはプライベートのままとし、Function App自身のマネージドID
# (Bicepで Storage Blob Data Owner を付与済み)で取得させるため、SASは発行しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RG_NAME='rg-tech-portfolio-runner'
CONTAINER_NAME='deployments'
ZIP_NAME='functions-deploy.zip'

# Azureログイン確認
if ! az account show > /dev/null 2>&1; then
  echo "Please login to Azure CLI using 'az login' command."
  exit 1
fi

FUNC_APP=$(az functionapp list -g "$RG_NAME" --query "[0].name" -o tsv)
STORAGE=$(az storage account list -g "$RG_NAME" --query "[0].name" -o tsv)

if [ -z "$FUNC_APP" ] || [ -z "$STORAGE" ]; then
  echo "Function App / Storage Account が見つかりません。先に ../deploy.sh を実行してください。"
  exit 1
fi

echo "Function App: $FUNC_APP"
echo "Storage:      $STORAGE"

# zipパッケージの作成 (host.jsonがzipのルート直下に来るよう、functions/配下で圧縮する)
cd "$SCRIPT_DIR"
rm -f "../$ZIP_NAME"
zip -rq "../$ZIP_NAME" . -x "local.settings.json" -x "local.settings.json.example"
cd ..
echo "Created $ZIP_NAME"

STORAGE_KEY=$(az storage account keys list -g "$RG_NAME" --account-name "$STORAGE" --query "[0].value" -o tsv)

# プライベートコンテナの作成 (既存の場合はエラーになるが || true で無視)
az storage container create \
  --account-name "$STORAGE" \
  --account-key "$STORAGE_KEY" \
  --name "$CONTAINER_NAME" \
  --public-access off \
  --output none || true

# zipのアップロード (上書き)
az storage blob upload \
  --account-name "$STORAGE" \
  --account-key "$STORAGE_KEY" \
  --container-name "$CONTAINER_NAME" \
  --name "$ZIP_NAME" \
  --file "$ZIP_NAME" \
  --overwrite \
  --output none
echo "Uploaded $ZIP_NAME to $CONTAINER_NAME container."

# WEBSITE_RUN_FROM_PACKAGE の設定 (SASなし。Function App自身のマネージドIDで取得される)
PACKAGE_URL="https://$STORAGE.blob.core.windows.net/$CONTAINER_NAME/$ZIP_NAME"
az functionapp config appsettings set \
  --resource-group "$RG_NAME" \
  --name "$FUNC_APP" \
  --settings WEBSITE_RUN_FROM_PACKAGE="$PACKAGE_URL" \
  --output none

# 再起動して反映
az functionapp restart --resource-group "$RG_NAME" --name "$FUNC_APP"

# トリガーの同期 (URL方式のデプロイ後は手動同期が必要)
SUB_ID=$(az account show --query id -o tsv)
az resource invoke-action \
  --action syncfunctiontriggers \
  --ids "/subscriptions/$SUB_ID/resourceGroups/$RG_NAME/providers/Microsoft.Web/sites/$FUNC_APP"

echo ""
echo "Deployment completed."
echo "  Webhook URL: https://$(az functionapp show -g "$RG_NAME" -n "$FUNC_APP" --query defaultHostName -o tsv)/api/webhook"
f