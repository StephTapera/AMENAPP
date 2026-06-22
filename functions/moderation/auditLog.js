"use strict";

/**
 * moderation/auditLog.js
 *
 * Structured audit log for moderation actions on the AMEN platform.
 *
 * Every write is immutable: documents are never updated, only appended.
 *
 * Exports:
 *   logModerationAction(options)
 */

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

const VALID_ACTION_TYPES = new Set([
  "approve",
  "block",
  "remove",
  "escalate",
  "appeal_submitted",
  "appeal_approved",
  "appeal_denied",
  "role_changed",
  "account_suspended",
]);

/**
 * logModerationAction(options)
 *
 * Validates the actionType and appends one immutable entry to the
 * moderationAuditLog collection.
 *
 * @param {object} options
 * @param {string}  options.actorUid       UID of the user or service performing the action
 * @param {string}  options.actorRole      e.g. "moderator" | "admin" | "system"
 * @param {string}  options.actionType     One of the VALID_ACTION_TYPES above
 * @param {string}  options.targetType     "post" | "comment" | "message" | "dm" | "account" | ...
 * @param {string}  options.targetRef      Firestore document path of the subject
 * @param {string}  [options.previousStatus] Status before the action
 * @param {string}  [options.newStatus]    Status after the action
 * @param {string}  [options.reasonCode]   Machine-readable reason code
 * @param {string}  [options.notes]        Free-text notes
 * @returns {Promise<string>} The log document ID
 * @throws {Error} If actionType is not in the valid set
 */
async function logModerationAction({
  actorUid,
  actorRole,
  actionType,
  targetType,
  targetRef,
  previousStatus = null,
  newStatus = null,
  reasonCode = null,
  notes = null,
} = {}) {
  if (!VALID_ACTION_TYPES.has(actionType)) {
    throw new Error(
      `[auditLog] Invalid actionType "${actionType}". ` +
      `Must be one of: ${[...VALID_ACTION_TYPES].join(", ")}`
    );
  }

  const db       = getFirestore();
  const logId    = crypto.randomUUID();

  await db.collection("moderationAuditLog").doc(logId).set({
    logId,
    actorUid:       actorUid       ?? null,
    actorRole:      actorRole      ?? null,
    actionType,
    targetType:     targetType     ?? null,
    targetRef:      targetRef      ?? null,
    previousStatus: previousStatus ?? null,
    newStatus:      newStatus      ?? null,
    reasonCode:     reasonCode     ?? null,
    notes:          notes          ?? null,
    createdAt:      FieldValue.serverTimestamp(),
    // Documents in this collection must never be deleted or modified.
    immutable:      true,
  });

  console.log(
    `[auditLog] ${actionType} logged: logId=${logId} targetRef=${targetRef} actorUid=${actorUid}`
  );

  return logId;
}

module.exports = { logModerationAction };
