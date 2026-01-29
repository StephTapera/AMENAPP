# 🚀 Deploy Message Notifications Function

## ✅ Function Already Added!

I've added the `onMessageCreated` function to your `functionsindex.js` file. This function will:
- Send push notifications when someone sends you a message
- Create in-app notifications
- Respect user notification preferences

---

## 📋 Deployment Steps

### Step 1: Clean Your Functions Folder

Make sure you're in the correct directory and the file is correct:

```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP/functions
```

### Step 2: Check for Syntax Errors

Run this to validate your JavaScript:

```bash
node -c index.js
```

**Expected output:** (nothing = good!)

If you see an error, it will tell you the line number.

### Step 3: Install Dependencies

Make sure all packages are installed:

```bash
npm install
```

**Expected output:**
```
added X packages, and audited X packages in Xs
found 0 vulnerabilities
```

### Step 4: Login to Firebase

```bash
firebase login
```

**Expected output:**
```
✔  Success! Logged in as your@email.com
```

### Step 5: Deploy Functions

```bash
firebase deploy --only functions
```

**Expected output:**
```
=== Deploying to 'your-project'...

i  deploying functions
i  functions: ensuring required API cloudfunctions.googleapis.com is enabled...
i  functions: ensuring required API cloudbuild.googleapis.com is enabled...
✔  functions: required API cloudfunctions.googleapis.com is enabled
✔  functions: required API cloudbuild.googleapis.com is enabled
i  functions: preparing codebase default for deployment
i  functions: preparing functions directory for uploading...
i  functions: packaged functions (XX KB) for uploading
✔  functions: functions folder uploaded successfully
i  functions: updating Node.js 18 function updateUserSearchFields(us-central1)...
i  functions: updating Node.js 18 function updateFollowerCount(us-central1)...
...
i  functions: creating Node.js 18 function onMessageCreated(us-central1)...
✔  functions[onMessageCreated(us-central1)] Successful create operation.
✔  Deploy complete!
```

---

## 🐛 Troubleshooting

### Error: "ReferenceError: functions is not defined"

**Problem:** Syntax error in your `index.js` file

**Solution:**

1. **Check if you accidentally added code outside the file:**
   ```bash
   tail -20 index.js
   ```
   
   The last line should be:
   ```javascript
     });
   ```

2. **If you see extra code after the last `});`, delete it**

3. **Validate the file:**
   ```bash
   node -c index.js
   ```

### Error: "Cannot find module 'firebase-functions'"

**Solution:**
```bash
cd functions
npm install firebase-functions firebase-admin
```

### Error: "Permission denied"

**Solution:**
```bash
firebase login --reauth
```

### Error: "Failed to create function"

**Solution:** Check Cloud Functions quota in Firebase Console

---

## ✅ Verify Deployment

### Check Function Exists:

```bash
firebase functions:list
```

You should see:
```
updateUserSearchFields(us-central1)
updateFollowerCount(us-central1)
updateAmenCount(us-central1)
updateCommentCount(us-central1)
updateRepostCount(us-central1)
moderatePost(us-central1)
detectSpam(us-central1)
sendPrayerReminders(us-central1)
generateWeeklyStats(us-central1)
generateFeed(us-central1)
reportContent(us-central1)
onMessageCreated(us-central1) ← NEW!
```

### Test the Function:

1. **Open your app**
2. **Send a message to another user**
3. **Check Firebase Console → Functions → Logs**

You should see:
```
💬 New message in conversation abc123 from user123
✅ Message notification sent to user456
✅ In-app notification created for user456
```

---

## 📊 What This Function Does

### Trigger:
```
Firestore Path: conversations/{conversationId}/messages/{messageId}
Event: onCreate
```

