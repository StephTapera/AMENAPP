"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteProject = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
exports.deleteProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
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
        await Promise.all(files.map(f => f.delete().catch((err) => {
            console.warn(`[deleteProject] Storage delete skipped for ${f.name}: ${err.message}`);
        })));
    }
    catch (err) {
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
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[deleteProject] Job subcollection cleanup error: ${msg}`);
    }
    await projectRef.delete();
    return { ok: true };
});
//# sourceMappingURL=deleteProject.js.map