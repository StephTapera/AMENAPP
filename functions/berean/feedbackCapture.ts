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

import * as FirebaseFirestore from "@google-cloud/firestore";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type FeedbackRating =
  | "accurate"
  | "inaccurate"
  | "helpful"
  | "misleading"
  | "missingContext"
  | "biased"
  | "unsafe"
  | "excellent";

export interface FeedbackEntry {
  feedbackId: string;
  userId: string;
  traceId: string;
  sessionId: string;
  rating: FeedbackRating;
  comment?: string;
  timestamp: FirebaseFirestore.Timestamp;
  guardianReviewQueued: boolean;
}

/** Ratings that require immediate guardian escalation. */
const HIGH_PRIORITY_RATINGS: ReadonlySet<FeedbackRating> = new Set([
  "unsafe",
  "misleading",
]);

// ---------------------------------------------------------------------------
// Feature flag helper
// ---------------------------------------------------------------------------

async function isFeedbackCaptureEnabled(
  db: FirebaseFirestore.Firestore
): Promise<boolean> {
  try {
    const flagDoc = await db.doc("featureFlags/trustArchitecture").get();
    if (!flagDoc.exists) return false;
    const data = flagDoc.data();
    return data?.feedbackCapture === true;
  } catch {
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
export async function submitFeedback(
  params: {
    userId: string;
    traceId: string;
    sessionId: string;
    rating: FeedbackRating;
    comment?: string;
  },
  db: FirebaseFirestore.Firestore
): Promise<string> {
  const enabled = await isFeedbackCaptureEnabled(db);
  if (!enabled) {
    throw new Error(
      "feedbackCapture: feature flag 'feedbackCapture' is not enabled"
    );
  }

  const { userId, traceId, sessionId, rating, comment } = params;

  const guardianReviewQueued = HIGH_PRIORITY_RATINGS.has(rating);
  const timestamp = FirebaseFirestore.Timestamp.now();

  // Generate stable IDs using the Firestore auto-id pattern.
  const primaryRef = db.collection("bereanFeedback").doc();
  const feedbackId = primaryRef.id;

  const entry: FeedbackEntry = {
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
export async function getFeedbackStats(
  traceId: string,
  db: FirebaseFirestore.Firestore
): Promise<Record<FeedbackRating, number>> {
  const enabled = await isFeedbackCaptureEnabled(db);
  if (!enabled) {
    throw new Error(
      "feedbackCapture: feature flag 'feedbackCapture' is not enabled"
    );
  }

  const allRatings: FeedbackRating[] = [
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
  const counts = Object.fromEntries(
    allRatings.map((r) => [r, 0])
  ) as Record<FeedbackRating, number>;

  const snapshot = await db
    .collection("bereanFeedback")
    .where("traceId", "==", traceId)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data() as Partial<FeedbackEntry>;
    const rating = data.rating;
    if (rating && rating in counts) {
      counts[rating] += 1;
    }
  }

  return counts;
}
