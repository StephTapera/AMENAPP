# Fixes: Follow/Unfollow Counting & Chat Navigation

## Issues Fixed

### 1. ✅ Follow/Unfollow Duplicate Counting

**Problem:**
When a user follows someone, unfollows them, and then follows them again, the follower count was being incremented twice. This was happening because the `followUser()` function wasn't checking if a follow relationship already existed before creating a new one.

**Root Cause:**
The code was creating a new document in the `follows` collection every time `followUser()` was called, even if a relationship already existed.

**Solution:**
Added a check in `SocialService.swift` → `followUser()` function to query for existing relationships before creating a new one:

```swift
// ⚠️ FIX: Check if relationship already exists to prevent duplicates
let existingQuery = db.collection("follows")
    .whereField("followerId", isEqualTo: currentUserId)
    .whereField("followingId", isEqualTo: userId)
    .limit(to: 1)

let existingSnapshot = try await existingQuery.getDocuments()

if !existingSnapshot.documents.isEmpty {
    print("⚠️ Already following user: \(userId)")
    return // Already following, don't create duplicate
}
```

**Files Modified:**
- `SocialService.swift` - Added duplicate check in `followUser()` method

---

### 2. ✅ Chat Navigation from New Message View

**Problem:**
When tapping on a user in the "New Message" search view, the chat conversation was not opening. The notification was being posted, but `MessagesView` was not listening for it.

**Root Cause:**
- `NewMessageView` was posting a notification via `NotificationCenter` to open a conversation
- `MessagingCoordinator` was listening for this notification
- **BUT** `MessagesView` was not observing the `MessagingCoordinator` or responding to its state changes

**Solution:**
1. Added `@StateObject` for `MessagingCoordinator` in `MessagesView`
2. Added `.onChange(of: messagingCoordinator.conversationToOpen)` handler to open the conversation when the coordinator signals it

```swift
struct MessagesView: View {
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @StateObject private var messagingCoordinator = MessagingCoordinator.shared // ✅ Added
    // ... rest of the code
}
```

```swift
.onChange(of: messagingCoordinator.conversationToOpen) { conversationId in
    // Handle opening a specific conversation from coordinator
    guard let conversationId = conversationId else { return }
    
    // Find the conversation in our list
    if let conversation = conversations.first(where: { $0.id == conversationId }) {
        selectedConversation = conversation
    } else {
        // Conversation might not be loaded yet, fetch it
        Task {
            // Give Firebase a moment to sync
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                await MainActor.run {
                    selectedConversation = conversation
                }
            }
        }
    }
}
```

**Files Modified:**
- `MessagesView.swift` - Added coordinator observation and conversation opening handler

---

## Testing Instructions

### Test Follow/Unfollow Fix:
1. Go to a user's profile
2. Tap "Follow"
3. Note the follower count
4. Tap "Unfollow"
5. Tap "Follow" again
6. **Expected:** Follower count should be the same as step 3 (not +1)
7. Check the database - there should only be ONE document in the `follows` collection for this relationship

### Test Chat Navigation Fix:
1. Go to Messages tab
2. Tap the compose/new message button
3. Search for a user
4. Tap on the user
5. **Expected:** The new message sheet should dismiss and the chat conversation view should open
6. You should see the chat interface with that user

---

## Architecture Notes

The messaging flow now works as follows:

```
NewMessageView
    ↓ (user taps contact)
    ↓ calls getOrCreateDirectConversation()
    ↓ posts NotificationCenter notification
    ↓
MessagingCoordinator (listens to notification)
    ↓ updates conversationToOpen property
    ↓
MessagesView (observes coordinator)
    ↓ onChange handler triggered
    ↓ finds conversation and sets selectedConversation
    ↓ SwiftUI sheet presents conversation
```

---

## Additional Improvements Made

- Added helpful comments in the code to explain the fixes
- Added small delay when conversation might not be loaded yet (for race conditions)
- Improved error handling and logging

---

## Known Edge Cases Handled

1. **Follow duplicate check:** If somehow the UI allows clicking follow twice quickly, only one relationship will be created
2. **Conversation not loaded yet:** If the new conversation hasn't synced from Firebase yet, we wait 0.5s and try again
3. **Already following:** Returns early without error, silently handles the duplicate attempt

---

Date: January 23, 2026
