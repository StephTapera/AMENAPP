/**
 * ingestion/importHub.ts
 *
 * Firebase Cloud Functions for the Catalog Import Hub.
 * All deployed to us-east1 (us-central1 quota exhausted — see CLAUDE.md).
 *
 * Callables:
 *  - connectSource: authorize + first-page fetch for a provider
 *  - listPendingImports: items in 'imported' state awaiting creator review
 *  - createCatalogWork: create a manual work entry
 *  - advanceWorkReviewState: move work to next review state
 *  - publishWork: explicitly publish an approved work (HUMAN GATE: confirmed=true)
 *
 * INVARIANTS:
 *  - All items stay private until creator explicitly approves + publishes
 *  - Never deploy this file without adding to Interim Region Table in docs/FUNCTION_INVENTORY.md
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
  spotifyProvider,
  youtubeProvider,
  appleMusicProvider,
  googleBooksProvider,
  openLibraryProvider,
  podcastRSSProvider,
  substackProvider,
  mediumProvider,
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  YOUTUBE_API_KEY,
  YOUTUBE_CLIENT_ID,
  YOUTUBE_CLIENT_SECRET,
  APPLE_MUSIC_DEVELOPER_TOKEN,
  GOOGLE_BOOKS_API_KEY,
} from "./providers";
import type { SourceProvider } from "./providers/types";
import { importWork, advanceWorkReviewState as advanceState, publishWork as doPublishWork } from "./reviewWorkflow";
import { createManualWork, updateManualWork, ManualWorkInput } from "./manualEntry";
import { syncSingleProvider } from "./continuousSync";
import * as admin from "firebase-admin";

// ─── Provider registry ──────────────────────────────────────────────────────

const PROVIDER_REGISTRY: Record<string, SourceProvider> = {
  spotify: spotifyProvider,
  youtube: youtubeProvider,
  apple_music: appleMusicProvider,
  google_books: googleBooksProvider,
  open_library: openLibraryProvider,
  podcast_rss: podcastRSSProvider,
  substack: substackProvider,
  medium: mediumProvider,
};

// ─── Region config (us-east1 — us-central1 at quota) ───────────────────────

const REGION_CONFIG = {
  region: "us-east1" as const,
  secrets: [
    SPOTIFY_CLIENT_ID,
    SPOTIFY_CLIENT_SECRET,
    YOUTUBE_API_KEY,
    YOUTUBE_CLIENT_ID,
    YOUTUBE_CLIENT_SECRET,
    APPLE_MUSIC_DEVELOPER_TOKEN,
    GOOGLE_BOOKS_API_KEY,
  ],
};

// ─── connectSource ──────────────────────────────────────────────────────────

/**
 * Authorize + first fetch for a source provider.
 * All imported items land at reviewState='imported', visibility='private'.
 */
export const connectSource = onCall(
  {
    ...REGION_CONFIG,
    enforceAppCheck: true,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { creatorId, providerId, oauthToken } = request.data as {
      creatorId?: string;
      providerId?: string;
      oauthToken?: string;
    };

    if (!creatorId || !providerId) {
      throw new HttpsError("invalid-argument", "creatorId and providerId required");
    }

    // Verify caller owns the creatorId
    if (request.auth.uid !== creatorId) {
      throw new HttpsError("permission-denied", "caller_must_be_creator");
    }

    const provider = PROVIDER_REGISTRY[providerId];
    if (!provider) {
      throw new HttpsError("invalid-argument", `unknown_provider: ${providerId}`);
    }

    try {
      // Step 1: Authorize
      const authResult = await provider.authorize(creatorId, oauthToken);
      if (!authResult.success) {
        throw new HttpsError("failed-precondition", authResult.error ?? "authorization_failed");
      }

      // Step 2: First-page fetch and import
      const syncResult = await syncSingleProvider(creatorId, providerId);

      return {
        success: true,
        providerId,
        itemsImported: syncResult.itemsImported,
        nextCursor: syncResult.nextCursor,
        error: syncResult.error,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : "connect_source_failed";
      throw new HttpsError("internal", msg);
    }
  }
);

// ─── listPendingImports ─────────────────────────────────────────────────────

/**
 * List works in 'imported' state for a creator (pending their review).
 */
export const listPendingImports = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { creatorId } = request.data as { creatorId?: string };
    if (!creatorId) {
      throw new HttpsError("invalid-argument", "creatorId required");
    }

    if (request.auth.uid !== creatorId) {
      throw new HttpsError("permission-denied", "caller_must_be_creator");
    }

    try {
      const db = admin.firestore();
      const snap = await db
        .collection("works")
        .where("creatorId", "==", creatorId)
        .where("reviewState", "==", "imported")
        .where("deletedAt", "==", null)
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();

      const items = snap.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
        createdAt: (doc.data()["createdAt"] as admin.firestore.Timestamp)?.toDate().toISOString(),
        updatedAt: (doc.data()["updatedAt"] as admin.firestore.Timestamp)?.toDate().toISOString(),
        publishedAt: (doc.data()["publishedAt"] as admin.firestore.Timestamp | null)?.toDate().toISOString() ?? null,
      }));

      return { items, total: items.length };
    } catch (err) {
      const msg = err instanceof Error ? err.message : "list_pending_failed";
      throw new HttpsError("internal", msg);
    }
  }
);

