/**
 * notebookFunctions.js — AMEN Connected Intelligence v1 · Amen Notebooks backend
 *
 * Five gen2 callable / scheduled Cloud Functions backing the Notebooks surface:
 *
 *   notebookCreate     — create a notebook by NotebookKind; server derives the
 *                        per-notebook Pinecone namespace (never client-supplied).
 *   notebookIngest     — attach a source, chunk → embed → upsert into the
 *                        notebook's PRIVATE namespace.
 *   notebookQuery      — retrieve grounding chunks → callModel (grounded) →
 *                        cite-or-REFUSE. NEVER answers ungrounded.
 *   notebookSoftDelete — set deletedAt (soft delete); the namespace is purged
 *                        later by the scheduled hard-purge job.
 *   notebookPurgeJob   — onSchedule; for every soft-deleted notebook past the
 *                        retention window, delete the WHOLE Pinecone namespace
 *                        and hard-remove the Firestore doc.
 *
 * HARD INVARIANTS (contract: connectedIntelligence.contracts.ts → Notebook):
 *   1. pineconeNamespace is ALWAYS server-derived as `notebook-{uid}-{notebookId}`.
 *      The client may never supply, override, or read another user's namespace.
 *   2. uid comes ONLY from request.auth.uid — never from the payload.
 *   3. FAIL-CLOSED grounding: notebookQuery refuses (reason 'ungrounded') when the
 *      notebook has zero indexed chunks OR retrieval returns nothing. It NEVER
 *      produces an answer without cited source chunks.
 *   4. Scripture-comparison legs route Claude-exclusive (`berean_answer`) and carry
 *      BibleProvider-style open-licensed citations.
 *   5. Caps from connectedIntelligence.config.ts: maxNotebooksFree, maxSourcesFree/Plus.
 *      Safety/crisis domains are out of scope here, so no cap exemption logic needed.
 *   6. Group notebooks (kind=group) are shared into a Space via sharedWithSpaceId;
 *      contributions are attributed but NO contribution counts are computed or stored.
 *   7. Soft-delete only in notebookSoftDelete; hard purge happens in notebookPurgeJob.
 *
 * Auth + rate limiting reuse the shared helpers (requireBereanAuth-style guard +
 * enforceRateLimit). callModel is the centralized router — no provider is named here.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const {
  openaiEmbed,
  openaiEmbedBatch,
  pineconeUpsert,
  pineconeQuery,
  logFunction,
} = require("../mlClients");
const { enforceRateLimit } = require("../rateLimiter");
const { callModel } = require("../router/callModel");

// ---------------------------------------------------------------------------
// CONFIG (mirror of connectedIntelligence.config.ts → notebooks + limits)
// These are the SERVER-side caps. Kept in sync with the TS config by Agent A.
// ---------------------------------------------------------------------------

const NOTEBOOK_CONFIG = {
  maxSourcesFree: 10,
  maxSourcesPlus: 100,
  maxNotebooksFree: 3,
};

const VALID_KINDS = ["sermon", "study", "prayer_journal", "project", "group", "event"];
const VALID_SOURCE_TYPES = ["note", "sermon", "verse_range", "doc", "chat_checkpoint"];

// Chunking
const CHUNK_CHAR_SIZE = 900;     // ~ 220 tokens; safe for text-embedding-3-small
const CHUNK_CHAR_OVERLAP = 120;
const MAX_CHUNKS_PER_SOURCE = 60;
const RETRIEVE_TOP_K = 6;
const MIN_GROUNDING_SCORE = 0.0; // Pinecone cosine; keep permissive — presence of a chunk is the gate

// Rate-limit windows (per uid)
const CREATE_MAX = 20;  const CREATE_WINDOW = 3600;   // 20 notebooks/hour
const INGEST_MAX = 60;  const INGEST_WINDOW = 3600;   // 60 ingests/hour
const QUERY_MAX = 40;   const QUERY_WINDOW = 3600;    // 40 queries/hour
const DELETE_MAX = 30;  const DELETE_WINDOW = 3600;

// Soft-delete retention before the namespace is hard-purged.
const PURGE_RETENTION_DAYS = 7;

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

function db() {
  return admin.firestore();
}

/** Auth guard — uid ALWAYS from auth, never from payload. */
function requireAuthUid(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required for notebooks.");
  }
  return uid;
}

