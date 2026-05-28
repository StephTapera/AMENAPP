"use strict";
// grantSpaceAccess.ts
// AMEN Spaces — Cloud Function: Admin Grant Entitlement
//
// Callable: { userId, spaceId, source: "grant", expiresAt?: Timestamp | null }
// Sets entitlements/{userId}_{spaceId} with status: "active", source: "grant"
// Admin/owner only — validates caller role from amenCommunities.members (via Space's communityId).
//
// Contract:
//   Collection: entitlements/{userId}_{spaceId}
//   Caller: must be admin/owner in the Space's parent community OR platform admin
//   NEVER deletes — upserts with status flip only
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
exports.grantSpaceAccess = void 0;
const logger = __importStar(require("firebase-functions/logger"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
// Initialize admin SDK if not already initialized (module-level guard)
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// MARK: - Callable
exports.grantSpaceAccess = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const { userId, spaceId, source, expiresAt } = request.data;
    // Validate required fields
    if (!userId || typeof userId !== "string" || userId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "userId is required.");
    }
    if (!spaceId || typeof spaceId !== "string" || spaceId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "spaceId is required.");
    }
    if (source !== "grant") {
        throw new https_1.HttpsError("invalid-argument", "source must be 'grant'.");
    }
    // Resolve the space to get its communityId
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) {
        throw new https_1.HttpsError("not-found", `Space ${spaceId} not found.`);
    }
    const spaceData = spaceDoc.data();
    const communityId = spaceData.communityId;
    if (!communityId) {
        throw new https_1.HttpsError("internal", "Space is missing communityId.");
    }
    // Authorize: caller must be admin/owner of the parent community
    // OR hold the Firebase Admin custom claim
    const callerIsAdmin = request.auth?.token?.admin === true;
    if (!callerIsAdmin) {
        await assertCommunityAdminOrOwner(callerUid, communityId);
    }
    // Target user must exist
    const targetUser = await admin.auth().getUser(userId).catch(() => null);
    if (!targetUser) {
        throw new https_1.HttpsError("not-found", `User ${userId} not found.`);
    }
    // Upsert entitlement — status flip only, never delete
    const entitlementId = `${userId}_${spaceId}`;
    const entitlementRef = db.collection("entitlements").doc(entitlementId);
    const entitlementData = {
        userId,
        spaceId,
        status: "active",
        source: "grant",
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    };
    // Only set expiresAt if explicitly provided; null = lifetime
    if (expiresAt !== undefined) {
        entitlementData.expiresAt = expiresAt;
    }
    // Use merge:true so we update without wiping existing stripeSubId if present
    await entitlementRef.set(entitlementData, { merge: true });
    logger.info(`[grantSpaceAccess] Granted access: user=${userId} space=${spaceId} by=${callerUid}`);
    return {
        success: true,
        entitlementId,
        userId,
        spaceId,
        status: "active",
    };
});
// MARK: - Auth Helpers
/**
 * Assert that the caller holds owner or admin role in the given community.
 * Checks amenCommunities/{communityId}/members/{callerUid}.
 */
async function assertCommunityAdminOrOwner(callerUid, communityId) {
    const memberDoc = await db
        .collection("amenCommunities")
        .doc(communityId)
        .collection("members")
        .doc(callerUid)
        .get();
    if (!memberDoc.exists) {
        throw new https_1.HttpsError("permission-denied", "You are not a member of this community.");
    }
    const role = memberDoc.data()?.role;
    if (!["owner", "admin"].includes(role ?? "")) {
        throw new https_1.HttpsError("permission-denied", "Owner or admin role is required to grant access.");
    }
}
