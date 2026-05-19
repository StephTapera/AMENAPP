import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {lightweightModeration, requireAuthAndAppCheck} from "../../amenAI/common";

const db = admin.firestore();

const supportedLanguages = new Set(["en", "es", "pt", "ko", "fr", "de", "ja", "zh", "ar", "hi"]);
const supportedKinds = new Set(["transcript", "caption", "translation"]);

function stringField(value: unknown, field: string, maxLength: number): string {
    if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
    const trimmed = value.trim();
    if (!trimmed) throw new HttpsError("invalid-argument", `${field} is required.`);
    if (trimmed.length > maxLength) throw new HttpsError("invalid-argument", `${field} is too long.`);
    return trimmed;
}

function optionalNumber(value: unknown): number {
    return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function language(value: unknown): string {
    const code = typeof value === "string" ? value.trim().toLowerCase() : "en";
    return supportedLanguages.has(code) ? code : "en";
}

async function assertSessionAccess(uid: string, sessionId: string): Promise<FirebaseFirestore.DocumentReference> {
    const ref = db.collection("realtimeSessions").doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Realtime session not found.");
    const data = snap.data() ?? {};
    const participantIds = Array.isArray(data.participantIds) ? data.participantIds : [];
    if (data.ownerId !== uid && !participantIds.includes(uid)) {
        throw new HttpsError("permission-denied", "You cannot write to this realtime session.");
    }
    if (data.status === "ended") {
        throw new HttpsError("failed-precondition", "Realtime session has ended.");
    }
    return ref;
}

export const persistRealtimeTranscriptChunk = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const sessionId = stringField(request.data?.sessionId, "sessionId", 160);
    const text = stringField(request.data?.text, "text", 4000);
    const kind = stringField(request.data?.kind ?? "transcript", "kind", 40);
    if (!supportedKinds.has(kind)) throw new HttpsError("invalid-argument", "Unsupported realtime chunk kind.");

    const sessionRef = await assertSessionAccess(uid, sessionId);
    const verdict = lightweightModeration(text);
    await db.collection("realtimeModerationEvents").doc().set({
        uid,
        sessionId,
        kind,
        allowed: verdict.ok,
        reason: verdict.reason ?? null,
        category: verdict.category ?? null,
        transcriptLength: text.length,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (!verdict.ok) throw new HttpsError("failed-precondition", "Realtime chunk blocked by safety policy.");

    const languageCode = language(request.data?.language);
    const payload = {
        ownerId: uid,
        text,
        language: languageCode,
        targetLanguage: language(request.data?.targetLanguage ?? languageCode),
        sourceLanguage: language(request.data?.sourceLanguage ?? languageCode),
        isFinal: request.data?.isFinal === true,
        startsAtMs: optionalNumber(request.data?.startsAtMs),
        durationMs: optionalNumber(request.data?.durationMs),
        moderationStatus: "approved",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const subcollection = kind === "translation" ? "translationChunks" : kind === "caption" ? "captionChunks" : "transcriptChunks";
    const chunkRef = sessionRef.collection(subcollection).doc();
    await chunkRef.set(payload);
    await sessionRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        "streamHealth.lastChunkAt": admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {chunkId: chunkRef.id, kind, moderationStatus: "approved"};
});
