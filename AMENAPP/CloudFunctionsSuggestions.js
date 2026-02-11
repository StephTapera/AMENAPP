// ============================================================================
// AMENAPP CLOUD FUNCTIONS - Suggested Implementation
// ============================================================================
// This file shows the recommended Cloud Functions for your NotificationsView
// Place this code in your functions/index.js file
// ============================================================================

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin (only once)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ============================================================================
// 1. CREATE NOTIFICATION ON FOLLOW
// ============================================================================
// Triggered when a user follows another user
// Creates a notification in the followed user's notifications subcollection

exports.onFollowCreate = functions.firestore
    .document("follows/{followId}")
    .onCreate(async (snap, context) => {
      const followData = snap.data();
      const {followerId, followingId} = followData;

      if (!followerId || !followingId) {
        console.log("Missing followerId or followingId");
        return null;
      }

      // Get follower's profile for notification
      const followerDoc = await db.collection("users").doc(followerId).get();
      const followerData = followerDoc.data();

      // Create notification
      const notification = {
        type: "follow",
        actorId: followerId,
        actorName: followerData?.displayName || "Someone",
        userId: followingId, // Who receives the notification
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Add to user's notifications subcollection
      await db.collection("users")
          .doc(followingId)
          .collection("notifications")
          .add(notification);

      console.log(`✅ Follow notification created for ${followingId}`);
      return null;
    });

// ============================================================================
// 2. CREATE NOTIFICATION ON COMMENT
// ============================================================================
// Triggered when a comment is added to a post
// Creates a notification for the post author

exports.onCommentCreate = functions.firestore
    .document("posts/{postId}/comments/{commentId}")
    .onCreate(async (snap, context) => {
      const {postId} = context.params;
      const commentData = snap.data();

      // Get post to find the author
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();

      if (!postData) {
        console.log("Post not found");
        return null;
      }

      const postAuthorId = postData.authorId;
      const commentAuthorId = commentData.userId || commentData.authorId;

      // Don't notify if user comments on their own post
      if (postAuthorId === commentAuthorId) {
        return null;
      }

      // Get commenter's profile
      const commenterDoc = await db.collection("users")
          .doc(commentAuthorId).get();
      const commenterData = commenterDoc.data();

      // Create notification
      const notification = {
        type: "comment",
        actorId: commentAuthorId,
        actorName: commenterData?.displayName || "Someone",
        postId: postId,
        commentText: commentData.text,
        userId: postAuthorId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Add to post author's notifications
      await db.collection("users")
          .doc(postAuthorId)
          .collection("notifications")
          .add(notification);

      console.log(`✅ Comment notification created for ${postAuthorId}`);
      return null;
    });

// ============================================================================
// 3. CREATE NOTIFICATION ON AMEN (LIKE)
// ============================================================================
// Triggered when a user "amens" a post
// Creates a notification for the post author

exports.onAmenCreate = functions.firestore
    .document("posts/{postId}/likes/{likeId}")
    .onCreate(async (snap, context) => {
      const {postId} = context.params;
      const likeData = snap.data();

      // Get post to find the author
      const postDoc = await db.collection("posts").doc(postId).get();
      const postData = postDoc.data();

      if (!postData) {
        console.log("Post not found");
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

      // Create notification
      const notification = {
        type: "amen",
        actorId: likerUserId,
        actorName: likerData?.displayName || "Someone",
        postId: postId,
        userId: postAuthorId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Add to post author's notifications
      await db.collection("users")
          .doc(postAuthorId)
          .collection("notifications")
          .add(notification);

      console.log(`✅ Amen notification created for ${postAuthorId}`);
      return null;
    });

// ============================================================================
// 4. CREATE NOTIFICATION ON MENTION
// ============================================================================
// Triggered when a post mentions a user (via @username)
// Creates a notification for the mentioned user

exports.onPostCreate = functions.firestore
    .document("posts/{postId}")
    .onCreate(async (snap, context) => {
      const postData = snap.data();
      const {postId} = context.params;

      // Extract mentions from post content (simple regex for @username)
      const mentionRegex = /@(\w+)/g;
      const mentions = [...postData.content.matchAll(mentionRegex)]
          .map((match) => match[1]);

      if (mentions.length === 0) {
        return null;
      }

      // Get author's profile
      const authorDoc = await db.collection("users")
          .doc(postData.authorId).get();
      const authorData = authorDoc.data();

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
            actorName: authorData?.displayName || "Someone",
            postId: postId,
            userId: mentionedUserId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      console.log(`✅ Mention notifications created for ${mentions.length} users`);
      return null;
    });

// ============================================================================
// 5. CLEANUP DUPLICATE FOLLOW NOTIFICATIONS (Scheduled)
// ============================================================================
// Runs daily to clean up duplicate follow notifications
// This is called from your Swift code via cleanupDuplicateFollowNotifications()

exports.cleanupDuplicateFollowNotifications = functions.https
    .onCall(async (data, context) => {
      // Verify authentication
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be authenticated",
        );
      }

      const userId = context.auth.uid;
      let deletedCount = 0;

      try {
        // Get all follow notifications for this user
        const notificationsRef = db.collection("users")
            .doc(userId)
            .collection("notifications")
            .where("type", "==", "follow");

        const snapshot = await notificationsRef.get();

        // Group by actorId
        const grouped = {};
        snapshot.forEach((doc) => {
          const data = doc.data();
          const actorId = data.actorId;

          if (!grouped[actorId]) {
            grouped[actorId] = [];
          }
          grouped[actorId].push({id: doc.id, data});
        });

        // Delete duplicates (keep the newest)
        const batch = db.batch();

        for (const actorId in grouped) {
          if (grouped[actorId].length > 1) {
            // Sort by createdAt (newest first)
            const sorted = grouped[actorId].sort((a, b) => {
              const aTime = a.data.createdAt?.toMillis() || 0;
              const bTime = b.data.createdAt?.toMillis() || 0;
              return bTime - aTime;
            });

            // Keep first (newest), delete rest
            for (let i = 1; i < sorted.length; i++) {
              const docRef = db.collection("users")
                  .doc(userId)
                  .collection("notifications")
                  .doc(sorted[i].id);
              batch.delete(docRef);
              deletedCount++;
            }
          }
        }

        await batch.commit();

        console.log(`✅ Cleaned up ${deletedCount} duplicate notifications`);
        return {success: true, deletedCount};
      } catch (error) {
        console.error("❌ Error cleaning up notifications:", error);
        throw new functions.https.HttpsError("internal", error.message);
      }
    });

// ============================================================================
// 6. SEND PUSH NOTIFICATION (via FCM)
// ============================================================================
// Triggered when a notification is created
// Sends a push notification to the user's device

exports.sendPushNotification = functions.firestore
    .document("users/{userId}/notifications/{notificationId}")
    .onCreate(async (snap, context) => {
      const {userId} = context.params;
      const notificationData = snap.data();

      // Get user's FCM token
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;

      if (!fcmToken) {
        console.log(`No FCM token for user ${userId}`);
        return null;
      }

      // Construct notification message
      let title = "AMENAPP";
      let body = "";

      switch (notificationData.type) {
        case "follow":
          title = "New Follower";
          body = `${notificationData.actorName} started following you`;
          break;
        case "amen":
          title = "New Amen";
          body = `${notificationData.actorName} amened your post`;
          break;
        case "comment":
          title = "New Comment";
          body = `${notificationData.actorName} commented on your post`;
          break;
        case "mention":
          title = "You were mentioned";
          body = `${notificationData.actorName} mentioned you in a post`;
          break;
        default:
          body = "You have a new notification";
      }

      const message = {
        notification: {
          title,
          body,
        },
        data: {
          type: notificationData.type,
          actorId: notificationData.actorId || "",
          postId: notificationData.postId || "",
        },
        token: fcmToken,
      };

      try {
        await admin.messaging().send(message);
        console.log(`✅ Push notification sent to ${userId}`);
      } catch (error) {
        console.error(`❌ Error sending push notification:`, error);
      }

      return null;
    });

// ============================================================================
// 7. UPDATE UNREAD COUNT (Aggregation)
// ============================================================================
// Updates the unread notification count in the user document
// This is triggered when notifications are created/updated

exports.updateUnreadCount = functions.firestore
    .document("users/{userId}/notifications/{notificationId}")
    .onWrite(async (change, context) => {
      const {userId} = context.params;

      // Count unread notifications
      const unreadQuery = await db.collection("users")
          .doc(userId)
          .collection("notifications")
          .where("read", "==", false)
          .get();

      const unreadCount = unreadQuery.size;

      // Update user document
      await db.collection("users").doc(userId).update({
        unreadNotificationsCount: unreadCount,
      });

      console.log(`✅ Updated unread count for ${userId}: ${unreadCount}`);
      return null;
    });

// ============================================================================
// 8. DELETE NOTIFICATION ON UNLIKE/UNFOLLOW
// ============================================================================
// Clean up notifications when actions are reversed

exports.onFollowDelete = functions.firestore
    .document("follows/{followId}")
    .onDelete(async (snap, context) => {
      const followData = snap.data();
      const {followerId, followingId} = followData;

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
    });

exports.onAmenDelete = functions.firestore
    .document("posts/{postId}/likes/{likeId}")
    .onDelete(async (snap, context) => {
      const {postId} = context.params;
      const likeData = snap.data();

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
    });