/** Server-derived per-notebook namespace. The ONLY source of truth. */
function notebookNamespace(uid, notebookId) {
  return `notebook-${uid}-${notebookId}`;
}

function notebookRef(uid, notebookId) {
  return db().collection("users").doc(uid).collection("notebooks").doc(notebookId);
}

function notebooksCol(uid) {
  return db().collection("users").doc(uid).collection("notebooks");
}

/** Resolve the caller's plan; defaults to 'free'. */
async function resolvePlan(uid) {
  try {
    const snap = await db().collection("users").doc(uid).get();
    const plan = snap.exists ? snap.data()?.plan : null;
    return plan === "plus" || plan === "pro" ? plan : "free";
  } catch (_) {
    return "free";
  }
}

function maxSourcesForPlan(plan) {
  return plan === "free" ? NOTEBOOK_CONFIG.maxSourcesFree : NOTEBOOK_CONFIG.maxSourcesPlus;
}

/** Deterministic, overlap-aware character chunker. */
function chunkText(text) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (!clean) return [];
  const chunks = [];
  let start = 0;
  while (start < clean.length && chunks.length < MAX_CHUNKS_PER_SOURCE) {
    const end = Math.min(start + CHUNK_CHAR_SIZE, clean.length);
    chunks.push(clean.slice(start, end));
    if (end >= clean.length) break;
    start = end - CHUNK_CHAR_OVERLAP;
  }
  return chunks;
}

/** Detect a scripture-comparison intent in the query (e.g. "compare with Romans 8"). */
function isScriptureComparison(query) {
  const q = String(query || "");
  // A book name + chapter (optionally :verse) signals a scripture leg.
  return /\b(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|Jude|Revelation)\b\s*\d+/i
    .test(q);
}

// ---------------------------------------------------------------------------
// FUNCTION 1: notebookCreate
// ---------------------------------------------------------------------------
/**
 * Create a notebook by NotebookKind. The Pinecone namespace is derived
 * server-side and stored on the doc; a client-supplied namespace is rejected.
 *
 * Input: { kind, title, sharedWithSpaceId?, sourceRefs? }
 * Returns: { success, notebookId, pineconeNamespace }
 */
