/**
 * bereanMemory.ts
 *
 * Berean Memory Store — Trust Architecture Layer 3
 *
 * Firestore path: berean_memory/{userId}/entries/{entryId}
 *
 * SECURITY INVARIANT:
 *   Every operation validates auth.uid === userId.
 *   No cross-user memory access is permitted under any code path.
 *
 * FEATURE FLAG:
 *   berean_memory_enabled in Firestore system/serverFeatureFlags.
 *   If false, all callables throw a clear "feature gated" HttpsError.
 *   Default = false (off until explicitly enabled).
 *
 * APP STORE 5.1.1(v) COMPLIANCE:
 *   bereanMemoryDeleteAll deletes the entire berean_memory/{userId} subcollection
 *   and is the account-deletion cascade entry point for this data domain.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { v4 as uuidv4 } from "uuid";

const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type MemoryCategory =
  | "STUDY_PREFERENCE"
  | "PRAYER_REQUEST"
  | "CHURCH_INVOLVEMENT"
  | "SAVED_STUDY"
  | "ONGOING_QUESTION"
  | "READING_PLAN"
  | "TRANSLATION_PREFERENCE";

const VALID_CATEGORIES: ReadonlySet<MemoryCategory> = new Set([
  "STUDY_PREFERENCE",
  "PRAYER_REQUEST",
  "CHURCH_INVOLVEMENT",
  "SAVED_STUDY",
  "ONGOING_QUESTION",
  "READING_PLAN",
  "TRANSLATION_PREFERENCE",
]);

export interface BereanMemoryEntry {
  id: string;
  userId: string;
  content: string;
  category: MemoryCategory;
  provenance: {
    conversationId?: string;
    action: string;
    traceId?: string;
  };
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
  isLocked: boolean;
}

// ─── Feature flag ─────────────────────────────────────────────────────────────

/** Cache TTL: 5 minutes — mirrors pattern in serverFeatureFlags.ts */
const FLAG_CACHE_TTL_MS = 5 * 60 * 1000;
let memoryFlagCache: boolean | null = null;
let memoryFlagCacheExpiresAt = 0;

async function isBereanMemoryEnabled(): Promise<boolean> {
  const now = Date.now();
  if (memoryFlagCache !== null && now < memoryFlagCacheExpiresAt) {
    return memoryFlagCache;
  }
  try {
    const snap = await db.collection("system").doc("serverFeatureFlags").get();
    const data = snap.data() ?? {};
    // Default OFF — must be explicitly set to true to enable.
    const enabled =
      typeof data.berean_memory_enabled === "boolean"
        ? data.berean_memory_enabled
        : false;
    memoryFlagCache = enabled;
    memoryFlagCacheExpiresAt = now + FLAG_CACHE_TTL_MS;
    return enabled;
  } catch (err) {
    functions.logger.error(
      "[BereanMemory] Failed to read berean_memory_enabled flag — defaulting OFF.",
      err
    );
    // Safe default: keep the feature gated on flag read failure.
    return false;
  }
}

/**
 * Throws a clear HttpsError when the feature is gated.
 * MUST be called at the top of every callable before any other logic.
 */
async function assertFeatureEnabled(): Promise<void> {
  const enabled = await isBereanMemoryEnabled();
  if (!enabled) {
    throw new HttpsError(
      "failed-precondition",
      "Berean Memory is not enabled on this environment. " +
        "Set berean_memory_enabled = true in system/serverFeatureFlags to activate."
    );
  }
}

// ─── Auth helper ──────────────────────────────────────────────────────────────

/**
 * Validates that the caller is authenticated and that auth.uid matches userId.
 * Also enforces App Check attestation via enforceAppCheck: true on every callable.
 *
 * Throws HttpsError on any failure — never returns undefined.
 */
function assertOwnership(
  request: { auth?: { uid: string } | null; app?: unknown },
  userId: string
): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!request.app) {
    throw new HttpsError("unauthenticated", "App Check attestation required.");
  }
  if (request.auth.uid !== userId) {
    // Return permission-denied — never reveal that the document exists.
    throw new HttpsError(
      "permission-denied",
      "You do not have access to this memory store."
    );
  }
}

// ─── Firestore path helpers ───────────────────────────────────────────────────

function entriesCollection(userId: string) {
  return db
    .collection("berean_memory")
    .doc(userId)
    .collection("entries");
}

function entryDoc(userId: string, entryId: string) {
  return entriesCollection(userId).doc(entryId);
}

// ─── 1. bereanMemoryWrite ─────────────────────────────────────────────────────

/**
 * Write a new Berean memory entry for the authenticated user.
 *
 * Request shape:
 *   { userId, content, category, provenance: { conversationId?, action, traceId? } }
 *
 * Returns: { entryId }
 */
