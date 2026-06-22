// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * selahCorpusService.js — Firebase gen2 callable Cloud Functions for the Selah personal study corpus.
 *
 * Exports TWO callable Cloud Functions:
 *   - indexSelahNote    : indexes (or soft-delete-syncs) a SelahNote into the user's private Pinecone namespace
 *   - querySelahCorpus  : retrieves semantically similar notes from the user's private Pinecone namespace
 *
 * HARD INVARIANTS (contract: selah.contracts.ts):
 *   1. Namespace uid comes ONLY from request.auth.uid — never from the client payload.
 *   2. No cross-user retrieval: every Pinecone operation is scoped to `selah-notes-${uid}`.
 *   3. translationRead must NEVER enter any Pinecone payload (licensed text constraint).
 *   4. Fail gracefully: Pinecone down → return empty, not an infrastructure error to the client.
 *   5. No fabrication: if no results are found, return empty — never generate fallback content.
 *   6. Soft-delete only: deletedAt synced to Pinecone; no Firestore hard-deletes performed here.
 *
 * RATE LIMITS:
 *   - indexSelahNote   : 60 writes / minute per uid
 *   - querySelahCorpus : 30 queries / minute per uid
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const { openaiEmbed, pineconeUpsert, pineconeDelete, logFunction } = require("../mlClients");
const { enforceRateLimit } = require("../rateLimiter");
const {
  selahNamespace,
  buildNoteEmbedText,
  buildNoteEmbeddingPayload,
  buildNoteQueryText,
  filterDeletedNotes,
  isValidNoteKind,
} = require("./selahCorpusUtils");

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

const VALID_KINDS = ["highlight", "note", "question", "prayer"];
const DEFAULT_TOP_K = 5;
const MAX_TOP_K = 10;

// Rate-limit windows (seconds)
const INDEX_WINDOW_SECS = 60;   // 60-second window
const INDEX_MAX = 60;           // 60 writes per window
const QUERY_WINDOW_SECS = 60;   // 60-second window
const QUERY_MAX = 30;           // 30 queries per window

// ---------------------------------------------------------------------------
// HELPER: Firestore path builder (mirrors FIRESTORE_PATHS from contracts)
// ---------------------------------------------------------------------------

function selahNoteRef(uid, noteId) {
  return admin.firestore().collection("users").doc(uid).collection("selahNotes").doc(noteId);
}

// ---------------------------------------------------------------------------
// FUNCTION 1: indexSelahNote
// ---------------------------------------------------------------------------

/**
 * indexSelahNote — callable Cloud Function (gen2)
 *
 * Indexes a SelahNote into the caller's strictly private Pinecone namespace.
 * If deletedAt is non-null, the vector is deleted from Pinecone (soft-delete sync).
 * On success, sets indexedToCorpus: true on the Firestore document.
 *
 * Input (data):
 *   noteId     {string}       required
 *   verseRef   {string}       required
 *   kind       {string}       required — 'highlight'|'note'|'question'|'prayer'
 *   body       {string|null}  optional
 *   color      {string|null}  optional
 *   createdAt  {number}       optional
 *   deletedAt  {number|null}  optional — non-null triggers vector delete
 *
 * Explicitly excluded from input (enforced):
 *   translationRead — must never be passed to this function or embedded
 *
 * Returns: { success: true, indexed: true } | { success: false, error: string }
 */
