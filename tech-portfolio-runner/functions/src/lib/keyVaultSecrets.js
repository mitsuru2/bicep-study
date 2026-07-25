const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

let client;
function getClient() {
  if (!client) {
    const vaultUri = process.env.KEY_VAULT_URI;
    if (!vaultUri) {
      throw new Error('KEY_VAULT_URI is not configured.');
    }
    client = new SecretClient(vaultUri, new DefaultAzureCredential());
  }
  return client;
}

// Key Vaultへの呼び出し回数を抑えるため、プロセス内で短時間キャッシュする。
const cache = new Map();
const CACHE_TTL_MS = 5 * 60 * 1000;

async function getSecret(name) {
  const cached = cache.get(name);
  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
    return cached.value;
  }
  const secret = await getClient().getSecret(name);
  cache.set(name, { value: secret.value, fetchedAt: Date.now() });
  return secret.value;
}

module.exports = { getSecret };
