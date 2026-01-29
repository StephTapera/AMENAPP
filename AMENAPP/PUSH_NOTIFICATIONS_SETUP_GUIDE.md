# Push Notifications & Cloud Functions Setup Guide

## 🚀 Complete Implementation Guide for AMENAPP

This guide walks you through setting up **push notifications** and **Cloud Functions** for your AMENAPP project.

---

## ✅ What's Been Implemented

### iOS App Components
- ✅ **PushNotificationManager.swift** - Handles FCM token management and push notifications
- ✅ **AppDelegate.swift** - Configures Firebase and notification delegates
- ✅ **NotificationSettingsView.swift** - UI for users to manage notification preferences
- ✅ **Updated NotificationService.swift** - Integrated with push notifications
- ✅ **Updated ContentView.swift** - Requests permissions on app launch

### Cloud Functions
- ✅ **onFollowCreated** - Sends push when someone follows you
- ✅ **onAmenCreated** - Sends push when someone says Amen to your post
- ✅ **onCommentCreated** - Sends push when someone comments
- ✅ **onMessageCreated** - Sends push for new messages
- ✅ **createConversation** - Callable function to create conversations
- ✅ **sendMessage** - Callable function to send messages
- ✅ **markMessagesAsRead** - Callable function to mark messages read
- ✅ **deleteMessage** - Callable function to delete messages
- ✅ **cleanupTypingIndicators** - Scheduled function to cleanup old typing data

---

## 📋 Prerequisites

1. **Xcode** - Latest version
2. **Node.js** - Version 18 or higher
3. **Firebase CLI** - Install with `npm install -g firebase-tools`
4. **Firebase Project** - Already configured
5. **Apple Developer Account** - For push notifications

---

## 🔧 Setup Steps

### Part 1: Enable Push Notifications in Xcode

#### 1.1 Add Push Notification Capability

1. Open your project in Xcode
2. Select your target (AMENAPP)
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**

#### 1.2 Add Background Modes

1. Still in **Signing & Capabilities**
2. Click **+ Capability**
3. Add **Background Modes**
4. Check the following boxes:
   - ☑️ Remote notifications
   - ☑️ Background fetch

#### 1.3 Update Info.plist

Add the following keys to your Info.plist:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

---

### Part 2: Configure Apple Push Notification Service (APNs)

#### 2.1 Create APNs Key in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Keys** in the sidebar
4. Click **+** to create a new key
5. Name it "AMENAPP Push Notifications"
6. Check **Apple Push Notifications service (APNs)**
7. Click **Continue** → **Register**
8. **Download the .p8 file** (you can only download once!)
9. Note your:
   - **Key ID** (10 characters)
   - **Team ID** (found in top-right of developer portal)

#### 2.2 Upload APNs Key to Firebase

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your AMENAPP project
3. Click **⚙️ Settings** → **Project Settings**
4. Go to **Cloud Messaging** tab
5. Scroll to **Apple app configuration**
6. Under **APNs Authentication Key**, click **Upload**
7. Upload your .p8 file
8. Enter your **Key ID** and **Team ID**
9. Click **Upload**

---

### Part 3: Install Swift Packages

#### 3.1 Add Firebase Messaging Package

If not already added:

1. In Xcode, go to **File** → **Add Package Dependencies**
2. Enter: `https://github.com/firebase/firebase-ios-sdk`
3. Select **FirebaseMessaging** library
4. Click **Add Package**

---

### Part 4: Deploy Cloud Functions

#### 4.1 Install Dependencies

Open Terminal and navigate to your project's `functions` directory:

```bash
cd /path/to/AMENAPP/functions
npm install
```

#### 4.2 Login to Firebase

```bash
firebase login
```

#### 4.3 Select Your Project

```bash
firebase use --add
```

Select your AMENAPP project from the list.

#### 4.4 Deploy Functions

```bash
firebase deploy --only functions
```

This will deploy all functions. You should see:

```
✔ functions[onFollowCreated] Successful create operation
✔ functions[onAmenCreated] Successful create operation
✔ functions[onCommentCreated] Successful create operation
✔ functions[onMessageCreated] Successful create operation
✔ functions[createConversation] Successful create operation
✔ functions[sendMessage] Successful create operation
✔ functions[markMessagesAsRead] Successful create operation
✔ functions[deleteMessage] Successful create operation
✔ functions[cleanupTypingIndicators] Successful create operation
```

---

### Part 5: Update Firestore Security Rules

