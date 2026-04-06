import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const cleanupOrphanedAssets = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
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
