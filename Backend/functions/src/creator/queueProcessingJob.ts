import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { CreatorJobPayload } from "./creatorTypes";

export const queueProcessingJob = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const projectID = String(data?.projectID ?? "");
    const type = String(data?.type ?? "");

    if (!projectID || !type) {
        throw new functions.https.HttpsError("invalid-argument", "Missing projectID or type");
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
