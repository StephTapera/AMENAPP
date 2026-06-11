"use strict";

/**
 * moderation/escalation.js
 *
 * Legal-hold and NCMEC escalation for suspected CSAM content.
 *
 * Legal note:
 *   18 U.S.C. § 2258A requires ESPs that detect apparent CSAM to report to
 *   NCMEC. createLegalHold() creates the hold and queues the case;
 *   reportToNcmec() is a placeholder that MUST NOT be called in production
 *   until legal/compliance approves the NCMEC CyberTipline integration.
 *
 * Exports:
 *   createLegalHold(contentRef, authorUid, reporterUid, evidenceSnapshot)
 *   reportToNcmec(holdId, caseData)
 */

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

/**
 * createLegalHold(contentRef, authorUid, reporterUid, evidenceSnapshot)
 *
 * Immediately hides the content, creates an immutable legal-hold record, and
 * queues the case for critical human review.
 *
 * @param {string} contentRef       Firestore document path of the offending content
 * @param {string} authorUid        UID of the content author
 * @param {string} reporterUid      UID of the reporting user (or "system")
 * @param {object} evidenceSnapshot Plain-object snapshot of the content document
 * @returns {Promise<string>} holdId — Firestore document ID of the legalHolds entry
 */
async function createLegalHold(contentRef, authorUid, reporterUid, evidenceSnapshot) {
  if (!contentRef) throw new Error("[escalation] contentRef is required");
  if (!authorUid)  throw new Error("[escalation] authorUid is required");

  const db     = getFirestore();
  const holdId = crypto.randomUUID();
  const caseId = crypto.randomUUID();

  console.warn(
    `[escalation] LEGAL HOLD INITIATED holdId=${holdId} caseId=${caseId} ` +
    `contentRef=${contentRef} authorUid=${authorUid}`
  );

  // ── Step 1: Immediately hide the content ────────────────────────────────────
  try {
    await db.doc(contentRef).set(
      {
        visible:          false,
        "moderation.status": "escalated",
        hiddenReason:     "csam_suspected",
        hiddenAt:         FieldValue.serverTimestamp(),
        hiddenByHoldId:   holdId,
      },
      { merge: true }
    );
    console.log(`[escalation] Content hidden: contentRef=${contentRef}`);
  } catch (err) {
    // If hiding fails, still proceed — preserving evidence is more important.
    console.error(
      `[escalation] CRITICAL: failed to hide content contentRef=${contentRef}:`,
      err.message
    );
  }

  // ── Step 2: Create the legal-hold record ────────────────────────────────────
  await db.collection("legalHolds").doc(holdId).set({
    caseId,
    type:             "csam_suspected",
    sourceContentRef: contentRef,
    sourceUserId:     authorUid,
    reporterUserId:   reporterUid ?? "system",
    status:           "new",
    severity:         "critical",
    evidenceRefs:     [],
    legalHold:        true,
    externalReport: {
      required:       true,
      provider:       "NCMEC_CYBERTIPLINE_TODO",
      submitted:      false,
      submittedAt:    null,
      confirmationId: null,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  console.log(`[escalation] Legal hold created: holdId=${holdId}`);

  // ── Step 3: Write to escalationQueue for critical human review ──────────────
  await db.collection("escalationQueue").doc(caseId).set({
    caseId,
    holdId,
    priority:             "critical",
    requiresHumanReview:  true,
    createdAt:            FieldValue.serverTimestamp(),
    updatedAt:            FieldValue.serverTimestamp(),
  });

  console.warn(
    `[escalation] LEGAL HOLD COMPLETE holdId=${holdId} caseId=${caseId}`
  );

  return holdId;
}

/**
 * reportToNcmec(holdId, caseData)
 *
 * PLACEHOLDER — wires future NCMEC CyberTipline API integration.
 *
 * TODO(legal): Wire NCMEC CyberTipline API — https://www.missingkids.org/gethelpnow/cybertipline
 * This function must NOT be called in production until legal/compliance approves the integration.
 *
 * @param {string} holdId    ID of the legalHolds document
 * @param {object} caseData  Case payload for the CyberTipline submission
 * @returns {never} Always throws
 */
async function reportToNcmec(holdId, caseData) { // eslint-disable-line no-unused-vars
  // TODO(legal): Wire NCMEC CyberTipline API — https://www.missingkids.org/gethelpnow/cybertipline
  // This function must NOT be called in production until legal/compliance approves the integration.
  throw new Error(
    "NCMEC reporting not yet configured — requires compliance approval"
  );
}

module.exports = { createLegalHold, reportToNcmec };
