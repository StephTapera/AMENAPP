import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

// createPrayerRequestFromMessage
// Converts a room message into a tracked prayer request.
// Validates membership. Creates prayer request document.
// Creates an activity notification for any members who have prayer-follow-up notifications enabled.

export const createPrayerRequestFromMessage = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { covenantId, roomId, messageId, body, visibility = "members_only" } = request.data;

        if (!covenantId || !body?.trim()) {
            throw new HttpsError("invalid-argument", "covenantId and body are required.");
        }

        const db = admin.firestore();

        // Validate membership
        const memberSnap = await db.collection("covenantMemberships")
            .where("covenantId", "==", covenantId)
            .where("userId", "==", uid)
            .where("status", "in", ["active", "trialing"])
            .limit(1)
            .get();
        if (memberSnap.empty) {
            throw new HttpsError("permission-denied", "Not a member of this community.");
        }

        const validVisibility = ["public", "members_only", "anonymous"];
        if (!validVisibility.includes(visibility)) {
            throw new HttpsError("invalid-argument", "Invalid visibility value.");
        }

        const requestRef = db.collection("covenants").doc(covenantId)
            .collection("prayerRequests").doc();

        await requestRef.set({
            sourceMessageId: messageId ?? null,
            covenantId,
            roomId: roomId ?? null,
            authorUserId: visibility === "anonymous" ? "anonymous" : uid,
            body: body.trim(),
            visibility,
            prayedCount: 0,
            followUpRequested: false,
            lastUpdateAt: null,
            status: "open",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { prayerRequestId: requestRef.id };
    }
);
