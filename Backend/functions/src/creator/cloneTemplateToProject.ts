import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

export const cloneTemplateToProject = onCall({ enforceAppCheck: true }, async (request) => {
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
    const templateID = String(data?.templateID ?? "");

    if (!templateID) {
        throw new HttpsError("invalid-argument", "Missing templateID");
    }

    const templateRef = admin.firestore().collection("creatorTemplates").doc(templateID);
    const templateSnap = await templateRef.get();

    if (!templateSnap.exists) {
        throw new HttpsError("not-found", "Template not found");
    }

    const projectRef = admin.firestore()
        .collection("users")
        .doc(ownerID)
        .collection("creatorProjects")
        .doc();

    await projectRef.set({
        ...templateSnap.data(),
        id: projectRef.id,
        ownerID,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastEditedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "draft"
    }, { merge: true });

    return { ok: true, projectID: projectRef.id };
});
