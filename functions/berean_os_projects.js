// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Projects Engine Cloud Functions
 * bereanCreateProject, bereanArchiveProject, bereanUpdateProject
 *
 * Deploy: firebase deploy --only functions:bereanCreateProject,bereanArchiveProject,bereanUpdateProject
 *         --project amen-5e359
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";
const PROJECT_LIMIT = 20;

exports.bereanCreateProject = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;

    // Rate limit: max 20 active projects per user
    const existing = await admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects")
      .where("isArchived", "==", false)
      .count()
      .get();
    if (existing.data().count >= PROJECT_LIMIT) {
      throw new HttpsError("resource-exhausted", `Maximum ${PROJECT_LIMIT} active projects reached.`);
    }

    const { title, description, projectType, visibility } = request.data;
    if (!title || typeof title !== "string" || title.trim().length === 0) {
      throw new HttpsError("invalid-argument", "title is required.");
    }
    if (title.length > 120) {
      throw new HttpsError("invalid-argument", "title must be ≤ 120 characters.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const projectRef = admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc();

    const project = {
      id: projectRef.id,
      title: title.trim(),
      description: description || "",
      projectType: projectType || "personal",
      visibility: visibility || "private",
      ownerUid: uid,
      contributorUids: [uid],
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    };

    await projectRef.set(project);
    return { projectId: projectRef.id };
  }
);

exports.bereanArchiveProject = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { projectId } = request.data;

    if (!projectId) throw new HttpsError("invalid-argument", "projectId is required.");

    const ref = admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc(projectId);
    const doc = await ref.get();

    if (!doc.exists) throw new HttpsError("not-found", "Project not found.");
    if (doc.data().ownerUid !== uid) throw new HttpsError("permission-denied", "Only the owner can archive this project.");

    await ref.update({ isArchived: true, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { success: true };
  }
);

exports.bereanUpdateProject = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { projectId, title, description, visibility } = request.data;

    if (!projectId) throw new HttpsError("invalid-argument", "projectId is required.");

    const ref = admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc(projectId);
    const doc = await ref.get();

    if (!doc.exists) throw new HttpsError("not-found", "Project not found.");
    if (doc.data().ownerUid !== uid) throw new HttpsError("permission-denied", "Only the owner can update this project.");

    const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (title && typeof title === "string" && title.trim().length > 0) {
      if (title.length > 120) throw new HttpsError("invalid-argument", "title must be ≤ 120 characters.");
      updates.title = title.trim();
    }
    if (description !== undefined) updates.description = description;
    if (visibility) updates.visibility = visibility;

    await ref.update(updates);
    return { success: true };
  }
);
