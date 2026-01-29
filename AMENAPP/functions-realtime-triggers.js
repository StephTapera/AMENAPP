/**
 * Cloud Functions for AMEN App - REALTIME DATABASE TRIGGERS
 * 
 * These functions watch Firebase Realtime Database for post interactions
 * and sync counts to Firestore for querying purposes.
 * 
 * This is MUCH faster than Firestore-only approach!
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// If not already initialized (keep existing initialization)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const rtdb = admin.database();
const messaging = admin.messaging();

// =============================================================================
// REALTIME DATABASE TRIGGERS FOR POST INTERACTIONS
// =============================================================================

/**
 * Update Firestore when lightbulb count changes in Realtime Database
 * This keeps Firestore in sync for complex queries while maintaining RT speed
 */
exports.syncLightbulbCount = functions.database
  .ref('/postInteractions/{postId}/lightbulbCount')
  .onWrite(async (change, context) => {
    const postId = context.params.postId;
    const newCount = change.after.val() || 0;
    
    console.log(`💡 Syncing lightbulb count for post ${postId}: ${newCount}`);
    
    try {
      await db.collection('posts').doc(postId).update({
        lightbulbCount: newCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`✅ Lightbulb count synced to Firestore`);
    } catch (error) {
      console.error(`❌ Error syncing lightbulb count:`, error);
    }
    
    return null;
  });

/**
 * Update Firestore when amen count changes in Realtime Database
 * Also sends push notification when new amen is added
 */
exports.syncAmenCount = functions.database
  .ref('/postInteractions/{postId}/amenCount')
  .onWrite(async (change, context) => {
    const postId = context.params.postId;
    const newCount = change.after.val() || 0;
    const oldCount = change.before.val() || 0;
    
    console.log(`🙏 Syncing amen count for post ${postId}: ${oldCount} -> ${newCount}`);
    
    try {
      // Update Firestore
      await db.collection('posts').doc(postId).update({
        amenCount: newCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`✅ Amen count synced to Firestore`);
      
      // If count increased, send notification
      if (newCount > oldCount) {
        // Get the most recent amen to find who did it
        const amensSnapshot = await rtdb.ref(`/postInteractions/${postId}/amens`)
          .orderByChild('timestamp')
          .limitToLast(1)
          .once('value');
        
        if (amensSnapshot.exists()) {
          const amenData = Object.values(amensSnapshot.val())[0];
          const amenUserId = amenData.userId;
          
          // Get post info for notification
          const postDoc = await db.collection('posts').doc(postId).get();
          if (postDoc.exists) {
            const post = postDoc.data();
            await sendAmenNotification(amenUserId, post.authorId, postId);
          }
        }
      }
      
    } catch (error) {
      console.error(`❌ Error syncing amen count:`, error);
    }
    
    return null;
  });

/**
 * Update Firestore when comment count changes in Realtime Database
 * Also sends push notification when new comment is added
 */
exports.syncCommentCount = functions.database
  .ref('/postInteractions/{postId}/commentCount')
  .onWrite(async (change, context) => {
    const postId = context.params.postId;
    const newCount = change.after.val() || 0;
    const oldCount = change.before.val() || 0;
    
    console.log(`💬 Syncing comment count for post ${postId}: ${oldCount} -> ${newCount}`);
    
    try {
      // Update Firestore
      await db.collection('posts').doc(postId).update({
        commentCount: newCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`✅ Comment count synced to Firestore`);
      
      // If count increased, send notification
      if (newCount > oldCount) {
        // Get the most recent comment
        const commentsSnapshot = await rtdb.ref(`/postInteractions/${postId}/comments`)
          .orderByChild('timestamp')
          .limitToLast(1)
          .once('value');
        
        if (commentsSnapshot.exists()) {
          const commentData = Object.values(commentsSnapshot.val())[0];
          
          // Get post info for notification
          const postDoc = await db.collection('posts').doc(postId).get();
          if (postDoc.exists) {
            const post = postDoc.data();
            await sendCommentNotification(
              commentData.authorId,
              post.authorId,
              postId,
              commentData.content
            );
          }
        }
      }
      
    } catch (error) {
      console.error(`❌ Error syncing comment count:`, error);
    }
    
    return null;
  });

/**
 * Update Firestore when repost count changes in Realtime Database
 */
exports.syncRepostCount = functions.database
  .ref('/postInteractions/{postId}/repostCount')
  .onWrite(async (change, context) => {
    const postId = context.params.postId;
    const newCount = change.after.val() || 0;
    
    console.log(`🔄 Syncing repost count for post ${postId}: ${newCount}`);
    
    try {
      await db.collection('posts').doc(postId).update({
        repostCount: newCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`✅ Repost count synced to Firestore`);
    } catch (error) {
      console.error(`❌ Error syncing repost count:`, error);
    }
    
    return null;
  });

// =============================================================================
// NOTIFICATION HELPERS (Same as before)
// =============================================================================

async function sendAmenNotification(amenUserId, postAuthorId, postId) {
  try {
    if (amenUserId === postAuthorId) return;

    const amenUserDoc = await db.collection('users').doc(amenUserId).get();
    if (!amenUserDoc.exists) return;
    const amenUser = amenUserDoc.data();

    const authorDoc = await db.collection('users').doc(postAuthorId).get();
    if (!authorDoc.exists) return;
    const author = authorDoc.data();

    const notifSettings = author.notificationSettings || {};
    if (notifSettings.amens === false) return;

    const fcmToken = author.fcmToken;
    if (!fcmToken) return;

    const message = {
      token: fcmToken,
      notification: {
        title: '🙏 New Amen',
        body: `${amenUser.displayName} said Amen to your post`,
      },
      data: {
        type: 'amen',
        postId: postId,
        userId: amenUserId,
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

    await messaging.send(message);
    console.log(`✅ Amen notification sent to ${postAuthorId}`);

    await db.collection('notifications').add({
      userId: postAuthorId,
      type: 'amen',
      actorId: amenUserId,
      actorName: amenUser.displayName,
      actorUsername: amenUser.username,
      postId: postId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending amen notification:', error);
  }
}

async function sendCommentNotification(commenterId, postAuthorId, postId, commentText) {
  try {
    if (commenterId === postAuthorId) return;

    const commenterDoc = await db.collection('users').doc(commenterId).get();
    if (!commenterDoc.exists) return;
    const commenter = commenterDoc.data();

    const authorDoc = await db.collection('users').doc(postAuthorId).get();
    if (!authorDoc.exists) return;
    const author = authorDoc.data();

    const notifSettings = author.notificationSettings || {};
    if (notifSettings.comments === false) return;

    const fcmToken = author.fcmToken;
    if (!fcmToken) return;

    const truncatedComment = commentText.length > 50 
      ? commentText.substring(0, 50) + '...' 
      : commentText;

    const message = {
      token: fcmToken,
      notification: {
        title: '💬 New Comment',
        body: `${commenter.displayName}: ${truncatedComment}`,
      },
      data: {
        type: 'comment',
        postId: postId,
        commenterId: commenterId,
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

    await messaging.send(message);
    console.log(`✅ Comment notification sent to ${postAuthorId}`);

    await db.collection('notifications').add({
      userId: postAuthorId,
      type: 'comment',
      actorId: commenterId,
      actorName: commenter.displayName,
      actorUsername: commenter.username,
      postId: postId,
      commentText: truncatedComment,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending comment notification:', error);
  }
}
