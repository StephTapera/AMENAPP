"use strict";
/**
 * usernameChangeTracking.ts
 *
 * Section-13 FIX: Username change rate limiting (30-day cooldown).
 *
 * PROBLEM:
 *   Users can change their username repeatedly, enabling impersonation attacks
 *   and making harassment harder to trace.
 *
 * SOLUTION:
 *   1. trackUsernameChange (Firestore onUpdate trigger on users/{uid}):
 *      When a user document's `username` field changes, writes to
 *      userSafetyRecords/{uid}:
 *        • usernameChangedAt:  server timestamp of the change
 *        • canChangeUsername:  false  (locks out further changes)
 *        • previousUsername:   the old username (audit trail)
 *
 *   2. usernameChangeCooldownRelease (daily scheduled, in scheduledMaintenance.ts):
 *      Finds all userSafetyRecords where canChangeUsername == false AND
 *      usernameChangeCooldownUntil <= now, and sets canChangeUsername: true.
 *
 *   3. Firestore rule (users/{userId} allow update):
 *      Already reads userSafetyRecords/{uid}.canChangeUsername. The existing
 *      check prevents username writes when canChangeUsername == false.
 *
 * Uses gen2 Firestore trigger syntax to coexist with other gen2 triggers.
 */
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
exports.trackUsernameChange = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
/** Cooldown duration in milliseconds (30 days). */
const USERNAME_COOLDOWN_MS = 30 * 24 * 60 * 60 * 1000;
// ─── Trigger: record username change ─────────────────────────────────────────
exports.trackUsernameChange = (0, firestore_1.onDocumentUpdated)("users/{uid}", async (event) => {
    const { uid } = event.params;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    // Only act when username actually changed.
    if (before.username === after.username)
        return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const cooldownUntilMs = Date.now() + USERNAME_COOLDOWN_MS;
    v2_1.logger.info(`[trackUsernameChange] User ${uid} changed username ` +
        `"${before.username}" → "${after.username}" — locking for 30 days.`);
    await db.collection("userSafetyRecords").doc(uid).set({
        canChangeUsername: false,
        usernameChangedAt: now,
        usernameChangeCooldownUntil: admin.firestore.Timestamp.fromMillis(cooldownUntilMs),
        previousUsername: before.username ?? null,
        usernameChangeHistory: admin.firestore.FieldValue.arrayUnion({
            from: before.username ?? null,
            to: after.username ?? null,
            changedAt: admin.firestore.Timestamp.fromMillis(Date.now()),
        }),
    }, { merge: true });
});
//# sourceMappingURL=usernameChangeTracking.js.map