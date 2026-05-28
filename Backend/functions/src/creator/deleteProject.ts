import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const deleteProject = functions.https.onCall(async (data, context) => {
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

    // Delete all Cloud Storage files for this project
    try {
        const bucket = admin.storage().bucket();
        const prefix = `creator_studio/${ownerID}/${projectID}/`;
        const [files] = await bucket.getFiles({ prefix });
        await Promise.all(files.map(f => f.delete().catch((err: Error) => {
            console.warn(`[deleteProject] Storage delete skipped for ${f.name}: ${err.message}`);
        })));
    } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[deleteProject] Storage cleanup error for project ${projectID}: ${msg}`);
        // Non-fatal — continue to remove the Firestore record
    }

    // Delete any creator job subcollection entries
    try {
        const jobsSnap = await projectRef.collection("creatorJobs").get();
        if (!jobsSnap.empty) {
            const batch = admin.firestore().batch();
            jobsSnap.docs.forEach(d => batch.delete(d.ref));
            await batch.commit();
        }
    } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[deleteProject] Job subcollection cleanup error: ${msg}`);
    }

    await projectRef.delete();

    return { ok: true };
});