exports.indexSelahNote = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    const startMs = Date.now();

    // ── Auth guard ───────────────────────────────────────────────────────────
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required to index selah notes.");
    }

    // ── Rate limit: 60 writes/minute per uid ─────────────────────────────────
    await enforceRateLimit(uid, "selah_index_note", INDEX_MAX, INDEX_WINDOW_SECS);

    const data = request.data || {};

    // ── Input validation ─────────────────────────────────────────────────────
    const { noteId, verseRef, kind, body, color, createdAt, deletedAt } = data;

    // HARD RULE: reject any payload that includes translationRead to prevent
    // accidental licensed-text ingestion at the earliest possible boundary.
    if ("translationRead" in data) {
      logFunction("indexSelahNote", {
        uid,
        error: "translationRead present in payload — rejected",
        durationMs: Date.now() - startMs,
      });
      throw new HttpsError(
        "invalid-argument",
        "translationRead must not be sent to indexSelahNote. " +
        "Licensed Bible text is restricted to the human reader path only."
      );
    }

    if (!noteId || typeof noteId !== "string") {
      throw new HttpsError("invalid-argument", "noteId is required and must be a string.");
    }
    if (!verseRef || typeof verseRef !== "string") {
      throw new HttpsError("invalid-argument", "verseRef is required and must be a string.");
    }
    if (!isValidNoteKind(kind)) {
      throw new HttpsError(
        "invalid-argument",
        `kind must be one of: ${VALID_KINDS.join(", ")}. Got: "${kind}".`
      );
    }

    // ── Namespace (always from auth uid, never from payload) ─────────────────
    const namespace = selahNamespace(uid);

    // ── Soft-delete sync: deletedAt non-null → remove vector from Pinecone ───
    if (deletedAt !== null && deletedAt !== undefined) {
      try {
        await pineconeDelete(namespace, [noteId]);

        // Mark Firestore document as de-indexed
        try {
          await selahNoteRef(uid, noteId).update({ indexedToCorpus: false });
        } catch (fsErr) {
          // Non-fatal: Pinecone delete succeeded; Firestore flag update failure is logged
          console.warn(`[indexSelahNote] Firestore de-index flag update failed for ${noteId}:`, fsErr.message);
        }

        logFunction("indexSelahNote", {
          uid,
          noteId,
          action: "delete",
          namespace,
          durationMs: Date.now() - startMs,
        });

        return { success: true, indexed: false, action: "deleted" };
      } catch (err) {
        console.error(`[indexSelahNote] Pinecone delete failed for ${noteId}:`, err.message);
        logFunction("indexSelahNote", {
          uid,
          noteId,
          action: "delete",
          error: err.message,
          durationMs: Date.now() - startMs,
        });
        return { success: false, error: "Failed to remove note from corpus." };
      }
    }

    // ── Upsert path ──────────────────────────────────────────────────────────

    // Build embedding text (translationRead excluded by design in buildNoteEmbedText)
    const noteForEmbed = { verseRef, kind, body: body ?? null };
    const embedText = buildNoteEmbedText(noteForEmbed);

    // Embed — cache key scoped to user+note to avoid cross-user cache collisions
    let vector;
    try {
      const cacheKey = `selah_${uid}_${noteId}`;
      vector = await openaiEmbed(embedText, cacheKey);
    } catch (embedErr) {
      console.error(`[indexSelahNote] Embedding failed for note ${noteId}:`, embedErr.message);
      logFunction("indexSelahNote", {
        uid,
        noteId,
        error: `embed_failed: ${embedErr.message}`,
        durationMs: Date.now() - startMs,
      });
      return { success: false, error: "Failed to embed note. Please try again." };
    }

    // Build Pinecone payload (translationRead excluded by buildNoteEmbeddingPayload)
    const noteForPayload = {
      id: noteId,
      userId: uid,           // uid from auth, not from payload
      verseRef,
      kind,
      color: color ?? null,
      body: body ?? null,
      createdAt: createdAt ?? Date.now(),
      deletedAt: null,       // active note — deletedAt is null
      // translationRead: intentionally omitted
    };

    let payload;
    try {
      payload = buildNoteEmbeddingPayload(noteForPayload, vector);
    } catch (payloadErr) {
      console.error(`[indexSelahNote] Payload build failed for note ${noteId}:`, payloadErr.message);
      logFunction("indexSelahNote", {
        uid,
        noteId,
        error: `payload_build_failed: ${payloadErr.message}`,
        durationMs: Date.now() - startMs,
      });
      return { success: false, error: "Failed to build embedding payload." };
    }

    // Upsert to Pinecone (user-scoped namespace)
    try {
      await pineconeUpsert(namespace, [payload]);
    } catch (upsertErr) {
      console.error(`[indexSelahNote] Pinecone upsert failed for note ${noteId}:`, upsertErr.message);
      logFunction("indexSelahNote", {
        uid,
        noteId,
        error: `upsert_failed: ${upsertErr.message}`,
        durationMs: Date.now() - startMs,
      });
      return { success: false, error: "Failed to sync note to corpus. Please try again." };
    }

    // Mark Firestore document as indexed
    try {
      await selahNoteRef(uid, noteId).update({ indexedToCorpus: true });
    } catch (fsErr) {
      // Non-fatal: Pinecone upsert succeeded; flag will be set on next successful call
      console.warn(`[indexSelahNote] Firestore indexedToCorpus flag update failed for ${noteId}:`, fsErr.message);
    }

    logFunction("indexSelahNote", {
      uid,
      noteId,
      action: "upsert",
      namespace,
      durationMs: Date.now() - startMs,
    });

    return { success: true, indexed: true };
  }
);

// ---------------------------------------------------------------------------
// FUNCTION 2: querySelahCorpus
// ---------------------------------------------------------------------------

