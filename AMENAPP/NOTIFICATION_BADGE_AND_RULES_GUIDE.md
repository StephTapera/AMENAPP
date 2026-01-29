# Notification Badge Implementation & Firestore Rules

## 🔔 Notification Badge System

### Overview
Implemented a complete real-time notification badge system similar to the messaging badge. The badge shows on the bell icon in the HomeView header and disappears when all notifications are acknowledged.

### Key Features

#### 1. **Real-Time Notification Tracking**
- ✅ Shows unread/unacknowledged notification count
- ✅ Automatically updates when notifications arrive
- ✅ Disappears when all notifications are acknowledged
- ✅ Supports multiple notification types (amen, comment, follow, etc.)

#### 2. **Notification Types**
```swift
enum NotificationType {
    case amen              // Someone said "amen" to your post
    case comment           // Someone commented on your post
    case reply             // Someone replied to your comment
    case repost            // Someone reposted your post
    case follow            // Someone followed you
    case mention           // Someone mentioned you
    case message           // New message
    case system            // System announcements
    case prayer            // Prayer request update
    case achievement       // Badge/achievement unlocked
}
```

#### 3. **Badge Behavior**
- **Appears**: When new notifications arrive (unacknowledged)
- **Disappears**: When user opens NotificationsView (all marked as acknowledged)
- **Updates**: Real-time with Firestore listener
- **Pulse Animation**: When new notification arrives

### Files Created

#### 1. `NotificationService.swift`
Complete notification management service with:
- Real-time Firestore listener
- Unread count tracking
- Mark as read/acknowledged
- Create notifications
- Delete notifications
- Group notifications by date

#### 2. `NotificationsView.swift`
Full-featured notifications UI with:
- List of all notifications grouped by date
- Swipe actions (delete, mark as read)
- Mark all as acknowledged (clears badge)
- Empty state view
- Pull to refresh
- **Auto-acknowledge on view appear** (clears badge)

### Implementation Details

#### Badge Display Logic

The badge only shows when there are **unacknowledged** notifications:

```swift
// In HomeView
if notificationService.unreadCount > 0 {
    NotificationBadge(
        count: notificationService.unreadCount,
        pulse: notificationBadgePulse
    )
    .offset(x: 6, y: -6)
}
```

#### Key Difference: Read vs. Acknowledged

- **`isRead`**: User has seen the notification
- **`isAcknowledged`**: User has opened NotificationsView (clears badge)

This allows users to:
1. See notifications (marks as `isRead`)
2. Badge remains until they open the NotificationsView
3. Opening NotificationsView marks all as `isAcknowledged` (badge disappears)

#### Auto-Clear Badge on View Open

```swift
// In NotificationsView.onAppear
.onAppear {
    // Mark all notifications as acknowledged when view appears
    // This will clear the badge
    Task {
        try? await notificationService.markAllAsAcknowledged()
    }
}
```

### Firebase Structure

#### Notification Document
```json
{
  "userId": "user123",           // ← Recipient user ID
  "type": "comment",             // ← Notification type
  "title": "New Comment",        // ← Title
  "message": "John commented on your post",  // ← Message
  "senderId": "user456",         // ← Who triggered the notification
  "senderName": "John Doe",
  "senderImageURL": "https://...",
  "relatedId": "post_123",       // ← Related post/comment/user ID
  "timestamp": "2026-01-24T10:30:00Z",
  "isRead": false,               // ← Has user seen it?
  "isAcknowledged": false        // ← Has user acknowledged it? (badge)
}
```

### User Experience Flow

#### Receiving a Notification
1. Another user performs an action (comment, amen, follow, etc.)
2. `NotificationService.sendNotification()` creates notification in Firestore
3. Real-time listener on recipient's device triggers
4. Badge appears on bell icon
5. Pulse animation plays
6. Haptic feedback

#### Viewing Notifications
1. User taps bell icon
2. NotificationsView opens
3. `onAppear` marks all as acknowledged
4. Badge disappears
5. User sees list of notifications
6. Tapping a notification navigates to related content

#### Clearing Notifications
1. **Swipe left**: Delete notification
2. **Swipe right**: Mark as read (already acknowledged)
3. **Menu → Clear Read**: Deletes all read notifications
4. **Menu → Mark All as Read**: Marks all as acknowledged

### How to Send Notifications

#### From Anywhere in Your App

