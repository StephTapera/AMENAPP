# 🚀 Firebase Cloud Functions Deployment Guide
## Complete Setup for AMENAPP Push Notifications

---

## 📋 **Prerequisites**

Before you begin, ensure you have:
- ✅ Firebase project set up
- ✅ Node.js installed (v16 or higher recommended)
- ✅ Firebase CLI installed globally
- ✅ Terminal/Command Line access

---

## 🛠️ **Step 1: Install Firebase CLI**

### macOS/Linux:
```bash
npm install -g firebase-tools
```

### Verify installation:
```bash
firebase --version
```

You should see something like: `12.9.1` or higher

---

## 🔐 **Step 2: Login to Firebase**

```bash
firebase login
```

This will:
1. Open your browser
2. Ask you to sign in with your Google account
3. Grant Firebase CLI permissions

You should see:
```
✔  Success! Logged in as your-email@gmail.com
```

---

## 📁 **Step 3: Initialize Firebase Functions**

Navigate to your project directory (or create a new folder for functions):

```bash
# Option 1: Initialize in project root
cd /path/to/AMENAPP

# Option 2: Create separate functions folder
mkdir AMENAPP-functions
cd AMENAPP-functions
```

Initialize Firebase:
```bash
firebase init functions
```

### You'll be prompted with:

**1. Select Firebase project:**
```
? Please select an option:
  > Use an existing project
    Create a new project
```
Choose: **Use an existing project**

**2. Select your AMENAPP project:**
```
? Select a default Firebase project:
  > amenapp-xxxxx (AMENAPP)
```

**3. Choose language:**
```
? What language would you like to use to write Cloud Functions?
  > JavaScript
    TypeScript
```
Choose: **JavaScript** (easier to start with)

**4. ESLint:**
```
? Do you want to use ESLint to catch probable bugs?
  > No
    Yes
```
Choose: **No** (or Yes if you want code linting)

**5. Install dependencies:**
```
? Do you want to install dependencies with npm now?
  > Yes
    No
```
Choose: **Yes**

---

## 📂 **Step 4: Your Functions Folder Structure**

After initialization, you'll have:
```
functions/
├── node_modules/
├── index.js          ← Your cloud functions go here
├── package.json
└── .gitignore
```

---

## ✍️ **Step 5: Write Your Cloud Functions**

Edit `functions/index.js` and replace with this code:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ========================================
// 1. FOLLOW NOTIFICATIONS
// ========================================

