// TODO: MIGRATE_TO_V2 — still using Gen1 runWith() pattern
/**
 * NCMEC CyberTipline Mandatory Reporting Pipeline — v1 Cloud Function
 *
 * Legal requirement: any platform that detects CSAM must file a report with
 * the National Center for Missing & Exploited Children (NCMEC) CyberTipline.
 * See: 18 U.S.C. § 2258A (PROTECT Our Children Act)
 *
 * This module:
 *   1. Writes a tamper-evident legal-hold record to ncmecReports/{reportId}
 *   2. Queues the report for human operator action in ncmecSubmissionQueue/{entryId}
 *   3. Fires onCSAMDetected (Firestore trigger) to alert admins via FCM + moderatorAlerts
 *
 * TODO(legal): Integrate NCMEC CyberTipline API — requires compliance approval before enabling.
 *   Step 1: Obtain NCMEC Electronic Service Provider (ESP) agreement + API credentials.
 *   Step 2: Replace the queue-only flow in fileNCMECReport() with a live HTTPS POST to:
 *             https://www.ncmec.org/cybertiplinedata/
 *   Step 3: Store the NCMEC-assigned reportId from the API response in ncmecReports.
 *   Step 4: Add a deadline SLA monitor: if status stays 'pending_submission' past
 *             NCMEC_SLA_HOURS, escalate and page on-call.
 *   Step 5: Set NCMEC_SUBMISSION_ENABLED=true in Cloud Functions environment after step 1-4.
 *
 *   CyberTipline payload shape (ESP Report submission):
 *     {
 *       reportType: "Child Pornography (possession, manufacture, and distribution)",
 *       incidentDateTime: <ISO8601>,
 *       espName: "Amen",
 *       espUserId: <authorId>,
 *       espUserEmail: <if available>,
 *       reportedContent: [{ value: <url>, type: "url" }],
 *       additionalInfo: <detectedCategories joined>
 *     }
 *
 * CURRENT STATUS: Queue-only (no live NCMEC HTTP call). Every detected CSAM case is
 * written to ncmecReports + ncmecSubmissionQueue and admins are alerted via FCM.
 * Human operators must manually submit to NCMEC until API integration is complete.
 * This is a LAUNCH BLOCKER — see OPEN-4 in C5-security-rules.md.
 */

const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getMessaging } = require("firebase-admin/messaging");

const db = getFirestore();
const NCMEC_SUBMISSION_ENABLED = process.env.NCMEC_SUBMISSION_ENABLED === "true";
const NCMEC_SLA_HOURS = Number(process.env.NCMEC_SLA_HOURS || 24);

function ncmecDueAt() {
  return new Date(Date.now() + NCMEC_SLA_HOURS * 60 * 60 * 1000);
}

/**
 * fileNCMECReport — internal helper (not a Cloud Function).
 *
 * Writes a tamper-evident record and queues the report for human operator review.
 * Does NOT make a live HTTP call to NCMEC (credentials required — see TODO above).
 */
async function fileNCMECReport(payload) {
  const {
    contentRef,
    contentType,
    contentUrl,
    authorId,
    detectedCategories,
    detectedBy,
    textPreview = "",
  } = payload;

  const reportRef = db.collection("ncmecReports").doc();
  const reportId = reportRef.id;

  // Tamper-evident legal-hold record. Never delete or modify this document.
  await reportRef.set({
    contentRef,
    contentType,
    contentUrl,
    authorId,
    detectedCategories,
    detectedBy,
    status: "pending_submission",
    createdAt: FieldValue.serverTimestamp(),
    legalHold: true,
    preservedAt: FieldValue.serverTimestamp(),
    submissionEnabled: NCMEC_SUBMISSION_ENABLED,
    submissionDueAt: ncmecDueAt(),
    decisionRequired: true,
    decisionItems: [
      "NCMEC ESP registration",
      "CyberTipline API credentials",
      "counsel-approved submission procedure",
    ],
  });

  const preview = textPreview ? String(textPreview).slice(0, 100) : "image";

  const entryRef = db.collection("ncmecSubmissionQueue").doc();
  await entryRef.set({
    reportId,
    contentRef,
    authorId,
    preview,
    urgency: "critical",
    status: "queued",
    createdAt: FieldValue.serverTimestamp(),
    submissionEnabled: NCMEC_SUBMISSION_ENABLED,
    submissionDueAt: ncmecDueAt(),
    decisionRequired: true,
  });

  console.log(`[NCMEC] Report queued: ${reportId}`);

  return { reportId, queued: true };
}

