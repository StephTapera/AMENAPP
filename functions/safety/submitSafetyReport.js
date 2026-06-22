"use strict";
// submitSafetyReport — the real backend for iOS report buttons.
// Auth + App Check + rate-limited. Writes to moderationQueue server-side.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const VALID_CATEGORIES = [
  "csam","child_safety","grooming","harassment","hate","spam","scam","self_harm","violence","other"
];
const MAX_REPORTS_PER_HOUR = 20;

exports.submitSafetyReport = onCall(
  { enforceAppCheck: true, region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
    const { contentRef, reportCategory, reportNotes } = request.data;

    if (!contentRef || typeof contentRef !== "string") {
      throw new HttpsError("invalid-argument", "contentRef required");
    }
    if (!VALID_CATEGORIES.includes(reportCategory)) {
      throw new HttpsError("invalid-argument", "Invalid category: " + reportCategory);
    }
    if (reportNotes && reportNotes.length > 500) {
      throw new HttpsError("invalid-argument", "reportNotes max 500 chars");
    }

    const db = getFirestore();
    const uid = request.auth.uid;

    // Rate limit: max MAX_REPORTS_PER_HOUR per user per hour
    const windowStart = Timestamp.fromMillis(Timestamp.now().toMillis() - 3600 * 1000);
    const recentSnap = await db.collection("moderationQueue")
      .where("reporterUid", "==", uid)
      .where("createdAt", ">", windowStart)
      .count().get();
    if (recentSnap.data().count >= MAX_REPORTS_PER_HOUR) {
      throw new HttpsError("resource-exhausted", "Report rate limit exceeded. Try again later.");
    }

    const batch = db.batch();
    const queueRef = db.collection("moderationQueue").doc();
    batch.set(queueRef, {
      contentRef,
      reportCategory,
      reportNotes: reportNotes || "",
      reporterUid: uid,
      status: "pending_review",
      createdAt: FieldValue.serverTimestamp(),
    });

    // Critical categories: also trigger escalation pipeline
    const isCritical = ["csam", "child_safety", "grooming"].includes(reportCategory);
    if (isCritical) {
      try {
        const { createLegalHold } = require("../moderation/escalation");
        await createLegalHold(contentRef, null, uid, {});
      } catch (escalationErr) {
        // Log but do not prevent the queue write
        console.error("[CRITICAL] Escalation failed for report " + queueRef.id, escalationErr);
      }
    }

    await batch.commit();
    return { success: true, reportId: queueRef.id };
  }
);
