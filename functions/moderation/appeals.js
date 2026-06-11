"use strict";

/**
 * moderation/appeals.js
 *
 * User-facing content appeal pipeline with moderator review gate.
 *
 * Exports:
 *   submitAppeal  — onCall: authenticated user submits an appeal for removed content
 *   decideAppeal  — onCall: moderator approves or denies an appeal
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { logModerationAction } = require("./auditLog");
const crypto = require("crypto");

// ─── submitAppeal ──────────────────────────────────────────────────────────────

/**
 * submitAppeal
 *
 * Callable: requires Auth + App Check.
 * Verifies the content belongs to the authenticated caller, then creates an
 * appeal document in the appeals collection with status:"submitted".
 *
 * Request data:
 *   contentRef   {string} Firestore document path (e.g. "posts/abc123")
 *   contentType  {string} "post" | "comment" | "prayer" | ...
 *   reason       {string} User-provided appeal reason (max 1000 chars)
 *   evidence     {string} [optional] Supporting evidence text (max 2000 chars)
 */
const submitAppeal = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  const { contentRef, contentType, reason, evidence } = request.data || {};

  if (!contentRef) {
    throw new HttpsError("invalid-argument", "contentRef is required.");
  }
  if (!reason || typeof reason !== "string" || reason.trim().length === 0) {
    throw new HttpsError("invalid-argument", "reason is required.");
  }
  if (reason.length > 1000) {
    throw new HttpsError("invalid-argument", "reason must be 1000 characters or fewer.");
  }
  if (evidence && evidence.length > 2000) {
    throw new HttpsError("invalid-argument", "evidence must be 2000 characters or fewer.");
  }

  const db = getFirestore();

  // Verify the content exists and belongs to the caller.
  let contentSnap;
  try {
    contentSnap = await db.doc(contentRef).get();
  } catch (err) {
    throw new HttpsError("invalid-argument", `Invalid contentRef: ${contentRef}`);
  }

  if (!contentSnap.exists) {
    throw new HttpsError("not-found", `Content not found: ${contentRef}`);
  }

  const contentData = contentSnap.data();
  const contentOwnerId = contentData.authorUID || contentData.authorId || contentData.uid;

  if (contentOwnerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You may only appeal content that belongs to your account."
    );
  }

  const appealId = crypto.randomUUID();

  await db.collection("appeals").doc(appealId).set({
    appealId,
    contentRef,
    contentType:    contentType ?? "unknown",
    authorUid:      uid,
    reason:         reason.trim(),
    evidence:       evidence ? evidence.trim() : null,
    status:         "submitted",
    reviewedAt:     null,
    reviewedBy:     null,
    reviewerNotes:  null,
    decision:       null,
    createdAt:      FieldValue.serverTimestamp(),
    updatedAt:      FieldValue.serverTimestamp(),
  });

  // Write audit log entry.
  await logModerationAction({
    actorUid:       uid,
    actorRole:      "user",
    actionType:     "appeal_submitted",
    targetType:     contentType ?? "unknown",
    targetRef:      contentRef,
    previousStatus: contentData.moderation?.status ?? null,
    newStatus:      "appeal_submitted",
    reasonCode:     "USER_APPEAL",
    notes:          `appealId=${appealId}`,
  }).catch((err) => {
    console.error("[appeals] auditLog write failed:", err.message);
  });

  console.log(
    `[appeals] Appeal submitted: appealId=${appealId} contentRef=${contentRef} uid=${uid}`
  );

  return { appealId, status: "submitted" };
});

// ─── decideAppeal ──────────────────────────────────────────────────────────────

/**
 * decideAppeal
 *
 * Callable: requires Auth + App Check + moderator custom claim.
 * Updates the appeal document with the moderator's decision.
 * If approved, re-checks the content document exists before restoring visible:true.
 *
 * Request data:
 *   appealId      {string} ID of the appeals document
 *   decision      {string} "approved" | "denied"
 *   reviewerNotes {string} [optional] Internal moderator notes
 */
const decideAppeal = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  // Require moderator custom claim.
  if (!request.auth.token || !request.auth.token.moderator) {
    throw new HttpsError(
      "permission-denied",
      "Moderator privileges are required to decide appeals."
    );
  }

  const moderatorUid = request.auth.uid;
  const { appealId, decision, reviewerNotes } = request.data || {};

  if (!appealId) {
    throw new HttpsError("invalid-argument", "appealId is required.");
  }
  if (decision !== "approved" && decision !== "denied") {
    throw new HttpsError(
      "invalid-argument",
      'decision must be "approved" or "denied".'
    );
  }

  const db = getFirestore();

  // Load the appeal.
  const appealSnap = await db.collection("appeals").doc(appealId).get();
  if (!appealSnap.exists) {
    throw new HttpsError("not-found", `Appeal not found: ${appealId}`);
  }

  const appeal = appealSnap.data();

  if (appeal.status !== "submitted") {
    throw new HttpsError(
      "failed-precondition",
      `Appeal ${appealId} is already in status "${appeal.status}" and cannot be decided again.`
    );
  }

  const newAppealStatus = decision === "approved" ? "approved" : "denied";
  const actionType      = decision === "approved" ? "appeal_approved" : "appeal_denied";

  // Update the appeal document.
  await db.collection("appeals").doc(appealId).update({
    status:        newAppealStatus,
    decision,
    reviewedAt:    FieldValue.serverTimestamp(),
    reviewedBy:    moderatorUid,
    reviewerNotes: reviewerNotes ? reviewerNotes.trim() : null,
    updatedAt:     FieldValue.serverTimestamp(),
  });

  // If approved, re-verify the content document still exists before restoring visibility.
  if (decision === "approved") {
    let contentSnap;
    try {
      contentSnap = await db.doc(appeal.contentRef).get();
    } catch (err) {
      console.error(
        `[appeals] Could not read contentRef ${appeal.contentRef} for approval:`,
        err.message
      );
      contentSnap = null;
    }

    if (contentSnap && contentSnap.exists) {
      await db.doc(appeal.contentRef).set(
        {
          visible:             true,
          "moderation.status": "appeal_approved",
          appealRestoredAt:    FieldValue.serverTimestamp(),
          appealRestoredBy:    moderatorUid,
        },
        { merge: true }
      );
      console.log(
        `[appeals] Content restored: contentRef=${appeal.contentRef} appealId=${appealId}`
      );
    } else {
      console.warn(
        `[appeals] Content not found for restoration: contentRef=${appeal.contentRef} appealId=${appealId}`
      );
    }
  }

  // Write audit log entry.
  await logModerationAction({
    actorUid:       moderatorUid,
    actorRole:      "moderator",
    actionType,
    targetType:     appeal.contentType ?? "unknown",
    targetRef:      appeal.contentRef,
    previousStatus: "appeal_submitted",
    newStatus:      newAppealStatus,
    reasonCode:     decision === "approved" ? "APPEAL_UPHELD" : "APPEAL_REJECTED",
    notes:          `appealId=${appealId}` + (reviewerNotes ? ` notes=${reviewerNotes.trim()}` : ""),
  }).catch((err) => {
    console.error("[appeals] auditLog write failed:", err.message);
  });

  console.log(
    `[appeals] Appeal decided: appealId=${appealId} decision=${decision} moderatorUid=${moderatorUid}`
  );

  return { appealId, decision, status: newAppealStatus };
});

module.exports = { submitAppeal, decideAppeal };
