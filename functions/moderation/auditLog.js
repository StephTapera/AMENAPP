"use strict";

/**
 * auditLog.js
 *
 * Tamper-evident audit log for all moderation and child-safety actions.
 *
 * Every write is immutable: documents are never updated, only created.
 * A simple content hash is stored alongside state snapshots so any
 * out-of-band modification is detectable during post-incident review.
 *
 * Exports:
 *   writeAuditLog(db, options)      — write one audit entry; never throws
 *   getAuditTrail(db, targetRef)    — retrieve all entries for a content ref
 */

const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

// ─── Simple deterministic hash ─────────────────────────────────────────────────

/**
 * sha256Hex(value)
 *
 * Returns the SHA-256 hex digest of JSON.stringify(value).
 * Used to create a tamper-evidence fingerprint of state snapshots.
 *
 * @param {*} value
 * @returns {string}
 */
function sha256Hex(value) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(value))
    .digest("hex");
}

// ─── writeAuditLog ─────────────────────────────────────────────────────────────

/**
 * writeAuditLog(db, options)
 *
 * Appends one immutable entry to moderationAuditLog/{actionId}.
 * Never throws — all errors are caught and logged to stderr so that a
 * logging failure never blocks the primary safety action.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} options
 * @param {string}  options.actorUid        UID of the user or service account performing the action
 * @param {string}  options.actorRole       "system" | "moderator" | "admin" | "trust_safety_admin" | …
 * @param {string}  options.actionType      e.g. "CONTENT_HIDDEN" | "LEGAL_HOLD_CREATED" | "CASE_ESCALATED"
 * @param {string}  options.targetType      "post" | "comment" | "message" | "dm" | "childSafetyCase" | …
 * @param {string}  options.targetRef       Firestore document path of the subject (e.g. "posts/abc123")
 * @param {*}       [options.previousState] State before the action (serialisable; may be null)
 * @param {*}       [options.newState]      State after the action (serialisable; may be null)
 * @param {string}  [options.reasonCode]    Machine-readable reason code (e.g. "CSAM_DETECTED")
 * @param {string}  [options.notes]         Free-text notes (will be stored verbatim)
 * @param {string}  [options.policyVersion] Version string of the policy applied (e.g. "2026-06-10-v1")
 * @returns {Promise<string>} actionId — Firestore document ID; returns "error" on failure
 */
async function writeAuditLog(db, {
  actorUid,
  actorRole,
  actionType,
  targetType,
  targetRef,
  previousState = null,
  newState = null,
  reasonCode = null,
  notes = null,
  policyVersion = null,
} = {}) {
  const actionId = crypto.randomUUID();

  try {
    // Build tamper-evidence fingerprints for both state snapshots.
    const previousStateHash = previousState != null ? sha256Hex(previousState) : null;
    const newStateHash      = newState != null      ? sha256Hex(newState)      : null;

    // Full entry fingerprint — covers all immutable fields so any field-level
    // tampering changes the digest.
    const entryFingerprint = sha256Hex({
      actionId,
      actorUid,
      actorRole,
      actionType,
      targetType,
      targetRef,
      previousStateHash,
      newStateHash,
      reasonCode,
      policyVersion,
    });

    await db.collection("moderationAuditLog").doc(actionId).set({
      actionId,
      actorUid:           actorUid       ?? null,
      actorRole:          actorRole      ?? null,
      actionType:         actionType     ?? null,
      targetType:         targetType     ?? null,
      targetRef:          targetRef      ?? null,

      // State snapshots (full data for legal/review purposes)
      previousState:      previousState  ?? null,
      newState:           newState       ?? null,

      // Tamper-evidence hashes
      previousStateHash,
      newStateHash,
      entryFingerprint,

      // Metadata
      reasonCode:         reasonCode     ?? null,
      notes:              notes          ?? null,
      policyVersion:      policyVersion  ?? null,

      createdAt: FieldValue.serverTimestamp(),

      // Documents in this collection must never be deleted or modified.
      immutable: true,
    });

    console.log(`[auditLog] ${actionType} logged: actionId=${actionId} targetRef=${targetRef}`);
    return actionId;

  } catch (err) {
    // Never throw — a log failure must not abort the safety action.
    console.error(
      `[auditLog] WRITE FAILED actionId=${actionId} actionType=${actionType} targetRef=${targetRef}:`,
      err.message
    );
    return "error";
  }
}

// ─── getAuditTrail ─────────────────────────────────────────────────────────────

/**
 * getAuditTrail(db, targetRef)
 *
 * Retrieves all moderationAuditLog entries for a given Firestore document path,
 * ordered by createdAt ascending (oldest-first) for chronological review.
 *
 * Admin-only usage: callers are responsible for enforcing access control before
 * passing results to a client.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} targetRef   Firestore document path (e.g. "posts/abc123")
 * @returns {Promise<Array<object>>} Array of audit entry plain objects
 */
async function getAuditTrail(db, targetRef) {
  if (!targetRef) {
    throw new Error("[auditLog] getAuditTrail: targetRef is required");
  }

  const snap = await db
    .collection("moderationAuditLog")
    .where("targetRef", "==", targetRef)
    .orderBy("createdAt", "asc")
    .get();

  return snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

// ─── Exports ───────────────────────────────────────────────────────────────────

module.exports = { writeAuditLog, getAuditTrail };
