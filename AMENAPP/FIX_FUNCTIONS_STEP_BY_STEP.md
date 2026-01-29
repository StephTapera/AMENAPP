# 🔧 Fix Cloud Functions - Step by Step

## Problem
Your `functions/index.js` has a v1 function (`functions.firestore`) in a v2 file. We need to remove it and add the correct v2 version.

---

## ✅ Step 1: Open Terminal

Open Terminal app (if not already open)

---

## ✅ Step 2: Navigate to Functions Folder

Copy and paste this command:

```bash
cd ~/Desktop/AMEN/AMENAPP/functions
```

Press **Enter**

---

## ✅ Step 3: Create a Backup

Copy and paste this command:

```bash
cp index.js index.js.backup
```

Press **Enter**

✅ You should see no output (that's good!)

---

## ✅ Step 4: Open the File in Nano Editor

Copy and paste this command:

```bash
nano index.js
```

Press **Enter**

You should see the file open in the terminal editor.

---

## ✅ Step 5: Find the Bad Function

1. Press `Ctrl + W` (this opens search)
2. Type: `exports.onMessageCreated`
3. Press **Enter**

The cursor will jump to the bad function.

---

## ✅ Step 6: Delete the Bad Function

1. Press `Ctrl + K` repeatedly to delete lines
2. Keep pressing `Ctrl + K` until you've deleted everything from `exports.onMessageCreated` to the very end
3. The last line of your file should now be the closing `});` of the `reportContent` function

**You should delete everything that looks like this:**

```javascript
exports.onMessageCreated = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const conversationId = context.params.conversationId;
    
    // Get conversation to find recipients
    const conversation = await db.collection('conversations').doc(conversationId).get();
    const participants = conversation.data().participantIds;
    
    // Send notification to all participants except sender
    for (const recipientId of participants) {
      if (recipientId === message.senderId) continue;
      
      const recipient = await db.collection('users').doc(recipientId).get();
      const fcmToken = recipient.data()?.fcmToken;
      
      if (fcmToken) {
        await messaging.send({
          token: fcmToken,
          notification: {
            title: `💬 ${message.senderName}`,
            body: message.text
          },
          data: {
            type: 'message',
            conversationId: conversationId
          }
        });
      }
    }
  });
```

---

## ✅ Step 7: Save and Exit Nano

1. Press `Ctrl + X` (exit)
2. It will ask "Save modified buffer?" - Press **Y** (yes)
3. It will show the filename - Press **Enter** (confirm)

✅ You should be back at the terminal prompt

---

## ✅ Step 8: Verify the File is Fixed

Copy and paste this command:

```bash
node -c index.js
```

Press **Enter**

**Expected output:** Nothing (silence is good!)

If you see an error, **STOP** and tell me what it says.

---

## ✅ Step 9: Deploy Functions

Copy and paste this command:

```bash
firebase deploy --only functions
```

Press **Enter**

**Wait...** (this takes 2-3 minutes)

**Expected output:**
```
=== Deploying to 'amenapp-xxxxx'...

i  deploying functions
✔  functions: Finished running predeploy script.
i  functions: preparing codebase default for deployment
...
✔  functions[updateUserSearchFields(us-central1)]: Successful update operation.
✔  functions[updateFollowerCount(us-central1)]: Successful update operation.
...
✔  Deploy complete!
```

✅ **SUCCESS!** Your functions are now deployed (without the message function).

---

## ✅ Step 10: Add the Correct Message Function (v2 Syntax)

Now let's add the message notification function with the CORRECT v2 syntax.

Copy and paste this ENTIRE command block:

```bash
cat >> index.js << 'EOF'

// =============================================================================
// MESSAGE NOTIFICATIONS (v2 syntax)
// =============================================================================

exports.onMessageCreated = onDocumentCreated({
  document: 'conversations/{conversationId}/messages/{messageId}',
  region: 'us-central1',
}, async (event) => {
  try {
    const message = event.data.data();
    const conversationId = event.params.conversationId;
    const senderId = message.senderId;
    
    console.log(`💬 New message in conversation ${conversationId} from ${senderId}`);
    
    // Get Firestore and Messaging instances
    const db = getFirestore();
    const messaging = getMessaging();
    
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
```

Press **Enter**

✅ Function added!

---

## ✅ Step 11: Verify Syntax Again

Copy and paste this command:

```bash
node -c index.js
```

Press **Enter**

**Expected output:** Nothing (silence is good!)

If you see an error, **STOP** and tell me what it says.

---

## ✅ Step 12: Deploy the Message Function

Copy and paste this command:

```bash
firebase deploy --only functions:onMessageCreated
```

Press **Enter**

**Wait...** (this takes 1-2 minutes)

**Expected output:**
```
=== Deploying to 'amenapp-xxxxx'...

i  deploying functions
i  functions: preparing codebase default for deployment
...
i  functions: creating Node.js 18 function onMessageCreated(us-central1)...
✔  functions[onMessageCreated(us-central1)] Successful create operation.
✔  Deploy complete!
```

---

## 🎉 Step 13: Verify It's Working

Copy and paste this command:

```bash
firebase functions:list
```

Press **Enter**

**You should see:**
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
onMessageCreated(us-central1) ← YOUR NEW FUNCTION! 🎉
```

---

## ✅ ALL DONE! 🚀

Your message notifications are now deployed and working!

### What Works Now:
- ✅ Real-time messaging (already fixed in MessagesView.swift)
- ✅ Push notifications when someone messages you
- ✅ In-app notifications
- ✅ Respects user notification preferences

### Test It:
1. Open your app on a device
2. Send a message to another user
3. The recipient should receive a push notification! 📬

---

## 🐛 Troubleshooting

### If Step 8 or Step 11 shows an error:

**Run this:**
```bash
cat index.js | tail -20
```

**Copy the output and send it to me.** I'll tell you what to fix.

### If deployment fails:

**Check the error message.** Common issues:
- **"Permission denied"** → Run `firebase login --reauth`
- **"Region not supported"** → Ignore, it still works
- **"Quota exceeded"** → Wait a few minutes and try again

### If function doesn't trigger:

**Check logs:**
```bash
firebase functions:log --only onMessageCreated
```

---

## 📋 Summary of What We Did

1. ✅ Backed up your functions file
2. ✅ Removed the broken v1 function
3. ✅ Deployed existing functions (to make sure they still work)
4. ✅ Added the correct v2 message notification function
5. ✅ Deployed the new function
6. ✅ Verified it's working

**Total time:** ~10 minutes (including deployment wait times)

---

## 🎯 Next Steps

Now that messages are working:

1. **Test messaging** - Send a message and verify it works
2. **Test notifications** - Send a message and verify push notification arrives
3. **Complete the setup checklist** from earlier (APNs key, etc.)

---

**Start with Step 1 and work through each step carefully!**

If you get stuck at ANY step, STOP and tell me:
1. What step you're on
2. What you see on screen
3. Any error messages

I'll help you fix it! 🚀
