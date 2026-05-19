/**
 * reportFunctions.js
 * Trust Spine — Content Reports (Phase 1, System 35).
 *
 * Lightweight reporter-facing entrypoint. Writes to the existing /reports
 * collection (already locked to backend-only writes by firestore rules).
 *
 * Heavier moderation pipelines (contentModeration, aiModeration, evidenceVault,
 * NCMEC readiness) handle downstream enforcement — this function's only job is:
 *   1. Validate the report payload.
 *   2. Rate-limit the reporter.
 *   3. Persist a /reports/{reportId} document.
 *   4. Enqueue a moderation_queue task for human review.
 *
 * Callable: reportContent
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

const ALLOWED_TARGET_TYPES = new Set([
  "post",
  "comment",
  "media",
  "user",
  "message",
  "community",
  "provenance",
]);

const ALLOWED_REASONS = new Set([
  "spam",
  "harassment",
  "scam",
  "self_harm",
  "hate_speech",
  "violence",
  "sexual_content",
  "minor_safety",
  "misinformation",
  "synthetic_media",
  "ai_undisclosed",
  "intellectual_property",
  "other",
]);

exports.reportContent = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      // Rate-limit to deter mass-report brigading.
      await checkRateLimit(uid, "report_content", 30, 3600);

      const {targetType, targetId, reason, details} = request.data || {};

      if (!ALLOWED_TARGET_TYPES.has(targetType)) {
        throw new HttpsError("invalid-argument", "targetType invalid");
      }
      if (typeof targetId !== "string" || !targetId || targetId.length > 200) {
        throw new HttpsError("invalid-argument", "targetId required");
      }
      if (!ALLOWED_REASONS.has(reason)) {
        throw new HttpsError("invalid-argument", "reason invalid");
      }
      const sanitizedDetails = typeof details === "string"
        ? details.slice(0, 2000)
        : "";

      const reportRef = db().collection("reports").doc();
      const reportId = reportRef.id;
      const now = admin.firestore.FieldValue.serverTimestamp();

      const report = {
        reporterId: uid,           // matches existing rules: resource.data.reporterId
        targetType,
        targetId,
        reason,
        details: sanitizedDetails,
        status: "open",
        createdAt: now,
        updatedAt: now,
      };

      await reportRef.set(report);

      // Enqueue for human review. moderation_queue is admin-only by rules,
      // so this admin-SDK write is authoritative.
      await db().collection("moderation_queue").add({
        sourceReportId: reportId,
        reporterId: uid,
        targetType,
        targetId,
        reason,
        priority: priorityForReason(reason),
        status: "pending",
        createdAt: now,
      });

      return {reportId, status: "submitted"};
    },
);

function priorityForReason(reason) {
  switch (reason) {
    case "minor_safety":
    case "self_harm":
    case "violence":
      return "p0";
    case "harassment":
    case "scam":
    case "synthetic_media":
    case "sexual_content":
      return "p1";
    case "ai_undisclosed":
    case "hate_speech":
    case "misinformation":
      return "p2";
    default:
      return "p3";
  }
}
