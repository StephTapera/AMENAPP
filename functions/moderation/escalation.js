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
 *   escalateChildSafety(db, contentRef, authorUid, reporterUid, categories, evidenceSnapshot)
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
      provider:       "NCMEC_CYBERTIPLINE",
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
 * TODO(gate: DECISION) — legal: Wire NCMEC CyberTipline API — https://www.missingkids.org/gethelpnow/cybertipline
 * This function must NOT be called in production until legal/compliance approves the integration.
 *
 * @param {string} holdId    ID of the legalHolds document
 * @param {object} caseData  Case payload for the CyberTipline submission
 * @returns {never} Always throws
 */
async function reportToNcmec(holdId, caseData) { // eslint-disable-line no-unused-vars
  // TODO(gate: DECISION) — legal: Wire NCMEC CyberTipline API — https://www.missingkids.org/gethelpnow/cybertipline
  // This function must NOT be called in production until legal/compliance approves the integration.
  throw new Error(
    "NCMEC reporting not yet configured — requires compliance approval"
  );
}

/**
 * escalateChildSafety
 *
 * User-report vector entry-point for child-safety escalation.
 * Called by blockMuteReport.reportContent() when a report category matches
 * CHILD_SAFETY_CATEGORIES.  Immediately hides the content, creates a
 * legalHolds record, a childSafetyEscalations record, and queues for
 * critical human review — identical guarantees to the system-detection path.
 *
 * Signature matches the call-site in blockMuteReport.js:
 *   escalateChildSafety(db, contentRef, authorUid, reporterUid, categories, evidenceSnapshot)
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string}   contentRef       Firestore document path of the offending content
 * @param {string}   authorUid        UID of the content author (may be null if unknown)
 * @param {string}   reporterUid      UID of the reporting user
 * @param {string[]} categories       Array of matched child-safety category strings
 * @param {object}   evidenceSnapshot Plain-object snapshot of the content document
 * @returns {Promise<string>} holdId
 */
async function escalateChildSafety(db, contentRef, authorUid, reporterUid, categories, evidenceSnapshot) {
  if (!db)         throw new Error("[escalation] db is required");
  if (!contentRef) throw new Error("[escalation] contentRef is required");

  const holdId = crypto.randomUUID();
  const caseId = crypto.randomUUID();

  console.warn(
    `[escalation] CHILD SAFETY ESCALATION (user-report) holdId=${holdId} caseId=${caseId} ` +
    `contentRef=${contentRef} authorUid=${authorUid} reporterUid=${reporterUid} ` +
    `categories=${(categories || []).join(",")}`
  );

  const batch = db.batch();

  // ── Step 1: Immediately hide the content ──────────────────────────────────
  try {
    batch.set(
      db.doc(contentRef),
      {
        visible:                     false,
        flaggedForReview:            true,
        hiddenReason:                "csam_suspected",
        hiddenAt:                    FieldValue.serverTimestamp(),
        hiddenByHoldId:              holdId,
        "moderation.status":         "escalated",
        "moderation.childSafetyEscalated": true,
        "moderation.categories":     categories || [],
      },
      { merge: true }
    );
  } catch (err) {
    // If the batch.set itself throws (e.g. invalid path), log and continue so
    // evidence is still preserved in the hold and escalation records.
    console.error(
      `[escalation] CRITICAL: failed to queue content hide for contentRef=${contentRef}:`,
      err.message
    );
  }

  // ── Step 2: Create the legal-hold record ──────────────────────────────────
  batch.set(db.collection("legalHolds").doc(holdId), {
    caseId,
    type:             "csam_suspected",
    sourceContentRef: contentRef,
    sourceUserId:     authorUid ?? null,
    reporterUserId:   reporterUid ?? "user",
    categories:       categories || [],
    postSnapshot:     evidenceSnapshot || {},
    status:           "new",
    severity:         "critical",
    legalHold:        true,
    externalReport: {
      required:       true,
      provider:       "NCMEC_CYBERTIPLINE",
      submitted:      false,
      submittedAt:    null,
      confirmationId: null,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  // ── Step 3: childSafetyEscalations record ─────────────────────────────────
  const escRef = db.collection("childSafetyEscalations").doc(caseId);
  batch.set(escRef, {
    caseId,
    holdId,
    contentRef,
    authorUid:   authorUid ?? null,
    reporterUid: reporterUid ?? "user",
    categories:  categories || [],
    status:      "new",
    severity:    "critical",
    legalHold:   true,
    legalHoldRef: `legalHolds/${holdId}`,
    externalReport: {
      required:  true,
      provider:  "NCMEC_CYBERTIPLINE",
      submitted: false,
    },
    createdAt: FieldValue.serverTimestamp(),
  });

  // ── Step 4: Escalation queue for critical human review ────────────────────
  batch.set(db.collection("escalationQueue").doc(caseId), {
    caseId,
    holdId,
    priority:            "critical",
    requiresHumanReview: true,
    createdAt:           FieldValue.serverTimestamp(),
    updatedAt:           FieldValue.serverTimestamp(),
  });

  await batch.commit();

  console.warn(
    `[escalation] CHILD SAFETY ESCALATION COMPLETE holdId=${holdId} caseId=${caseId}`
  );

  return holdId;
}

module.exports = { createLegalHold, escalateChildSafety, reportToNcmec };
