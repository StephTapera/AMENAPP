"use strict";

/**
 * legalHold.js
 *
 * Immutable evidence preservation for child-safety escalations.
 *
 * When CSAM or child-exploitation content is detected, the original document
 * must be preserved in its exact state before any removal occurs, and the
 * source document must be marked so that no retention-policy cleanup job
 * can destroy the evidence.
 *
 * Firestore security rules for the legalHolds collection MUST deny all
 * client writes and deletes. Only Cloud Functions (admin SDK) may write here.
 *
 * SCHEMA NOTE (H4 fix 2026-06-11):
 *   All writes to the legalHolds collection MUST go through createLegalHold()
 *   in this file, which delegates to buildLegalHoldDoc() in legalHoldSchema.js.
 *   Never write to legalHolds directly from escalation.js or moderatePost.js.
 *   This ensures the NCMEC reporting pipeline and legal review tooling always
 *   see a consistent document shape.
 *
 * Exports:
 *   createLegalHold(db, contentRef, contentSnapshot, caseId, opts)
 *   isUnderLegalHold(db, contentRef)   — boolean check on the source document
 *   getLegalHoldEvidence(db, caseId)   — admin-only evidence retrieval
 */

const { FieldValue } = require("firebase-admin/firestore");
const { buildLegalHoldDoc } = require("./legalHoldSchema");

// ─── createLegalHold ───────────────────────────────────────────────────────────

/**
 * createLegalHold(db, contentRef, contentSnapshot, caseId, opts)
 *
 * THE SINGLE WRITER for the legalHolds Firestore collection.
 * All code paths that need to create a legal hold must call this function.
 *
 * 1. Builds a canonical legalHolds document via buildLegalHoldDoc().
 * 2. Writes an immutable snapshot of the content to legalHolds/{holdId}.
 * 3. Sets legalHold: true on the original content document so that
 *    retention-policy cleanup jobs can skip it.
 *
 * The snapshot document is keyed by holdId. holdId defaults to caseId (system
 * detection path); callers may pass opts.holdId to override (user-report path
 * uses a separate UUID so the document ID can differ from caseId while still
 * carrying both IDs in the document body for cross-referencing).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} contentRef        Firestore document path (e.g. "posts/abc123")
 * @param {object} contentSnapshot   Plain-object copy of the document data at the
 *                                   time of detection (call .data() before passing in)
 * @param {string} caseId            UUID cross-referencing childSafetyEscalations
 * @param {object} [opts]            Optional overrides forwarded to buildLegalHoldDoc:
 *                                     holdId, type, sourceUserId, reporterUserId,
 *                                     categories, status, severity, externalReport
 * @returns {Promise<string>} holdId — the legalHolds document ID
 */
async function createLegalHold(db, contentRef, contentSnapshot, caseId, opts = {}) {
  if (!contentRef) throw new Error("[legalHold] contentRef is required");
  if (!caseId)     throw new Error("[legalHold] caseId is required");

  // holdId defaults to caseId (system path) but callers may override (user-report path).
  const holdId = opts.holdId ?? caseId;

  // Build the canonical document — single schema for all writers.
  const holdDoc = buildLegalHoldDoc({
    holdId,
    caseId,
    contentRef,
    contentSnapshot,
    ...opts,
  });

  // Step 1: Write immutable hold record.
  await db.collection("legalHolds").doc(holdId).set(holdDoc);

  console.log(`[legalHold] Hold created: holdId=${holdId} caseId=${caseId} contentRef=${contentRef}`);

  // Step 2: Mark the original document so cleanup jobs leave it alone.
  // Use merge:true so we don't clobber other fields on the document.
  try {
    await db.doc(contentRef).set(
      { legalHold: true, legalHoldCaseId: caseId, legalHoldAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    console.log(`[legalHold] Source document marked: contentRef=${contentRef}`);
  } catch (err) {
    // Log but do not abort: the hold record already exists; the source-document
    // flag is a belt-and-suspenders protection, not the primary hold.
    console.error(
      `[legalHold] WARNING: failed to mark source document ${contentRef}:`,
      err.message
    );
  }

  return holdId;
}

// ─── isUnderLegalHold ─────────────────────────────────────────────────────────

/**
 * isUnderLegalHold(db, contentRef)
 *
 * Returns true if the content document has legalHold: true set.
 * This is a lightweight check intended for use in retention/deletion pipelines
 * to prevent accidental destruction of evidence.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} contentRef   Firestore document path
 * @returns {Promise<boolean>}
 */
async function isUnderLegalHold(db, contentRef) {
  if (!contentRef) return false;

  try {
    const snap = await db.doc(contentRef).get();
    if (!snap.exists) {
      // Document may have been deleted — check legalHolds collection instead.
      const holdSnap = await db
        .collection("legalHolds")
        .where("contentRef", "==", contentRef)
        .limit(1)
        .get();
      return !holdSnap.empty;
    }
    return snap.data()?.legalHold === true;
  } catch (err) {
    // Fail safe: if we cannot confirm the hold status, treat as held.
    console.error(`[legalHold] isUnderLegalHold check failed for ${contentRef}:`, err.message);
    return true;
  }
}

// ─── getLegalHoldEvidence ──────────────────────────────────────────────────────

/**
 * getLegalHoldEvidence(db, caseId)
 *
 * Retrieves the preserved evidence snapshot for a given case.
 *
 * ADMIN-ONLY: callers must verify the requesting user holds the
 * trust_safety_admin or legal_admin role before calling this function.
 * The snapshot contains the original content data, which may be illegal
 * to view without authorisation.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} caseId
 * @returns {Promise<object|null>} Plain hold document object, or null if not found
 */
async function getLegalHoldEvidence(db, caseId) {
  if (!caseId) throw new Error("[legalHold] getLegalHoldEvidence: caseId is required");

  // Primary lookup: system-detection path uses holdId==caseId, so try doc(caseId) first.
  let snap = await db.collection("legalHolds").doc(caseId).get();

  // Fallback: user-report path uses a separate holdId UUID — query by caseId field.
  if (!snap.exists) {
    const q = await db.collection("legalHolds").where("caseId", "==", caseId).limit(1).get();
    snap = q.empty ? null : q.docs[0];
  }

  if (!snap || !snap.exists) {
    console.warn(`[legalHold] No hold found for caseId=${caseId}`);
    return null;
  }

  return { id: snap.id, ...snap.data() };
}

// ─── Exports ───────────────────────────────────────────────────────────────────

module.exports = { createLegalHold, isUnderLegalHold, getLegalHoldEvidence };
