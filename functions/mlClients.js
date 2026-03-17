/**
 * Shared ML Client Library for AMEN Cloud Functions
 *
 * Provides Hugging Face inference, Pinecone vector DB,
 * and Secret Manager integration with retry logic,
 * caching, and structured logging.
 */

let SecretManagerServiceClient;
try {
  SecretManagerServiceClient = require("@google-cloud/secret-manager").SecretManagerServiceClient;
} catch (e) {
  // Secret Manager SDK not installed — will use env vars only
  SecretManagerServiceClient = null;
}
const admin = require("firebase-admin");

// ═══════════════════════════════════════════
// SECRET MANAGER
// ═══════════════════════════════════════════

const secretCache = {};

/**
 * Fetch a secret from Google Secret Manager with in-memory caching.
 * Falls back to process.env for local emulator development.
 */
async function getSecret(name) {
  if (secretCache[name]) return secretCache[name];

  // Local dev fallback
  if (process.env[name]) {
    secretCache[name] = process.env[name];
    return secretCache[name];
  }

  try {
    if (!SecretManagerServiceClient) {
      console.warn(`[SecretManager] SDK not installed — secret "${name}" unavailable`);
      return null;
    }
    const client = new SecretManagerServiceClient();
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    const [version] = await client.accessSecretVersion({
      name: `projects/${projectId}/secrets/${name}/versions/latest`,
    });
    const value = version.payload.data.toString("utf8");
    secretCache[name] = value;
    return value;
  } catch (err) {
    console.error(`[SecretManager] Failed to fetch secret "${name}":`, err.message);
    return null;
  }
}

// ═══════════════════════════════════════════
// HUGGING FACE CLIENT
// ═══════════════════════════════════════════

const hfResultCache = new Map();
const HF_CACHE_MAX = 500;

/**
 * Call Hugging Face Inference API with retry, caching, and cost logging.
 *
 * @param {string} model - HF model identifier (e.g. "sentence-transformers/all-MiniLM-L6-v2")
 * @param {string|object} inputs - Text input or structured input
 * @param {object} options - { retries: 3, parameters: {} }
 * @returns {Promise<any>} Model output
 */
async function hfInference(model, inputs, options = {}) {
  const { retries = 3, parameters = {} } = options;
  const startMs = Date.now();

  // Check cache
  const cacheKey = JSON.stringify({ model, inputs, parameters });
  if (hfResultCache.has(cacheKey)) {
    console.log(`[HF] Cache hit for ${model}`);
    return hfResultCache.get(cacheKey);
  }

  const apiKey = await getSecret("HUGGINGFACE_API_KEY");
  if (!apiKey) {
    console.warn(`[HF] No API key found — skipping ${model} inference`);
    return null;
  }

  let lastError = null;

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const body = parameters && Object.keys(parameters).length > 0
        ? { inputs, parameters }
        : { inputs };

      const response = await fetch(`https://api-inference.huggingface.co/models/${model}`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15000), // 15s timeout
      });

      if (response.status === 503) {
        // Model loading — wait and retry
        const waitTime = Math.pow(2, attempt) * 1000;
        console.log(`[HF] Model ${model} loading, retry in ${waitTime}ms (attempt ${attempt})`);
        await sleep(waitTime);
        continue;
      }

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${await response.text()}`);
      }

      const result = await response.json();
      const durationMs = Date.now() - startMs;

      // Cache result
      if (hfResultCache.size >= HF_CACHE_MAX) {
        const firstKey = hfResultCache.keys().next().value;
        hfResultCache.delete(firstKey);
      }
      hfResultCache.set(cacheKey, result);

      console.log(`[HF] ${model} completed in ${durationMs}ms (attempt ${attempt})`);
      return result;
    } catch (err) {
      lastError = err;
      if (attempt < retries) {
        const backoff = Math.pow(2, attempt) * 500;
        console.warn(`[HF] ${model} attempt ${attempt} failed: ${err.message}. Retrying in ${backoff}ms`);
        await sleep(backoff);
      }
    }
  }

  console.error(`[HF] ${model} failed after ${retries} attempts:`, lastError?.message);
  return null;
}

// ═══════════════════════════════════════════
// PINECONE CLIENT
// ═══════════════════════════════════════════

let pineconeHost = null;

async function getPineconeConfig() {
  if (pineconeHost) return { host: pineconeHost };
  const apiKey = await getSecret("PINECONE_API_KEY");
  const host = await getSecret("PINECONE_HOST");
  pineconeHost = host;
  return { apiKey, host };
}

/**
 * Upsert vectors to a Pinecone index.
 *
 * @param {string} namespace - Pinecone namespace
 * @param {Array<{id: string, values: number[], metadata?: object}>} vectors
 */
async function pineconeUpsert(namespace, vectors) {
  const startMs = Date.now();
  const config = await getPineconeConfig();
  const apiKey = await getSecret("PINECONE_API_KEY");

  if (!apiKey || !config.host) {
    console.warn("[Pinecone] Not configured — skipping upsert");
    return;
  }

  try {
    const response = await fetch(`https://${config.host}/vectors/upsert`, {
      method: "POST",
      headers: {
        "Api-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ vectors, namespace }),
      signal: AbortSignal.timeout(5000), // 500ms too aggressive for upserts, use 5s
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    console.log(`[Pinecone] Upserted ${vectors.length} vectors to ${namespace} in ${Date.now() - startMs}ms`);
  } catch (err) {
    console.error(`[Pinecone] Upsert failed for ${namespace}:`, err.message);
  }
}

