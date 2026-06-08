import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const autosaveProject = onCall(async (request) => {
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
    const projectID = String(data?.projectID ?? "");
    const draft = data?.draft ?? {};
    const autosaveVersion = Number(data?.autosaveVersion ?? 0);

    if (!projectID) {
        throw new HttpsError("invalid-argument", "Missing projectID");
    }

    const draftRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorDrafts")
        .doc(projectID);

    await draftRef.set(
        {
            projectID,
            autosaveVersion,
            draft,
            lastEditedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        { merge: true }
    );

    return { ok: true };
});
