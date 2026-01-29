/**
 * Messaging Cloud Functions
 * 
 * Handles:
 * - Conversation creation and management
 * - Message sending with metadata updates
 * - Unread count management
 * - Message read receipts
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// MARK: - Create Conversation

/**
 * Callable function to create a new conversation
 * 
 * Parameters:
 * - participantIds: string[] - Array of user IDs
 * - isGroup: boolean - Whether this is a group conversation
 * - groupName?: string - Name for group conversations
 * 
 * Returns:
 * - conversationId: string - ID of created conversation
 */
export const createConversation = functions.https.onCall(
  async (data, context) => {
    // Check authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to create a conversation"
      );
    }

    const currentUserId = context.auth.uid;
    const {participantIds, isGroup, groupName} = data;

    console.log(`📱 Creating conversation for user ${currentUserId}`);

    try {
      // Validate input
      if (!participantIds || !Array.isArray(participantIds)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "participantIds must be an array"
        );
      }

      // Add current user to participants if not already included
      const allParticipants = [...new Set([currentUserId, ...participantIds])];

      // For direct messages, check if conversation already exists
      if (!isGroup && allParticipants.length === 2) {
        const existingConversations = await db
          .collection("conversations")
          .where("participantIds", "array-contains", currentUserId)
          .where("isGroup", "==", false)
          .get();

        for (const doc of existingConversations.docs) {
          const conv = doc.data();
          if (
            conv.participantIds.length === 2 &&
            conv.participantIds.includes(allParticipants[0]) &&
            conv.participantIds.includes(allParticipants[1])
          ) {
            console.log(`✅ Found existing conversation: ${doc.id}`);
            return {conversationId: doc.id, existed: true};
          }
        }
      }

      // Get participant names
      const participantNames: {[key: string]: string} = {};
      for (const userId of allParticipants) {
        const userDoc = await db.collection("users").doc(userId).get();
        const userData = userDoc.data();
        participantNames[userId] = userData?.fullName || "Unknown User";
      }

      // Create conversation
      const conversationRef = await db.collection("conversations").add({
        participantIds: allParticipants,
        participantNames: participantNames,
        isGroup: isGroup || false,
        groupName: groupName || null,
        groupAvatarUrl: null,
        lastMessage: null,
        lastMessageText: "",
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        unreadCounts: {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`✅ Created conversation: ${conversationRef.id}`);

      return {conversationId: conversationRef.id, existed: false};
    } catch (error) {
      console.error("Error creating conversation:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to create conversation",
        error
      );
    }
  }
);

// MARK: - Send Message

/**
 * Callable function to send a message
 * 
 * Parameters:
 * - conversationId: string - ID of the conversation
 * - text: string - Message text
 * - replyToMessageId?: string - ID of message being replied to
 * 
 * Returns:
 * - messageId: string - ID of created message
 */
export const sendMessage = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to send a message"
    );
  }

  const currentUserId = context.auth.uid;
  const {conversationId, text, replyToMessageId} = data;

  console.log(`💬 Sending message to conversation ${conversationId}`);

  try {
    // Validate input
    if (!conversationId || !text) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "conversationId and text are required"
      );
    }

    // Get conversation
    const conversationDoc = await db
      .collection("conversations")
      .doc(conversationId)
      .get();

    if (!conversationDoc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Conversation not found"
      );
    }

    const conversationData = conversationDoc.data();

    // Check if user is participant
    if (!conversationData?.participantIds.includes(currentUserId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "User is not a participant in this conversation"
      );
    }

    // Get sender info
    const senderDoc = await db.collection("users").doc(currentUserId).get();
    const senderData = senderDoc.data();
    const senderName = senderData?.fullName || "Unknown User";

    // Handle reply-to message
    let replyTo = null;
    if (replyToMessageId) {
      const replyToDoc = await db
        .collection("conversations")
        .doc(conversationId)
        .collection("messages")
        .doc(replyToMessageId)
        .get();

      if (replyToDoc.exists) {
        const replyToData = replyToDoc.data();
        replyTo = {
          messageId: replyToMessageId,
          text: replyToData?.text || "",
          senderId: replyToData?.senderId || "",
          senderName: replyToData?.senderName || "",
        };
      }
    }

    // Create message
    const messageRef = await db
      .collection("conversations")
      .doc(conversationId)
      .collection("messages")
      .add({
        conversationId: conversationId,
        senderId: currentUserId,
        senderName: senderName,
        text: text,
        attachments: [],
        reactions: [],
        replyTo: replyTo,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        readBy: [currentUserId],
      });

    // Update conversation metadata
    const unreadCounts: {[key: string]: number} = {};
    for (const participantId of conversationData.participantIds) {
      if (participantId !== currentUserId) {
        const currentCount =
          conversationData.unreadCounts?.[participantId] || 0;
        unreadCounts[participantId] = currentCount + 1;
      } else {
        unreadCounts[participantId] = 0;
      }
    }

    await db
      .collection("conversations")
      .doc(conversationId)
      .update({
        lastMessage: messageRef.id,
        lastMessageText: text,
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        unreadCounts: unreadCounts,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.log(`✅ Message sent: ${messageRef.id}`);

    return {messageId: messageRef.id};
  } catch (error) {
    console.error("Error sending message:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send message",
      error
    );
  }
});

