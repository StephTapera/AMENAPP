# Phase 1: Critical Implementation - Integration Guide

## 📋 Overview

This guide walks you through integrating all Phase 1 components into your AMENAPP messaging system.

---

## ✅ Files Created

1. **MessageModels.swift** - Message data models
2. **FirebaseMessagingService+RequestsAndBlocking.swift** - Blocking and follow status
3. **PushNotificationManager.swift** - FCM token and push notifications
4. **AppDelegate+Messaging.swift** - AppDelegate integration guide
5. **firebase-functions/index.js** - Cloud Functions (backend)

---

## 🚀 Step-by-Step Integration

### Step 1: Add Files to Xcode Project

1. Open your Xcode project
2. Drag and drop these files into your project:
   - `MessageModels.swift`
   - `FirebaseMessagingService+RequestsAndBlocking.swift`
   - `PushNotificationManager.swift`
3. Ensure they're added to your app target

---

### Step 2: Update AppDelegate

**Option A: If you already have an AppDelegate**

Add this to your existing `AppDelegate.swift`:

```swift
import FirebaseMessaging
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // ⚠️ CRITICAL: Configure Firestore IMMEDIATELY after FirebaseApp.configure()
        setupFirestore()
        
        // Setup messaging
        setupMessaging()
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        return true
    }
    
    func setupFirestore() {
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
        print("✅ Firestore configured with offline persistence")
    }
    
    func setupMessaging() {
        UNUserNotificationCenter.current().delegate = self
        PushNotificationManager.shared.configure()
        print("✅ Push notifications configured")
    }
    
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register: \(error)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let conversationId = userInfo["conversationId"] as? String {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenConversation"),
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
        completionHandler()
    }
}
```

**Option B: Create new AppDelegate**

Use the template in `AppDelegate+Messaging.swift`

Then add to your `@main` App file:

```swift
@main
struct AMENAPPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

### Step 3: Update Info.plist

Add these keys to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

---

### Step 4: Enable Push Notifications in Xcode

1. Select your project in Xcode
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **Push Notifications**
5. Add **Background Modes** and enable **Remote notifications**

---

### Step 5: Configure Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Cloud Messaging**
4. Upload your APNs authentication key or certificate

---

### Step 6: Deploy Cloud Functions

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize functions (if not already done)
firebase init functions

# Copy the cloud functions file
cp firebase-functions/index.js functions/index.js

# Install dependencies
cd functions
npm install firebase-admin firebase-functions

# Deploy
firebase deploy --only functions
```

---

### Step 7: Update FirebaseMessagingService

The extension file adds these methods to `FirebaseMessagingService`:

**Blocking:**
- `checkIfBlocked(userId:)` → Bool
- `checkIfBlockedByUser(userId:)` → Bool
- `blockUser(userId:)` → Void
- `unblockUser(userId:)` → Void
- `getBlockedUsers()` → [String]

**Follow Status:**
- `checkFollowStatus(userId1:, userId2:)` → (Bool, Bool)
- `checkIfFollowing(userId:)` → Bool
- `checkIfFollowedBy(userId:)` → Bool

**Message Requests:**
- `fetchMessageRequests()` → [MessagingRequest]
- `markMessageRequestAsRead(conversationId:)` → Void
- `getUnreadMessageRequestCount()` → Int

**Privacy:**
- `fetchPrivacySettings(userId:)` → UserPrivacySettings
- `updatePrivacySettings(settings:)` → Void
- `validateConversationCreation(with:)` → (Bool, String?)

---

### Step 8: Test Integration

Run these tests in order:

#### Test 1: FCM Token
```swift
// In your login flow
Task {
    await PushNotificationManager.shared.fetchFCMToken()
    print("FCM Token: \(PushNotificationManager.shared.fcmToken ?? "nil")")
}
```

#### Test 2: Blocking
```swift
let service = FirebaseMessagingService.shared

// Block a user
try await service.blockUser(userId: "testUserId")

// Check if blocked
let isBlocked = try await service.checkIfBlocked(userId: "testUserId")
print("Is blocked: \(isBlocked)") // Should print: true

// Unblock
try await service.unblockUser(userId: "testUserId")
```

#### Test 3: Message Request
```swift
// Fetch message requests
let requests = try await service.fetchMessageRequests()
print("Pending requests: \(requests.count)")

// Accept a request
try await service.acceptMessageRequest(conversationId: "requestId")
```

#### Test 4: Push Notification
```swift
// Send a test notification
try await PushNotificationManager.shared.queuePushNotification(
    to: "recipientUserId",
    title: "Test",
    body: "This is a test notification",
    conversationId: "testConvId",
    type: .message
)
```

---

## 🔧 Firestore Database Structure

### Users Collection Enhancement

Add these fields to user documents:

```json
{
  "fcmToken": "string",
  "fcmTokenUpdatedAt": "timestamp",
  "allowMessagesFromEveryone": true,
  "requireFollowToMessage": false,
  "autoDeclineSpam": false,
  "isOnline": false,
  "lastSeen": "timestamp"
}
```

### Conversations Collection Enhancement

Add these fields:

```json
{
  "messageCount": {
    "userId1": 5,
    "userId2": 3
  }
}
```

---

## 📱 Handle Notification Taps

In your root SwiftUI view:

```swift
struct ContentView: View {
    @State private var selectedConversationId: String?
    
    var body: some View {
        TabView {
            MessagesView(selectedConversationId: $selectedConversationId)
                .tabItem { Label("Messages", systemImage: "message") }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenConversation"))) { notification in
            if let conversationId = notification.userInfo?["conversationId"] as? String {
                selectedConversationId = conversationId
            }
        }
    }
}
```

---

## 🐛 Troubleshooting

### Issue: No FCM token received
**Solution:** 
- Check if push notifications permission is granted
- Verify APNs certificate in Firebase Console
- Check device can receive notifications (not simulator for production)

### Issue: Firestore offline persistence error
**Solution:**
- Ensure `setupFirestore()` is called IMMEDIATELY after `FirebaseApp.configure()`
- Only call it once

### Issue: Cloud Functions not triggering
**Solution:**
- Check Firebase Console > Functions for errors
- Verify billing is enabled (required for Cloud Functions)
- Check function logs: `firebase functions:log`

### Issue: Block check fails
**Solution:**
- Verify Firestore rules allow reading `blockedUsers` collection
- Check user is authenticated

---

## 📊 Monitoring

### Check Cloud Function Logs
```bash
firebase functions:log
```

### Monitor FCM Queue
Check Firestore Console → `fcmQueue` collection for:
- `status: "pending"` - Waiting to send
- `status: "sent"` - Successfully sent
- `status: "failed"` - Failed (check error field)

---

## 🎯 Next Steps

After Phase 1 is working:

1. ✅ Test all blocking flows
2. ✅ Test message requests
3. ✅ Verify push notifications
4. ✅ Check offline support
5. Move to **Phase 2: Essential Features**

---

## 📞 Support

If you encounter issues:

1. Check console logs for error messages
2. Verify all Firebase services are enabled
3. Ensure Firestore rules match the provided rules
4. Test with debug logging enabled

---

## ✅ Completion Checklist

- [ ] All 5 files added to Xcode project
- [ ] AppDelegate updated with messaging setup
- [ ] Info.plist configured
- [ ] Push Notifications capability enabled
- [ ] Firebase Console APNs configured
- [ ] Cloud Functions deployed
- [ ] FCM token successfully retrieved
- [ ] Block/unblock tested
- [ ] Message requests tested
- [ ] Push notifications received
- [ ] Notification tap navigation working

**Once all checked, Phase 1 is complete! 🎉**
