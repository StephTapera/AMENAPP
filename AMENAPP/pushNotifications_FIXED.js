/**
 * Push Notifications Module for AMENAPP
 * Compatible with Firebase Functions v7 (2nd generation)
 */

const {onDocumentCreated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {onCall} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// Initialize Firestore
const db = admin.firestore();

// ============================================================================
// 1. SEND PUSH NOTIFICATION (Helper Function)
// ============================================================================

/**
 * Send push notification to a user
 * @param {string} userId - User ID to send notification to
 * @param {string} title - Notification title
 * @param {string} body - Notification body
 * @param {object} data - Additional data payload
 */
async function sendPushNotificationToUser(userId, title, body, data = {}) {
  try {
    // Get user's FCM token
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`⚠️ No FCM token for user ${userId}`);
      return null;
    }

    // Construct notification message
    const message = {
      notification: {
        title,
        body,
      },
      data,
      token: fcmToken,
    };

    // Send notification
    await admin.messaging().send(message);
    console.log(`✅ Push notification sent to ${userId}`);
    return {success: true};
  } catch (error) {
    console.error(`❌ Error sending push notification to ${userId}:`, error);
    return {success: false, error: error.message};
  }
}

// ============================================================================
// 2. ON USER FOLLOW - Send Notification
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
        // Get follower's profile
        const followerDoc = await db.collection("users").doc(followerId).get();
        const followerData = followerDoc.data();
        const followerName = followerData?.displayName || "Someone";

        // Create notification in Firestore
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

        // Send push notification
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

// ============================================================================
// 3. ON USER UNFOLLOW - Remove Notification
// ============================================================================

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
        // Find and delete the follow notification
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
// 4. ON FOLLOW REQUEST ACCEPTED - Send Notification
// ============================================================================

exports.onFollowRequestAccepted = onDocumentCreated(
    {document: "followRequests/{requestId}"},
    async (event) => {
      const requestData = event.data.data();
      const {fromUserId, toUserId, status} = requestData;

      // Only send notification when request is accepted
      if (status !== "accepted") {
        return null;
      }

      if (!fromUserId || !toUserId) {
        console.log("⚠️ Missing fromUserId or toUserId");
        return null;
      }

      try {
        // Get the user who accepted
        const toUserDoc = await db.collection("users").doc(toUserId).get();
        const toUserData = toUserDoc.data();
        const toUserName = toUserData?.displayName || "Someone";

        // Create notification
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

        // Send push notification
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
// 5. ON MESSAGE REQUEST ACCEPTED - Send Notification
// ============================================================================

exports.onMessageRequestAccepted = onDocumentCreated(
    {document: "conversations/{conversationId}"},
    async (event) => {
      const conversationData = event.data.data();
      const {participantIds, conversationStatus} = conversationData;

      // Only send notification when message request is accepted
      if (conversationStatus !== "accepted" || !participantIds || participantIds.length !== 2) {
        return null;
      }

      try {
        const [user1Id, user2Id] = participantIds;

        // Get both users' data
        const user1Doc = await db.collection("users").doc(user1Id).get();
        const user2Doc = await db.collection("users").doc(user2Id).get();

        const user1Data = user1Doc.data();
        const user2Data = user2Doc.data();

        const user1Name = user1Data?.displayName || "Someone";
        const user2Name = user2Data?.displayName || "Someone";

        // Send notification to user1
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

        // Send notification to user2
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
// 6. SEND PUSH NOTIFICATION (Callable Function)
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
