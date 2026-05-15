import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

// publishScheduledCovenantContent
// Runs every 5 minutes. Finds scheduled content past its scheduledAt timestamp
// and transitions it to published. Handles posts, stories, events, devotionals,
// study drops, and digest highlights.

export const publishScheduledCovenantContent = onSchedule(
    { schedule: "every 5 minutes", region: "us-central1" },
    async () => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        // Query across all covenants' scheduledContent subcollections
        // Limitations of Firestore: use a top-level collection group query.
        const snap = await db.collectionGroup("scheduledContent")
            .where("status", "==", "scheduled")
            .where("scheduledAt", "<=", now)
            .limit(50)
            .get();

        if (snap.empty) return;

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
);
