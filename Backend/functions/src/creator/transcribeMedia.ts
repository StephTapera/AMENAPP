import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const transcribeMedia = onCall({ enforceAppCheck: true }, async (request) => {
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
    const jobID = String(data?.jobID ?? "");

    if (!jobID) {
        throw new HttpsError("invalid-argument", "Missing jobID");
    }

    const jobRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorJobs")
        .doc(jobID);

    await jobRef.set({ status: "running", progress: 0.2 }, { merge: true });
    // TODO: call speech-to-text provider and store transcript.
    await jobRef.set({ status: "completed", progress: 1 }, { merge: true });

    return { ok: true };
});
