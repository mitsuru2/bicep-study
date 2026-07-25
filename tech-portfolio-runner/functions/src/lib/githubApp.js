const jwt = require('jsonwebtoken');
const { getSecret } = require('./keyVaultSecrets');

const GITHUB_API_BASE = 'https://api.github.com';

function buildAppJwt(appId, privateKeyPem) {
  const now = Math.floor(Date.now() / 1000);
  return jwt.sign(
    {
      iat: now - 60,
      exp: now + 9 * 60, // GitHubの上限(10分)より短く設定
      iss: appId,
    },
    privateKeyPem,
    { algorithm: 'RS256' }
  );
}

async function getInstallationAccessToken() {
  const appId = process.env.GITHUB_APP_ID;
  const installationId = process.env.GITHUB_APP_INSTALLATION_ID;
  const privateKeyPem = await getSecret('github-app-private-key');

  const appJwt = buildAppJwt(appId, privateKeyPem);

  const res = await fetch(`${GITHUB_API_BASE}/app/installations/${installationId}/access_tokens`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${appJwt}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!res.ok) {
    throw new Error(`Failed to get installation access token: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  return body.token; // 有効期限1時間
}

// ephemeral runner登録用トークンを取得する(個人PATは使用しない)。
async function getRunnerRegistrationToken() {
  const installationToken = await getInstallationAccessToken();
  const repoFullName = process.env.GITHUB_REPO_FULL_NAME;

  const res = await fetch(`${GITHUB_API_BASE}/repos/${repoFullName}/actions/runners/registration-token`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${installationToken}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!res.ok) {
    throw new Error(`Failed to get runner registration token: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  return body.token;
}

module.exports = { getRunnerRegistrationToken };
