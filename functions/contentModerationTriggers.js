/**
 * contentModerationTriggers.js
 *
 * Firebase Functions v2 Firestore triggers for server-side post moderation.
 * Kept in a separate file from contentModeration.js (gen1 callables) to avoid
 * the gen1/gen2 conflict that causes Firebase CLI to misapply CPU/concurrency settings.
 */

const admin = require("firebase-admin");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { moderatePostText } = require("./contentModeration");

const db = admin.firestore();

function writeModerationJob({ contentId, contentType, authorId, contentSnapshot = "", scores = {}, decision = {}, signals = [] }) {
  try {
    const jobId = `${contentType}_${contentId}_${Date.now()}`;
    const jobData = {
      content_id: contentId,
      content_type: contentType,
      author_id: authorId,
      toxicity_score: scores.toxicity ?? null,
      spam_score: scores.spam ?? null,
      ai_suspicion_score: scores.aiSuspicion ?? null,
      overall_risk_score: Math.max(scores.toxicity ?? 0, scores.spam ?? 0, scores.aiSuspicion ?? 0, scores.userRiskScore ?? 0),
      signals,
      decision: decision.action || "allow",
      decision_actor: "ai_automatic",
      decision_reason: (decision.reasons || []).join("; ") || null,
      decision_confidence: decision.confidence ?? null,
      zero_tolerance_violations: [],
      high_risk_violations: [],
      sensitive_categories: [],
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      completed_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    return db.collection("moderation_jobs").doc(jobId).set(jobData).then(() => jobId);
  } catch (err) {
    console.error("[writeModerationJob] Error:", err);
    return Promise.resolve(null);
  }
}

// ============================================================================
// SERVER-SIDE POST MODERATION TRIGGER (v2 Firestore onDocumentWritten)
// Runs moderation whenever a new post is created or its text changes.
// Bypasses client-side moderation for direct Firestore writes.
// ============================================================================

exports.serverSidePostModeration = onDocumentWritten(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const postId = event.params.postId;
    const afterData = event.data.after.data();

    if (!afterData) return null;
    if (afterData.serverModerated === true) return null;
    if (afterData.removed === true) return null;

    const userId = afterData.userId || afterData.authorId;
    const text = afterData.content || "";

    if (!text || text.length < 3) return null;

    console.log(`🛡️ [serverSidePostModeration] Running on post ${postId}`);

    try {
      const result = await moderatePostText(postId, userId, text);

      await writeModerationJob({
        contentId: postId,
        contentType: "post",
        authorId: userId,
        contentSnapshot: text.substring(0, 4000),
        scores: { toxicity: result.toxicityScore || 0, spam: result.spamScore || 0 },
        decision: { action: result.action, reasons: result.reasons, confidence: result.confidence || 0 },
        signals: result.reasons || [],
      });

      if (result.action === "remove") {
        await db.collection("posts").doc(postId).update({
          removed: true,
          moderationStatus: "rejected",
          moderationReasons: result.reasons,
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`🚫 [serverSidePostModeration] Post ${postId} removed`);
      } else if (result.action === "flag_for_review") {
        await db.collection("posts").doc(postId).update({
          flaggedForReview: true,
          moderationReasons: result.reasons,
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`⚠️ [serverSidePostModeration] Post ${postId} flagged`);
      } else {
        await db.collection("posts").doc(postId).update({
          serverModerated: true,
          serverModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (err) {
      console.error("[serverSidePostModeration] Error:", err);
    }

    return null;
  }
);
