import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const saveBrandKit = onCall({ enforceAppCheck: true }, async (request) => {
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
    const kit = data?.kit ?? {};
    const kitID = String(kit?.id ?? admin.firestore().collection("_tmp").doc().id);

    const kitRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorBrandKits")
        .doc(kitID);

    await kitRef.set({
        ...kit,
        id: kitID,
        ownerID,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { ok: true, brandKitID: kitID };
});
