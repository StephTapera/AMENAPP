import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CreatorProjectPayload } from "./creatorTypes";

export const createProject = onCall({ enforceAppCheck: true }, async (request) => {
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

    const title = String(data?.title ?? "Untitled Project");
    const projectType = String(data?.projectType ?? "flyer");
    const ownerID = context.auth.uid;

    const projectRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorProjects")
        .doc();

    const payload: CreatorProjectPayload = {
        id: projectRef.id,
        ownerID,
        title,
        projectType,
        status: "draft",
        visibility: "private",
        aspectRatio: "portrait",
        assetIDs: [],
        layerIDs: [],
        sceneIDs: [],
        subtitleTrackIDs: [],
        outputVariants: [],
        publishTargets: [],
        autosaveVersion: 0,
        lastEditedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    };

    await projectRef.set(payload, { merge: true });

    return { ok: true, projectID: projectRef.id };
});
