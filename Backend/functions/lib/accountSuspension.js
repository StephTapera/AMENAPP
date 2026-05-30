"use strict";
/**
 * accountSuspension.ts
 *
 * Server-side account suspension via Firebase Auth.
 *
 * WHY THIS EXISTS (HIGH-2 from Trust/Safety Audit):
 *   handleHarassmentPattern() in the Swift client applies Firestore-based restrictions
 *   (commenting freeze, DM freeze) at the CRITICAL harassment tier, but never calls
 *   Firebase Auth disableUser(). A suspended-at-Firestore-level user can:
 *     - Continue signing in (Firebase Auth still issues tokens)
 *     - Access their account through the REST API or alternate clients
 *     - Circumvent Firestore restrictions by using an alternate SDK path
 *
 *   Firebase Auth account disablement must be performed via the Admin SDK
 *   (server-side). This file provides:
 *     1. A Firestore onCreate trigger on moderationQueue that automatically
 *        suspends accounts when a "critical_harassment" or "minor_safety_pattern"
 *        queue item is created.
 *     2. A callable function for admin-initiated manual suspension/restoration.
 *
 * SUSPENSION BEHAVIOR:
 *   - Firebase Auth: user.disabled = true  → prevents all future sign-ins
 *   - users/{uid}.accountStatus = "suspended"  → client-readable status for UX
 *   - suspensionLog/{uid} is created for audit trail + appeal reference
 *   - A notification is written to the user's subcollection explaining the suspension
 *
 * RESTORATION:
 *   The callable `restoreAccount` re-enables Auth and removes the accountStatus flag.
 *   Only callable by admins (requires "admin" custom claim).
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
exports.restoreAccount = exports.suspendAccount = exports.autoSuspendOnCriticalPattern = void 0;
const functions = __importStar(require("firebase-functions"));
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
const auth = admin.auth();
// ─── Core Logic ──────────────────────────────────────────────────────────────
/**
 * Disables the Firebase Auth account and writes a suspension record.
 * Idempotent: if the user is already disabled, the record is updated without error.
 */
async function suspendUser(uid, reason, triggeredBy, triggerType) {
    // 1. Disable in Firebase Auth — prevents all future sign-ins.
    await auth.updateUser(uid, { disabled: true });
    // Revoke all refresh tokens so active sessions cannot obtain new ID tokens.
    // Without this, a suspended user stays active until their current token expires (≤1 hour).
    await auth.revokeRefreshTokens(uid).catch((err) => {
        functions.logger.warn(`[AccountSuspension] Token revocation failed for ${uid}:`, err);
    });
    // 2. Write accountStatus to the user document so clients can show UX.
    await db.collection("users").doc(uid).set({
        accountStatus: "suspended",
        accountSuspendedAt: admin.firestore.FieldValue.serverTimestamp(),
        accountSuspensionReason: reason,
    }, { merge: true });
    // 3. Create suspension log entry for audit trail.
    const record = {
        uid,
        reason,
        triggeredBy,
        triggerType,
        suspendedAt: admin.firestore.FieldValue.serverTimestamp(),
        policyVersion: "2026-03-06",
    };
    await db.collection("suspensionLog").doc(uid).set(record, { merge: true });
    // 4. Notify the suspended user (shown on next login attempt via accountStatus check).
    await db
        .collection("users")
        .doc(uid)
        .collection("notifications")
        .add({
        type: "system_account_suspended",
        userId: uid,
        toUserId: uid,
        title: "Account Suspended",
        body: "Your account has been suspended due to a violation of our community guidelines. " +
            "You may appeal this decision from the Settings screen.",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { reason, triggerType },
    });
    functions.logger.warn(`[AccountSuspension] Suspended uid=${uid} reason="${reason}" triggerType=${triggerType}`);
}
// ─── Firestore Trigger ────────────────────────────────────────────────────────
/**
 * Firestore onCreate trigger: autoSuspendOnCriticalPattern
 *
 * Fires when a document is added to the moderationQueue collection.
 * If the document type is "critical_harassment_pattern" or "minor_safety_pattern"
 * with priority="high" or priority="immediate", the offender's account is automatically
 * suspended in Firebase Auth.
 *
 * This closes the loop that AntiHarassmentEngine's handleHarassmentPattern() opens —
 * Firestore-level restrictions are applied client-side, but Auth suspension
 * requires server-side execution.
 */
