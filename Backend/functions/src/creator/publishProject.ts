import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const publishProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const projectID = String(data?.projectID ?? "");

    if (!projectID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing projectID");
    }

    const projectRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorProjects")
        .doc(projectID);

    await projectRef.set({ status: "published", publishedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    return { ok: true, progress: 1 };
});
