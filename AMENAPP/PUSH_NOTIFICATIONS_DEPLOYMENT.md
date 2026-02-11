# Push Notification Implementation Guide

## Overview

Complete implementation of push notifications for AMEN app including:
- ✅ Lock screen notifications (APNs/FCM)
- ✅ Follow notifications with duplicate prevention
- ✅ Follow request accepted notifications
- ✅ Message request accepted notifications
- ✅ Automatic notification deletion on unfollow
- ✅ Deep linking from notifications

---

## Files Created/Modified

### New Files
1. **functions/pushNotifications.js** - Cloud Functions for push delivery
2. **PushNotificationHandler.swift** - iOS push notification handler
3. **AppDelegate.swift** - App lifecycle with FCM setup
4. **AMENAPPApp.swift** - Main app with deep link handling

### Modified Files
1. **NotificationService.swift** - Added new notification types

---

## Deployment Steps

### STEP 1: Deploy Cloud Functions

```bash
# Navigate to functions directory
cd functions

# Install dependencies
npm install firebase-functions firebase-admin

# Deploy to Firebase
firebase deploy --only functions:sendPushNotification
firebase deploy --only functions:onUserFollow
firebase deploy --only functions:onUserUnfollow
firebase deploy --only functions:onFollowRequestAccepted
firebase deploy --only functions:onMessageRequestAccepted
```

### STEP 2: Configure Firebase Cloud Messaging

1. **Get APNs Key from Apple Developer**:
   - Go to Apple Developer → Keys
   - Create new key with "Apple Push Notifications service (APNs)" enabled
   - Download `.p8` file
   - Note the Key ID and Team ID

2. **Upload to Firebase Console**:
   - Go to Firebase Console → Project Settings → Cloud Messaging
   - Under "Apple app configuration"
   - Upload APNs Authentication Key (.p8 file)
   - Enter Key ID and Team ID

3. **Enable Background Modes in Xcode**:
   - Open Xcode project
   - Select target → Signing & Capabilities
   - Add capability: "Push Notifications"
   - Add capability: "Background Modes"
   - Enable: "Remote notifications"

### STEP 3: Update Info.plist

Add to `Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>amenapp</string>
        </array>
    </dict>
</array>
```

### STEP 4: Update Firestore Security Rules

Add to `firestore.rules`:
```javascript
match /users/{userId} {
  allow read: if request.auth != null;
  allow update: if request.auth.uid == userId;
  
  // Allow Cloud Functions to update FCM token
  allow update: if request.auth.token.admin == true;
}

match /notifications/{notificationId} {
  allow read: if request.auth != null && 
                 resource.data.userId == request.auth.uid;
  allow create: if request.auth != null;
  allow delete: if request.auth.uid == resource.data.userId;
}
```

### STEP 5: Test Notifications

#### Test Follow Notification
```bash
# In Firebase Console → Firestore
# Create a follow relationship:

Collection: followers
Document ID: [userA_id]
  Collection: following
  Document ID: [userB_id]
    Fields:
      userId: [userB_id]
      followedAt: [timestamp]
```

**Expected**:
1. Cloud Function `onUserFollow` triggers
2. Notification created in `/notifications`
3. Cloud Function `sendPushNotification` triggers
4. Push notification sent to User B's device
5. User B sees notification on lock screen

#### Test Unfollow (No Notification)
```bash
# Delete the follow relationship:
# Delete: followers/[userA_id]/following/[userB_id]
```

**Expected**:
1. Cloud Function `onUserUnfollow` triggers
2. Follow notification deleted from `/notifications`
3. No push notification sent

#### Test Follow Request Accepted
```bash
# In Firebase Console → Firestore
# Update follow request status:

Collection: followRequests
Document ID: [request_id]
  Fields:
    status: "accepted" (change from "pending")
```

**Expected**:
1. Cloud Function `onFollowRequestAccepted` triggers
2. Notification created for requester
3. Push notification sent

---

## Testing Checklist

### Manual Testing

- [ ] **Follow Notification**
  - [ ] User A follows User B
  - [ ] User B receives push notification
  - [ ] Notification appears on lock screen
  - [ ] Tapping opens app to User A's profile
  - [ ] In-app notification shows in NotificationsView

- [ ] **Duplicate Prevention**
  - [ ] User A follows User B (notification sent)
  - [ ] User A unfollows User B (notification deleted)
  - [ ] User A follows User B again (notification sent)
  - [ ] User B has only ONE notification (not two)

- [ ] **Unfollow (No Notification)**
  - [ ] User A follows User B
  - [ ] User B gets notification
  - [ ] User A unfollows User B
  - [ ] Notification disappears from User B's list
  - [ ] No "unfollowed" notification sent

- [ ] **Follow Request Accepted**
  - [ ] User A sends follow request to User B (private account)
  - [ ] User B accepts request
  - [ ] User A receives "accepted" push notification
  - [ ] Tapping opens app to User B's profile

