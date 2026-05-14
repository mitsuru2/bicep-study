@description('The base name for Azure resources used by Tech Portfolio project.')
param accountNameBase string = uniqueString(resourceGroup().id)

@description('Location for all resources.')
param location string = resourceGroup().location

@description('User object ID for the application. This should be a valid Azure AD user or service principal object ID.')
param principalId string

@description('The object ID of the owner principal. This should be a valid Azure AD user or service principal object ID.')
param ownerPrincipalId string

@description('The container image to deploy.')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

//------------------------------------------------------------------------------
// Cosmos DB
// https://learn.microsoft.com/ja-jp/azure/cosmos-db/quickstart-template-bicep?toc=%2Fazure%2Fazure-resource-manager%2Fbicep%2Ftoc.json&tabs=CLI
//------------------------------------------------------------------------------
// Cosmos DB の構成
var cosmosLocations array = [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
]
var cosmosDefaultConsistencyLevel string = 'Session'
var cosmosDbAndContainers array = [
  {
    name: 'main-db'
    containers: [
      {
        name: 'articles'
        partitionKey: '/pk'
        throughput: 400
      }
    ]
  }
]
var cosmosConsistencyPolicy = {
  Eventual: {
    defaultConsistencyLevel: 'Eventual'
  }
  ConsistentPrefix: {
    defaultConsistencyLevel: 'ConsistentPrefix'
  }
  Session: {
    defaultConsistencyLevel: 'Session'
  }
  BoundedStaleness: {
    defaultConsistencyLevel: 'BoundedStaleness'
    maxStalenessPrefix: 100
    maxIntervalInSeconds: 5
  }
  Strong: {
    defaultConsistencyLevel: 'Strong'
  }
}

// Cosmos DB アカウントの作成
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2025-10-15' = {
  name: '${accountNameBase}-cosmosdb'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: cosmosConsistencyPolicy[cosmosDefaultConsistencyLevel]
    locations: cosmosLocations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    disableKeyBasedMetadataWriteAccess: true
  }
}

// Cosmos DB データベースとコンテナの作成
module cosmosDatabases 'database.bicep' = [
  for db in cosmosDbAndContainers: {
    name: 'deploy-cosmosdb-${db.name}' // デプロイ履歴の名前。リソース名ではないので注意。
    params: {
      accountName: cosmosAccount.name
      databaseName: db.name
      containers: db.containers
    }
  }
]

// IAMロールの割り当て
var cosmosDbOperatorRoleId string = '230815da-be43-4aae-9cb4-875f7bd000aa'
resource cosmosRoleAssignmentApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, principalId, cosmosDbOperatorRoleId)
  scope: cosmosAccount
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDbOperatorRoleId)
    principalType: 'ServicePrincipal'
  }
}
resource cosmosRoleAssignmentOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, ownerPrincipalId, cosmosDbOperatorRoleId)
  scope: cosmosAccount
  properties: {
    principalId: ownerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDbOperatorRoleId)
    principalType: 'User'
  }
}

// データプレーンへのアクセスを許可するロール割り当て (ビルド時にデータを取得するために必要)
var cosmosDataPlaneReadOnlyRoleId string = '00000000-0000-0000-0000-000000000001'
var cosmosDataPlaneReadWriteRoleId string = '00000000-0000-0000-0000-000000000002'
resource cosmosDataPlaneRoleAssignmentApp 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-10-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, principalId, cosmosDataPlaneReadOnlyRoleId)
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataPlaneReadOnlyRoleId}'
    principalId: principalId
    scope: cosmosAccount.id
  }
}
resource cosmosDataPlaneRoleAssignmentOwner 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-10-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, ownerPrincipalId, cosmosDataPlaneReadWriteRoleId)
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataPlaneReadWriteRoleId}'
    principalId: ownerPrincipalId
    scope: cosmosAccount.id
  }
}

//------------------------------------------------------------------------------
// Storage Account (Blob Storage)
// https://learn.microsoft.com/ja-jp/azure/storage/common/storage-account-create?tabs=bicep
//------------------------------------------------------------------------------
// Storage アカウントの作成
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: '${accountNameBase}storage'
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

// IAMロールの割り当て
var storageBlobDataReaderRoleId string = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' // ビルド時にリソースをDLするために使用
var storageBlobDataContributorRoleId string = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
resource storageRoleAssignmentApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalType: 'ServicePrincipal'
  }
}
resource storageRoleAssignmentOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, ownerPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: ownerPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalType: 'User'
  }
}

