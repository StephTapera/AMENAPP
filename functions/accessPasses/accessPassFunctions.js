"use strict";
// accessPassFunctions.ts — Firebase Callable Functions for Access Passes
//
// Security: App Check enforced, auth enforced where required,
// all mutations backend-only, tokenHash never returned to client.
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
exports.listAccessRequestsForTarget = exports.listAccessPassesForTarget = exports.denyAccessRequest = exports.approveAccessRequest = exports.rotateAccessPassToken = exports.resumeAccessPass = exports.pauseAccessPass = exports.revokeAccessPass = exports.acceptAccessPass = exports.resolveAccessPass = exports.createAccessPass = void 0;
const functions = __importStar(require("firebase-functions"));
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const accessPassToken_1 = require("./accessPassToken");
const accessPassValidation_1 = require("./accessPassValidation");
const accessPassPermissions_1 = require("./accessPassPermissions");
const accessPassRateLimit_1 = require("./accessPassRateLimit");
const accessPassPreview_1 = require("./accessPassPreview");
const accessPassAudit_1 = require("./accessPassAudit");
const db = admin.firestore();
// ---------------------------------------------------------------------------
// 1. createAccessPass
// ---------------------------------------------------------------------------
exports.createAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const uid = context.auth.uid;
    const { targetType, targetId, orgId, churchId, spaceId, mode, title, subtitle, description, requiresAuth, requiresApproval, allowedEmailDomains, allowedRoleIds, allowedMemberUids, maxUses, maxUsesPerUser, startsAt, expiresAt, checkInDurationMinutes, safetyProfile, landingConfig, } = data;
    if (!targetType || !targetId || !mode || !title) {
        throw new HttpsError("invalid-argument", "missing-required-fields");
    }
    // Verify admin for target
    await (0, accessPassPermissions_1.verifyAdminForTarget)(uid, targetType, targetId);
    // Validate mode vs sensitivity
    if (safetyProfile?.isSensitive) {
        (0, accessPassValidation_1.validateModeForTarget)(mode, targetType, true);
    }
    // Get display name
    const userRecord = await admin.auth().getUser(uid);
    const displayName = userRecord.displayName ?? undefined;
    // Generate token
    const rawToken = (0, accessPassToken_1.generateRawToken)();
    const tokenHash = (0, accessPassToken_1.hashToken)(rawToken);
    const now = admin.firestore.Timestamp.now();
    const passId = db.collection("accessPasses").doc().id;
    const pass = {
        accessPassId: passId,
        tokenHash,
        tokenVersion: 1,
        targetType,
        targetId,
        orgId,
        churchId,
        spaceId,
        createdByUid: uid,
        createdByDisplayName: displayName,
        mode,
        status: "active",
        title,
        subtitle,
        description,
        requiresAuth: requiresAuth ?? true,
        requiresApproval: requiresApproval ?? false,
        allowedEmailDomains: allowedEmailDomains ?? [],
        allowedRoleIds: allowedRoleIds ?? [],
        allowedMemberUids: allowedMemberUids ?? [],
        maxUses,
        usesCount: 0,
        maxUsesPerUser: maxUsesPerUser ?? 1,
        startsAt: startsAt ? admin.firestore.Timestamp.fromMillis(startsAt) : undefined,
        expiresAt: expiresAt ? admin.firestore.Timestamp.fromMillis(expiresAt) : undefined,
        checkInDurationMinutes,
        safetyProfile: {
            isSensitive: safetyProfile?.isSensitive ?? false,
            requiresModeratorApproval: safetyProfile?.requiresModeratorApproval ?? false,
            allowYouthAccess: safetyProfile?.allowYouthAccess ?? false,
            allowGuestPreview: safetyProfile?.allowGuestPreview ?? false,
            showMemberVisibilityWarning: safetyProfile?.showMemberVisibilityWarning ?? true,
            showPrayerPrivacyWarning: safetyProfile?.showPrayerPrivacyWarning ?? false,
        },
        landingConfig: {
            headline: landingConfig?.headline ?? title,
            body: landingConfig?.body ?? "",
            primaryActionLabel: landingConfig?.primaryActionLabel ?? "Join",
            secondaryActionLabel: landingConfig?.secondaryActionLabel,
            allowedActions: landingConfig?.allowedActions ?? ["join", "preview"],
        },
        audit: {
            createdAt: now,
            updatedAt: now,
        },
    };
    await db.collection("accessPasses").doc(passId).set(pass);
    const universalLink = (0, accessPassToken_1.buildUniversalLink)(passId, rawToken);
    const deepLink = (0, accessPassToken_1.buildDeepLink)(passId, rawToken);
    return {
        accessPassId: passId,
        rawToken, // Returned once only — never stored
        universalLink,
        qrPayload: universalLink,
        nfcPayload: deepLink,
        shareLink: universalLink,
        previewTitle: title,
        previewSubtitle: subtitle ?? null,
    };
});
// ---------------------------------------------------------------------------
// 2. resolveAccessPass
// ---------------------------------------------------------------------------
exports.resolveAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    const uid = context.auth?.uid;
    const { accessPassId, token, anonymousSessionId, devicePlatform, appVersion } = data;
    if (!accessPassId || !token) {
        throw new HttpsError("invalid-argument", "missing-fields");
    }
    const identity = uid ?? anonymousSessionId ?? "anon";
    // Rate limit
    try {
        await (0, accessPassRateLimit_1.enforceRateLimit)("resolve", identity);
    }
    catch (e) {
        if (anonymousSessionId || uid) {
            await (0, accessPassAudit_1.logRateLimited)(accessPassId, "unknown", "unknown", uid).catch(() => { });
        }
        throw e;
    }
    let pass;
    try {
        pass = await (0, accessPassValidation_1.loadAndValidatePass)(accessPassId, token);
    }
    catch (err) {
        if (err.message === "invalid-pass") {
            await (0, accessPassRateLimit_1.recordInvalidTokenAttempt)(identity).catch(() => { });
        }
        throw err;
    }
    // Auth gate
    if (pass.requiresAuth && !uid) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    // Guest preview gate
    if (!pass.requiresAuth && !uid && !pass.safetyProfile.allowGuestPreview) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const alreadyMember = uid
        ? await (0, accessPassValidation_1.checkIfAlreadyMember)(pass.targetType, pass.targetId, uid)
        : false;
    const existingRequestPending = uid
        ? await (0, accessPassValidation_1.checkIfRequestPending)(accessPassId, uid)
        : false;
    // Log resolve event
    await (0, accessPassAudit_1.logResolved)(accessPassId, pass.targetType, pass.targetId, uid, anonymousSessionId, devicePlatform, appVersion).catch(() => { });
    // Update lastUsedAt
    await db.collection("accessPasses").doc(accessPassId).update({
        "audit.lastUsedAt": admin.firestore.Timestamp.now(),
    });
    return (0, accessPassPreview_1.buildPreviewResponse)(pass, alreadyMember, existingRequestPending);
});
// ---------------------------------------------------------------------------
// 3. acceptAccessPass
// ---------------------------------------------------------------------------
exports.acceptAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const uid = context.auth.uid;
    const { accessPassId, token, action, requestMessage } = data;
    if (!accessPassId || !token || !action) {
        throw new HttpsError("invalid-argument", "missing-fields");
    }
    await (0, accessPassRateLimit_1.enforceRateLimit)("accept", uid);
    const pass = await (0, accessPassValidation_1.loadAndValidatePass)(accessPassId, token);
    // Check user eligibility
    if (pass.mode === "roleGated") {
        const userRecord = await admin.auth().getUser(uid);
        await (0, accessPassValidation_1.verifyRoleGatedEligibility)(pass, uid, userRecord.email ?? undefined);
    }
    await (0, accessPassValidation_1.checkMaxUsesPerUser)(pass, uid);
    const now = admin.firestore.Timestamp.now();
    const passRef = db.collection("accessPasses").doc(accessPassId);
    switch (action) {
        case "preview": {
            await (0, accessPassAudit_1.logPreviewed)(accessPassId, pass.targetType, pass.targetId, uid).catch(() => { });
            return {
                success: true,
                action: "preview",
                targetId: pass.targetId,
                targetType: pass.targetType,
                routePayload: `amen://${pass.targetType}/${pass.targetId}`,
                message: "Preview opened.",
            };
        }
        case "join": {
            // Block sensitive direct join
            if (pass.safetyProfile.isSensitive) {
                (0, accessPassValidation_1.validateModeForTarget)("join", pass.targetType, true);
            }
            // Transactional join + usesCount increment
            await db.runTransaction(async (tx) => {
                const freshSnap = await tx.get(passRef);
                const fresh = freshSnap.data();
                (0, accessPassValidation_1.checkMaxUses)(fresh);
                // Write membership using existing membership pattern
                const memberRef = db
                    .collection(`${pass.targetType}s`)
                    .doc(pass.targetId)
                    .collection("members")
                    .doc(uid);
                tx.set(memberRef, {
                    userId: uid,
                    joinedAt: now,
                    role: "member",
                    accessPassId,
                    joinMethod: "accessPass",
                }, { merge: true });
                tx.update(passRef, {
                    usesCount: admin.firestore.FieldValue.increment(1),
                    "audit.updatedAt": now,
                });
            });
            await (0, accessPassAudit_1.logJoined)(accessPassId, pass.targetType, pass.targetId, uid).catch(() => { });
            return {
                success: true,
                action: "join",
                targetId: pass.targetId,
                targetType: pass.targetType,
                routePayload: `amen://${pass.targetType}/${pass.targetId}`,
                message: "Welcome! You've joined.",
            };
        }
        case "request": {
            // Check if already pending
            const alreadyPending = await (0, accessPassValidation_1.checkIfRequestPending)(accessPassId, uid);
            if (alreadyPending) {
                return {
                    success: true,
                    action: "request",
                    targetId: pass.targetId,
                    targetType: pass.targetType,
                    message: "Your request is already pending.",
                };
            }
            const requestId = db.collection("accessRequests").doc().id;
            const userRecord = await admin.auth().getUser(uid);
            const request = {
                requestId,
                accessPassId,
                targetType: pass.targetType,
                targetId: pass.targetId,
                requesterUid: uid,
                requesterDisplayName: userRecord.displayName ?? undefined,
                requesterPhotoURL: userRecord.photoURL ?? undefined,
                orgId: pass.orgId,
                churchId: pass.churchId,
                spaceId: pass.spaceId,
                status: "pending",
                requestMessage: requestMessage ?? undefined,
                createdAt: now,
                updatedAt: now,
            };
            await db.collection("accessRequests").doc(requestId).set(request);
            await (0, accessPassAudit_1.logRequested)(accessPassId, pass.targetType, pass.targetId, uid).catch(() => { });
            return {
                success: true,
                action: "request",
                requestId,
                targetId: pass.targetId,
                targetType: pass.targetType,
                message: "Your request has been sent to the host.",
            };
        }
        case "checkIn": {
            const durationMinutes = pass.checkInDurationMinutes ?? 120;
            const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + durationMinutes * 60000);
            const checkInId = db.collection("activeCheckIns").doc().id;
            const checkIn = {
                checkInId,
                accessPassId,
                uid,
                targetType: pass.targetType,
                targetId: pass.targetId,
                startedAt: now,
                expiresAt,
                status: "active",
            };
            await db.runTransaction(async (tx) => {
                const freshSnap = await tx.get(passRef);
                const fresh = freshSnap.data();
                (0, accessPassValidation_1.checkMaxUses)(fresh);
                tx.set(db.collection("activeCheckIns").doc(checkInId), checkIn);
                tx.update(passRef, {
                    usesCount: admin.firestore.FieldValue.increment(1),
                    "audit.updatedAt": now,
                });
            });
            await (0, accessPassAudit_1.logCheckedIn)(accessPassId, pass.targetType, pass.targetId, uid).catch(() => { });
            return {
                success: true,
                action: "checkIn",
                targetId: pass.targetId,
                targetType: pass.targetType,
                checkInExpiresAt: expiresAt.toMillis(),
                message: `You're checked in for ${durationMinutes} minutes.`,
            };
        }
        case "openSermonNotes":
        case "askForPrayer":
        case "meetLeader":
        case "followChurch": {
            return {
                success: true,
                action,
                targetId: pass.targetId,
                targetType: pass.targetType,
                routePayload: `amen://${pass.targetType}/${pass.targetId}/${action}`,
                message: "Action available.",
            };
        }
        default:
            throw new HttpsError("invalid-argument", "unknown-action");
    }
});
// ---------------------------------------------------------------------------
// 4. revokeAccessPass
// ---------------------------------------------------------------------------
exports.revokeAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const uid = context.auth.uid;
    const { accessPassId, reason } = data;
    await (0, accessPassPermissions_1.verifyPassAdmin)(uid, accessPassId);
    const passSnap = await db.collection("accessPasses").doc(accessPassId).get();
    const pass = passSnap.data();
    const now = admin.firestore.Timestamp.now();
    await db.collection("accessPasses").doc(accessPassId).update({
        status: "revoked",
        "audit.revokedAt": now,
        "audit.revokedByUid": uid,
        "audit.revokeReason": reason ?? null,
        "audit.updatedAt": now,
    });
    await (0, accessPassAudit_1.logRevoked)(accessPassId, pass.targetType, pass.targetId, uid, reason).catch(() => { });
    return { success: true };
});
// ---------------------------------------------------------------------------
// 5. pauseAccessPass
// ---------------------------------------------------------------------------
exports.pauseAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    await (0, accessPassPermissions_1.verifyPassAdmin)(context.auth.uid, data.accessPassId);
    await db.collection("accessPasses").doc(data.accessPassId).update({
        status: "paused",
        "audit.updatedAt": admin.firestore.Timestamp.now(),
    });
    return { success: true };
});
// ---------------------------------------------------------------------------
// 6. resumeAccessPass
// ---------------------------------------------------------------------------
exports.resumeAccessPass = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    await (0, accessPassPermissions_1.verifyPassAdmin)(context.auth.uid, data.accessPassId);
    const snap = await db.collection("accessPasses").doc(data.accessPassId).get();
    const pass = snap.data();
    if (pass.status === "revoked" || pass.status === "expired") {
        throw new HttpsError("failed-precondition", "cannot-resume-revoked-or-expired");
    }
    await db.collection("accessPasses").doc(data.accessPassId).update({
        status: "active",
        "audit.updatedAt": admin.firestore.Timestamp.now(),
    });
    return { success: true };
});
// ---------------------------------------------------------------------------
// 7. rotateAccessPassToken
// ---------------------------------------------------------------------------
exports.rotateAccessPassToken = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    await (0, accessPassPermissions_1.verifyPassAdmin)(context.auth.uid, data.accessPassId);
    const newRawToken = (0, accessPassToken_1.generateRawToken)();
    const newTokenHash = (0, accessPassToken_1.hashToken)(newRawToken);
    await db.collection("accessPasses").doc(data.accessPassId).update({
        tokenHash: newTokenHash,
        tokenVersion: admin.firestore.FieldValue.increment(1),
        "audit.updatedAt": admin.firestore.Timestamp.now(),
    });
    const universalLink = (0, accessPassToken_1.buildUniversalLink)(data.accessPassId, newRawToken);
    const deepLink = (0, accessPassToken_1.buildDeepLink)(data.accessPassId, newRawToken);
    return {
        accessPassId: data.accessPassId,
        newRawToken, // Returned once only
        newUniversalLink: universalLink,
        newQrPayload: universalLink,
        newShareLink: universalLink,
        newNfcPayload: deepLink,
    };
});
// ---------------------------------------------------------------------------
// 8. approveAccessRequest
// ---------------------------------------------------------------------------
exports.approveAccessRequest = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const uid = context.auth.uid;
    const { requestId } = data;
    await (0, accessPassPermissions_1.verifyRequestAdmin)(uid, requestId);
    const reqSnap = await db.collection("accessRequests").doc(requestId).get();
    const req = reqSnap.data();
    if (req.status !== "pending") {
        return { success: true, alreadyProcessed: true };
    }
    const now = admin.firestore.Timestamp.now();
    await db.runTransaction(async (tx) => {
        tx.update(db.collection("accessRequests").doc(requestId), {
            status: "approved",
            reviewedByUid: uid,
            reviewedAt: now,
            updatedAt: now,
        });
        // Create membership using existing Amen membership paths
        const memberRef = db
            .collection(`${req.targetType}s`)
            .doc(req.targetId)
            .collection("members")
            .doc(req.requesterUid);
        tx.set(memberRef, {
            userId: req.requesterUid,
            joinedAt: now,
            role: "member",
            accessPassId: req.accessPassId,
            joinMethod: "accessPassRequest",
        }, { merge: true });
    });
    return { success: true };
});
// ---------------------------------------------------------------------------
// 9. denyAccessRequest
// ---------------------------------------------------------------------------
exports.denyAccessRequest = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    await (0, accessPassPermissions_1.verifyRequestAdmin)(context.auth.uid, data.requestId);
    const now = admin.firestore.Timestamp.now();
    await db.collection("accessRequests").doc(data.requestId).update({
        status: "denied",
        reviewedByUid: context.auth.uid,
        reviewedAt: now,
        denialReason: data.denialReason ?? null,
        updatedAt: now,
    });
    return { success: true };
});
// ---------------------------------------------------------------------------
// 10. listAccessPassesForTarget
// ---------------------------------------------------------------------------
exports.listAccessPassesForTarget = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const { targetType, targetId } = data;
    await (0, accessPassPermissions_1.verifyAdminForTarget)(context.auth.uid, targetType, targetId);
    const passesSnap = await db
        .collection("accessPasses")
        .where("targetType", "==", targetType)
        .where("targetId", "==", targetId)
        .orderBy("audit.createdAt", "desc")
        .limit(50)
        .get();
    const passes = passesSnap.docs.map((doc) => {
        const pass = doc.data();
        // Strip tokenHash before returning to client
        const safe = { ...pass };
        delete safe.tokenHash;
        delete safe.tokenVersion;
        return safe;
    });
    return { passes };
});
// ---------------------------------------------------------------------------
// 11. listAccessRequestsForTarget
// ---------------------------------------------------------------------------
exports.listAccessRequestsForTarget = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "auth-required");
    }
    const { targetType, targetId } = data;
    await (0, accessPassPermissions_1.verifyAdminForTarget)(context.auth.uid, targetType, targetId);
    const reqSnap = await db
        .collection("accessRequests")
        .where("targetType", "==", targetType)
        .where("targetId", "==", targetId)
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();
    const requests = reqSnap.docs.map((doc) => doc.data());
    return { requests };
});
//# sourceMappingURL=accessPassFunctions.js.map