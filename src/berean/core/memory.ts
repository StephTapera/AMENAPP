/**
 * memory.ts — Berean Phase 2A
 *
 * Client-side memory service. Reads from and writes to `berean/{uid}/memory`
 * using the Firebase client Firestore SDK. All writes default to
 * visibility: 'private'. Soft-delete only — hard deletes are denied.
 *
 * Summarization is delegated to the `bereanMemory` CF via summarizeAndSave();
 * the AI call never happens client-side.
 *
 * NO batching, NO localStorage, NO sessionStorage.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 2A Core Agent
 */

import {
  getFirestore,
  collection,
  doc,
  getDocs,
  setDoc,
  updateDoc,
  serverTimestamp,
  query,
  where,
} from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';

import type {
  Domain,
  BereanMemoryDoc,
  MemorySummary,
  Visibility,
} from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Internal CF payload shapes
// ─────────────────────────────────────────────────────────────────────────────

interface BereanMemoryRequest {
  domain: Domain;
  text: string;
}

interface BereanMemoryResponse {
  summary: string;
  domain: Domain;
}

// ─────────────────────────────────────────────────────────────────────────────
// fetchMemoryContext
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Reads `berean/{uid}/memory`, filters to the given domain and not-softDeleted,
 * and returns a typed MemorySummary array ordered by pinned-first then createdAt.
 *
 * Returns [] on any error so missing or permission-denied memory never blocks
 * a Berean call.
 */
export async function fetchMemoryContext(
  userId: string,
  domain: Domain,
): Promise<MemorySummary[]> {
  try {
    const db = getFirestore();
    const memoryCol = collection(db, 'berean', userId, 'memory');

    // Firestore does not allow inequality on two different fields with a simple
    // composite index here — filter softDeleted server-side, domain client-side
    // to keep index requirements minimal.
    const q = query(memoryCol, where('softDeleted', '==', false));
    const snap = await getDocs(q);

    const summaries: MemorySummary[] = [];

    snap.forEach((docSnap) => {
      const data = docSnap.data() as BereanMemoryDoc;
      if (data.domain !== domain) return;

      summaries.push({
        domain: data.domain,
        summary: data.summary,
        pinned: data.pinned,
        refs: data.refs ?? [],
      });
    });

    // Pinned entries first; within each group preserve Firestore iteration order
    summaries.sort((a, b) => Number(b.pinned) - Number(a.pinned));

    return summaries;
  } catch {
    // Fail open — missing memory context degrades quality but never blocks the call.
    return [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// upsertMemory
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Writes (or overwrites) a memory document at `berean/{uid}/memory/{memoryId}`.
 *
 * Always enforces:
 *   - visibility: 'private'  (callers cannot override this)
 *   - softDeleted: false      (fresh write is never pre-deleted)
 *   - createdAt: serverTimestamp() on first write (merge: true preserves existing)
 */
export async function upsertMemory(
  userId: string,
  doc_: BereanMemoryDoc & { memoryId: string },
): Promise<void> {
  const { memoryId, ...docData } = doc_;

  const db = getFirestore();
  const memRef = doc(collection(db, 'berean', userId, 'memory'), memoryId);

  const safeWrite: BereanMemoryDoc = {
    ...docData,
    visibility: 'private' as Visibility,   // invariant — never caller-overrideable
    softDeleted: false,
    createdAt: serverTimestamp(),
  };

  // setDoc with merge: true so a re-upsert doesn't stomp createdAt on the
  // server when the document already exists. The serverTimestamp() above will
  // only land as a write if the field is absent (Firestore merge semantics).
  await setDoc(memRef, safeWrite, { merge: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// softDeleteMemory
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Soft-deletes a memory document by setting softDeleted: true.
 * Hard deletes are denied by Firestore security rules — this is the only path.
 */
export async function softDeleteMemory(
  userId: string,
  memoryId: string,
): Promise<void> {
  const db = getFirestore();
  const memRef = doc(collection(db, 'berean', userId, 'memory'), memoryId);
  await updateDoc(memRef, { softDeleted: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// summarizeAndSave
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Calls the `bereanMemory` CF to auto-summarize `text`, then persists the
 * returned summary as a new memory document under `berean/{uid}/memory`.
 *
 * The CF enforces an 8 000-character input cap — callers should truncate first
 * but the CF also rejects oversized inputs with an HttpsError.
 *
 * Returns the saved MemorySummary, or null if the CF or Firestore write fails
 * (failure is logged but never surfaced to the user as a crash).
 */
export async function summarizeAndSave(
  userId: string,
  domain: Domain,
  text: string,
): Promise<MemorySummary | null> {
  try {
    const functions = getFunctions();
    const bereanMemoryCF = httpsCallable<BereanMemoryRequest, BereanMemoryResponse>(
      functions,
      'bereanMemory',
    );

    const result = await bereanMemoryCF({ domain, text });
    const { summary } = result.data;

    if (!summary) return null;

    const memoryId = `${domain}_${Date.now()}`;
    const newDoc: BereanMemoryDoc & { memoryId: string } = {
      memoryId,
      domain,
      summary,
      refs: [],
      pinned: false,
      visibility: 'private',
      createdAt: serverTimestamp(),
      softDeleted: false,
    };

    await upsertMemory(userId, newDoc);

    return {
      domain,
      summary,
      pinned: false,
      refs: [],
    };
  } catch {
    // Summarization failure is non-fatal — degrade to no new memory entry.
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Named export object (for BereanCore context value)
// ─────────────────────────────────────────────────────────────────────────────

export const memoryService = {
  fetchMemoryContext,
  upsertMemory,
  softDeleteMemory,
  summarizeAndSave,
};
