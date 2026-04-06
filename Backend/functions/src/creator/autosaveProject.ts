import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const autosaveProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const projectID = String(data?.projectID ?? "");
    const draft = data?.draft ?? {};
    const autosaveVersion = Number(data?.autosaveVersion ?? 0);

    if (!projectID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing projectID");
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
