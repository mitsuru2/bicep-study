@description('The base name for Azure resources used by the GitHub Actions self-hosted runner (ACI) project.')
param accountNameBase string = uniqueString(resourceGroup().id)

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The object ID of the owner principal (human). Used to grant Key Vault secret management access.')
param ownerPrincipalId string

@description('The login server of the existing ACR that hosts the runner container image (e.g. b5lamds6tm4ioacr.azurecr.io). Defined in the tech-portfolio project.')
param acrLoginServer string

@description('The repository (image name) within the ACR that hosts the runner image.')
param runnerImageRepository string = 'gha-runner'

@description('The GitHub App ID used to authenticate as the runner controller.')
param githubAppId string

@description('The GitHub App installation ID for this repository.')
param githubInstallationId string

@description('The full name (owner/repo) of the GitHub repository this runner infrastructure serves.')
param githubRepoFullName string = 'mitsuru2/docker-nodejs-study'

//------------------------------------------------------------------------------
// Log Analytics Workspace + Application Insights
// ACIはコンテナグループ削除後にログが失われるため、診断ログの外部集約先として使用する。
// Function Appの実行ログもここに集約する。
//------------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${accountNameBase}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${accountNameBase}-appi'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

//------------------------------------------------------------------------------
// Storage Account (Function App backing storage + Queue + Table)
// https://learn.microsoft.com/ja-jp/azure/storage/common/storage-account-create?tabs=bicep
//------------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: '${accountNameBase}ghrunner'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Queue Service + キュー (Receiver -> Controller のジョブメタデータ受け渡し)
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2025-08-01' = {
  parent: storageAccount
  name: 'default'
}
resource aciRunnerJobsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2025-08-01' = {
  parent: queueService
  name: 'aci-runner-jobs'
}

// Table Service + テーブル (起動したACIコンテナグループの追跡台帳)
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2025-08-01' = {
  parent: storageAccount
  name: 'default'
}
resource runnerInstancesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-08-01' = {
  parent: tableService
  name: 'RunnerInstances'
}

//------------------------------------------------------------------------------
// Key Vault (GitHub App秘密鍵・webhook secret・Log Analytics共有キーを格納)
// https://learn.microsoft.com/ja-jp/azure/key-vault/general/quick-create-bicep
//------------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${accountNameBase}-kv'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}

// オーナー(人間)がシークレットを設定・ローテーションできるようにする
var keyVaultSecretsOfficerRoleId string = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
resource kvRoleAssignmentOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, ownerPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    principalId: ownerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalType: 'User'
  }
}

//------------------------------------------------------------------------------
// ACIイメージPull用 ユーザー割り当てマネージドID
// Controller Functionが起動するACIコンテナグループに紐付け、ACRからのイメージPullに使用する。
// AcrPullロールの割り当ては、ACRが別リソースグループ(tech-portfolio)にあるため
// deploy.shからのCLIコマンドで別途行う。
//------------------------------------------------------------------------------
resource aciPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${accountNameBase}-aci-pull-identity'
  location: location
}

//------------------------------------------------------------------------------
// Function App (Receiver / Controller / Cleanup)
// https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-infrastructure-as-code
//------------------------------------------------------------------------------
resource functionPlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: '${accountNameBase}-func-plan'
  location: location
  kind: 'functionapp,linux'
  properties: {
    reserved: true
  }
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: '${accountNameBase}-func-ghrunner'
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|22'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~22' }
        // AzureWebJobsStorage をマネージドID経由の接続にする(アカウントキー不使用)
        { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        // アプリケーション固有設定
        { name: 'KEY_VAULT_URI', value: keyVault.properties.vaultUri }
        { name: 'STORAGE_ACCOUNT_NAME', value: storageAccount.name }
        { name: 'JOBS_QUEUE_NAME', value: aciRunnerJobsQueue.name }
        { name: 'RUNNER_INSTANCES_TABLE_NAME', value: runnerInstancesTable.name }
        { name: 'ACR_LOGIN_SERVER', value: acrLoginServer }
        { name: 'RUNNER_IMAGE_REPOSITORY', value: runnerImageRepository }
        // build-runner-image.yml がイメージを更新するたびに、このapp settingを最新タグへ更新する運用を想定。
        { name: 'RUNNER_IMAGE_TAG', value: 'latest' }
        { name: 'ACI_PULL_IDENTITY_RESOURCE_ID', value: aciPullIdentity.id }
        { name: 'ACI_RESOURCE_GROUP_NAME', value: resourceGroup().name }
        { name: 'ACI_LOCATION', value: location }
        { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
        { name: 'GITHUB_APP_ID', value: githubAppId }
        { name: 'GITHUB_APP_INSTALLATION_ID', value: githubInstallationId }
        { name: 'GITHUB_REPO_FULL_NAME', value: githubRepoFullName }
        { name: 'RUNNER_LABEL', value: 'aci-runner' }
        { name: 'LOG_ANALYTICS_WORKSPACE_ID', value: logAnalytics.properties.customerId }
      ]
    }
  }
}

//------------------------------------------------------------------------------
// IAMロールの割り当て (Function App のシステム割り当てマネージドID向け)
//------------------------------------------------------------------------------
var keyVaultSecretsUserRoleId string = '4633458b-17de-408a-b874-0445c86b69e6'
resource kvRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

// AzureWebJobsStorage(マネージドID接続)のホスト動作に必要
var storageBlobDataOwnerRoleId string = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
resource storageBlobRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Receiver -> Queue へのenqueue、Controller <- Queue のdequeueに使用
var storageQueueDataContributorRoleId string = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
resource storageQueueRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Controller/Cleanup が RunnerInstances テーブルを読み書きするために使用
var storageTableDataContributorRoleId string = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
resource storageTableRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Controller が ACI コンテナグループを作成、Cleanup が削除するために使用 (このリソースグループ全体に対して)
var containerInstanceContributorRoleId string = '5d977122-f97e-4b4d-a52f-6b43003ddb4d'
resource aciRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, containerInstanceContributorRoleId)
  scope: resourceGroup()
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', containerInstanceContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ACIコンテナグループにaciPullIdentity(ユーザー割り当てID)を紐付ける(assign)には、
// ContainerGroups/writeとは別に、そのID自体に対する明示的な権限が必要。
var managedIdentityOperatorRoleId string = 'f1a07417-d97a-45cb-824c-7a7467783830'
resource aciPullIdentityRoleAssignmentFunc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aciPullIdentity.id, functionApp.id, managedIdentityOperatorRoleId)
  scope: aciPullIdentity
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleId)
    principalType: 'ServicePrincipal'
  }
}

//------------------------------------------------------------------------------
// Outputs
//------------------------------------------------------------------------------
output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountName string = storageAccount.name
output aciPullIdentityResourceId string = aciPullIdentity.id
output aciPullIdentityPrincipalId string = aciPullIdentity.properties.principalId
output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
