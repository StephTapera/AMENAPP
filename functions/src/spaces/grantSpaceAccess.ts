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

import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// Initialize admin SDK if not already initialized (module-level guard)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// MARK: - Types

interface GrantSpaceAccessRequest {
  userId: string;
  spaceId: string;
  source: "grant";
  expiresAt?: admin.firestore.Timestamp | null;
}

// MARK: - Callable

export const grantSpaceAccess = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const { userId, spaceId, source, expiresAt } = request.data as GrantSpaceAccessRequest;

    // Validate required fields
    if (!userId || typeof userId !== "string" || userId.trim() === "") {
      throw new HttpsError("invalid-argument", "userId is required.");
    }
    if (!spaceId || typeof spaceId !== "string" || spaceId.trim() === "") {
      throw new HttpsError("invalid-argument", "spaceId is required.");
    }
    if (source !== "grant") {
      throw new HttpsError("invalid-argument", "source must be 'grant'.");
    }

    // Resolve the space to get its communityId
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) {
      throw new HttpsError("not-found", `Space ${spaceId} not found.`);
    }
    const spaceData = spaceDoc.data()!;
    const communityId: string = spaceData.communityId;
    if (!communityId) {
      throw new HttpsError("internal", "Space is missing communityId.");
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
      throw new HttpsError("not-found", `User ${userId} not found.`);
    }

    // Upsert entitlement — status flip only, never delete
    const entitlementId = `${userId}_${spaceId}`;
    const entitlementRef = db.collection("entitlements").doc(entitlementId);

    const entitlementData: Record<string, unknown> = {
      userId,
      spaceId,
      status: "active",
      source: "grant",
      updatedAt: FieldValue.serverTimestamp(),
    };

    // Only set expiresAt if explicitly provided; null = lifetime
    if (expiresAt !== undefined) {
      entitlementData.expiresAt = expiresAt;
    }

    // Use merge:true so we update without wiping existing stripeSubId if present
    await entitlementRef.set(entitlementData, { merge: true });

    logger.info(
      `[grantSpaceAccess] Granted access: user=${userId} space=${spaceId} by=${callerUid}`
    );

    return {
      success: true,
      entitlementId,
      userId,
      spaceId,
      status: "active",
    };
  }
);

// MARK: - Auth Helpers

/**
 * Assert that the caller holds owner or admin role in the given community.
 * Checks amenCommunities/{communityId}/members/{callerUid}.
 */
async function assertCommunityAdminOrOwner(
  callerUid: string,
  communityId: string
): Promise<void> {
  const memberDoc = await db
    .collection("amenCommunities")
    .doc(communityId)
    .collection("members")
    .doc(callerUid)
    .get();

  if (!memberDoc.exists) {
    throw new HttpsError(
      "permission-denied",
      "You are not a member of this community."
    );
  }

  const role = memberDoc.data()?.role as string | undefined;
  if (!["owner", "admin"].includes(role ?? "")) {
    throw new HttpsError(
      "permission-denied",
      "Owner or admin role is required to grant access."
    );
  }
}
