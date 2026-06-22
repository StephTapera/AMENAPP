/**
 * selahCorpusUtils.js — Embedding + namespace helpers for the Selah personal study corpus.
 *
 * HARD LEGAL CONSTRAINT (from selah.contracts.ts §SECTION 2):
 *   translationRead may be a licensed version (ESV, NIV, NLT, NASB, etc.).
 *   It is for DISPLAY ONLY and must NEVER appear in any Pinecone embedding payload,
 *   metadata, or AI citation path. All helpers in this file enforce this invariant.
 *
 * PRIVACY INVARIANT:
 *   User namespaces are strictly per-user: `selah-notes-${uid}`.
 *   selahNamespace() is the single gated constructor — no caller may build the
 *   namespace string themselves. The uid must always come from request.auth.uid,
 *   never from the input payload.
 *
 * VALID NOTE KINDS: 'highlight' | 'note' | 'question' | 'prayer'
 */

"use strict";

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

/** Allowed note kinds, frozen from SelahNote interface in selah.contracts.ts */
const VALID_NOTE_KINDS = Object.freeze(["highlight", "note", "question", "prayer"]);

// ---------------------------------------------------------------------------
// NAMESPACE BUILDER
// ---------------------------------------------------------------------------

/**
 * Returns the strictly private Pinecone namespace for a user's selah notes.
 * This is the single gated constructor — no other code should interpolate this string.
 *
 * @param {string} uid - Must be request.auth.uid; never from client payload.
 * @returns {string} e.g. "selah-notes-abc123"
 * @throws if uid is missing or not a non-empty string
 */
function selahNamespace(uid) {
  if (!uid || typeof uid !== "string" || uid.trim() === "") {
    throw new Error("[selahCorpusUtils] uid is required to build a selah namespace. " +
      "Never pass uid from the client payload — always use request.auth.uid.");
  }
  return `selah-notes-${uid}`;
}

// ---------------------------------------------------------------------------
// EMBEDDING TEXT BUILDER
// ---------------------------------------------------------------------------

/**
 * Builds the plain-text string to embed for a given note.
 * Format: "[verseRef] [kind]: [body]"
 *
 * Invariants enforced:
 *   - translationRead is deliberately excluded (may contain licensed text).
 *   - null body is handled gracefully (replaced with empty string).
 *   - Resulting text is trimmed to avoid leading/trailing whitespace.
 *
 * @param {{ verseRef: string, kind: string, body: string|null }} note
 * @returns {string}
 */
function buildNoteEmbedText(note) {
  const verseRef = (note.verseRef || "").trim();
  const kind = (note.kind || "").trim();
  const body = (note.body || "").trim(); // null → ""

  // NOTE: translationRead is intentionally NOT included here.
  return `${verseRef} ${kind}: ${body}`.trim();
}

// ---------------------------------------------------------------------------
// EMBEDDING PAYLOAD BUILDER
// ---------------------------------------------------------------------------

/**
 * Builds the full Pinecone upsert payload for a single SelahNote.
 *
 * Returns: { id: string, vector: number[], metadata: object }
 * The caller is responsible for embedding the text and passing the vector in.
 *
 * For the upsert flow, use `buildNoteEmbedText` first to get the text,
 * then embed it with `openaiEmbed`, then call this function with the result.
 *
 * HARD RULE: translationRead must NEVER appear in the returned metadata.
 *
 * @param {{
 *   id: string,
 *   userId: string,
 *   verseRef: string,
 *   kind: string,
 *   color: string|null,
 *   body: string|null,
 *   createdAt: number,
 *   deletedAt: number|null
 * }} note - SelahNote fields (translationRead explicitly excluded at call site)
 * @param {number[]} vector - Pre-computed embedding vector
 * @returns {{ id: string, vector: number[], metadata: object }}
 */
function buildNoteEmbeddingPayload(note, vector) {
  if (!note.id) throw new Error("[selahCorpusUtils] buildNoteEmbeddingPayload: note.id is required");
  if (!note.userId) throw new Error("[selahCorpusUtils] buildNoteEmbeddingPayload: note.userId is required");
  if (!note.verseRef) throw new Error("[selahCorpusUtils] buildNoteEmbeddingPayload: note.verseRef is required");
  if (!VALID_NOTE_KINDS.includes(note.kind)) {
    throw new Error(`[selahCorpusUtils] buildNoteEmbeddingPayload: invalid kind "${note.kind}". ` +
      `Must be one of: ${VALID_NOTE_KINDS.join(", ")}`);
  }
  if (!Array.isArray(vector) || vector.length === 0) {
    throw new Error("[selahCorpusUtils] buildNoteEmbeddingPayload: vector must be a non-empty number[]");
  }

  // INVARIANT: translationRead deliberately excluded — licensed text must never enter Pinecone.
  const metadata = {
    uid: note.userId,
    verseRef: note.verseRef,
    kind: note.kind,
    color: note.color ?? null,
    body: note.body ?? null,           // stored for retrieval display; not used for re-embedding
    createdAt: note.createdAt ?? null,
    deletedAt: note.deletedAt ?? null,
  };

  return {
    id: note.id,
    vector,
    metadata,
  };
}

// ---------------------------------------------------------------------------
// QUERY TEXT BUILDER
// ---------------------------------------------------------------------------

/**
 * Builds the query text to embed for a corpus retrieval operation.
 * If verseRef is provided, it is prepended so that the embedding is weighted
 * toward that reference (the verse reference is a strong semantic signal).
 *
 * @param {string|undefined} verseRef - Optional Bible reference (e.g. "John 3:16")
 * @param {string|undefined} query    - Free-text query from the user
 * @returns {string} Combined query text ready for embedding
 */
function buildNoteQueryText(verseRef, query) {
  const ref = (verseRef || "").trim();
  const q = (query || "").trim();

  if (ref && q) return `${ref} ${q}`;
  if (ref) return ref;
  if (q) return q;

  // Fallback: return a generic corpus-scope string rather than empty
  return "selah notes";
}

// ---------------------------------------------------------------------------
// DELETED-NOTE FILTER
// ---------------------------------------------------------------------------

/**
 * Removes Pinecone match results where the note has been soft-deleted.
 * A note is considered deleted when metadata.deletedAt is non-null (any truthy value).
 *
 * @param {Array<{ id: string, score: number, metadata: object }>} results - Raw Pinecone matches
 * @returns {Array<{ id: string, score: number, metadata: object }>} Active (non-deleted) matches
 */
function filterDeletedNotes(results) {
  if (!Array.isArray(results)) return [];
  return results.filter((hit) => {
    // deletedAt must be null or undefined to be considered active.
    const deletedAt = hit?.metadata?.deletedAt;
    return deletedAt === null || deletedAt === undefined;
  });
}

// ---------------------------------------------------------------------------
// KIND VALIDATOR (exported for use by service layer)
// ---------------------------------------------------------------------------

/**
 * Validates that a note kind is one of the four contract-defined values.
 * Returns true if valid, false otherwise.
 *
 * @param {string} kind
 * @returns {boolean}
 */
function isValidNoteKind(kind) {
  return VALID_NOTE_KINDS.includes(kind);
}

// ---------------------------------------------------------------------------
// EXPORTS
// ---------------------------------------------------------------------------

module.exports = {
  selahNamespace,
  buildNoteEmbedText,
  buildNoteEmbeddingPayload,
  buildNoteQueryText,
  filterDeletedNotes,
  isValidNoteKind,
  VALID_NOTE_KINDS,
};
