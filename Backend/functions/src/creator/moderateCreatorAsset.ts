import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const moderateCreatorAsset = onCall(async (request) => {
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
    const assetID = String(data?.assetID ?? "");

    if (!assetID) {
        throw new HttpsError("invalid-argument", "Missing assetID");
    }

    const assetRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorAssets")
        .doc(assetID);

    await assetRef.set({ moderationStatus: "pending" }, { merge: true });

    // TODO: integrate moderation pipeline.
    await assetRef.set({ moderationStatus: "approved" }, { merge: true });

    return { ok: true };
});
