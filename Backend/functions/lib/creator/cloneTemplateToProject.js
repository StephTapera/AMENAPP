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
exports.cloneTemplateToProject = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
exports.cloneTemplateToProject = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
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
//# sourceMappingURL=cloneTemplateToProject.js.map