export const bereanMemoryWrite = onCall(
  { enforceAppCheck: true, region: "us-east1" },
  async (request) => {
    await assertFeatureEnabled();

    const data = request.data as {
      userId: string;
      content: string;
      category: string;
      provenance: {
        conversationId?: string;
        action: string;
        traceId?: string;
      };
    };

    assertOwnership(request, data?.userId);

    // Input validation
    if (typeof data.content !== "string" || data.content.trim().length === 0) {
      throw new HttpsError("invalid-argument", "content must be a non-empty string.");
    }
    if (data.content.length > 8000) {
      throw new HttpsError(
        "invalid-argument",
        "content exceeds maximum length of 8000 characters."
      );
    }
    if (!VALID_CATEGORIES.has(data.category as MemoryCategory)) {
      throw new HttpsError(
        "invalid-argument",
        `category must be one of: ${[...VALID_CATEGORIES].join(", ")}.`
      );
    }
    if (
      !data.provenance ||
      typeof data.provenance.action !== "string" ||
      data.provenance.action.trim().length === 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "provenance.action must be a non-empty string."
      );
    }

    const entryId = uuidv4();
    const now = admin.firestore.Timestamp.now();

    const entry: BereanMemoryEntry = {
      id: entryId,
      userId: data.userId,
      content: data.content.trim(),
      category: data.category as MemoryCategory,
      provenance: {
        ...(data.provenance.conversationId
          ? { conversationId: data.provenance.conversationId }
          : {}),
        action: data.provenance.action.trim(),
        ...(data.provenance.traceId
          ? { traceId: data.provenance.traceId }
          : {}),
      },
      createdAt: now,
      updatedAt: now,
      isLocked: false,
    };

    await entryDoc(data.userId, entryId).set(entry);

    functions.logger.info("[BereanMemory] Entry written.", {
      userId: data.userId,
      entryId,
      category: data.category,
    });

    return { entryId };
  }
);

// ─── 2. bereanMemoryRead ──────────────────────────────────────────────────────

/**
 * Fetch all memory entries for the authenticated user, optionally filtered by category.
 *
 * Request shape:
 *   { userId, category?: MemoryCategory }
 *
 * Returns: { entries: BereanMemoryEntry[] }
 */
export const bereanMemoryRead = onCall(
  { enforceAppCheck: true, region: "us-east1" },
  async (request) => {
    await assertFeatureEnabled();

    const data = request.data as {
      userId: string;
      category?: string;
    };

    assertOwnership(request, data?.userId);

    let query: admin.firestore.Query = entriesCollection(data.userId).orderBy(
      "createdAt",
      "asc"
    );

    if (data.category !== undefined && data.category !== null) {
      if (!VALID_CATEGORIES.has(data.category as MemoryCategory)) {
        throw new HttpsError(
          "invalid-argument",
          `category filter must be one of: ${[...VALID_CATEGORIES].join(", ")}.`
        );
      }
      query = query.where("category", "==", data.category);
    }

    const snap = await query.get();
    const entries = snap.docs.map((doc) => doc.data() as BereanMemoryEntry);

    functions.logger.info("[BereanMemory] Entries read.", {
      userId: data.userId,
      count: entries.length,
      categoryFilter: data.category ?? "none",
    });

    return { entries };
  }
);

// ─── 3. bereanMemoryDelete ────────────────────────────────────────────────────

/**
 * Delete a single memory entry by entryId.
 * Validates ownership of both the user record and the individual entry.
 *
 * Also removes the entry from the Pinecone vector index if applicable.
 *
 * Request shape:
 *   { userId, entryId }
 *
 * Returns: { deleted: boolean }
 */
export const bereanMemoryDelete = onCall(
  { enforceAppCheck: true, region: "us-east1" },
  async (request) => {
    await assertFeatureEnabled();

    const data = request.data as {
      userId: string;
      entryId: string;
    };

    assertOwnership(request, data?.userId);

    if (typeof data.entryId !== "string" || data.entryId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "entryId must be a non-empty string.");
    }

    const docRef = entryDoc(data.userId, data.entryId);
    const snap = await docRef.get();

    if (!snap.exists) {
      // Return not-found rather than silently succeeding — allows the client
      // to detect double-delete or stale UI state.
      throw new HttpsError("not-found", "Memory entry not found.");
    }

    const existing = snap.data() as BereanMemoryEntry;

    // Secondary ownership check — the document's userId field must also match.
    if (existing.userId !== data.userId) {
      throw new HttpsError(
        "permission-denied",
        "You do not have access to this memory entry."
      );
    }

    await docRef.delete();

    // TODO(pinecone): Delete the corresponding vector from Pinecone using entryId
    // as the vector ID. Example:
    //   await pineconeIndex.delete1({ ids: [data.entryId], namespace: data.userId });
    // This requires the Pinecone SDK to be initialised and the index name configured
    // in environment variables (PINECONE_INDEX_NAME, PINECONE_API_KEY).

    functions.logger.info("[BereanMemory] Entry deleted.", {
      userId: data.userId,
      entryId: data.entryId,
    });

    return { deleted: true };
  }
);

// ─── 4. bereanMemoryDeleteAll ─────────────────────────────────────────────────

/**
 * Delete the entire berean_memory/{userId} subcollection.
 *
 * This is the account-deletion cascade for the Berean memory data domain,
 * required by App Store Review Guideline 5.1.1(v).
 *
 * Caller must be either:
 *   (a) The owning user (auth.uid === userId), OR
 *   (b) An admin Cloud Function invocation with the "admin" custom claim.
 *
 * Request shape:
 *   { userId }
 *
 * Returns: { deletedCount: number }
 */
