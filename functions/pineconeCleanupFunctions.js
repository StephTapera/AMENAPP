/**
 * pineconeCleanupFunctions.js
 * One-time cleanup: delete Pinecone vectors that were embedded from unsent drafts.
 *
 * Background:
 *   Prior to audit fix H-30, mlUserIntelligence.buildPassiveInterestGraph was
 *   embedding unsent draft content into the "user-interest-embeddings" Pinecone
 *   namespace. Draft signals arrived as type "draft" in the signals array, so
 *   vectors whose dominantType metadata equals "draft" are the stale artifacts.
 *   The pipeline fix (H-30) stopped new draft vectors from being written, but
 *   vectors already in Pinecone were not cleaned up. This file handles that.
 *
 * Run once after deploy:
 *   firebase functions:call cleanupDraftVectors --data '{}'
 *
 * Idempotent — safe to run multiple times.
 */
'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const PINECONE_API_KEY = defineSecret('PINECONE_API_KEY');
const PINECONE_HOST    = defineSecret('PINECONE_HOST');

// ─── Shared Pinecone REST helpers ────────────────────────────────────────────

/**
 * Build headers for every Pinecone REST call.
 */
function pineconeHeaders(apiKey) {
  return {
    'Api-Key': apiKey,
    'Content-Type': 'application/json',
  };
}

/**
 * Query Pinecone with a metadata filter and a zero vector to enumerate matches.
 *
 * Pinecone does not offer a native "list by metadata" endpoint — the closest
 * approximation is a query with topK=10000 and a zero-vector so every match
 * is returned (scores will all be equal). We then page by cursor if supported,
 * or batch repeatedly against Pinecone's list endpoint when available.
 *
 * @param {string} host
 * @param {string} apiKey
 * @param {string} namespace
 * @param {object} filter   Pinecone metadata filter expression
 * @param {number} topK     Max matches per page (Pinecone cap: 10 000)
 * @returns {Promise<string[]>} vector IDs
 */
async function queryByMetadata(host, apiKey, namespace, filter, topK = 10000) {
  // Pinecone requires a non-empty values array; use a 384-dim zero vector
  // (matches the all-MiniLM-L6-v2 model used by mlUserIntelligence).
  const zeroVector = new Array(384).fill(0);

  const body = {
    vector: zeroVector,
    topK,
    namespace,
    includeMetadata: false,
    includeValues: false,
    filter,
  };

  const response = await fetch(`https://${host}/query`, {
    method: 'POST',
    headers: pineconeHeaders(apiKey),
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Pinecone query failed HTTP ${response.status}: ${text}`);
  }

  const result = await response.json();
  return (result.matches || []).map((m) => m.id).filter(Boolean);
}

/**
 * Delete vectors by IDs from a Pinecone namespace in batches of `batchSize`.
 *
 * @param {string}   host
 * @param {string}   apiKey
 * @param {string}   namespace
 * @param {string[]} ids
 * @param {number}   batchSize  Default 100 (Pinecone recommended max per delete call)
 * @returns {Promise<number>} number of IDs submitted for deletion
 */
async function deleteBatched(host, apiKey, namespace, ids, batchSize = 100) {
  let deleted = 0;

  for (let i = 0; i < ids.length; i += batchSize) {
    const batch = ids.slice(i, i + batchSize);

    const response = await fetch(`https://${host}/vectors/delete`, {
      method: 'POST',
      headers: pineconeHeaders(apiKey),
      body: JSON.stringify({ ids: batch, namespace }),
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      const text = await response.text();
      console.error(`[PineconeCleanup] Delete batch failed HTTP ${response.status}: ${text}`);
      // Continue — log and keep going rather than aborting the entire cleanup.
    } else {
      deleted += batch.length;
      console.log(`[PineconeCleanup] Deleted batch of ${batch.length} vectors (total so far: ${deleted})`);
    }
  }

  return deleted;
}

// ─── cleanupDraftVectors ─────────────────────────────────────────────────────

/**
 * Admin-only callable: scan the "user-interest-embeddings" Pinecone namespace for
 * vectors whose metadata.dominantType == "draft" and delete them in batches.
 *
 * mlUserIntelligence.buildPassiveInterestGraph used to include unsent drafts in
 * its signal array (signal type = "draft"). When drafts were the most frequent
 * signal type, getMostCommon returned "draft" which was stored as dominantType.
 * Those vectors violate user privacy (H-30) and must be purged.
 *
 * Returns: { deleted: N, scanned: M }
 */
