# 🚨 QUICK FIX GUIDE - Phase 1 Errors

## Issue 1: Duplicate PushNotificationManager

You have **TWO** `PushNotificationManager.swift` files in your project:
- `PushNotificationManager.swift` (NEW - Phase 1)
- `PushNotificationManager 2.swift` (OLD)

### Fix:

1. **In Xcode**, delete `PushNotificationManager 2.swift`:
   - Right-click the file
   - Select "Delete"
   - Choose "Move to Trash"

2. **Keep only** the newer `PushNotificationManager.swift` file

---

## Issue 2: Cloud Functions Linting Errors

The linting errors are from ESLint complaining about code style. Here's the fixed Cloud Functions file:

### Create `functions/index.js`:

```javascript
/**
 * Firebase Cloud Functions for AMENAPP Messaging
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ============================================================================
// FUNCTION 1: Process FCM Queue (Send Push Notifications)
// ============================================================================

exports.processFCMQueue = functions.firestore
    .document("fcmQueue/{queueId}")
    .onCreate(async (snap, context) => {
      const notification = snap.data();

      console.log("📬 Processing notification:", notification);

      try {
        // Get recipient's FCM token
        const userDoc = await db.collection("users")
            .doc(notification.recipientId).get();

        if (!userDoc.exists) {
          console.error("❌ Recipient user not found:",
              notification.recipientId);
          await snap.ref.update({
            status: "failed",
            error: "User not found",
          });
          return;
        }

        const fcmToken = userDoc.data().fcmToken;

        if (!fcmToken) {
          console.log("⚠️ No FCM token for user:",
              notification.recipientId);
          await snap.ref.update({status: "no_token"});
          return;
        }

        // Build notification payload
        const message = {
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: {
            conversationId: notification.conversationId,
            messageId: notification.messageId || "",
            type: notification.type,
            senderId: notification.senderId,
          },
          token: fcmToken,
        };

        // Send notification
        const response = await messaging.send(message);
        console.log("✅ Notification sent successfully:", response);

        // Update queue status
        await snap.ref.update({
          status: "sent",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          response: response,
        });
      } catch (error) {
        console.error("❌ Error sending notification:", error);
        await snap.ref.update({
          status: "failed",
          error: error.message,
        });
      }
    });

// ============================================================================
// FUNCTION 2: Clean Up Disappeared Messages
// ============================================================================

exports.cleanupDisappearedMessages = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async (context) => {
      console.log("🧹 Starting cleanup of disappeared messages...");

      const now = admin.firestore.Timestamp.now();

      try {
        // Get all conversations
        const conversationsSnapshot = await db.collection("conversations")
            .get();

        let totalDeleted = 0;

        for (const conversationDoc of conversationsSnapshot.docs) {
          const conversationId = conversationDoc.id;

          // Find messages that should have disappeared
          const messagesSnapshot = await db
              .collection("conversations")
              .doc(conversationId)
              .collection("messages")
              .where("disappearAt", "<=", now)
              .get();

          if (messagesSnapshot.empty) {
            continue;
          }

          // Delete expired messages in batch
          const batch = db.batch();

          messagesSnapshot.docs.forEach((messageDoc) => {
            batch.delete(messageDoc.ref);
          });

          await batch.commit();

          totalDeleted += messagesSnapshot.size;
          console.log(`🗑️ Deleted ${messagesSnapshot.size} from ${conversationId}`);
        }

        console.log(`✅ Cleanup complete. Total deleted: ${totalDeleted}`);
      } catch (error) {
        console.error("❌ Error during cleanup:", error);
      }
    });

// ============================================================================
// FUNCTION 3: Update Search Index
// ============================================================================

exports.updateSearchIndex = functions.firestore
    .document("conversations/{convId}/messages/{msgId}")
    .onCreate(async (snap, context) => {
      const message = snap.data();
      const conversationId = context.params.convId;
      const messageId = context.params.msgId;

      console.log("🔍 Updating search index for message:", messageId);

      try {
        // Extract searchable text
        const searchText = message.text.toLowerCase();

        // Create search index entry
        await db.collection("searchIndex")
            .doc(`message_${messageId}`).set({
              type: "message",
              conversationId: conversationId,
              messageId: messageId,
              text: searchText,
              senderId: message.senderId,
              senderName: message.senderName,
              timestamp: message.timestamp,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        console.log("✅ Search index updated for message:", messageId);
      } catch (error) {
        console.error("❌ Error updating search index:", error);
      }
    });

// ============================================================================
// FUNCTION 4: Clean Up Old FCM Queue
// ============================================================================

exports.cleanupFCMQueue = functions.pubsub
    .schedule("every 24 hours")
    .onRun(async (context) => {
      console.log("🧹 Cleaning up old FCM queue entries...");

      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - 7); // 7 days ago

      try {
        const oldEntries = await db
            .collection("fcmQueue")
            .where("createdAt", "<",
                admin.firestore.Timestamp.fromDate(cutoffDate))
            .get();

        if (oldEntries.empty) {
          console.log("No old entries to delete");
          return;
        }

        const batch = db.batch();

        oldEntries.docs.forEach((doc) => {
          batch.delete(doc.ref);
        });

        await batch.commit();

        console.log(`✅ Deleted ${oldEntries.size} old FCM queue entries`);
      } catch (error) {
        console.error("❌ Error cleaning up FCM queue:", error);
      }
    });

console.log("🚀 Cloud Functions initialized successfully");
```

---

## Issue 3: AppDelegate Redeclaration Errors

The errors indicate methods are declared twice. This is because your existing `PushNotificationManager` might have methods that conflict.

### Fix:

The `PushNotificationManager 2.swift` file doesn't have `didRegisterForRemoteNotifications` method. We need to add it.

**Replace `PushNotificationManager 2.swift` with this complete version:**

Since you already have the newer version as a separate file, just **delete** `PushNotificationManager 2.swift` and use the one I created in Phase 1.

---

## 🎯 Quick Action Steps

### Step 1: Fix Xcode Errors

1. **Open Xcode**
2. **Delete** `PushNotificationManager 2.swift`:
   - Find it in Project Navigator
   - Right-click → Delete → Move to Trash
3. **Build** (⌘B) to verify errors are gone

### Step 2: Fix Cloud Functions

1. **Open Terminal** in your project directory
2. **Navigate to functions folder:**
   ```bash
   cd functions
   ```

3. **Replace `index.js` with the fixed version above**
   - Copy the entire code block above
   - Replace the contents of `functions/index.js`

4. **Fix linting automatically:**
   ```bash
   npm run lint -- --fix
   ```

5. **Deploy:**
   ```bash
   cd ..
   firebase deploy --only functions
   ```

---

## ✅ Verification

After fixing:

1. **Xcode should build** without errors
2. **Cloud Functions should deploy** successfully
3. **Test the app** on a real device

---

## 📞 If You Still Have Errors

If you still see errors after these fixes:

1. **Clean Xcode build**: Product → Clean Build Folder (⌘⇧K)
2. **Restart Xcode**
3. **Check which PushNotificationManager is in your target**:
   - Select the file
   - Check File Inspector (right sidebar)
   - Ensure it's checked under "Target Membership"

Let me know if you need help with any specific error!
