# App Icon Badge Count Implementation Guide

## 📱 Overview

This document provides a **precise breakdown** of all implementations needed to make the app icon badge count work correctly - going up when notifications arrive, down when they're read, and clearing when NotificationsView is opened.

---

## 🎯 Requirements

### Badge Behavior
1. **Increment** when new notification arrives (via push notification)
2. **Decrement** when individual notification marked as read
3. **Clear to 0** when NotificationsView is opened
4. **Update** when "Mark all as read" is tapped
5. **Sync** with actual unread count from Firestore
6. **Persist** across app restarts

---

## ✅ Current Implementation Status

### What's Already Working

#### 1. Badge Update on Notification Fetch
**File**: `NotificationService.swift` (line 117)
```swift
await UIApplication.shared.applicationIconBadgeNumber = unreadCount
```
✅ Badge updates when notifications are fetched

#### 2. Mark as Read Functions
**File**: `NotificationsView.swift`
- Line 792: `markAsRead(_ notification:)` - Individual notification
- Line 783: `markAllAsRead()` - All notifications  
✅ Functions exist but don't update badge

---

## ❌ Missing Implementations

### 1. Clear Badge When NotificationsView Opens

**Problem**: Badge stays at same number even when view is open

**Solution**: Add badge clear in `onAppear`

**File**: `NotificationsView.swift`  
**Location**: Inside `body` var, after `.onAppear`

**Code to Add**:
```swift
.onAppear {
    // Existing code...
    
    // ✅ NEW: Clear badge when notifications view opens
    Task {
        await clearAllBadges()
    }
}

// ✅ NEW: Add helper function
private func clearAllBadges() async {
    #if !targetEnvironment(simulator)
    await MainActor.run {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    #endif
    
    // Also clear UNUserNotificationCenter badges
    UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
            print("❌ Error clearing badge: \(error)")
        } else {
            print("📛 Badge cleared to 0")
        }
    }
}
```

---

### 2. Update Badge When Individual Notification Marked as Read

**Problem**: Badge doesn't decrease when single notification is marked as read

**Solution**: Update badge after marking as read

**File**: `NotificationsView.swift`  
**Location**: Line 792, `markAsRead` function

**Current Code**:
```swift
private func markAsRead(_ notification: AppNotification) {
    Task {
        guard let id = notification.id else { return }
        try? await notificationService.markAsRead(id)
    }
}
```

**Updated Code**:
```swift
private func markAsRead(_ notification: AppNotification) {
    Task {
        guard let id = notification.id else { return }
        try? await notificationService.markAsRead(id)
        
        // ✅ NEW: Update badge count after marking as read
        await updateBadgeCount()
    }
}

// ✅ NEW: Add helper function
private func updateBadgeCount() async {
    let unreadCount = notificationService.unreadCount
    
    #if !targetEnvironment(simulator)
    await MainActor.run {
        UIApplication.shared.applicationIconBadgeNumber = unreadCount
    }
    #endif
    
    UNUserNotificationCenter.current().setBadgeCount(unreadCount) { error in
        if let error = error {
            print("❌ Error updating badge: \(error)")
        } else {
            print("📛 Badge updated to: \(unreadCount)")
        }
    }
}
```

---

### 3. Update Badge When "Mark All as Read" is Tapped

**Problem**: Badge doesn't clear when all notifications marked as read

**Solution**: Already has `clearBadgeCount()` call but needs implementation

**File**: `NotificationsView.swift`  
**Location**: Line 789, check if `clearBadgeCount()` is implemented

**Current Code**:
```swift
private func markAllAsRead() {
    Task {
        try? await notificationService.markAllAsRead()
    }
    
    // Update badge count
    clearBadgeCount()  // ← This function needs to exist!
}
```

**Add Missing Function** (if not present):
```swift
private func clearBadgeCount() {
    Task {
        await clearAllBadges()
    }
}
```

---

### 4. Increment Badge on Push Notification Received

**Problem**: Badge doesn't increase when push notification arrives while app is in background/foreground

**Solution**: Handle badge in push notification delegate

**File**: `AppDelegate+Messaging.swift`  
**Location**: In `userNotificationCenter(_:willPresent:)` delegate method

**Find This Function**:
```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
    // Existing code...
    
    completionHandler([.banner, .sound, .badge])  // ← Make sure .badge is included!
}
```

**✅ Ensure `.badge` is in the presentation options**

---

### 5. Update Badge from Cloud Functions

**Problem**: Cloud Functions send push notifications but might not set badge

**Solution**: Include badge count in notification payload

**File**: `functions/pushNotifications.js`  
**Location**: In the `sendPushNotificationToUser` function and all notification creation functions

