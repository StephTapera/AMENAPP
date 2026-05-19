import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {lightweightModeration, requireAuthAndAppCheck} from "../amenAI/common";

const db = admin.firestore();

export const moderateRealtimeTranscript = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const sessionId = String(request.data?.sessionId ?? "").trim();
    const transcript = String(request.data?.transcript ?? "");
    if (transcript.length > 20000) {
        throw new HttpsError("invalid-argument", "Transcript chunk is too large.");
    }

    const verdict = lightweightModeration(transcript);
    if (sessionId) {
        await db.collection("realtimeModerationEvents").doc().set({
            uid,
            sessionId,
            allowed: verdict.ok,
            reason: verdict.reason ?? null,
            category: verdict.category ?? null,
            transcriptLength: transcript.length,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    if (!verdict.ok) throw new HttpsError("failed-precondition", "Transcript blocked by safety policy.");
    return {allowed: true, reason: null};
});
