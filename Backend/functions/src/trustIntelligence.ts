import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

function requireAuth(context: functions.https.CallableContext) {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    return context.auth.uid;
}

export function requireAppCheck(context: functions.https.CallableContext) {
    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
}

function assertOwner(uid: string, userId: string) {
    if (uid !== userId) {
        throw new functions.https.HttpsError("permission-denied", "User mismatch");
    }
}

export const writeAgentInsight = functions.https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);

    const insightId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: insightId,
        agentType: String(data?.agentType ?? "berean"),
        title: String(data?.title ?? ""),
        detail: String(data?.detail ?? ""),
        confidence: Number(data?.confidence ?? 0),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(userId)
        .collection("agentInsights")
        .doc(insightId)
        .set(payload, { merge: true });

    return { ok: true, id: insightId };
});

export const writeAgentRecommendation = functions.https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);

    const recId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: recId,
        agentType: String(data?.agentType ?? "berean"),
        recommendation: String(data?.recommendation ?? ""),
        confidence: Number(data?.confidence ?? 0),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(userId)
        .collection("agentRecommendations")
        .doc(recId)
        .set(payload, { merge: true });

    return { ok: true, id: recId };
});

export const writeAgentExecutionLog = functions.https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);

    const logId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: logId,
        agentType: String(data?.agentType ?? "berean"),
        summary: String(data?.summary ?? ""),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(userId)
        .collection("executionLogs")
        .doc(logId)
        .set(payload, { merge: true });

    return { ok: true, id: logId };
});

export const writeTrustEvent = functions.https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);

    const eventId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: eventId,
        userId,
        type: String(data?.type ?? "messageSent"),
        metadata: data?.metadata ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(userId)
        .collection("trustEvents")
        .doc(eventId)
        .set(payload, { merge: true });

    return { ok: true, id: eventId };
});

export const writeTrustSnapshot = functions.https.onCall(async (data, context) => {
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);

    const snapshotId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: snapshotId,
        userId,
        humanScore: data?.humanScore ?? null,
        careScore: data?.careScore ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(userId)
        .collection("trustSnapshots")
        .doc(snapshotId)
        .set(payload, { merge: true });

    return { ok: true, id: snapshotId };
});
