// selahConnection.ts
// AMEN — Selah Connection Cloud Functions
//
// Connection features: Tables (join/sunset), Commitments (close-the-loop nudge),
// PrayerChains (assemble woven artifact).
//
// All functions: region us-central1, Firebase v2 imports.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

// MARK: - joinTable

/**
 * Transaction-based join with hard cap enforcement.
 * If members.length >= memberLimit: throws HttpsError("failed-precondition").
 * Region: us-central1.
 */
export const joinTable = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request) => {
        const { tableId, uid } = request.data as { tableId: string; uid: string };

        if (!tableId || !uid) {
            throw new HttpsError("invalid-argument", "tableId and uid are required.");
        }

        const tableRef = db.collection("tables").doc(tableId);

        await db.runTransaction(async (tx) => {
            const tableSnap = await tx.get(tableRef);
            if (!tableSnap.exists) {
                throw new HttpsError("not-found", "Table not found.");
            }

            const data = tableSnap.data()!;
            const members: string[] = data.members ?? [];
            const memberLimit: number = data.memberLimit ?? 12;

            if (data.archived === true) {
                throw new HttpsError(
                    "failed-precondition",
                    "This Table has drawn to a close."
                );
            }

            if (members.includes(uid)) {
                // Already a member — idempotent, no error.
                return;
            }

            if (members.length >= memberLimit) {
                throw new HttpsError(
                    "failed-precondition",
                    "This Table is full."
                );
            }

            tx.update(tableRef, {
                members: admin.firestore.FieldValue.arrayUnion(uid),
            });
        });

        return { success: true };
    }
);

// MARK: - closeTheLoopNudge

/**
 * Scheduled every 6 hours.
 * Checks commitments where loopState == "open" AND closeTheLoopAt <= now.
 * Sends a single gentle push notification. Sets loopState to "nudged" — never fires again.
 * Region: us-central1.
 */
export const closeTheLoopNudge = onSchedule(
    { schedule: "every 6 hours", region: "us-central1" },
    async () => {
        const now = admin.firestore.Timestamp.now();

        const snapshot = await db
            .collection("commitments")
            .where("loopState", "==", "open")
            .where("closeTheLoopAt", "<=", now)
            .limit(200)
            .get();

        const batch = db.batch();
        const notificationPromises: Promise<void>[] = [];

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const parties: string[] = data.parties ?? [];

            // Transition loopState to "nudged" so this never fires again.
            batch.update(doc.ref, { loopState: "nudged" });

            // Send a gentle nudge to each party.
            for (const uid of parties) {
                notificationPromises.push(
                    sendGentleNudge(uid, data.kind as string)
                );
            }
        }

        await Promise.all([batch.commit(), ...notificationPromises]);
    }
);

async function sendGentleNudge(uid: string, kind: string): Promise<void> {
    const userSnap = await db.collection("users").doc(uid).get();
    const fcmToken: string | undefined = userSnap.data()?.fcmToken;
    if (!fcmToken) return;

    const kindLabel =
        kind === "prayFor"
            ? "check in on your prayer commitment"
            : kind === "checkIn"
            ? "check in with someone"
            : kind === "readWith"
            ? "revisit your reading commitment"
            : "revisit a commitment";

    await messaging.send({
        token: fcmToken,
        notification: {
            title: "A gentle reminder",
            body: `Whenever you're ready, ${kindLabel}.`,
        },
        apns: {
            payload: {
                aps: {
                    "interruption-level": "passive",
                },
            },
        },
    });
}

// MARK: - sunsetTable

/**
 * Scheduled every 24 hours.
 * Archives tables where sunsetAt <= now AND archived != true.
 * Sends warm closing summary to members. Preserves notebookId ref.
 * Region: us-central1.
 */
export const sunsetTable = onSchedule(
    { schedule: "every 24 hours", region: "us-central1" },
    async () => {
        const now = admin.firestore.Timestamp.now();

        const snapshot = await db
            .collection("tables")
            .where("sunsetAt", "<=", now)
            .where("archived", "!=", true)
            .limit(100)
            .get();

        const batch = db.batch();
        const notificationPromises: Promise<void>[] = [];

        for (const doc of snapshot.docs) {
            const data = doc.data();
            const tableName: string = data.name ?? "your Table";
            const members: string[] = data.members ?? [];

            // Archive the table; preserve notebookId.
            batch.update(doc.ref, { archived: true });

            // Send warm closing summary to each member.
            for (const uid of members) {
                notificationPromises.push(
                    sendTableClosingSummary(uid, tableName)
                );
            }
        }

        await Promise.all([batch.commit(), ...notificationPromises]);
    }
);

async function sendTableClosingSummary(
    uid: string,
    tableName: string
): Promise<void> {
    const userSnap = await db.collection("users").doc(uid).get();
    const fcmToken: string | undefined = userSnap.data()?.fcmToken;
    if (!fcmToken) return;

    await messaging.send({
        token: fcmToken,
        notification: {
            title: "Your Table has drawn to a close",
            body: `Your Table "${tableName}" has drawn to a close. Your shared notes are preserved.`,
        },
        apns: {
            payload: {
                aps: {
                    "interruption-level": "passive",
                },
            },
        },
    });
}

// MARK: - assemblePrayerChain

/**
 * HTTP callable. Reads chain links from Firestore, creates a wovenArtifact document
 * with ordered link refs, updates chain.wovenArtifactRef, returns artifact metadata.
 * Region: us-central1.
 */
export const assemblePrayerChain = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request) => {
        const { chainId } = request.data as { chainId: string };

        if (!chainId) {
            throw new HttpsError("invalid-argument", "chainId is required.");
        }

        const chainRef = db.collection("prayerChains").doc(chainId);
        const chainSnap = await chainRef.get();

        if (!chainSnap.exists) {
            throw new HttpsError("not-found", "Prayer chain not found.");
        }

        const chainData = chainSnap.data()!;
        const links: Array<Record<string, unknown>> = chainData.links ?? [];

        if (links.length === 0) {
            throw new HttpsError(
                "failed-precondition",
                "This chain has no links to assemble."
            );
        }

        // Create the woven artifact metadata record.
        const artifactId = db.collection("wovenArtifacts").doc().id;
        const artifactRef = db.collection("wovenArtifacts").doc(artifactId);
        const now = admin.firestore.Timestamp.now();

        const artifactData = {
            id: artifactId,
            chainId,
            requestRef: chainData.requestRef ?? null,
            orderedLinkRefs: links.map((link, index) => ({
                index,
                uid: link.uid,
                kind: link.kind ?? link.type,
            })),
            createdAt: now,
        };

        await artifactRef.set(artifactData);
        await chainRef.update({ wovenArtifactRef: artifactId });

        return {
            artifactId,
            chainId,
            linkCount: links.length,
            createdAt: now.toMillis(),
        };
    }
);
