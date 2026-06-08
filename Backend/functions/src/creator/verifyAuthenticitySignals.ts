import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const verifyAuthenticitySignals = onCall(async (request) => {
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

    if (!projectID) {
        throw new HttpsError("invalid-argument", "Missing projectID");
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
