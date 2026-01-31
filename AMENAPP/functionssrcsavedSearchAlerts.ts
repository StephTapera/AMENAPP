/**
 * Cloud Function: Send push notification when search alert is created
 * Trigger: onCreate for searchAlerts collection
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const onSearchAlertCreated = functions.firestore
    .document('searchAlerts/{alertId}')
    .onCreate(async (snap, context) => {
        const alert = snap.data();
        const userId = alert.userId;
        const alertId = context.params.alertId;
        
        console.log(`📬 Search alert created for user ${userId}: "${alert.query}"`);
        
        try {
            // Get user's FCM token and notification preferences
            const userDoc = await admin.firestore()
                .collection('users')
                .doc(userId)
                .get();
                
            if (!userDoc.exists) {
                console.log(`⚠️ User ${userId} not found`);
                return null;
            }
            
            const userData = userDoc.data();
            
            // Check if user has enabled notifications
            if (!userData?.allowNotifications) {
                console.log(`⚠️ User ${userId} has disabled all notifications`);
                return null;
            }
            
            // Check if user has enabled saved search alert notifications
            if (!userData?.savedSearchAlertNotifications) {
                console.log(`⚠️ User ${userId} has disabled saved search notifications`);
                return null;
            }
            
            const fcmToken = userData.fcmToken;
            if (!fcmToken) {
                console.log(`⚠️ User ${userId} has no FCM token`);
                return null;
            }
            
            // Get unread notification count for badge
            const unreadCount = await getUnreadNotificationCount(userId);
            
            // Send push notification
            const message = {
                token: fcmToken,
                notification: {
                    title: `New Results: "${alert.query}"`,
                    body: `${alert.resultCount} new result${alert.resultCount === 1 ? '' : 's'} found`,
                },
                data: {
                    type: 'savedSearchAlert',
                    alertId: alertId,
                    savedSearchId: alert.savedSearchId,
                    query: alert.query,
                    resultCount: alert.resultCount.toString(),
                },
                apns: {
                    payload: {
                        aps: {
                            sound: 'default',
                            badge: unreadCount,
                            'thread-id': 'saved-searches',
                        },
                    },
                },
            };
            
            await admin.messaging().send(message);
            console.log(`✅ Search alert notification sent to user ${userId}`);
            
            return null;
            
        } catch (error) {
            console.error(`❌ Error sending search alert notification:`, error);
            return null;
        }
    });

/**
 * Get total unread notification count for badge
 */
async function getUnreadNotificationCount(userId: string): Promise<number> {
    try {
        const snapshot = await admin.firestore()
            .collection('notifications')
            .where('userId', '==', userId)
            .where('read', '==', false)
            .get();
        
        return snapshot.size;
    } catch (error) {
        console.error('Error getting unread count:', error);
        return 0;
    }
}
