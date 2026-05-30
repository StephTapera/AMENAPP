import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import { cleanupTmp, createThumbnailImage, downloadToTmp, uploadFromTmp } from "./ffmpegUtils";

export const generateThumbnail = functions.https.onCall(async (data, context) => {
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
    const jobID = String(data?.jobID ?? "");
    const sourceStoragePath = String(data?.sourceStoragePath ?? "");
    const outputStoragePath = String(data?.outputStoragePath ?? "");

    if (!jobID || !sourceStoragePath || !outputStoragePath) {
        throw new functions.https.HttpsError("invalid-argument", "Missing jobID or storage paths");
    }

    const jobRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorJobs")
        .doc(jobID);

    await jobRef.set({ status: "running", progress: 0.2 }, { merge: true });

    const localInput = await downloadToTmp(sourceStoragePath);
    const localOutput = path.join(os.tmpdir(), `${path.basename(outputStoragePath)}`);

    try {
        await createThumbnailImage(localInput, localOutput);
        await uploadFromTmp(localOutput, outputStoragePath);
        // SECURITY (H-04): short-lived signed URL (7 days). The previous value of
        // "03-01-2500" produced a ~475-year URL that would remain valid indefinitely
        // even after the creator's account or the underlying file is removed.
        const sevenDaysMs = Date.now() + 7 * 24 * 60 * 60 * 1000;
        const thumbnailURL = (await admin.storage().bucket().file(outputStoragePath).getSignedUrl({ action: "read", expires: sevenDaysMs }))[0];
        await jobRef.set(
            { status: "completed", progress: 1, outputRefs: [thumbnailURL], outputStoragePath: outputStoragePath },
            { merge: true }
        );
    } finally {
        cleanupTmp(localInput);
        cleanupTmp(localOutput);
    }

    return { ok: true };
});
