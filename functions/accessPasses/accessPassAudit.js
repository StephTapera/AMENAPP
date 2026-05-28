"use strict";
// accessPassAudit.ts — Audit event logging for Access Passes
//
// Privacy-safe: never logs prayer content, message bodies, note text, tokens, or tokenHash.
// Logs only broad reason codes, target type, platform, and pass IDs.
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
exports.logAccessPassEvent = logAccessPassEvent;
exports.logResolved = logResolved;
exports.logJoined = logJoined;
exports.logRequested = logRequested;
exports.logCheckedIn = logCheckedIn;
exports.logPreviewed = logPreviewed;
exports.logDenied = logDenied;
exports.logRevoked = logRevoked;
exports.logRateLimited = logRateLimited;
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
async function logAccessPassEvent(event) {
    const eventId = db
        .collection("accessPasses")
        .doc(event.accessPassId)
        .collection("events")
        .doc().id;
    const record = {
        ...event,
        eventId,
        createdAt: admin.firestore.Timestamp.now(),
    };
    await db
        .collection("accessPasses")
        .doc(event.accessPassId)
        .collection("events")
        .doc(eventId)
        .set(record);
}
async function logResolved(accessPassId, targetType, targetId, uid, anonymousSessionId, devicePlatform, appVersion) {
    await logAccessPassEvent({
        type: "resolved",
        accessPassId,
        targetType,
        targetId,
        uid,
        anonymousSessionId,
        devicePlatform: devicePlatform,
        appVersion,
    });
}
async function logJoined(accessPassId, targetType, targetId, uid) {
    await logAccessPassEvent({ type: "joined", accessPassId, targetType, targetId, uid });
}
async function logRequested(accessPassId, targetType, targetId, uid) {
    await logAccessPassEvent({ type: "requested", accessPassId, targetType, targetId, uid });
}
async function logCheckedIn(accessPassId, targetType, targetId, uid) {
    await logAccessPassEvent({ type: "checkedIn", accessPassId, targetType, targetId, uid });
}
async function logPreviewed(accessPassId, targetType, targetId, uid) {
    await logAccessPassEvent({ type: "previewed", accessPassId, targetType, targetId, uid });
}
async function logDenied(accessPassId, targetType, targetId, uid, reason) {
    await logAccessPassEvent({ type: "denied", accessPassId, targetType, targetId, uid, reason });
}
async function logRevoked(accessPassId, targetType, targetId, uid, reason) {
    await logAccessPassEvent({ type: "revoked", accessPassId, targetType, targetId, uid, reason });
}
async function logRateLimited(accessPassId, targetType, targetId, uid) {
    await logAccessPassEvent({ type: "rateLimited", accessPassId, targetType, targetId, uid });
}
//# sourceMappingURL=accessPassAudit.js.map