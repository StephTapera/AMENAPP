"use strict";
// accessPassRateLimit.ts — Rate limiting for Access Pass operations
//
// Stored in Firestore rateLimits collection.
// Short windows protect against scan abuse and brute force.
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
exports.enforceRateLimit = enforceRateLimit;
exports.recordInvalidTokenAttempt = recordInvalidTokenAttempt;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const db = admin.firestore();
const WINDOWS = {
    resolve: { maxRequests: 10, windowMs: 60000 }, // 10 resolves/min per identity
    accept: { maxRequests: 5, windowMs: 60000 }, // 5 accepts/min per identity
    invalidToken: { maxRequests: 5, windowMs: 300000 }, // 5 invalid attempts/5min per identity
};
/**
 * Check and increment the rate limit counter for an operation.
 * Identity is uid if authenticated, else anonymousSessionId.
 * Throws HttpsError("resource-exhausted") if limit exceeded.
 */
async function enforceRateLimit(operation, identity) {
    const { maxRequests, windowMs } = WINDOWS[operation];
    const now = Date.now();
    const windowStart = now - windowMs;
    const docId = `${operation}:${identity}`;
    const ref = db.collection("rateLimits").doc(docId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.data() ?? { timestamps: [] };
        // Prune old timestamps outside window
        const recent = data.timestamps.filter((ts) => ts > windowStart);
        if (recent.length >= maxRequests) {
            throw new functions.https.HttpsError("resource-exhausted", "rate-limited");
        }
        recent.push(now);
        tx.set(ref, { timestamps: recent, updatedAt: admin.firestore.Timestamp.now() });
    });
}
/** Increment invalid token counter and check abuse threshold. */
async function recordInvalidTokenAttempt(identity) {
    await enforceRateLimit("invalidToken", identity);
}
//# sourceMappingURL=accessPassRateLimit.js.map