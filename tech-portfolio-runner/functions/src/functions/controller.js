const { app } = require('@azure/functions');
const { getRunnerRegistrationToken } = require('../lib/githubApp');
const { createRunnerContainerGroup } = require('../lib/aciRunner');
const { upsertRunnerInstance } = require('../lib/runnerTable');

app.storageQueue('controller', {
  queueName: process.env.JOBS_QUEUE_NAME || 'aci-runner-jobs',
  connection: 'AzureWebJobsStorage',
  handler: async (queueItem, context) => {
    const message = typeof queueItem === 'string' ? JSON.parse(queueItem) : queueItem;
    const { jobId, runId, repoFullName, workflowName } = message;

    context.log(`Provisioning ACI runner for job ${jobId} (${workflowName})`);

    const registrationToken = await getRunnerRegistrationToken();
    const containerGroupName = await createRunnerContainerGroup({
      jobId,
      runId,
      repoFullName,
      workflowName,
      registrationToken,
    });

    await upsertRunnerInstance({
      containerGroupName,
      jobId: String(jobId),
      runId: String(runId),
      repo: repoFullName,
      workflowName,
      state: 'Creating',
      createdAt: new Date().toISOString(),
    });

    context.log(`Created ACI container group ${containerGroupName} for job ${jobId}.`);
  },
});
