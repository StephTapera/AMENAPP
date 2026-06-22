"use strict";
// resolveContextAccess.ts — Context Engine internal policy resolver (Wave 1: Lane A)
//
// Non-callable module. Called by other server-side functions to gate Capability access.
// Writes one contextAuditLog entry per source per call. Never throws on audit failure.
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
exports.resolveContextAccess = resolveContextAccess;
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const crypto_1 = require("crypto");
// Device-level sources that are not yet supported server-side
const DEVICE_LEVEL_SOURCES = new Set(["calendar", "location"]);
// All valid ContextSource values for default-filling missing grants
const ALL_SOURCES = [
    "calendar",
    "location",
    "contacts",
    "prayerHistory",
    "readingHistory",
    "notesContent",
    "messagesMeta",
    "churchProfile",
];
function resolveDecision(source, policy, invocationType, requestId) {
    // Device-level sources: always denied regardless of stored policy
    if (DEVICE_LEVEL_SOURCES.has(source)) {
        return { source, decision: "denied", reason: "notYetSupported", requestId };
    }
    switch (policy) {
        case "always":
            return { source, decision: "allowed", requestId };
        case "whileUsing":
            if (invocationType === "foreground") {
                return { source, decision: "allowed", requestId };
            }
            return { source, decision: "denied", reason: "backgroundDenied", requestId };
        case "askEveryTime":
            return { source, decision: "promptRequired", requestId };
        case "never":
        default:
            return { source, decision: "denied", reason: "notGranted", requestId };
    }
}
async function resolveContextAccess(input) {
    const { uid, capabilityId, sources, invocationType } = input;
    const db = (0, firestore_1.getFirestore)();
    const requestId = (0, crypto_1.randomUUID)();
    // Fetch all grant docs in parallel
    const grantRefs = sources.map((source) => db.doc(`users/${uid}/contextGrants/${source}`));
    const grantSnaps = await Promise.all(grantRefs.map((ref) => ref.get()));
    const decisions = grantSnaps.map((snap, i) => {
        const source = sources[i];
        // Missing grant → policy defaults to "never"
        const policy = snap.exists
            ? snap.data().policy
            : "never";
        return resolveDecision(source, policy, invocationType, requestId);
    });
    const allAllowed = decisions.every((d) => d.decision === "allowed");
    // Write audit log entries — one per source — using a batch write.
    // Failures are caught and logged; never re-thrown.
    try {
        const now = new Date();
        const batch = db.batch();
        for (const decision of decisions) {
            const logRef = db
                .collection(`users/${uid}/contextAuditLog`)
                .doc(); // auto-ID
            batch.set(logRef, {
                source: decision.source,
                capabilityId,
                decision: decision.decision,
                requestId,
                at: now.toISOString(),
            });
        }
        await batch.commit();
    }
    catch (auditErr) {
        logger.error("[contextEngine] audit log write failed — non-fatal", {
            uid,
            capabilityId,
            requestId,
            error: String(auditErr),
        });
    }
    return { decisions, allAllowed };
}
