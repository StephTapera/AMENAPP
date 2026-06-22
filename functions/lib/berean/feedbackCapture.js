"use strict";
/**
 * berean/feedbackCapture.ts — Berean Trust Architecture · Layer 4 · Human Feedback Loop
 *
 * Captures in-app ratings on Berean AI responses, maintains a denormalized audit
 * trail on pipeline traces, and auto-queues high-priority guardian review for
 * safety-critical ratings ('unsafe' | 'misleading').
 *
 * Firestore layout:
 *   bereanFeedback/{feedbackId}                              — primary feedback records
 *   bereanPipelineTraces/{traceId}/feedback/{feedbackId}     — denormalized audit copy
 *   guardianReviewQueue/{reviewId}                           — escalated items
 *
 * Feature flag gate: featureFlags/trustArchitecture → field "feedbackCapture" === true
 *
 * SECURITY: submitFeedback receives a userId that the HTTP callable wrapper has
 * already validated against request.auth.uid before calling into this module.
 * Never call this function with an unverified userId.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.submitFeedback = submitFeedback;
exports.getFeedbackStats = getFeedbackStats;
const FirebaseFirestore = __importStar(require("@google-cloud/firestore"));
/** Ratings that require immediate guardian escalation. */
const HIGH_PRIORITY_RATINGS = new Set([
    "unsafe",
    "misleading",
]);
// ---------------------------------------------------------------------------
// Feature flag helper
// ---------------------------------------------------------------------------
async function isFeedbackCaptureEnabled(db) {
    try {
        const flagDoc = await db.doc("featureFlags/trustArchitecture").get();
        if (!flagDoc.exists)
            return false;
        const data = flagDoc.data();
        return data?.feedbackCapture === true;
    }
    catch {
        // Fail open: if we cannot read the flag, block the feature to be safe.
        return false;
    }
}
// ---------------------------------------------------------------------------
// submitFeedback
// ---------------------------------------------------------------------------
/**
 * Records a Berean response rating from a verified user.
 *
 * Writes:
 *   1. Primary document at bereanFeedback/{feedbackId}
 *   2. Denormalized copy at bereanPipelineTraces/{traceId}/feedback/{feedbackId}
 *   3. (Conditional) Guardian review item at guardianReviewQueue/{reviewId}
 *      when rating is 'unsafe' or 'misleading'.
 *
 * @returns feedbackId of the newly created record.
 * @throws Error if the feedbackCapture flag is disabled.
 */
async function submitFeedback(params, db) {
    const enabled = await isFeedbackCaptureEnabled(db);
    if (!enabled) {
        throw new Error("feedbackCapture: feature flag 'feedbackCapture' is not enabled");
    }
    const { userId, traceId, sessionId, rating, comment } = params;
    const guardianReviewQueued = HIGH_PRIORITY_RATINGS.has(rating);
    const timestamp = FirebaseFirestore.Timestamp.now();
    // Generate stable IDs using the Firestore auto-id pattern.
    const primaryRef = db.collection("bereanFeedback").doc();
    const feedbackId = primaryRef.id;
    const entry = {
        feedbackId,
        userId,
        traceId,
        sessionId,
        rating,
        timestamp,
        guardianReviewQueued,
        ...(comment !== undefined && comment.trim().length > 0
            ? { comment: comment.trim() }
            : {}),
    };
    const batch = db.batch();
    // 1. Primary feedback record.
    batch.set(primaryRef, entry);
    // 2. Denormalized audit copy on the pipeline trace.
    const auditRef = db
        .collection("bereanPipelineTraces")
        .doc(traceId)
        .collection("feedback")
        .doc(feedbackId);
    batch.set(auditRef, entry);
    // 3. Guardian review queue escalation for high-priority ratings.
    if (guardianReviewQueued) {
        const reviewRef = db.collection("guardianReviewQueue").doc();
        batch.set(reviewRef, {
            reviewId: reviewRef.id,
            priority: "high",
            type: "berean_feedback",
            sourceTraceId: traceId,
            sourceUserId: userId,
            sourceFeedbackId: feedbackId,
            rating,
            timestamp,
            resolved: false,
        });
    }
    await batch.commit();
    return feedbackId;
}
// ---------------------------------------------------------------------------
// getFeedbackStats
// ---------------------------------------------------------------------------
/**
 * Aggregates feedback counts by rating type for a given pipeline trace.
 *
 * Queries bereanFeedback where traceId === the provided value, then counts
 * occurrences of each FeedbackRating.
 *
 * @returns A record mapping every FeedbackRating to its count (0 if none).
 * @throws Error if the feedbackCapture flag is disabled.
 */
async function getFeedbackStats(traceId, db) {
    const enabled = await isFeedbackCaptureEnabled(db);
    if (!enabled) {
        throw new Error("feedbackCapture: feature flag 'feedbackCapture' is not enabled");
    }
    const allRatings = [
        "accurate",
        "inaccurate",
        "helpful",
        "misleading",
        "missingContext",
        "biased",
        "unsafe",
        "excellent",
    ];
    // Initialise counts to zero.
    const counts = Object.fromEntries(allRatings.map((r) => [r, 0]));
    const snapshot = await db
        .collection("bereanFeedback")
        .where("traceId", "==", traceId)
        .get();
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const rating = data.rating;
        if (rating && rating in counts) {
            counts[rating] += 1;
        }
    }
    return counts;
}
