/**
 * Cloud Functions for AMEN App
 * 
 * Features:
 * 1. Auto-update user search fields (usernameLowercase, displayNameLowercase)
 * 2. Update follower/following counts
 * 3. Send push notifications for interactions
 * 4. Auto-moderate content (basic implementation)
 * 5. Update post engagement counts
 * 6. Generate user feed recommendations
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const rtdb = admin.database();
const messaging = admin.messaging();

// =============================================================================
// 1. AUTO-UPDATE USER SEARCH FIELDS
// =============================================================================

/**
 * Automatically update lowercase search fields when user profile changes
 * This eliminates the need for manual migration!
 */
exports.updateUserSearchFields = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    // If document was deleted, nothing to do
    if (!change.after.exists) {
      return null;
    }

    const newData = change.after.data();
    const oldData = change.before.exists ? change.before.data() : {};

    // Check if username or displayName changed
    const usernameChanged = newData.username !== oldData.username;
    const displayNameChanged = newData.displayName !== oldData.displayName;

    if (!usernameChanged && !displayNameChanged) {
      // Nothing changed, skip update
      return null;
    }

    // Prepare updates
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

    updates.searchUpdatedAt = admin.firestore.FieldValue.serverTimestamp();

    console.log(`📝 Updating search fields for user ${context.params.userId}:`, updates);

    // Update the document
    return change.after.ref.update(updates);
  });

// =============================================================================
// 2. UPDATE FOLLOWER/FOLLOWING COUNTS
// =============================================================================

/**
 * Update follower count when someone follows/unfollows
 */
exports.updateFollowerCount = functions.firestore
  .document('follows/{followId}')
  .onWrite(async (change, context) => {
    // Get the follow data
    const followData = change.after.exists ? change.after.data() : change.before.data();
    
    if (!followData) return null;

    const followingUserId = followData.followingId; // User being followed
    const followerUserId = followData.followerId;   // User doing the following

    // Determine if this is a creation or deletion
    const isCreated = change.after.exists && !change.before.exists;
    const isDeleted = !change.after.exists && change.before.exists;

    if (!isCreated && !isDeleted) {
      return null; // Update, not create/delete
    }

    const increment = isCreated ? 1 : -1;

    const batch = db.batch();

    // Update follower count for the user being followed
    const followingUserRef = db.collection('users').doc(followingUserId);
    batch.update(followingUserRef, {
      followersCount: admin.firestore.FieldValue.increment(increment)
    });

    // Update following count for the follower
    const followerUserRef = db.collection('users').doc(followerUserId);
    batch.update(followerUserRef, {
      followingCount: admin.firestore.FieldValue.increment(increment)
    });

    console.log(`👥 ${isCreated ? 'Added' : 'Removed'} follow: ${followerUserId} -> ${followingUserId}`);

    await batch.commit();

    // Send notification if someone followed
    if (isCreated) {
      await sendFollowNotification(followerUserId, followingUserId);
    }

    return null;
  });

// =============================================================================
// 3. REALTIME DATABASE TRIGGERS FOR POST INTERACTIONS
// =============================================================================
// These watch Firebase Realtime Database where the iOS app actually writes!

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
// 4. PUSH NOTIFICATIONS
// =============================================================================

/**
 * Send notification when someone follows a user
 */
