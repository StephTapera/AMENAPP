import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const cleanupOrphanedAssets = onCall({ enforceAppCheck: true }, async (request) => {
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
