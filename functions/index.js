/**
 * Cloud Functions for AMEN App - FIXED VERSION WITH REALTIME DB TRIGGERS
 * 
 * This version uses Realtime Database triggers for post interactions
 * to make them instant (< 100ms instead of 2-5 seconds)
 */

const {onDocumentWritten, onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onValueWritten} = require("firebase-functions/v2/database");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getDatabase} = require("firebase-admin/database");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const rtdb = getDatabase();

// =============================================================================
// 1. AUTO-UPDATE USER SEARCH FIELDS
// =============================================================================

exports.updateUserSearchFields = onDocumentWritten("users/{userId}", async (event) => {
  if (!event.data.after.exists) {
    return null;
  }

  const newData = event.data.after.data();
  const oldData = event.data.before.exists ? event.data.before.data() : {};

  const usernameChanged = newData.username !== oldData.username;
  const displayNameChanged = newData.displayName !== oldData.displayName;

  if (!usernameChanged && !displayNameChanged) {
    return null;
  }

  const updates = {};

  if (usernameChanged && newData.username) {
    updates.usernameLowercase = newData.username.toLowerCase();
  }

  if (displayNameChanged && newData.displayName) {
    updates.displayNameLowercase = newData.displayName.toLowerCase();
  }

  if (Object.keys(updates).length === 0) {
    return null;
  }

  updates.searchUpdatedAt = FieldValue.serverTimestamp();

  console.log(`📝 Updating search fields for user ${event.params.userId}:`, updates);

  return event.data.after.ref.update(updates);
});

// =============================================================================
// 2. UPDATE FOLLOWER/FOLLOWING COUNTS
// =============================================================================

exports.updateFollowerCount = onDocumentWritten("follows/{followId}", async (event) => {
  const followData = event.data.after.exists ? event.data.after.data() : event.data.before.data();
  
  if (!followData) return null;

  const followingUserId = followData.followingId;
  const followerUserId = followData.followerId;

  const isCreated = event.data.after.exists && !event.data.before.exists;
  const isDeleted = !event.data.after.exists && event.data.before.exists;

  if (!isCreated && !isDeleted) {
    return null;
  }

  const increment = isCreated ? 1 : -1;

  const batch = db.batch();

  const followingUserRef = db.collection('users').doc(followingUserId);
  batch.update(followingUserRef, {
    followersCount: FieldValue.increment(increment)
  });

  const followerUserRef = db.collection('users').doc(followerUserId);
  batch.update(followerUserRef, {
    followingCount: FieldValue.increment(increment)
  });

  console.log(`👥 ${isCreated ? 'Added' : 'Removed'} follow: ${followerUserId} -> ${followingUserId}`);

  await batch.commit();

  if (isCreated) {
    await sendFollowNotification(followerUserId, followingUserId);
  }

  return null;
});

// =============================================================================
// 3. REALTIME DATABASE TRIGGERS FOR POST INTERACTIONS (NEW - FAST!)
// =============================================================================
// These watch Realtime Database where your iOS app actually writes!

/**
 * Sync lightbulb count from Realtime DB to Firestore
 */
exports.syncLightbulbCount = onValueWritten({
  ref: "/postInteractions/{postId}/lightbulbCount",
  region: "us-central1"
}, async (event) => {
  const postId = event.params.postId;
  const newCount = event.data.after.val() || 0;
  
  console.log(`💡 Syncing lightbulb count for post ${postId}: ${newCount}`);
  
  try {
    await db.collection('posts').doc(postId).update({
      lightbulbCount: newCount,
      updatedAt: FieldValue.serverTimestamp()
    });
    
    console.log(`✅ Lightbulb count synced to Firestore`);
  } catch (error) {
    console.error(`❌ Error syncing lightbulb count:`, error);
  }
  
  return null;
});

/**
 * Sync amen count from Realtime DB to Firestore
 * Also sends push notification when new amen is added
 */
