import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

// publishScheduledCovenantContent
// Runs every 5 minutes. Finds scheduled content past its scheduledAt timestamp
// and transitions it to published. Handles posts, stories, events, devotionals,
// study drops, and digest highlights.
//
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const publishScheduledCovenantContent = onSchedule(
    { schedule: "every 5 minutes", region: "us-central1" },
    async () => {
        const db = admin.firestore();

        // Idempotency: lock by 5-minute window (UTC ISO rounded to nearest 5 min)
        const nowMs = Date.now();
        const windowMs = 5 * 60 * 1000;
        const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
        const lockRef = db.doc(`system/scheduledJobLocks/publishScheduledContent_${windowKey}`);

        const lockAcquired = await db.runTransaction(async (tx) => {
            const snap = await tx.get(lockRef);
            if (snap.exists && snap.data()?.status === "completed") {
                return false;
            }
            tx.set(lockRef, {
                status: "running",
                startedAt: admin.firestore.FieldValue.serverTimestamp(),
                windowKey,
                expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
            });
            return true;
        });

        if (!lockAcquired) {
            logger.info("Scheduled job already completed this window, skipping", { job: "publishScheduledContent", windowKey });
            return;
        }

        try {
            const now = admin.firestore.Timestamp.now();

            // Query across all covenants' scheduledContent subcollections
            // Limitations of Firestore: use a top-level collection group query.
            const snap = await db.collectionGroup("scheduledContent")
                .where("status", "==", "scheduled")
                .where("scheduledAt", "<=", now)
                .limit(50)
                .get();

            if (!snap.empty) {
                const batch = db.batch();

                for (const doc of snap.docs) {
                    const data = doc.data();
                    try {
                        batch.update(doc.ref, {
                            status: "published",
                            publishedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });

                        // Fanout: create a covenantActivity event for all members (simplified)
                        // Full fan-out would read membership list; here we mark published and
                        // rely on client-side digest polling for discovery.
                        // A production implementation would use a Pub/Sub fan-out pattern.

                    } catch {
                        batch.update(doc.ref, {
                            status: "failed",
                            failedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }
                }

                await batch.commit();
            }

            await lockRef.update({
                status: "completed",
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (err) {
            await lockRef.update({
                status: "failed",
                error: String(err),
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            throw err;
        }
    }
);
