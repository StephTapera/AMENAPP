// functions/index.js
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// Set global options
setGlobalOptions({maxInstances: 10});

// ========================================
// 1. FOLLOW NOTIFICATIONS
// ========================================

exports.sendFollowNotification = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const notification = event.data.data();
  const notificationId = event.params.notificationId;
  
  if (notification.type !== 'follow') {
    console.log('Skipping non-follow notification');
    return null;
  }
  
  console.log('📬 Processing follow notification:', notification);
  
  try {
    const userDoc = await db.collection('users').doc(notification.userId).get();
    
    if (!userDoc.exists) {
      console.log('❌ User not found:', notification.userId);
      return null;
    }
    
    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;
    
    if (!fcmToken) {
      console.log('⚠️ No FCM token for user:', notification.userId);
      return null;
    }
    
    const message = {
      notification: {
        title: 'New Follower',
        body: notification.message || `${notification.fromUserName} started following you`,
      },
      data: {
        type: 'follow',
        fromUserId: notification.fromUserId || '',
        notificationId: notificationId,
      },
      token: fcmToken,
    };
    
    await messaging.send(message);
    console.log('✅ Follow notification sent to:', notification.userId);
    
    return null;
  } catch (error) {
    console.error('❌ Error sending follow notification:', error);
    return null;
  }
});

// ========================================
// 2. MESSAGE NOTIFICATIONS
// ========================================

exports.sendMessageNotification = onDocumentCreated(
  'conversations/{conversationId}/messages/{messageId}',
  async (event) => {
    const message = event.data.data();
    const conversationId = event.params.conversationId;
    const messageId = event.params.messageId;
    
    console.log('💬 Processing new message:', message);
    
    try {
      const conversationDoc = await db.collection('conversations').doc(conversationId).get();
      
      if (!conversationDoc.exists) {
        console.log('❌ Conversation not found:', conversationId);
        return null;
      }
      
      const conversation = conversationDoc.data();
      const participantIds = conversation.participantIds || [];
      const recipientId = participantIds.find(id => id !== message.senderId);
      
      if (!recipientId) {
        console.log('⚠️ No recipient found');
        return null;
      }
      
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      
      if (!recipientDoc.exists) {
        console.log('❌ Recipient not found:', recipientId);
        return null;
      }
      
      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;
      const notificationsEnabled = recipientData.messageNotificationsEnabled !== false;
      
      if (!notificationsEnabled) {
        console.log('⚠️ User has disabled message notifications:', recipientId);
        return null;
      }
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for recipient:', recipientId);
        return null;
      }
      
      const senderDoc = await db.collection('users').doc(message.senderId).get();
      const senderName = senderDoc.exists 
        ? (senderDoc.data().displayName || 'Someone')
        : 'Someone';
      
      const pushMessage = {
        notification: {
          title: senderName,
          body: message.text || 'Sent you a message',
        },
        data: {
          type: 'message',
          conversationId: conversationId,
          senderId: message.senderId,
          messageId: messageId,
        },
        token: fcmToken,
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: 'default',
            },
          },
        },
      };
      
      await messaging.send(pushMessage);
      console.log('✅ Message notification sent to:', recipientId);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending message notification:', error);
      return null;
    }
  }
);

// ========================================
// 3. SAVED SEARCH MATCH NOTIFICATIONS
// ========================================

exports.sendSavedSearchNotification = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const notification = event.data.data();
  const notificationId = event.params.notificationId;
  
  if (notification.type !== 'savedSearchMatch') {
    return null;
  }
  
  console.log('🔍 Processing saved search notification:', notification);
  
  try {
    const userDoc = await db.collection('users').doc(notification.userId).get();
    
    if (!userDoc.exists) {
      console.log('❌ User not found:', notification.userId);
      return null;
    }
    
    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;
    
    if (!fcmToken) {
      console.log('⚠️ No FCM token for user:', notification.userId);
      return null;
    }
    
    const message = {
      notification: {
        title: 'Saved Search Match',
        body: notification.message,
      },
      data: {
        type: 'savedSearchMatch',
        category: notification.category || '',
        contentId: notification.contentId || '',
        query: notification.query || '',
        notificationId: notificationId,
      },
      token: fcmToken,
    };
    
    await messaging.send(message);
    console.log('✅ Saved search notification sent to:', notification.userId);
    
    return null;
  } catch (error) {
    console.error('❌ Error sending saved search notification:', error);
    return null;
  }
});

console.log('✅ Cloud Functions v2 loaded successfully');
