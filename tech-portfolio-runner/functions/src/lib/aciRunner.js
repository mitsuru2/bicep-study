const { DefaultAzureCredential } = require('@azure/identity');
const { ContainerInstanceManagementClient } = require('@azure/arm-containerinstance');
const { getSecret } = require('./keyVaultSecrets');

let client;
function getClient() {
  if (!client) {
    const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID;
    client = new ContainerInstanceManagementClient(new DefaultAzureCredential(), subscriptionId);
  }
  return client;
}

// npm buildを伴う重量ジョブはheavyプロファイル(2vCPU/4GiB)を選択する。
// ワークフロー名は .github/workflows/*.yml の `name:` と一致させる。
const HEAVY_WORKFLOWS = new Set(['Manual Release Build', 'Publish Docker Image (develop)']);

function resolveResourceProfile(workflowName) {
  if (HEAVY_WORKFLOWS.has(workflowName)) {
    return { cpu: 2, memoryInGB: 4 };
  }
  return { cpu: 1, memoryInGB: 2 };
}

async function createRunnerContainerGroup({ jobId, runId, repoFullName, workflowName, registrationToken }) {
  const rgName = process.env.ACI_RESOURCE_GROUP_NAME;
  const location = process.env.ACI_LOCATION;
  const acrLoginServer = process.env.ACR_LOGIN_SERVER;
  const imageRepository = process.env.RUNNER_IMAGE_REPOSITORY || 'gha-runner';
  const imageTag = process.env.RUNNER_IMAGE_TAG || 'latest';
  const pullIdentityResourceId = process.env.ACI_PULL_IDENTITY_RESOURCE_ID;
  const lawWorkspaceId = process.env.LOG_ANALYTICS_WORKSPACE_ID;
  const lawKey = await getSecret('log-analytics-shared-key');

  const suffix = Math.random().toString(36).slice(2, 6);
  const containerGroupName = `ghr-${jobId}-${suffix}`;
  const { cpu, memoryInGB } = resolveResourceProfile(workflowName);

  await getClient().containerGroups.beginCreateOrUpdateAndWait(rgName, containerGroupName, {
    location,
    osType: 'Linux',
    restartPolicy: 'Never',
    identity: {
      type: 'UserAssigned',
      userAssignedIdentities: {
        [pullIdentityResourceId]: {},
      },
    },
    imageRegistryCredentials: [
      {
        server: acrLoginServer,
        identity: pullIdentityResourceId,
      },
    ],
    containers: [
      {
        name: 'runner',
        image: `${acrLoginServer}/${imageRepository}:${imageTag}`,
        resources: { requests: { cpu, memoryInGB } },
        environmentVariables: [
          { name: 'REPO_URL', value: `https://github.com/${repoFullName}` },
          { name: 'RUNNER_TOKEN', secureValue: registrationToken },
          { name: 'RUNNER_NAME', value: containerGroupName },
          { name: 'RUNNER_LABELS', value: process.env.RUNNER_LABEL || 'aci-runner' },
          { name: 'RUNNER_WORKDIR', value: '_work' },
        ],
      },
    ],
    diagnostics: {
      logAnalytics: {
        workspaceId: lawWorkspaceId,
        workspaceKey: lawKey,
      },
    },
    tags: {
      'managed-by': 'gha-runner-controller',
      job_id: String(jobId),
      run_id: String(runId),
      repo: repoFullName,
      created_at: new Date().toISOString(),
    },
  });

  return containerGroupName;
}

async function listManagedContainerGroups() {
  const rgName = process.env.ACI_RESOURCE_GROUP_NAME;
  const groups = [];
  for await (const group of getClient().containerGroups.listByResourceGroup(rgName)) {
    if (group.tags && group.tags['managed-by'] === 'gha-runner-controller') {
      groups.push(group);
    }
  }
  return groups;
}

async function deleteContainerGroup(name) {
  const rgName = process.env.ACI_RESOURCE_GROUP_NAME;
  await getClient().containerGroups.beginDeleteAndWait(rgName, name);
}

module.exports = { createRunnerContainerGroup, listManagedContainerGroups, deleteContainerGroup };
