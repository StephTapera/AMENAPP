import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const cleanupOrphanedAssets = functions.https.onCall(async (data, context) => {
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
    const assetIDs: string[] = data?.assetIDs ?? [];

    const batch = admin.firestore().batch();
    for (const assetID of assetIDs) {
        const assetRef = admin.firestore()
            .collection("users")
            .doc(ownerID)
            .collection("creatorAssets")
            .doc(assetID);
        batch.delete(assetRef);
    }

    await batch.commit();

    return { ok: true, deleted: assetIDs.length };
});