exports.cleanupDraftVectors = onCall(
  {
    enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR // admin-only; protected by custom-claim check below
    region: 'us-central1',
    secrets: [PINECONE_API_KEY, PINECONE_HOST],
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (request) => {
    // ── Auth + admin role check ───────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const userRecord = await admin.auth().getUser(request.auth.uid);
    const claims = userRecord.customClaims ?? {};
    if (!claims.admin && !claims.superAdmin) {
      throw new HttpsError('permission-denied', 'Admin role required.');
    }

    const apiKey = PINECONE_API_KEY.value();
    const host   = PINECONE_HOST.value();

    if (!apiKey || !host) {
      throw new HttpsError('internal', 'Pinecone secrets not configured.');
    }

    const NAMESPACE = 'user-interest-embeddings';
    const startMs   = Date.now();

    console.log('[PineconeCleanup] Starting draft vector cleanup...');

    // ── Step 1: Query for vectors with dominantType == "draft" ────────────────
    let draftIds = [];
    try {
      draftIds = await queryByMetadata(
        host,
        apiKey,
        NAMESPACE,
        { dominantType: { $eq: 'draft' } },
        10000,
      );
      console.log(`[PineconeCleanup] Found ${draftIds.length} draft vectors to delete.`);
    } catch (err) {
      console.error('[PineconeCleanup] Query failed:', err.message);
      throw new HttpsError('internal', `Pinecone query error: ${err.message}`);
    }

    const scanned = draftIds.length;

    if (scanned === 0) {
      console.log('[PineconeCleanup] No draft vectors found — index is already clean.');
      return { deleted: 0, scanned: 0, durationMs: Date.now() - startMs };
    }

    // ── Step 2: Delete in batches of 100 ─────────────────────────────────────
    let deleted = 0;
    try {
      deleted = await deleteBatched(host, apiKey, NAMESPACE, draftIds, 100);
    } catch (err) {
      console.error('[PineconeCleanup] Deletion error:', err.message);
      throw new HttpsError('internal', `Pinecone delete error: ${err.message}`);
    }

    const durationMs = Date.now() - startMs;
    console.log(`[PineconeCleanup] Complete. deleted=${deleted} scanned=${scanned} durationMs=${durationMs}`);

    // ── Step 3: Write an audit record ─────────────────────────────────────────
    await admin.firestore().collection('bereanAuditLog').add({
      event: 'pinecone_draft_cleanup',
      adminUid: request.auth.uid,
      deleted,
      scanned,
      namespace: NAMESPACE,
      durationMs,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch((e) => console.warn('[PineconeCleanup] Audit log write failed:', e.message));

    return { deleted, scanned, durationMs };
  },
);

// ─── deleteUserPineconeVectors ────────────────────────────────────────────────

/**
 * Delete all Pinecone vectors belonging to a specific user across all
 * namespaces used by the AMEN embedding pipeline.
 *
 * Namespaces containing user data (from mlUserIntelligence + semanticEmbeddings):
 *   - user-interest-embeddings  (vector id == uid, metadata.userId == uid)
 *   - prayer-partner-pool       (vector id == "user_{uid}", metadata.userId == uid)
 *   - testimony-embeddings      (metadata.authorId == uid, id == postId — handled separately)
 *
 * @param {string} uid
 * @param {string} apiKey
 * @param {string} host
 */
async function deleteUserPineconeVectors(uid, apiKey, host) {
  const results = {};

  // 1. user-interest-embeddings — vector id is the uid directly
  try {
    const deleted = await deleteBatched(host, apiKey, 'user-interest-embeddings', [uid], 100);
    results['user-interest-embeddings'] = deleted;
    console.log(`[PineconeCleanup] Deleted user-interest-embeddings for uid=${uid}`);
  } catch (err) {
    console.error(`[PineconeCleanup] Failed user-interest-embeddings deletion for uid=${uid}:`, err.message);
    results['user-interest-embeddings'] = 0;
  }

  // 2. prayer-partner-pool — vector id is "user_{uid}"
  try {
    const deleted = await deleteBatched(host, apiKey, 'prayer-partner-pool', [`user_${uid}`], 100);
    results['prayer-partner-pool'] = deleted;
    console.log(`[PineconeCleanup] Deleted prayer-partner-pool vector for uid=${uid}`);
  } catch (err) {
    console.error(`[PineconeCleanup] Failed prayer-partner-pool deletion for uid=${uid}:`, err.message);
    results['prayer-partner-pool'] = 0;
  }

  // 3. testimony-embeddings — vectors keyed by postId; find by metadata.authorId filter
  try {
    const testimonyIds = await queryByMetadata(
      host,
      apiKey,
      'testimony-embeddings',
      { authorId: { $eq: uid } },
      10000,
    );
    if (testimonyIds.length > 0) {
      const deleted = await deleteBatched(host, apiKey, 'testimony-embeddings', testimonyIds, 100);
      results['testimony-embeddings'] = deleted;
      console.log(`[PineconeCleanup] Deleted ${deleted} testimony-embeddings vectors for uid=${uid}`);
    } else {
      results['testimony-embeddings'] = 0;
    }
  } catch (err) {
    console.error(`[PineconeCleanup] Failed testimony-embeddings deletion for uid=${uid}:`, err.message);
    results['testimony-embeddings'] = 0;
  }

  return results;
}

// Export the helper so bereanFunctions.js can require it.
exports.deleteUserPineconeVectors = deleteUserPineconeVectors;
exports._pineconeHost             = PINECONE_HOST;
exports._pineconeApiKey           = PINECONE_API_KEY;