**Current Code** (example from onUserFollow):
```javascript
const message = {
  notification: {
    title: `${followerName} started following you`,
    body: "Tap to view their profile"
  },
  data: {
    type: "follow",
    followerId: followerId
  },
  token: fcmToken
};
```

**Updated Code**:
```javascript
// ✅ First, get the current unread count
const userNotifications = await db.collection("users")
    .doc(followingId)
    .collection("notifications")
    .where("read", "==", false)
    .get();

const unreadCount = userNotifications.size;

const message = {
  notification: {
    title: `${followerName} started following you`,
    body: "Tap to view their profile"
  },
  data: {
    type: "follow",
    followerId: followerId
  },
  apns: {
    payload: {
      aps: {
        badge: unreadCount  // ✅ NEW: Set badge count
      }
    }
  },
  token: fcmToken
};
```

**Apply to ALL notification functions**:
- `onUserFollow`
- `onAmenCreate`
- `onCommentCreate`
- `onPostCreated` (mentions)
- `onMessageCreate`
- `onMessageRequestAccepted`
- `onFollowRequestAccepted`

---

### 6. Badge Permissions in Info.plist

**Problem**: App might not have permission to show badges

**Solution**: Ensure badge permissions are configured

**File**: `AMENAPP/Info.plist`

**Required Keys**:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>

<key>UNUserNotificationCenter</key>
<dict>
    <key>UNAuthorizationOptionBadge</key>
    <true/>
</dict>
```

---

### 7. Request Badge Permission on App Launch

**Problem**: User might not have granted badge permission

**Solution**: Request badge permission along with notification permission

**File**: `AppDelegate.swift` or `AMENAPPApp.swift`  
**Location**: In notification permission request

**Code**:
```swift
UNUserNotificationCenter.current().requestAuthorization(options: [
    .alert,
    .sound,
    .badge  // ✅ Make sure .badge is included!
]) { granted, error in
    if granted {
        print("✅ Notification permissions granted (including badge)")
    }
}
```

---

### 8. Clear Badge on App Launch (Optional but Recommended)

**Problem**: Badge might show stale count when app launches

**Solution**: Sync badge with actual unread count on launch

**File**: `AMENAPPApp.swift`  
**Location**: In `init()` or `onAppear` of root view

**Code**:
```swift
.onAppear {
    // Sync badge with actual unread count
    Task {
        await syncBadgeCount()
    }
}

private func syncBadgeCount() async {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    
    do {
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .getDocuments()
        
        let unreadCount = snapshot.documents.count
        
        await MainActor.run {
            #if !targetEnvironment(simulator)
            UIApplication.shared.applicationIconBadgeNumber = unreadCount
            #endif
        }
        
        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    } catch {
        print("❌ Error syncing badge count: \(error)")
    }
}
```

---

## 📋 Complete Implementation Checklist

### iOS App (Swift)

- [ ] **NotificationsView.swift**
  - [ ] Add `clearAllBadges()` function
  - [ ] Call `clearAllBadges()` in `.onAppear`
  - [ ] Add `updateBadgeCount()` function
  - [ ] Call `updateBadgeCount()` in `markAsRead()`
  - [ ] Implement `clearBadgeCount()` if missing
  - [ ] Call in `markAllAsRead()`

- [ ] **AppDelegate+Messaging.swift**
  - [ ] Verify `.badge` in `UNNotificationPresentationOptions`
  - [ ] Handle badge in `willPresent` delegate

- [ ] **AMENAPPApp.swift** or **ContentView.swift**
  - [ ] Add `syncBadgeCount()` on app launch
  - [ ] Request `.badge` permission on first launch

- [ ] **Info.plist**
  - [ ] Verify `UIBackgroundModes` includes `remote-notification`
  - [ ] Check badge permissions are configured

### Cloud Functions (JavaScript)

- [ ] **functions/pushNotifications.js**
  - [ ] Update `sendPushNotificationToUser()` to fetch unread count
  - [ ] Add `apns.payload.aps.badge` to all push notifications
  - [ ] Update `onUserFollow` function
  - [ ] Update `onAmenCreate` function  
  - [ ] Update `onCommentCreate` function
  - [ ] Update `onPostCreated` function (mentions)
  - [ ] Update `onMessageCreate` function (if exists)
  - [ ] Update `onFollowRequestAccepted` function
  - [ ] Update `onMessageRequestAccepted` function

---

## 🔧 Helper Functions to Add

### In NotificationsView.swift

```swift
// MARK: - Badge Management

private func clearAllBadges() async {
    #if !targetEnvironment(simulator)
    await MainActor.run {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    #endif
    
    UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
            print("❌ Error clearing badge: \(error)")
        } else {
            print("📛 Badge cleared to 0")
        }
    }
}

