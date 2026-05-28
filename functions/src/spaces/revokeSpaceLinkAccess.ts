// revokeSpaceLinkAccess.ts
// AMEN Spaces — Cloud Function: Revoke External Member Access on Link Revocation
//
// Called when a community link is revoked (by Agent F or admin action).
// For each user in the Space's members sub-collection whose homeCommunityId
// matches the revoked community: set access = "none".
// Does NOT delete member rows — status flip only.
//
// Callable: { spaceId, revokedCommunityId }
// Authorization: caller must be admin/owner in the Space's parent community OR platform admin.
//
// Contract:
//   Collection: spaces/{spaceId}/members/{userId}
//   Field flipped: access ("granted" → "none")
//   Never deletes rows — MUST keep them for in-render safety (CALayerGetSuperlayer crash prevention)

import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// MARK: - Types

interface RevokeSpaceLinkRequest {
  spaceId: string;
  revokedCommunityId: string;
}

// MARK: - Callable

export const revokeSpaceLinkAccess = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const { spaceId, revokedCommunityId } = request.data as RevokeSpaceLinkRequest;

    if (!spaceId || typeof spaceId !== "string" || spaceId.trim() === "") {
      throw new HttpsError("invalid-argument", "spaceId is required.");
    }
    if (!revokedCommunityId || typeof revokedCommunityId !== "string" || revokedCommunityId.trim() === "") {
      throw new HttpsError("invalid-argument", "revokedCommunityId is required.");
    }

    // Resolve the space and its parent community
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) {
      throw new HttpsError("not-found", `Space ${spaceId} not found.`);
    }
    const spaceData = spaceDoc.data()!;
    const communityId: string = spaceData.communityId;

    if (!communityId) {
      throw new HttpsError("internal", "Space is missing communityId.");
    }

    // Authorization: caller must be admin/owner OR platform admin
    const callerIsAdmin = request.auth?.token?.admin === true;
    if (!callerIsAdmin) {
      await assertCommunityAdminOrOwner(callerUid, communityId);
    }

    // Safety: cannot revoke the owning community's own members
    if (revokedCommunityId === communityId) {
      throw new HttpsError(
        "invalid-argument",
        "Cannot revoke the owning community's own members."
      );
    }

    // Find all space members whose homeCommunityId matches the revoked community
    const membersSnap = await db
      .collection("spaces").doc(spaceId)
      .collection("members")
      .where("homeCommunityId", "==", revokedCommunityId)
      .get();

    if (membersSnap.empty) {
      logger.info(
        `[revokeSpaceLinkAccess] No external members found for community=${revokedCommunityId} in space=${spaceId}`
      );
      return { success: true, revokedCount: 0, spaceId, revokedCommunityId };
    }

    // Flip access to "none" in a batch — never delete
    const BATCH_SIZE = 400; // Firestore batch limit is 500
    let revokedCount = 0;
    const docs = membersSnap.docs;

    for (let i = 0; i < docs.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const chunk = docs.slice(i, i + BATCH_SIZE);

      for (const doc of chunk) {
        const currentAccess = doc.data()?.access as string | undefined;
        if (currentAccess === "granted") {
          batch.update(doc.ref, {
            access: "none",
            updatedAt: FieldValue.serverTimestamp(),
          });
          revokedCount++;
        }
      }

      await batch.commit();
    }

    // Also update the Space's sharedWith array to remove the revoked communityId
    // sharedWith is denormalized; keep it in sync so badge/banner render is accurate.
    try {
      await db.collection("spaces").doc(spaceId).update({
        sharedWith: admin.firestore.FieldValue.arrayRemove(revokedCommunityId),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Non-fatal: the access revocation succeeded. Log and continue.
      logger.warn(
        `[revokeSpaceLinkAccess] Failed to remove ${revokedCommunityId} from sharedWith on space=${spaceId}:`,
        e
      );
    }

    logger.info(
      `[revokeSpaceLinkAccess] Revoked ${revokedCount} members of community=${revokedCommunityId} from space=${spaceId} by caller=${callerUid}`
    );

    return {
      success: true,
      revokedCount,
      spaceId,
      revokedCommunityId,
    };
  }
);

// MARK: - Auth Helpers

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
      "Owner or admin role is required."
    );
  }
}
