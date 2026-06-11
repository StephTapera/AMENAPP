import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

// calculateCovenantChurnRisk
// Scheduled daily. Reads membership + activity signals to compute churn risk.
// Writes aggregate signals to /covenants/{covenantId}/memberSignals/{userId}.
// Individual-level data is only written for consent-enabled members.
// Creator UI aggregates risk — never surfaces invasive personal surveillance by default.

export const calculateCovenantChurnRisk = onSchedule(
    { schedule: "every 24 hours", region: "us-central1" },
    async () => {
        const db = admin.firestore();
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
                let risk: "low" | "medium" | "high" = hasRecentActivity ? "low" : "medium";

                if (!hasRecentActivity) {
                    reasons.push("inactive_14_days");
                }

                if (risk !== "low") {
                    mediumCount++;

                    const signalRef = db.collection("covenants").doc(covenantId)
                        .collection("memberSignals").doc(userId);

                    batch.set(signalRef, {
                        userId,
                        covenantId,
                        churnRisk: risk,
                        reasons,
                        suggestedAction: "Consider a check-in post or digest highlight.",
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
    }
);
