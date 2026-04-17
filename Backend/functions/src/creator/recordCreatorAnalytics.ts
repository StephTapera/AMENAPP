import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const recordCreatorAnalytics = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const ownerID = context.auth.uid;
    const dayKey = String(data?.dayKey ?? "");
    const event = String(data?.event ?? "");

    if (!dayKey || !event) {
        throw new functions.https.HttpsError("invalid-argument", "Missing dayKey or event");
    }

    const docRef = admin.firestore().collection("creatorUsageAnalytics").doc(dayKey);

    await docRef.set({
        dayKey,
        lastEvent: event,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { ok: true };
});
