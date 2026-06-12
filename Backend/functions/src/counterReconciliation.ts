/**
 * counterReconciliation.ts
 *
 * WHY THIS EXISTS:
 *   Follow/unfollow counters (followersCount, followingCount) are incremented
 *   and decremented in Cloud Function batch writes. While these are atomic,
 *   network failures, retries, or direct Firestore writes from older client
 *   versions can cause drift between the stored counter and the actual edge count.
 *
 *   This scheduled function recomputes the ground-truth counts from the
 *   follows_index collection and corrects any discrepancies.
 *
 * Schedule: Every Monday at 03:00 America/New_York (low-traffic window).
 *   Processes users in batches of BATCH_SIZE to stay within function timeout.
 *
 * See docs/privacy-model.md §2 (Counter Integrity).
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

const BATCH_SIZE = 50; // users per batch (aggregate queries are still billed per read)

export const reconcileFollowCounts = onSchedule(
    {
        schedule: "every monday 03:00",
        timeZone: "America/New_York",
        region: "us-east1", // us-central1 at 999/1000 Cloud Run service quota
        memory: "512MiB",
        timeoutSeconds: 540,
        maxInstances: 1, // prevent concurrent reconciliation runs
    },
    async () => {
        logger.info("[reconcileFollowCounts] Starting weekly follow count reconciliation");

        let processed = 0;
        let repaired = 0;
        let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

        while (true) {
            let query: admin.firestore.Query = db
                .collection("users")
                .orderBy("createdAt", "asc")
                .limit(BATCH_SIZE);

            if (lastDoc) {
                query = query.startAfter(lastDoc);
            }

            const snap = await query.get();
            if (snap.empty) break;

            lastDoc = snap.docs[snap.docs.length - 1];

            // Process this batch — use aggregate COUNT queries to avoid fetching all docs
            const batchResults = await Promise.allSettled(
                snap.docs.map(async (userDoc) => {
                    const uid = userDoc.id;

                    const [followersAgg, followingAgg] = await Promise.all([
                        db
                            .collection("follows_index")
                            .where("followingId", "==", uid)
                            .count()
                            .get(),
                        db
                            .collection("follows_index")
                            .where("followerId", "==", uid)
                            .count()
                            .get(),
                    ]);

                    const actualFollowers = followersAgg.data().count;
                    const actualFollowing = followingAgg.data().count;

                    const userData = userDoc.data();
                    const storedFollowers = userData.followersCount ?? 0;
                    const storedFollowing = userData.followingCount ?? 0;

                    if (
                        actualFollowers !== storedFollowers ||
                        actualFollowing !== storedFollowing
                    ) {
                        await userDoc.ref.update({
                            followersCount: actualFollowers,
                            followingCount: actualFollowing,
                            followCountReconciledAt:
                                admin.firestore.FieldValue.serverTimestamp(),
                        });

                        logger.warn(
                            `[reconcileFollowCounts] Repaired uid=${uid}: ` +
                            `followers ${storedFollowers}→${actualFollowers}, ` +
                            `following ${storedFollowing}→${actualFollowing}`
                        );
                        return { repaired: true };
                    }
                    return { repaired: false };
                })
            );

            for (const result of batchResults) {
                processed++;
                if (result.status === "fulfilled" && result.value.repaired) repaired++;
            }
        }

        logger.info(
            `[reconcileFollowCounts] Done. Processed=${processed}, Repaired=${repaired}`
        );
    }
);
