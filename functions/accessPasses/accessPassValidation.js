"use strict";
// accessPassValidation.ts — Pass status and eligibility validation
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
exports.loadAndValidatePass = loadAndValidatePass;
exports.validateModeForTarget = validateModeForTarget;
exports.checkMaxUsesPerUser = checkMaxUsesPerUser;
exports.checkMaxUses = checkMaxUses;
exports.verifyRoleGatedEligibility = verifyRoleGatedEligibility;
exports.checkIfAlreadyMember = checkIfAlreadyMember;
exports.checkIfRequestPending = checkIfRequestPending;
const admin = __importStar(require("firebase-admin"));
const accessPassTypes_1 = require("./accessPassTypes");
const accessPassToken_1 = require("./accessPassToken");
const functions = __importStar(require("firebase-functions"));
const db = admin.firestore();
/**
 * Load and validate an access pass by ID.
 * Throws HttpsError with the appropriate code and a safe error code in message.
 */
async function loadAndValidatePass(accessPassId, rawToken) {
    const passRef = db.collection("accessPasses").doc(accessPassId);
    const passSnap = await passRef.get();
    if (!passSnap.exists) {
        throw new functions.https.HttpsError("not-found", "invalid-pass");
    }
    const pass = passSnap.data();
    // Verify token before checking status (fail-safe ordering)
    if (!(0, accessPassToken_1.verifyToken)(rawToken, pass.tokenHash)) {
        throw new functions.https.HttpsError("permission-denied", "invalid-pass");
    }
    const now = admin.firestore.Timestamp.now();
    // Check status
    if (pass.status === "revoked") {
        throw new functions.https.HttpsError("permission-denied", "revoked");
    }
    if (pass.status === "expired") {
        throw new functions.https.HttpsError("permission-denied", "expired");
    }
    if (pass.status === "paused") {
        throw new functions.https.HttpsError("unavailable", "paused");
    }
    // Check time windows
    if (pass.startsAt && pass.startsAt.toMillis() > now.toMillis()) {
        throw new functions.https.HttpsError("failed-precondition", "not-started");
    }
    if (pass.expiresAt && pass.expiresAt.toMillis() < now.toMillis()) {
        // Auto-mark expired
        await passRef.update({ status: "expired", "audit.updatedAt": now });
        throw new functions.https.HttpsError("permission-denied", "expired");
    }
    return pass;
}
/** Check if mode is allowed for a given target type (sensitive space protection). */
function validateModeForTarget(mode, targetType, isSensitive) {
    if (mode === "join" && accessPassTypes_1.RESTRICTED_DIRECT_JOIN_TYPES.includes(targetType)) {
        throw new functions.https.HttpsError("failed-precondition", "sensitive-direct-join-blocked");
    }
    if (mode === "join" && isSensitive) {
        throw new functions.https.HttpsError("failed-precondition", "sensitive-direct-join-blocked");
    }
}
/** Check per-user usage limits. */
async function checkMaxUsesPerUser(pass, uid) {
    if (!pass.maxUsesPerUser || pass.maxUsesPerUser <= 0)
        return;
    const eventsRef = db
        .collection("accessPasses")
        .doc(pass.accessPassId)
        .collection("events");
    const userEventsSnap = await eventsRef
        .where("uid", "==", uid)
        .where("type", "in", ["joined", "checkedIn"])
        .count()
        .get();
    if (userEventsSnap.data().count >= pass.maxUsesPerUser) {
        throw new functions.https.HttpsError("resource-exhausted", "max-uses-per-user-exceeded");
    }
}
/** Check global max uses. Must be called inside a transaction. */
function checkMaxUses(pass) {
    if (pass.maxUses !== undefined && pass.usesCount >= pass.maxUses) {
        throw new functions.https.HttpsError("resource-exhausted", "max-uses-exceeded");
    }
}
/** Verify user eligibility for role-gated passes. */
async function verifyRoleGatedEligibility(pass, uid, userEmail) {
    // Check allowed member UIDs
    if (pass.allowedMemberUids && pass.allowedMemberUids.length > 0) {
        if (!pass.allowedMemberUids.includes(uid)) {
            throw new functions.https.HttpsError("permission-denied", "role-restricted");
        }
        return;
    }
    // Check allowed email domains
    if (pass.allowedEmailDomains && pass.allowedEmailDomains.length > 0 && userEmail) {
        const domain = userEmail.split("@")[1] ?? "";
        if (!pass.allowedEmailDomains.includes(domain)) {
            throw new functions.https.HttpsError("permission-denied", "role-restricted");
        }
        return;
    }
    // Check allowed role IDs
    if (pass.allowedRoleIds && pass.allowedRoleIds.length > 0) {
        // Check user's roles in the target's membership/role collection
        const memberSnap = await db
            .collection(`${pass.targetType}s`)
            .doc(pass.targetId)
            .collection("members")
            .doc(uid)
            .get();
        const memberData = memberSnap.data();
        const userRole = memberData?.role ?? "";
        if (!pass.allowedRoleIds.includes(userRole)) {
            throw new functions.https.HttpsError("permission-denied", "role-restricted");
        }
        return;
    }
    // No restrictions configured — pass is open within role-gated mode
}
/** Check if user is already a member of the target. */
async function checkIfAlreadyMember(targetType, targetId, uid) {
    try {
        const memberRef = db
            .collection(`${targetType}s`)
            .doc(targetId)
            .collection("members")
            .doc(uid);
        const snap = await memberRef.get();
        return snap.exists;
    }
    catch {
        return false;
    }
}
/** Check if user has a pending request for this pass. */
async function checkIfRequestPending(accessPassId, uid) {
    const requestsSnap = await db
        .collection("accessRequests")
        .where("accessPassId", "==", accessPassId)
        .where("requesterUid", "==", uid)
        .where("status", "==", "pending")
        .limit(1)
        .get();
    return !requestsSnap.empty;
}
//# sourceMappingURL=accessPassValidation.js.map