Add these rules to allow Cloud Functions to create notifications:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Notifications - users can read their own, functions can write
    match /notifications/{notificationId} {
      allow read: if request.auth != null && 
                     resource.data.userId == request.auth.uid;
      allow create: if request.auth != null || 
                       request.resource.data.userId != null; // Allow functions
      allow update, delete: if request.auth != null && 
                              resource.data.userId == request.auth.uid;
    }
    
    // Users collection - allow functions to read for FCM tokens
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Conversations
    match /conversations/{conversationId} {
      allow read: if request.auth != null && 
                     request.auth.uid in resource.data.participantIds;
      allow create: if request.auth != null;
      allow update: if request.auth != null && 
                       request.auth.uid in resource.data.participantIds;
      
      // Messages subcollection
      match /messages/{messageId} {
        allow read: if request.auth != null && 
                       request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
        allow create: if request.auth != null;
        allow update, delete: if request.auth != null && 
                                 resource.data.senderId == request.auth.uid;
      }
      
      // Typing indicators subcollection
      match /typing/{userId} {
        allow read, write: if request.auth != null;
      }
    }
  }
}
```

Deploy rules:

```bash
firebase deploy --only firestore:rules
```

---

### Part 6: Test Push Notifications

#### 6.1 Build and Run App

1. Build and run the app on a **physical device** (push notifications don't work in simulator)
2. Sign in to the app
3. You should see a permission alert for notifications
4. Tap **Allow**

#### 6.2 Verify FCM Token

Check your console output in Xcode. You should see:

```
✅ Firebase configured
✅ Push notification delegates configured
📱 Registering for remote notifications...
📱 Device Token: [hex string]
🔑 FCM Token: [long string]
✅ FCM token saved to Firestore for user: [userId]
```

#### 6.3 Test Notification from App

1. Navigate to **Profile** → **Settings** → **Notifications**
2. Scroll to bottom and tap **Send Test Notification**
3. You should receive a test notification in 5 seconds

#### 6.4 Test Real Notifications

**Test Follow Notification:**
1. Have another user follow you
2. You should receive a push notification: "New Follower - [Name] started following you"

**Test Amen Notification:**
1. Have another user say Amen to your post
2. You should receive: "New Amen - [Name] said Amen to your post"

**Test Comment Notification:**
1. Have another user comment on your post
2. You should receive: "New Comment - [Name] commented: [text]"

**Test Message Notification:**
1. Have another user send you a message
2. You should receive: "[Name] - [message text]"

---

### Part 7: Add Navigation Links to Settings

Update your settings view to include notification settings:

```swift
// In your SettingsView or AccountSettingsView
Section {
    NavigationLink(destination: NotificationSettingsView()) {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
            Text("Notifications")
                .font(.custom("OpenSans-SemiBold", size: 15))
        }
    }
    
    NavigationLink(destination: PrivacySettingsView()) {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.blue)
            Text("Privacy")
                .font(.custom("OpenSans-SemiBold", size: 15))
        }
    }
}
```

---

## 🔍 Debugging

### Check Function Logs

```bash
# View all function logs
firebase functions:log

# View specific function
firebase functions:log --only onMessageCreated

# Follow logs in real-time
firebase functions:log --follow
```

### Common Issues

#### Issue: "No FCM token"
**Solution:** Make sure you:
- Enabled Push Notifications capability
- Uploaded APNs key to Firebase
- Running on physical device (not simulator)
- Granted notification permissions

#### Issue: "Permission denied" in functions
**Solution:** Update Firestore rules as shown in Part 5

#### Issue: Notifications not appearing
**Solution:** 
1. Check notification settings on device: Settings → AMENAPP → Notifications
2. Verify user has notifications enabled in-app
3. Check function logs for errors

#### Issue: Functions deployment fails
**Solution:**
1. Make sure you're on the correct Firebase project: `firebase use`
2. Check Node.js version: `node --version` (should be 18+)
3. Try: `npm install` in functions directory

---

## 📊 Monitoring & Analytics

### View Function Usage

1. Go to Firebase Console → Functions
2. See execution counts, errors, and performance

### View Notification Delivery

1. Go to Firebase Console → Cloud Messaging
2. View notification statistics

---

## 💰 Cost Estimates

### Cloud Functions Pricing

**Free Tier (Spark Plan) includes:**
- 2M invocations/month
- 400,000 GB-seconds compute time
- 200,000 CPU-seconds
- 5GB network egress

**Your estimated usage:**
- ~10,000 notifications/month
- ~5,000 messages/month
- **Total: ~15,000 invocations/month**
- **Cost: $0** (within free tier)

For production with 10,000 users:
- ~100,000 notifications/month
- ~50,000 messages/month
- **Estimated cost: ~$5-10/month**

---

## 🎉 You're Done!

Your app now has:
- ✅ Real-time push notifications
- ✅ Background notification delivery
- ✅ User notification preferences
- ✅ Cloud Functions for messaging
- ✅ Automated notification triggers
- ✅ Badge count management
- ✅ Notification sound & settings

---

## 🚀 Next Steps (Optional)

### Add Rich Notifications
- Include images in push notifications
- Add notification actions (Reply, Like, etc.)
- Implement notification categories

### Add Notification History
- Store notification history in Firestore
- Allow users to view past notifications
- Add "mark all as read" functionality

### Advanced Messaging Features
- Voice messages
- Video messages
- Message reactions
- Message forwarding
- Group messaging enhancements

---

## 📱 User Experience Flow

### First Launch:
```
App opens
  ↓
User signs in
  ↓
After 2 seconds: "AMENAPP would like to send you notifications"
  ↓
User taps "Allow"
  ↓
FCM token saved to Firestore
  ↓
User can now receive push notifications!
```

### Receiving a Notification:
```
User A says Amen to User B's post
  ↓
Cloud Function triggered (onAmenCreated)
  ↓
Function checks User B's notification preferences
  ↓
Function creates notification document in Firestore
  ↓
Function sends push notification via FCM
  ↓
User B's device receives push notification
  ↓
Notification appears on lock screen
  ↓
User B taps notification
  ↓
App opens to the post
```

---

## 🛠 Maintenance

### Regular Tasks
- Monitor function logs weekly
- Review notification delivery rates
- Update notification preferences based on user feedback
- Optimize function performance if needed

### Updates Needed When:
- Adding new notification types → Update Cloud Functions
- Changing notification format → Update both app and functions
- Adding new user preferences → Update NotificationSettingsView and functions

---

**Questions?** Check the function logs or Firebase Console for detailed error messages.

**Need help?** All functions include comprehensive logging with ✅ and ❌ emojis to track success and failures.