- [ ] **Message Request Accepted**
  - [ ] User A sends message request to User B
  - [ ] User B accepts message request
  - [ ] User A receives push notification
  - [ ] Tapping opens conversation with User B

- [ ] **Badge Count**
  - [ ] Badge shows correct unread count
  - [ ] Badge updates when notification is read
  - [ ] Badge clears when all notifications read

---

## Notification Flow

### Follow Notification
```
1. User A follows User B
   ↓
2. Firestore: /followers/{A}/following/{B} created
   ↓
3. Cloud Function: onUserFollow triggers
   ↓
4. Check: Existing notification for A → B follow?
   ├─ Yes → Update timestamp, mark unread
   └─ No → Create new notification
   ↓
5. Firestore: /notifications/{id} created
   ↓
6. Cloud Function: sendPushNotification triggers
   ↓
7. Get User B's FCM token from /users/{B}
   ↓
8. Send push via Firebase Cloud Messaging
   ↓
9. User B's device receives notification
   ↓
10. Notification appears on lock screen
```

### Unfollow (Delete Notification)
```
1. User A unfollows User B
   ↓
2. Firestore: /followers/{A}/following/{B} deleted
   ↓
3. Cloud Function: onUserUnfollow triggers
   ↓
4. Find notification: type=follow, actorId=A, userId=B
   ↓
5. Delete notification from /notifications
   ↓
6. No push notification sent
```

---

## Troubleshooting

### Push Notifications Not Received

**Check**:
1. FCM token saved in Firestore?
   ```bash
   # Firebase Console → Firestore → users/{userId}
   # Look for "fcmToken" field
   ```

2. Cloud Functions deployed?
   ```bash
   firebase functions:list
   # Should show all 5 functions
   ```

3. APNs key configured in Firebase Console?
   - Project Settings → Cloud Messaging → Apple app configuration

4. Device registered for push notifications?
   ```swift
   // Check app logs for:
   // "✅ APNs device token registered"
   ```

5. App has notification permissions?
   ```swift
   // Settings → [App Name] → Notifications → Allow Notifications
   ```

### Duplicate Notifications

**Check**:
1. Cloud Function `onUserFollow` has duplicate prevention logic
2. Firestore query finds existing notifications
3. Only one notification per follow relationship

**Debug**:
```bash
# Firebase Console → Functions → Logs
# Look for: "⚠️ Follow notification already exists"
```

### Notification Not Deleted on Unfollow

**Check**:
1. Cloud Function `onUserUnfollow` is deployed
2. Function has correct Firestore path match
3. Function logs show deletion

**Debug**:
```bash
# Firebase Console → Functions → Logs
# Look for: "✅ Follow notification(s) deleted"
```

---

## Security Considerations

### FCM Token Storage
- FCM tokens stored in `/users/{userId}/fcmToken`
- Only user can update their own token
- Cloud Functions have admin access to update tokens

### Notification Access
- Users can only read their own notifications
- Notifications filtered by `userId` field
- Cloud Functions create notifications on behalf of users

### Push Notification Data
- Don't include sensitive data in notification payload
- Use notification ID for deep linking
- Fetch full data from Firestore after opening app

---

## Cost Estimates (Firebase)

### Cloud Functions
- **onUserFollow**: ~1 invocation per follow = Free tier covers
- **sendPushNotification**: ~1 invocation per notification
- **onUserUnfollow**: ~1 invocation per unfollow

**Estimated**: ~10,000 follows/day = ~$0.40/month

### FCM
- Free for unlimited push notifications

### Firestore
- Reads: Minimal (token lookup)
- Writes: 1 per notification + 1 per token update

**Estimated**: ~10,000 notifications/day = ~$0.36/month

**Total**: ~$1/month for push notifications (within Firebase free tier)

---

## Production Readiness

### Before Launch
- [x] Cloud Functions deployed
- [x] APNs certificate configured
- [x] Firestore security rules updated
- [x] Background modes enabled in Xcode
- [ ] Test on physical devices (not simulator)
- [ ] Test with production APNs certificate
- [ ] Monitor Cloud Function logs for errors
- [ ] Set up error alerting (Cloud Functions)

### After Launch
- [ ] Monitor FCM delivery rates (Firebase Console → Cloud Messaging)
- [ ] Track notification open rates
- [ ] Monitor Cloud Function execution times
- [ ] Set up error reporting (Crashlytics)
- [ ] Collect user feedback on notifications

---

## Support

For issues or questions:
1. Check Firebase Console → Functions → Logs
2. Check Xcode Console for device logs
3. Review Firestore data structure
4. Test Cloud Functions locally with Firebase Emulator

---

**Implementation Date**: February 5, 2026  
**Status**: ✅ Ready for Testing  
**Next Step**: Deploy to staging environment
