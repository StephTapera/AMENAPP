import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const verifyAuthenticitySignals = functions.https.onCall(async (data, context) => {
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
    const projectID = String(data?.projectID ?? "");

    if (!projectID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing projectID");
    }

    const projectRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorProjects")
        .doc(projectID);

    // TODO: add authenticity signal checks.
    await projectRef.set({ authenticityStatus: "verified" }, { merge: true });

    return { ok: true };
});
