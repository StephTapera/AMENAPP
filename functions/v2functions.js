/**
 * v2functions.js
 * All gen-2 (Firebase Functions v2) inline trigger definitions.
 * Kept in a separate file so that index.js (which contains gen-1 functions)
 * does not import v2 SDKs — the Firebase CLI infers generation from the SDK
 * used per-file, and mixing imports caused it to apply v2 CPU/concurrency
 * settings to the gen-1 cancelAllSubscriptions and stripeWebhook functions.
 */

const admin = require("firebase-admin");
const {onValueCreated} = require("firebase-functions/v2/database");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

function isSundayForUser(uid) {
  return require("./shabbatMiddleware").isSundayForUser(uid);
}

// ============================================================================
// REALTIME DATABASE: COMMENT + REPLY NOTIFICATIONS (merged single trigger)
// Previously two separate triggers fired on every write to the same RTDB path,
// each short-circuiting on parentId. Merged into one to halve invocation cost.
// ============================================================================

exports.onRealtimeCommentCreate = onValueCreated(
    {
      ref: "/postInteractions/{postId}/comments/{commentId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const commentId = event.params.commentId;
      const commentData = event.data.val();
      const isReply = !!commentData.parentId;

      console.log(`${isReply ? "💬 New reply" : "📝 New comment"} on post ${postId}: ${commentId}`);

      try {
        const authorId = commentData.userId;

        // ── Shabbat guard ────────────────────────────────────────────────
        if (await isSundayForUser(authorId)) {
          console.log(`🕊️ Shabbat Mode active for ${authorId} — skipping notification`);
          return null;
        }

        if (isReply) {
          // ── Reply branch ──────────────────────────────────────────────
          const parentSnap = await admin.database()
              .ref(`postInteractions/${postId}/comments/${commentData.parentId}`)
              .once("value");
          if (!parentSnap.exists()) {
            console.log("⚠️ Parent comment not found");
            return null;
          }
          const parentAuthorId = parentSnap.val().userId;
          if (parentAuthorId === authorId) {
            console.log("⏭️ Skipping - user replied to their own comment");
            return null;
          }

          const actorDoc = await admin.firestore().collection("users").doc(authorId).get();
          const actorData = actorDoc.data();
          const actorName = actorData?.displayName || "Someone";
          const actorProfileImageURL = actorData?.profileImageURL || actorData?.profilePictureURL || "";

          await admin.firestore()
              .collection("users").doc(parentAuthorId).collection("notifications")
              .add({
                type: "reply",
                actorId: authorId,
                actorName,
                actorUsername: actorData?.username || "",
                actorProfileImageURL,
                postId,
                commentText: commentData.content || commentData.text || "",
                userId: parentAuthorId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
          console.log(`✅ Reply notification created for user ${parentAuthorId}`);

          const recipientDoc = await admin.firestore().collection("users").doc(parentAuthorId).get();
          const fcmToken = recipientDoc.data()?.fcmToken;
          if (fcmToken) {
            await admin.messaging().send({
              notification: { title: "New Reply", body: `${actorName} replied to your comment` },
              data: { type: "reply", actorId: authorId, postId },
              token: fcmToken,
            });
          }
        } else {
          // ── Top-level comment branch ──────────────────────────────────
          const postDoc = await admin.firestore().collection("posts").doc(postId).get();
          if (!postDoc.exists) {
            console.log("⚠️ Post not found");
            return null;
          }
          const postAuthorId = postDoc.data().userId;
          if (postAuthorId === authorId) {
            console.log("⏭️ Skipping - user commented on their own post");
            return null;
          }

          const actorDoc = await admin.firestore().collection("users").doc(authorId).get();
          const actorData = actorDoc.data();
          const actorName = actorData?.displayName || "Someone";
          const actorProfileImageURL = actorData?.profileImageURL || actorData?.profilePictureURL || "";

          await admin.firestore()
              .collection("users").doc(postAuthorId).collection("notifications")
              .add({
                type: "comment",
                actorId: authorId,
                actorName,
                actorUsername: actorData?.username || "",
                actorProfileImageURL,
                postId,
                commentText: commentData.content || commentData.text || "",
                userId: postAuthorId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
          console.log(`✅ Comment notification created for user ${postAuthorId}`);

          const recipientDoc = await admin.firestore().collection("users").doc(postAuthorId).get();
          const fcmToken = recipientDoc.data()?.fcmToken;
          if (fcmToken) {
            await admin.messaging().send({
              notification: { title: "New Comment", body: `${actorName} commented on your post` },
              data: { type: "comment", actorId: authorId, postId },
              token: fcmToken,
            });
          }
        }

        return { success: true };
      } catch (error) {
        console.error("❌ Error in onRealtimeCommentCreate:", error);
        return null;
      }
    },
);

// ============================================================================
// FIRESTORE: MESSAGE NOTIFICATIONS
// ============================================================================

/**
 * Triggers when a new message is sent in a conversation
 * Path: conversations/{conversationId}/messages/{messageId}
 */
exports.onMessageSent = onDocumentCreated(
    {
      document: "conversations/{conversationId}/messages/{messageId}",
      region: "us-central1",
    },
    async (event) => {
      const conversationId = event.params.conversationId;
      const messageId = event.params.messageId;
      const messageData = event.data.data();

      console.log(`💬 New message in conversation ${conversationId}: ${messageId}`);

      try {
        const senderId = messageData.senderId;

        // ── Shabbat guard ────────────────────────────────────────────────
        if (await isSundayForUser(senderId)) {
          console.log(`🕊️ Shabbat Mode active for ${senderId} — skipping message notification`);
          return null;
        }
        // ────────────────────────────────────────────────────────────────
        const messageText = messageData.text || "";

        // Get conversation to find recipients
        const conversationDoc = await admin.firestore()
            .collection("conversations")
            .doc(conversationId)
            .get();

        if (!conversationDoc.exists) {
          console.log("⚠️ Conversation not found");
          return null;
        }

        const conversationData = conversationDoc.data();
        const participantIds = conversationData.participantIds || [];
        const conversationStatus = conversationData.conversationStatus || "accepted";
        const isGroup = conversationData.isGroup || false;
        const groupName = conversationData.groupName;

        // Get sender info
        const senderDoc = await admin.firestore()
            .collection("users")
            .doc(senderId)
            .get();

        const senderData = senderDoc.data();
        const senderName = senderData?.displayName || "Someone";
        const senderIsPrivate = senderData?.isPrivateAccount || false;

        // Send notification to all participants except sender
        const recipients = participantIds.filter((id) => id !== senderId);

        for (const recipientId of recipients) {
          const recipientDoc = await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .get();

          const recipientData = recipientDoc.data();
          const recipientIsPrivate = recipientData?.isPrivateAccount || false;

          const senderBlockedUsers = senderData?.blockedUsers || [];
          const recipientBlockedUsers = recipientData?.blockedUsers || [];
          const isBlocked = senderBlockedUsers.includes(recipientId) ||
                          recipientBlockedUsers.includes(senderId);

          const shouldHidePreview = senderIsPrivate || recipientIsPrivate || isBlocked;
          const safeMessageText = shouldHidePreview ? "" : messageText.substring(0, 100);

          // Create notification
          const notification = {
            type: conversationStatus === "pending" ? "message_request" : "message",
            actorId: senderId,
            actorName: senderName,
            conversationId: conversationId,
            messageText: safeMessageText,
            userId: recipientId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          await admin.firestore()
              .collection("users")
              .doc(recipientId)
              .collection("notifications")
              .add(notification);

          console.log(`✅ Message notification created for user ${recipientId}${shouldHidePreview ? " (preview hidden)" : ""}`);

          // Send push notification
          const fcmToken = recipientData?.fcmToken;

          if (fcmToken) {
            const notificationTitle = conversationStatus === "pending" ?
              "New Message Request" :
              isGroup ? groupName || "Group Message" : senderName;

            const notificationBody = conversationStatus === "pending" ?
              `${senderName} wants to message you` :
              shouldHidePreview ? "New message" : messageText.substring(0, 100);

            await admin.messaging().send({
              notification: {
                title: notificationTitle,
                body: notificationBody,
              },
              data: {
                type: conversationStatus === "pending" ? "message_request" : "message",
                actorId: senderId,
                conversationId: conversationId,
              },
              token: fcmToken,
            });

            console.log(`✅ Push notification sent to ${recipientId}${shouldHidePreview ? " (generic message)" : ""}`);
          }
        }

        return {success: true};
      } catch (error) {
        console.error("❌ Error in onMessageSent:", error);
        return null;
      }
    },
);

// ============================================================================
// SCHEDULED: DAILY NOTIFICATION DIGEST PUSH
// Runs at 8:00 AM UTC daily.
// ============================================================================

exports.sendDailyNotificationDigest = onSchedule(
    {schedule: "0 8 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const db = admin.firestore();
      const today = new Date();
      today.setUTCHours(0, 0, 0, 0);

      console.log("⏰ Running daily notification digest delivery...");

      try {
        const usersSnap = await db.collection("users")
            .where("notificationSettings.digestMode", "==", true)
            .get();

        if (usersSnap.empty) {
          console.log("ℹ️ No users with digest mode enabled");
          return;
        }

        let deliveredCount = 0;

        for (const userDoc of usersSnap.docs) {
          const userId = userDoc.id;
          const userData = userDoc.data();

          const deviceTokensSnap = await db.collection("users")
              .doc(userId)
              .collection("deviceTokens")
              .where("enabled", "==", true)
              .limit(1)
              .get();

          const hasToken = !deviceTokensSnap.empty || !!userData.fcmToken;
          if (!hasToken) continue;

          const unreadSnap = await db.collection("users")
              .doc(userId)
              .collection("notifications")
              .where("read", "==", false)
              .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(today))
              .get();

          if (unreadSnap.empty) continue;

          const typeCounts = {};
          for (const doc of unreadSnap.docs) {
            const t = doc.data().type || "activity";
            typeCounts[t] = (typeCounts[t] || 0) + 1;
          }

          const summaryParts = Object.entries(typeCounts).map(([type, count]) => {
            const label = {
              follow: "new follower",
              amen: "amen",
              comment: "comment",
              reply: "reply",
              mention: "mention",
              repost: "repost",
            }[type] || "notification";
            return `${count} ${label}${count === 1 ? "" : "s"}`;
          });

          const body = summaryParts.slice(0, 3).join(", ") +
              (summaryParts.length > 3 ? ` +${summaryParts.length - 3} more` : "");

          const digestId = `${userId}_${today.getTime()}`;

          const tokens = deviceTokensSnap.empty ?
              (userData.fcmToken ? [userData.fcmToken] : []) :
              deviceTokensSnap.docs.map((d) => d.data().token).filter(Boolean);

          const staleTokens = [];
          await Promise.all(tokens.map(async (token) => {
            try {
              await admin.messaging().send({
                notification: {
                  title: "Your Daily Summary",
                  body,
                },
                data: {
                  type: "digest",
                  digestId,
                  deepLink: `amen://notifications/digest/${digestId}`,
                  unreadCount: String(unreadSnap.size),
                },
                token,
              });
            } catch (err) {
              if (err.code === "messaging/registration-token-not-registered" ||
                  err.code === "messaging/invalid-registration-token") {
                staleTokens.push(token);
              }
            }
          }));

          if (staleTokens.length > 0) {
            const batch = db.batch();
            deviceTokensSnap.docs.forEach((d) => {
              if (staleTokens.includes(d.data().token)) batch.delete(d.ref);
            });
            await batch.commit();
          }

          await db.collection("notificationDigests").doc(digestId).set({
            userId,
            period: "daily",
            itemCount: unreadSnap.size,
            typeCounts,
            delivered: true,
            deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            opened: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          deliveredCount++;
        }

        console.log(`✅ Digest delivery complete — sent to ${deliveredCount} user(s)`);
      } catch (error) {
        console.error("❌ Error in sendDailyNotificationDigest:", error);
      }
    },
);
