import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = admin.firestore();

type CrisisUrgency = "none" | "moderate" | "high" | "critical";

interface CrisisAnalysisResult {
    isCrisis: boolean;
    crisisTypes: string[];
    urgencyLevel: CrisisUrgency;
    recommendedResources: string[];
    confidence: number;
    suggestedIntervention: "none" | "show_resources" | "emergency_contact";
}

export const detectCrisis = onDocumentCreated(
    {
        document: "crisisDetectionRequests/{requestId}",
        region: "us-central1",
    },
    async (event) => {
        const requestId = event.params.requestId;
        const data = event.data?.data() as { prayerText?: string; userId?: string } | undefined;

        if (!data?.prayerText || !data.userId) {
            console.error("[detectCrisis] Missing prayerText or userId", { requestId });
            return;
        }

        try {
            const crisisResult = analyzeForCrisis(data.prayerText);

            await db.collection("crisisDetectionResults").doc(requestId).set({
                isCrisis: crisisResult.isCrisis,
                crisisTypes: crisisResult.crisisTypes,
                urgencyLevel: crisisResult.urgencyLevel,
                recommendedResources: crisisResult.recommendedResources,
                confidence: crisisResult.confidence,
                suggestedIntervention: crisisResult.suggestedIntervention,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (crisisResult.urgencyLevel === "critical") {
                await db.collection("moderatorAlerts").add({
                    type: "critical_crisis",
                    userId: data.userId,
                    crisisTypes: crisisResult.crisisTypes,
                    urgencyLevel: crisisResult.urgencyLevel,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    status: "urgent",
                });
            }
        } catch (error) {
            console.error("[detectCrisis] Failed to analyze request", { requestId, error });

            await db.collection("crisisDetectionResults").doc(requestId).set({
                isCrisis: false,
                crisisTypes: [],
                urgencyLevel: "none",
                recommendedResources: [],
                confidence: 0,
                suggestedIntervention: "none",
                error: error instanceof Error ? error.message : "Unknown error",
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    }
);

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const deliverBatchedNotifications = onSchedule(
    {
        schedule: "every 5 minutes",
        region: "us-central1",
    },
    async () => {
        // Idempotency: lock by 5-minute window (UTC ISO rounded to nearest 5 min)
        const nowMs = Date.now();
        const windowMs = 5 * 60 * 1000;
        const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
        const lockRef = db.doc(`system/scheduledJobLocks/deliverBatchedNotifications_${windowKey}`);

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
            console.info("[deliverBatchedNotifications] Already completed this window, skipping", { windowKey });
            return;
        }

        try {
            const now = admin.firestore.Timestamp.now();
            const snapshot = await db.collection("scheduledBatches")
                .where("status", "==", "scheduled")
                .where("deliveryTime", "<=", now)
                .limit(100)
                .get();

            for (const doc of snapshot.docs) {
                const scheduleData = doc.data() as {
                    batchId?: string;
                    recipientId?: string;
                };

                if (!scheduleData.batchId || !scheduleData.recipientId) {
                    await doc.ref.update({
                        status: "failed",
                        error: "Missing batch metadata",
                    });
                    continue;
                }

                try {
                    const batchDoc = await db.collection("notificationBatches")
                        .doc(scheduleData.batchId)
                        .get();

                    if (!batchDoc.exists) {
                        await doc.ref.update({
                            status: "failed",
                            error: "Missing notification batch",
                        });
                        continue;
                    }

                    const batch = batchDoc.data() as {
                        type?: string;
                        count?: number;
                    } | undefined;

                    if (!batch?.type || batch.count == null) {
                        await doc.ref.update({
                            status: "failed",
                            error: "Incomplete notification batch",
                        });
                        continue;
                    }

                    const notification = generateBatchNotification(batch.type, batch.count);
                    const userDoc = await db.collection("users").doc(scheduleData.recipientId).get();
                    const fcmToken = userDoc.data()?.fcmToken as string | undefined;

                    if (fcmToken) {
                        await admin.messaging().send({
                            token: fcmToken,
                            notification: {
                                title: notification.title,
                                body: notification.body,
                            },
                            data: {
                                type: batch.type,
                                count: String(batch.count),
                            },
                            apns: {
                                payload: {
                                    aps: {
                                        badge: 1,
                                        sound: "default",
                                    },
                                },
                            },
                        });
                    }

                    await Promise.all([
                        batchDoc.ref.update({ delivered: true }),
                        doc.ref.update({ status: "delivered" }),
                    ]);
                } catch (error) {
                    console.error("[deliverBatchedNotifications] Failed to deliver batch", {
                        scheduleId: doc.id,
                        error,
                    });
                    await doc.ref.update({
                        status: "failed",
                        error: error instanceof Error ? error.message : "Unknown error",
                    });
                }
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

function analyzeForCrisis(prayerText: string): CrisisAnalysisResult {
    const lowercased = prayerText.toLowerCase();
    const detectedCrises: string[] = [];
    let maxUrgency: CrisisUrgency = "none";

    const suicidePatterns = [
        "want to die",
        "kill myself",
        "end my life",
        "suicide",
    ];
    if (suicidePatterns.some((pattern) => lowercased.includes(pattern))) {
        detectedCrises.push("suicide_ideation");
        maxUrgency = "critical";
    }

    const selfHarmPatterns = [
        "hurt myself",
        "cut myself",
        "harm myself",
    ];
    if (selfHarmPatterns.some((pattern) => lowercased.includes(pattern))) {
        detectedCrises.push("self_harm");
        if (maxUrgency !== "critical") {
            maxUrgency = "high";
        }
    }

    const abusePatterns = [
        "abused",
        "hitting me",
        "hurting me",
        "violence",
    ];
    if (abusePatterns.some((pattern) => lowercased.includes(pattern))) {
        detectedCrises.push("abuse");
        if (maxUrgency !== "critical") {
            maxUrgency = "high";
        }
    }

    if (detectedCrises.length === 0) {
        return {
            isCrisis: false,
            crisisTypes: [],
            urgencyLevel: "none",
            recommendedResources: [],
            confidence: 0,
            suggestedIntervention: "none",
        };
    }

    return {
        isCrisis: true,
        crisisTypes: detectedCrises,
        urgencyLevel: maxUrgency,
        recommendedResources: recommendedResourcesFor(detectedCrises),
        confidence: 0.85,
        suggestedIntervention: maxUrgency === "critical" ? "emergency_contact" : "show_resources",
    };
}

function recommendedResourcesFor(crisisTypes: string[]): string[] {
    const resources = new Set<string>(["christian_counseling"]);

    for (const type of crisisTypes) {
        if (type === "suicide_ideation") {
            resources.add("suicide_prevention");
            resources.add("crisis_text_line");
        } else if (type === "self_harm") {
            resources.add("mental_health");
            resources.add("crisis_text_line");
        } else if (type === "abuse") {
            resources.add("domestic_violence");
        }
    }

    return Array.from(resources);
}

function generateBatchNotification(type: string, count: number): { title: string; body: string } {
    switch (type) {
    case "likes":
        return {
            title: "New encouragement on AMEN",
            body: count === 1 ? "Someone reacted to your post." : `${count} people reacted to your post.`,
        };
    case "comments":
        return {
            title: "New replies on AMEN",
            body: count === 1 ? "You received a new comment." : `You received ${count} new comments.`,
        };
    case "follows":
        return {
            title: "Community update",
            body: count === 1 ? "Someone followed you." : `${count} people followed you.`,
        };
    default:
        return {
            title: "AMEN updates",
            body: count === 1 ? "You have a new update." : `You have ${count} new updates.`,
        };
    }
}
