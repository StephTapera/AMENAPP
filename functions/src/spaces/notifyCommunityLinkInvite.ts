// notifyCommunityLinkInvite.ts
// AMEN Spaces — Cloud Function: Notify Community Admins of a Link Invite
//
// Triggered by Firestore onCreate on:
//   amenCommunities/{communityId}/links/{linkId}
//   where status == "pending"
//
// Sends FCM push notifications to the target community's owner + all admins.
//   title: "[Community Name] wants to share a Space with you"
//   body:  "[Space title] — tap to review"
//
// FCM pattern matches existing AMEN push notification infra (pushNotifications.js):
//   - Fan-out to all enabled deviceTokens subcollection entries.
//   - Fallback to legacy top-level fcmToken field.
//   - Stale tokens removed automatically.
//
// Agent F owns this file. Do not modify revokeSpaceLinkAccess.ts here.

import * as logger from "firebase-functions/logger";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// MARK: - Trigger

export const notifyCommunityLinkInvite = onDocumentCreated(
  "amenCommunities/{communityId}/links/{linkId}",
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("[notifyCommunityLinkInvite] No snapshot data.");
      return null;
    }

    const linkData = snap.data();

    // Only process pending invites.
    if (linkData?.status !== "pending") {
      logger.info("[notifyCommunityLinkInvite] Skipping non-pending link.");
      return null;
    }

    const fromCommunityId: string = linkData?.fromCommunityId ?? "";
    const toCommunityId: string   = linkData?.toCommunityId   ?? "";
    const spaceId: string         = linkData?.spaceId         ?? "";
    const scope: string           = linkData?.scope           ?? "";

    if (!fromCommunityId || !toCommunityId) {
      logger.warn("[notifyCommunityLinkInvite] Missing fromCommunityId or toCommunityId.");
      return null;
    }

    // 1. Resolve the sending community's name.
    let fromCommunityName = fromCommunityId;
    try {
      const fromDoc = await db.collection("amenCommunities").doc(fromCommunityId).get();
      if (fromDoc.exists) {
        fromCommunityName = fromDoc.data()?.name ?? fromCommunityId;
      }
    } catch (e) {
      logger.warn("[notifyCommunityLinkInvite] Failed to resolve fromCommunity name:", e);
    }

    // 2. Resolve the space title for the body copy.
    let spaceTitle = scope.startsWith("Shared: ")
      ? scope.slice("Shared: ".length)
      : scope;
    if (spaceId) {
      try {
        const spaceDoc = await db.collection("spaces").doc(spaceId).get();
        if (spaceDoc.exists) {
          spaceTitle = spaceDoc.data()?.title ?? spaceTitle;
        }
      } catch (e) {
        logger.warn("[notifyCommunityLinkInvite] Failed to resolve space title:", e);
      }
    }

    // 3. Get owner + admins of the TARGET community.
    const targetAdminUids: string[] = [];
    try {
      const membersSnap = await db
        .collection("amenCommunities")
        .doc(toCommunityId)
        .collection("members")
        .where("role", "in", ["owner", "admin"])
        .get();
      for (const doc of membersSnap.docs) {
        targetAdminUids.push(doc.id); // doc.id = userId
      }
    } catch (e) {
      logger.error("[notifyCommunityLinkInvite] Failed to fetch target community admins:", e);
      return null;
    }

    if (targetAdminUids.length === 0) {
      logger.info(
        `[notifyCommunityLinkInvite] No admins found for community=${toCommunityId}. No notifications sent.`
      );
      return null;
    }

    // 4. Build notification payload.
    const title = `${fromCommunityName} wants to share a Space with you`;
    const body  = `${spaceTitle} — tap to review`;
    const data: Record<string, string> = {
      type: "communityLinkInvite",
      fromCommunityId,
      toCommunityId,
      spaceId,
      linkId: event.params.linkId ?? "",
    };

    // 5. Fan-out to all target admins.
    let totalSent = 0;
    for (const userId of targetAdminUids) {
      const sent = await sendPushToUser(userId, title, body, data);
      totalSent += sent;
    }

    logger.info(
      `[notifyCommunityLinkInvite] Sent ${totalSent} push(es) to ${targetAdminUids.length} admin(s) ` +
      `of community=${toCommunityId} from community=${fromCommunityId}`
    );

    return { success: true, notifiedCount: totalSent };
  }
);

// MARK: - FCM Helper
//
// Matches the pattern in functions/pushNotifications.js:
//   - Fan-out to all enabled deviceTokens subcollection tokens.
//   - Fallback to legacy top-level fcmToken field.
//   - Remove stale tokens on messaging/registration-token-not-registered.

async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<number> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      logger.info(`[notifyCommunityLinkInvite] User ${userId} not found.`);
      return 0;
    }
    const userData = userDoc.data() ?? {};

    // Collect enabled device tokens (subcollection first, legacy fallback).
    let tokens: string[] = [];
    const deviceSnap = await db
      .collection("users")
      .doc(userId)
      .collection("deviceTokens")
      .where("enabled", "==", true)
      .get();

    if (!deviceSnap.empty) {
      tokens = deviceSnap.docs.map((d) => d.data().token as string).filter(Boolean);
    } else if (userData.fcmToken) {
      tokens = [userData.fcmToken as string];
    }

    if (tokens.length === 0) {
      logger.info(`[notifyCommunityLinkInvite] No FCM tokens for user ${userId}.`);
      return 0;
    }

    const messageBase: admin.messaging.BaseMessage = {
      notification: { title, body },
      data,
    };

    const staleTokens: string[] = [];
    let sentCount = 0;

    await Promise.all(
      tokens.map(async (token) => {
        try {
          await admin.messaging().send({ ...messageBase, token });
          sentCount++;
        } catch (err: unknown) {
          const code = (err as { code?: string }).code ?? "";
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            staleTokens.push(token);
          } else {
            logger.warn(`[notifyCommunityLinkInvite] FCM send error for ${userId}:`, err);
          }
        }
      })
    );

    // Clean up stale tokens.
    if (staleTokens.length > 0) {
      const batch = db.batch();
      deviceSnap.docs.forEach((d) => {
        if (staleTokens.includes(d.data().token as string)) {
          batch.delete(d.ref);
        }
      });
      await batch.commit();
      logger.info(
        `[notifyCommunityLinkInvite] Removed ${staleTokens.length} stale token(s) for ${userId}.`
      );
    }

    return sentCount;
  } catch (e) {
    logger.error(`[notifyCommunityLinkInvite] sendPushToUser failed for ${userId}:`, e);
    return 0;
  }
}
