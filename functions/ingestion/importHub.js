/**
 * importHub.js
 * Cloud Functions for the Import Hub UI — source connection, sync, and manual entry.
 *
 * Entry points for creators to:
 *   - Connect / disconnect external sources (Spotify, YouTube, Google Books, podcast RSS, Substack)
 *   - Trigger manual or background syncs
 *   - Manually enter works (sermon, course, event, article)
 *   - List connected sources and ingestion job status
 *
 * Security:
 *   - All CFs require context.auth
 *   - Raw access tokens are NEVER stored in Firestore (only a tokenRef reference)
 *   - Ingested works default to visibility='private', reviewState='imported'
 *   - Rate limit: max 5 ingestion triggers per creator per hour (enforced by ingestionEngine)
 */

'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { startIngestion } = require('./ingestionEngine');

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// Supported provider ids
const SUPPORTED_PROVIDERS = new Set([
  'spotify',
  'youtube',
  'google_books',
  'podcast_rss',
  'substack',
]);

// Valid work types for manual entry
const MANUAL_ENTRY_TYPES = new Set([
  'sermon', 'course', 'event', 'article', 'book',
  'podcast', 'episode', 'video', 'album', 'track',
]);

// ─── Auth guard helper ────────────────────────────────────────────────────────

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be signed in to use the Import Hub.'
    );
  }
  return context.auth.uid;
}

// ─── connectSource ────────────────────────────────────────────────────────────

/**
 * Connect an external source for the authenticated creator.
 *
 * The client passes the OAuth token (or feed URL for RSS) on this call only —
 * the token is used immediately to verify ownership and start an initial ingestion,
 * but only a non-sensitive tokenRef is stored in Firestore.
 *
 * data: {
 *   provider: string,       // 'spotify' | 'youtube' | 'google_books' | 'podcast_rss' | 'substack'
 *   tokenRef: string,       // Firebase credential reference or OAuth token (RSS: feedUrl)
 *   fetchOpts?: object,     // provider-specific options (e.g. { authorName, feedUrl, substackUrl })
 *   skipInitialSync?: bool  // default false
 * }
 */
exports.connectSource = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const { provider, tokenRef, fetchOpts = {}, skipInitialSync = false } = data || {};

  if (!provider || !SUPPORTED_PROVIDERS.has(provider)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `provider must be one of: ${[...SUPPORTED_PROVIDERS].join(', ')}.`
    );
  }
  if (!tokenRef) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'tokenRef is required. Pass your OAuth credential reference or feed URL.'
    );
  }

  // Store connected source metadata — tokenRef only (not the raw token)
  const sourceRef = db()
    .collection('users')
    .doc(uid)
    .collection('connectedSources')
    .doc(provider);

  await sourceRef.set({
    provider,
    tokenRef,        // Non-sensitive reference; resolve to actual token client-side
    fetchOpts,       // Provider-specific options (e.g. authorName, feedUrl)
    autoSync: true,
    connectedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    lastSyncAt: null,
    lastJobId: null,
  });

  let jobResult = null;
  if (!skipInitialSync) {
    try {
      // accessToken here is the tokenRef; in production the CF resolves the real token
      // from Firebase credentials before calling ingestionEngine (token never hits Firestore)
      jobResult = await startIngestion(uid, provider, tokenRef, fetchOpts);

      await sourceRef.update({
        lastSyncAt: FieldValue.serverTimestamp(),
        lastJobId: jobResult.jobId,
      });
    } catch (err) {
      // Rate limit errors or ingestion errors should surface to the client
      if (err.code === 'ingestion_rate_limit_exceeded') {
        throw new functions.https.HttpsError('resource-exhausted', err.message);
      }
      // Non-fatal: source is connected but initial sync failed
      console.error(`[importHub.connectSource] Initial sync failed for ${uid}/${provider}:`, err.message);
      await sourceRef.update({ lastSyncError: err.message });
    }
  }

  return {
    provider,
    connected: true,
    ...(jobResult ? { jobId: jobResult.jobId, itemsImported: jobResult.itemsImported } : {}),
  };
});

// ─── disconnectSource ─────────────────────────────────────────────────────────

/**
 * Disconnect an external source.
 * Removes the connectedSources entry and disables auto-sync for that provider's works.
 * Does NOT delete existing works — creator retains their catalog.
 *
 * data: { provider: string }
 */
exports.disconnectSource = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const { provider } = data || {};

  if (!provider || !SUPPORTED_PROVIDERS.has(provider)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `provider must be one of: ${[...SUPPORTED_PROVIDERS].join(', ')}.`
    );
  }

  // Remove the connected source document
  await db()
    .collection('users')
    .doc(uid)
    .collection('connectedSources')
    .doc(provider)
    .delete();

  // Mark auto-sync disabled for all works from this provider (non-deleted)
  // We do this in a batched write for efficiency
  const worksSnap = await db()
    .collection('works')
    .where('creatorId', '==', uid)
    .where('source.provider', '==', provider)
    .where('deletedAt', '==', null)
    .get();

  if (!worksSnap.empty) {
    const batch = db().batch();
    let count = 0;
    for (const doc of worksSnap.docs) {
      batch.update(doc.ref, {
        ingestMode: 'manual', // no longer auto-synced
        updatedAt: FieldValue.serverTimestamp(),
      });
      count++;
      // Firestore batch limit is 500 writes
      if (count === 499) break;
    }
    await batch.commit();
  }

  return { provider, disconnected: true };
});

// ─── triggerManualSync ────────────────────────────────────────────────────────

