import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const cloneTemplateToProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const ownerID = context.auth.uid;
    const templateID = String(data?.templateID ?? "");

    if (!templateID) {
        throw new functions.https.HttpsError("invalid-argument", "Missing templateID");
    }

    const templateRef = admin.firestore().collection("creatorTemplates").doc(templateID);
    const templateSnap = await templateRef.get();

    if (!templateSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Template not found");
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
