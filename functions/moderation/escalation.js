"use strict";

/**
 * escalation.js
 *
 * Child-safety escalation pipeline for the AMEN platform.
 *
 * When CSAM or child-exploitation content is detected (by automated pipelines
 * or human reviewers), this module:
 *
 *   1. Immediately hides the content from all users (visible: false).
 *   2. Creates an immutable legal-hold preserving the exact content snapshot.
 *   3. Opens a child-safety case in childSafetyEscalations/{caseId}.
 *   4. Writes a tamper-evident audit-log entry.
 *   5. Does NOT add the content to the normal moderationQueue — child-safety
 *      cases flow through a dedicated, legally isolated review path.
 *
 * Legal note:
 *   18 U.S.C. § 2258A requires ESPs that detect apparent CSAM to report to
 *   NCMEC. This module creates the case and legal hold; the NCMEC CyberTipline
 *   submission itself is performed manually via cyberTiplineInterface.js after
 *   legal/compliance review.
 *
 * Exports:
 *   escalateChildSafety(contentRef, authorId, reporterId, categories, snapshot)
 */

const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

const { createLegalHold }  = require("./legalHold");
const { writeAuditLog }    = require("./auditLog");

// ─── Category → case-type mapping ────────────────────────────────────────────

/**
 * deriveCaseType(categories)
 *
 * Maps an array of detected content-safety category strings to a canonical
 * child-safety case type string. Categories come from the moderation pipeline
 * (NeMo Guard, Vision LLM, etc.) and are normalised to lower-case.
 *
 * The most severe matching category wins.
 *
 * @param {string[]} categories
 * @returns {string}
 */
function deriveCaseType(categories) {
  const cats = (categories ?? []).map((c) => String(c).toLowerCase());

  if (cats.some((c) => c.includes("csam") || c.includes("child_sexual_abuse"))) {
    return "CSAM";
  }
  if (cats.some((c) => c.includes("child_exploitation") || c.includes("exploitation"))) {
    return "CHILD_EXPLOITATION";
  }
  if (cats.some((c) => c.includes("grooming"))) {
    return "CHILD_GROOMING";
  }
  if (cats.some((c) => c.includes("trafficking"))) {
    return "CHILD_TRAFFICKING";
  }
  if (cats.some((c) => c.includes("minor") || c.includes("child"))) {
    return "CHILD_SAFETY_OTHER";
  }
  // Default when specific categories are not identified.
  return "CHILD_SAFETY_UNCLASSIFIED";
}

// ─── escalateChildSafety ───────────────────────────────────────────────────────

/**
 * escalateChildSafety(db, contentRef, authorId, reporterId, categories, snapshot)
 *
 * Primary entry point for child-safety escalations.
 *
 * Steps (in order; all writes are sequential to guarantee ordering):
 *   1. Hide the content document immediately.
 *   2. Create a legal-hold record preserving the content snapshot.
 *   3. Create a child-safety case in childSafetyEscalations.
 *   4. Write to moderationAuditLog.
 *   NOTE: does NOT write to moderationQueue.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string}   contentRef   Firestore document path of the offending content
 *                                (e.g. "posts/abc123" or "messages/uid/dm/xyz")
 * @param {string}   authorId     UID of the content author
 * @param {string}   reporterId   UID of the reporting user, or "system" for automated detections
 * @param {string[]} categories   Detected content-safety categories from the moderation pipeline
 * @param {object}   snapshot     Plain-object copy of the content document at time of detection
 *                                (call .data() on the Firestore DocumentSnapshot before passing in)
 * @returns {Promise<string>} caseId — UUID of the new childSafetyEscalations document
 */
