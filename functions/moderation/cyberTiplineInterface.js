"use strict";

/**
 * cyberTiplineInterface.js
 *
 * Structured interface for NCMEC CyberTipline mandatory reporting.
 *
 * Legal context:
 *   18 U.S.C. § 2258A (PROTECT Our Children Act) requires any Electronic
 *   Service Provider (ESP) that detects apparent child sexual abuse material
 *   (CSAM) to file a report with the National Center for Missing & Exploited
 *   Children (NCMEC) CyberTipline.
 *
 *   Failure to report carries criminal penalties.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * !!! CRITICAL TODO — NCMEC CyberTipline API integration required here. !!!
 *
 * The submission stub in prepareCyberTiplineReport does NOT make a live HTTP
 * call to NCMEC. Before enabling automated submission:
 *
 *   1. Register as an Electronic Service Provider with NCMEC:
 *      https://www.missingkids.org/gethelpnow/cybertipline
 *
 *   2. Obtain an ESP ID and API key via the NCMEC ESP agreement.
 *
 *   3. Implement the HTTPS POST to the CyberTipline intake endpoint.
 *      Reference: NCMEC CyberTipline ESP Technical Specifications
 *      (available after ESP registration)
 *
 *   4. Store the NCMEC-issued report ID (confirmationId) in the case record
 *      by calling markReportSubmitted() after a successful submission.
 *
 *   5. Contact legal@yourcompany.com for compliance review and approval
 *      before enabling automated submission in production.
 *
 * DO NOT submit reports without legal/compliance review and approval.
 * Contact legal@yourcompany.com before enabling.
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * Exports:
 *   prepareCyberTiplineReport(db, caseId)      — build structured report object
 *   markReportSubmitted(db, caseId, confirmationId) — record submission result
 *   getPendingReports(db)                       — list cases awaiting submission
 */

const { FieldValue } = require("firebase-admin/firestore");

// ─── prepareCyberTiplineReport ────────────────────────────────────────────────

/**
 * prepareCyberTiplineReport(db, caseId)
 *
 * Reads the childSafetyEscalations case and the associated legalHold evidence
 * to build a structured report object in the shape expected by the NCMEC
 * CyberTipline ESP submission API.
 *
 * This function does NOT make any HTTP call to NCMEC.
 * See the TODO above for integration steps.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} caseId
 * @returns {Promise<object>} Structured report ready for human review and submission
 */
async function prepareCyberTiplineReport(db, caseId) {
  if (!caseId) throw new Error("[cyberTipline] caseId is required");

  // Load the escalation case.
  const caseSnap = await db.collection("childSafetyEscalations").doc(caseId).get();
  if (!caseSnap.exists) {
    throw new Error(`[cyberTipline] No childSafetyEscalation found for caseId=${caseId}`);
  }
  const escalation = caseSnap.data();

  // Load the legal-hold snapshot (contains the original content).
  let holdData = null;
  try {
    const holdSnap = await db.collection("legalHolds").doc(caseId).get();
    if (holdSnap.exists) holdData = holdSnap.data();
  } catch (err) {
    console.error(`[cyberTipline] Failed to load legalHold for caseId=${caseId}:`, err.message);
  }

  // Build the report object.
  // Shape follows the NCMEC CyberTipline ESP Report submission format.
  // Fields marked TODO must be populated once ESP credentials are available.
  const report = {
    // ── Case metadata ──────────────────────────────────────────────────────────
    internalCaseId:   caseId,
    reportType:       "Child Pornography (possession, manufacture, and distribution)",
    severity:         escalation.severity ?? "critical",
    status:           escalation.status ?? "new",

    // ── Incident details ───────────────────────────────────────────────────────
    incidentDateTime: holdData?.preservedAt?.toDate?.()?.toISOString?.()
                      ?? new Date().toISOString(),

    // ── ESP identification (populate after NCMEC registration) ────────────────
    espName:          "Amen",               // TODO: confirm legal entity name with legal
    espId:            "TODO_ESP_ID",        // TODO: issued by NCMEC after registration
    espApiKey:        "TODO_ESP_API_KEY",   // TODO: from Secret Manager, never hardcoded

    // ── Subject / uploader ────────────────────────────────────────────────────
    espUserId:        escalation.sourceUserId ?? null,
    espUserEmail:     null,                 // TODO: fetch from auth if legally permitted
    espUserIpAddress: null,                 // TODO: capture at upload time if legally permitted

    // ── Content references ────────────────────────────────────────────────────
    // NCMEC requires at minimum a URL or hash of the reported content.
    reportedContent: (escalation.evidenceRefs ?? []).map((ref) => ({
      value: ref,
      type: "firestore_ref",
      // TODO: replace with publicly-unreachable signed URL or file hash once
      //       Storage integration is in place.
    })),

    // ── Detection context ─────────────────────────────────────────────────────
    detectedCategories: escalation.type ? [escalation.type] : [],
    additionalInfo: [
      `Internal case type: ${escalation.type ?? "unknown"}`,
      `Source content ref: ${escalation.sourceContentRef ?? "unknown"}`,
      `Legal hold: ${escalation.legalHold ? "YES" : "NO"}`,
    ].join(" | "),

    // ── Submission state ───────────────────────────────────────────────────────
    submissionStatus: escalation.externalReport?.submitted ? "submitted" : "pending",
    confirmationId:   escalation.externalReport?.confirmationId ?? null,
    submittedAt:      escalation.externalReport?.submittedAt ?? null,

    // ── Legal/compliance gate ─────────────────────────────────────────────────
    legalReviewRequired: true,
    legalReviewNote: "DO NOT submit without legal/compliance approval. Contact legal@yourcompany.com.",

    preparedAt: new Date().toISOString(),
  };

  console.log(`[cyberTipline] Report prepared for caseId=${caseId} submissionStatus=${report.submissionStatus}`);
  return report;
}

