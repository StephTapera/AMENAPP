/**
 * berean/memoryStore.ts — Berean Trust Architecture · Layer 3 · Memory Layer
 *
 * Provides user-owned, provenance-tracked, auditable memory storage for the
 * Berean AI assistant. Satisfies App Store guideline 5.1.1(v): users can view,
 * edit, delete, and lock every memory entry. All deletes are soft + audited.
 *
 * Firestore layout:
 *   users/{userId}/bereanMemory/{entryId}         — live memory entries
 *   bereanMemoryVectors/{vectorDocId}              — associated embeddings (optional)
 *   bereanAuditLog/{userId}/memoryDeletes/{docId}  — per-user delete receipts
 *   bereanAuditLog/cascade/{userId}                — cascade delete receipt
 *
 * Feature flag gate: featureFlags/trustArchitecture → field "memoryLayer" === true
 *
 * SECURITY: readMemory / writeMemory / deleteMemory / lockMemory all receive
 * a userId that the HTTP callable wrapper has already validated against
 * request.auth.uid before calling into this module. Never call these functions
 * with an unverified userId.
 *
 * No external dependencies beyond firebase-admin and Node built-ins.
 */

import * as admin from "firebase-admin";

// ── TYPES ─────────────────────────────────────────────────────────────────────

export type MemoryCategory =
  | "preference"
  | "study"
  | "prayer"
  | "church"
  | "action"
  | "context";

export type MemorySource = "ai-inferred" | "user-explicit";

export interface MemoryProvenance {
  conversationId: string;
  sessionId: string;
  createdAt: admin.firestore.Timestamp;
  source: MemorySource;
}

export interface MemoryEntry {
  entryId: string;
  userId: string;
  category: MemoryCategory;
  content: string;
  provenance: MemoryProvenance;
  /** When true this entry is never auto-updated by AI inference. */
  isLocked: boolean;
  /** Soft-delete flag. Entries with isDeleted=true are filtered from reads. */
  isDeleted: boolean;
  updatedAt: admin.firestore.Timestamp;
}

export interface MemoryWriteRequest {
  userId: string;
  category: MemoryCategory;
  content: string;
  conversationId: string;
  sessionId: string;
  source: MemorySource;
}

export interface MemoryReadRequest {
  userId: string;
  /** Optional allow-list of categories. Omit to return all categories. */
  categories?: MemoryCategory[];
  /** Maximum entries to return (capped at HARD_READ_LIMIT). */
  limit?: number;
}

// ── CONSTANTS ──────────────────────────────────────────────────────────────────

const HARD_READ_LIMIT = 50;
/** Jaccard-style content overlap threshold (0–1) above which we update in-place. */
const SIMILARITY_THRESHOLD = 0.8;

// ── HELPERS ───────────────────────────────────────────────────────────────────

/**
 * Generate a UUID using Node's built-in crypto module.
 * Avoids any external uuid package dependency.
 */
function generateId(): string {
  return crypto.randomUUID();
}

/**
 * checkMemoryLayerFlag — throws if the memoryLayer feature flag is not true.
 * Reads featureFlags/trustArchitecture from Firestore.
 */
async function checkMemoryLayerFlag(
  db: admin.firestore.Firestore,
): Promise<void> {
  const snap = await db.doc("featureFlags/trustArchitecture").get();
  const flags = snap.exists ? (snap.data() ?? {}) : {};
  if (flags["memoryLayer"] !== true) {
    throw new Error("memoryStore: memoryLayer feature flag is not enabled");
  }
}

/**
 * contentOverlap — cheap word-level Jaccard similarity between two strings.
 * Returns a value in [0, 1].
 */
function contentOverlap(a: string, b: string): number {
  const words = (s: string): Set<string> =>
    new Set(
      s
        .toLowerCase()
        .replace(/[^\w\s]/g, "")
        .split(/\s+/)
        .filter(Boolean),
    );

  const setA = words(a);
  const setB = words(b);

  if (setA.size === 0 && setB.size === 0) return 1;
  if (setA.size === 0 || setB.size === 0) return 0;

  let intersection = 0;
  setA.forEach((w) => {
    if (setB.has(w)) intersection++;
  });

  const union = setA.size + setB.size - intersection;
  return intersection / union;
}

// ── writeMemory ───────────────────────────────────────────────────────────────

/**
 * writeMemory — persist a memory entry for a user.
 *
 * If a non-deleted, non-locked entry with the same category and content overlap
 * above SIMILARITY_THRESHOLD exists, the existing entry is updated in-place
 * (preserving the original provenance.createdAt and entryId).
 *
 * Returns the entryId (new or existing).
 */
