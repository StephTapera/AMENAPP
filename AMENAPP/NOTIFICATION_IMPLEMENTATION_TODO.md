# 🔔 NOTIFICATION IMPLEMENTATION GUIDE

## ✅ What's Been Created:

I've created `/repo/NotificationService.swift` with all notification functionality:
- ✅ Like notifications (amen & lightbulb)
- ✅ Comment notifications
- ✅ Repost notifications  
- ✅ Follow notifications
- ✅ Reply notifications
- ✅ Mention notifications

## 🔧 WHAT YOU NEED TO DO:

### Step 1: Add NotificationService calls to PostInteractionsService

In `PostInteractionsService.swift`, add these notification calls:

#### 1. In `toggleAmen` function (around line 230):

```swift
// After successfully adding amen (line ~228)
// Add amen
try await userAmenRef.setValue([
    "userId": currentUserId,
    "userName": currentUserName,
    "timestamp": ServerValue.timestamp()
])

// Increment count
try await ref.child("postInteractions").child(postId).child("amenCount").setValue(ServerValue.increment(1))

// 🔔 ADD THIS - Create notification
Task {
    // Get post author ID from post
    if let postAuthorId = await getPostAuthorId(postId: postId) {
        await NotificationService.shared.createLikeNotification(
            postId: postId,
            postAuthorId: postAuthorId,
            postType: "amen"
        )
    }
}

// Update user interaction index
try await syncUserInteraction(type: "amens", postId: postId, value: true)
```

#### 2. In `toggleLightbulb` function (similar location):

```swift
// After successfully adding lightbulb
// 🔔 ADD THIS - Create notification
Task {
    if let postAuthorId = await getPostAuthorId(postId: postId) {
        await NotificationService.shared.createLikeNotification(
            postId: postId,
            postAuthorId: postAuthorId,
            postType: "lightbulb"
        )
    }
}
```

#### 3. Add helper function to get post author:

Add this function to `PostInteractionsService.swift`:

```swift
/// Get post author ID from Realtime Database
private func getPostAuthorId(postId: String) async -> String? {
    do {
        let snapshot = try await ref.child("posts").child(postId).child("authorId").getData()
        return snapshot.value as? String
    } catch {
        print("❌ Failed to get post author: \(error)")
        return nil
    }
}
```

### Step 2: Add notification for comments

In your comment creation function (likely in `CommentService.swift` or wherever you create comments):

```swift
// After creating comment successfully
Task {
    await NotificationService.shared.createCommentNotification(
        postId: postId,
        postAuthorId: postAuthorId,  // You should have this from the post
        commentText: commentText
    )
}
```

### Step 3: Add notification for reposts

In your repost function:

```swift
// After creating repost successfully
Task {
    await NotificationService.shared.createRepostNotification(
        postId: postId,
        postAuthorId: postAuthorId
    )
}
```

### Step 4: Add notification for follows

In `FollowService.swift`, the notification is already being created! Look for this line (around line 169):

```swift
// Create notification for followed user
try? await createFollowNotification(userId: userId)
```

**Update it to use the new service:**

```swift
// Create notification for followed user
await NotificationService.shared.createFollowNotification(followedUserId: userId)
```

## 🎯 Quick Implementation (Copy & Paste This):

### Add to PostInteractionsService.swift (at the end of the class):

```swift
// MARK: - Helper: Get Post Author

/// Get post author ID from Realtime Database
private func getPostAuthorId(postId: String) async -> String? {
    do {
        let snapshot = try await ref.child("posts").child(postId).child("authorId").getData()
        return snapshot.value as? String
    } catch {
        print("❌ Failed to get post author: \(error)")
        return nil
    }
}
```

### Add notification calls in toggleAmen (line ~228):

```swift
// 🔔 Create notification after adding amen
Task {
    if let postAuthorId = await getPostAuthorId(postId: postId) {
        await NotificationService.shared.createLikeNotification(
            postId: postId,
            postAuthorId: postAuthorId,
            postType: "amen"
        )
    }
}
```

### Add notification calls in toggleLightbulb (similar location):

```swift
// 🔔 Create notification after adding lightbulb
Task {
    if let postAuthorId = await getPostAuthorId(postId: postId) {
        await NotificationService.shared.createLikeNotification(
            postId: postId,
            postAuthorId: postAuthorId,
            postType: "lightbulb"
        )
    }
}
```

## 📱 How to View Notifications:

You'll need a NotificationsView to display them. Here's a basic implementation:

```swift
import SwiftUI

struct NotificationsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var notifications: [AppNotification] = []
    @State private var unreadCount = 0
    
    var body: some View {
        List(notifications) { notification in
            NotificationRow(notification: notification)
                .onTapGesture {
                    Task {
                        if let id = notification.id {
                            await notificationService.markAsRead(notificationId: id)
                        }
                    }
                }
        }
        .navigationTitle("Notifications")
        .onAppear {
            Task {
                await loadNotifications()
            }
        }
    }
    
    private func loadNotifications() async {
        do {
            notifications = try await notificationService.fetchNotifications()
        } catch {
            print("Error loading notifications: \(error)")
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    
    var body: some View {
        HStack(spacing: 12) {
            Text(notification.emoji ?? "📬")
                .font(.system(size: 32))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(notification.isRead ? .secondary : .primary)
                
                Text(notification.timeAgo)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !notification.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}
```

## ✅ Testing:

1. Like/amen someone else's post → They should get a notification
2. Comment on someone else's post → They should get a notification  
3. Repost someone else's post → They should get a notification
4. Follow someone → They should get a notification

## 📊 Real-Time Notifications:

To show notifications in real-time, use the listener:

```swift
@State private var notificationListener: ListenerRegistration?

// In onAppear:
notificationListener = notificationService.listenToNotifications { newNotifications in
    self.notifications = newNotifications
    self.unreadCount = newNotifications.filter { !$0.isRead }.count
}

// In onDisappear:
notificationListener?.remove()
```

**That's it! Notifications will now be created for all interactions!** 🎉
