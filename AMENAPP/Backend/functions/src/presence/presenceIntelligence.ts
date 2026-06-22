import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

const db = admin.firestore();

function requireAuth(request: {auth?: {uid?: string}}): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
}

export const updatePresencePreferences = onCall({region: "us-central1", enforceAppCheck: true}, async (request) => {
    const uid = requireAuth(request);
    const data = request.data as Record<string, unknown>;

    await db.collection("users")
        .doc(uid)
        .collection("presence_preferences")
        .doc("main")
        .set({
            quietModeEnabled: data.quietModeEnabled === true,
            worshipAwareSuppression: data.worshipAwareSuppression !== false,
            travelAwareSuppression: data.travelAwareSuppression !== false,
            sensitivityLevel: typeof data.sensitivityLevel === "string" ? data.sensitivityLevel : "balanced",
            enabledSignals: Array.isArray(data.enabledSignals) ? data.enabledSignals : [],
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

    return {success: true};
});

export const generatePresenceSignals = onCall({region: "us-central1", enforceAppCheck: true}, async (request) => {
    const uid = requireAuth(request);
    const now = Date.now();

    const signals = [
        {
            id: `saved_church_${now}`,
            type: "serviceStartingSoon",
            title: "Saved church starts service soon.",
            detail: "Notification confidence is high enough to surface calmly.",
            confidence: 0.82,
            confidenceLevel: "high",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {
            id: `study_${now}`,
            type: "bibleStudyTonight",
            title: "Bible study tonight near your location.",
            detail: "Travel-aware suppression should be applied client-side.",
            confidence: 0.74,
            confidenceLevel: "high",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    ];

    const batch = db.batch();
    signals.forEach((signal) => {
        const ref = db.collection("users").doc(uid).collection("presence_signals").doc(signal.id);
        batch.set(ref, signal, {merge: true});
    });
    await batch.commit();

    return {success: true, signals};
});
