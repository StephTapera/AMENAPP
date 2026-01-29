#!/bin/bash

# This script will add the correct v2 message notification function

cd ~/Desktop/AMEN/AMENAPP/functions

# Create a backup
cp index.js index.js.backup

# Create a temporary file with the correct function
cat > temp_function.txt << 'EOF'

// =============================================================================
// MESSAGE NOTIFICATIONS (v2 syntax)
// =============================================================================

exports.onMessageCreated = onDocumentCreated('conversations/{conversationId}/messages/{messageId}', async (event) => {
  try {
    const message = event.data.data();
    const conversationId = event.params.conversationId;
    const senderId = message.senderId;
    
    console.log(`💬 New message in conversation ${conversationId} from ${senderId}`);
    
    // Get conversation to find recipients
    const db = getFirestore();
    const messaging = getMessaging();
    
    const conversationDoc = await db.collection('conversations').doc(conversationId).get();
    
    if (!conversationDoc.exists) {
      console.log('⚠️ Conversation not found');
      return null;
    }
    
    const conversation = conversationDoc.data();
    const participants = conversation.participantIds || [];
    
    // Send notification to all participants except sender
    for (const recipientId of participants) {
      if (recipientId === senderId) {
        console.log(`⏭️ Skipping sender: ${senderId}`);
        continue;
      }
      
      // Get recipient info
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      
      if (!recipientDoc.exists) {
        console.log(`⚠️ Recipient ${recipientId} not found`);
        continue;
      }
      
      const recipient = recipientDoc.data();
      
      // Check notification preferences
      const notifSettings = recipient.notificationSettings || {};
      if (notifSettings.messages === false) {
        console.log(`🔕 User ${recipientId} has disabled message notifications`);
        continue;
      }
      
      const fcmToken = recipient.fcmToken;
      
      if (!fcmToken) {
        console.log(`⚠️ No FCM token for recipient ${recipientId}`);
        continue;
      }
      
      // Truncate message for notification
      const messageText = message.text || '';
      const truncatedText = messageText.length > 100 
        ? messageText.substring(0, 100) + '...' 
        : messageText;
      
      // Send push notification
      const notificationMessage = {
        token: fcmToken,
        notification: {
          title: `💬 ${message.senderName || 'New Message'}`,
          body: truncatedText || '📷 Photo'
        },
        data: {
          type: 'message',
          conversationId: conversationId,
          senderId: senderId,
          timestamp: Date.now().toString()
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1
            }
          }
        }
      };
      
      await messaging.send(notificationMessage);
      console.log(`✅ Message notification sent to ${recipientId}`);
      
      // Create in-app notification
      await db.collection('notifications').add({
        userId: recipientId,
        type: 'message',
        actorId: senderId,
        actorName: message.senderName,
        conversationId: conversationId,
        messagePreview: truncatedText,
        createdAt: FieldValue.serverTimestamp(),
        read: false
      });
      
      console.log(`✅ In-app notification created for ${recipientId}`);
    }
    
    return null;
    
  } catch (error) {
    console.error('❌ Error sending message notification:', error);
    return null;
  }
});
EOF

echo "Backup created: index.js.backup"
echo ""
echo "Now remove the incorrect function and we'll add the correct one..."
