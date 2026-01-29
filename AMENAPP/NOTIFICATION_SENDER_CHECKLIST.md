# Notification Sender Implementation Checklist

To complete the real-time ProfileView updates, these components need to send notifications:

## ✅ Already Implemented

### CreatePostView
- [x] Sends `.newPostCreated` notification with post object
- [x] Includes `post: Post` in userInfo
- [x] Includes `category: String` in userInfo

## ⚠️ Needs Implementation

### PostCard.swift - Delete Action

Location: In `deletePost()` function

**Add this code:**
```swift
private func deletePost() {
    guard let post = post else { return }
    
    // Delete from backend
    postsManager.deletePost(postId: post.id)
    
    // Send notification for real-time ProfileView update
    NotificationCenter.default.post(
        name: Notification.Name("postDeleted"),
        object: nil,
        userInfo: ["postId": post.id]
    )
    
    print("🗑️ Post deleted notification sent")
}
```

---

### PostCard.swift - Repost Action

Location: In `repostToProfile()` function

**Add this code:**
```swift
private func repostToProfile() {
    guard let post = post else { return }
    
    postsManager.repostToProfile(originalPost: post)
    
    // Send notification for real-time ProfileView update
    NotificationCenter.default.post(
        name: Notification.Name("postReposted"),
        object: nil,
        userInfo: ["post": post]
    )
    
    // Show confirmation
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.success)
    
    print("✅ Reposted to your profile - notification sent")
}
```

---

### SavedPostsService.swift - Save Action

Location: In `savePost()` function

**Add this code:**
```swift
func savePost(post: Post) async throws {
    guard let userId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    // Save to Firestore
    let savedPostData: [String: Any] = [
        "userId": userId,
        "postId": post.id.uuidString,
        "savedAt": Date()
    ]
    
    try await db.collection("savedPosts").addDocument(data: savedPostData)
    
    // Send notification for real-time ProfileView update
    NotificationCenter.default.post(
        name: Notification.Name("postSaved"),
        object: nil,
        userInfo: ["post": post]
    )
    
    print("🔖 Post saved - notification sent")
}
```

---

### SavedPostsService.swift - Unsave Action

Location: In `unsavePost()` function

**Add this code:**
```swift
func unsavePost(postId: UUID) async throws {
    guard let userId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    // Remove from Firestore
    let snapshot = try await db.collection("savedPosts")
        .whereField("userId", isEqualTo: userId)
        .whereField("postId", isEqualTo: postId.uuidString)
        .getDocuments()
    
    for document in snapshot.documents {
        try await document.reference.delete()
    }
    
    // Send notification for real-time ProfileView update
    NotificationCenter.default.post(
        name: Notification.Name("postUnsaved"),
        object: nil,
        userInfo: ["postId": postId]
    )
    
    print("🔖 Post unsaved - notification sent")
}
```

---

### PostCard.swift - Save Button Toggle

Location: In the save button action

**Current code probably looks like:**
```swift
Button {
    Task {
        if isSaved {
            await savedPostsService.unsavePost(postId: post.id)
        } else {
            await savedPostsService.savePost(post: post)
        }
        isSaved.toggle()
    }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
}
```

**This should work automatically** if you add notifications to SavedPostsService as shown above.

---

## Testing Steps

### 1. Test Post Creation
```
1. Create a new post
2. Check ProfileView → Posts tab
3. Verify post appears at top instantly
```

### 2. Test Post Deletion
```
1. Go to ProfileView → Posts tab
2. Open post menu (three dots)
3. Tap "Delete"
4. Verify post disappears from all tabs instantly
```

### 3. Test Repost
```
1. View someone else's post
2. Tap repost button
3. Go to ProfileView → Reposts tab
4. Verify reposted item appears at top
```

### 4. Test Save
```
1. Tap bookmark icon on any post
2. Go to ProfileView → Saved tab
3. Verify post appears at top
```

### 5. Test Unsave
```
1. Go to ProfileView → Saved tab
2. Tap bookmark icon to unsave
3. Verify post disappears instantly
```

---

## Quick Find Instructions

### Finding PostCard.swift delete function:
```bash
# Search for "deletePost" or "func deletePost"
```

### Finding PostCard.swift repost function:
```bash
# Search for "repostToProfile" or "func repostToProfile"
```

### Finding SavedPostsService.swift:
```bash
# Search for "SavedPostsService" or "class SavedPostsService"
```

---

## Expected Console Output After Implementation

### When deleting:
```
🗑️ Deleting post: 12345678-1234-1234-1234-123456789012
🗑️ Post deleted notification sent
🗑️ Post removed from profile feed: 12345678-1234-1234-1234-123456789012
```

### When reposting:
```
🔄 Reposted: Post content here
✅ Reposted to your profile - notification sent
🔄 Repost added to profile feed: 12345678-1234-1234-1234-123456789012
```

### When saving:
```
🔖 Post saved - notification sent
🔖 Saved post added to profile: 12345678-1234-1234-1234-123456789012
```

### When unsaving:
```
🔖 Post unsaved - notification sent
🔖 Post removed from saved: 12345678-1234-1234-1234-123456789012
```

---

## Summary

**ProfileView listeners:** ✅ Already implemented
**Notification senders:** ⚠️ Need to add 4 notifications

Once you add the 4 notifications to:
1. PostCard `deletePost()` ← Delete notification
2. PostCard `repostToProfile()` ← Repost notification  
3. SavedPostsService `savePost()` ← Save notification
4. SavedPostsService `unsavePost()` ← Unsave notification

Then everything will work in real-time! 🚀
