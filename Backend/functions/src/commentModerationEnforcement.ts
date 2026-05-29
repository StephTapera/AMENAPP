/**
 * commentModerationEnforcement.ts
 *
 * Server-authoritative comment moderation visibility enforcement.
 *
 * WHY THIS EXISTS:
 *   The client app reads `moderationStatus` from RTDB comment nodes to decide
 *   whether to render a comment. Previously, no backend pipeline wrote this field —
 *   it was either absent (client treats as visible) or written client-side (trivially
 *   bypassed). This function closes that gap by writing `moderationStatus` from a
 *   trusted server context in response to report accumulation.
 *
 * TRIGGER:
 *   Firestore onCreate on `userReports/{reportId}`.
 *   Only processes reports with `contentType === "comment"` and a valid `contentId`.
 *   User-to-user reports (no `contentType`) pass through untouched.
 *
 * THRESHOLDS (see MODERATION_THRESHOLDS below):
 *   - 1 tier-1 report (grooming/CSAM/threat/sextortion) → auto-hide immediately
 *   - 3+ reports (any reason) against the same comment → status: "pending" (human review queue)
 *   - 5+ reports OR 2+ tier-2 reports → status: "hidden" (auto-hidden, pending appeal)
 *
 * RTDB PATH:
 *   /comments/{postId}/{commentId}/moderationStatus
 *
 *   `postId` must be present on the userReports document (`postId` field).
 *   Without it, the function logs a warning and skips the RTDB write — the
 *   Firestore moderationQueue entry is still written for human triage.
 *
 * IDEMPOTENCY:
 *   The function queries existing reports for the same `contentId` before deciding
 *   on a threshold action. Multiple report submissions for the same comment are
 *   safe — the worst-case result is that a comment moves from "pending" → "hidden"
 *   sooner than the threshold would normally trigger.
 *
 * APPEAL:
 *   A human moderator can reset `moderationStatus` to "visible" via the admin console.
 *   The RTDB write uses `set(..., { merge: false })` on only the `moderationStatus`
 *   field (via `update`) so other comment fields are untouched.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Moderation Thresholds ────────────────────────────────────────────────────

const MODERATION_THRESHOLDS = {
    /** A single tier-1 report auto-hides the comment immediately. */
    autoHideOnTier1: true,

    /** Number of tier-2 reports that auto-hides a comment. */
    tier2HideCount: 2,

    /** Total report count that moves a comment to "pending" (queued for review). */
    pendingReportCount: 3,

    /** Total report count that auto-hides a comment regardless of tier. */
    autoHideReportCount: 5,

    /** Look-back window for aggregating reports (days). */
    windowDays: 30,
};

// ─── Types ────────────────────────────────────────────────────────────────────

type ModerationStatus = "visible" | "pending" | "hidden" | "parent_deleted";

