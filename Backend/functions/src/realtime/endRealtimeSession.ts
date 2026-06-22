import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {requireAuthAndAppCheck} from "../amenAI/common";

const db = admin.firestore();

export const endRealtimeSession = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const sessionId = String(request.data?.sessionId ?? "").trim();
    if (!sessionId) throw new HttpsError("invalid-argument", "sessionId required");

    const sessionRef = db.collection("realtimeSessions").doc(sessionId);
    const session = await sessionRef.get();
    if (!session.exists) throw new HttpsError("not-found", "Realtime session not found.");
    const data = session.data() ?? {};
    const participantIds = Array.isArray(data.participantIds) ? data.participantIds : [];
    if (data.ownerId !== uid && !participantIds.includes(uid)) {
        throw new HttpsError("permission-denied", "You cannot end this realtime session.");
    }

    await sessionRef.set({
        status: "ended",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {ok: true};
});