exports.notebookCreate = onCall({ region: "us-central1" }, async (request) => {
  const startMs = Date.now();
  const uid = requireAuthUid(request);
  await enforceRateLimit(uid, "notebook_create", CREATE_MAX, CREATE_WINDOW);

  const data = request.data || {};

  // SECURITY: never accept a client-supplied namespace.
  if ("pineconeNamespace" in data) {
    throw new HttpsError(
      "invalid-argument",
      "pineconeNamespace is server-derived and must not be supplied by the client."
    );
  }

  const { kind, title, sharedWithSpaceId, sourceRefs } = data;

  if (!VALID_KINDS.includes(kind)) {
    throw new HttpsError("invalid-argument", `kind must be one of: ${VALID_KINDS.join(", ")}.`);
  }
  if (!title || typeof title !== "string" || title.trim() === "") {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (title.length > 140) {
    throw new HttpsError("invalid-argument", "title exceeds 140 character limit.");
  }

  // Validate sharedWithSpaceId only allowed for group notebooks.
  let sharedSpace = null;
  if (sharedWithSpaceId !== undefined && sharedWithSpaceId !== null) {
    if (kind !== "group") {
      throw new HttpsError("invalid-argument", "sharedWithSpaceId is only valid for group notebooks.");
    }
    if (typeof sharedWithSpaceId !== "string") {
      throw new HttpsError("invalid-argument", "sharedWithSpaceId must be a string.");
    }
    // Enforce existing Space membership before sharing into it.
    const ok = await isSpaceMember(uid, sharedWithSpaceId);
    if (!ok) {
      throw new HttpsError("permission-denied", "You are not a member of that Space.");
    }
    sharedSpace = sharedWithSpaceId;
  }

  // Validate sourceRefs shape (optional at creation).
  const cleanRefs = [];
  if (Array.isArray(sourceRefs)) {
    for (const ref of sourceRefs) {
      if (!ref || !VALID_SOURCE_TYPES.includes(ref.type) || typeof ref.pointer !== "string") {
        throw new HttpsError("invalid-argument", "Each sourceRef needs a valid type and pointer.");
      }
      cleanRefs.push({ type: ref.type, pointer: ref.pointer });
    }
  }

  // Free-plan notebook cap (active, non-deleted notebooks only).
  const plan = await resolvePlan(uid);
  if (plan === "free") {
    const activeSnap = await notebooksCol(uid).where("deletedAt", "==", null).get();
    if (activeSnap.size >= NOTEBOOK_CONFIG.maxNotebooksFree) {
      throw new HttpsError(
        "resource-exhausted",
        `Free plan is limited to ${NOTEBOOK_CONFIG.maxNotebooksFree} notebooks. Upgrade for more.`
      );
    }
  }

  const ref = notebooksCol(uid).doc();
  const notebookId = ref.id;
  const pineconeNamespace = notebookNamespace(uid, notebookId);

  await ref.set({
    id: notebookId,
    uid,
    kind,
    title: title.trim(),
    sourceRefs: cleanRefs,
    pineconeNamespace,
    sharedWithSpaceId: sharedSpace,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    deletedAt: null,
    // Bookkeeping (not in the public contract; server-only):
    sourceCount: cleanRefs.length,
    chunkCount: 0,
  });

  logFunction("notebookCreate", { uid, notebookId, kind, durationMs: Date.now() - startMs });
  return { success: true, notebookId, pineconeNamespace };
});

// ---------------------------------------------------------------------------
// FUNCTION 2: notebookIngest
// ---------------------------------------------------------------------------
/**
 * Attach a source to a notebook and index it: chunk → embed → upsert into the
 * notebook's PRIVATE Pinecone namespace.
 *
 * Input: { notebookId, sourceType, pointer, title?, content }
 * Returns: { success, chunksIndexed, sourceId }
 */
exports.notebookIngest = onCall({ region: "us-central1" }, async (request) => {
  const startMs = Date.now();
  const uid = requireAuthUid(request);
  await enforceRateLimit(uid, "notebook_ingest", INGEST_MAX, INGEST_WINDOW);

  const data = request.data || {};
  const { notebookId, sourceType, pointer, title, content } = data;

  if (!notebookId || typeof notebookId !== "string") {
    throw new HttpsError("invalid-argument", "notebookId is required.");
  }
  if (!VALID_SOURCE_TYPES.includes(sourceType)) {
    throw new HttpsError("invalid-argument", `sourceType must be one of: ${VALID_SOURCE_TYPES.join(", ")}.`);
  }
  if (!pointer || typeof pointer !== "string") {
    throw new HttpsError("invalid-argument", "pointer (deep link to source of truth) is required.");
  }
  if (!content || typeof content !== "string" || content.trim() === "") {
    throw new HttpsError("invalid-argument", "content is required to index a source.");
  }

  const ref = notebookRef(uid, notebookId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Notebook not found.");
  }
  const notebook = snap.data();
  if (notebook.deletedAt) {
    throw new HttpsError("failed-precondition", "Cannot add sources to a deleted notebook.");
  }

  // Source cap by plan.
  const plan = await resolvePlan(uid);
  const maxSources = maxSourcesForPlan(plan);
  if ((notebook.sourceCount || 0) >= maxSources) {
    throw new HttpsError(
      "resource-exhausted",
      `This notebook has reached its ${maxSources}-source limit for your plan.`
    );
  }

  // SECURITY: derive namespace; never trust a stored value the client could have forged
  // via a direct Firestore write (rules deny client writes, but defense-in-depth).
  const namespace = notebookNamespace(uid, notebookId);

  // Chunk.
  const chunks = chunkText(content);
  if (chunks.length === 0) {
    throw new HttpsError("invalid-argument", "Source produced no indexable text.");
  }

  const sourceId = db().collection("_ids").doc().id; // opaque source id

  // Embed (batched).
  let vectors;
  try {
    vectors = await openaiEmbedBatch(chunks);
  } catch (err) {
    logFunction("notebookIngest", { uid, notebookId, error: `embed_failed: ${err.message}`, durationMs: Date.now() - startMs });
    return { success: false, error: "Failed to embed source. Please try again." };
  }

  // Build Pinecone payloads. Metadata carries enough to CITE the chunk later.
  const upserts = chunks.map((chunkBody, i) => ({
    id: `${sourceId}_${i}`,
    values: vectors[i],
    metadata: {
      uid,                       // defense-in-depth; namespace already scopes by uid
      notebookId,
      sourceId,
      sourceType,
      pointer,
      sourceTitle: typeof title === "string" ? title.slice(0, 160) : "",
      chunkIndex: i,
      text: chunkBody,
    },
  }));

  try {
    await pineconeUpsert(namespace, upserts);
  } catch (err) {
    logFunction("notebookIngest", { uid, notebookId, error: `upsert_failed: ${err.message}`, durationMs: Date.now() - startMs });
    return { success: false, error: "Failed to index source. Please try again." };
  }

  // Update notebook bookkeeping + append sourceRef.
  await ref.update({
    sourceRefs: admin.firestore.FieldValue.arrayUnion({ type: sourceType, pointer }),
    sourceCount: admin.firestore.FieldValue.increment(1),
    chunkCount: admin.firestore.FieldValue.increment(chunks.length),
  });

  logFunction("notebookIngest", { uid, notebookId, sourceId, chunksIndexed: chunks.length, namespace, durationMs: Date.now() - startMs });
  return { success: true, chunksIndexed: chunks.length, sourceId };
});

// ---------------------------------------------------------------------------
// FUNCTION 3: notebookQuery
// ---------------------------------------------------------------------------
/**
 * Grounded notebook query. Pipeline:
 *   1. Resolve namespace from auth uid + notebookId (server-derived).
 *   2. Embed query → retrieve top-K chunks from the notebook's PRIVATE namespace.
 *   3. FAIL-CLOSED: zero indexed chunks OR zero retrieval ⇒ REFUSE (reason 'ungrounded').
 *      Never call the model without grounding; never fabricate.
 *   4. Call callModel grounded with the retrieved chunks as context.
 *      - Scripture-comparison legs ⇒ task 'berean_answer' (Claude-exclusive, requires
 *        scripture citations) so the answer carries open-licensed verse citations.
 *      - Note/sermon synthesis ⇒ task 'quick_summary' grounded ONLY by injected chunks.
 *   5. Map any callModel block (retrieval_failed | citations_required | guard) to REFUSE.
 *   6. Return the answer PLUS the citations (which source chunks were used).
 *
 * Input: { notebookId, query }
 * Returns one of:
 *   { grounded:true, answer, citations:[{sourceId,sourceType,pointer,sourceTitle,chunkIndex,score,snippet}], scripture:boolean }
 *   { grounded:false, refused:true, reason, message }   // explicit ungrounded REFUSE
 */
exports.notebookQuery = onCall({ region: "us-central1" }, async (request) => {
  const startMs = Date.now();
  const uid = requireAuthUid(request);
  await enforceRateLimit(uid, "notebook_query", QUERY_MAX, QUERY_WINDOW);

  const data = request.data || {};
  const { notebookId, query } = data;

  if (!notebookId || typeof notebookId !== "string") {
    throw new HttpsError("invalid-argument", "notebookId is required.");
  }
  if (!query || typeof query !== "string" || query.trim() === "") {
    throw new HttpsError("invalid-argument", "query is required.");
  }
  if (query.length > 2000) {
    throw new HttpsError("invalid-argument", "query exceeds 2000 character limit.");
  }

  const ref = notebookRef(uid, notebookId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Notebook not found.");
  }
  const notebook = snap.data();
  if (notebook.deletedAt) {
    throw new HttpsError("failed-precondition", "This notebook has been deleted.");
  }

  const namespace = notebookNamespace(uid, notebookId);

  // ── FAIL-CLOSED gate #1: notebook has no indexed chunks at all ──────────────
  if (!notebook.chunkCount || notebook.chunkCount === 0) {
    logFunction("notebookQuery", { uid, notebookId, refused: "no_index", durationMs: Date.now() - startMs });
    return {
      grounded: false,
      refused: true,
      reason: "ungrounded",
      message: "I can only answer from sources you've added to this notebook. Add at least one source to begin.",
    };
  }

  // ── Embed query (no cache — queries must be fresh) ──────────────────────────
  let queryVector;
  try {
    queryVector = await openaiEmbed(query, null);
  } catch (err) {
    logFunction("notebookQuery", { uid, notebookId, error: `embed_failed: ${err.message}`, durationMs: Date.now() - startMs });
    return {
      grounded: false,
      refused: true,
      reason: "ungrounded",
      message: "I couldn't search this notebook just now. Please try again.",
    };
  }

  // ── Retrieve grounding chunks from the PRIVATE namespace ────────────────────
  let matches;
  try {
    matches = await pineconeQuery(namespace, queryVector, RETRIEVE_TOP_K);
  } catch (err) {
    logFunction("notebookQuery", { uid, notebookId, error: `retrieve_failed: ${err.message}`, durationMs: Date.now() - startMs });
    matches = [];
  }

  const grounding = (Array.isArray(matches) ? matches : [])
    .filter((m) => (typeof m.score === "number" ? m.score >= MIN_GROUNDING_SCORE : true))
    .filter((m) => m.metadata?.text);

  // ── FAIL-CLOSED gate #2: nothing retrieved ⇒ REFUSE, never answer ───────────
  if (grounding.length === 0) {
    logFunction("notebookQuery", { uid, notebookId, refused: "no_grounding", durationMs: Date.now() - startMs });
    return {
      grounded: false,
      refused: true,
      reason: "ungrounded",
      message: "I couldn't find anything in this notebook's sources to ground an answer. Try adding more sources or rephrasing.",
    };
  }

  // ── Build cited context block + citation list ───────────────────────────────
  const citations = grounding.map((m, idx) => ({
    sourceId: m.metadata.sourceId ?? null,
    sourceType: m.metadata.sourceType ?? null,
    pointer: m.metadata.pointer ?? null,
    sourceTitle: m.metadata.sourceTitle ?? "",
    chunkIndex: typeof m.metadata.chunkIndex === "number" ? m.metadata.chunkIndex : null,
    score: typeof m.score === "number" ? m.score : null,
    snippet: String(m.metadata.text).slice(0, 240),
    marker: `[${idx + 1}]`,
  }));

  const contextBlock = grounding
    .map((m, idx) => `[${idx + 1}] (${m.metadata.sourceTitle || m.metadata.sourceType || "source"}): ${m.metadata.text}`)
    .join("\n\n");

  const scripture = isScriptureComparison(query);

  // ── Route: scripture-comparison ⇒ Claude-exclusive berean_answer (citations
  //    required); otherwise grounded note-synthesis via quick_summary. ─────────
  const task = scripture ? "berean_answer" : "quick_summary";

  const systemPrompt = scripture
    ? "You are AMEN's grounded study assistant. Answer ONLY from the NOTEBOOK SOURCES provided below and from canonical scripture. " +
      "When you reference scripture, cite it in 'Book Chapter:Verse' form using open-licensed translations (BSB/WEB/KJV). " +
      "Cite notebook sources using their bracket markers like [1], [2]. If the sources do not support an answer, say so plainly — never invent content."
    : "You are AMEN's grounded study assistant. Answer ONLY from the NOTEBOOK SOURCES provided below. " +
      "Cite every claim with the source's bracket marker like [1], [2]. " +
      "If the sources do not contain enough to answer, say so plainly — never invent content.";

  let result;
  try {
    result = await callModel({
      task,
      input: query,
      systemPrompt,
      context: `NOTEBOOK SOURCES:\n${contextBlock}`,
      userId: uid,
      safetyLevel: "standard",
      // We pass the namespace/queryVector too so the router's own retrieval (for
      // berean_answer) reinforces grounding; our injected context is the primary ground.
      namespace,
      queryVector,
    });
  } catch (err) {
    logFunction("notebookQuery", { uid, notebookId, error: `callModel_threw: ${err.message}`, durationMs: Date.now() - startMs });
    return {
      grounded: false,
      refused: true,
      reason: "ungrounded",
      message: "The study assistant is temporarily unavailable. Your sources are safe — please try again.",
    };
  }

  // ── Map any block (retrieval_failed | citations_required | guard) to REFUSE ─
  if (result?.blocked || result?.output == null) {
    logFunction("notebookQuery", {
      uid, notebookId, refused: result?.reason || "blocked", durationMs: Date.now() - startMs,
    });
    return {
      grounded: false,
      refused: true,
      reason: "ungrounded",
      message:
        result?.reason === "citations_required"
          ? "I couldn't ground that answer in scripture or your sources, so I won't guess. Try adding the passage or more notes."
          : "I couldn't produce a grounded answer from this notebook's sources. Add more sources or rephrase.",
    };
  }

  const answer = typeof result.output === "string" ? result.output : JSON.stringify(result.output);

  logFunction("notebookQuery", {
    uid, notebookId, task, scripture, citationCount: citations.length, durationMs: Date.now() - startMs,
  });

  return {
    grounded: true,
    answer,
    citations,
    scripture,
  };
});

// ---------------------------------------------------------------------------
// FUNCTION 4: notebookSoftDelete
// ---------------------------------------------------------------------------
/**
 * Soft-delete a notebook (set deletedAt). The Pinecone namespace is NOT purged
 * here — notebookPurgeJob hard-purges it after the retention window.
 *
 * Input: { notebookId }
 * Returns: { success, deletedAt }
 */
exports.notebookSoftDelete = onCall({ region: "us-central1" }, async (request) => {
  const startMs = Date.now();
  const uid = requireAuthUid(request);
  await enforceRateLimit(uid, "notebook_soft_delete", DELETE_MAX, DELETE_WINDOW);

  const data = request.data || {};
  const { notebookId } = data;
  if (!notebookId || typeof notebookId !== "string") {
    throw new HttpsError("invalid-argument", "notebookId is required.");
  }

  const ref = notebookRef(uid, notebookId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Notebook not found.");
  }
  if (snap.data().deletedAt) {
    return { success: true, alreadyDeleted: true };
  }

  await ref.update({ deletedAt: admin.firestore.FieldValue.serverTimestamp() });

  logFunction("notebookSoftDelete", { uid, notebookId, durationMs: Date.now() - startMs });
  return { success: true };
});

// ---------------------------------------------------------------------------
// FUNCTION 5: notebookPurgeJob (onSchedule)
// ---------------------------------------------------------------------------
/**
 * Daily hard-purge. For every soft-deleted notebook whose deletedAt is older than
 * PURGE_RETENTION_DAYS, delete the WHOLE Pinecone namespace (deleteAll) and then
 * hard-remove the Firestore document.
 *
 * Uses a collectionGroup query over 'notebooks' so it covers all users.
 * Namespace deletion is best-effort per-notebook; the Firestore doc is only
 * removed after the namespace purge succeeds, so a transient Pinecone failure
 * leaves the doc to be retried on the next run (idempotent).
 */
exports.notebookPurgeJob = onSchedule(
  {
    schedule: "0 5 * * *", // daily at 5 AM UTC
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - PURGE_RETENTION_DAYS * 86400000);

    const snap = await db()
      .collectionGroup("notebooks")
      .where("deletedAt", "<", cutoff)
      .limit(200)
      .get();

    if (snap.empty) {
      console.log("[notebookPurgeJob] No notebooks past retention window.");
      return;
    }

    let purged = 0;
    let failed = 0;

    for (const doc of snap.docs) {
      const nb = doc.data();
      const uid = nb.uid;
      const notebookId = nb.id || doc.id;
      const namespace = notebookNamespace(uid, notebookId);

      try {
        await purgeNamespace(namespace);
        await doc.ref.delete(); // hard delete only after namespace purge succeeds
        purged += 1;
      } catch (err) {
        failed += 1;
        console.error(`[notebookPurgeJob] Failed to purge ${namespace}:`, err.message);
        // Leave the doc; next run retries (idempotent).
      }
    }

    console.log(`[notebookPurgeJob] Purged ${purged} notebooks, ${failed} deferred for retry.`);
  }
);

