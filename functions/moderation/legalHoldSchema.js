"use strict";

/**
 * legalHoldSchema.js
 *
 * SINGLE SOURCE OF TRUTH for the legalHolds Firestore collection schema.
 *
 * Every write to legalHolds/{holdId} MUST go through buildLegalHoldDoc() so
 * that downstream NCMEC reporting tools and legal review tooling always see a
 * consistent document shape. Adding a field here automatically propagates to
 * every writer.
 *
 * Schema version: v1 (2026-06-11)
 *
 * Exports:
 *   buildLegalHoldDoc(params)  — returns the plain object to be written to Firestore
 *   LEGAL_HOLD_SCHEMA_VERSION  — string version stamp written into every doc
 */

const crypto = require("crypto");
const { FieldValue } = require("firebase-admin/firestore");

const LEGAL_HOLD_SCHEMA_VERSION = "v1";

/**
 * buildLegalHoldDoc(params)
 *
 * Constructs a canonical legalHolds document.  All three writers (legalHold.js,
 * escalation.js createLegalHold, escalation.js escalateChildSafety) call this
 * function so the collection stays schema-consistent.
 *
 * Required params:
 *   holdId          {string}  Firestore document ID (same as caseId for system path;
 *                             crypto.randomUUID() for user-report path — caller decides)
 *   caseId          {string}  Cross-reference key linking legalHolds ↔ childSafetyEscalations
 *   contentRef      {string}  Firestore document path of the offending content
 *                             (e.g. "posts/abc123").  Alias: sourceContentRef accepted.
 *   contentSnapshot {object|null}  Plain-object copy of the document data at detection time.
 *                                  Alias: postSnapshot / evidenceSnapshot accepted.
 *
 * Optional params:
 *   type            {string}   Detection type label, default "csam_suspected"
 *   sourceUserId    {string|null}  UID of content author.  Alias: authorId / authorUid.
 *   reporterUserId  {string|null}  UID of reporter.  Alias: reporterUid.
 *   categories      {string[]} Matched safety-category strings, default []
 *   status          {string}   Default "new"
 *   severity        {string}   Default "critical"
 *   externalReport  {object}   NCMEC reporting block; defaults to the standard
 *                              NCMEC_CYBERTIPLINE stub (required:true, submitted:false)
 *
 * @returns {object} Plain Firestore document object (no DocumentReference fields)
 */
function buildLegalHoldDoc(params) {
  const {
    holdId,
    caseId,
    // accept both naming conventions used across callers
    contentRef      = params.sourceContentRef ?? null,
    contentSnapshot = params.postSnapshot ?? params.evidenceSnapshot ?? null,
    type            = "csam_suspected",
    sourceUserId    = params.authorId ?? params.authorUid ?? null,
    reporterUserId  = params.reporterUid ?? "system",
    categories      = [],
    status          = "new",
    severity        = "critical",
    externalReport  = null,
  } = params;

  if (!holdId)     throw new Error("[legalHoldSchema] holdId is required");
  if (!caseId)     throw new Error("[legalHoldSchema] caseId is required");
  if (!contentRef) throw new Error("[legalHoldSchema] contentRef / sourceContentRef is required");

  // SHA-256 fingerprint of the snapshot for tamper detection.
  const snapshotHash = crypto
    .createHash("sha256")
    .update(JSON.stringify(contentSnapshot ?? null))
    .digest("hex");

  const canonicalExternalReport = externalReport ?? {
    required:       true,
    provider:       "NCMEC_CYBERTIPLINE",
    submitted:      false,
    submittedAt:    null,
    confirmationId: null,
  };

  return {
    // ── Identity ───────────────────────────────────────────────────────────────
    schemaVersion:   LEGAL_HOLD_SCHEMA_VERSION,
    holdId,          // document ID echoed into the body for self-identification
    caseId,          // cross-reference to childSafetyEscalations/{caseId}

    // ── Content reference ──────────────────────────────────────────────────────
    contentRef,      // canonical field name; previously split across contentRef/sourceContentRef/postRef
    type,

    // ── Actor references ───────────────────────────────────────────────────────
    sourceUserId,    // UID of content author (null if anonymous/unknown)
    reporterUserId,  // UID of user who reported, or "system"

    // ── Evidence ───────────────────────────────────────────────────────────────
    contentSnapshot: contentSnapshot ?? null,  // verbatim document data at detection
    snapshotHash,                              // SHA-256 of JSON.stringify(contentSnapshot)
    categories:      Array.isArray(categories) ? categories : [],

    // ── Status ─────────────────────────────────────────────────────────────────
    status,
    severity,

    // ── Legal-hold flags ───────────────────────────────────────────────────────
    legalHold:       true,   // retention-policy cleanup jobs check this flag
    immutable:       true,   // belt-and-suspenders: doc must not be mutated post-creation

    // ── Disposition tracking (updated only by authorised legal/compliance staff) ──
    disposition:      "preserved",
    dispositionAt:    null,
    dispositionBy:    null,
    dispositionNote:  null,

    // ── NCMEC external reporting ───────────────────────────────────────────────
    externalReport:  canonicalExternalReport,

    // ── Timestamps ─────────────────────────────────────────────────────────────
    preservedAt:  FieldValue.serverTimestamp(),   // alias used by cyberTiplineInterface.js
    createdAt:    FieldValue.serverTimestamp(),
    updatedAt:    FieldValue.serverTimestamp(),
  };
}

module.exports = { buildLegalHoldDoc, LEGAL_HOLD_SCHEMA_VERSION };
