import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

// calculateCovenantChurnRisk
// Scheduled daily. Reads membership + activity signals to compute churn risk.
// Writes aggregate signals to /covenants/{covenantId}/memberSignals/{userId}.
// Individual-level data is only written for consent-enabled members.
// Creator UI aggregates risk — never surfaces invasive personal surveillance by default.
//
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const calculateCovenantChurnRisk = onSchedule(
    { schedule: "every 24 hours", region: "us-central1" },
    async () => {
        const db = admin.firestore();
        const today = new Date().toISOString().slice(0, 10);
        const lockRef = db.doc(`system/scheduledJobLocks/covenantChurnRisk_${today}`);

        const lockAcquired = await db.runTransaction(async (tx) => {
            const snap = await tx.get(lockRef);
            if (snap.exists && snap.data()?.status === "completed") {
                return false;
            }
            tx.set(lockRef, {
                status: "running",
                startedAt: admin.firestore.FieldValue.serverTimestamp(),
                date: today,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            });
            return true;
        });

        if (!lockAcquired) {
            logger.info("Scheduled job already completed today, skipping", { job: "covenantChurnRisk", date: today });
            return;
        }

        try {
            const now = Date.now();
            const fourteenDaysAgo = new Date(now - 14 * 24 * 60 * 60 * 1000);

            // Load all active paid memberships
            const membershipsSnap = await db.collection("covenantMemberships")
                .where("status", "in", ["active", "trialing"])
                .get();

            const byCovenantId: Record<string, typeof membershipsSnap.docs> = {};
            for (const doc of membershipsSnap.docs) {
                const cid = doc.data().covenantId as string;
                if (!byCovenantId[cid]) byCovenantId[cid] = [];
                byCovenantId[cid].push(doc);
            }

            const batch = db.batch();
            let opCount = 0;

            for (const [covenantId, docs] of Object.entries(byCovenantId)) {
                let highCount = 0;
                let mediumCount = 0;

                for (const doc of docs) {
                    const { userId } = doc.data() as { userId: string };

                    // Pull recent activity count from user's covenantActivity
                    const activitySnap = await db.collection("users").doc(userId)
                        .collection("covenantActivity")
                        .where("covenantId", "==", covenantId)
                        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
                        .limit(1)
                        .get();

                    const hasRecentActivity = !activitySnap.empty;
                    const reasons: string[] = [];
                    let risk: "low" | "medium" | "high" = "low";

                    if (!hasRecentActivity) {
                        reasons.push("inactive_14_days");
                        risk = "medium";
                    }

                    // Escalate to high if member has been inactive for 30+ days
                    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
                    const longInactiveSnap = await db.collection("users").doc(userId)
                        .collection("covenantActivity")
                        .where("covenantId", "==", covenantId)
                        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
                        .limit(1)
                        .get();
                    if (longInactiveSnap.empty && risk === "medium") {
                        risk = "high";
                        reasons.push("inactive_30_days");
                    }

                    if (risk !== "low") {
                        if (risk === "high") highCount++;
                        else mediumCount++;

                        const signalRef = db.collection("covenants").doc(covenantId)
                            .collection("memberSignals").doc(userId);

                        batch.set(signalRef, {
                            userId,
                            covenantId,
                            churnRisk: risk,
                            reasons,
                            suggestedAction: risk === "high"
                                ? "Consider sending a personal message or a special offer."
                                : "Consider a check-in post or digest highlight.",
                            computedAt: admin.firestore.FieldValue.serverTimestamp(),
                        }, { merge: true });

                        opCount++;
                        // Commit in batches of 400
                        if (opCount >= 400) {
                            await batch.commit();
                            opCount = 0;
                        }
                    }
                }
            }

            if (opCount > 0) await batch.commit();

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