// ─── createCatalogWork ──────────────────────────────────────────────────────

/**
 * Create a manual catalog work entry.
 * Always: reviewState='draft', visibility='private'.
 */
export const createCatalogWork = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { creatorId, type, title, subtitle, description, coverUrl, publishedAt, links, topics } =
      request.data as ManualWorkInput & { creatorId?: string };

    if (!creatorId) {
      throw new HttpsError("invalid-argument", "creatorId required");
    }

    if (request.auth.uid !== creatorId) {
      throw new HttpsError("permission-denied", "caller_must_be_creator");
    }

    try {
      const workId = await createManualWork(creatorId, {
        type,
        title,
        subtitle,
        description,
        coverUrl,
        publishedAt,
        links,
        topics,
      });

      return { workId };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : "create_catalog_work_failed";
      throw new HttpsError("invalid-argument", msg);
    }
  }
);

// ─── advanceWorkReviewState ─────────────────────────────────────────────────

/**
 * Advance a work from imported→draft or draft→review.
 * Does NOT publish — that requires explicit publishWork() with confirmed=true.
 */
export const advanceWorkReviewState = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { workId } = request.data as { workId?: string };
    if (!workId) {
      throw new HttpsError("invalid-argument", "workId required");
    }

    try {
      const result = await advanceState(workId, request.auth.uid);
      return result;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : "advance_state_failed";
      throw new HttpsError("internal", msg);
    }
  }
);

// ─── publishWork ────────────────────────────────────────────────────────────

/**
 * Publish an approved work. HUMAN GATE — confirmed MUST be true.
 * The client must pass confirmed=true explicitly; false throws unconditionally.
 */
export const publishWork = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { workId, confirmed, visibility } = request.data as {
      workId?: string;
      confirmed?: boolean;
      visibility?: "public" | "followers" | "paid_members" | "organization";
    };

    if (!workId) {
      throw new HttpsError("invalid-argument", "workId required");
    }

    // HUMAN GATE enforcement
    if (confirmed !== true) {
      throw new HttpsError(
        "failed-precondition",
        "confirmed_required: you must explicitly confirm publishing by passing confirmed=true"
      );
    }

    try {
      await doPublishWork(workId, request.auth.uid, true, visibility ?? "public");
      return { success: true, workId };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : "publish_work_failed";
      throw new HttpsError("internal", msg);
    }
  }
);

// ─── updateCatalogWork (bonus: needed for ManualWorkEntryView edits) ────────

export const updateCatalogWork = onCall(
  {
    region: "us-east1",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "authentication_required");
    }

    const { workId, ...updates } = request.data as Partial<ManualWorkInput> & { workId?: string };
    if (!workId) {
      throw new HttpsError("invalid-argument", "workId required");
    }

    try {
      await updateManualWork(workId, request.auth.uid, updates);
      return { success: true };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : "update_catalog_work_failed";
      throw new HttpsError("internal", msg);
    }
  }
);
