import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const translateSubtitleTrack = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const jobID = String(data?.jobID ?? "");

    if (!jobID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing jobID");
    }

    const jobRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorJobs")
        .doc(jobID);

    await jobRef.set({ status: "running", progress: 0.2 }, { merge: true });
    await jobRef.set({ status: "completed", progress: 1 }, { merge: true });

    return { ok: true };
});