// MARK: - Mark Messages as Read

/**
 * Callable function to mark messages as read
 * 
 * Parameters:
 * - conversationId: string - ID of the conversation
 * - messageIds?: string[] - Specific message IDs to mark (optional)
 * 
 * Returns:
 * - success: boolean
 */
export const markMessagesAsRead = functions.https.onCall(
  async (data, context) => {
    // Check authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const currentUserId = context.auth.uid;
    const {conversationId, messageIds} = data;

    console.log(
      `✅ Marking messages as read in conversation ${conversationId}`
    );

    try {
      // Validate input
      if (!conversationId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "conversationId is required"
        );
      }

      const batch = db.batch();

      // If specific message IDs provided, mark only those
      if (messageIds && Array.isArray(messageIds)) {
        for (const messageId of messageIds) {
          const messageRef = db
            .collection("conversations")
            .doc(conversationId)
            .collection("messages")
            .doc(messageId);

          batch.update(messageRef, {
            readBy: admin.firestore.FieldValue.arrayUnion(currentUserId),
          });
        }
      } else {
        // Mark all unread messages as read
        const unreadMessages = await db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .where("readBy", "not-in", [[currentUserId]])
          .get();

        for (const doc of unreadMessages.docs) {
          batch.update(doc.ref, {
            readBy: admin.firestore.FieldValue.arrayUnion(currentUserId),
          });
        }
      }

      // Update conversation unread count
      const conversationRef = db
        .collection("conversations")
        .doc(conversationId);

      batch.update(conversationRef, {
        [`unreadCounts.${currentUserId}`]: 0,
      });

      await batch.commit();

      console.log(`✅ Messages marked as read for user ${currentUserId}`);

      return {success: true};
    } catch (error) {
      console.error("Error marking messages as read:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to mark messages as read",
        error
      );
    }
  }
);

// MARK: - Delete Message

/**
 * Callable function to delete a message
 * 
 * Parameters:
 * - conversationId: string - ID of the conversation
 * - messageId: string - ID of the message to delete
 * 
 * Returns:
 * - success: boolean
 */
export const deleteMessage = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const currentUserId = context.auth.uid;
  const {conversationId, messageId} = data;

  console.log(`🗑️ Deleting message ${messageId}`);

  try {
    // Validate input
    if (!conversationId || !messageId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "conversationId and messageId are required"
      );
    }

    // Get message to check ownership
    const messageDoc = await db
      .collection("conversations")
      .doc(conversationId)
      .collection("messages")
      .doc(messageId)
      .get();

    if (!messageDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Message not found");
    }

    const messageData = messageDoc.data();

    // Only allow sender to delete their message
    if (messageData?.senderId !== currentUserId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You can only delete your own messages"
      );
    }

    // Delete message
    await messageDoc.ref.delete();

    console.log(`✅ Message deleted: ${messageId}`);

    return {success: true};
  } catch (error) {
    console.error("Error deleting message:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to delete message",
      error
    );
  }
});

// MARK: - Update Typing Status

/**
 * Trigger: Clean up old typing indicators
 * Runs every 5 minutes
 */
export const cleanupTypingIndicators = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    console.log("🧹 Cleaning up old typing indicators");

    try {
      const fiveMinutesAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 5 * 60 * 1000)
      );

      // Get all conversations
      const conversations = await db.collection("conversations").get();

      const batch = db.batch();
      let deleteCount = 0;

      for (const conversationDoc of conversations.docs) {
        const typingDocs = await conversationDoc.ref
          .collection("typing")
          .where("timestamp", "<", fiveMinutesAgo)
          .get();

        for (const typingDoc of typingDocs.docs) {
          batch.delete(typingDoc.ref);
          deleteCount++;
        }
      }

      if (deleteCount > 0) {
        await batch.commit();
        console.log(`✅ Deleted ${deleteCount} old typing indicators`);
      } else {
        console.log("No old typing indicators to delete");
      }

      return null;
    } catch (error) {
      console.error("Error cleaning up typing indicators:", error);
      return null;
    }
  });