/**
 * Query Pinecone index for similar vectors.
 *
 * @param {string} namespace
 * @param {number[]} vector - Query vector
 * @param {number} topK - Number of results
 * @param {object} filter - Metadata filter
 * @returns {Promise<Array<{id: string, score: number, metadata: object}>>}
 */
async function pineconeQuery(namespace, vector, topK = 5, filter = undefined) {
  const startMs = Date.now();
  const config = await getPineconeConfig();
  const apiKey = await getSecret("PINECONE_API_KEY");

  if (!apiKey || !config.host) {
    console.warn("[Pinecone] Not configured — returning empty results");
    return [];
  }

  try {
    const body = {
      vector,
      topK,
      namespace,
      includeMetadata: true,
    };
    if (filter) body.filter = filter;

    const response = await fetch(`https://${config.host}/query`, {
      method: "POST",
      headers: {
        "Api-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(3000), // 3s timeout for queries
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    const result = await response.json();
    console.log(`[Pinecone] Query ${namespace} returned ${result.matches?.length || 0} results in ${Date.now() - startMs}ms`);
    return result.matches || [];
  } catch (err) {
    console.error(`[Pinecone] Query failed for ${namespace}:`, err.message);
    return [];
  }
}

/**
 * Delete a vector from Pinecone.
 */
async function pineconeDelete(namespace, ids) {
  const config = await getPineconeConfig();
  const apiKey = await getSecret("PINECONE_API_KEY");

  if (!apiKey || !config.host) return;

  try {
    await fetch(`https://${config.host}/vectors/delete`, {
      method: "POST",
      headers: {
        "Api-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ids, namespace }),
      signal: AbortSignal.timeout(3000),
    });
    console.log(`[Pinecone] Deleted ${ids.length} vectors from ${namespace}`);
  } catch (err) {
    console.error(`[Pinecone] Delete failed:`, err.message);
  }
}

// ═══════════════════════════════════════════
// STRUCTURED LOGGER
// ═══════════════════════════════════════════

function logFunction(functionName, data = {}) {
  console.log(JSON.stringify({
    severity: data.error ? "ERROR" : "INFO",
    function: functionName,
    durationMs: data.durationMs || 0,
    success: !data.error,
    ...data,
    timestamp: new Date().toISOString(),
  }));
}

// ═══════════════════════════════════════════
// RATE LIMITER
// ═══════════════════════════════════════════

const db = admin.firestore();

/**
 * Simple rate limiter: max N calls per minute per user.
 * @returns {boolean} true if allowed, false if rate limited
 */
async function checkRateLimit(userId, functionName, maxPerMinute = 10) {
  const key = `rateLimits/${userId}_${functionName}`;
  const ref = admin.database().ref(key);

  const snap = await ref.get();
  const data = snap.val() || { count: 0, resetAt: 0 };
  const now = Date.now();

  if (now > data.resetAt) {
    // Reset window
    await ref.set({ count: 1, resetAt: now + 60000 });
    return true;
  }

  if (data.count >= maxPerMinute) {
    console.warn(`[RateLimit] ${userId} exceeded ${maxPerMinute}/min on ${functionName}`);
    return false;
  }

  await ref.update({ count: data.count + 1 });
  return true;
}

// ═══════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function cosineSimilarity(a, b) {
  if (!a || !b || a.length !== b.length) return 0;
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denominator = Math.sqrt(normA) * Math.sqrt(normB);
  return denominator === 0 ? 0 : dotProduct / denominator;
}

module.exports = {
  getSecret,
  hfInference,
  pineconeUpsert,
  pineconeQuery,
  pineconeDelete,
  logFunction,
  checkRateLimit,
  sleep,
  cosineSimilarity,
};