export async function writeMemory(
  req: MemoryWriteRequest,
  db: admin.firestore.Firestore,
): Promise<string> {
  await checkMemoryLayerFlag(db);

  const { userId, category, content, conversationId, sessionId, source } = req;
  const memoryRef = db
    .collection("users")
    .doc(userId)
    .collection("bereanMemory");

  // ── Similarity check: look for a close-enough existing entry ─────────────────
  const candidateSnap = await memoryRef
    .where("category", "==", category)
    .where("isDeleted", "==", false)
    .get();

  let existingDocId: string | null = null;
  let existingCreatedAt: admin.firestore.Timestamp | null = null;
  let bestOverlap = 0;

  for (const doc of candidateSnap.docs) {
    const data = doc.data() as MemoryEntry;
    // Skip locked entries — they must not be auto-updated
    if (data.isLocked) continue;
    const overlap = contentOverlap(data.content, content);
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      if (overlap >= SIMILARITY_THRESHOLD) {
        existingDocId = doc.id;
        existingCreatedAt = data.provenance?.createdAt ?? null;
      }
    }
  }

  const now = admin.firestore.Timestamp.now();

  if (existingDocId !== null) {
    // ── Update existing entry (preserve entryId and original createdAt) ──────────
    const docRef = memoryRef.doc(existingDocId);
    await docRef.update({
      content,
      "provenance.conversationId": conversationId,
      "provenance.sessionId": sessionId,
      "provenance.source": source,
      updatedAt: now,
    });
    return existingDocId;
  }

  // ── Create new entry ──────────────────────────────────────────────────────────
  const entryId = generateId();
  const entry: MemoryEntry = {
    entryId,
    userId,
    category,
    content,
    provenance: {
      conversationId,
      sessionId,
      createdAt: now,
      source,
    },
    isLocked: false,
    isDeleted: false,
    updatedAt: now,
  };

  await memoryRef.doc(entryId).set(entry);
  return entryId;
}

// ── readMemory ────────────────────────────────────────────────────────────────

/**
 * readMemory — retrieve non-deleted memory entries for a user.
 *
 * SECURITY CONTRACT: caller (the Firebase callable wrapper) must have verified
 * that request.auth.uid === req.userId before invoking this function.
 *
 * Results are ordered by updatedAt descending and capped at HARD_READ_LIMIT.
 */
export async function readMemory(
  req: MemoryReadRequest,
  db: admin.firestore.Firestore,
): Promise<MemoryEntry[]> {
  await checkMemoryLayerFlag(db);

  const { userId, categories, limit } = req;
  const effectiveLimit = Math.min(limit ?? HARD_READ_LIMIT, HARD_READ_LIMIT);

  let query: admin.firestore.Query = db
    .collection("users")
    .doc(userId)
    .collection("bereanMemory")
    .where("isDeleted", "==", false)
    .orderBy("updatedAt", "desc")
    .limit(effectiveLimit);

  // Firestore does not allow inequality + in-filter on different fields in the
  // same query without a composite index. We apply category filtering in-memory
  // after fetching (categories list is small; hard cap is 50 docs already).
  const snap = await query.get();

  const entries: MemoryEntry[] = snap.docs.map(
    (d) => d.data() as MemoryEntry,
  );

  if (categories && categories.length > 0) {
    const allowed = new Set<string>(categories);
    return entries.filter((e) => allowed.has(e.category));
  }

  return entries;
}

// ── deleteMemory ──────────────────────────────────────────────────────────────

/**
 * deleteMemory — soft-delete a single memory entry.
 *
 * Also removes any associated embedding from bereanMemoryVectors, and writes a
 * compliance receipt to bereanAuditLog/{userId}/memoryDeletes.
 */
export async function deleteMemory(
  userId: string,
  entryId: string,
  db: admin.firestore.Firestore,
): Promise<void> {
  await checkMemoryLayerFlag(db);

  const now = admin.firestore.Timestamp.now();
  const entryRef = db
    .collection("users")
    .doc(userId)
    .collection("bereanMemory")
    .doc(entryId);

  // ── 1. Verify entry exists and belongs to this user ───────────────────────────
  const snap = await entryRef.get();
  if (!snap.exists) {
    throw new Error(
      `deleteMemory: entry ${entryId} does not exist for user ${userId}`,
    );
  }
  const data = snap.data() as MemoryEntry;
  if (data.userId !== userId) {
    // Belt-and-suspenders check: Firestore path already scopes to userId.
    throw new Error(
      `deleteMemory: userId mismatch for entry ${entryId}`,
    );
  }

  // ── 2. Soft-delete the memory entry ──────────────────────────────────────────
  await entryRef.update({
    isDeleted: true,
    updatedAt: now,
  });

  // ── 3. Remove associated vector if present (best-effort, non-fatal) ──────────
  try {
    const vectorSnap = await db
      .collection("bereanMemoryVectors")
      .where("entryId", "==", entryId)
      .where("userId", "==", userId)
      .limit(1)
      .get();
    if (!vectorSnap.empty) {
      await vectorSnap.docs[0].ref.delete();
    }
  } catch (vectorErr) {
    // Non-fatal: vector cleanup failure must not block the user-visible delete.
    console.warn(
      `[memoryStore] deleteMemory: vector cleanup failed for ${entryId}:`,
      vectorErr,
    );
  }

  // ── 4. Write compliance audit log ─────────────────────────────────────────────
  const auditRef = db
    .collection("bereanAuditLog")
    .doc(userId)
    .collection("memoryDeletes")
    .doc();

  await auditRef.set({
    entryId,
    userId,
    category: data.category,
    deletedAt: now,
    initiatedBy: "user",
  });
}

