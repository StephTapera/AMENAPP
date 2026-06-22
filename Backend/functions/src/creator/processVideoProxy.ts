import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import { cleanupTmp, createProxyVideo, downloadToTmp, uploadFromTmp } from "./ffmpegUtils";

export const processVideoProxy = onCall({ enforceAppCheck: true }, async (request) => {
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
    const sourceStoragePath = String(data?.sourceStoragePath ?? "");
    const outputStoragePath = String(data?.outputStoragePath ?? "");

    if (!jobID || !sourceStoragePath || !outputStoragePath) {
        throw new HttpsError("invalid-argument", "Missing jobID or storage paths");
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
        await createProxyVideo(localInput, localOutput);
        await uploadFromTmp(localOutput, outputStoragePath);
        const proxyURL = (await admin.storage().bucket().file(outputStoragePath).getSignedUrl({
            action: "read",
            expires: Date.now() + 60 * 60 * 1000,
        }))[0];
        await jobRef.set(
            { status: "completed", progress: 1, outputRefs: [proxyURL], outputStoragePath: outputStoragePath },
            { merge: true }
        );
    } finally {
        cleanupTmp(localInput);
        cleanupTmp(localOutput);
    }

    return { ok: true };
});