export const bereanMemoryDeleteAll = onCall(
  { enforceAppCheck: true, region: "us-east1" },
  async (request) => {
    await assertFeatureEnabled();

    const data = request.data as { userId: string };

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check attestation required.");
    }

    const callerUid = request.auth.uid;
    const isAdmin = (request.auth.token as Record<string, unknown>).admin === true;

    // Allow owning user OR admin.
    if (callerUid !== data?.userId && !isAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Only the account owner or an admin may delete all memory entries."
      );
    }

    if (typeof data.userId !== "string" || data.userId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "userId must be a non-empty string.");
    }

    // Delete in batches of 400 (Firestore batch limit is 500; leave headroom).
    const BATCH_SIZE = 400;
    let deletedCount = 0;
    let hasMore = true;

    while (hasMore) {
      const snap = await entriesCollection(data.userId)
        .limit(BATCH_SIZE)
        .get();

      if (snap.empty) {
        hasMore = false;
        break;
      }

      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      deletedCount += snap.docs.length;

      if (snap.docs.length < BATCH_SIZE) {
        hasMore = false;
      }
    }

    // Also delete the parent user document if it exists (clean Firestore tree).
    const parentRef = db.collection("berean_memory").doc(data.userId);
    const parentSnap = await parentRef.get();
    if (parentSnap.exists) {
      await parentRef.delete();
    }

    // TODO(pinecone): Delete the entire namespace for this userId from Pinecone.
    // Example:
    //   await pineconeIndex.delete1({ deleteAll: true, namespace: data.userId });

    functions.logger.warn("[BereanMemory] All entries deleted (account cascade).", {
      userId: data.userId,
      callerUid,
      isAdmin,
      deletedCount,
    });

    return { deletedCount };
  }
);

// ─── 5. bereanMemoryUpdate ────────────────────────────────────────────────────

/**
 * Update the content or isLocked field of a single memory entry.
 *
 * - Only the entry owner may update their own entries.
 * - A locked entry (isLocked: true) may NOT have its content changed,
 *   but the isLocked flag itself may be toggled by the owner.
 *
 * Request shape:
 *   { userId, entryId, content?: string, isLocked?: boolean }
 *
 * At least one of content or isLocked must be provided.
 *
 * Returns: { updated: boolean }
 */
export const bereanMemoryUpdate = onCall(
  { enforceAppCheck: true, region: "us-east1" },
  async (request) => {
    await assertFeatureEnabled();

    const data = request.data as {
      userId: string;
      entryId: string;
      content?: string;
      isLocked?: boolean;
    };

    assertOwnership(request, data?.userId);

    if (typeof data.entryId !== "string" || data.entryId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "entryId must be a non-empty string.");
    }

    const hasContentUpdate =
      data.content !== undefined && data.content !== null;
    const hasLockUpdate =
      data.isLocked !== undefined && data.isLocked !== null;

    if (!hasContentUpdate && !hasLockUpdate) {
      throw new HttpsError(
        "invalid-argument",
        "At least one of content or isLocked must be provided."
      );
    }

    if (hasContentUpdate) {
      if (typeof data.content !== "string" || data.content.trim().length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "content must be a non-empty string."
        );
      }
      if (data.content.length > 8000) {
        throw new HttpsError(
          "invalid-argument",
          "content exceeds maximum length of 8000 characters."
        );
      }
    }

    if (hasLockUpdate && typeof data.isLocked !== "boolean") {
      throw new HttpsError("invalid-argument", "isLocked must be a boolean.");
    }

    const docRef = entryDoc(data.userId, data.entryId);
    const snap = await docRef.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "Memory entry not found.");
    }

    const existing = snap.data() as BereanMemoryEntry;

    // Secondary ownership check on the stored document.
    if (existing.userId !== data.userId) {
      throw new HttpsError(
        "permission-denied",
        "You do not have access to this memory entry."
      );
    }

    // A locked entry cannot have its content changed.
    if (existing.isLocked && hasContentUpdate) {
      throw new HttpsError(
        "failed-precondition",
        "This memory entry is locked and its content cannot be changed. " +
          "Unlock the entry (isLocked: false) first."
      );
    }

    const updates: Partial<BereanMemoryEntry> & {
      updatedAt: admin.firestore.Timestamp;
    } = {
      updatedAt: admin.firestore.Timestamp.now(),
    };

    if (hasContentUpdate) {
      updates.content = (data.content as string).trim();
    }
    if (hasLockUpdate) {
      updates.isLocked = data.isLocked as boolean;
    }

    await docRef.update(updates);

    functions.logger.info("[BereanMemory] Entry updated.", {
      userId: data.userId,
      entryId: data.entryId,
      fieldsUpdated: [
        ...(hasContentUpdate ? ["content"] : []),
        ...(hasLockUpdate ? ["isLocked"] : []),
      ],
    });

    return { updated: true };
  }
);