// ── lockMemory ────────────────────────────────────────────────────────────────

/**
 * lockMemory — toggle the isLocked flag on a memory entry.
 *
 * Locked entries are skipped by writeMemory's auto-update logic, giving users
 * full control over which memories the AI can revise.
 */
export async function lockMemory(
  userId: string,
  entryId: string,
  locked: boolean,
  db: admin.firestore.Firestore,
): Promise<void> {
  await checkMemoryLayerFlag(db);

  const entryRef = db
    .collection("users")
    .doc(userId)
    .collection("bereanMemory")
    .doc(entryId);

  const snap = await entryRef.get();
  if (!snap.exists) {
    throw new Error(
      `lockMemory: entry ${entryId} does not exist for user ${userId}`,
    );
  }

  const data = snap.data() as MemoryEntry;
  if (data.isDeleted) {
    throw new Error(
      `lockMemory: cannot lock a deleted entry (${entryId})`,
    );
  }

  await entryRef.update({
    isLocked: locked,
    updatedAt: admin.firestore.Timestamp.now(),
  });
}

// ── deleteAllUserMemory ───────────────────────────────────────────────────────

/**
 * deleteAllUserMemory — cascade-delete all memory for a user.
 *
 * Called on account deletion to satisfy App Store guideline 5.1.1(v).
 * Soft-deletes all entries in users/{userId}/bereanMemory in batches,
 * hard-deletes all matching vectors from bereanMemoryVectors, and writes a
 * single cascade receipt to bereanAuditLog/cascade/{userId}.
 *
 * NOTE: Feature flag is intentionally NOT checked here — account deletion must
 * succeed even if the memoryLayer flag has been turned off.
 */
export async function deleteAllUserMemory(
  userId: string,
  db: admin.firestore.Firestore,
): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  const BATCH_SIZE = 400; // Firestore batch limit is 500; stay well under it

  // ── 1. Soft-delete all memory entries in batches ──────────────────────────────
  const memoryCollRef = db
    .collection("users")
    .doc(userId)
    .collection("bereanMemory");

  let totalSoftDeleted = 0;
  let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

  while (true) {
    let pageQuery: admin.firestore.Query = memoryCollRef
      .where("isDeleted", "==", false)
      .limit(BATCH_SIZE);
    if (lastDoc) {
      pageQuery = pageQuery.startAfter(lastDoc);
    }

    const pageSnap = await pageQuery.get();
    if (pageSnap.empty) break;

    const batch = db.batch();
    for (const doc of pageSnap.docs) {
      batch.update(doc.ref, { isDeleted: true, updatedAt: now });
    }
    await batch.commit();

    totalSoftDeleted += pageSnap.size;
    lastDoc = pageSnap.docs[pageSnap.docs.length - 1];

    if (pageSnap.size < BATCH_SIZE) break;
  }

  // ── 2. Hard-delete all vector embeddings for this user ────────────────────────
  let totalVectorsDeleted = 0;
  try {
    let vectorLastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

    while (true) {
      let vectorQuery: admin.firestore.Query = db
        .collection("bereanMemoryVectors")
        .where("userId", "==", userId)
        .limit(BATCH_SIZE);
      if (vectorLastDoc) {
        vectorQuery = vectorQuery.startAfter(vectorLastDoc);
      }

      const vectorSnap = await vectorQuery.get();
      if (vectorSnap.empty) break;

      const batch = db.batch();
      for (const doc of vectorSnap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();

      totalVectorsDeleted += vectorSnap.size;
      vectorLastDoc = vectorSnap.docs[vectorSnap.docs.length - 1];

      if (vectorSnap.size < BATCH_SIZE) break;
    }
  } catch (vectorErr) {
    // Non-fatal: vector deletion failure must not prevent the cascade receipt
    // from being written, which is the compliance-critical step.
    console.error(
      `[memoryStore] deleteAllUserMemory: vector deletion failed for ${userId}:`,
      vectorErr,
    );
  }

  // ── 3. Write cascade compliance receipt ───────────────────────────────────────
  await db
    .collection("bereanAuditLog")
    .doc("cascade")
    .collection(userId)
    .doc("deleteReceipt")
    .set({
      userId,
      cascadeAt: now,
      totalEntriesSoftDeleted: totalSoftDeleted,
      totalVectorsDeleted,
      initiatedBy: "accountDeletion",
    });
}