// ---------------------------------------------------------------------------
// INTERNAL: whole-namespace Pinecone purge (deleteAll).
// mlClients.pineconeDelete takes explicit ids; namespace-wide delete uses the
// REST deleteAll flag. Direct fetch mirrors the mlClients adapter pattern.
// ---------------------------------------------------------------------------

async function purgeNamespace(namespace) {
  const { getSecret } = require("../mlClients");
  const apiKey = await getSecret("PINECONE_API_KEY");
  const host = await getSecret("PINECONE_HOST");
  if (!apiKey || !host) {
    // Not configured (e.g. local emulator) — treat as no-op success so the
    // Firestore doc can still be removed.
    console.warn("[notebookPurgeJob] Pinecone not configured — skipping namespace purge.");
    return;
  }

  const res = await fetch(`https://${host}/vectors/delete`, {
    method: "POST",
    headers: { "Api-Key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ deleteAll: true, namespace }),
    signal: AbortSignal.timeout(10000),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    // 404 = namespace already gone; treat as success (idempotent).
    if (res.status === 404) return;
    throw new Error(`Pinecone deleteAll ${res.status}: ${body.slice(0, 160)}`);
  }
}

// ---------------------------------------------------------------------------
// INTERNAL: Space membership check (group notebooks).
// Reads spaces/{spaceId}/members/{uid}. NO contribution counts are read/derived.
// ---------------------------------------------------------------------------

async function isSpaceMember(uid, spaceId) {
  try {
    const memberSnap = await db()
      .collection("spaces").doc(spaceId)
      .collection("members").doc(uid)
      .get();
    if (memberSnap.exists && memberSnap.data()?.status !== "removed") return true;

    // Fallback: some Spaces store membership as an array on the space doc.
    const spaceSnap = await db().collection("spaces").doc(spaceId).get();
    if (spaceSnap.exists) {
      const members = spaceSnap.data()?.memberUids;
      if (Array.isArray(members) && members.includes(uid)) return true;
    }
    return false;
  } catch (err) {
    console.error(`[isSpaceMember] check failed for ${spaceId}:`, err.message);
    return false; // fail closed
  }
}