exports.syncAmenCount = onValueWritten({
  ref: "/postInteractions/{postId}/amenCount",
  region: "us-central1"
}, async (event) => {
  const postId = event.params.postId;
  const newCount = event.data.after.val() || 0;
  const oldCount = event.data.before.val() || 0;
  
  console.log(`🙏 Syncing amen count for post ${postId}: ${oldCount} -> ${newCount}`);
  
  try {
    // Update Firestore
    await db.collection('posts').doc(postId).update({
      amenCount: newCount,
      updatedAt: FieldValue.serverTimestamp()
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
 * Sync comment count from Realtime DB to Firestore
 * Also sends push notification when new comment is added
 */
exports.syncCommentCount = onValueWritten({
  ref: "/postInteractions/{postId}/commentCount",
  region: "us-central1"
}, async (event) => {
  const postId = event.params.postId;
  const newCount = event.data.after.val() || 0;
  const oldCount = event.data.before.val() || 0;
  
  console.log(`💬 Syncing comment count for post ${postId}: ${oldCount} -> ${newCount}`);
  
  try {
    // Update Firestore
    await db.collection('posts').doc(postId).update({
      commentCount: newCount,
      updatedAt: FieldValue.serverTimestamp()
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
 * Sync repost count from Realtime DB to Firestore
 */
exports.syncRepostCount = onValueWritten({
  ref: "/postInteractions/{postId}/repostCount",
  region: "us-central1"
}, async (event) => {
  const postId = event.params.postId;
  const newCount = event.data.after.val() || 0;
  
  console.log(`🔄 Syncing repost count for post ${postId}: ${newCount}`);
  
  try {
    await db.collection('posts').doc(postId).update({
      repostCount: newCount,
      updatedAt: FieldValue.serverTimestamp()
    });
    
    console.log(`✅ Repost count synced to Firestore`);
  } catch (error) {
    console.error(`❌ Error syncing repost count:`, error);
  }
  
  return null;
});

// =============================================================================
// 4. PUSH NOTIFICATIONS
// =============================================================================

async function sendFollowNotification(followerUserId, followingUserId) {
  try {
    if (followerUserId === followingUserId) return;

    const followerDoc = await db.collection('users').doc(followerUserId).get();
    if (!followerDoc.exists) return;
    const follower = followerDoc.data();

    const followingDoc = await db.collection('users').doc(followingUserId).get();
    if (!followingDoc.exists) return;
    const following = followingDoc.data();

    const notifSettings = following.notificationSettings || {};
    if (notifSettings.follows === false) {
      console.log('🔕 User has disabled follow notifications');
      return;
    }

    const fcmToken = following.fcmToken;
    if (!fcmToken) {
      console.log('⚠️ No FCM token found for user');
      return;
    }

    const message = {
      token: fcmToken,
      notification: {
        title: 'New Follower',
        body: `${follower.displayName} started following you`,
      },
      data: {
        type: 'follow',
        followerId: followerUserId,
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
    console.log(`✅ Follow notification sent to ${followingUserId}`);

    await db.collection('notifications').add({
      userId: followingUserId,
      type: 'follow',
      actorId: followerUserId,
      actorName: follower.displayName,
      actorUsername: follower.username,
      createdAt: FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending follow notification:', error);
  }
}

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
      createdAt: FieldValue.serverTimestamp(),
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
      createdAt: FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending comment notification:', error);
  }
}

// =============================================================================
// 5. CONTENT MODERATION
// =============================================================================

exports.moderatePost = onDocumentCreated("posts/{postId}", async (event) => {
  const post = event.data.data();
  const content = (post.content || '').toLowerCase();

  const inappropriateWords = ['spam', 'scam', 'hack', 'cheat'];

  const containsInappropriate = inappropriateWords.some(word => 
    content.includes(word)
  );

  if (containsInappropriate) {
    console.log(`⚠️ Post ${event.params.postId} flagged for moderation`);
    
    await event.data.ref.update({
      flaggedForReview: true,
      flaggedAt: FieldValue.serverTimestamp(),
      flaggedReason: 'automatic_keyword_detection'
    });

    await db.collection('moderationQueue').add({
      postId: event.params.postId,
      authorId: post.authorId,
      content: post.content,
      reason: 'automatic_keyword_detection',
      createdAt: FieldValue.serverTimestamp(),
      reviewed: false
    });
  }

  return null;
});

exports.detectSpam = onDocumentCreated("posts/{postId}", async (event) => {
  const post = event.data.data();
  const userId = post.authorId;

  const oneMinuteAgo = Timestamp.fromDate(new Date(Date.now() - 60000));

  const recentPosts = await db.collection('posts')
    .where('authorId', '==', userId)
    .where('createdAt', '>', oneMinuteAgo)
    .get();

  if (recentPosts.size > 5) {
    console.log(`🚫 User ${userId} detected as potential spammer`);

    await event.data.ref.update({
      flaggedForReview: true,
      flaggedReason: 'spam_detection'
    });

    await db.collection('users').doc(userId).update({
      postingRestricted: true,
      restrictionExpires: Timestamp.fromDate(new Date(Date.now() + 3600000)),
      restrictionReason: 'spam_detection'
    });
  }

  return null;
});

// =============================================================================
// 6. SCHEDULED FUNCTIONS
// =============================================================================

exports.sendPrayerReminders = onSchedule("0 9 * * *", async (event) => {
  console.log('📅 Running daily prayer reminders...');

  const prayerRequests = await db.collection('prayers')
    .where('status', '==', 'active')
    .where('type', '==', 'request')
    .get();

  let remindersSent = 0;

  for (const prayerDoc of prayerRequests.docs) {
    const prayer = prayerDoc.data();
    const commitments = await prayerDoc.ref.collection('commitments').get();

    for (const commitment of commitments.docs) {
      const commitmentData = commitment.data();
      
      if (!commitmentData.wantsReminders) continue;

      await sendPrayerReminderNotification(
        commitmentData.userId,
        prayerDoc.id,
        prayer.title || 'Prayer Request'
      );

      remindersSent++;
    }
  }

  console.log(`✅ Sent ${remindersSent} prayer reminders`);
  return null;
});

async function sendPrayerReminderNotification(userId, prayerId, prayerTitle) {
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return;
    
    const user = userDoc.data();
    const fcmToken = user.fcmToken;
    
    if (!fcmToken) return;

    const notifSettings = user.notificationSettings || {};
    if (notifSettings.prayerRequests === false) return;

    const message = {
      token: fcmToken,
      notification: {
        title: '🙏 Prayer Reminder',
        body: `Remember to pray for: ${prayerTitle}`,
      },
      data: {
        type: 'prayer_reminder',
        prayerId: prayerId,
        timestamp: Date.now().toString()
      },
      apns: {
        payload: {
          aps: {
            sound: 'default'
          }
        }
      }
    };

    await messaging.send(message);
    console.log(`✅ Prayer reminder sent to ${userId}`);

  } catch (error) {
    console.error('❌ Error sending prayer reminder:', error);
  }
}

exports.generateWeeklyStats = onSchedule("0 9 * * 1", async (event) => {
  console.log('📊 Generating weekly stats...');

  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const postsSnapshot = await db.collection('posts')
    .where('createdAt', '>', Timestamp.fromDate(weekAgo))
    .get();

  const prayersSnapshot = await db.collection('prayers')
    .where('createdAt', '>', Timestamp.fromDate(weekAgo))
    .get();

  const answeredPrayers = prayersSnapshot.docs.filter(doc => 
    doc.data().status === 'answered'
  ).length;

  const stats = {
    week: `${weekAgo.toISOString().split('T')[0]} to ${now.toISOString().split('T')[0]}`,
    totalPosts: postsSnapshot.size,
    totalPrayers: prayersSnapshot.size,
    answeredPrayers: answeredPrayers,
    generatedAt: FieldValue.serverTimestamp()
  };

  await db.collection('weeklyStats').add(stats);

  console.log('✅ Weekly stats generated:', stats);
  return null;
});

// =============================================================================
// 7. CALLABLE FUNCTIONS
// =============================================================================

exports.generateFeed = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = request.auth.uid;
  const limit = request.data.limit || 20;

  try {
    const followsSnapshot = await db.collection('follows')
      .where('followerId', '==', userId)
      .get();

    const followingIds = followsSnapshot.docs.map(doc => doc.data().followingId);

    if (followingIds.length === 0) {
      const postsSnapshot = await db.collection('posts')
        .orderBy('amenCount', 'desc')
        .limit(limit)
        .get();

      return {
        posts: postsSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }))
      };
    }

    const allPosts = [];
    
    for (let i = 0; i < followingIds.length; i += 10) {
      const batch = followingIds.slice(i, i + 10);
      const postsSnapshot = await db.collection('posts')
        .where('authorId', 'in', batch)
        .orderBy('createdAt', 'desc')
        .limit(limit)
        .get();

      allPosts.push(...postsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })));
    }

    allPosts.sort((a, b) => b.createdAt - a.createdAt);

    return {
      posts: allPosts.slice(0, limit)
    };

  } catch (error) {
    console.error('Error generating feed:', error);
    throw new HttpsError('internal', 'Failed to generate feed');
  }
});

exports.reportContent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { contentType, contentId, reason, details } = request.data;

  if (!contentType || !contentId || !reason) {
    throw new HttpsError('invalid-argument', 'Missing required fields');
  }

  try {
    await db.collection('reports').add({
      contentType,
      contentId,
      reason,
      details: details || '',
      reportedBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      status: 'pending'
    });

    console.log(`🚩 Content reported: ${contentType}/${contentId} by ${request.auth.uid}`);

    return { success: true };

  } catch (error) {
    console.error('Error creating report:', error);
    throw new HttpsError('internal', 'Failed to create report');
  }
});

// =============================================================================
// 8. MESSAGE NOTIFICATIONS (REALTIME DATABASE - FAST!)
// =============================================================================

/**
 * Sync new messages from Realtime DB to Firestore
 * Path: /conversations/{conversationId}/messages/{messageId}
 */
exports.syncNewMessage = onValueWritten({
  ref: "/conversations/{conversationId}/messages/{messageId}",
  region: "us-central1"
}, async (event) => {
  // Only trigger when message is created (not updated or deleted)
  if (!event.data.after.exists() || event.data.before.exists()) {
    return null;
  }
  
  const conversationId = event.params.conversationId;
  const messageId = event.params.messageId;
  const messageData = event.data.after.val();
  
  console.log(`💬 New message in conversation ${conversationId}`);
  
  try {
    // Sync message to Firestore
    await db.collection('conversations')
      .doc(conversationId)
      .collection('messages')
      .doc(messageId)
      .set({
        ...messageData,
        createdAt: FieldValue.serverTimestamp()
      });
    
    // Update conversation's last message info
    await db.collection('conversations').doc(conversationId).update({
      lastMessage: messageData.text || '📷 Photo',
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessageSenderId: messageData.senderId
    });
    
    console.log(`✅ Message synced to Firestore`);
    
    // Send notifications to other participants
    const conversationDoc = await db.collection('conversations').doc(conversationId).get();
    if (!conversationDoc.exists) return null;
    
    const conversation = conversationDoc.data();
    const participants = conversation.participantIds || [];
    
    for (const recipientId of participants) {
      if (recipientId === messageData.senderId) continue;
      
      // Increment unread message count
      await rtdb.ref(`unreadCounts/${recipientId}/messages`).transaction(current => {
        return (current || 0) + 1;
      });
      
      // Send push notification
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      if (!recipientDoc.exists) continue;
      
      const recipient = recipientDoc.data();
      const notifSettings = recipient.notificationSettings || {};
      
      if (notifSettings.messages === false) continue;
      
      const fcmToken = recipient.fcmToken;
      if (!fcmToken) continue;
      
      const messageText = messageData.text || '';
      const truncatedText = messageText.length > 100 
        ? messageText.substring(0, 100) + '...' 
        : messageText;
      
      await messaging.send({
        token: fcmToken,
        notification: {
          title: `💬 ${messageData.senderName || 'New Message'}`,
          body: truncatedText || '📷 Photo'
        },
        data: {
          type: 'message',
          conversationId: conversationId,
          senderId: messageData.senderId,
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
      });
      
      await db.collection('notifications').add({
        userId: recipientId,
        type: 'message',
        actorId: messageData.senderId,
        actorName: messageData.senderName,
        conversationId: conversationId,
        messagePreview: truncatedText,
        createdAt: FieldValue.serverTimestamp(),
        read: false
      });
    }
    
    return null;
  } catch (error) {
    console.error('❌ Error syncing message:', error);
    return null;
  }
});

// =============================================================================
// 9. LIKES/LIGHTBULBS (REALTIME DATABASE - FAST!)
// =============================================================================

/**
 * Handle individual lightbulb/like actions
 * Path: /postInteractions/{postId}/lightbulbs/{userId}
 */
exports.syncLightbulbAction = onValueWritten({
  ref: "/postInteractions/{postId}/lightbulbs/{userId}",
  region: "us-central1"
}, async (event) => {
  const postId = event.params.postId;
  const userId = event.params.userId;
  const isLiked = event.data.after.val() === true;
  const wasLiked = event.data.before.val() === true;
  
  // Only trigger when status changes
  if (isLiked === wasLiked) return null;
  
  console.log(`💡 User ${userId} ${isLiked ? 'liked' : 'unliked'} post ${postId}`);
  
  try {
    // Update the count
    await rtdb.ref(`postInteractions/${postId}/lightbulbCount`).transaction(current => {
      const increment = isLiked ? 1 : -1;
      return Math.max(0, (current || 0) + increment);
    });
    
    // Send notification if it's a new like
    if (isLiked) {
      const postDoc = await db.collection('posts').doc(postId).get();
      if (postDoc.exists) {
        const post = postDoc.data();
        await sendLightbulbNotification(userId, post.authorId, postId);
      }
    }
    
    return null;
  } catch (error) {
    console.error('❌ Error syncing lightbulb action:', error);
    return null;
  }
});

async function sendLightbulbNotification(likerUserId, postAuthorId, postId) {
  try {
    if (likerUserId === postAuthorId) return;

    const likerDoc = await db.collection('users').doc(likerUserId).get();
    if (!likerDoc.exists) return;
    const liker = likerDoc.data();

    const authorDoc = await db.collection('users').doc(postAuthorId).get();
    if (!authorDoc.exists) return;
    const author = authorDoc.data();

    const notifSettings = author.notificationSettings || {};
    if (notifSettings.likes === false) return;

    const fcmToken = author.fcmToken;
    if (!fcmToken) return;

    const message = {
      token: fcmToken,
      notification: {
        title: '💡 New Like',
        body: `${liker.displayName} liked your post`,
      },
      data: {
        type: 'lightbulb',
        postId: postId,
        userId: likerUserId,
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
    console.log(`✅ Lightbulb notification sent to ${postAuthorId}`);

    await db.collection('notifications').add({
      userId: postAuthorId,
      type: 'lightbulb',
      actorId: likerUserId,
      actorName: liker.displayName,
      actorUsername: liker.username,
      postId: postId,
      createdAt: FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending lightbulb notification:', error);
  }
}

// =============================================================================
// 10. FOLLOWS (REALTIME DATABASE - FAST!)
// =============================================================================

/**
 * Handle follow actions in Realtime Database
 * Path: /follows/{followerId}/following/{followingId}
 */
exports.syncFollowAction = onValueWritten({
  ref: "/follows/{followerId}/following/{followingId}",
  region: "us-central1"
}, async (event) => {
  const followerId = event.params.followerId;
  const followingId = event.params.followingId;
  const isFollowing = event.data.after.val() === true;
  const wasFollowing = event.data.before.val() === true;
  
  // Only trigger when status changes
  if (isFollowing === wasFollowing) return null;
  
  console.log(`👥 User ${followerId} ${isFollowing ? 'followed' : 'unfollowed'} ${followingId}`);
  
  try {
    if (isFollowing) {
      // Create follow document in Firestore
      const followId = `${followerId}_${followingId}`;
      await db.collection('follows').doc(followId).set({
        followerId: followerId,
        followingId: followingId,
        createdAt: FieldValue.serverTimestamp()
      });
    } else {
      // Delete follow document from Firestore
      const followId = `${followerId}_${followingId}`;
      await db.collection('follows').doc(followId).delete();
    }
    
    // Update follower/following counts
    const increment = isFollowing ? 1 : -1;
    
    await db.collection('users').doc(followingId).update({
      followersCount: FieldValue.increment(increment)
    });
    
    await db.collection('users').doc(followerId).update({
      followingCount: FieldValue.increment(increment)
    });
    
    // Send notification for new follow
    if (isFollowing) {
      await sendFollowNotification(followerId, followingId);
    }
    
    console.log(`✅ Follow action synced`);
    return null;
  } catch (error) {
    console.error('❌ Error syncing follow action:', error);
    return null;
  }
});

// =============================================================================
// 11. COMMENTS (REALTIME DATABASE - FAST!)
// =============================================================================

/**
 * Handle individual comment creation
 * Path: /postInteractions/{postId}/comments/{commentId}
 */
exports.syncCommentCreation = onValueWritten({
  ref: "/postInteractions/{postId}/comments/{commentId}",
  region: "us-central1"
}, async (event) => {
  // Only trigger when comment is created
  if (!event.data.after.exists() || event.data.before.exists()) {
    return null;
  }
  
  const postId = event.params.postId;
  const commentId = event.params.commentId;
  const commentData = event.data.after.val();
  
  console.log(`💬 New comment on post ${postId}`);
  
  try {
    // Sync comment to Firestore
    await db.collection('posts')
      .doc(postId)
      .collection('comments')
      .doc(commentId)
      .set({
        ...commentData,
        createdAt: FieldValue.serverTimestamp()
      });
    
    // Update comment count
    await rtdb.ref(`postInteractions/${postId}/commentCount`).transaction(current => {
      return (current || 0) + 1;
    });
    
    // Send notification
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
    
    console.log(`✅ Comment synced`);
    return null;
  } catch (error) {
    console.error('❌ Error syncing comment:', error);
    return null;
  }
});

// =============================================================================
// 12. COMMENT REPLIES (REALTIME DATABASE - FAST!)
// =============================================================================

/**
 * Handle comment replies
 * Path: /postInteractions/{postId}/comments/{commentId}/replies/{replyId}
 */
exports.syncCommentReply = onValueWritten({
  ref: "/postInteractions/{postId}/comments/{commentId}/replies/{replyId}",
  region: "us-central1"
}, async (event) => {
  // Only trigger when reply is created
  if (!event.data.after.exists() || event.data.before.exists()) {
    return null;
  }
  
  const postId = event.params.postId;
  const commentId = event.params.commentId;
  const replyId = event.params.replyId;
  const replyData = event.data.after.val();
  
  console.log(`↩️ New reply on comment ${commentId}`);
  
  try {
    // Sync reply to Firestore
    await db.collection('posts')
      .doc(postId)
      .collection('comments')
      .doc(commentId)
      .collection('replies')
      .doc(replyId)
      .set({
        ...replyData,
        createdAt: FieldValue.serverTimestamp()
      });
    
    // Update reply count on the comment
    await rtdb.ref(`postInteractions/${postId}/comments/${commentId}/replyCount`)
      .transaction(current => {
        return (current || 0) + 1;
      });
    
    // Send notification to comment author
    const commentSnapshot = await rtdb.ref(`postInteractions/${postId}/comments/${commentId}`).once('value');
    if (commentSnapshot.exists()) {
      const commentData = commentSnapshot.val();
      await sendReplyNotification(
        replyData.authorId,
        commentData.authorId,
        postId,
        commentId,
        replyData.content
      );
    }
    
    console.log(`✅ Reply synced`);
    return null;
  } catch (error) {
    console.error('❌ Error syncing reply:', error);
    return null;
  }
});

async function sendReplyNotification(replyAuthorId, commentAuthorId, postId, commentId, replyText) {
  try {
    if (replyAuthorId === commentAuthorId) return;

    const replyAuthorDoc = await db.collection('users').doc(replyAuthorId).get();
    if (!replyAuthorDoc.exists) return;
    const replyAuthor = replyAuthorDoc.data();

    const commentAuthorDoc = await db.collection('users').doc(commentAuthorId).get();
    if (!commentAuthorDoc.exists) return;
    const commentAuthor = commentAuthorDoc.data();

    const notifSettings = commentAuthor.notificationSettings || {};
    if (notifSettings.replies === false) return;

    const fcmToken = commentAuthor.fcmToken;
    if (!fcmToken) return;

    const truncatedReply = replyText.length > 50 
      ? replyText.substring(0, 50) + '...' 
      : replyText;

    const message = {
      token: fcmToken,
      notification: {
        title: '↩️ New Reply',
        body: `${replyAuthor.displayName}: ${truncatedReply}`,
      },
      data: {
        type: 'reply',
        postId: postId,
        commentId: commentId,
        replyAuthorId: replyAuthorId,
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
    console.log(`✅ Reply notification sent to ${commentAuthorId}`);

    await db.collection('notifications').add({
      userId: commentAuthorId,
      type: 'reply',
      actorId: replyAuthorId,
      actorName: replyAuthor.displayName,
      actorUsername: replyAuthor.username,
      postId: postId,
      commentId: commentId,
      replyText: truncatedReply,
      createdAt: FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending reply notification:', error);
  }
}
// =============================================================================
// 13. UNREAD COUNTS (REALTIME DATABASE)
// =============================================================================

/**
 * Update unread notification count when notification is created
 */
exports.updateUnreadNotificationCount = onDocumentCreated("notifications/{notificationId}", async (event) => {
  try {
    const notification = event.data.data();
    const userId = notification.userId;
    
    if (!userId) return null;
    
    console.log(`📬 Incrementing unread notification count for user ${userId}`);
    
    // Increment unread notification count in Realtime Database
    await rtdb.ref(`unreadCounts/${userId}/notifications`).transaction(current => {
      return (current || 0) + 1;
    });
    
    console.log(`✅ Unread notification count updated`);
    return null;
  } catch (error) {
    console.error('❌ Error updating unread notification count:', error);
    return null;
  }
});

/**
 * Decrement unread count when notification is marked as read
 */
exports.decrementUnreadNotificationCount = onDocumentWritten("notifications/{notificationId}", async (event) => {
  try {
    // Only trigger when notification is marked as read
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    
    // Check if notification was just marked as read
    if (before && after && !before.read && after.read) {
      const userId = after.userId;
      
      console.log(`📭 Decrementing unread notification count for user ${userId}`);
      
      // Decrement unread notification count
      await rtdb.ref(`unreadCounts/${userId}/notifications`).transaction(current => {
        return Math.max(0, (current || 0) - 1);
      });
      
      console.log(`✅ Unread notification count decremented`);
    }
    
    return null;
  } catch (error) {
    console.error('❌ Error decrementing unread notification count:', error);
    return null;
  }
});

// =============================================================================
// 14. LIVE PRAYER COUNTERS
// =============================================================================

/**
 * Update live prayer counter when someone starts/stops praying
 * Uses Realtime Database path: prayerActivity/{prayerId}/prayingNow
 */
exports.updatePrayerCounter = onValueWritten({
  ref: "/prayerActivity/{prayerId}/prayingUsers/{userId}",
  region: "us-central1"
}, async (event) => {
  const prayerId = event.params.prayerId;
  const userId = event.params.userId;
  const isActive = event.data.after.val() === true;
  const wasActive = event.data.before.val() === true;
  
  // Only update count if status actually changed
  if (isActive === wasActive) return null;
  
  try {
    console.log(`🙏 ${isActive ? 'User started' : 'User stopped'} praying for ${prayerId}`);
    
    // Update the prayingNow counter
    const increment = isActive ? 1 : -1;
    await rtdb.ref(`prayerActivity/${prayerId}/prayingNow`).transaction(current => {
      return Math.max(0, (current || 0) + increment);
    });
    
    // Also update total prayer count in Firestore
    if (isActive) {
      await db.collection('prayers').doc(prayerId).update({
        totalPrayerCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp()
      });
    }
    
    console.log(`✅ Prayer counter updated`);
    return null;
  } catch (error) {
    console.error('❌ Error updating prayer counter:', error);
    return null;
  }
});

// =============================================================================
// 15. LIVE ACTIVITY FEED
// =============================================================================

/**
 * Add post creation to live activity feed
 */
exports.addPostToActivityFeed = onDocumentCreated("posts/{postId}", async (event) => {
  try {
    const post = event.data.data();
    const postId = event.params.postId;
    
    console.log(`📰 Adding post to live activity feed: ${postId}`);
    
    // Add to global activity feed (keep last 100 activities)
    const activityRef = rtdb.ref('activityFeed/global').push();
    await activityRef.set({
      type: 'post',
      postId: postId,
      userId: post.authorId,
      userName: post.authorName,
      category: post.category,
      timestamp: Date.now(),
      content: post.content.substring(0, 100) // Preview
    });
    
    // Cleanup old activities (keep only last 100)
    const activitiesSnapshot = await rtdb.ref('activityFeed/global')
      .orderByChild('timestamp')
      .once('value');
    
    const activities = [];
    activitiesSnapshot.forEach(child => {
      activities.push({ key: child.key, timestamp: child.val().timestamp });
    });
    
    // Sort by timestamp descending
    activities.sort((a, b) => b.timestamp - a.timestamp);
    
    // Delete activities beyond the 100th
    if (activities.length > 100) {
      const batch = activities.slice(100).map(activity => 
        rtdb.ref(`activityFeed/global/${activity.key}`).remove()
      );
      await Promise.all(batch);
    }
    
    console.log(`✅ Post added to activity feed`);
    return null;
  } catch (error) {
    console.error('❌ Error adding to activity feed:', error);
    return null;
  }
});

/**
 * Add amen to live activity feed
 */
exports.addAmenToActivityFeed = onValueWritten({
  ref: "/postInteractions/{postId}/amens/{userId}",
  region: "us-central1"
}, async (event) => {
  // Only trigger when amen is added (not removed)
  if (!event.data.after.exists() || event.data.before.exists()) {
    return null;
  }
  
  try {
    const postId = event.params.postId;
    const amenData = event.data.after.val();
    
    console.log(`🙏 Adding amen to live activity feed`);
    
    // Get post info
    const postDoc = await db.collection('posts').doc(postId).get();
    if (!postDoc.exists) return null;
    
    const post = postDoc.data();
    
    // Add to activity feed
    const activityRef = rtdb.ref('activityFeed/global').push();
    await activityRef.set({
      type: 'amen',
      postId: postId,
      userId: amenData.userId,
      userName: amenData.userName,
      postAuthor: post.authorName,
      timestamp: Date.now()
    });
    
    console.log(`✅ Amen added to activity feed`);
    return null;
  } catch (error) {
    console.error('❌ Error adding amen to activity feed:', error);
    return null;
  }
});

// =============================================================================
// 16. LIVE COMMUNITY ACTIVITY FEED
// =============================================================================

/**
 * Add community post to community-specific activity feed
 */
exports.addCommunityActivity = onDocumentCreated("communityPosts/{postId}", async (event) => {
  try {
    const post = event.data.data();
    const postId = event.params.postId;
    const communityId = post.communityId;
    
    if (!communityId) return null;
    
    console.log(`📰 Adding post to community ${communityId} activity feed`);
    
    // Add to community activity feed
    const activityRef = rtdb.ref(`communityActivity/${communityId}`).push();
    await activityRef.set({
      type: 'post',
      postId: postId,
      userId: post.authorId,
      userName: post.authorName,
      timestamp: Date.now(),
      content: post.content.substring(0, 100)
    });
    
    // Update community's last activity timestamp
    await db.collection('communities').doc(communityId).update({
      lastActivityAt: FieldValue.serverTimestamp(),
      postCount: FieldValue.increment(1)
    });
    
    // Cleanup old activities (keep only last 50 per community)
    const activitiesSnapshot = await rtdb.ref(`communityActivity/${communityId}`)
      .orderByChild('timestamp')
      .once('value');
    
    const activities = [];
    activitiesSnapshot.forEach(child => {
      activities.push({ key: child.key, timestamp: child.val().timestamp });
    });
    
    activities.sort((a, b) => b.timestamp - a.timestamp);
    
    if (activities.length > 50) {
      const batch = activities.slice(50).map(activity => 
        rtdb.ref(`communityActivity/${communityId}/${activity.key}`).remove()
      );
      await Promise.all(batch);
    }
    
    console.log(`✅ Community activity added`);
    return null;
  } catch (error) {
    console.error('❌ Error adding community activity:', error);
    return null;
  }
});

/**
 * Track when users join communities
 */
exports.trackCommunityJoin = onDocumentCreated("communityMembers/{membershipId}", async (event) => {
  try {
    const membership = event.data.data();
    const communityId = membership.communityId;
    const userId = membership.userId;
    
    console.log(`👥 User ${userId} joined community ${communityId}`);
    
    // Get user info
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return null;
    
    const user = userDoc.data();
    
    // Add to community activity feed
    const activityRef = rtdb.ref(`communityActivity/${communityId}`).push();
    await activityRef.set({
      type: 'join',
      userId: userId,
      userName: user.displayName,
      timestamp: Date.now()
    });
    
    // Update community member count
    await db.collection('communities').doc(communityId).update({
      memberCount: FieldValue.increment(1),
      lastActivityAt: FieldValue.serverTimestamp()
    });
    
    console.log(`✅ Community join tracked`);
    return null;
  } catch (error) {
    console.error('❌ Error tracking community join:', error);
    return null;
  }
});