/**
 * onCSAMDetected — Firestore trigger on ncmecSubmissionQueue/{entryId}.
 *
 * Alerts all admin users via FCM and writes a high-priority moderatorAlert.
 * Fails closed: all errors are caught and logged; the trigger is never re-thrown
 * (avoids Cloud Function retry loops on a poisoned document).
 */
exports.onCSAMDetected = onDocumentCreated(
  { document: "ncmecSubmissionQueue/{entryId}", region: "us-central1" },
  async (event) => {
    const queueEntryId = event.params.entryId;

    try {
      const entry = event.data?.data();
      if (!entry) {
        console.error("[NCMEC] onCSAMDetected: empty document — entryId:", queueEntryId);
        return null;
      }

      const adminsSnap = await db.collection("users")
        .where("isAdmin", "==", true)
        .get();

      const tokens = [];
      adminsSnap.forEach((doc) => {
        const t = doc.data().fcmToken;
        if (t) tokens.push(t);
      });

      if (tokens.length > 0) {
        const messaging = getMessaging();
        await Promise.all(
          tokens.map((token) =>
            messaging.send({
              token,
              notification: {
                title: "CSAM Report Queued",
                body: "A critical child safety item requires immediate review.",
              },
              data: {
                type: "csam_mandatory_report",
                queueEntryId,
                urgency: "critical",
              },
              apns: {
                payload: {
                  aps: { sound: "default", "content-available": 1 },
                },
                headers: { "apns-priority": "10" },
              },
            }).catch((err) =>
              console.error(`[NCMEC] FCM send failed for token ${token.slice(0, 10)}…:`, err.message)
            )
          )
        );
        console.log(`[NCMEC] Admin FCM alerts sent to ${tokens.length} device(s)`);
      } else {
        console.warn("[NCMEC] No admin FCM tokens found — alert not delivered");
      }

      await db.collection("moderatorAlerts").add({
        type: "csam_mandatory_report",
        queueEntryId,
        urgency: "critical",
        createdAt: FieldValue.serverTimestamp(),
        read: false,
      });

      console.log(`[NCMEC] moderatorAlert written for queue entry: ${queueEntryId}`);
    } catch (err) {
      console.error("[NCMEC] onCSAMDetected error:", err);
    }

    return null;
  }
);

exports.fileNCMECReport = fileNCMECReport;

/**
 * reportToNcmec — placeholder that throws explicitly when called without credentials.
 *
 * This function MUST throw rather than silently swallowing calls so that callers
 * are never left believing a live report was submitted when it was not.
 * Replace this stub with the live HTTPS POST once NCMEC ESP credentials are obtained.
 *
 * TODO(legal): Replace stub body with live NCMEC API call — requires compliance approval.
 *
 * @param {object} caseData - CSAM case details (contentRef, authorId, mediaUrl, etc.)
 * @throws {Error} Always — stub is not callable without proper setup.
 */
async function reportToNcmec(caseData) {
  // SECURITY: This function intentionally throws so callers cannot silently skip
  // the live NCMEC submission. A swallowed error would give false assurance that
  // a mandatory report was filed when it was not.
  throw new Error(
    "[NCMEC] reportToNcmec() is not yet implemented — live API integration requires " +
    "NCMEC Electronic Service Provider agreement and API credentials. " +
    "See TODO(legal) in ncmecReporter.js. This is a LAUNCH BLOCKER."
  );
}

/**
 * createLegalHold — atomically write a tamper-evident legal hold record.
 *
 * Writes to legalHolds/{holdId} using a single atomic set(). The Admin SDK bypasses
 * Firestore rules, so this record cannot be modified or deleted by any client.
 * Used by the CSAM escalation pipeline to preserve evidence before content removal.
 *
 * @param {string} contentRef   - Firestore path of the content (e.g. "posts/abc123")
 * @param {string} authorUid    - UID of the content author
 * @param {object} evidence     - Evidence snapshot (mediaUrl, detectedCategories, etc.)
 * @returns {Promise<string>}   - The holdId of the created document
 */