//------------------------------------------------------------------------------
// Container Registry
// https://learn.microsoft.com/ja-jp/azure/container-registry/container-registry-get-started-bicep?tabs=CLI
//------------------------------------------------------------------------------
// Container Registry の構成
var acrName string = '${accountNameBase}acr'
var acrSku string = 'Basic'

// Container Registry の作成
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}

// IAMロールの割り当て
var acrPushRoleId string = '8311e382-0749-4cb8-b61a-304f252e45ec'
resource acrRoleAssignmentApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, principalId, acrPushRoleId)
  scope: containerRegistry
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
    principalType: 'ServicePrincipal'
  }
}

//------------------------------------------------------------------------------
// Container Apps
// https://learn.microsoft.com/ja-jp/azure/templates/microsoft.app/containerapps?pivots=deployment-language-bicep
//------------------------------------------------------------------------------

// ユーザー割り当てマネージド ID の作成 (コンテナ実行環境で共通利用)
// ACAやWeb AppからACRにアクセス（Pull）するために使用
resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${accountNameBase}-workload-identity'
  location: location
}

// 上記で作成したユーザー割り当て ID への AcrPull ロール割り当て
var acrPullRoleId string = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, workloadIdentity.id, acrPullRoleId)
  scope: containerRegistry
  properties: {
    principalId: workloadIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Container Apps 環境の作成
resource managedEnvironment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: '${accountNameBase}-aca-environment'
  location: location
  properties: {
    zoneRedundant: false
  }
}

// Container App の作成
resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: '${accountNameBase}-aca'
  location: location
  dependsOn: [
    acrPullRoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${workloadIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      ingress: {
        external: true
        targetPort: 4000
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: workloadIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: '${accountNameBase}-aca-container'
          // ACRにイメージがない間は、パブリックのHello Worldイメージを使用する
          image: containerImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            http: { metadata: { concurrentRequests: '50' } }
            name: 'http-scaler'
          }
        ]
      }
    }
  }
}

// GitHub Actions などの外部サービスから Container App を管理するためのロール割り当て
var acaContributorRoleId string = '358470bc-b998-42bd-ab17-a7e34c199c0f'
resource acaContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerApp.id, principalId, acaContributorRoleId)
  scope: containerApp
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acaContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

//------------------------------------------------------------------------------
// Azure App Services
// https://learn.microsoft.com/ja-jp/azure/app-service/provision-resource-bicep?pivots=app-service-bicep-linux
//------------------------------------------------------------------------------
// App Service Plan
var appServicePlanName string = '${accountNameBase}-webapp-plan'
resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  properties: {
    reserved: true // Linux OS のプランを作成する場合は true に設定する必要があります。
  }
  kind: 'linux'
  sku: { name: 'B1' }
}

// Web App インスタンス
var webAppName string = '${accountNameBase}-webapp'
resource webApp 'Microsoft.Web/sites@2025-03-01' = {
  name: webAppName
  location: location
  dependsOn: [
    acrPullRoleAssignment
  ]
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${workloadIdentity.id}': {} // 作成済みのマネージドIDを紐付け (ACAと共通利用)
    }
  }
  properties: {
    serverFarmId: appServicePlan.id // 紐付ける App Service Plan の ID
    httpsOnly: true // HTTP アクセスを HTTPS に強制リダイレクト
    siteConfig: {
      linuxFxVersion: 'DOCKER|${containerImage}' // Web App for Containers で使用するイメージを指定
      acrUseManagedIdentityCreds: true // ACR からのプルにマネージドIDを使用する設定
      acrUserManagedIdentityID: workloadIdentity.properties.clientId // ACR プルに使用するマネージドIDのクライアントID
      ftpsState: 'FtpsOnly' // FTPSのみを許可
      minTlsVersion: '1.2' // 最小TLSバージョンを1.2に設定
      http20Enabled: true // HTTP 2.0を有効化
      alwaysOn: true // コンテナのコールドスタートを防ぎ、応答性を維持するために有効化
      appSettings: [
        { name: 'WEBSITES_PORT', value: '4000' } // Angularのポートを設定
      ]
    }
  }
}

// FTP接続 (パスワードアクセスを不許可)
resource webAppFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

// SCM (Kudu) 接続 (パスワードアクセスを不許可)
resource webAppScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: false
  }
}
