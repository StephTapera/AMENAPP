import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const moderateCreatorAsset = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const assetID = String(data?.assetID ?? "");

    if (!assetID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing assetID");
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
