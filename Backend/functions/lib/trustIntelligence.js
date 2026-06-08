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
exports.writeTrustSnapshot = exports.writeTrustEvent = exports.writeAgentExecutionLog = exports.writeAgentRecommendation = exports.writeAgentInsight = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
function requireAuth(context) {
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Auth required");
    }
    return context.auth.uid;
}
function requireAppCheck(context) {
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
}
function assertOwner(uid, userId) {
    if (uid !== userId) {
        throw new https_1.HttpsError("permission-denied", "User mismatch");
    }
}
exports.writeAgentInsight = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);
    const insightId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: insightId,
        agentType: String(data?.agentType ?? "berean"),
        title: String(data?.title ?? ""),
        detail: String(data?.detail ?? ""),
        confidence: Number(data?.confidence ?? 0),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(userId)
        .collection("agentInsights")
        .doc(insightId)
        .set(payload, { merge: true });
    return { ok: true, id: insightId };
});
exports.writeAgentRecommendation = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);
    const recId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: recId,
        agentType: String(data?.agentType ?? "berean"),
        recommendation: String(data?.recommendation ?? ""),
        confidence: Number(data?.confidence ?? 0),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(userId)
        .collection("agentRecommendations")
        .doc(recId)
        .set(payload, { merge: true });
    return { ok: true, id: recId };
});
exports.writeAgentExecutionLog = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);
    const logId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: logId,
        agentType: String(data?.agentType ?? "berean"),
        summary: String(data?.summary ?? ""),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(userId)
        .collection("executionLogs")
        .doc(logId)
        .set(payload, { merge: true });
    return { ok: true, id: logId };
});
exports.writeTrustEvent = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);
    const eventId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: eventId,
        userId,
        type: String(data?.type ?? "messageSent"),
        metadata: data?.metadata ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(userId)
        .collection("trustEvents")
        .doc(eventId)
        .set(payload, { merge: true });
    return { ok: true, id: eventId };
});
exports.writeTrustSnapshot = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);
    const userId = String(data?.userId ?? uid);
    assertOwner(uid, userId);
    const snapshotId = String(data?.id ?? db.collection("_ids").doc().id);
    const payload = {
        id: snapshotId,
        userId,
        humanScore: data?.humanScore ?? null,
        careScore: data?.careScore ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(userId)
        .collection("trustSnapshots")
        .doc(snapshotId)
        .set(payload, { merge: true });
    return { ok: true, id: snapshotId };
});
//# sourceMappingURL=trustIntelligence.js.map