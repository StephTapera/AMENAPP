import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {requireAuthAndAppCheck} from "../amenAI/common";

const db = admin.firestore();

export const logRealtimeVoiceEvent = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const sessionId = String(request.data?.sessionId ?? "").trim();
    if (!sessionId) throw new HttpsError("invalid-argument", "sessionId required");

    const session = await db.collection("realtimeSessions").doc(sessionId).get();
    if (!session.exists) throw new HttpsError("not-found", "Realtime session not found.");
    const sessionData = session.data() ?? {};
    const participantIds = Array.isArray(sessionData.participantIds) ? sessionData.participantIds : [];
    if (sessionData.ownerId !== uid && !participantIds.includes(uid)) {
        throw new HttpsError("permission-denied", "You cannot write events for this session.");
    }

    const type = String(request.data?.type ?? "unknown").slice(0, 80);
    const eventRef = db.collection("realtimeSessions").doc(sessionId).collection("analyticsEvents").doc();
    await eventRef.set({
        uid,
        type: String(request.data?.type ?? "unknown"),
        sessionId,
        latencyMs: Number(request.data?.latencyMs ?? 0),
        language: String(request.data?.language ?? ""),
        surface: String(request.data?.surface ?? ""),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection("aiAudit").doc("realtimeEvents").collection("events").doc(eventRef.id).set({
        uid,
        sessionId,
        type,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {eventId: eventRef.id};
});
