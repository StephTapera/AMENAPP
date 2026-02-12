/**
 * Push Notification Cloud Functions for AMEN App
 * Handles APNs/FCM push notification delivery
 * 
 * Triggers:
 * - New notifications created in Firestore
 * - Follow requests accepted
 * - Message requests accepted
 * - Duplicate prevention for follows
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Send push notification when a new notification is created
 * Triggers on: /notifications/{notificationId}
 */
exports.sendPushNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    const notificationId = context.params.notificationId;
    
    console.log('📬 New notification created:', notificationId);
    console.log('   Type:', notification.type);
    console.log('   User:', notification.userId);
    
    try {
      // Get recipient user's FCM token
      const userDoc = await db.collection('users').doc(notification.userId).get();
      
      if (!userDoc.exists) {
        console.log('⚠️ User not found:', notification.userId);
        return null;
      }
      
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for user:', notification.userId);
        return null;
      }
      
      // Build notification payload
      const payload = buildNotificationPayload(notification);
      
      if (!payload) {
        console.log('⚠️ Could not build payload for notification type:', notification.type);
        return null;
      }
      
      // Send push notification
      const message = {
        token: fcmToken,
        notification: payload.notification,
        data: payload.data,
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: userData.unreadNotificationCount || 1,
              'content-available': 1
            }
          }
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'amen_notifications'
          }
        }
      };
      
      await messaging.send(message);
      
      console.log('✅ Push notification sent successfully');
      console.log('   To user:', notification.userId);
      console.log('   Type:', notification.type);
      
      return null;
    } catch (error) {
      console.error('❌ Failed to send push notification:', error);
      console.error('   Notification ID:', notificationId);
      console.error('   Error:', error.message);
      return null;
    }
  });

/**
 * Handle follow events with duplicate prevention
 * Triggers on: /follows/{followId}
 * 
 * IMPORTANT: Uses top-level /follows collection, NOT subcollection
 * Document structure: { followerId: string, followingId: string, createdAt: timestamp }
 */