private func updateBadgeCount() async {
    let unreadCount = notificationService.unreadCount
    
    #if !targetEnvironment(simulator)
    await MainActor.run {
        UIApplication.shared.applicationIconBadgeNumber = unreadCount
    }
    #endif
    
    UNUserNotificationCenter.current().setBadgeCount(unreadCount) { error in
        if let error = error {
            print("❌ Error updating badge: \(error)")
        } else {
            print("📛 Badge updated to: \(unreadCount)")
        }
    }
}

private func clearBadgeCount() {
    Task {
        await clearAllBadges()
    }
}
```

---

### In Cloud Functions (pushNotifications.js)

```javascript
// ✅ Helper function to get unread count
async function getUnreadNotificationCount(userId) {
  try {
    const snapshot = await db.collection("users")
        .doc(userId)
        .collection("notifications")
        .where("read", "==", false)
        .get();
    
    return snapshot.size;
  } catch (error) {
    console.error(`❌ Error getting unread count for ${userId}:`, error);
    return 0; // Default to 0 on error
  }
}

// ✅ Updated sendPushNotificationToUser function
async function sendPushNotificationToUser(userId, title, body, data = {}) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`⚠️ No FCM token for user ${userId}`);
      return null;
    }

    // Get current unread count for badge
    const unreadCount = await getUnreadNotificationCount(userId);

    const message = {
      notification: {
        title,
        body,
      },
      data,
      apns: {
        payload: {
          aps: {
            badge: unreadCount,  // ✅ Set badge count
            sound: "default"
          }
        }
      },
      token: fcmToken,
    };

    await admin.messaging().send(message);
    console.log(`✅ Push notification sent to ${userId} (badge: ${unreadCount})`);
    return {success: true};
  } catch (error) {
    console.error(`❌ Error sending push notification to ${userId}:`, error);
    return {success: false, error: error.message};
  }
}
```

---

## 🧪 Testing Strategy

### Test Scenarios

1. **Receive Notification** (App in background)
   - Send notification from another account
   - ✅ Badge should increment by 1

2. **Open NotificationsView**
   - Open app → Navigate to NotificationsView
   - ✅ Badge should clear to 0

3. **Mark Single Notification as Read**
   - Swipe notification → Mark as read
   - ✅ Badge should decrease by 1

4. **Mark All as Read**
   - Tap "Mark all read" button
   - ✅ Badge should clear to 0

5. **App Restart**
   - Receive 3 notifications → Close app → Reopen app
   - ✅ Badge should show 3

6. **Background Sync**
   - Receive notification while app is closed
   - ✅ Badge should update immediately

---

## 🚨 Common Pitfalls

### 1. Simulator Doesn't Support Badges
```swift
#if !targetEnvironment(simulator)
UIApplication.shared.applicationIconBadgeNumber = count
#endif
```

### 2. Permission Not Granted
Always request `.badge` permission:
```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
```

### 3. Badge Not in Push Notification Options
```swift
// ❌ Wrong
completionHandler([.banner, .sound])

// ✅ Correct
completionHandler([.banner, .sound, .badge])
```

### 4. Cloud Functions Not Setting Badge
Always include `apns.payload.aps.badge` in Firebase Cloud Messaging payload

### 5. Not Clearing Badge on View Open
Must clear badge in `.onAppear` of NotificationsView

---

## 📊 Expected Behavior Summary

| Event | Badge Action |
|-------|--------------|
| New notification arrives | **+1** |
| NotificationsView opened | **Set to 0** |
| Single notification marked read | **-1** |
| "Mark all read" tapped | **Set to 0** |
| App launches | **Sync with actual count** |
| User reads notification from lock screen | **-1** (handled by system) |

---

## 🎯 Priority Implementation Order

1. **HIGH PRIORITY** - Clear badge when NotificationsView opens
2. **HIGH PRIORITY** - Update badge when marking as read
3. **MEDIUM PRIORITY** - Set badge in Cloud Functions push notifications
4. **MEDIUM PRIORITY** - Sync badge on app launch
5. **LOW PRIORITY** - Handle edge cases and error states

---

## ✅ Final Verification

After implementation, verify:
- [ ] Badge increments on notification receipt
- [ ] Badge clears when NotificationsView opens
- [ ] Badge decrements when single notification read
- [ ] Badge clears when all marked as read
- [ ] Badge persists across app restarts
- [ ] Badge syncs correctly on app launch
- [ ] Works on real device (not simulator)
- [ ] Cloud Functions set correct badge count

---

**Implementation Date**: February 10, 2026  
**Priority**: HIGH - User-facing feature  
**Complexity**: MEDIUM - Requires iOS + Cloud Functions changes