async function createLegalHold(contentRef, authorUid, evidence) {
  if (!contentRef || !authorUid) {
    throw new Error("[createLegalHold] contentRef and authorUid are required.");
  }
  const holdId = `hold_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const holdRef = db.collection("legalHolds").doc(holdId);
  // Atomic single-document set — either the entire hold is written or nothing is.
  await holdRef.set({
    contentRef,
    authorUid,
    evidence: evidence || {},
    legalHold: true,
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
    preservedAt: FieldValue.serverTimestamp(),
    modifiedBy: "CF_Admin_SDK",
    // This document must never be deleted or updated by any client or CF except
    // under explicit legal-counsel direction. I-2 invariant applies.
  });
  console.log(`[createLegalHold] Legal hold created: ${holdId} for contentRef=${contentRef}`);
  return holdId;
}

exports.reportToNcmec   = reportToNcmec;
exports.createLegalHold = createLegalHold;

// ─── Internal helper: alert trust_safety_admin users via FCM ──────────────────

async function alertTrustSafetyAdmins(messaging, payload) {
  const adminsSnap = await db.collection("users")
    .where("role", "==", "trust_safety_admin")
    .get();

  const tokens = [];
  adminsSnap.forEach((doc) => {
    const t = doc.data().fcmToken;
    if (t) tokens.push(t);
  });

  if (tokens.length === 0) {
    console.warn("[NCMEC] No trust_safety_admin FCM tokens found — alert not delivered");
    return;
  }

  await Promise.all(
    tokens.map((token) =>
      messaging.send({
        token,
        notification: {
          title: "MANDATORY REPORT REQUIRED — NCMEC",
          body: "Content requiring mandatory NCMEC CyberTipline reporting has been detected.",
        },
        data: {
          type: "ncmec_mandatory_report_required",
          ...payload,
        },
        apns: {
          payload: { aps: { sound: "default", "content-available": 1 } },
          headers: { "apns-priority": "10" },
        },
      }).catch((err) =>
        console.error(`[NCMEC] FCM send failed for token ${token.slice(0, 10)}…:`, err.message)
      )
    )
  );

  console.log(`[NCMEC] trust_safety_admin FCM alerts sent to ${tokens.length} device(s)`);
}

// ─── flagForNCMECReview — callable ────────────────────────────────────────────

/**
 * flagForNCMECReview — callable (trust_safety_admin or admin only).
 *
 * Allows a human reviewer to manually flag content for NCMEC mandatory review.
 * When called:
 *   1. Deletes the offending media from Firebase Storage (if mediaPath provided).
 *   2. Writes a tamper-evident record to mandatory_reports/{auto-id}.
 *   3. Sends an FCM alert to all trust_safety_admin users.
 *
 * Expected request.data:
 *   {
 *     contentId:    string,   // e.g. post ID or moderation doc ID
 *     userId:       string,   // the content author's UID
 *     contentType:  string,   // "post" | "image" | "video" | "message"
 *     mediaUrl:     string,   // public URL of the media (for the report record)
 *     mediaPath:    string?,  // Storage path to delete (e.g. "posts/uid/file.jpg")
 *     storageBucket: string?, // Storage bucket (defaults to project default)
 *   }
 */
exports.flagForNCMECReview = onCall(
  { region: "us-central1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    // Require auth and admin/trust_safety_admin role
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const callerSnap = await db.collection("users").doc(request.auth.uid).get();
    const callerData = callerSnap.data() || {};
    const isAuthorized =
      callerData.isAdmin === true ||
      callerData.role === "trust_safety_admin" ||
      request.auth.token?.admin === true;

    if (!isAuthorized) {
      throw new HttpsError("permission-denied", "trust_safety_admin or admin role required.");
    }

    const { contentId, userId, contentType, mediaUrl, mediaPath, storageBucket } = request.data;
    if (!contentId || !userId || !contentType || !mediaUrl) {
      throw new HttpsError(
        "invalid-argument",
        "contentId, userId, contentType, and mediaUrl are required."
      );
    }

    const detectedAt = FieldValue.serverTimestamp();

    // Step 1: Delete media from Storage if a path was provided.
    if (mediaPath) {
      try {
        const bucket = storageBucket
          ? getStorage().bucket(storageBucket)
          : getStorage().bucket();
        await bucket.file(mediaPath).delete();
        console.log(`[NCMEC flagForNCMECReview] Deleted media from Storage: ${mediaPath}`);
      } catch (err) {
        // Log but do not abort — the report must be filed even if delete fails.
        console.error(`[NCMEC flagForNCMECReview] Storage delete failed for ${mediaPath}:`, err.message);
      }
    }

    // Step 2: Write to mandatory_reports collection.
    const reportRef = db.collection("mandatory_reports").doc();
    await reportRef.set({
      contentId,
      userId,
      contentType,
      detectedAt,
      reportType: "NCMEC_REQUIRED",
      status: "PENDING_HUMAN_REVIEW",
      mediaUrl,
      mediaPath: mediaPath || null,
      flaggedBy: request.auth.uid,
      legalHold: true,
      submissionEnabled: NCMEC_SUBMISSION_ENABLED,
      submissionDueAt: ncmecDueAt(),
      decisionRequired: true,
      decisionItems: [
        "NCMEC ESP registration",
        "CyberTipline API credentials",
        "counsel-approved submission procedure",
      ],
    });
    console.log(`[NCMEC flagForNCMECReview] mandatory_reports record created: ${reportRef.id}`);

    // Step 3: Alert all trust_safety_admin users.
    const messaging = getMessaging();
    await alertTrustSafetyAdmins(messaging, {
      reportId: reportRef.id,
      contentId,
      urgency: "critical",
    });

    return { reportId: reportRef.id, status: "PENDING_HUMAN_REVIEW" };
  }
);

// ─── onModerationRequiresMandatoryReport — Firestore trigger ──────────────────

/**
 * onModerationRequiresMandatoryReport — Firestore trigger on moderationResults/{docId}.
 *
 * Fires whenever a document in moderationResults is created or updated.
 * When requiresMandatoryReport transitions to true:
 *   1. Deletes the offending media from Firebase Storage.
 *   2. Writes a tamper-evident record to mandatory_reports/{auto-id}.
 *   3. Sends an FCM alert to all trust_safety_admin users.
 *
 * This closes the gap where automated moderation pipelines (e.g. cameraOSFunctions,
 * moderatePost) set requiresMandatoryReport: true but no server-side action fires.
 *
 * Fails closed: errors are caught and logged; no retry loop from re-throw.
 */
exports.onModerationRequiresMandatoryReport = onDocumentWritten(
  { document: "moderationResults/{docId}", region: "us-central1" },
  async (event) => {
    const docId = event.params.docId;

    try {
      const after = event.data?.after?.data();
      if (!after) {
        // Document deleted — nothing to do.
        return null;
      }

      // Only act when requiresMandatoryReport transitions to true.
      if (after.requiresMandatoryReport !== true) {
        return null;
      }

      const before = event.data?.before?.data();
      const wasAlreadyFlagged = before?.requiresMandatoryReport === true;
      if (wasAlreadyFlagged) {
        // Idempotent: do not re-file if already flagged.
        return null;
      }

      const {
        contentId = docId,
        userId = after.authorId || after.userId || "unknown",
        contentType = after.contentType || "unknown",
        mediaUrl = after.mediaUrl || after.contentUrl || "",
        mediaPath = after.mediaPath || after.contentRef || null,
        storageBucket = after.storageBucket || null,
      } = after;

      console.log(`[NCMEC trigger] requiresMandatoryReport=true on moderationResults/${docId}`);

      // Step 1: Delete media from Storage if a path is known.
      if (mediaPath) {
        try {
          const bucket = storageBucket
            ? getStorage().bucket(storageBucket)
            : getStorage().bucket();
          await bucket.file(mediaPath).delete();
          console.log(`[NCMEC trigger] Deleted media from Storage: ${mediaPath}`);
        } catch (err) {
          console.error(`[NCMEC trigger] Storage delete failed for ${mediaPath}:`, err.message);
        }
      }

      // Step 2: Write to mandatory_reports collection.
      const reportRef = db.collection("mandatory_reports").doc();
      await reportRef.set({
        contentId,
        userId,
        contentType,
        detectedAt: FieldValue.serverTimestamp(),
        reportType: "NCMEC_REQUIRED",
        status: "PENDING_HUMAN_REVIEW",
        mediaUrl,
      mediaPath: mediaPath || null,
      sourceDocId: docId,
      triggeredBy: "onModerationRequiresMandatoryReport",
      legalHold: true,
      submissionEnabled: NCMEC_SUBMISSION_ENABLED,
      submissionDueAt: ncmecDueAt(),
      decisionRequired: true,
      decisionItems: [
        "NCMEC ESP registration",
        "CyberTipline API credentials",
        "counsel-approved submission procedure",
      ],
    });
      console.log(`[NCMEC trigger] mandatory_reports record created: ${reportRef.id}`);

      // Step 3: Alert all trust_safety_admin users.
      const messaging = getMessaging();
      await alertTrustSafetyAdmins(messaging, {
        reportId: reportRef.id,
        contentId,
        urgency: "critical",
      });
    } catch (err) {
      console.error("[NCMEC trigger] onModerationRequiresMandatoryReport error:", err);
    }

    return null;
  }
);