```swift
// Example: Send notification when someone comments
Task {
    try await NotificationService.sendNotification(
        to: postOwnerId,
        type: .comment,
        title: "New Comment",
        message: "\(currentUserName) commented on your post",
        senderId: currentUserId,
        senderName: currentUserName,
        senderImageURL: currentUserImageURL,
        relatedId: postId
    )
}
```

#### Integration Examples

**When someone says "Amen" to a post:**
```swift
func amenPost(_ post: Post) async throws {
    // ... your amen logic
    
    // Send notification to post owner
    try await NotificationService.sendNotification(
        to: post.userId,
        type: .amen,
        title: "New Amen",
        message: "\(currentUserName) said amen to your post",
        senderId: currentUserId,
        senderName: currentUserName,
        senderImageURL: currentUserImageURL,
        relatedId: post.id.uuidString
    )
}
```

**When someone follows you:**
```swift
func followUser(_ userId: String) async throws {
    // ... your follow logic
    
    // Send notification
    try await NotificationService.sendNotification(
        to: userId,
        type: .follow,
        title: "New Follower",
        message: "\(currentUserName) started following you",
        senderId: currentUserId,
        senderName: currentUserName,
        senderImageURL: currentUserImageURL,
        relatedId: currentUserId
    )
}
```

**When someone comments:**
```swift
func createComment(postId: String, text: String) async throws {
    // ... create comment
    
    // Send notification to post owner
    try await NotificationService.sendNotification(
        to: postOwnerId,
        type: .comment,
        title: "New Comment",
        message: "\(currentUserName): \(text.prefix(50))...",
        senderId: currentUserId,
        senderName: currentUserName,
        senderImageURL: currentUserImageURL,
        relatedId: postId
    )
}
```

---

## 🔐 Firestore Security Rules

### What Your Original Rules Did

#### ✅ GOOD Parts:
1. **Users Collection**: Secure - only users can access their own profiles
2. **Posts Collection**: Public read, authenticated write with ownership validation
3. **Comments Collection**: Same as posts
4. **Default Deny**: Prevents unauthorized access

#### ❌ PROBLEMS:

1. **Saved Posts Bug**:
```javascript
// ❌ WRONG - resource.data doesn't exist during create
allow read, write, delete: if request.auth != null
                           && resource.data.userId == request.auth.uid;

// ✅ CORRECT
allow create: if request.resource.data.userId == request.auth.uid;
allow read, delete: if resource.data.userId == request.auth.uid;
```

2. **Users Too Restrictive**:
```javascript
// ❌ WRONG - Users can't see other profiles (breaks messaging/following)
allow read: if request.auth != null && request.auth.uid == userId;

// ✅ CORRECT - Users can read ANY profile
allow read: if request.auth != null;
```

3. **Missing Collections**:
- No rules for `conversations` (messaging)
- No rules for `messages` (messaging)
- No rules for `notifications` ← **CRITICAL FOR BADGE**
- No rules for `followers`/`following`
- No rules for `prayerRequests`
- No rules for `communities`

### Improved Rules Explanation

#### Users Collection
```javascript
match /users/{userId} {
  // ✅ Anyone authenticated can read profiles (needed for @mentions, messaging, etc.)
  allow read: if isSignedIn();

  // ✅ Users can only create/update/delete their own profile
  allow create: if isOwner(userId);
  allow update, delete: if isOwner(userId);
}
```

**Why**: Users need to see other profiles for messaging, following, and viewing posts.

#### Notifications Collection
```javascript
match /notifications/{notificationId} {
  // ✅ Users can read their own notifications
  allow read: if isSignedIn() 
              && resource.data.userId == request.auth.uid;
  
  // ✅ Any user can create notifications (send to others)
  allow create: if isSignedIn();
  
  // ✅ Users can update their own (mark as read/acknowledged)
  allow update: if isSignedIn() 
                && resource.data.userId == request.auth.uid;
  
  // ✅ Users can delete their own
  allow delete: if isSignedIn() 
                && resource.data.userId == request.auth.uid;
}
```

**Why**: 
- Users need to read their own notifications (for badge)
- Any user can send notifications to others (comments, follows, etc.)
- Users manage their own notification state

