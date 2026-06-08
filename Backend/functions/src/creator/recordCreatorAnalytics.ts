import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const recordCreatorAnalytics = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Auth required");
    }

    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const ownerID = context.auth.uid;
    const dayKey = String(data?.dayKey ?? "");
    const event = String(data?.event ?? "");

    if (!dayKey || !event) {
        throw new HttpsError("invalid-argument", "Missing dayKey or event");
    }

    const docRef = admin.firestore().collection("creatorUsageAnalytics").doc(dayKey);

    await docRef.set({
        dayKey,
        lastEvent: event,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { ok: true };
});
