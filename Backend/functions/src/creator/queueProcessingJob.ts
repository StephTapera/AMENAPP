import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CreatorJobPayload } from "./creatorTypes";

export const queueProcessingJob = onCall({ enforceAppCheck: true }, async (request) => {
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
    const type = String(data?.type ?? "");

    if (!projectID || !type) {
        throw new HttpsError("invalid-argument", "Missing projectID or type");
    }

    const jobRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorJobs")
        .doc();

    const payload: CreatorJobPayload = {
        id: jobRef.id,
        projectID,
        ownerID,
        type,
        status: "queued",
        progress: 0,
        inputRefs: data?.inputRefs ?? [],
        outputRefs: [],
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    };

    await jobRef.set(payload, { merge: true });

    return { ok: true, jobID: jobRef.id };
});
