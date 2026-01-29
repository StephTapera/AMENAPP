/**
 * Notification Cloud Functions
 * 
 * Sends push notifications for:
 * - New followers
 * - Amens on posts
 * - Comments on posts
 * - New messages
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// MARK: - Helper Functions

/**
 * Send push notification to user via FCM
 */
async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data: { [key: string]: string }
): Promise<void> {
  try {
    // Get user's FCM token
    const userDoc = await db.collection("users").doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${userId}`);
      return;
    }

    // Check if user allows notifications
    const notificationSettings = userDoc.data();
    if (!notificationSettings?.allowNotifications) {
      console.log(`User ${userId} has notifications disabled`);
      return;
    }

    // Send notification
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: data,
      token: fcmToken,
      apns: {
        payload: {
          aps: {
            badge: await getUnreadNotificationCount(userId),
            sound: notificationSettings?.soundEnabled ? "default" : undefined,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log(`✅ Push notification sent to ${userId}: ${response}`);
  } catch (error) {
    console.error(`❌ Error sending push notification to ${userId}:`, error);
  }
}

/**
 * Get unread notification count for badge
 */
async function getUnreadNotificationCount(userId: string): Promise<number> {
  const snapshot = await db
    .collection("notifications")
    .where("userId", "==", userId)
    .where("read", "==", false)
    .count()
    .get();

  return snapshot.data().count;
}

/**
 * Create notification document in Firestore
 */
async function createNotification(
  userId: string,
  type: string,
  actorId: string,
  actorName: string,
  actorUsername: string,
  postId?: string,
  commentText?: string
): Promise<void> {
  await db.collection("notifications").add({
    userId: userId,
    type: type,
    actorId: actorId,
    actorName: actorName,
    actorUsername: actorUsername,
    postId: postId || null,
    commentText: commentText || null,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`✅ Created ${type} notification for user ${userId}`);
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
    const followerId = followData.followerId;
    const followedId = followData.followedId;

    console.log(`👥 New follow: ${followerId} followed ${followedId}`);

    try {
      // Get follower info
      const followerDoc = await db.collection("users").doc(followerId).get();
      const followerData = followerDoc.data();

      if (!followerData) {
        console.log("Follower user not found");
        return;
      }

      // Check if followed user wants follow notifications
      const followedDoc = await db.collection("users").doc(followedId).get();
      const followedData = followedDoc.data();

      if (!followedData?.followNotifications) {
        console.log("User has follow notifications disabled");
        return;
      }

      // Create notification document
      await createNotification(
        followedId,
        "follow",
        followerId,
        followerData.fullName || "Someone",
        followerData.username || "unknown"
      );

      // Send push notification
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
      console.error("Error in onFollowCreated:", error);
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
    const postId = context.params.postId;
    const amenData = snapshot.data();
    const amenUserId = amenData.userId;

    console.log(`🙏 New Amen on post ${postId} by user ${amenUserId}`);

    try {
      // Get post to find author
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();

      if (!postData) {
        console.log("Post not found");
        return;
      }

      const postAuthorId = postData.authorId;

      // Don't send notification if user liked their own post
      if (amenUserId === postAuthorId) {
        console.log("User liked their own post, skipping notification");
        return;
      }

      // Get Amen user info
      const amenUserDoc = await db.collection("users").doc(amenUserId).get();
      const amenUserData = amenUserDoc.data();

      if (!amenUserData) {
        console.log("Amen user not found");
        return;
      }

      // Check if post author wants Amen notifications
      const authorDoc = await db.collection("users").doc(postAuthorId).get();
      const authorData = authorDoc.data();

      if (!authorData?.amenNotifications) {
        console.log("User has Amen notifications disabled");
        return;
      }

      // Create notification document
      await createNotification(
        postAuthorId,
        "amen",
        amenUserId,
        amenUserData.fullName || "Someone",
        amenUserData.username || "unknown",
        postId
      );

      // Send push notification
      await sendPushNotification(
        postAuthorId,
        "New Amen",
        `${amenUserData.fullName || "Someone"} said Amen to your post`,
        {
          type: "amen",
          actorId: amenUserId,
          actorName: amenUserData.fullName || "Someone",
          postId: postId,
        }
      );
    } catch (error) {
      console.error("Error in onAmenCreated:", error);
    }
  });

// MARK: - Comment Notification

/**
 * Trigger: When a new comment is created
 * Action: Send notification to post author
 */
export const onCommentCreated = functions.firestore
  .document("comments/{commentId}")
  .onCreate(async (snapshot, context) => {
    const commentData = snapshot.data();
    const postId = commentData.postId;
    const commentUserId = commentData.userId;
    const commentText = commentData.text;

    console.log(`💬 New comment on post ${postId} by user ${commentUserId}`);

    try {
      // Get post to find author
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();

      if (!postData) {
        console.log("Post not found");
        return;
      }

      const postAuthorId = postData.authorId;

      // Don't send notification if user commented on their own post
      if (commentUserId === postAuthorId) {
        console.log("User commented on their own post, skipping notification");
        return;
      }

      // Get commenter info
      const commenterDoc = await db
        .collection("users")
        .doc(commentUserId)
        .get();
      const commenterData = commenterDoc.data();

      if (!commenterData) {
        console.log("Commenter user not found");
        return;
      }

      // Check if post author wants comment notifications
      const authorDoc = await db.collection("users").doc(postAuthorId).get();
      const authorData = authorDoc.data();

      if (!authorData?.commentNotifications) {
        console.log("User has comment notifications disabled");
        return;
      }

      // Create notification document
      await createNotification(
        postAuthorId,
        "comment",
        commentUserId,
        commenterData.fullName || "Someone",
        commenterData.username || "unknown",
        postId,
        commentText
      );

      // Send push notification
      await sendPushNotification(
        postAuthorId,
        "New Comment",
        `${commenterData.fullName || "Someone"} commented: ${commentText.substring(0, 50)}${commentText.length > 50 ? "..." : ""}`,
        {
          type: "comment",
          actorId: commentUserId,
          actorName: commenterData.fullName || "Someone",
          postId: postId,
          commentText: commentText,
        }
      );
    } catch (error) {
      console.error("Error in onCommentCreated:", error);
    }
  });

// MARK: - Message Notification

/**
 * Trigger: When a new message is created
 * Action: Send notification to all participants except sender
 */
export const onMessageCreated = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const conversationId = context.params.conversationId;
    const messageData = snapshot.data();
    const senderId = messageData.senderId;
    const senderName = messageData.senderName;
    const messageText = messageData.text;

    console.log(`💬 New message in conversation ${conversationId}`);

    try {
      // Get conversation to find participants
      const conversationDoc = await db
        .collection("conversations")
        .doc(conversationId)
        .get();
      const conversationData = conversationDoc.data();

      if (!conversationData) {
        console.log("Conversation not found");
        return;
      }

      const participantIds = conversationData.participantIds as string[];

      // Send notification to all participants except sender
      for (const participantId of participantIds) {
        if (participantId === senderId) {
          continue; // Skip sender
        }

        // Check if participant wants message notifications
        const participantDoc = await db
          .collection("users")
          .doc(participantId)
          .get();
        const participantData = participantDoc.data();

        if (!participantData?.messageNotifications) {
          console.log(`User ${participantId} has message notifications disabled`);
          continue;
        }

        // Create notification document
        await createNotification(
          participantId,
          "message",
          senderId,
          senderName,
          "", // Username not needed for messages
          undefined,
          messageText
        );

        // Send push notification
        await sendPushNotification(
          participantId,
          conversationData.isGroup
            ? conversationData.groupName || "Group Message"
            : senderName,
          conversationData.isGroup
            ? `${senderName}: ${messageText}`
            : messageText,
          {
            type: "message",
            actorId: senderId,
            actorName: senderName,
            conversationId: conversationId,
            messageText: messageText,
          }
        );
      }
    } catch (error) {
      console.error("Error in onMessageCreated:", error);
    }
  });
