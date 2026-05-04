@description('The base name for Azure resources used by Tech Portfolio project.')
param accountNameBase string = uniqueString(resourceGroup().id)

@description('Location for all resources.')
param location string = resourceGroup().location

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
