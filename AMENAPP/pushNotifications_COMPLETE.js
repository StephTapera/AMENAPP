/**
 * Complete Push Notifications Module for AMENAPP
 * Compatible with Firebase Functions v7 (2nd generation)
 * 
 * Includes ALL notification types:
 * - Follow/Unfollow
 * - Follow Requests
 * - Comments
 * - Replies
 * - Mentions
 * - Likes/Amens
 * - Reposts
 * - Messages
 */

const {onDocumentCreated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {onCall} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();

// ============================================================================
// HELPER FUNCTION: Send Push Notification
// ============================================================================

async function sendPushNotificationToUser(userId, title, body, data = {}) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`⚠️ No FCM token for user ${userId}`);
      return null;
    }

    const message = {
      notification: {
        title,
        body,
      },
      data,
      token: fcmToken,
    };

    await admin.messaging().send(message);
    console.log(`✅ Push notification sent to ${userId}`);
    return {success: true};
  } catch (error) {
    console.error(`❌ Error sending push notification to ${userId}:`, error);
    return {success: false, error: error.message};
  }
}

// ============================================================================
// 1. FOLLOW NOTIFICATIONS (Already Deployed)
// ============================================================================

exports.onUserFollow = onDocumentCreated(
    {document: "follows/{followId}"},
    async (event) => {
      const followData = event.data.data();
      const {followerId, followingId} = followData;

      if (!followerId || !followingId) {
        console.log("⚠️ Missing followerId or followingId");
        return null;
      }

      try {
        const followerDoc = await db.collection("users").doc(followerId).get();
        const followerData = followerDoc.data();
        const followerName = followerData?.displayName || "Someone";

        const notification = {
          type: "follow",
          actorId: followerId,
          actorName: followerName,
          userId: followingId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(followingId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Follow notification created for ${followingId}`);

        await sendPushNotificationToUser(
            followingId,
            "New Follower",
            `${followerName} started following you`,
            {
              type: "follow",
              actorId: followerId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onUserFollow:", error);
        return null;
      }
    },
);

exports.onUserUnfollow = onDocumentDeleted(
    {document: "follows/{followId}"},
    async (event) => {
      const followData = event.data.data();
      const {followerId, followingId} = followData;

      if (!followerId || !followingId) {
        console.log("⚠️ Missing followerId or followingId");
        return null;
      }

      try {
        const notificationsQuery = await db.collection("users")
            .doc(followingId)
            .collection("notifications")
            .where("type", "==", "follow")
            .where("actorId", "==", followerId)
            .get();

        const batch = db.batch();
        notificationsQuery.forEach((doc) => {
          batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`✅ Deleted follow notification for ${followingId}`);

        return null;
      } catch (error) {
        console.error("❌ Error in onUserUnfollow:", error);
        return null;
      }
    },
);

// ============================================================================
// 2. COMMENT NOTIFICATIONS (NEW)
// ============================================================================

exports.onCommentCreate = onDocumentCreated(
    {document: "posts/{postId}/comments/{commentId}"},
    async (event) => {
      const {postId} = event.params;
      const commentData = event.data.data();

      try {
        // Get post to find the author
        const postDoc = await db.collection("posts").doc(postId).get();
        const postData = postDoc.data();

        if (!postData) {
          console.log("⚠️ Post not found");
          return null;
        }

        const postAuthorId = postData.authorId;
        const commentAuthorId = commentData.userId || commentData.authorId;

        // Don't notify if user comments on their own post
        if (postAuthorId === commentAuthorId) {
          return null;
        }

        // Get commenter's profile
        const commenterDoc = await db.collection("users").doc(commentAuthorId).get();
        const commenterData = commenterDoc.data();
        const commenterName = commenterData?.displayName || "Someone";

        // Create notification
        const notification = {
          type: "comment",
          actorId: commentAuthorId,
          actorName: commenterName,
          postId: postId,
          commentText: commentData.text,
          userId: postAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Comment notification created for ${postAuthorId}`);

        // Send push notification
        await sendPushNotificationToUser(
            postAuthorId,
            "New Comment",
            `${commenterName} commented on your post`,
            {
              type: "comment",
              actorId: commentAuthorId,
              postId: postId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onCommentCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// 3. REPLY NOTIFICATIONS (NEW)
// ============================================================================

exports.onCommentReply = onDocumentCreated(
    {document: "posts/{postId}/comments/{commentId}"},
    async (event) => {
      const {postId} = event.params;
      const commentData = event.data.data();

      // Only process if this is a reply (has parentCommentId)
      if (!commentData.parentCommentId) {
        return null;
      }

      try {
        // Get parent comment to find who to notify
        const parentCommentDoc = await db.collection("posts")
            .doc(postId)
            .collection("comments")
            .doc(commentData.parentCommentId)
            .get();

        if (!parentCommentDoc.exists) {
          console.log("⚠️ Parent comment not found");
          return null;
        }

        const parentCommentData = parentCommentDoc.data();
        const parentCommentAuthorId = parentCommentData.userId || parentCommentData.authorId;
        const replyAuthorId = commentData.userId || commentData.authorId;

        // Don't notify if user replies to their own comment
        if (parentCommentAuthorId === replyAuthorId) {
          return null;
        }

        // Get replier's profile
        const replierDoc = await db.collection("users").doc(replyAuthorId).get();
        const replierData = replierDoc.data();
        const replierName = replierData?.displayName || "Someone";

        // Create notification
        const notification = {
          type: "reply",
          actorId: replyAuthorId,
          actorName: replierName,
          postId: postId,
          commentText: commentData.text,
          userId: parentCommentAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(parentCommentAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Reply notification created for ${parentCommentAuthorId}`);

        // Send push notification
        await sendPushNotificationToUser(
            parentCommentAuthorId,
            "New Reply",
            `${replierName} replied to your comment`,
            {
              type: "reply",
              actorId: replyAuthorId,
              postId: postId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onCommentReply:", error);
        return null;
      }
    },
);

// ============================================================================
// 4. MENTION NOTIFICATIONS (NEW)
// ============================================================================

exports.onPostCreate = onDocumentCreated(
    {document: "posts/{postId}"},
    async (event) => {
      const postData = event.data.data();
      const {postId} = event.params;

      // Extract mentions from post content (simple regex for @username)
      const mentionRegex = /@(\w+)/g;
      const mentions = [...postData.content.matchAll(mentionRegex)]
          .map((match) => match[1]);

      if (mentions.length === 0) {
        return null;
      }

      try {
        // Get author's profile
        const authorDoc = await db.collection("users").doc(postData.authorId).get();
        const authorData = authorDoc.data();
        const authorName = authorData?.displayName || "Someone";

        // Create notification for each mentioned user
        const batch = db.batch();

        for (const username of mentions) {
          // Find user by username
          const userQuery = await db.collection("users")
              .where("username", "==", username)
              .limit(1)
              .get();

          if (!userQuery.empty) {
            const mentionedUserDoc = userQuery.docs[0];
            const mentionedUserId = mentionedUserDoc.id;

            // Don't notify if user mentions themselves
            if (mentionedUserId === postData.authorId) {
              continue;
            }

            const notificationRef = db.collection("users")
                .doc(mentionedUserId)
                .collection("notifications")
                .doc();

            batch.set(notificationRef, {
              type: "mention",
              actorId: postData.authorId,
              actorName: authorName,
              postId: postId,
              userId: mentionedUserId,
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Send push notification
            await sendPushNotificationToUser(
                mentionedUserId,
                "You were mentioned",
                `${authorName} mentioned you in a post`,
                {
                  type: "mention",
                  actorId: postData.authorId,
                  postId: postId,
                },
            );
          }
        }

        await batch.commit();
        console.log(`✅ Mention notifications created for ${mentions.length} users`);

        return null;
      } catch (error) {
        console.error("❌ Error in onPostCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// 5. LIKE/AMEN NOTIFICATIONS (NEW)
// ============================================================================

exports.onAmenCreate = onDocumentCreated(
    {document: "posts/{postId}/likes/{likeId}"},
    async (event) => {
      const {postId} = event.params;
      const likeData = event.data.data();

      try {
        // Get post to find the author
        const postDoc = await db.collection("posts").doc(postId).get();
        const postData = postDoc.data();

        if (!postData) {
          console.log("⚠️ Post not found");
          return null;
        }

        const postAuthorId = postData.authorId;
        const likerUserId = likeData.userId;

        // Don't notify if user likes their own post
        if (postAuthorId === likerUserId) {
          return null;
        }

        // Get liker's profile
        const likerDoc = await db.collection("users").doc(likerUserId).get();
        const likerData = likerDoc.data();
        const likerName = likerData?.displayName || "Someone";

        // Create notification
        const notification = {
          type: "amen",
          actorId: likerUserId,
          actorName: likerName,
          postId: postId,
          userId: postAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Amen notification created for ${postAuthorId}`);

        // Send push notification
        await sendPushNotificationToUser(
            postAuthorId,
            "New Amen",
            `${likerName} amened your post`,
            {
              type: "amen",
              actorId: likerUserId,
              postId: postId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onAmenCreate:", error);
        return null;
      }
    },
);

exports.onAmenDelete = onDocumentDeleted(
    {document: "posts/{postId}/likes/{likeId}"},
    async (event) => {
      const {postId} = event.params;
      const likeData = event.data.data();

      try {
        // Get post author
        const postDoc = await db.collection("posts").doc(postId).get();
        const postData = postDoc.data();

        if (!postData) return null;

        // Find and delete the amen notification
        const notificationsQuery = await db.collection("users")
            .doc(postData.authorId)
            .collection("notifications")
            .where("type", "==", "amen")
            .where("actorId", "==", likeData.userId)
            .where("postId", "==", postId)
            .get();

        const batch = db.batch();
        notificationsQuery.forEach((doc) => {
          batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`✅ Deleted amen notification for ${postData.authorId}`);

        return null;
      } catch (error) {
        console.error("❌ Error in onAmenDelete:", error);
        return null;
      }
    },
);

// ============================================================================
// 6. REPOST NOTIFICATIONS (NEW)
// ============================================================================

exports.onRepostCreate = onDocumentCreated(
    {document: "reposts/{repostId}"},
    async (event) => {
      const repostData = event.data.data();

      try {
        // Get original post to find the author
        const postDoc = await db.collection("posts").doc(repostData.postId).get();
        const postData = postDoc.data();

        if (!postData) {
          console.log("⚠️ Post not found");
          return null;
        }

        const postAuthorId = postData.authorId;
        const reposterId = repostData.userId;

        // Don't notify if user reposts their own post
        if (postAuthorId === reposterId) {
          return null;
        }

        // Get reposter's profile
        const reposterDoc = await db.collection("users").doc(reposterId).get();
        const reposterData = reposterDoc.data();
        const reposterName = reposterData?.displayName || "Someone";

        // Create notification
        const notification = {
          type: "repost",
          actorId: reposterId,
          actorName: reposterName,
          postId: repostData.postId,
          userId: postAuthorId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Repost notification created for ${postAuthorId}`);

        // Send push notification
        await sendPushNotificationToUser(
            postAuthorId,
            "Post Reposted",
            `${reposterName} reposted your post`,
            {
              type: "repost",
              actorId: reposterId,
              postId: repostData.postId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onRepostCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// 7. FOLLOW REQUEST NOTIFICATIONS (Already Deployed)
// ============================================================================

exports.onFollowRequestAccepted = onDocumentCreated(
    {document: "followRequests/{requestId}"},
    async (event) => {
      const requestData = event.data.data();
      const {fromUserId, toUserId, status} = requestData;

      if (status !== "accepted") {
        return null;
      }

      if (!fromUserId || !toUserId) {
        console.log("⚠️ Missing fromUserId or toUserId");
        return null;
      }

      try {
        const toUserDoc = await db.collection("users").doc(toUserId).get();
        const toUserData = toUserDoc.data();
        const toUserName = toUserData?.displayName || "Someone";

        const notification = {
          type: "followRequestAccepted",
          actorId: toUserId,
          actorName: toUserName,
          userId: fromUserId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection("users")
            .doc(fromUserId)
            .collection("notifications")
            .add(notification);

        console.log(`✅ Follow request accepted notification created for ${fromUserId}`);

        await sendPushNotificationToUser(
            fromUserId,
            "Follow Request Accepted",
            `${toUserName} accepted your follow request`,
            {
              type: "followRequestAccepted",
              actorId: toUserId,
            },
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onFollowRequestAccepted:", error);
        return null;
      }
    },
);

// ============================================================================
// 8. MESSAGE NOTIFICATIONS (Already Deployed)
// ============================================================================

exports.onMessageRequestAccepted = onDocumentCreated(
    {document: "conversations/{conversationId}"},
    async (event) => {
      const conversationData = event.data.data();
      const {participantIds, conversationStatus} = conversationData;

      if (conversationStatus !== "accepted" || !participantIds || participantIds.length !== 2) {
        return null;
      }

      try {
        const [user1Id, user2Id] = participantIds;

        const user1Doc = await db.collection("users").doc(user1Id).get();
        const user2Doc = await db.collection("users").doc(user2Id).get();

        const user1Data = user1Doc.data();
        const user2Data = user2Doc.data();

        const user1Name = user1Data?.displayName || "Someone";
        const user2Name = user2Data?.displayName || "Someone";

        await sendPushNotificationToUser(
            user1Id,
            "Message Request Accepted",
            `${user2Name} accepted your message request`,
            {
              type: "messageRequestAccepted",
              actorId: user2Id,
              conversationId: event.params.conversationId,
            },
        );

        await sendPushNotificationToUser(
            user2Id,
            "New Conversation",
            `You can now message ${user1Name}`,
            {
              type: "messageRequestAccepted",
              actorId: user1Id,
              conversationId: event.params.conversationId,
            },
        );

        console.log(`✅ Message request accepted notifications sent`);

        return null;
      } catch (error) {
        console.error("❌ Error in onMessageRequestAccepted:", error);
        return null;
      }
    },
);

// ============================================================================
// 9. MANUAL PUSH NOTIFICATION (Already Deployed)
// ============================================================================

exports.sendPushNotification = onCall(async (request) => {
  const {userId, title, body, data} = request.data;

  if (!userId || !title || !body) {
    throw new Error("Missing required parameters: userId, title, body");
  }

  try {
    const result = await sendPushNotificationToUser(userId, title, body, data || {});
    return result;
  } catch (error) {
    console.error("❌ Error in sendPushNotification:", error);
    throw new Error(`Failed to send notification: ${error.message}`);
  }
});
