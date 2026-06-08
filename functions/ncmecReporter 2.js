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
 * TODO — CyberTipline API integration (requires NCMEC Electronic Service Provider agreement):
 *   Endpoint: https://www.ncmec.org/cybertiplinedata/
 *   Auth: HTTPS Basic + ESP ID + API key issued by NCMEC after registration agreement
 *   Payload shape (ESP Report submission):
 *     {
 *       reportType: "Child Pornography (possession, manufacture, and distribution)",
 *       incidentDateTime: <ISO8601>,
 *       espName: "Amen",
 *       espUserId: <authorId>,
 *       espUserEmail: <if available>,
 *       reportedContent: [{ value: <url>, type: "url" }],
 *       additionalInfo: <detectedCategories joined>
 *     }
 *   Once credentials are obtained, replace the queue-only approach below with a
 *   live HTTPS POST to the above endpoint, and store the NCMEC report ID returned
 *   in the ncmecReports document alongside the local reportId.
 */

const functions = require("firebase-functions/v1");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getMessaging } = require("firebase-admin/messaging");

const db = getFirestore();

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
exports.onCSAMDetected = functions.region("us-central1").firestore
  .document("ncmecSubmissionQueue/{entryId}")
  .onCreate(async (snap, context) => {
    const queueEntryId = context.params.entryId;

    try {
      const entry = snap.data();
      if (!entry) {
        console.error("[NCMEC] onCSAMDetected: empty document — entryId:", queueEntryId);
        return null;
      }

      // Find all users with admin: true custom claim.
      // We store a mirror in users/{uid}.isAdmin so we can query without listing all Auth users.
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
                  aps: {
                    sound: "default",
                    "content-available": 1,
                  },
                },
                headers: {
                  "apns-priority": "10",
                },
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
  });

exports.fileNCMECReport = fileNCMECReport;

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