/**
 * querySelahCorpus — callable Cloud Function (gen2)
 *
 * Retrieves the top-K most semantically similar notes from the caller's
 * strictly private Pinecone namespace.
 *
 * INVARIANTS:
 *   - uid comes from request.auth.uid ONLY — never from the input payload.
 *   - No cross-user retrieval: namespace is always `selah-notes-${uid}`.
 *   - No fabrication: empty Pinecone results → return empty, never generate content.
 *   - Fail closed on Pinecone errors: return degraded empty, not a client-visible crash.
 *   - Soft-deleted notes (metadata.deletedAt non-null) are filtered from results.
 *
 * Input (data):
 *   query    {string}           required — free-text search query
 *   verseRef {string|undefined} optional — weights query toward this reference
 *   topK     {number|undefined} optional — default 5, max 10
 *
 * Returns:
 *   { results: [...], empty: boolean, degraded?: boolean }
 *   results[]: { noteId, verseRef, kind, score, body, color, createdAt }
 */
exports.querySelahCorpus = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    const startMs = Date.now();

    // ── Auth guard ───────────────────────────────────────────────────────────
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required to query selah corpus.");
    }

    // ── Rate limit: 30 queries/minute per uid ─────────────────────────────────
    await enforceRateLimit(uid, "selah_query_corpus", QUERY_MAX, QUERY_WINDOW_SECS);

    const data = request.data || {};
    const { query, verseRef, topK: rawTopK } = data;

    // ── Input validation ─────────────────────────────────────────────────────
    if (!query || typeof query !== "string" || query.trim() === "") {
      throw new HttpsError("invalid-argument", "query is required and must be a non-empty string.");
    }

    // Clamp topK to [1, MAX_TOP_K]
    let topK = DEFAULT_TOP_K;
    if (rawTopK !== undefined && rawTopK !== null) {
      const parsed = parseInt(rawTopK, 10);
      if (!isNaN(parsed) && parsed > 0) {
        topK = Math.min(parsed, MAX_TOP_K);
      }
    }

    // ── Namespace (always from auth uid) ─────────────────────────────────────
    const namespace = selahNamespace(uid);

    // ── Build query text ─────────────────────────────────────────────────────
    // If verseRef is provided, prepend it to weight the embedding toward that reference.
    const queryText = buildNoteQueryText(verseRef, query);

    // ── Embed query ──────────────────────────────────────────────────────────
    // Do NOT pass a cacheKey for queries: query results must always be fresh.
    let queryVector;
    try {
      queryVector = await openaiEmbed(queryText, null);
    } catch (embedErr) {
      // Embedding failure: fail gracefully — return degraded empty, not a crash
      console.error(`[querySelahCorpus] Embedding failed for uid ${uid}:`, embedErr.message);
      logFunction("querySelahCorpus", {
        uid,
        error: `embed_failed: ${embedErr.message}`,
        durationMs: Date.now() - startMs,
      });
      return { results: [], empty: true, degraded: true };
    }

    // ── Query Pinecone (strictly scoped to uid namespace) ────────────────────
    let rawResults;
    try {
      // INVARIANT: namespace is always `selah-notes-${uid}` (from auth, not payload).
      // No cross-user retrieval is possible because the namespace constructor enforces uid.
      rawResults = await require("../mlClients").pineconeQuery(namespace, queryVector, topK);
    } catch (queryErr) {
      // Pinecone unavailable: fail gracefully — return degraded empty, never throw to client
      console.error(`[querySelahCorpus] Pinecone query failed for uid ${uid}:`, queryErr.message);
      logFunction("querySelahCorpus", {
        uid,
        error: `pinecone_query_failed: ${queryErr.message}`,
        durationMs: Date.now() - startMs,
      });
      return { results: [], empty: true, degraded: true };
    }

    // pineconeQuery returns [] on network failure, never throws (see mlClients.js).
    // Still wrap in a guard in case of unexpected non-array.
    if (!Array.isArray(rawResults)) {
      console.warn(`[querySelahCorpus] Unexpected non-array from Pinecone for uid ${uid}`);
      return { results: [], empty: true, degraded: true };
    }

    // ── Filter soft-deleted notes ─────────────────────────────────────────────
    const activeResults = filterDeletedNotes(rawResults);

    // ── No fabrication: empty results → return empty ─────────────────────────
    if (activeResults.length === 0) {
      logFunction("querySelahCorpus", {
        uid,
        topK,
        resultCount: 0,
        durationMs: Date.now() - startMs,
      });
      return { results: [], empty: true };
    }

    // ── Shape results — only contract-defined fields, no internal metadata leaks ──
    const results = activeResults.map((hit) => ({
      noteId: hit.id,
      verseRef: hit.metadata?.verseRef ?? null,
      kind: hit.metadata?.kind ?? null,
      score: typeof hit.score === "number" ? hit.score : null,
      body: hit.metadata?.body ?? null,
      color: hit.metadata?.color ?? null,
      createdAt: hit.metadata?.createdAt ?? null,
      // Explicitly excluded: uid, deletedAt (internal), any unlisted field
    }));

    logFunction("querySelahCorpus", {
      uid,
      topK,
      resultCount: results.length,
      durationMs: Date.now() - startMs,
    });

    return { results, empty: false };
  }
);
