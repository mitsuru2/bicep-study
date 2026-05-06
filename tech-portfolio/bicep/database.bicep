@description('The name of the Cosmos DB account.')
param accountName string

@description('The parent database name.')
param databaseName string

@description('''
Array of container objects. Each object defines a Cosmos DB container and should have the following properties:
- name: (string) The name of the container (e.g., 'articles').
- partitionKey: (string) The partition key path for the container (e.g., '/pk').
- throughput: (int) The throughput in RU/s for the container (e.g., 400).
''')
param containers array

// Cosmos DB アカウントの場所を指定
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2025-10-15' existing = {
  name: accountName
}

// データベースの作成
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-10-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// コンテナのループ
resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-10-15' = [
  for c in containers: {
    parent: database
    name: c.name
    properties: {
      resource: {
        id: c.name
        partitionKey: {
          paths: [c.partitionKey]
          kind: 'Hash'
        }
        indexingPolicy: { automatic: true, indexingMode: 'consistent' }
      }
      options: {
        throughput: c.throughput
      }
    }
  }
]