async function sendFollowNotification(followerUserId, followingUserId) {
  try {
    // Don't notify yourself
    if (followerUserId === followingUserId) return;

    // Get follower info
    const followerDoc = await db.collection('users').doc(followerUserId).get();
    if (!followerDoc.exists) return;
    const follower = followerDoc.data();

    // Get following user's FCM token and settings
    const followingDoc = await db.collection('users').doc(followingUserId).get();
    if (!followingDoc.exists) return;
    const following = followingDoc.data();

    // Check notification preferences
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

    // Send notification
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

    // Create in-app notification
    await db.collection('notifications').add({
      userId: followingUserId,
      type: 'follow',
      actorId: followerUserId,
      actorName: follower.displayName,
      actorUsername: follower.username,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

  } catch (error) {
    console.error('❌ Error sending follow notification:', error);
  }
}

/**
 * Send notification when someone amens a post
 */
async function sendAmenNotification(amenUserId, postAuthorId, postId) {
  try {
    // Don't notify yourself
    if (amenUserId === postAuthorId) return;

    // Get amen user info
    const amenUserDoc = await db.collection('users').doc(amenUserId).get();
    if (!amenUserDoc.exists) return;
    const amenUser = amenUserDoc.data();

    // Get post author's FCM token and settings
    const authorDoc = await db.collection('users').doc(postAuthorId).get();
    if (!authorDoc.exists) return;
    const author = authorDoc.data();

    // Check notification preferences
    const notifSettings = author.notificationSettings || {};
    if (notifSettings.amens === false) return;

    const fcmToken = author.fcmToken;
    if (!fcmToken) return;

    // Send notification
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

    // Create in-app notification
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

/**
 * Send notification when someone comments on a post
 */
async function sendCommentNotification(commenterId, postAuthorId, postId, commentText) {
  try {
    // Don't notify yourself
    if (commenterId === postAuthorId) return;

    // Get commenter info
    const commenterDoc = await db.collection('users').doc(commenterId).get();
    if (!commenterDoc.exists) return;
    const commenter = commenterDoc.data();

    // Get post author's FCM token and settings
    const authorDoc = await db.collection('users').doc(postAuthorId).get();
    if (!authorDoc.exists) return;
    const author = authorDoc.data();

    // Check notification preferences
    const notifSettings = author.notificationSettings || {};
    if (notifSettings.comments === false) return;

    const fcmToken = author.fcmToken;
    if (!fcmToken) return;

    // Truncate comment for notification
    const truncatedComment = commentText.length > 50 
      ? commentText.substring(0, 50) + '...' 
      : commentText;

    // Send notification
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

    // Create in-app notification
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

// =============================================================================
// 5. CONTENT MODERATION
// =============================================================================

/**
 * Basic content moderation - flag potentially inappropriate content
 * In production, you'd use Google's Perspective API or similar
 */
exports.moderatePost = functions.firestore
  .document('posts/{postId}')
  .onCreate(async (snap, context) => {
    const post = snap.data();
    const content = (post.content || '').toLowerCase();

    // Simple keyword-based moderation (expand this list)
    const inappropriateWords = [
      'spam', 'scam', 'hack', 'cheat',
      // Add more as needed
    ];

    const containsInappropriate = inappropriateWords.some(word => 
      content.includes(word)
    );

    if (containsInappropriate) {
      console.log(`⚠️ Post ${context.params.postId} flagged for moderation`);
      
      await snap.ref.update({
        flaggedForReview: true,
        flaggedAt: admin.firestore.FieldValue.serverTimestamp(),
        flaggedReason: 'automatic_keyword_detection'
      });

      // Notify moderators
      await db.collection('moderationQueue').add({
        postId: context.params.postId,
        authorId: post.authorId,
        content: post.content,
        reason: 'automatic_keyword_detection',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewed: false
      });
    }

    return null;
  });

/**
 * Check for spam - too many posts in short time
 */
exports.detectSpam = functions.firestore
  .document('posts/{postId}')
  .onCreate(async (snap, context) => {
    const post = snap.data();
    const userId = post.authorId;

    // Check how many posts user made in last minute
    const oneMinuteAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );

    const recentPosts = await db.collection('posts')
      .where('authorId', '==', userId)
      .where('createdAt', '>', oneMinuteAgo)
      .get();

    if (recentPosts.size > 5) {
      console.log(`🚫 User ${userId} detected as potential spammer`);

      // Flag the post
      await snap.ref.update({
        flaggedForReview: true,
        flaggedReason: 'spam_detection'
      });

      // Temporarily restrict user
      await db.collection('users').doc(userId).update({
        postingRestricted: true,
        restrictionExpires: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 3600000) // 1 hour
        ),
        restrictionReason: 'spam_detection'
      });
    }

    return null;
  });

// =============================================================================
// 6. PRAYER REQUEST REMINDERS (Scheduled Function)
// =============================================================================

/**
 * Send daily prayer reminders to users who committed to pray
 * Runs every day at 9 AM
 */
exports.sendPrayerReminders = functions.pubsub
  .schedule('0 9 * * *')
  .timeZone('America/New_York')
  .onRun(async (context) => {
    console.log('📅 Running daily prayer reminders...');

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    // Get active prayer requests
    const prayerRequests = await db.collection('prayers')
      .where('status', '==', 'active')
      .where('type', '==', 'request')
      .get();

    let remindersSent = 0;

    for (const prayerDoc of prayerRequests.docs) {
      const prayer = prayerDoc.data();
      
      // Get users who committed to pray
      const commitments = await prayerDoc.ref
        .collection('commitments')
        .get();

      for (const commitment of commitments.docs) {
        const commitmentData = commitment.data();
        
        // Check if user wants reminders
        if (!commitmentData.wantsReminders) continue;

        // Send reminder
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

/**
 * Helper to send prayer reminder notification
 */
async function sendPrayerReminderNotification(userId, prayerId, prayerTitle) {
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) return;
    
    const user = userDoc.data();
    const fcmToken = user.fcmToken;
    
    if (!fcmToken) return;

    // Check if prayer reminder notifications are enabled
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

// =============================================================================
// 7. COMMUNITY STATS (Scheduled Function)
// =============================================================================

/**
 * Generate weekly community stats
 * Runs every Monday at 9 AM
 */
exports.generateWeeklyStats = functions.pubsub
  .schedule('0 9 * * 1')
  .timeZone('America/New_York')
  .onRun(async (context) => {
    console.log('📊 Generating weekly stats...');

    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // Get stats for the week
    const postsSnapshot = await db.collection('posts')
      .where('createdAt', '>', admin.firestore.Timestamp.fromDate(weekAgo))
      .get();

    const prayersSnapshot = await db.collection('prayers')
      .where('createdAt', '>', admin.firestore.Timestamp.fromDate(weekAgo))
      .get();

    const answeredPrayers = prayersSnapshot.docs.filter(doc => 
      doc.data().status === 'answered'
    ).length;

    const stats = {
      week: `${weekAgo.toISOString().split('T')[0]} to ${now.toISOString().split('T')[0]}`,
      totalPosts: postsSnapshot.size,
      totalPrayers: prayersSnapshot.size,
      answeredPrayers: answeredPrayers,
      generatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

    // Save stats
    await db.collection('weeklyStats').add(stats);

    console.log('✅ Weekly stats generated:', stats);
    return null;
  });

// =============================================================================
// 8. CALLABLE FUNCTIONS (Called from app)
// =============================================================================

/**
 * Generate personalized feed for user
 */
exports.generateFeed = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = context.auth.uid;
  const limit = data.limit || 20;

  try {
    // Get user's following list
    const followsSnapshot = await db.collection('follows')
      .where('followerId', '==', userId)
      .get();

    const followingIds = followsSnapshot.docs.map(doc => doc.data().followingId);

    if (followingIds.length === 0) {
      // User doesn't follow anyone, return popular posts
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

    // Get posts from followed users (Firestore has a limit of 10 for 'in' queries)
    // So we'll do this in batches
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

    // Sort by created date
    allPosts.sort((a, b) => b.createdAt - a.createdAt);

    return {
      posts: allPosts.slice(0, limit)
    };

  } catch (error) {
    console.error('Error generating feed:', error);
    throw new functions.https.HttpsError('internal', 'Failed to generate feed');
  }
});

/**
 * Report content
 */
exports.reportContent = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { contentType, contentId, reason, details } = data;

  if (!contentType || !contentId || !reason) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  try {
    // Create report
    await db.collection('reports').add({
      contentType,
      contentId,
      reason,
      details: details || '',
      reportedBy: context.auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending'
    });

    console.log(`🚩 Content reported: ${contentType}/${contentId} by ${context.auth.uid}`);

    return { success: true };

  } catch (error) {
    console.error('Error creating report:', error);
    throw new functions.https.HttpsError('internal', 'Failed to create report');
  }
});
// =============================================================================
// 9. MESSAGE NOTIFICATIONS
// =============================================================================

/**
 * Send notification when someone sends a message
 */
exports.onMessageCreated = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      const message = snap.data();
      const conversationId = context.params.conversationId;
      const senderId = message.senderId;
      
      console.log(`💬 New message in conversation ${conversationId} from ${senderId}`);
      
      // Get conversation to find recipients
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
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
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