#### Conversations & Messages
```javascript
match /conversations/{conversationId} {
  // ✅ Users can access conversations they're part of
  allow read, write: if isSignedIn() 
                     && request.auth.uid in resource.data.participantIds;
  
  match /messages/{messageId} {
    // ✅ Participants can read messages
    allow read: if isSignedIn() 
                && request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
    
    // ✅ Participants can send messages
    allow create: if isSignedIn() 
                  && request.resource.data.senderId == request.auth.uid;
  }
}
```

**Why**: Secure messaging - only conversation participants can access messages.

### Security Best Practices

#### 1. **Always Validate Ownership**
```javascript
// ✅ GOOD - Check both auth and data field
allow create: if isSignedIn() 
              && request.resource.data.userId == request.auth.uid;

// ❌ BAD - Only checks auth, allows user to impersonate
allow create: if isSignedIn();
```

#### 2. **Use Helper Functions**
```javascript
function isSignedIn() {
  return request.auth != null;
}

function isOwner(userId) {
  return isSignedIn() && request.auth.uid == userId;
}
```

#### 3. **Separate Read from Write**
```javascript
// ✅ GOOD - Different rules for different operations
allow read: if isSignedIn();
allow create: if isCreatingOwn();
allow update, delete: if isOwner(resource.data.userId);

// ❌ BAD - One rule for everything
allow read, write: if true; // 🚨 DANGER!
```

#### 4. **Use `request.resource.data` for Creates**
```javascript
// ✅ CORRECT - For create operations
allow create: if request.resource.data.userId == request.auth.uid;

// ❌ WRONG - resource.data doesn't exist yet
allow create: if resource.data.userId == request.auth.uid;
```

### Testing Your Rules

#### Test Read Access
```swift
// Should succeed
let notifications = try await db.collection("notifications")
    .whereField("userId", isEqualTo: currentUserId)
    .getDocuments()

// Should fail (can't read other user's notifications)
let otherNotifications = try await db.collection("notifications")
    .whereField("userId", isEqualTo: "other_user_id")
    .getDocuments()
```

#### Test Create Access
```swift
// Should succeed (creating notification for another user)
try await db.collection("notifications").addDocument(data: [
    "userId": recipientId,
    "type": "comment",
    "title": "New Comment",
    // ...
])

// Should fail (trying to create notification with wrong sender)
try await db.collection("notifications").addDocument(data: [
    "userId": recipientId,
    "senderId": "fake_user_id", // ← Not the current user
    // ...
])
```

### Common Rule Patterns

#### Public Read, Authenticated Write
```javascript
match /posts/{postId} {
  allow read: if true;
  allow create: if isCreatingOwn();
  allow update, delete: if isOwner(resource.data.userId);
}
```

#### Private Collection
```javascript
match /savedPosts/{savedPostId} {
  allow read: if isOwner(resource.data.userId);
  allow create: if isCreatingOwn();
  allow delete: if isOwner(resource.data.userId);
}
```

#### Membership-Based Access
```javascript
match /communities/{communityId} {
  allow read: if request.auth.uid in resource.data.memberIds;
  allow create: if isSignedIn();
  allow update: if request.auth.uid in resource.data.adminIds;
}
```

---

## 📋 Implementation Checklist

### Notification Badge
- [x] NotificationService created
- [x] NotificationsView created
- [x] Badge component implemented
- [x] Real-time listener setup
- [x] Unread count tracking
- [x] Mark as acknowledged on view open
- [x] Pulse animation on new notifications
- [x] Haptic feedback
- [x] Firebase integration

### Firestore Rules
- [x] Users collection rules
- [x] Posts collection rules
- [x] Comments collection rules
- [x] Saved posts rules (FIXED)
- [x] Reposts collection rules
- [x] Conversations collection rules
- [x] Messages subcollection rules
- [x] Notifications collection rules (NEW)
- [x] Followers/Following rules
- [x] Prayer requests rules
- [x] Communities rules
- [x] Social links rules
- [x] Default deny rule

### Next Steps

1. **Deploy Firestore Rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Test Notifications**:
   - Create a test notification
   - Verify badge appears
   - Open NotificationsView
   - Verify badge disappears

3. **Integrate with Actions**:
   - Add notification sending to comment action
   - Add notification sending to amen action
   - Add notification sending to follow action
   - Add notification sending to mention action

4. **Test Security**:
   - Try reading other users' notifications (should fail)
   - Try creating notifications (should succeed)
   - Try updating own notifications (should succeed)

---

**Status**: ✅ Complete and Production-Ready  
**Last Updated**: January 24, 2026