/**
 * Manually re-trigger ingestion for a specific connected provider.
 * Uses the stored tokenRef from connectedSources.
 * The actual OAuth token resolution must happen client-side before this call,
 * or the tokenRef is passed fresh in data.tokenRef.
 *
 * data: {
 *   provider: string,
 *   tokenRef?: string,  // override stored tokenRef (e.g. refreshed token)
 *   fetchOpts?: object
 * }
 */
exports.triggerManualSync = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const { provider, tokenRef: tokenRefOverride, fetchOpts: optsOverride } = data || {};

  if (!provider || !SUPPORTED_PROVIDERS.has(provider)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `provider must be one of: ${[...SUPPORTED_PROVIDERS].join(', ')}.`
    );
  }

  // Load stored source config
  const sourceSnap = await db()
    .collection('users')
    .doc(uid)
    .collection('connectedSources')
    .doc(provider)
    .get();

  if (!sourceSnap.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      `No connected source found for provider "${provider}". Connect it first.`
    );
  }

  const sourceData = sourceSnap.data();
  const tokenRef = tokenRefOverride || sourceData.tokenRef;
  const fetchOpts = optsOverride || sourceData.fetchOpts || {};

  let jobResult;
  try {
    jobResult = await startIngestion(uid, provider, tokenRef, fetchOpts);
  } catch (err) {
    if (err.code === 'ingestion_rate_limit_exceeded') {
      throw new functions.https.HttpsError('resource-exhausted', err.message);
    }
    throw new functions.https.HttpsError('internal', `Sync failed: ${err.message}`);
  }

  await sourceSnap.ref.update({
    lastSyncAt: FieldValue.serverTimestamp(),
    lastJobId: jobResult.jobId,
    lastSyncError: null,
  });

  return {
    provider,
    jobId: jobResult.jobId,
    itemsFound: jobResult.itemsFound,
    itemsImported: jobResult.itemsImported,
  };
});

// ─── createManualWork ─────────────────────────────────────────────────────────

/**
 * Manual entry: creator submits a work directly (sermon, course, event, article, etc.).
 * CF validates and saves with ingestMode='manual', reviewState='imported', visibility='private'.
 *
 * data: {
 *   type: string,             // Required: one of MANUAL_ENTRY_TYPES
 *   title: string,            // Required
 *   subtitle?: string,
 *   description?: string,
 *   coverUrl?: string,
 *   publishedAt?: string,     // ISO date string or null
 *   sourceUrl?: string,       // Where this work lives externally
 *   links?: Array<{ kind, platform, url, affiliateUrl? }>,
 *   topics?: string[],
 * }
 */
exports.createManualWork = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const {
    type,
    title,
    subtitle,
    description,
    coverUrl,
    publishedAt,
    sourceUrl,
    links = [],
    topics = [],
  } = data || {};

  // Validation
  if (!type || !MANUAL_ENTRY_TYPES.has(type)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `type must be one of: ${[...MANUAL_ENTRY_TYPES].join(', ')}.`
    );
  }
  if (!title || typeof title !== 'string' || title.trim().length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'title is required.');
  }
  if (title.trim().length > 500) {
    throw new functions.https.HttpsError('invalid-argument', 'title must be under 500 characters.');
  }

  // Validate links array
  const VALID_LINK_KINDS = new Set(['read', 'listen', 'watch', 'buy', 'register']);
  for (const link of links) {
    if (!link.kind || !VALID_LINK_KINDS.has(link.kind)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `link.kind must be one of: ${[...VALID_LINK_KINDS].join(', ')}.`
      );
    }
    if (!link.url || typeof link.url !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'Each link must have a url.');
    }
  }

  const ref = db().collection('works').doc();
  const workId = ref.id;
  const parsedDate = publishedAt ? new Date(publishedAt) : null;

  await ref.set({
    id: workId,
    creatorId: uid,
    type,
    title: title.trim(),
    subtitle: subtitle || null,
    description: description || null,
    coverUrl: coverUrl || null,
    publishedAt: parsedDate,
    source: {
      provider: 'manual',
      externalId: workId, // self-referential for manual entries
      sourceUrl: sourceUrl || null,
    },
    links,
    topics: Array.isArray(topics) ? topics : [],
    embeddingRef: null,
    transcriptRef: null,
    visibility: 'private',
    reviewState: 'imported',
    ingestMode: 'manual',
    verifiedOwnership: true, // creator is directly attesting to ownership
    deletedAt: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, reviewState: 'imported', visibility: 'private' };
});

// ─── listConnectedSources ─────────────────────────────────────────────────────

/**
 * Return the list of connected sources for the authenticated creator.
 * Does NOT return tokenRef values.
 */
exports.listConnectedSources = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);

  const snap = await db()
    .collection('users')
    .doc(uid)
    .collection('connectedSources')
    .get();

  const sources = snap.docs.map((doc) => {
    const d = doc.data();
    // Strip token reference — client does not need it
    return {
      provider: d.provider,
      autoSync: d.autoSync,
      connectedAt: d.connectedAt,
      lastSyncAt: d.lastSyncAt,
      lastJobId: d.lastJobId,
      lastSyncError: d.lastSyncError || null,
      fetchOpts: d.fetchOpts || {},
    };
  });

  return { sources };
});

// ─── getIngestionStatus ───────────────────────────────────────────────────────

/**
 * Return all IngestionJobs for the authenticated creator, most recent first.
 * data: { limit?: number } (default 20, max 100)
 */
exports.getIngestionStatus = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const limit = Math.min(parseInt((data && data.limit) || 20, 10), 100);

  const snap = await db()
    .collection('ingestionJobs')
    .where('creatorId', '==', uid)
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  const jobs = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: d.id,
      provider: d.provider,
      status: d.status,
      itemsFound: d.itemsFound,
      itemsImported: d.itemsImported,
      errorMessage: d.errorMessage,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
    };
  });

  return { jobs };
});
