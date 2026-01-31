# Push Notifications & Delivery Status - Complete Implementation Guide

## ✅ What I've Implemented for You

### 1. Enhanced PushNotificationManager
- ✅ Badge count now includes unread messages
- ✅ Automatic conversation opening from notifications
- ✅ Message request navigation support

### 2. MessagingCoordinator Updates
- ✅ Added `shouldOpenMessageRequests` property
- ✅ `openMessageRequests()` method for deep linking

### 3. Message Delivery Status UI
- ✅ Created `MessageDeliveryStatusView.swift` with beautiful status indicators
- ✅ Animated delivery states
- ✅ Updated ChatView to display delivery status

### 4. MessagesView Updates
- ✅ Added coordinator listener for opening requests tab
- ✅ Smooth animation when navigating to requests

---

## 🚀 Complete Setup Instructions

### Phase 1: Xcode Configuration (5 minutes)

#### Step 1: Add Push Notification Capability
1. Open your project in Xcode
2. Select your target (AMENAPP)
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes** and check:
   - [x] Remote notifications
   - [x] Background fetch

#### Step 2: Verify Info.plist
Add these keys if not already present:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

---

### Phase 2: Firebase Console Setup (10 minutes)

#### Step 1: Generate APNs Authentication Key

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Keys** → **+** (Create new key)
4. Name it "AMENAPP Push Notifications"
5. Check **Apple Push Notifications service (APNs)**
6. Click **Continue** → **Register**
7. **Download the .p8 file** (you can't download it again!)
8. Note your **Key ID** and **Team ID**

#### Step 2: Upload to Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your AMENAPP project
3. Click the gear icon → **Project Settings**
4. Go to **Cloud Messaging** tab
5. Scroll to **Apple app configuration**
6. Click **Upload** under **APNs Authentication Key**
7. Upload your .p8 file
8. Enter your **Key ID** and **Team ID**
9. Click **Upload**

✅ **Done!** Firebase can now send push notifications to iOS devices.

---

### Phase 3: Initialize Notifications in App (Already Done! ✅)

The following is already wired up in your code:

```swift
// In AMENAPPApp.swift
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

// AppDelegate.swift already has:
// - Firebase configuration
// - Notification delegate setup
// - FCM token handling
```

You just need to **request permission** when appropriate. Add this to your login flow or onboarding:

```swift
// In your ContentView or after login:
.onAppear {
    Task {
        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
        if granted {
            print("✅ Push notifications enabled")
            PushNotificationManager.shared.setupFCMToken()
        }
    }
}
```

---

### Phase 4: Deploy Cloud Functions (20 minutes)

#### Step 1: Install Firebase CLI

```bash
# If not already installed:
npm install -g firebase-tools

# Login to Firebase:
firebase login
```

#### Step 2: Initialize Functions in Your Project

```bash
# Navigate to your project directory:
cd /path/to/AMENAPP

# Initialize Firebase Functions:
firebase init functions

# Select:
# - Use existing project → Select AMENAPP
# - Language → TypeScript
# - ESLint → Yes
# - Install dependencies → Yes
```

#### Step 3: Create the Cloud Function

Create `functions/src/index.ts` with this code:

```typescript
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

interface Message {
  senderId: string;
  senderName: string;
  text: string;
  timestamp: admin.firestore.Timestamp;
  isRead: boolean;
  attachments?: Array<{
    type: string;
    url: string;
  }>;
}

interface Conversation {
  participantIds: string[];
  participantNames: Record<string, string>;
  conversationStatus: string;
  isGroup: boolean;
  groupName?: string;
  mutedBy?: string[];
}

/**
 * Send push notification when new message is created
 */
export const sendMessageNotification = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    try {
      const message = snapshot.data() as Message;
      const conversationId = context.params.conversationId;
      const messageId = context.params.messageId;

      console.log(`📨 New message in conversation ${conversationId}`);

      // Get conversation details
      const conversationDoc = await db
        .collection("conversations")
        .doc(conversationId)
        .get();

      if (!conversationDoc.exists) {
        console.log("❌ Conversation not found");
        return;
      }

      const conversation = conversationDoc.data() as Conversation;

      // Don't send notifications for pending conversations (message requests)
      // Those will trigger a different notification
      if (conversation.conversationStatus === "pending") {
        console.log("⏸️ Message request - sending request notification");
        await sendMessageRequestNotification(
          conversationId,
          message,
          conversation
        );
        return;
      }

      // Get recipients (all participants except sender)
      const recipientIds = conversation.participantIds.filter(
        (id) => id !== message.senderId
      );

      if (recipientIds.length === 0) {
        console.log("⚠️ No recipients to notify");
        return;
      }

      // Prepare notification content
      const senderName = message.senderName || "Someone";
      let notificationBody = message.text;

      // Handle attachments
      if (message.attachments && message.attachments.length > 0) {
        const attachment = message.attachments[0];
        switch (attachment.type) {
          case "photo":
            notificationBody = "📷 Photo";
            break;
          case "video":
            notificationBody = "🎥 Video";
            break;
          case "audio":
            notificationBody = "🎤 Voice message";
            break;
          default:
            notificationBody = "📎 Attachment";
        }
      }

      // Truncate long messages
      if (notificationBody.length > 100) {
        notificationBody = notificationBody.substring(0, 97) + "...";
      }

      // Conversation name for title
      let conversationName: string;
      if (conversation.isGroup) {
        conversationName = conversation.groupName || "Group Chat";
      } else {
        conversationName = senderName;
      }

      // Send to all recipients
      const promises = recipientIds.map(async (recipientId) => {
        // Get recipient's FCM token
        const userDoc = await db.collection("users").doc(recipientId).get();

        if (!userDoc.exists) {
          console.log(`⚠️ User ${recipientId} not found`);
          return;
        }

        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;

        if (!fcmToken) {
          console.log(`⚠️ No FCM token for user ${recipientId}`);
          return;
        }

        // Check if muted
        const isMuted = conversation.mutedBy?.includes(recipientId) ?? false;
        if (isMuted) {
          console.log(`🔕 Conversation muted for user ${recipientId}`);
          return;
        }

        // Calculate badge count
        const badgeCount = await calculateBadgeCount(recipientId);

        try {
          const notificationMessage: admin.messaging.Message = {
            token: fcmToken,
            notification: {
              title: conversation.isGroup
                ? `${senderName} in ${conversationName}`
                : conversationName,
              body: notificationBody,
            },
            data: {
              conversationId: conversationId,
              messageId: messageId,
              senderId: message.senderId,
              type: "message",
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: badgeCount,
                  category: "MESSAGE",
                  threadId: conversationId,
                },
              },
            },
            android: {
              notification: {
                sound: "default",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
                channelId: "messages",
              },
            },
          };

          const response = await messaging.send(notificationMessage);
          console.log(`✅ Notification sent to ${recipientId}: ${response}`);
        } catch (error: any) {
          console.error(`❌ Error sending to ${recipientId}:`, error);

          // Remove invalid token
          if (
            error.code === "messaging/invalid-registration-token" ||
            error.code === "messaging/registration-token-not-registered"
          ) {
            await db.collection("users").doc(recipientId).update({
              fcmToken: admin.firestore.FieldValue.delete(),
            });
            console.log(`🗑️ Removed invalid token for ${recipientId}`);
          }
        }
      });

      await Promise.all(promises);
    } catch (error) {
      console.error("❌ Error in sendMessageNotification:", error);
    }
  });

/**
 * Send notification for message request (pending conversation)
 */
async function sendMessageRequestNotification(
  conversationId: string,
  message: Message,
  conversation: Conversation
) {
  const recipientIds = conversation.participantIds.filter(
    (id) => id !== message.senderId
  );

  for (const recipientId of recipientIds) {
    const userDoc = await db.collection("users").doc(recipientId).get();

    if (!userDoc.exists) continue;

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) continue;

    const senderName = message.senderName || "Someone";
    const badgeCount = await calculateBadgeCount(recipientId);

    try {
      await messaging.send({
        token: fcmToken,
        notification: {
          title: "New Message Request",
          body: `${senderName} wants to message you`,
        },
        data: {
          conversationId: conversationId,
          senderId: message.senderId,
          type: "messageRequest",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: badgeCount,
              category: "MESSAGE_REQUEST",
            },
          },
        },
      });

      console.log(`✅ Message request notification sent to ${recipientId}`);
    } catch (error) {
      console.error(`❌ Error sending request notification:`, error);
    }
  }
}

/**
 * Calculate total badge count for user
 */
async function calculateBadgeCount(userId: string): Promise<number> {
  try {
    const conversationsSnapshot = await db
      .collection("conversations")
      .where("participantIds", "array-contains", userId)
      .where("conversationStatus", "==", "accepted")
      .get();

    let totalUnread = 0;
    conversationsSnapshot.forEach((doc) => {
      const conversation = doc.data();
      const unreadCounts = conversation.unreadCounts || {};
      totalUnread += unreadCounts[userId] || 0;
    });

    return totalUnread;
  } catch (error) {
    console.error("❌ Error calculating badge count:", error);
    return 0;
  }
}

/**
 * Update badge count when conversation is updated
 */
export const updateBadgeOnConversationChange = functions.firestore
  .document("conversations/{conversationId}")
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();

      const beforeUnread = beforeData.unreadCounts || {};
      const afterUnread = afterData.unreadCounts || {};

      // Get affected users
      const affectedUserIds = new Set([
        ...Object.keys(beforeUnread),
        ...Object.keys(afterUnread),
      ]);

      for (const userId of affectedUserIds) {
        const beforeCount = beforeUnread[userId] || 0;
        const afterCount = afterUnread[userId] || 0;

        if (beforeCount !== afterCount) {
          await updateSilentBadge(userId);
        }
      }
    } catch (error) {
      console.error("❌ Error updating badge:", error);
    }
  });

/**
 * Send silent notification to update badge
 */
async function updateSilentBadge(userId: string) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) return;

    const badgeCount = await calculateBadgeCount(userId);

    await messaging.send({
      token: fcmToken,
      apns: {
        payload: {
          aps: {
            badge: badgeCount,
            contentAvailable: true,
          },
        },
      },
      data: {
        type: "badgeUpdate",
        badge: badgeCount.toString(),
      },
    });

    console.log(`🔔 Badge updated to ${badgeCount} for user ${userId}`);
  } catch (error) {
    console.error(`❌ Error updating silent badge:`, error);
  }
}
```

#### Step 4: Deploy Functions

```bash
# Deploy all functions:
firebase deploy --only functions

# Or deploy specific functions:
firebase deploy --only functions:sendMessageNotification
firebase deploy --only functions:updateBadgeOnConversationChange
```

---

### Phase 5: Testing (15 minutes)

#### Test 1: Request Permissions

```swift
// Add to your ContentView.onAppear or login flow:
Task {
    let granted = await PushNotificationManager.shared.requestNotificationPermissions()
    if granted {
        PushNotificationManager.shared.setupFCMToken()
    }
}
```

Run the app and grant permission when prompted.

#### Test 2: Verify FCM Token

Check Xcode console for:
```
🔑 FCM Token received: [long token string]
✅ FCM token saved to Firestore for user: [userId]
```

#### Test 3: Send a Message

1. Open app on **Device A** (logged in as User 1)
2. Open app on **Device B** (logged in as User 2)
3. Send message from Device A to Device B
4. **Close Device B app** (to background or force close)
5. Send another message from Device A
6. Device B should receive a push notification! 🎉

#### Test 4: Badge Count

1. Send multiple messages while app is closed
2. Open app - badge should show correct count
3. Read messages
4. Close app - badge should update to 0

#### Test 5: Notification Tap

1. Receive notification while app is closed
2. Tap notification
3. App should open directly to that conversation

---

## 🎨 Delivery Status Indicators

### Already Implemented! ✅

I've added beautiful delivery status indicators to your messages:

| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| **Sending** | 🕐 Clock | Gray | Message being sent |
| **Sent** | ✓ Single check | Gray | Delivered to server |
| **Delivered** | ✓✓ Double check | Gray | Received by recipient |
| **Read** | ✓✓ Double check | Blue | Opened by recipient |
| **Failed** | ⚠️ Exclamation | Red | Send failed |

### How It Works

The `MessageDeliveryStatus` enum in `Message.swift` calculates status based on message properties:

```swift
var deliveryStatus: MessageDeliveryStatus {
    if isSendFailed {
        return .failed
    } else if !isFromCurrentUser {
        return .delivered // Received messages are always delivered
    } else if isRead {
        return .read
    } else if isDelivered {
        return .delivered
    } else if isSent {
        return .sent
    } else {
        return .sending
    }
}
```

### Viewing Status

Open any conversation and look at your sent messages. You'll see:
- Clock icon while sending
- Single checkmark when sent
- Double checkmark when delivered
- Blue double checkmark when read

---

## 🔍 Troubleshooting

### Problem: No FCM Token
**Solution:**
1. Check that APNs key is uploaded to Firebase
2. Verify app has push notification capability
3. Run on real device (not simulator)
4. Check console for errors

### Problem: Notifications Not Received
**Solution:**
1. Verify FCM token is saved in Firestore users collection
2. Check Cloud Functions logs: `firebase functions:log`
3. Ensure recipient hasn't muted the conversation
4. Test with `PushNotificationManager.shared.scheduleTestNotification()`

### Problem: Notification Doesn't Open Conversation
**Solution:**
1. Verify `MessagingCoordinator` is properly set up
2. Check that `conversationId` is in notification data
3. Ensure conversation exists in Firestore

### Problem: Badge Count Wrong
**Solution:**
1. Check unreadCounts in conversation documents
2. Verify `updateBadgeCount()` is called after marking messages read
3. Check Cloud Function logs for badge update

### Problem: Duplicate Notifications
**Solution:**
- Check that you only have ONE Cloud Function deployed
- Run `firebase functions:list` to see active functions
- Delete duplicates: `firebase functions:delete functionName`

---

## 📊 Firebase Console Monitoring

### View Function Logs

```bash
# Real-time logs:
firebase functions:log

# Filter by function:
firebase functions:log --only sendMessageNotification
```

### Check Function Performance

1. Go to Firebase Console
2. **Functions** section
3. Click on function name
4. View:
   - Invocations
   - Execution time
   - Error rate
   - Logs

---

## 🎯 Success Checklist

- [ ] APNs key uploaded to Firebase Console
- [ ] Push notification capability added in Xcode
- [ ] Notification permission requested in app
- [ ] FCM token saved to Firestore
- [ ] Cloud Functions deployed
- [ ] Test notification received on real device
- [ ] Notification tap opens correct conversation
- [ ] Badge count updates correctly
- [ ] Message requests trigger notifications
- [ ] Delivery status indicators visible in chat
- [ ] Muted conversations don't send notifications

---

## 🚀 You're Done!

Once you complete all the steps above, your messaging system will have:

✅ **Push notifications** for new messages
✅ **Message request notifications** for non-followers
✅ **Accurate badge counts** for unread messages
✅ **Deep linking** from notifications to conversations
✅ **Beautiful delivery status** indicators
✅ **Silent badge updates** when messages are read

Your users can now receive notifications even when the app is closed! 🎉

---

## 📚 Additional Resources

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [Apple Push Notifications Guide](https://developer.apple.com/documentation/usernotifications)
- [Firebase Functions Docs](https://firebase.google.com/docs/functions)

---

## ⚡️ Quick Reference Commands

```bash
# Deploy all functions
firebase deploy --only functions

# View logs
firebase functions:log

# Test locally
firebase emulators:start

# Delete a function
firebase functions:delete functionName

# List all functions
firebase functions:list
```

---

**Need Help?** Check the troubleshooting section or Firebase Console logs!
