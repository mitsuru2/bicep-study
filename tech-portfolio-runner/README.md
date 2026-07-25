# tech-portfolio-runner

`docker-nodejs-study` リポジトリの GitHub Actions ワークフローを Azure Container Instances (ACI) 上の self-hosted runner で実行するための制御プレーン。GitHub webhook (`workflow_job`) を受けて ACI コンテナグループをオンデマンド起動し、ephemeral runner としてジョブを1回実行後に自動終了・削除する。

`tech-portfolio` (アプリ本体のインフラ) とは別のリソースグループ `rg-tech-portfolio-runner` で管理する。

## 構成

- `bicep/main.bicep`: Function App, Storage Account (Queue/Table), Key Vault, Log Analytics, ACIイメージPull用マネージドID一式
- `functions/`: Azure Functions (Node.js v4 programming model)
  - `src/functions/receiver.js`: GitHub webhookのHTTPトリガー。署名検証・フィルタリング後、Storage Queueへenqueue
  - `src/functions/controller.js`: Queueトリガー。GitHub Appでrunner登録トークンを取得し、ACIコンテナグループを起動
  - `src/functions/cleanup.js`: Timerトリガー(5分毎)。Terminated/ハング/期限超過のコンテナグループを削除
- `deploy.sh`: ローカルからの手動デプロイスクリプト(`tech-portfolio/deploy.sh`と同様のパターン)

## 前提

- `docker-nodejs-study` 側に GitHub App (`docker-nodejs-study-aci-runner`, App ID: `4374525`, Installation ID: `148492753`) が作成・インストール済みであること
  - 権限: Administration (Read and write), Actions (Read-only), Metadata (Read-only)
  - 購読イベント: Workflow job
- 既存の `tech-portfolio` プロジェクトの ACR (`rg-tech-portfolio`) がデプロイ済みであること

## デプロイ手順

```bash
az login
./deploy.sh
```

`deploy.sh` は以下を行う:

1. `rg-tech-portfolio-runner` リソースグループを新規作成
2. `bicep/main.bicep` をデプロイ(Function App, Storage, Key Vault, Log Analytics, ACIイメージPull用マネージドID)
3. ACIイメージPull用マネージドIDに、既存ACR(別リソースグループ)への `AcrPull` ロールを付与
4. Log Analyticsワークスペースの共有キーをKey Vaultへ格納(ACI診断ログ送信用)

以下は手動で行う必要がある(スクリプト実行後にコンソールへ案内が表示される):

1. GitHub Appのシークレットをkey Vaultへ設定:
   ```bash
   az keyvault secret set --vault-name <kv-name> --name github-app-private-key --file <ダウンロードした.pemファイル>
   az keyvault secret set --vault-name <kv-name> --name github-app-webhook-secret --value <GitHub App作成時に設定したwebhook secret>
   ```
2. Function Appのデプロイ:
   ```bash
   cd functions
   npm install
   func azure functionapp publish <function-app-name>
   ```
3. GitHub Appの Webhook URL を `https://<function-app-name>.azurewebsites.net/api/webhook` に更新(GitHub App設定画面 > General > Webhook URL)

## runnerイメージについて

ACIが起動するコンテナイメージ(`gha-runner`)は `docker-nodejs-study` リポジトリ側の `docker/runner/Dockerfile` から、GitHub-hosted runner上の専用ワークフローでビルドしACRへpushする(このプロジェクトの管理範囲外)。イメージタグは Function App の app setting `RUNNER_IMAGE_TAG` で参照する。

## 運用上の注意

- self-hosted runnerを使うワークフローに `pull_request` トリガーを追加しないこと(フォークPR由来のジョブをReceiver側でも拒否する多層防御を実装しているが、第一の防御線はワークフロー側のトリガー設計)
- Cleanup Functionの強制削除閾値(45分ハング / 3時間絶対上限)は `functions/src/functions/cleanup.js` の定数で調整可能
