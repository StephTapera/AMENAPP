/**
 * ingestionEngine.js
 * Main orchestrator for the AMEN Catalog ingestion pipeline.
 *
 * Responsibilities:
 *   - Create and manage IngestionJob documents
 *   - Call SourceProvider adapters and save normalized Works
 *   - Deduplicate by (creatorId, source.provider, source.externalId)
 *   - Enforce max 500 items per run and 5 triggers per creator per hour
 *
 * Does NOT call AI (no callModel import here — ingestion is deterministic).
 */

'use strict';

const admin = require('firebase-admin');

// SourceProvider registry — all provider modules
const PROVIDERS = {
  spotify:      require('./providers/spotifyProvider'),
  youtube:      require('./providers/youtubeProvider'),
  google_books: require('./providers/googleBooksProvider'),
  podcast_rss:  require('./providers/podcastRSSProvider'),
  substack:     require('./providers/substackProvider'),
};

const MAX_ITEMS_PER_RUN = 500;
// Rate limit: max 5 ingestion triggers per creator per hour
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ─── Rate Limiting ────────────────────────────────────────────────────────────

/**
 * Check whether a creator has exceeded ingestion trigger rate limit.
 * Reads ingestionJobs created within the last hour.
 * Throws if limit exceeded.
 */
async function checkIngestionRateLimit(creatorId) {
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
  const snap = await db()
    .collection('ingestionJobs')
    .where('creatorId', '==', creatorId)
    .where('createdAt', '>=', windowStart)
    .get();

  if (snap.size >= RATE_LIMIT_MAX) {
    const err = new Error(
      `Ingestion rate limit: max ${RATE_LIMIT_MAX} triggers per hour. ` +
      `You have ${snap.size} recent jobs. Please wait before triggering again.`
    );
    err.code = 'ingestion_rate_limit_exceeded';
    throw err;
  }
}

// ─── IngestionJob helpers ─────────────────────────────────────────────────────

/**
 * Create a new IngestionJob document in Firestore.
 * Returns the new job id.
 */
async function createJob(creatorId, provider) {
  const ref = db().collection('ingestionJobs').doc();
  await ref.set({
    id: ref.id,
    creatorId,
    provider,
    status: 'pending',
    cursor: null,
    itemsFound: 0,
    itemsImported: 0,
    errorMessage: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return ref.id;
}

/**
 * Update job fields.
 */
async function updateJob(jobId, fields) {
  await db()
    .collection('ingestionJobs')
    .doc(jobId)
    .update({ ...fields, updatedAt: FieldValue.serverTimestamp() });
}

// ─── Deduplication ────────────────────────────────────────────────────────────

/**
 * Check if a work already exists for this creator + provider + externalId.
 * Returns the existing work id or null.
 */
async function deduplicateWork(creatorId, provider, externalId) {
  // provider stored in source.provider — query on composite source fields
  // Note: Firestore does not support querying nested fields with dots in index
  // We query by creatorId and source.externalId, then filter on provider in memory
  // (a composite index on creatorId + source.externalId is sufficient for small catalogs)
  const snap = await db()
    .collection('works')
    .where('creatorId', '==', creatorId)
    .where('source.externalId', '==', externalId)
    .where('deletedAt', '==', null)
    .limit(5)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.source && data.source.provider === provider) {
      return doc.id;
    }
  }
  return null;
}

// ─── Save Work ────────────────────────────────────────────────────────────────

/**
 * Write a normalized work to Firestore. Deduplicates before writing.
 * Returns { workId, isNew: boolean }.
 */
