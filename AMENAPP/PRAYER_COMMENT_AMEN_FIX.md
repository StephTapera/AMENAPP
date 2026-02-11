# Prayer Comment Amen Bug Fix

## Problem Summary
When users tapped "Amen" on a comment in the Prayer view, it would immediately un-amen instead of amening. The logs showed:
```
✅ Removed amen from comment
🙏 Toggling Amen on comment: -OkkpAld5JHeC8gfTOAI
✅ Removed amen from comment
```

This indicated that the system thought the user had **already amened** the comment when they hadn't.

## Root Cause
The issue was in `CommentService.swift`:

### Before (Broken Code)
```swift
/// Check if user has amened a comment
func hasUserAmened(commentId: String) async -> Bool {
    guard let userId = firebaseManager.currentUser?.uid else { return false }
    
    // ❌ PROBLEM: Searching through local cache to find postId
    var postId: String?
    for (pid, commentsArray) in comments {
        if commentsArray.contains(where: { $0.id == commentId }) {
            postId = pid
            break
        }
    }
    
    // ❌ Returns false if not found in cache, causing wrong behavior
    guard let postId = postId else { return false }
    
    let userLikeRef = ref.child("postInteractions").child(postId)
        .child("comments").child(commentId).child("likedBy").child(userId)
    
    let snapshot = try await userLikeRef.getData()
    return snapshot.exists()
}
```

**Why this failed:**
1. The local `comments` cache might not be populated yet when `hasUserAmened` is called
2. The cache only contains comments that have been loaded in the current session
3. When a new comment is added, it might not be in the cache immediately
4. If `postId` couldn't be found, it returned `false` even though it should check Firebase

The same issue existed in `toggleAmen()`.

## Solution
The `Comment` model already has a `postId` field! We should use it directly instead of searching through the cache.

### After (Fixed Code)

#### CommentService.swift
```swift
/// Check if user has amened a comment
/// - Parameters:
///   - commentId: The comment ID to check
///   - postId: The post ID (required since cache might not be populated yet)
func hasUserAmened(commentId: String, postId: String) async -> Bool {
    guard let userId = firebaseManager.currentUser?.uid else { return false }
    
    // ✅ FIXED: Uses postId directly from Comment model
    let userLikeRef = ref.child("postInteractions").child(postId)
        .child("comments").child(commentId).child("likedBy").child(userId)
    
    do {
        let snapshot = try await userLikeRef.getData()
        let hasLiked = snapshot.exists()
        print("✅ hasUserAmened check - commentId: \(commentId), postId: \(postId), result: \(hasLiked)")
        return hasLiked
    } catch {
        print("❌ Error checking amen status: \(error)")
        return false
    }
}

/// Toggle "Amen" (or lightbulb) on a comment
/// - Parameters:
///   - commentId: The comment ID to toggle
///   - postId: The post ID (required for direct Firebase access)
func toggleAmen(commentId: String, postId: String) async throws {
    print("🙏 Toggling Amen on comment: \(commentId) in post: \(postId)")
    
    guard let userId = firebaseManager.currentUser?.uid else {
        throw NSError(domain: "CommentService", code: -1, 
                     userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
    }
    
    // ✅ FIXED: Uses postId parameter directly
    let commentRef = ref.child("postInteractions").child(postId)
        .child("comments").child(commentId)
    let userLikeRef = commentRef.child("likedBy").child(userId)
    let likesCountRef = commentRef.child("likes")
    
    // ... rest of implementation
}
```

#### PrayerView.swift - PrayerCommentRow
```swift
/// Load initial amen state from backend
private func loadInitialState() async {
    guard let commentId = comment.id else {
        print("⚠️ Cannot load state: Missing comment ID")
        return
    }
    
    do {
        // ✅ FIXED: Passes postId from comment model
        hasPrayed = await commentService.hasUserAmened(commentId: commentId, postId: comment.postId)
        print("✅ Loaded amen state for comment \(commentId): \(hasPrayed)")
    } catch {
        print("⚠️ Failed to load amen state: \(error.localizedDescription)")
        hasPrayed = false
    }
}

/// Handle amen toggle with optimistic update and error rollback
private func handleAmenToggle() {
    guard let commentId = comment.id else {
        print("⚠️ Cannot toggle amen: Missing comment ID")
        return
    }
    
    // ... optimistic update logic ...
    
    // ✅ FIXED: Passes postId directly from comment
    let postId = comment.postId
    Task.detached(priority: .userInitiated) {
        do {
            try await commentService.toggleAmen(commentId: commentId, postId: postId)
            print("✅ Amen toggled successfully")
        } catch {
            // ... error handling ...
        }
    }
}
```

## Changes Made
1. **CommentService.swift**:
   - ✅ Updated `hasUserAmened(commentId:postId:)` to require `postId` parameter
   - ✅ Updated `toggleAmen(commentId:postId:)` to require `postId` parameter
   - ✅ Removed cache searching logic from both functions
   - ✅ Added logging to track amen state checks

2. **PrayerView.swift - PrayerCommentRow**:
   - ✅ Updated `loadInitialState()` to pass `comment.postId` to `hasUserAmened()`
   - ✅ Updated `handleAmenToggle()` to pass `comment.postId` to `toggleAmen()`
   - ✅ Added logging to confirm amen state is loaded correctly

## Benefits
- ✅ **More reliable**: No longer depends on local cache state
- ✅ **Faster**: Direct Firebase access without cache searching
- ✅ **Clearer API**: Explicit parameters make function dependencies obvious
- ✅ **Better debugging**: Added logging to track amen state
- ✅ **Production-ready**: Handles edge cases and failures gracefully

## Testing
To verify the fix works:
1. Open a prayer post with comments
2. Tap "Amen" on a comment
3. **Expected**: Comment shows amened state (filled icon, count increments)
4. **Logs should show**:
   ```
   ✅ hasUserAmened check - commentId: XXX, postId: YYY, result: false
   ✅ Loaded amen state for comment XXX: false
   🙏 Toggling Amen on comment: XXX in post: YYY
   ✅ Added amen to comment
   ✅ Amen toggled successfully
   ```

## Additional Notes
This same pattern should be applied to **all comment-related operations** that currently search through the cache. Always prefer using the data already available in the model over searching through caches.

**Other views that might have similar issues:**
- PostCard.swift (if it has comment interactions)
- TestimoniesView.swift (if it has comment interactions)
- PrivateCommunitiesView.swift (if it has comment interactions)

These should be audited and updated to follow the same pattern.
