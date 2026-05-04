// ストレージアカウント名の定義。
// リソースグループIDはすでにユニークだが、ハイフンが含まれているのでそのままでは使えない。
// uniqueString()を使用することで13文字のハッシュを生成し、制約を満たすユニークな文字列を取得している。
@minLength(3)
@maxLength(24)
@description('Provide a name for the storage account. Use only lowercase letters and numbers. The name must be unique across Azure.')
param storageAccountName string = 'store${uniqueString(resourceGroup().id)}'

// ロケーションの定義。リソースグループ情報から取得。
param location string = resourceGroup().location

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: 'name'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'Subnet-1'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'Subnet-2'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}