// ─── markReportSubmitted ──────────────────────────────────────────────────────

/**
 * markReportSubmitted(db, caseId, confirmationId)
 *
 * Records that an NCMEC CyberTipline report has been successfully submitted.
 * Updates both the childSafetyEscalations case and the moderationAuditLog.
 *
 * Must only be called after receiving a valid NCMEC-issued confirmation ID.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} caseId
 * @param {string} confirmationId   NCMEC-issued report ID returned by the CyberTipline API
 * @returns {Promise<void>}
 */
async function markReportSubmitted(db, caseId, confirmationId) {
  if (!caseId)         throw new Error("[cyberTipline] markReportSubmitted: caseId is required");
  if (!confirmationId) throw new Error("[cyberTipline] markReportSubmitted: confirmationId is required");

  const submittedAt = FieldValue.serverTimestamp();

  await db.collection("childSafetyEscalations").doc(caseId).update({
    "externalReport.submitted":      true,
    "externalReport.submittedAt":    submittedAt,
    "externalReport.confirmationId": confirmationId,
    "status":                        "reported",
    "updatedAt":                     submittedAt,
  });

  // Append to audit log directly (avoids circular dependency with escalation.js).
  await db.collection("moderationAuditLog").add({
    actionType:    "NCMEC_REPORT_SUBMITTED",
    targetType:    "childSafetyCase",
    targetRef:     `childSafetyEscalations/${caseId}`,
    caseId,
    confirmationId,
    actorUid:      "system",
    actorRole:     "system",
    createdAt:     submittedAt,
    immutable:     true,
    policyVersion: "2026-06-10-v1",
  });

  console.log(`[cyberTipline] Report marked submitted: caseId=${caseId} confirmationId=${confirmationId}`);
}

// ─── getPendingReports ────────────────────────────────────────────────────────

/**
 * getPendingReports(db)
 *
 * Returns all childSafetyEscalation cases where the external NCMEC report
 * has not yet been submitted (externalReport.submitted !== true).
 *
 * Ordered by createdAt ascending so the oldest cases surface first.
 * Intended for use by human trust-and-safety operators and admin tooling.
 *
 * ADMIN-ONLY: callers must enforce access control before exposing results.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<Array<object>>} Array of pending case plain objects
 */
async function getPendingReports(db) {
  const snap = await db
    .collection("childSafetyEscalations")
    .where("externalReport.submitted", "==", false)
    .orderBy("createdAt", "asc")
    .get();

  const results = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  console.log(`[cyberTipline] getPendingReports: ${results.length} pending case(s)`);
  return results;
}

// ─── Exports ───────────────────────────────────────────────────────────────────

module.exports = { prepareCyberTiplineReport, markReportSubmitted, getPendingReports };