async function escalateChildSafety(db, contentRef, authorId, reporterId, categories, snapshot) {
  if (!db)          throw new Error("[escalation] db is required");
  if (!contentRef)  throw new Error("[escalation] contentRef is required");
  if (!authorId)    throw new Error("[escalation] authorId is required");

  const caseId    = crypto.randomUUID();
  const caseType  = deriveCaseType(categories);

  console.warn(
    `[escalation] CHILD SAFETY ESCALATION INITIATED caseId=${caseId} ` +
    `contentRef=${contentRef} authorId=${authorId} type=${caseType}`
  );

  // ── Step 1: Immediately hide the content ─────────────────────────────────────
  // Use merge:true so we only change the visibility fields, not the entire doc.
  try {
    await db.doc(contentRef).set(
      {
        visible:          false,
        hiddenReason:     "child_safety_escalation",
        hiddenAt:         FieldValue.serverTimestamp(),
        hiddenByCaseId:   caseId,
      },
      { merge: true }
    );
    console.log(`[escalation] Content hidden: contentRef=${contentRef}`);
  } catch (err) {
    // If hiding fails we still proceed — preserving evidence is more important.
    // Log as a critical error so the on-call team is alerted.
    console.error(
      `[escalation] CRITICAL: failed to hide content contentRef=${contentRef}:`,
      err.message
    );
  }

  // ── Step 2: Create legal hold ─────────────────────────────────────────────────
  await createLegalHold(db, contentRef, snapshot, caseId);

  // ── Step 3: Create child-safety case ─────────────────────────────────────────
  await db.collection("childSafetyEscalations").doc(caseId).set({
    caseId,
    type:             caseType,
    sourceContentRef: contentRef,
    sourceUserId:     authorId,
    reporterUserId:   reporterId ?? "system",
    status:           "new",
    severity:         "critical",
    evidenceRefs:     [contentRef],
    legalHold:        true,
    createdAt:        FieldValue.serverTimestamp(),
    updatedAt:        FieldValue.serverTimestamp(),

    // Notes are redacted by default; only legal/trust-safety staff may view.
    notesRedacted:    true,

    // External reporting to NCMEC CyberTipline.
    // The submission itself is performed manually via cyberTiplineInterface.js
    // after legal/compliance review — see that module for full instructions.
    externalReport: {
      required:       true,
      provider:       "NCMEC_CYBERTIPLINE_TODO",
      submitted:      false,
      submittedAt:    null,
      confirmationId: null,
    },
  });

  console.log(`[escalation] Case created: caseId=${caseId} type=${caseType}`);

  // ── Step 4: Write to moderation audit log ────────────────────────────────────
  // writeAuditLog never throws, so this will not abort the escalation flow.
  await writeAuditLog(db, {
    actorUid:      reporterId ?? "system",
    actorRole:     reporterId && reporterId !== "system" ? "reporter" : "system",
    actionType:    "CHILD_SAFETY_ESCALATION_CREATED",
    targetType:    "childSafetyCase",
    targetRef:     `childSafetyEscalations/${caseId}`,
    previousState: null,
    newState: {
      caseId,
      type:       caseType,
      contentRef,
      authorId,
      reporterId: reporterId ?? "system",
      status:     "new",
      severity:   "critical",
    },
    reasonCode:    "CHILD_SAFETY_CONTENT_DETECTED",
    notes:         `Categories: ${(categories ?? []).join(", ") || "unclassified"}`,
    policyVersion: "2026-06-10-v1",
  });

  // ── NOTE: intentionally NOT adding to moderationQueue ────────────────────────
  // Child-safety cases must flow through the dedicated childSafetyEscalations
  // review path only. Adding them to the general moderationQueue would expose
  // CSAM to reviewers who are not specifically trained and legally designated
  // for child-safety content.

  console.warn(
    `[escalation] CHILD SAFETY ESCALATION COMPLETE caseId=${caseId} ` +
    `contentRef=${contentRef} caseType=${caseType}`
  );

  return caseId;
}

// ─── Exports ───────────────────────────────────────────────────────────────────

module.exports = { escalateChildSafety };
