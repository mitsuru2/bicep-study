@description('The base name for Azure resources used by Tech Portfolio project.')
param accountNameBase string = uniqueString(resourceGroup().id)

@description('Location for all resources.')
param location string = resourceGroup().location

@description('User object ID for the application. This should be a valid Azure AD user or service principal object ID.')
param principalId string

@description('The object ID of the owner principal. This should be a valid Azure AD user or service principal object ID.')
param ownerPrincipalId string

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

// データプレーンへのアクセスを許可するロール割り当て
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
var storageBlobDataReaderRoleId string = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
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
