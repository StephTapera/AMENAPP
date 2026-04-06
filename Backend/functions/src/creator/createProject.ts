import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { CreatorProjectPayload } from "./creatorTypes";

export const createProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
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
