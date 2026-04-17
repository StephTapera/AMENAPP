/**
 * notifications/prayerAnsweredBatch.ts
 *
 * 5.4 FIX: Firestore trigger that processes a single prayer-answered
 * notification batch in its own Cloud Function invocation.
 *
 * onPrayerAnswered (onSocialEvent.ts) writes one batch document per
 * 100 supporters to prayerAnsweredJobs/{prayerId}/batches/{index}.
 * This trigger fires for each batch document, processes ≤100 supporters
 * via the shared processCandidate pipeline, and marks the batch complete.
 *
 * Fan-out architecture:
 *   onPrayerAnswered trigger (1 invocation)
 *     → writes N batch docs  (N = ceil(supporters / 100))
 *     → each doc triggers this function (N parallel invocations)
 *     → each invocation processes ≤100 supporters
 *
 * Each invocation completes in seconds, not minutes — eliminating the
 * timeout risk that existed when all 5,000+ supporters were processed
 * sequentially in a single function call.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import {
    NotificationType,
    NotificationCandidate,
} from "./types";
import { buildRoutes } from "./helpers";
import { processCandidate } from "./onSocialEvent";

const db = admin.firestore();

export const processPrayerAnsweredBatch = onDocumentCreated(
    "prayerAnsweredJobs/{prayerId}/batches/{batchIndex}",
    async (event) => {
        const snap = event.data;
        if (!snap) return;
        const job = snap.data();
        if (!job) return;

        const { prayerId, authorId, actorName, actorUsername, actorProfileImageURL, supporterIds } = job;

        if (!prayerId || !authorId || !Array.isArray(supporterIds) || supporterIds.length === 0) {
            await snap.ref.update({ status: "skipped_invalid" });
            return;
        }

        const routes = buildRoutes(NotificationType.PrayerAnswered, {
            prayerId,
            actorId: authorId,
        });

        const candidates: NotificationCandidate[] = (supporterIds as string[]).map(
            (supporterId) => ({
                recipientId: supporterId,
                type: NotificationType.PrayerAnswered,
                actorId: authorId,
                actorName: actorName ?? "",
                actorUsername: actorUsername ?? "",
                actorProfileImageURL: actorProfileImageURL ?? null,
                postId: null,
                commentId: null,
                parentCommentId: null,
                conversationId: null,
                prayerId,
                noteId: null,
                commentText: null,
                ...routes,
            })
        );

        // Process all supporters in this batch in parallel.
        // Each batch is ≤100 entries — safe for a single invocation.
        await Promise.all(candidates.map((c) => processCandidate(c)));

        // Mark batch complete for observability / idempotency.
        await snap.ref.update({
            status: "completed",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
);
