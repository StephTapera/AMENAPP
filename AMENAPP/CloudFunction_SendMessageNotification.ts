/**
 * Cloud Function: Send push notification when a new message is sent
 * 
 * Deploy with: firebase deploy --only functions:sendMessageNotification
 * 
 * Trigger: Firestore onCreate in conversations/{conversationId}/messages/{messageId}
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Initialize Admin SDK (only once)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

interface Message {
  senderId: string;
  senderName: string;
  text: string;
  timestamp: admin.firestore.Timestamp;
  isRead: boolean;
  attachments?: Array<{
    type: string;
    url: string;
  }>;
}

interface Conversation {
  participantIds: string[];
  participantNames: Record<string, string>;
  conversationStatus: string;
  isGroup: boolean;
  groupName?: string;
  mutedBy?: string[];
}

export const sendMessageNotification = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    try {
      const message = snapshot.data() as Message;
      const conversationId = context.params.conversationId;
      const messageId = context.params.messageId;

      console.log(`📨 New message in conversation ${conversationId}`);

      // Get conversation details
      const conversationDoc = await db
        .collection("conversations")
        .doc(conversationId)
        .get();

      if (!conversationDoc.exists) {
        console.log("❌ Conversation not found");
        return;
      }

      const conversation = conversationDoc.data() as Conversation;

      // Don't send notifications for pending conversations (message requests)
      if (conversation.conversationStatus === "pending") {
        console.log("⏸️ Skipping notification for pending conversation");
        return;
      }

      // Get all participants except the sender
      const recipientIds = conversation.participantIds.filter(
        (id) => id !== message.senderId
      );

      if (recipientIds.length === 0) {
        console.log("⚠️ No recipients to notify");
        return;
      }

      // Get FCM tokens for all recipients
      const recipientTokens: Record<string, string> = {};
      
      for (const recipientId of recipientIds) {
        const userDoc = await db.collection("users").doc(recipientId).get();
        
        if (userDoc.exists) {
          const userData = userDoc.data();
          const fcmToken = userData?.fcmToken;
          
          if (fcmToken) {
            // Check if conversation is muted
            const isMuted = conversation.mutedBy?.includes(recipientId) ?? false;
            
            if (!isMuted) {
              recipientTokens[recipientId] = fcmToken;
            } else {
              console.log(`🔕 Conversation muted for user ${recipientId}`);
            }
          }
        }
      }

      if (Object.keys(recipientTokens).length === 0) {
        console.log("⚠️ No FCM tokens found for recipients");
        return;
      }

      // Prepare notification content
      const senderName = message.senderName || "Someone";
      let notificationBody = message.text;

      // Handle attachments
      if (message.attachments && message.attachments.length > 0) {
        const attachment = message.attachments[0];
        switch (attachment.type) {
          case "photo":
            notificationBody = "📷 Photo";
            break;
          case "video":
            notificationBody = "🎥 Video";
            break;
          case "audio":
            notificationBody = "🎤 Voice message";
            break;
          case "file":
            notificationBody = "📎 File";
            break;
        }
      }

      // Truncate long messages
      if (notificationBody.length > 100) {
        notificationBody = notificationBody.substring(0, 97) + "...";
      }

      // Determine conversation name for notification title
      let conversationName: string;
      if (conversation.isGroup) {
        conversationName = conversation.groupName || "Group Chat";
      } else {
        conversationName = senderName;
      }

      // Send notifications to all recipients
      const promises = Object.entries(recipientTokens).map(
        async ([recipientId, token]) => {
          try {
            const notificationMessage: admin.messaging.Message = {
              token: token,
              notification: {
                title: conversation.isGroup 
                  ? `${senderName} in ${conversationName}`
                  : conversationName,
                body: notificationBody,
              },
              data: {
                conversationId: conversationId,
                messageId: messageId,
                senderId: message.senderId,
                type: "message",
              },
              apns: {
                payload: {
                  aps: {
                    sound: "default",
                    badge: 1, // Will be updated to actual count
                    category: "MESSAGE",
                    threadId: conversationId, // Group notifications by conversation
                  },
                },
              },
              android: {
                notification: {
                  sound: "default",
                  clickAction: "FLUTTER_NOTIFICATION_CLICK",
                  channelId: "messages",
                },
              },
            };

            const response = await messaging.send(notificationMessage);
            console.log(`✅ Notification sent to ${recipientId}: ${response}`);
            
            return { success: true, recipientId };
          } catch (error) {
            console.error(`❌ Error sending to ${recipientId}:`, error);
            
            // If token is invalid, remove it from user profile
            if (
              error instanceof Error && 
              (error.message.includes("not-found") || 
               error.message.includes("invalid-registration-token"))
            ) {
              await db.collection("users").doc(recipientId).update({
                fcmToken: admin.firestore.FieldValue.delete(),
              });
              console.log(`🗑️ Removed invalid token for user ${recipientId}`);
            }
            
            return { success: false, recipientId, error };
          }
        }
      );

      const results = await Promise.all(promises);
      
      const successCount = results.filter((r) => r.success).length;
      console.log(`📊 Sent ${successCount}/${results.length} notifications`);

    } catch (error) {
      console.error("❌ Error in sendMessageNotification:", error);
    }
  });

/**
 * Update badge count for a user
 * Called when messages are read or unread count changes
 */
export const updateBadgeCount = functions.firestore
  .document("conversations/{conversationId}")
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      // Check if unreadCounts changed
      const beforeUnread = beforeData.unreadCounts || {};
      const afterUnread = afterData.unreadCounts || {};
      
      // Get all users whose unread count changed
      const affectedUserIds = new Set([
        ...Object.keys(beforeUnread),
        ...Object.keys(afterUnread),
      ]);
      
      for (const userId of affectedUserIds) {
        const beforeCount = beforeUnread[userId] || 0;
        const afterCount = afterUnread[userId] || 0;
        
        if (beforeCount !== afterCount) {
          // Calculate total unread across all conversations
          await updateUserBadge(userId);
        }
      }
    } catch (error) {
      console.error("❌ Error updating badge count:", error);
    }
  });

async function updateUserBadge(userId: string) {
  try {
    // Get all conversations for user
    const conversationsSnapshot = await db
      .collection("conversations")
      .where("participantIds", "array-contains", userId)
      .where("conversationStatus", "==", "accepted")
      .get();
    
    let totalUnread = 0;
    
    conversationsSnapshot.forEach((doc) => {
      const conversation = doc.data();
      const unreadCounts = conversation.unreadCounts || {};
      totalUnread += unreadCounts[userId] || 0;
    });
    
    // Get user's FCM token
    const userDoc = await db.collection("users").doc(userId).get();
    
    if (userDoc.exists) {
      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;
      
      if (fcmToken) {
        // Send silent notification with badge update
        await messaging.send({
          token: fcmToken,
          apns: {
            payload: {
              aps: {
                badge: totalUnread,
                contentAvailable: true,
              },
            },
          },
          android: {
            data: {
              badge: totalUnread.toString(),
            },
          },
        });
        
        console.log(`🔔 Updated badge to ${totalUnread} for user ${userId}`);
      }
    }
  } catch (error) {
    console.error(`❌ Error updating badge for user ${userId}:`, error);
  }
}
