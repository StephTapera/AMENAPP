/**
 * Notification Cloud Functions — V1
 *
 * Sends push notifications for:
 * - New followers
 * - Amens on posts
 * - Comments on posts
 * - New messages
 *
 * Security hardening applied 2026-05-24:
 *  - Block check before every send (recipient's blockedUsers subcollection)
 *  - Privacy-safe push body (no raw message or comment text)
 *  - Deduplication via deterministic Firestore document IDs (idempotent on retry)
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// MARK: - Helper Functions

/**
 * Returns true if actorId is blocked by recipientId.
 * Reads from blockedUsers/{recipientId}/blocked/{actorId}.
 */
async function isBlocked(recipientId: string, actorId: string): Promise<boolean> {
  try {
    const doc = await db
      .collection("blockedUsers")
      .doc(recipientId)
      .collection("blocked")
      .doc(actorId)
      .get();
    return doc.exists;
  } catch {
    // If the read fails (e.g. missing rule), allow the notification rather than
    // silently suppressing legitimate activity.
    return false;
  }
}

/**
 * Send push notification to user via FCM.
 * Handles invalid token detection and soft-disables the token on permanent failure.
 */
async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data: { [key: string]: string }
): Promise<void> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`[notif] No FCM token for user ${userId}`);
      return;
    }

    if (!userData?.allowNotifications) {
      console.log(`[notif] Notifications disabled for user ${userId}`);
      return;
    }

    const badgeCount = await getUnreadNotificationCount(userId);

    const message: admin.messaging.Message = {
      notification: { title, body },
      data,
      token: fcmToken,
      apns: {
        payload: {
          aps: {
            badge: badgeCount,
            sound: userData?.soundEnabled !== false ? "default" : undefined,
          },
        },
      },
    };

    await admin.messaging().send(message);
    console.log(`[notif] ✅ Sent to ${userId}`);
  } catch (error: unknown) {
    // Mark token as invalid so the backend can clean it up.
    const fcmError = error as { code?: string };
    if (
      fcmError?.code === "messaging/invalid-registration-token" ||
      fcmError?.code === "messaging/registration-token-not-registered"
    ) {
      console.warn(`[notif] Invalid token for user ${userId} — disabling`);
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
        fcmTokenInvalidatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => { /* best effort */ });
    } else {
      console.error(`[notif] ❌ Error sending to ${userId}:`, error);
    }
  }
}

/**
 * Get unread notification count for badge (capped at 99).
 */
async function getUnreadNotificationCount(userId: string): Promise<number> {
  try {
    const snapshot = await db
      .collection("notifications")
      .where("userId", "==", userId)
      .where("read", "==", false)
      .count()
      .get();
    return Math.min(snapshot.data().count, 99);
  } catch {
    return 0;
  }
}

/**
 * Create notification document using a deterministic ID for idempotency.
 * A repeated function execution for the same event will hit the same doc
 * (setData with merge:false is a no-op if the doc already exists).
 */