exports.onUserFollow = functions.firestore
  .document('follows/{followId}')
  .onCreate(async (snap, context) => {
    const followData = snap.data();
    const followerId = followData.followerId;
    const followingId = followData.followingId;
    
    if (!followerId || !followingId) {
      console.log('⚠️ Missing followerId or followingId in follow document');
      return null;
    }
    
    console.log('👥 New follow detected');
    console.log('   Follower:', followerId);
    console.log('   Following:', followingId);
    
    try {
      // Check for existing follow notification (duplicate prevention)
      const existingNotifications = await db.collection('notifications')
        .where('userId', '==', followingId)
        .where('type', '==', 'follow')
        .where('actorId', '==', followerId)
        .limit(1)
        .get();
      
      if (!existingNotifications.empty) {
        console.log('⚠️ Follow notification already exists, updating timestamp');
        
        // Update existing notification's timestamp instead of creating duplicate
        const existingNotification = existingNotifications.docs[0];
        await existingNotification.ref.update({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false // Mark as unread again
        });
        
        return null;
      }
      
      // Get follower's info
      const followerDoc = await db.collection('users').doc(followerId).get();
      
      if (!followerDoc.exists) {
        console.log('⚠️ Follower user not found:', followerId);
        return null;
      }
      
      const followerData = followerDoc.data();
      
      // Create notification
      const notificationRef = await db.collection('notifications').add({
        userId: followingId,
        type: 'follow',
        actorId: followerId,
        actorName: followerData.displayName || followerData.username || 'Someone',
        actorUsername: followerData.username || 'unknown',
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log('✅ Follow notification created:', notificationRef.id);
      
      // Increment unread count
      await db.collection('users').doc(followingId).update({
        unreadNotificationCount: admin.firestore.FieldValue.increment(1)
      });
      
      return null;
    } catch (error) {
      console.error('❌ Failed to create follow notification:', error);
      return null;
    }
  });

/**
 * Delete notification when someone unfollows
 * Triggers on: /follows/{followId} (delete)
 */
exports.onUserUnfollow = functions.firestore
  .document('follows/{followId}')
  .onDelete(async (snap, context) => {
    const followData = snap.data();
    const followerId = followData.followerId;
    const followingId = followData.followingId;
    
    if (!followerId || !followingId) {
      console.log('⚠️ Missing followerId or followingId in deleted follow document');
      return null;
    }
    
    console.log('👋 Unfollow detected');
    console.log('   Follower:', followerId);
    console.log('   Following:', followingId);
    
    try {
      // Find and delete the follow notification
      const notifications = await db.collection('notifications')
        .where('userId', '==', followingId)
        .where('type', '==', 'follow')
        .where('actorId', '==', followerId)
        .get();
      
      if (notifications.empty) {
        console.log('⚠️ No follow notification found to delete');
        return null;
      }
      
      // Delete all matching notifications (should be only one due to duplicate prevention)
      const batch = db.batch();
      let deletedCount = 0;
      let wasUnread = false;
      
      notifications.forEach(doc => {
        batch.delete(doc.ref);
        deletedCount++;
        if (!doc.data().read) {
          wasUnread = true;
        }
      });
      
      await batch.commit();
      
      console.log('✅ Follow notification(s) deleted:', deletedCount);
      
      // Decrement unread count if notification was unread
      if (wasUnread) {
        await db.collection('users').doc(followingId).update({
          unreadNotificationCount: admin.firestore.FieldValue.increment(-deletedCount)
        });
      }
      
      return null;
    } catch (error) {
      console.error('❌ Failed to delete follow notification:', error);
      return null;
    }
  });

/**
 * Create notification when follow request is accepted
 * Triggers on: /followRequests/{requestId}
 */
exports.onFollowRequestAccepted = functions.firestore
  .document('followRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    
    // Only trigger when status changes to 'accepted'
    if (before.status !== 'accepted' && after.status === 'accepted') {
      console.log('✅ Follow request accepted');
      console.log('   Request ID:', context.params.requestId);
      console.log('   From:', after.fromUserId);
      console.log('   To:', after.toUserId);
      
      try {
        // Get the user who accepted the request (toUserId)
        const accepterDoc = await db.collection('users').doc(after.toUserId).get();
        
        if (!accepterDoc.exists) {
          console.log('⚠️ Accepter user not found');
          return null;
        }
        
        const accepterData = accepterDoc.data();
        
        // Create notification for the requester (fromUserId)
        await db.collection('notifications').add({
          userId: after.fromUserId,
          type: 'follow_request_accepted',
          actorId: after.toUserId,
          actorName: accepterData.displayName || accepterData.username || 'Someone',
          actorUsername: accepterData.username || 'unknown',
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        console.log('✅ Follow request accepted notification created');
        
        // Increment unread count
        await db.collection('users').doc(after.fromUserId).update({
          unreadNotificationCount: admin.firestore.FieldValue.increment(1)
        });
        
        return null;
      } catch (error) {
        console.error('❌ Failed to create follow request accepted notification:', error);
        return null;
      }
    }
    
    return null;
  });

/**
 * Create notification when message request is accepted
 * Triggers on: /messageRequests/{requestId}
 */
exports.onMessageRequestAccepted = functions.firestore
  .document('messageRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    
    // Only trigger when status changes to 'accepted'
    if (before.status !== 'accepted' && after.status === 'accepted') {
      console.log('✅ Message request accepted');
      console.log('   Request ID:', context.params.requestId);
      console.log('   From:', after.fromUserId);
      console.log('   To:', after.toUserId);
      
      try {
        // Get the user who accepted the request
        const accepterDoc = await db.collection('users').doc(after.toUserId).get();
        
        if (!accepterDoc.exists) {
          console.log('⚠️ Accepter user not found');
          return null;
        }
        
        const accepterData = accepterDoc.data();
        
        // Create notification for the requester
        await db.collection('notifications').add({
          userId: after.fromUserId,
          type: 'message_request_accepted',
          actorId: after.toUserId,
          actorName: accepterData.displayName || accepterData.username || 'Someone',
          actorUsername: accepterData.username || 'unknown',
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        console.log('✅ Message request accepted notification created');
        
        // Increment unread count
        await db.collection('users').doc(after.fromUserId).update({
          unreadNotificationCount: admin.firestore.FieldValue.increment(1)
        });
        
        return null;
      } catch (error) {
        console.error('❌ Failed to create message request accepted notification:', error);
        return null;
      }
    }
    
    return null;
  });

/**
 * Build notification payload based on type
 */
function buildNotificationPayload(notification) {
  const actorName = notification.actorName || 'Someone';
  
  switch (notification.type) {
    case 'follow':
      return {
        notification: {
          title: 'New Follower',
          body: `${actorName} started following you`
        },
        data: {
          type: 'follow',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'follow_request_accepted':
      return {
        notification: {
          title: 'Follow Request Accepted',
          body: `${actorName} accepted your follow request`
        },
        data: {
          type: 'follow_request_accepted',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'message_request_accepted':
      return {
        notification: {
          title: 'Message Request Accepted',
          body: `${actorName} accepted your message request`
        },
        data: {
          type: 'message_request_accepted',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'amen':
      return {
        notification: {
          title: 'New Reaction',
          body: `${actorName} said Amen to your post`
        },
        data: {
          type: 'amen',
          postId: notification.postId || '',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'comment':
      return {
        notification: {
          title: 'New Comment',
          body: `${actorName} commented on your post`
        },
        data: {
          type: 'comment',
          postId: notification.postId || '',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'reply':
      return {
        notification: {
          title: 'New Reply',
          body: `${actorName} replied to your comment`
        },
        data: {
          type: 'reply',
          postId: notification.postId || '',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    case 'mention':
      return {
        notification: {
          title: 'You were mentioned',
          body: `${actorName} mentioned you in a post`
        },
        data: {
          type: 'mention',
          postId: notification.postId || '',
          actorId: notification.actorId || '',
          notificationId: notification.id || ''
        }
      };
      
    default:
      console.log('⚠️ Unknown notification type:', notification.type);
      return null;
  }
}

// Export all functions
module.exports = {
  sendPushNotification: exports.sendPushNotification,
  onUserFollow: exports.onUserFollow,
  onUserUnfollow: exports.onUserUnfollow,
  onFollowRequestAccepted: exports.onFollowRequestAccepted,
  onMessageRequestAccepted: exports.onMessageRequestAccepted
};