interface ReportAggregation {
    total: number;
    tier1Count: number;
    tier2Count: number;
    highestEscalationTier: number;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Counts all existing reports for a given `contentId` (comment) within the
 * configured look-back window. Returns aggregated tier counts.
 */
async function aggregateCommentReports(commentId: string): Promise<ReportAggregation> {
    const cutoffDate = new Date(
        Date.now() - MODERATION_THRESHOLDS.windowDays * 24 * 60 * 60 * 1000
    );
    const cutoff = admin.firestore.Timestamp.fromDate(cutoffDate);

    const snap = await db
        .collection("userReports")
        .where("contentId", "==", commentId)
        .where("contentType", "==", "comment")
        .where("submittedAt", ">=", cutoff)
        .limit(100)
        .get();

    let tier1Count = 0;
    let tier2Count = 0;
    let highestEscalationTier = 3;

    for (const doc of snap.docs) {
        const tier: number = doc.data().escalationTier ?? 3;
        if (tier === 1) tier1Count++;
        else if (tier === 2) tier2Count++;
        if (tier < highestEscalationTier) highestEscalationTier = tier;
    }

    return {
        total: snap.size,
        tier1Count,
        tier2Count,
        highestEscalationTier,
    };
}

/**
 * Derives the appropriate ModerationStatus from aggregated report counts.
 * Returns null if no threshold is met (comment stays visible).
 */
function computeModerationStatus(agg: ReportAggregation): ModerationStatus | null {
    // Tier-1 report (CSAM, grooming, sextortion, threats) → immediate hide.
    if (MODERATION_THRESHOLDS.autoHideOnTier1 && agg.tier1Count >= 1) {
        return "hidden";
    }

    // Volume-based auto-hide threshold.
    if (agg.total >= MODERATION_THRESHOLDS.autoHideReportCount) {
        return "hidden";
    }

    // Tier-2 cluster hide (2+ serious reports).
    if (agg.tier2Count >= MODERATION_THRESHOLDS.tier2HideCount) {
        return "hidden";
    }

    // Enough reports to flag for human review, but not auto-hide yet.
    if (agg.total >= MODERATION_THRESHOLDS.pendingReportCount) {
        return "pending";
    }

    return null;
}

/**
 * Writes `moderationStatus` to the RTDB comment node.
 * Only updates the `moderationStatus` field — all other comment fields are untouched.
 *
 * Skips the write if `postId` is missing (logs a warning instead).
 */
async function writeRtdbModerationStatus(
    postId: string | null,
    commentId: string,
    status: ModerationStatus
): Promise<void> {
    if (!postId) {
        logger.warn(
            `[CommentModeration] Cannot write RTDB status for comment ${commentId} — ` +
            `postId is missing from the userReports document. ` +
            `Ensure submitReport includes postId when contentType=comment.`
        );
        return;
    }

    await admin.database()
        .ref(`comments/${postId}/${commentId}`)
        .update({ moderationStatus: status });

    logger.info(
        `[CommentModeration] RTDB /comments/${postId}/${commentId}/moderationStatus → "${status}"`
    );
}

/**
 * Writes a moderation queue entry to Firestore for human review.
 * Uses an idempotency key so repeated threshold crossings don't spam the queue.
 */
async function writeModerationQueueEntry(
    commentId: string,
    postId: string | null,
    reporterId: string,
    reportedUserId: string,
    status: ModerationStatus,
    agg: ReportAggregation,
    newReportId: string
): Promise<void> {
    const idempotencyKey = `comment_moderation_${commentId}_${status}`;

    // Skip if an entry for this (commentId, status) pair already exists.
    const existing = await db
        .collection("moderationQueue")
        .where("idempotencyKey", "==", idempotencyKey)
        .limit(1)
        .get();

    if (!existing.empty) {
        logger.info(
            `[CommentModeration] Queue entry already exists for comment ${commentId} ` +
            `status=${status} — skipping duplicate.`
        );
        return;
    }

    await db.collection("moderationQueue").add({
        type: "comment_moderation",
        commentId,
        postId: postId ?? null,
        triggeringReportId: newReportId,
        reporterId,
        reportedUserId,
        moderationStatus: status,
        reportAggregation: {
            total: agg.total,
            tier1Count: agg.tier1Count,
            tier2Count: agg.tier2Count,
            highestEscalationTier: agg.highestEscalationTier,
        },
        priority: agg.tier1Count >= 1 ? "immediate" : agg.tier2Count >= 2 ? "high" : "standard",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        idempotencyKey,
        policyVersion: "2026-04-20",
    });

    logger.info(
        `[CommentModeration] moderationQueue entry written for comment ${commentId} ` +
        `(status=${status}, total reports=${agg.total})`
    );
}

// ─── Cloud Function ────────────────────────────────────────────────────────────

/**
 * Firestore onCreate trigger: enforceCommentModerationVisibility
 *
 * Fires on every new userReports document. For reports targeting a specific
 * comment (`contentType === "comment"`), aggregates the report history and
 * writes `moderationStatus` to the RTDB comment node when thresholds are met.
 *
 * Non-comment reports (user-to-user reports without contentType) are skipped
 * immediately so there is no latency impact on the existing report flow.
 */
export const enforceCommentModerationVisibility = onDocumentCreated(
    "userReports/{reportId}",
    async (event) => {
        const reportId = event.params.reportId;
        const snap = event.data;
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        // ── Only process comment reports ────────────────────────────────────
        const contentType: string = data.contentType ?? "";
        const contentId: string = data.contentId ?? "";

        if (contentType !== "comment" || !contentId) {
            // Not a comment report — nothing to do here.
            return;
        }

        const postId: string | null = data.postId ?? null;
        const reporterId: string = data.reporterId ?? "";
        const reportedUserId: string = data.reportedUserId ?? "";

        logger.info(
            `[CommentModeration] Processing report ${reportId} — ` +
            `comment=${contentId}, postId=${postId ?? "MISSING"}, ` +
            `reporter=${reporterId}, reported=${reportedUserId}`
        );

        // ── Aggregate all reports for this comment ──────────────────────────
        let agg: ReportAggregation;
        try {
            agg = await aggregateCommentReports(contentId);
        } catch (err) {
            logger.error(
                `[CommentModeration] Failed to aggregate reports for comment ${contentId}`, err
            );
            return;
        }

        logger.info(
            `[CommentModeration] Comment ${contentId} report aggregation: ` +
            `total=${agg.total}, tier1=${agg.tier1Count}, tier2=${agg.tier2Count}`
        );

        // ── Determine target moderation status ──────────────────────────────
        const targetStatus = computeModerationStatus(agg);

        if (!targetStatus) {
            // Thresholds not yet met — comment stays visible.
            logger.info(
                `[CommentModeration] Comment ${contentId} below all thresholds ` +
                `(total=${agg.total}) — no status change.`
            );
            return;
        }

        // ── Write RTDB moderationStatus ─────────────────────────────────────
        try {
            await writeRtdbModerationStatus(postId, contentId, targetStatus);
        } catch (err) {
            logger.error(
                `[CommentModeration] RTDB write failed for comment ${contentId}`, err
            );
            // Continue — still write the moderation queue entry for human triage.
        }

        // ── Write Firestore moderation queue entry for human review ─────────
        try {
            await writeModerationQueueEntry(
                contentId,
                postId,
                reporterId,
                reportedUserId,
                targetStatus,
                agg,
                reportId
            );
        } catch (err) {
            logger.error(
                `[CommentModeration] moderationQueue write failed for comment ${contentId}`, err
            );
        }
    }
);
