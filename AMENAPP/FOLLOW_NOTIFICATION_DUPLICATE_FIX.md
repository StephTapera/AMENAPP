# Follow Notification Duplicate Fix

## Problem
When a user follows someone, the followed user sees **2 duplicate notifications** instead of 1, and the follower count shows "2 people followed you" instead of "1 person followed you".

## Root Cause
There were **TWO systems** creating follow notifications:

### 1. Cloud Function (✅ Correct)
- **Location**: `functions/pushNotifications.js` line 59-131
- **Trigger**: `onDocumentCreated` on `follows/{followId}`
- **Creates notification in**: `users/{userId}/notifications/{notificationId}`
- **Uses deterministic ID**: `follow_${followerId}_${followingId}` (prevents duplicates)
- **Status**: ✅ Working correctly

### 2. Swift Code (❌ Old/Duplicate)
- **Location**: `AMENAPP/AMENAPP/FollowService.swift` line 596-619 (NOW REMOVED)
- **Function**: `createFollowNotification(userId:)`
- **Creates notification in**: Old `notifications` collection (wrong location)
- **Status**: ❌ Created duplicate notifications, NOW REMOVED

## The Fix
**Removed the duplicate `createFollowNotification` function from `FollowService.swift`**

### What was removed:
```swift
// MARK: - Notifications

private func createFollowNotification(userId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else { return }
    
    // Fetch current user's name
    let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
        .document(currentUserId)
        .getDocument()
    
    let displayName = userDoc.data()?["displayName"] as? String ?? "Someone"
    
    let notification: [String: Any] = [
        "userId": userId,
        "type": "follow",
        "fromUserId": currentUserId,
        "fromUserName": displayName,
        "message": "\(displayName) started following you",
        "createdAt": Date(),
        "isRead": false
    ]
    
    try await db.collection("notifications").addDocument(data: notification)
    
    print("✅ Follow notification created for user: \(userId)")
}
```

### Why this was wrong:
1. **Wrong collection**: Used old `notifications` collection instead of `users/{userId}/notifications` subcollection
2. **No deduplication**: Used `addDocument()` which creates random IDs instead of deterministic IDs
3. **Duplicate logic**: Cloud Function already handles this automatically

## How Notifications Work Now

### Follow Flow:
1. User A follows User B
2. `FollowService.followUser()` creates document in `follows` collection
3. Cloud Function `onUserFollow` automatically triggers
4. Cloud Function creates notification in `users/{userId}/notifications/follow_A_B`
5. NotificationService real-time listener receives update
6. User B sees exactly **1 notification**

### Unfollow Flow:
1. User A unfollows User B
2. `FollowService.unfollowUser()` deletes document from `follows` collection
3. Cloud Function `onUserUnfollow` automatically triggers
4. Cloud Function deletes notification `users/{userId}/notifications/follow_A_B`
5. Notification disappears from User B's list

## Deduplication Systems

### 1. Cloud Function Level (Primary)
- Uses deterministic ID: `follow_${followerId}_${followingId}`
- Multiple follows from same person = same notification (updated, not duplicated)
- Ensures only 1 notification exists per follower-followed pair

### 2. NotificationService Level (Client-side)
- `deduplicateNotifications()` function (line 277-304)
- Groups by `type_actorId_postId` or `type_actorId` for follows
- Keeps most recent notification per unique key
- Provides immediate UI deduplication

### 3. Background Cleanup
- `removeDuplicateFollowNotifications()` (line 308-364)
- Runs in background after detecting duplicates
- Removes old duplicate notifications from Firestore
- Keeps only the most recent per actor

## Testing Checklist
- [ ] Follow a user → See exactly 1 notification
- [ ] Follow same user multiple times quickly → Still see only 1 notification
- [ ] Unfollow user → Notification disappears
- [ ] Multiple people follow you → Each shows as separate notification
- [ ] Follower count shows correct number
- [ ] No duplicate notifications in NotificationsView

## Database Cleanup (Optional)
If users have old duplicate notifications in the wrong `notifications` collection:

```javascript
// Run this in Firebase Console to clean up old notifications
db.collection('notifications')
  .where('type', '==', 'follow')
  .get()
  .then(snapshot => {
    snapshot.forEach(doc => {
      doc.ref.delete();
      console.log('Deleted old notification:', doc.id);
    });
  });
```

## Summary
✅ **Fixed**: Removed duplicate notification creation from Swift code  
✅ **Result**: Only Cloud Function creates notifications (correct behavior)  
✅ **Benefit**: No more duplicate follow notifications  
✅ **Deduplication**: Multiple layers ensure clean notification experience

---
**Date Fixed**: 2026-02-11  
**Files Modified**: `AMENAPP/AMENAPP/FollowService.swift`  
**Cloud Functions**: No changes needed (already correct)