### Actions:
1. ✅ Gets conversation details
2. ✅ Finds all participants (recipients)
3. ✅ Excludes sender (don't notify yourself)
4. ✅ Checks recipient notification preferences
5. ✅ Gets recipient FCM token
6. ✅ Sends push notification
7. ✅ Creates in-app notification

### Push Notification Format:
```json
{
  "notification": {
    "title": "💬 John Doe",
    "body": "Hey! How are you?"
  },
  "data": {
    "type": "message",
    "conversationId": "abc123",
    "senderId": "user123"
  },
  "apns": {
    "payload": {
      "aps": {
        "sound": "default",
        "badge": 1
      }
    }
  }
}
```

---

## 🧪 Testing Flow

### Test 1: Send Message
1. User A sends message to User B
2. Check logs: `firebase functions:log --only onMessageCreated`
3. Expected: `✅ Message notification sent to {userId}`

### Test 2: Receive Notification (requires 2 devices)
1. User A sends message from Device A
2. Device B should receive push notification
3. Tap notification
4. App opens to conversation

### Test 3: In-App Notification
1. Open app on Device B (while Device A sends message)
2. Check notifications collection in Firestore
3. Should see new notification document

---

## 💰 Cost Estimate

**Free Tier:**
- 2M function invocations/month

**Expected Usage:**
- Average user sends 50 messages/day
- 100 users = 5,000 messages/day = 150,000/month
- **Cost: $0** (well within free tier)

**At Scale (10,000 users):**
- 500,000 messages/day = 15M/month
- **Cost: ~$5-10/month**

---

## 📝 Function Code Summary

```javascript
exports.onMessageCreated = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    // 1. Get message data
    const message = snap.data();
    
    // 2. Get conversation to find recipients
    const conversation = await db.collection('conversations')
      .doc(context.params.conversationId)
      .get();
    
    // 3. Loop through participants
    for (const recipientId of conversation.data().participantIds) {
      // 4. Skip sender
      if (recipientId === message.senderId) continue;
      
      // 5. Check notification preferences
      const recipient = await db.collection('users').doc(recipientId).get();
      if (!recipient.data().notificationSettings?.messages) continue;
      
      // 6. Send push notification
      await messaging.send({
        token: recipient.data().fcmToken,
        notification: {
          title: `💬 ${message.senderName}`,
          body: message.text
        }
      });
      
      // 7. Create in-app notification
      await db.collection('notifications').add({
        userId: recipientId,
        type: 'message',
        actorId: message.senderId,
        actorName: message.senderName,
        conversationId: context.params.conversationId,
        messagePreview: message.text,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false
      });
    }
  });
```

---

## 🎯 Next Steps After Deployment

1. ✅ **Test on real devices** (not simulator)
2. ✅ **Check Firebase Console logs** for errors
3. ✅ **Verify notifications arrive** on recipient device
4. ✅ **Check notification settings** in app work
5. ✅ **Test with multiple users** for real-world scenario

---

## 📞 Common Issues & Solutions

### Issue: "No notification received"

**Checklist:**
- [ ] Function deployed successfully?
- [ ] Recipient has FCM token saved in Firestore?
- [ ] Recipient has notifications enabled in app?
- [ ] Recipient has notifications enabled in iOS Settings?
- [ ] APNs key uploaded to Firebase Console?
- [ ] Message actually created in Firestore?

**Debug:**
```bash
# Check logs
firebase functions:log --only onMessageCreated

# Look for:
✅ Message notification sent to {userId}
⚠️ No FCM token for recipient {userId}
🔕 User has disabled message notifications
```

### Issue: "Function not triggering"

**Causes:**
1. Function not deployed
2. Firestore path doesn't match
3. Function has runtime error

**Debug:**
```bash
# Check function exists
firebase functions:list | grep onMessageCreated

# Check logs for errors
firebase functions:log --only onMessageCreated --limit 50
```

### Issue: "Notification sent but not appearing"

**Causes:**
1. iOS notification permissions not granted
2. App in foreground (need to handle via PushNotificationManager)
3. APNs certificate issue

**Debug:**
1. Check iOS Settings → Notifications → AMENAPP
2. Check Firebase Console → Cloud Messaging → APNs certificates
3. Test with app in background

---

## ✅ Success Criteria

You know it's working when:
- ✅ Function appears in `firebase functions:list`
- ✅ Logs show "Message notification sent"
- ✅ Push notification appears on device
- ✅ Tapping notification opens conversation
- ✅ In-app notification created in Firestore
- ✅ Badge count updates

---

## 🎉 Once Working

Your messaging system will have:
- ✅ Real-time messaging
- ✅ Push notifications
- ✅ In-app notifications
- ✅ Conversation list
- ✅ Message history
- ✅ User preferences
- ✅ Group chat support

**Status:** 🚀 Production Ready!

---

## Quick Deploy Command

```bash
cd /Users/stephtapera/Desktop/AMEN/AMENAPP/functions && \
npm install && \
firebase deploy --only functions:onMessageCreated
```

If all goes well, you should see:
```
✔  functions[onMessageCreated(us-central1)] Successful create operation.
✔  Deploy complete!
```

🎉 **Done!**
