// notificationGrouping.js
// Intelligent notification grouping and badge management
// Prevents notification spam and maintains badge accuracy

const {onDocumentCreated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const db = admin.firestore();

/**
 * Single source of truth for message notifications
 * Replaces multiple notification creation points
 */
exports.onMessageCreated = onDocumentCreated('conversations/{conversationId}/messages/{messageId}', async (event) => {
    const message = event.data.data();
    const conversationId = event.params.conversationId;
    const messageId = event.params.messageId;
    const senderId = message.senderId;

    try {
        // Get conversation details
        const conversationDoc = await db.collection('conversations').doc(conversationId).get();

        if (!conversationDoc.exists) return;

        const conversation = conversationDoc.data();
        const participants = conversation.participants || [];
        const isGroup = conversation.isGroup || false;

        // Send notification to each participant (except sender)
        for (const participantId of participants) {
            if (participantId === senderId) continue;

            // Check if should notify this user
            const shouldNotify = await checkNotificationRules(participantId, conversation, message);

            if (!shouldNotify) continue;

            // Get mute settings
            const muteSettings = await getMuteSettings(participantId, conversationId);

            if (muteSettings.isMuted) continue;

            // Get notification preferences
            const prefs = await getNotificationPreferences(participantId);

            // Create notification document
            const groupId = prefs.groupMessages ? `conv_${conversationId}` : null;

            await db.collection('notifications').add({
                userId: participantId,
                type: isGroup ? 'group_message' : 'message',
                conversationId: conversationId,
                messageId: messageId,
                senderId: senderId,
                senderName: message.senderName || 'Someone',
                preview: message.text ? message.text.substring(0, 100) : '[Media]',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                read: false,
                groupId: groupId,
                priority: conversation.state === 'request' ? 'medium' : 'low'
            });

            // Send FCM push notification if enabled
            if (prefs.pushEnabled) {
                await sendPushNotification(participantId, conversation, message, conversationId);
            }
        }

    } catch (error) {
        console.error('Error creating message notification:', error);
    }
});

/**
 * Check if user should be notified
 */
async function checkNotificationRules(userId, conversation, message) {
    // Don't notify if conversation is in hidden tier
    if (conversation.tier === 'hidden') return false;

    // Don't notify for request messages unless user has opted in
    if (conversation.state === 'request') {
        const userSettings = await getUserSettings(userId);
        if (!userSettings.notifyOnRequests) return false;
    }

    // Don't notify if message is held by moderation
    if (message.deliveryState === 'held') return false;

    return true;
}

/**
 * Get user's mute settings
 */
async function getMuteSettings(userId, conversationId) {
    try {
        const muteDoc = await db.collection('users').doc(userId)
            .collection('muteSettings').doc('current').get();

        if (!muteDoc.exists) {
            return { isMuted: false };
        }

        const settings = muteDoc.data();

        // Check thread-level mute
        const mutedThreads = settings.mutedThreads || {};
        const threadMute = mutedThreads[conversationId];

        if (threadMute) {
            const expiresAt = threadMute.expiresAt?.toDate();
            if (!expiresAt || expiresAt > new Date()) {
                return { isMuted: true };
            }
        }

        // Check quiet hours
        if (settings.quietHoursEnabled) {
            const now = new Date();
            const currentHour = now.getHours();
            const startHour = settings.quietHoursStart || 22;
            const endHour = settings.quietHoursEnd || 8;

            const isQuietHours = (startHour < endHour)
                ? (currentHour >= startHour && currentHour < endHour)
                : (currentHour >= startHour || currentHour < endHour);

            if (isQuietHours) {
                return { isMuted: true };
            }
        }

        return { isMuted: false };

    } catch (error) {
        console.error('Error getting mute settings:', error);
        return { isMuted: false };
    }
}

/**
 * Get user's notification preferences
 */
async function getUserSettings(userId) {
    try {
        const userDoc = await db.collection('users').doc(userId).get();
        const userData = userDoc.data() || {};

        return {
            notifyOnRequests: userData.notifyOnRequests !== false,
            groupMessages: userData.groupMessageNotifications !== false,
            pushEnabled: userData.pushNotificationsEnabled !== false
        };

    } catch (error) {
        console.error('Error getting user settings:', error);
        return {
            notifyOnRequests: true,
            groupMessages: true,
            pushEnabled: true
        };
    }
}

/**
 * Get notification preferences
 */
async function getNotificationPreferences(userId) {
    return await getUserSettings(userId);
}

/**
 * Send FCM push notification
 */
async function sendPushNotification(userId, conversation, message, conversationId) {
    try {
        // Get user's FCM tokens
        const tokensSnapshot = await db.collection('users').doc(userId)
            .collection('devices').get();

        if (tokensSnapshot.empty) return;

        const tokens = tokensSnapshot.docs
            .map(doc => doc.data().fcmToken)
            .filter(token => token);

        if (tokens.length === 0) return;

        // Get current unread count
        const unreadCount = await getUnreadCount(userId);

        // Build notification payload
        const title = conversation.isGroup
            ? conversation.name || 'Group'
            : message.senderName || 'Someone';

        const body = conversation.state === 'request'
            ? 'Message request...'
            : message.text.substring(0, 100) || '[Media]';

        const payload = {
            notification: {
                title: title,
                body: body,
                badge: unreadCount.toString(),
                sound: 'default'
            },
            data: {
                type: conversation.isGroup ? 'group_message' : 'message',
                conversationId: conversationId,
                messageId: message.id || '',
                senderId: message.senderId,
                deepLink: `amen://messages/${conversationId}`
            },
            apns: {
                payload: {
                    aps: {
                        'mutable-content': 1,
                        'content-available': 1,
                        category: conversation.state === 'request' ? 'MESSAGE_REQUEST' : 'MESSAGE',
                        threadId: conversationId
                    }
                }
            }
        };

        // Send to all user devices
        const promises = tokens.map(token =>
            admin.messaging().send({
                token: token,
                ...payload
            }).catch(error => {
                console.error(`Error sending to token ${token}:`, error);
                // Remove invalid tokens
                if (error.code === 'messaging/invalid-registration-token' ||
                    error.code === 'messaging/registration-token-not-registered') {
                    return db.collection('users').doc(userId)
                        .collection('devices')
                        .where('fcmToken', '==', token)
                        .get()
                        .then(snapshot => {
                            snapshot.forEach(doc => doc.ref.delete());
                        });
                }
            })
        );

        await Promise.all(promises);

    } catch (error) {
        console.error('Error sending push notification:', error);
    }
}

/**
 * Get unread count for user
 */
async function getUnreadCount(userId) {
    try {
        const snapshot = await db.collection('notifications')
            .where('userId', '==', userId)
            .where('read', '==', false)
            .count()
            .get();

        return snapshot.data().count;

    } catch (error) {
        console.error('Error getting unread count:', error);
        return 0;
    }
}

/**
 * Update badge count when notification is created/updated
 */
exports.updateBadgeCount = onDocumentWritten('notifications/{notificationId}', async (event) => {
    const notification = event.data.after.exists ? event.data.after.data() : null;
    const previousNotification = event.data.before.exists ? event.data.before.data() : null;
    const userId = notification?.userId || previousNotification?.userId;

    if (!userId) return;

    try {
        // Calculate new unread count
        const unreadCount = await getUnreadCount(userId);

        // Update user's badge count document
        await db.collection('users').doc(userId)
            .collection('metadata').doc('badge')
            .set({
                count: unreadCount,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

        // Send silent push to update badge on all devices
        const tokensSnapshot = await db.collection('users').doc(userId)
            .collection('devices').get();

        const tokens = tokensSnapshot.docs
            .map(doc => doc.data().fcmToken)
            .filter(token => token);

        if (tokens.length === 0) return;

        const promises = tokens.map(token =>
            admin.messaging().send({
                token: token,
                apns: {
                    payload: {
                        aps: {
                            badge: unreadCount,
                            'content-available': 1
                        }
                    }
                }
            }).catch(error => {
                console.error(`Error updating badge for token:`, error);
            })
        );

        await Promise.all(promises);

    } catch (error) {
        console.error('Error updating badge count:', error);
    }
});

/**
 * Group notifications for display
 */
exports.getGroupedNotifications = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = request.auth.uid;

    try {
        // Get all unread notifications
        const snapshot = await db.collection('notifications')
            .where('userId', '==', userId)
            .where('read', '==', false)
            .orderBy('createdAt', 'desc')
            .limit(100)
            .get();

        const notifications = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data()
        }));

        // Group by groupId or individual
        const grouped = {};

        for (const notif of notifications) {
            const key = notif.groupId || notif.id;

            if (!grouped[key]) {
                grouped[key] = {
                    groupId: key,
                    notifications: [],
                    latestTimestamp: notif.createdAt,
                    title: '',
                    count: 0
                };
            }

            grouped[key].notifications.push(notif);
            grouped[key].count++;

            if (notif.createdAt > grouped[key].latestTimestamp) {
                grouped[key].latestTimestamp = notif.createdAt;
            }
        }

        // Format groups
        const groups = Object.values(grouped).map(group => {
            if (group.notifications.length === 1) {
                const notif = group.notifications[0];
                return {
                    groupId: group.groupId,
                    title: notif.senderName || 'Someone',
                    preview: notif.preview,
                    count: 1,
                    timestamp: notif.createdAt,
                    conversationId: notif.conversationId
                };
            } else {
                const firstNotif = group.notifications[0];
                return {
                    groupId: group.groupId,
                    title: firstNotif.senderName || 'Conversation',
                    preview: `${group.count} new messages`,
                    count: group.count,
                    timestamp: group.latestTimestamp,
                    conversationId: firstNotif.conversationId
                };
            }
        });

        // Sort by timestamp
        groups.sort((a, b) => b.timestamp - a.timestamp);

        return { groups };

    } catch (error) {
        console.error('Error grouping notifications:', error);
        throw new HttpsError('internal', 'Error grouping notifications');
    }
});

/**
 * Mark notification(s) as read
 */
exports.markNotificationsRead = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = request.auth.uid;
    const { conversationId, notificationIds } = request.data;

    try {
        const batch = db.batch();

        if (conversationId) {
            // Mark all notifications for this conversation as read
            const snapshot = await db.collection('notifications')
                .where('userId', '==', userId)
                .where('conversationId', '==', conversationId)
                .where('read', '==', false)
                .get();

            snapshot.docs.forEach(doc => {
                batch.update(doc.ref, { read: true, readAt: admin.firestore.FieldValue.serverTimestamp() });
            });

        } else if (notificationIds && notificationIds.length > 0) {
            // Mark specific notifications as read
            for (const notifId of notificationIds) {
                const notifRef = db.collection('notifications').doc(notifId);
                batch.update(notifRef, { read: true, readAt: admin.firestore.FieldValue.serverTimestamp() });
            }
        }

        await batch.commit();

        return { success: true };

    } catch (error) {
        console.error('Error marking notifications read:', error);
        throw new HttpsError('internal', 'Error marking notifications read');
    }
});
