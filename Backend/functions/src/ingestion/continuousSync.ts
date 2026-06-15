/**
 * ingestion/continuousSync.ts
 *
 * Continuous sync engine for the Catalog Ingestion system.
 *
 * INVARIANTS:
 *  - Only syncs sources for works with reviewState='approved' or 'published'
 *  - NEVER re-imports rejected (draft with rejectionReason) or deleted items
 *  - New items from sync land at reviewState='imported', visibility='private'
 *  - Deduplication is handled by importWork() in reviewWorkflow.ts
 */

import * as admin from "firebase-admin";
import { importWork } from "./reviewWorkflow";
import {
  spotifyProvider,
  youtubeProvider,
  appleMusicProvider,
  googleBooksProvider,
  openLibraryProvider,
  podcastRSSProvider,
  substackProvider,
  mediumProvider,
} from "./providers";
import type { SourceProvider, WorkReviewState } from "./providers/types";

const ALL_PROVIDERS: SourceProvider[] = [
  spotifyProvider,
  youtubeProvider,
  appleMusicProvider,
  googleBooksProvider,
  openLibraryProvider,
  podcastRSSProvider,
  substackProvider,
  mediumProvider,
];

const SYNC_ELIGIBLE_STATES: WorkReviewState[] = ["approved", "published"];

// ─── syncApprovedSources ────────────────────────────────────────────────────

/**
 * Re-pull new content from all connected, approved sources for a creator.
 *
 * "Approved source" = a provider that has at least one work in approved/published state.
 * This ensures we only pull from sources the creator has vetted.
 *
 * @returns Summary of items fetched and imported.
 */
export async function syncApprovedSources(creatorId: string): Promise<{
  providersChecked: number;
  newItemsImported: number;
  errors: string[];
}> {
  const db = admin.firestore();
  const errors: string[] = [];

  // Determine which providers have approved/published content for this creator
  const approvedProviders = new Set<string>();

  for (const state of SYNC_ELIGIBLE_STATES) {
    const snap = await db
      .collection("works")
      .where("creatorId", "==", creatorId)
      .where("reviewState", "==", state)
      .where("deletedAt", "==", null)
      .get();

    for (const doc of snap.docs) {
      const providerId = doc.data()["sourceProviderId"] as string | undefined;
      if (providerId) {
        approvedProviders.add(providerId);
      }
    }
  }

  if (approvedProviders.size === 0) {
    return { providersChecked: 0, newItemsImported: 0, errors: [] };
  }

  let newItemsImported = 0;

  for (const provider of ALL_PROVIDERS) {
    if (!approvedProviders.has(provider.id)) continue;
    if (!provider.supportsSync) continue;

    try {
      // Fetch first page of recent items from the provider
      const { items } = await provider.fetch(creatorId);

      for (const rawItem of items) {
        // importWork handles dedup by (creatorId, sourceProviderId, externalId)
        const work = provider.normalize(creatorId, rawItem);

        // Double-check: work must be private+imported
        if (work.visibility !== "private" || work.reviewState !== "imported") {
          errors.push(`provider_${provider.id}_returned_non_private_work`);
          continue;
        }

        const workId = await importWork(creatorId, work);
        // importWork returns existing ID if dedup hit — only count new
        const isNew = await db
          .collection("works")
          .doc(workId)
          .get()
          .then((snap) => {
            const data = snap.data();
            if (!data) return false;
            const createdAt = data["createdAt"] as admin.firestore.Timestamp;
            const updatedAt = data["updatedAt"] as admin.firestore.Timestamp;
            // New if createdAt and updatedAt are within 5 seconds of each other
            return Math.abs(createdAt.toMillis() - updatedAt.toMillis()) < 5000;
          });

        if (isNew) newItemsImported++;
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      errors.push(`provider_${provider.id}_sync_error: ${msg}`);
    }
  }

  // Write sync log
  try {
    await db
      .collection("creatorSyncLogs")
      .doc(`${creatorId}_${Date.now()}`)
      .set({
        creatorId,
        syncedAt: admin.firestore.Timestamp.now(),
        providersChecked: approvedProviders.size,
        newItemsImported,
        errors,
      });
  } catch {
    // Non-fatal: log write failed
  }

  return {
    providersChecked: approvedProviders.size,
    newItemsImported,
    errors,
  };
}

// ─── syncSingleProvider ─────────────────────────────────────────────────────

/**
 * Sync a single provider for a creator (used by connectSource on first connect).
 * Provider must be in approved/connected state — first connection is authorized separately.
 */
export async function syncSingleProvider(
  creatorId: string,
  providerId: string,
  cursor?: string
): Promise<{
  itemsImported: number;
  nextCursor?: string;
  error?: string;
}> {
  const provider = ALL_PROVIDERS.find((p) => p.id === providerId);
  if (!provider) {
    return { itemsImported: 0, error: `unknown_provider: ${providerId}` };
  }

  try {
    const { items, nextCursor } = await provider.fetch(creatorId, cursor);
    let itemsImported = 0;

    for (const rawItem of items) {
      const work = provider.normalize(creatorId, rawItem);

      if (work.visibility !== "private" || work.reviewState !== "imported") {
        continue;
      }

      await importWork(creatorId, work);
      itemsImported++;
    }

    return { itemsImported, nextCursor };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return { itemsImported: 0, error: msg };
  }
}