async function saveWork(workData) {
  const { creatorId, source } = workData;
  if (!creatorId || !source || !source.provider || !source.externalId) {
    throw new Error('saveWork: workData must include creatorId and source.{provider,externalId}');
  }

  // Deduplication check
  const existingId = await deduplicateWork(creatorId, source.provider, source.externalId);
  if (existingId) {
    // Work already exists — update metadata only, do not reset reviewState or visibility
    await db()
      .collection('works')
      .doc(existingId)
      .update({
        title: workData.title,
        subtitle: workData.subtitle || null,
        description: workData.description || null,
        coverUrl: workData.coverUrl || null,
        publishedAt: workData.publishedAt || null,
        links: workData.links || [],
        updatedAt: FieldValue.serverTimestamp(),
      });
    return { workId: existingId, isNew: false };
  }

  // New work — generate a new doc id and write full document
  const ref = db().collection('works').doc();
  const workId = ref.id;
  await ref.set({
    ...workData,
    id: workId,
    // Ensure safe defaults
    visibility: 'private',
    reviewState: workData.reviewState || 'imported',
    ingestMode: workData.ingestMode || 'auto',
    verifiedOwnership: workData.verifiedOwnership || false,
    embeddingRef: null,
    transcriptRef: null,
    deletedAt: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, isNew: true };
}

// ─── Main Ingestion ───────────────────────────────────────────────────────────

/**
 * Start an ingestion job for a creator and provider.
 *
 * @param {string} creatorId    - Firebase Auth UID
 * @param {string} provider     - Provider id: 'spotify' | 'youtube' | 'google_books' | 'podcast_rss' | 'substack'
 * @param {string} accessToken  - OAuth access token or feed URL (provider-specific)
 * @param {object} [opts]       - Additional options passed as initial cursor (e.g. { authorName, feedUrl })
 * @returns {Promise<{ jobId: string, itemsImported: number, itemsFound: number }>}
 */
async function startIngestion(creatorId, provider, accessToken, opts = {}) {
  if (!PROVIDERS[provider]) {
    throw new Error(`Unknown provider: "${provider}". Valid: ${Object.keys(PROVIDERS).join(', ')}`);
  }

  // Rate limit check
  await checkIngestionRateLimit(creatorId);

  const providerModule = PROVIDERS[provider];
  const jobId = await createJob(creatorId, provider);

  await updateJob(jobId, { status: 'running' });

  let itemsFound = 0;
  let itemsImported = 0;
  let cursor = Object.keys(opts).length > 0 ? opts : null;

  try {
    // Paginate until no nextCursor or we hit the item cap
    while (itemsFound < MAX_ITEMS_PER_RUN) {
      const result = await providerModule.fetch(creatorId, accessToken, cursor);
      const works = result.works || [];
      itemsFound += works.length;

      // Save works up to the cap
      const toSave = works.slice(0, MAX_ITEMS_PER_RUN - (itemsFound - works.length));
      for (const work of toSave) {
        const { isNew } = await saveWork(work);
        if (isNew) itemsImported++;
      }

      // Advance cursor
      if (result.nextCursor) {
        cursor = result.nextCursor;
        await updateJob(jobId, {
          cursor,
          itemsFound,
          itemsImported,
        });
      } else {
        break; // No more pages
      }

      // Hard stop at cap
      if (itemsFound >= MAX_ITEMS_PER_RUN) {
        console.log(`[ingestionEngine] Hit ${MAX_ITEMS_PER_RUN} item cap for job ${jobId}`);
        break;
      }
    }

    await updateJob(jobId, {
      status: 'done',
      cursor: null,
      itemsFound,
      itemsImported,
    });

    return { jobId, itemsFound, itemsImported };
  } catch (err) {
    console.error(`[ingestionEngine] Job ${jobId} failed:`, err.message);
    await updateJob(jobId, {
      status: 'error',
      errorMessage: err.message,
      itemsFound,
      itemsImported,
    });
    throw err;
  }
}

// ─── Sync Approved Sources ────────────────────────────────────────────────────

/**
 * Re-fetch works for all approved/published auto-sync sources for a creator.
 * Only re-syncs works with ingestMode='auto' and reviewState in ['approved','published'].
 *
 * @param {string} creatorId
 * @returns {Promise<{ synced: number, errors: string[] }>}
 */
async function syncApprovedSources(creatorId) {
  // Find distinct (provider, source) combos for approved/published auto works
  const snap = await db()
    .collection('works')
    .where('creatorId', '==', creatorId)
    .where('ingestMode', '==', 'auto')
    .where('deletedAt', '==', null)
    .get();

  const providers = new Set();
  for (const doc of snap.docs) {
    const data = doc.data();
    if (
      data.reviewState === 'approved' ||
      data.reviewState === 'published'
    ) {
      providers.add(data.source && data.source.provider ? data.source.provider : null);
    }
  }
  providers.delete(null);

  // Load connected sources to get access tokens
  // (tokens are passed per-call; for sync, retrieve from user's connectedSources)
  const sourcesSnap = await db()
    .collection('users')
    .doc(creatorId)
    .collection('connectedSources')
    .get();

  const sourcesByProvider = {};
  for (const doc of sourcesSnap.docs) {
    sourcesByProvider[doc.id] = doc.data();
  }

  let synced = 0;
  const errors = [];

  for (const provider of providers) {
    const sourceData = sourcesByProvider[provider];
    if (!sourceData) {
      errors.push(`No connected source found for provider: ${provider}`);
      continue;
    }

    try {
      // accessToken reference is stored; the actual token is fetched from Firebase credentials
      // For sync, we pass the stored tokenRef (provider-specific resolution happens in CF)
      const { itemsImported } = await startIngestion(
        creatorId,
        provider,
        sourceData.tokenRef || '', // tokenRef, not raw token
        sourceData.fetchOpts || {}
      );
      synced += itemsImported;
    } catch (err) {
      errors.push(`${provider}: ${err.message}`);
    }
  }

  return { synced, errors };
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  startIngestion,
  syncApprovedSources,
  deduplicateWork,
  saveWork,
  PROVIDERS,
};