exports.autoSuspendOnCriticalPattern = (0, firestore_1.onDocumentCreated)("moderationQueue/{queueId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    if (!data)
        return;
    const queueType = data.type ?? "";
    const priority = data.priority ?? "";
    const offenderId = data.offenderId ?? "";
    if (!offenderId) {
        v2_1.logger.warn(`[AccountSuspension] moderationQueue/${snap.id} missing offenderId — skipping.`);
        return;
    }
    // Only auto-suspend for the highest-severity queue types.
    const isAutoSuspendable = (queueType === "minor_safety_pattern" && priority === "immediate") ||
        (queueType === "critical_harassment_pattern" && priority === "high");
    if (!isAutoSuspendable) {
        return;
    }
    // Check if already suspended to keep the trigger idempotent.
    try {
        const userRecord = await auth.getUser(offenderId);
        if (userRecord.disabled) {
            v2_1.logger.info(`[AccountSuspension] uid=${offenderId} already suspended — skipping.`);
            return;
        }
    }
    catch (err) {
        v2_1.logger.error(`[AccountSuspension] Could not fetch Auth record for uid=${offenderId}`, err);
        return;
    }
    const reason = queueType === "minor_safety_pattern"
        ? "Minor safety violation — account suspended pending human review"
        : "Critical harassment pattern — account suspended pending human review";
    await suspendUser(offenderId, reason, "server_trigger", queueType);
    await snap.ref.update({
        autoSuspensionApplied: true,
        autoSuspendedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
});
// ─── Callable: Manual Suspension ─────────────────────────────────────────────
/**
 * Callable function: suspendAccount
 *
 * Allows admin users to manually suspend an account.
 * Requires the "admin" custom claim.
 *
 * Input:  { uid: string, reason: string }
 * Output: { success: boolean }
 */
exports.suspendAccount = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!context.auth.token.admin) {
        throw new functions.https.HttpsError("permission-denied", "Only admins can suspend accounts");
    }
    const uid = data.uid ?? "";
    const reason = (data.reason ?? "Manual suspension by admin").trim();
    if (!uid) {
        throw new functions.https.HttpsError("invalid-argument", "uid is required");
    }
    if (reason.length < 5 || reason.length > 500) {
        throw new functions.https.HttpsError("invalid-argument", "reason must be between 5 and 500 characters");
    }
    await suspendUser(uid, reason, `admin:${context.auth.uid}`, "manual");
    return { success: true };
});
// ─── Callable: Restore Account ────────────────────────────────────────────────
/**
 * Callable function: restoreAccount
 *
 * Re-enables a suspended account and removes the accountStatus flag.
 * Requires the "admin" custom claim.
 *
 * Input:  { uid: string, reason: string }
 * Output: { success: boolean }
 */
exports.restoreAccount = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!context.auth.token.admin) {
        throw new functions.https.HttpsError("permission-denied", "Only admins can restore accounts");
    }
    const uid = data.uid ?? "";
    const reason = (data.reason ?? "Account reinstated by admin").trim();
    if (!uid) {
        throw new functions.https.HttpsError("invalid-argument", "uid is required");
    }
    // Re-enable in Firebase Auth.
    await auth.updateUser(uid, { disabled: false });
    // Remove suspension status from user document.
    await db.collection("users").doc(uid).set({
        accountStatus: "active",
        accountReinstatedAt: admin.firestore.FieldValue.serverTimestamp(),
        accountSuspensionReason: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    // Update suspension log.
    await db.collection("suspensionLog").doc(uid).set({
        reinstatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reinstatedBy: `admin:${context.auth.uid}`,
        reinstatementReason: reason,
    }, { merge: true });
    // Notify user of reinstatement.
    await db
        .collection("users")
        .doc(uid)
        .collection("notifications")
        .add({
        type: "system_account_reinstated",
        userId: uid,
        toUserId: uid,
        title: "Account Reinstated",
        body: "Your account has been reinstated. Welcome back to AMEN.",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { reason },
    });
    functions.logger.info(`[AccountSuspension] Restored uid=${uid} by admin ${context.auth.uid}`);
    return { success: true };
});
//# sourceMappingURL=accountSuspension.js.map