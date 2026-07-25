const { app } = require('@azure/functions');
const crypto = require('crypto');
const { QueueClient } = require('@azure/storage-queue');
const { DefaultAzureCredential } = require('@azure/identity');
const { getSecret } = require('../lib/keyVaultSecrets');

let queueClient;
function getQueueClient() {
  if (!queueClient) {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    const queueName = process.env.JOBS_QUEUE_NAME || 'aci-runner-jobs';
    const url = `https://${accountName}.queue.core.windows.net/${queueName}`;
    queueClient = new QueueClient(url, new DefaultAzureCredential());
  }
  return queueClient;
}

function timingSafeEqualStrings(a, b) {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

async function verifySignature(rawBody, signatureHeader) {
  if (!signatureHeader || !signatureHeader.startsWith('sha256=')) return false;
  const secret = await getSecret('github-app-webhook-secret');
  const expected = 'sha256=' + crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  return timingSafeEqualStrings(expected, signatureHeader);
}

app.http('webhook', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'webhook',
  handler: async (request, context) => {
    const rawBody = await request.text();
    const signature = request.headers.get('x-hub-signature-256');

    if (!(await verifySignature(rawBody, signature))) {
      context.warn('Webhook signature verification failed.');
      return { status: 401, body: 'invalid signature' };
    }

    const eventType = request.headers.get('x-github-event');
    if (eventType !== 'workflow_job') {
      return { status: 204 };
    }

    const payload = JSON.parse(rawBody);
    if (payload.action !== 'queued') {
      return { status: 204 };
    }

    const job = payload.workflow_job;
    const requiredLabel = process.env.RUNNER_LABEL || 'aci-runner';
    if (!job.labels || !job.labels.includes(requiredLabel)) {
      return { status: 204 };
    }

    const expectedRepo = process.env.GITHUB_REPO_FULL_NAME;
    if (payload.repository.full_name !== expectedRepo) {
      context.warn(`Rejected workflow_job from unexpected repository: ${payload.repository.full_name}`);
      return { status: 403 };
    }

    // フォークPR由来のジョブは拒否する(多層防御。現状pushトリガーのみだが将来pull_requestが
    // 追加された場合に備える)。
    const pullRequests = job.pull_requests || [];
    for (const pr of pullRequests) {
      if (pr.head && pr.head.repo && pr.head.repo.id !== payload.repository.id) {
        context.warn(`Rejected workflow_job originating from a fork PR (job id: ${job.id}).`);
        return { status: 403 };
      }
    }

    const message = {
      jobId: job.id,
      runId: job.run_id,
      repoFullName: payload.repository.full_name,
      workflowName: job.workflow_name,
      labels: job.labels,
    };
    await getQueueClient().sendMessage(Buffer.from(JSON.stringify(message)).toString('base64'));

    context.log(`Enqueued job ${job.id} (${job.workflow_name}) for ACI runner provisioning.`);
    return { status: 202 };
  },
});