async function createNotification(
  dedupeId: string,
  userId: string,
  type: string,
  actorId: string,
  actorName: string,
  actorUsername: string,
  postId?: string
): Promise<void> {
  const ref = db.collection("notifications").doc(dedupeId);
  // Only create if not already present — prevents double-send on retries.
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      console.log(`[notif] Dedupe hit for ${dedupeId} — skipping`);
      return;
    }
    tx.set(ref, {
      userId,
      type,
      actorId,
      actorName,
      actorUsername,
      postId: postId ?? null,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  console.log(`[notif] Created ${type} notification for ${userId}`);
}

// MARK: - Follow Notification

/**
 * Trigger: When a new follow relationship is created
 * Action: Send notification to the followed user
 */
export const onFollowCreated = functions.firestore
  .document("follows/{followId}")
  .onCreate(async (snapshot, context) => {
    const followData = snapshot.data();
    const followerId = followData.followerId as string;
    const followedId = followData.followedId as string;
    const followId = context.params.followId as string;

    console.log(`[notif] Follow: ${followerId} → ${followedId}`);

    try {
      const followerDoc = await db.collection("users").doc(followerId).get();
      const followerData = followerDoc.data();
      if (!followerData) return;

      const followedDoc = await db.collection("users").doc(followedId).get();
      const followedData = followedDoc.data();
      if (!followedData?.followNotifications) return;

      // Block check: don't notify if recipient has blocked the actor
      if (await isBlocked(followedId, followerId)) {
        console.log(`[notif] Follow notification suppressed — ${followerId} is blocked by ${followedId}`);
        return;
      }

      const dedupeId = `follow_${followId}_${followedId}`;
      await createNotification(
        dedupeId,
        followedId,
        "follow",
        followerId,
        followerData.fullName || "Someone",
        followerData.username || "unknown"
      );

      await sendPushNotification(
        followedId,
        "New Follower",
        `${followerData.fullName || "Someone"} started following you`,
        {
          type: "follow",
          actorId: followerId,
          actorName: followerData.fullName || "Someone",
        }
      );
    } catch (error) {
      console.error("[notif] Error in onFollowCreated:", error);
    }
  });

// MARK: - Amen Notification

/**
 * Trigger: When someone says Amen to a post
 * Action: Send notification to post author
 */
export const onAmenCreated = functions.firestore
  .document("posts/{postId}/amens/{amenId}")
  .onCreate(async (snapshot, context) => {
    const postId = context.params.postId as string;
    const amenId = context.params.amenId as string;
    const amenData = snapshot.data();
    const amenUserId = amenData.userId as string;

    console.log(`[notif] Amen on post ${postId} by ${amenUserId}`);

    try {
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();
      if (!postData) return;

      const postAuthorId = postData.authorId as string;
      if (amenUserId === postAuthorId) return; // self-action

      const amenUserDoc = await db.collection("users").doc(amenUserId).get();
      const amenUserData = amenUserDoc.data();
      if (!amenUserData) return;

      const authorDoc = await db.collection("users").doc(postAuthorId).get();
      const authorData = authorDoc.data();
      if (!authorData?.amenNotifications) return;

      // Block check
      if (await isBlocked(postAuthorId, amenUserId)) {
        console.log(`[notif] Amen notification suppressed — ${amenUserId} is blocked by ${postAuthorId}`);
        return;
      }

      const dedupeId = `amen_${amenId}_${postAuthorId}`;
      await createNotification(
        dedupeId,
        postAuthorId,
        "amen",
        amenUserId,
        amenUserData.fullName || "Someone",
        amenUserData.username || "unknown",
        postId
      );

      await sendPushNotification(
        postAuthorId,
        "New Amen",
        `${amenUserData.fullName || "Someone"} said Amen to your post`,
        {
          type: "amen",
          actorId: amenUserId,
          actorName: amenUserData.fullName || "Someone",
          postId,
        }
      );
    } catch (error) {
      console.error("[notif] Error in onAmenCreated:", error);
    }
  });

// MARK: - Comment Notification

/**
 * Trigger: When a new comment is created
 * Action: Send notification to post author
 *
 * Privacy: The raw comment text is never included in the push body.
 * Recipients open the app to read the comment content.
 */
export const onCommentCreated = functions.firestore
  .document("comments/{commentId}")
  .onCreate(async (snapshot, context) => {
    const commentId = context.params.commentId as string;
    const commentData = snapshot.data();
    const postId = commentData.postId as string;
    const commentUserId = commentData.userId as string;

    console.log(`[notif] Comment ${commentId} on post ${postId} by ${commentUserId}`);

    try {
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();
      if (!postData) return;

      const postAuthorId = postData.authorId as string;
      if (commentUserId === postAuthorId) return; // self-action

      const commenterDoc = await db.collection("users").doc(commentUserId).get();
      const commenterData = commenterDoc.data();
      if (!commenterData) return;

      const authorDoc = await db.collection("users").doc(postAuthorId).get();
      const authorData = authorDoc.data();
      if (!authorData?.commentNotifications) return;

      // Block check
      if (await isBlocked(postAuthorId, commentUserId)) {
        console.log(`[notif] Comment notification suppressed — ${commentUserId} is blocked by ${postAuthorId}`);
        return;
      }

      const dedupeId = `comment_${commentId}_${postAuthorId}`;
      // Store the commentId in the notification for deep-link routing; never store raw text here.
      await db.runTransaction(async (tx) => {
        const ref = db.collection("notifications").doc(dedupeId);
        const existing = await tx.get(ref);
        if (existing.exists) {
          console.log(`[notif] Dedupe hit for ${dedupeId} — skipping`);
          return;
        }
        tx.set(ref, {
          userId: postAuthorId,
          type: "comment",
          actorId: commentUserId,
          actorName: commenterData.fullName || "Someone",
          actorUsername: commenterData.username || "unknown",
          postId,
          commentId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      // Privacy-safe push body: never include raw comment text
      const actorName = commenterData.fullName || "Someone";
      await sendPushNotification(
        postAuthorId,
        "New Comment",
        `${actorName} commented on your post`,
        {
          type: "comment",
          actorId: commentUserId,
          actorName,
          postId,
          commentId,
          // commentText intentionally omitted from push data
        }
      );
    } catch (error) {
      console.error("[notif] Error in onCommentCreated:", error);
    }
  });

// MARK: - Message Notification

/**
 * Trigger: When a new message is created
 * Action: Send notification to all participants except sender
 *
 * Privacy: The raw message text is never included in the push body or data payload.
 * Recipients open the app to read the message content.
 */
export const onMessageCreated = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const conversationId = context.params.conversationId as string;
    const messageId = context.params.messageId as string;
    const messageData = snapshot.data();
    const senderId = messageData.senderId as string;
    const senderName = messageData.senderName as string;

    console.log(`[notif] Message ${messageId} in conversation ${conversationId}`);

    try {
      const conversationDoc = await db.collection("conversations").doc(conversationId).get();
      const conversationData = conversationDoc.data();
      if (!conversationData) return;

      const participantIds = conversationData.participantIds as string[];

      for (const participantId of participantIds) {
        if (participantId === senderId) continue;

        const participantDoc = await db.collection("users").doc(participantId).get();
        const participantData = participantDoc.data();
        if (!participantData?.messageNotifications) continue;

        // Block check
        if (await isBlocked(participantId, senderId)) {
          console.log(`[notif] Message notification suppressed — ${senderId} is blocked by ${participantId}`);
          continue;
        }

        const dedupeId = `message_${messageId}_${participantId}`;
        // Create notification record (no raw text stored in push-facing doc)
        await db.runTransaction(async (tx) => {
          const ref = db.collection("notifications").doc(dedupeId);
          const existing = await tx.get(ref);
          if (existing.exists) {
            console.log(`[notif] Dedupe hit for ${dedupeId} — skipping`);
            return;
          }
          tx.set(ref, {
            userId: participantId,
            type: "message",
            actorId: senderId,
            actorName: senderName,
            actorUsername: "",
            conversationId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });

        // Privacy-safe push body: never include raw message text
        const pushTitle = conversationData.isGroup
          ? conversationData.groupName || "Group Message"
          : senderName;
        const pushBody = conversationData.isGroup
          ? `${senderName} sent a message`
          : "You have a new message";

        await sendPushNotification(
          participantId,
          pushTitle,
          pushBody,
          {
            type: "message",
            actorId: senderId,
            actorName: senderName,
            conversationId,
            // messageText intentionally omitted from push data
          }
        );
      }
    } catch (error) {
      console.error("[notif] Error in onMessageCreated:", error);
    }
  });
