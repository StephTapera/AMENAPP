/**
 * Firebase Cloud Functions for AMENAPP Messaging
 * 
 * DEPLOYMENT INSTRUCTIONS:
 * 
 * 1. Install Firebase CLI:
 *    npm install -g firebase-tools
 * 
 * 2. Login to Firebase:
 *    firebase login
 * 
 * 3. Initialize functions in your project:
 *    firebase init functions
 *    - Select JavaScript or TypeScript
 *    - Install dependencies
 * 
 * 4. Replace functions/index.js with this file
 * 
 * 5. Install required dependencies:
 *    cd functions
 *    npm install firebase-admin firebase-functions
 * 
 * 6. Deploy:
 *    firebase deploy --only functions
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ============================================================================
// FUNCTION 1: Process FCM Queue (Send Push Notifications)
// ============================================================================

exports.processFCMQueue = functions.firestore
  .document('fcmQueue/{queueId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    console.log('📬 Processing notification:', notification);
    
    try {
      // Get recipient's FCM token
      const userDoc = await db.collection('users').doc(notification.recipientId).get();
      
      if (!userDoc.exists) {
        console.error('❌ Recipient user not found:', notification.recipientId);
        await snap.ref.update({ status: 'failed', error: 'User not found' });
        return;
      }
      
      const fcmToken = userDoc.data().fcmToken;
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for user:', notification.recipientId);
        await snap.ref.update({ status: 'no_token' });
        return;
      }
      
      // Build notification payload
      const message = {
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: {
          conversationId: notification.conversationId,
          messageId: notification.messageId || '',
          type: notification.type,
          senderId: notification.senderId,
        },
        token: fcmToken,
      };
      
      // Send notification
      const response = await messaging.send(message);
      console.log('✅ Notification sent successfully:', response);
      
      // Update queue status
      await snap.ref.update({
        status: 'sent',
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        response: response,
      });
      
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      await snap.ref.update({
        status: 'failed',
        error: error.message,
      });
    }
  });

// ============================================================================
// FUNCTION 2: Clean Up Disappeared Messages
// ============================================================================

exports.cleanupDisappearedMessages = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log('🧹 Starting cleanup of disappeared messages...');
    
    const now = admin.firestore.Timestamp.now();
    
    try {
      // Get all conversations
      const conversationsSnapshot = await db.collection('conversations').get();
      
      let totalDeleted = 0;
      
      for (const conversationDoc of conversationsSnapshot.docs) {
        const conversationId = conversationDoc.id;
        
        // Find messages that should have disappeared
        const messagesSnapshot = await db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .where('disappearAt', '<=', now)
          .get();
        
        if (messagesSnapshot.empty) {
          continue;
        }
        
        // Delete expired messages in batch
        const batch = db.batch();
        
        messagesSnapshot.docs.forEach((messageDoc) => {
          batch.delete(messageDoc.ref);
        });
        
        await batch.commit();
        
        totalDeleted += messagesSnapshot.size;
        console.log(`🗑️ Deleted ${messagesSnapshot.size} messages from conversation ${conversationId}`);
      }
      
      console.log(`✅ Cleanup complete. Total messages deleted: ${totalDeleted}`);
      
    } catch (error) {
      console.error('❌ Error during cleanup:', error);
    }
  });

// ============================================================================
// FUNCTION 3: Update Search Index
// ============================================================================

exports.updateSearchIndex = functions.firestore
  .document('conversations/{convId}/messages/{msgId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const conversationId = context.params.convId;
    const messageId = context.params.msgId;
    
    console.log('🔍 Updating search index for message:', messageId);
    
    try {
      // Extract searchable text
      const searchText = message.text.toLowerCase();
      
      // Create search index entry
      await db.collection('searchIndex').doc(`message_${messageId}`).set({
        type: 'message',
        conversationId: conversationId,
        messageId: messageId,
        text: searchText,
        senderId: message.senderId,
        senderName: message.senderName,
        timestamp: message.timestamp,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      console.log('✅ Search index updated for message:', messageId);
      
    } catch (error) {
      console.error('❌ Error updating search index:', error);
    }
  });

// ============================================================================
// FUNCTION 4: Auto-Decline Spam Requests
// ============================================================================

exports.checkSpamRequests = functions.firestore
  .document('conversations/{convId}')
  .onCreate(async (snap, context) => {
    const conversation = snap.data();
    
    // Only check pending message requests
    if (conversation.conversationStatus !== 'pending') {
      return;
    }
    
    console.log('🔍 Checking spam for conversation:', context.params.convId);
    
    try {
      const requesterId = conversation.requesterId;
      const participantIds = conversation.participantIds;
      
      // Find recipient (not the requester)
      const recipientId = participantIds.find(id => id !== requesterId);
      
      if (!recipientId) {
        return;
      }
      
      // Check recipient's privacy settings
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      
      if (!recipientDoc.exists) {
        return;
      }
      
      const autoDeclineSpam = recipientDoc.data().autoDeclineSpam || false;
      
      if (!autoDeclineSpam) {
        return;
      }
      
      // Check for spam indicators
      const isSpam = await checkSpamIndicators(requesterId, conversation);
      
      if (isSpam) {
        console.log('🚫 Spam detected, auto-declining request');
        
        // Auto-decline
        await snap.ref.update({
          conversationStatus: 'declined',
          declinedReason: 'auto_spam_detection',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      
    } catch (error) {
      console.error('❌ Error checking spam:', error);
    }
  });

// Helper function to check spam indicators
async function checkSpamIndicators(userId, conversation) {
  // Simple spam checks:
  // 1. Check if user has sent multiple requests recently
  const recentRequests = await db
    .collection('conversations')
    .where('requesterId', '==', userId)
    .where('conversationStatus', '==', 'pending')
    .where('createdAt', '>', admin.firestore.Timestamp.fromDate(new Date(Date.now() - 3600000))) // Last hour
    .get();
  
  if (recentRequests.size > 10) {
    return true; // Sent more than 10 requests in last hour
  }
  
  // 2. Check for spam keywords in first message
  const spamKeywords = ['click here', 'buy now', 'limited offer', 'prize', 'winner'];
  const messageText = conversation.lastMessageText?.toLowerCase() || '';
  
  for (const keyword of spamKeywords) {
    if (messageText.includes(keyword)) {
      return true;
    }
  }
  
  return false;
}

// ============================================================================
// FUNCTION 5: Clean Up Old FCM Queue
// ============================================================================

exports.cleanupFCMQueue = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    console.log('🧹 Cleaning up old FCM queue entries...');
    
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 7); // Delete entries older than 7 days
    
    try {
      const oldEntries = await db
        .collection('fcmQueue')
        .where('createdAt', '<', admin.firestore.Timestamp.fromDate(cutoffDate))
        .get();
      
      if (oldEntries.empty) {
        console.log('No old entries to delete');
        return;
      }
      
      const batch = db.batch();
      
      oldEntries.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });
      
      await batch.commit();
      
      console.log(`✅ Deleted ${oldEntries.size} old FCM queue entries`);
      
    } catch (error) {
      console.error('❌ Error cleaning up FCM queue:', error);
    }
  });

// ============================================================================
// FUNCTION 6: Update User Online Status
// ============================================================================

exports.updateUserStatus = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }
  
  const userId = context.auth.uid;
  const isOnline = data.isOnline;
  
  try {
    await db.collection('users').doc(userId).update({
      isOnline: isOnline,
      lastSeen: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`✅ Updated status for user ${userId}: ${isOnline ? 'online' : 'offline'}`);
    
    return { success: true };
  } catch (error) {
    console.error('❌ Error updating user status:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update status');
  }
});

// ============================================================================
// Export all functions
// ============================================================================

console.log('🚀 Cloud Functions initialized successfully');