exports.sendFollowNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    // Only process follow notifications
    if (notification.type !== 'follow') {
      console.log('Skipping non-follow notification');
      return null;
    }
    
    console.log('📬 Processing follow notification:', notification);
    
    try {
      // Get recipient's FCM token
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
      
      // Send push notification
      const message = {
        notification: {
          title: 'New Follower',
          body: notification.message || `${notification.fromUserName} started following you`,
        },
        data: {
          type: 'follow',
          fromUserId: notification.fromUserId || '',
          notificationId: context.params.notificationId,
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

exports.sendMessageNotification = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const conversationId = context.params.conversationId;
    
    console.log('💬 Processing new message:', message);
    
    try {
      // Get conversation to find recipient
      const conversationDoc = await db.collection('conversations').doc(conversationId).get();
      
      if (!conversationDoc.exists) {
        console.log('❌ Conversation not found:', conversationId);
        return null;
      }
      
      const conversation = conversationDoc.data();
      const participantIds = conversation.participantIds || [];
      
      // Find recipient (not the sender)
      const recipientId = participantIds.find(id => id !== message.senderId);
      
      if (!recipientId) {
        console.log('⚠️ No recipient found');
        return null;
      }
      
      // Get recipient's FCM token and notification preferences
      const recipientDoc = await db.collection('users').doc(recipientId).get();
      
      if (!recipientDoc.exists) {
        console.log('❌ Recipient not found:', recipientId);
        return null;
      }
      
      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;
      
      // Check if user has message notifications enabled
      const notificationsEnabled = recipientData.messageNotificationsEnabled !== false;
      
      if (!notificationsEnabled) {
        console.log('⚠️ User has disabled message notifications:', recipientId);
        return null;
      }
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for recipient:', recipientId);
        return null;
      }
      
      // Get sender's name
      const senderDoc = await db.collection('users').doc(message.senderId).get();
      const senderName = senderDoc.exists 
        ? (senderDoc.data().displayName || 'Someone')
        : 'Someone';
      
      // Send push notification
      const pushMessage = {
        notification: {
          title: senderName,
          body: message.text || 'Sent you a message',
        },
        data: {
          type: 'message',
          conversationId: conversationId,
          senderId: message.senderId,
          messageId: context.params.messageId,
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
  });

// ========================================
// 3. PRAYER REQUEST NOTIFICATIONS
// ========================================

exports.sendPrayerRequestNotification = functions.firestore
  .document('prayerRequests/{requestId}')
  .onCreate(async (snap, context) => {
    const prayerRequest = snap.data();
    
    console.log('🙏 Processing new prayer request:', prayerRequest);
    
    try {
      // Get author's followers
      const followsSnapshot = await db.collection('follows')
        .where('followingId', '==', prayerRequest.userId)
        .get();
      
      if (followsSnapshot.empty) {
        console.log('⚠️ No followers to notify');
        return null;
      }
      
      const followerIds = followsSnapshot.docs.map(doc => doc.data().followerId);
      
      // Get author's name
      const authorDoc = await db.collection('users').doc(prayerRequest.userId).get();
      const authorName = authorDoc.exists 
        ? (authorDoc.data().displayName || 'Someone')
        : 'Someone';
      
      // Send notifications to all followers
      const notifications = followerIds.map(async (followerId) => {
        // Get follower's FCM token
        const followerDoc = await db.collection('users').doc(followerId).get();
        
        if (!followerDoc.exists) return;
        
        const followerData = followerDoc.data();
        const fcmToken = followerData.fcmToken;
        
        if (!fcmToken) return;
        
        // Check if user has prayer notifications enabled
        const notificationsEnabled = followerData.prayerNotificationsEnabled !== false;
        if (!notificationsEnabled) return;
        
        // Send push notification
        const message = {
          notification: {
            title: 'New Prayer Request',
            body: `${authorName} shared a prayer request`,
          },
          data: {
            type: 'prayer',
            requestId: context.params.requestId,
            userId: prayerRequest.userId,
          },
          token: fcmToken,
        };
        
        try {
          await messaging.send(message);
          console.log('✅ Prayer notification sent to:', followerId);
        } catch (error) {
          console.error('❌ Error sending to follower:', followerId, error);
        }
      });
      
      await Promise.all(notifications);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending prayer notifications:', error);
      return null;
    }
  });

// ========================================
// 4. SAVED SEARCH MATCH NOTIFICATIONS
// ========================================

exports.sendSavedSearchNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    
    // Only process saved search match notifications
    if (notification.type !== 'savedSearchMatch') {
      return null;
    }
    
    console.log('🔍 Processing saved search notification:', notification);
    
    try {
      // Get recipient's FCM token
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
      
      // Send push notification
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
          notificationId: context.params.notificationId,
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

// ========================================
// 5. TESTIMONY REACTION NOTIFICATIONS
// ========================================

exports.sendTestimonyReactionNotification = functions.firestore
  .document('testimonies/{testimonyId}/reactions/{reactionId}')
  .onCreate(async (snap, context) => {
    const reaction = snap.data();
    const testimonyId = context.params.testimonyId;
    
    console.log('✨ Processing testimony reaction:', reaction);
    
    try {
      // Get testimony to find author
      const testimonyDoc = await db.collection('testimonies').doc(testimonyId).get();
      
      if (!testimonyDoc.exists) {
        console.log('❌ Testimony not found:', testimonyId);
        return null;
      }
      
      const testimony = testimonyDoc.data();
      const authorId = testimony.userId;
      
      // Don't notify user about their own reactions
      if (authorId === reaction.userId) {
        console.log('⚠️ User reacted to their own testimony');
        return null;
      }
      
      // Get author's FCM token
      const authorDoc = await db.collection('users').doc(authorId).get();
      
      if (!authorDoc.exists) {
        console.log('❌ Author not found:', authorId);
        return null;
      }
      
      const authorData = authorDoc.data();
      const fcmToken = authorData.fcmToken;
      
      if (!fcmToken) {
        console.log('⚠️ No FCM token for author:', authorId);
        return null;
      }
      
      // Get reactor's name
      const reactorDoc = await db.collection('users').doc(reaction.userId).get();
      const reactorName = reactorDoc.exists 
        ? (reactorDoc.data().displayName || 'Someone')
        : 'Someone';
      
      // Determine reaction emoji
      const reactionEmoji = reaction.type === 'amen' ? '🙏' : '❤️';
      
      // Send push notification
      const message = {
        notification: {
          title: 'Testimony Reaction',
          body: `${reactorName} reacted ${reactionEmoji} to your testimony`,
        },
        data: {
          type: 'testimonyReaction',
          testimonyId: testimonyId,
          reactorId: reaction.userId,
          reactionType: reaction.type,
        },
        token: fcmToken,
      };
      
      await messaging.send(message);
      console.log('✅ Testimony reaction notification sent to:', authorId);
      
      return null;
    } catch (error) {
      console.error('❌ Error sending testimony reaction notification:', error);
      return null;
    }
  });

// ========================================
// 6. DAILY DEVOTIONAL SCHEDULER (Optional)
// ========================================

exports.scheduledDailyDevotional = functions.pubsub
  .schedule('0 8 * * *') // Every day at 8 AM UTC
  .timeZone('America/New_York') // Change to your timezone
  .onRun(async (context) => {
    console.log('📖 Sending daily devotional notifications...');
    
    try {
      // Get all users with devotional notifications enabled
      const usersSnapshot = await db.collection('users')
        .where('dailyDevotionalEnabled', '==', true)
        .get();
      
      if (usersSnapshot.empty) {
        console.log('⚠️ No users subscribed to daily devotionals');
        return null;
      }
      
      // Send to all subscribed users
      const notifications = usersSnapshot.docs.map(async (userDoc) => {
        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;
        
        if (!fcmToken) return;
        
        const message = {
          notification: {
            title: 'Daily Devotional 📖',
            body: 'Your daily word is ready!',
          },
          data: {
            type: 'dailyDevotional',
          },
          token: fcmToken,
        };
        
        try {
          await messaging.send(message);
          console.log('✅ Devotional sent to:', userDoc.id);
        } catch (error) {
          console.error('❌ Error sending to user:', userDoc.id, error);
        }
      });
      
      await Promise.all(notifications);
      console.log('✅ Daily devotionals sent successfully');
      
      return null;
    } catch (error) {
      console.error('❌ Error sending daily devotionals:', error);
      return null;
    }
  });

// ========================================
// 7. CLEANUP OLD NOTIFICATIONS (Optional)
// ========================================

exports.cleanupOldNotifications = functions.pubsub
  .schedule('0 0 * * 0') // Every Sunday at midnight
  .onRun(async (context) => {
    console.log('🧹 Cleaning up old notifications...');
    
    try {
      // Delete notifications older than 30 days
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      
      const oldNotifications = await db.collection('notifications')
        .where('createdAt', '<', thirtyDaysAgo)
        .limit(500) // Process in batches
        .get();
      
      const batch = db.batch();
      oldNotifications.docs.forEach(doc => {
        batch.delete(doc.ref);
      });
      
      await batch.commit();
      
      console.log(`✅ Deleted ${oldNotifications.size} old notifications`);
      
      return null;
    } catch (error) {
      console.error('❌ Error cleaning up notifications:', error);
      return null;
    }
  });
```

---

## 📦 **Step 6: Install Required Dependencies**

Make sure you're in the `functions/` directory:

```bash
cd functions
npm install firebase-admin firebase-functions
```

---

## 🧪 **Step 7: Test Functions Locally (Optional)**

Install the Firebase emulator suite:

```bash
firebase init emulators
```

Select:
- ✅ Functions Emulator
- ✅ Firestore Emulator

Run emulators:
```bash
firebase emulators:start
```

---

## 🚀 **Step 8: Deploy to Firebase**

From the `functions/` directory:

```bash
firebase deploy --only functions
```

You'll see output like:
```
✔  functions[sendFollowNotification(us-central1)] Successful create operation.
✔  functions[sendMessageNotification(us-central1)] Successful create operation.
✔  functions[sendPrayerRequestNotification(us-central1)] Successful create operation.
...

✔  Deploy complete!
```

---

## 🔍 **Step 9: Verify Deployment**

### Check Firebase Console:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your AMENAPP project
3. Click **Functions** in left sidebar
4. You should see all deployed functions

### Test a function:
Create a test follow in your app and check logs:

```bash
firebase functions:log
```

---

## 🐛 **Step 10: Debugging & Monitoring**

### View real-time logs:
```bash
firebase functions:log --only sendFollowNotification
```

### View logs in Firebase Console:
1. Go to Functions
2. Click on a function name
3. Click "Logs" tab

### Common errors:

**Error: "Permission denied"**
- Solution: Enable Cloud Functions API in Google Cloud Console

**Error: "FCM token invalid"**
- Solution: User needs to re-login or refresh FCM token

**Error: "Function timeout"**
- Solution: Increase timeout in `firebase.json`:
```json
{
  "functions": {
    "timeoutSeconds": 60,
    "memory": "256MB"
  }
}
```

---

## 💰 **Step 11: Pricing Considerations**

Firebase Cloud Functions pricing:
- **Free tier**: 2 million invocations/month
- **Paid tier**: $0.40 per million invocations

For AMENAPP with moderate usage, you'll likely stay in free tier.

---

## ✅ **Step 12: Integration Checklist**

After deployment:

- [ ] Verify all functions deployed successfully
- [ ] Test follow notification (follow a user)
- [ ] Test message notification (send a message)
- [ ] Test prayer request notification (create prayer request)
- [ ] Monitor Firebase Console logs for errors
- [ ] Set up budget alerts in Google Cloud Console

---

## 📱 **Step 13: Update iOS App**

No code changes needed! The app already:
- ✅ Saves FCM tokens to Firestore
- ✅ Handles notification taps
- ✅ Updates badge counts

Just deploy and test!

---

## 🔄 **Step 14: Update Functions**

When you make changes to `functions/index.js`:

```bash
# Re-deploy all functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:sendFollowNotification
```

---

## 🎯 **Quick Commands Reference**

```bash
# Login
firebase login

# Initialize
firebase init functions

# Deploy all
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:functionName

# View logs
firebase functions:log

# Test locally
firebase emulators:start

# Delete function
firebase functions:delete functionName
```

---

## 🚨 **Troubleshooting**

### Problem: Functions not triggering

**Check:**
1. Firestore collection names match (e.g., `notifications`, `conversations`)
2. Document fields match (e.g., `type`, `userId`)
3. FCM tokens are being saved correctly
4. User has granted notification permissions

### Problem: Notifications not received

**Check:**
1. User's FCM token exists in Firestore
2. App has notification permissions
3. Device is connected to internet
4. Check Firebase Console logs for errors

---

## 📊 **Monitoring Dashboard**

Create a monitoring dashboard:

1. Go to Firebase Console → Functions
2. Click "Usage" tab
3. View:
   - Invocations per function
   - Execution time
   - Error rate
   - Memory usage

---

## 🎉 **You're Done!**

Your AMENAPP now has:
✅ Full push notification backend
✅ Follow notifications
✅ Message notifications
✅ Prayer request notifications
✅ Saved search notifications
✅ Testimony reaction notifications
✅ Daily devotional scheduler (optional)
✅ Automatic cleanup

---

## 📚 **Next Steps**

1. **Add notification preferences** to user profile
2. **Implement quiet hours** (don't notify at night)
3. **Add notification batching** (combine multiple notifications)
4. **Implement rich notifications** with images
5. **Add notification actions** (reply, like, etc.)

---

**Need help?** Check Firebase documentation:
- [Cloud Functions Docs](https://firebase.google.com/docs/functions)
- [FCM Documentation](https://firebase.google.com/docs/cloud-messaging)
