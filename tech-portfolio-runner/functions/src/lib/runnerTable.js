const { DefaultAzureCredential } = require('@azure/identity');
const { TableClient } = require('@azure/data-tables');

let client;
function getClient() {
  if (!client) {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    const tableName = process.env.RUNNER_INSTANCES_TABLE_NAME || 'RunnerInstances';
    const url = `https://${accountName}.table.core.windows.net`;
    client = new TableClient(url, tableName, new DefaultAzureCredential());
  }
  return client;
}

async function upsertRunnerInstance(entity) {
  await getClient().upsertEntity(
    { partitionKey: 'runner', rowKey: entity.containerGroupName, ...entity },
    'Merge'
  );
}

async function deleteRunnerInstance(containerGroupName) {
  try {
    await getClient().deleteEntity('runner', containerGroupName);
  } catch (err) {
    if (err.statusCode !== 404) throw err;
  }
}

module.exports = { upsertRunnerInstance, deleteRunnerInstance };
