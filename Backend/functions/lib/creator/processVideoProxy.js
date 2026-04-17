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
exports.processVideoProxy = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const ffmpegUtils_1 = require("./ffmpegUtils");
exports.processVideoProxy = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
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
    const localInput = await (0, ffmpegUtils_1.downloadToTmp)(sourceStoragePath);
    const localOutput = path.join(os.tmpdir(), `${path.basename(outputStoragePath)}`);
    try {
        await (0, ffmpegUtils_1.createProxyVideo)(localInput, localOutput);
        await (0, ffmpegUtils_1.uploadFromTmp)(localOutput, outputStoragePath);
        const proxyURL = (await admin.storage().bucket().file(outputStoragePath).getSignedUrl({ action: "read", expires: "03-01-2500" }))[0];
        await jobRef.set({ status: "completed", progress: 1, outputRefs: [proxyURL], outputStoragePath: outputStoragePath }, { merge: true });
    }
    finally {
        (0, ffmpegUtils_1.cleanupTmp)(localInput);
        (0, ffmpegUtils_1.cleanupTmp)(localOutput);
    }
    return { ok: true };
});
//# sourceMappingURL=processVideoProxy.js.map