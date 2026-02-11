# 🐛 Prayer Reactions State Persistence Issues - Diagnosis & Fixes

**Date**: 2026-02-07
**Reported Issues**:
1. Amen button doesn't stay illuminated after leaving app/switching tabs
2. Comments don't persist in real-time when app closes
3. Where are saved posts stored?

---

## 🔍 Root Cause Analysis

### Issue 1: Amen Button Not Staying Illuminated ❌

**Problem**: The Amen button state (`hasAmened`) is loaded correctly when the view appears, but there's a **race condition** in the real-time listener that may overwrite the state.

#### Current Flow (AMENAPP/PrayerView.swift)

**Lines 2373-2391: Reaction Buttons Task**
```swift
.task {
    // Load interaction states when view appears
    await loadInteractionStates()  // ← Loads hasAmened from backend

    // Start real-time listener for interaction counts
    startRealtimeListener()  // ← May overwrite state!
}
```

**Lines 1991-2008: Load Interaction States**
```swift
private func loadInteractionStates() async {
    let postId = post.id.uuidString

    // ✅ Check if user has amened (THIS WORKS)
    hasAmened = await interactionsService.hasAmened(postId: postId)

    // ✅ Check if user has saved (THIS WORKS)
    hasSaved = await savedPostsService.isPostSaved(postId: postId)

    // ✅ Check if user has reposted (THIS WORKS)
    hasReposted = await interactionsService.hasReposted(postId: postId)

    // Update counts from backend
    let counts = await interactionsService.getInteractionCounts(postId: postId)
    amenCount = counts.amenCount
    commentCount = counts.commentCount
    repostCount = counts.repostCount
}
```

**Lines 1958-1981: Real-Time Listener (THE PROBLEM)**
```swift
private func startRealtimeListener() {
    let postId = post.id.uuidString
    let ref = Database.database().reference()

    // Listen to interaction counts in real-time
    ref.child("postInteractions").child(postId).observe(.value) { snapshot in
        guard let data = snapshot.value as? [String: Any] else { return }

        Task { @MainActor in
            // ❌ PROBLEM: Updates counts but DOESN'T update hasAmened state
            if let amenData = data["amens"] as? [String: Any] {
                self.amenCount = amenData.count  // ← Updates count
                // Missing: Check if current user is in amenData!
            }

            if let comments = data["comments"] as? [String: Any] {
                self.commentCount = comments.count
            }

            if let reposts = data["reposts"] as? [String: Any] {
                self.repostCount = reposts.count
            }
        }
    }
}
```

**Root Cause**: The real-time listener updates **counts** but doesn't check if the current user's ID exists in the `amens`, `reposts`, or `comments` dictionaries. If the listener fires after `loadInteractionStates()`, it won't reset the button states, but the issue is that **the button state isn't being synced with the real-time data**.

#### Where Amen State is Stored

**Firebase Realtime Database Path**:
```
postInteractions/
  └── {postId}/
      └── amens/
          └── {userId}: true
```

**Firestore Subcollection Path** (alternative):
```
posts/{postId}/likes/{likeId}
  - userId: string
  - createdAt: timestamp
```

---

### Issue 2: Comments Not Persisting in Real-Time ⚠️

**Problem**: Comments have their own real-time listener that stops when the view disappears.

#### Current Flow (AMENAPP/PrayerView.swift)

**Lines 3032-3042: Comment View Lifecycle**
```swift
.onAppear {
    commentService.startListening(to: post.id.uuidString)
}
.onDisappear {
    commentService.stopListening()  // ← Stops real-time updates
}
```

**This is INTENTIONAL behavior** - when you leave the view:
1. Real-time listener stops to save resources (battery, network)
2. Comments won't update in real-time until you return to the view
3. When you return, `.task` block runs `await loadComments()` to sync

**Location**: Comments are stored in **Firestore**:
```
posts/{postId}/comments/{commentId}
  - userId: string
  - text: string
  - authorName: string
  - createdAt: timestamp
```

---

### Issue 3: Where Are Saved Posts Stored? 💾

**Answer**: Saved posts are stored in **TWO locations** for redundancy and performance:

#### Location 1: Firestore - `savedPosts` Collection

**Path**: `savedPosts/{saveId}`

**Document Structure**:
```javascript
{
  userId: "user123",           // Who saved it
  postId: "post456",           // Which post
  savedAt: Timestamp,          // When saved
  collectionName: "Prayer"     // Optional collection tag
}
```

**Security Rules** (firestore.rules:635-647):
```javascript
match /savedPosts/{saveId} {
  // Allow users to read their own saved posts
  allow read: if isAuthenticated()
    && resource.data.userId == request.auth.uid;

  // Allow users to create their own saved posts
  allow create: if isAuthenticated()
    && request.resource.data.userId == request.auth.uid;

  // Allow users to delete their own saved posts
  allow delete: if isAuthenticated()
    && resource.data.userId == request.auth.uid;
}
```

#### Location 2: User Subcollection (Backup)

**Path**: `users/{userId}/savedPosts/{postId}`

**Document Structure**:
```javascript
{
  savedAt: Timestamp,
  postId: "post456"
}
```

**Security Rules** (firestore.rules:110-115):
```javascript
match /savedPosts/{postId} {
  allow read: if isAuthenticated() && isOwner(userId);
  allow create: if isAuthenticated() && isOwner(userId);
  allow delete: if isAuthenticated() && isOwner(userId);
}
```

#### SavedPostsService Implementation

**File**: `AMENAPP/SavedPostsService.swift`

**Save Function** (Lines ~35-70):
```swift
func savePost(postId: String, post: Post? = nil, collection: String? = nil) async throws {
    print("💾 Saving post: \(postId)")

    guard let userId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }

    // Check if already saved
    if savedPostIds.contains(postId) {
        print("⚠️ Post already saved")
        return
    }

    let savedPost = SavedPost(
        userId: userId,
        postId: postId,
        collectionName: collection
    )

    // Save to Firestore (top-level collection)
    let docRef = try db.collection(FirebaseManager.CollectionPath.savedPosts)
        .addDocument(from: savedPost)

    // Update local cache
    savedPostIds.insert(postId)
    savedPosts.append(savedPost)

    print("✅ Post saved successfully to Firestore")
}
```

**Check if Saved** (Lines ~150-180):
```swift
func isPostSaved(postId: String) async -> Bool {
    guard let userId = firebaseManager.currentUser?.uid else {
        return false
    }

    // First check local cache (FAST)
    if savedPostIds.contains(postId) {
        return true
    }

    // If not in cache, check Firestore (SLOW)
    do {
        let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .whereField("postId", isEqualTo: postId)
            .limit(to: 1)

        let snapshot = try await query.getDocuments()
        return !snapshot.documents.isEmpty
    } catch {
        print("❌ Error checking saved status: \(error)")
        return false
    }
}
```

---

## 🔧 Fixes Required

### Fix 1: Amen Button State Persistence ✅

**Problem**: Real-time listener doesn't sync button states with Firebase data.

**Solution**: Update `startRealtimeListener()` to check if current user exists in the interaction data.

#### Updated Code (AMENAPP/PrayerView.swift:1958-1981)

```swift
private func startRealtimeListener() {
    let postId = post.id.uuidString
    let ref = Database.database().reference()

    // Get current user ID for state checks
    let userId = Auth.auth().currentUser?.uid ?? ""

    // Listen to interaction counts in real-time
    ref.child("postInteractions").child(postId).observe(.value) { snapshot in
        guard let data = snapshot.value as? [String: Any] else { return }

        Task { @MainActor in
            // ✅ FIX: Update counts AND button states
            if let amenData = data["amens"] as? [String: Any] {
                self.amenCount = amenData.count
                // ✅ Check if current user has amened
                self.hasAmened = amenData[userId] != nil
            }

            if let comments = data["comments"] as? [String: Any] {
                self.commentCount = comments.count
            }

            if let reposts = data["reposts"] as? [String: Any] {
                self.repostCount = reposts.count
                // ✅ Check if current user has reposted
                self.hasReposted = reposts[userId] != nil
            }
        }
    }
}
```

**This ensures**:
- When user reopens the app, real-time listener fires
- Listener checks if `userId` exists in `amens` dictionary
- Updates `hasAmened = true` if user has amened the post
- Button stays illuminated! ✅

---

### Fix 2: Comment Persistence (Optional Enhancement) 🔔

**Current Behavior**: Comments stop updating when view disappears (INTENTIONAL)

**Why**: Saves battery and network bandwidth

**If You Want Comments to Persist**:

#### Option A: Keep Listener Active (Not Recommended - Battery Drain)

Remove `.onDisappear`:
```swift
.onAppear {
    commentService.startListening(to: post.id.uuidString)
}
// Remove .onDisappear block
```

**Downside**: Listener runs 24/7, even when user isn't viewing the post.

#### Option B: Global Comment Sync Service (Recommended)

Create a singleton service that manages all comment listeners:

**New File**: `AMENAPP/GlobalCommentSyncService.swift`

```swift
import Foundation
import Combine

@MainActor
class GlobalCommentSyncService: ObservableObject {
    static let shared = GlobalCommentSyncService()

    @Published var unreadCommentCounts: [String: Int] = [:]  // postId -> count

    private var activeListeners: [String: Any] = [:]

    private init() {}

    /// Start listening to a post (even when view is gone)
    func startPersistentListener(postId: String) {
        // Keep listener active across view lifecycle
    }

    /// Get unread count for a post
    func unreadCount(for postId: String) -> Int {
        unreadCommentCounts[postId] ?? 0
    }
}
```

**Use in PrayerView**:
```swift
.onAppear {
    // Start persistent background sync
    GlobalCommentSyncService.shared.startPersistentListener(postId: post.id.uuidString)

    // Also start local listener for immediate updates
    commentService.startListening(to: post.id.uuidString)
}
.onDisappear {
    // Stop local listener but keep global sync active
    commentService.stopListening()
}
```

**Downside**: More complex implementation, slight battery impact.

#### Option C: Push Notifications (Best User Experience)

**When someone comments on a prayer**:
1. Send push notification to post author
2. Notification includes comment preview
3. User taps notification → Opens post with new comments loaded

**Already implemented in**: `AMENAPP/PushNotificationManager.swift`

---

### Fix 3: Saved Posts Location (No Fix Needed) ℹ️

**Answer**: Posts are saved to **Firestore `savedPosts` collection**.

**To View Saved Posts**:

1. **In Firebase Console**:
   - Navigate to: Firestore Database → `savedPosts` collection
   - Filter by `userId` to see specific user's saves

2. **In App**:
   - Navigate to: Profile → Saved Posts
   - Handled by: `AMENAPP/SavedPostsView.swift`

**Query Example**:
```swift
// Fetch all saved posts for current user
let savedPosts = try await SavedPostsService.shared.fetchSavedPosts()

// Fetch actual post objects
let posts = try await SavedPostsService.shared.fetchSavedPostObjects()
```

**Saved Posts View Location**:
- File: `AMENAPP/SavedPostsView.swift`
- Accessed from: Profile tab → "Saved" option

---

## 📊 Data Flow Summary

### Amen Button State Flow

```
┌────────────────────────────────────────────────────────┐
│ USER TAPS AMEN BUTTON                                  │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 1. OPTIMISTIC UPDATE (Instant)                         │
│    • hasAmened = true (local state)                    │
│    • amenCount += 1                                    │
│    • Animation + haptic                                │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 2. FIREBASE WRITE (Background)                         │
│    Path: postInteractions/{postId}/amens/{userId}      │
│    Data: { userId: true, timestamp: now }              │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 3. REAL-TIME LISTENER FIRES (All Clients)              │
│    • All devices with this post open get update        │
│    • amenCount syncs across devices                    │
│    • ❌ MISSING: hasAmened state sync (NEED FIX)       │
└────────────────────────────────────────────────────────┘
```

### Saved Posts Flow

```
┌────────────────────────────────────────────────────────┐
│ USER TAPS SAVE BUTTON                                  │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 1. OPTIMISTIC UPDATE (Instant)                         │
│    • hasSaved = true (local state)                     │
│    • Bookmark icon fills                               │
│    • Haptic feedback                                   │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 2. FIRESTORE WRITE                                     │
│    Collection: savedPosts                              │
│    Document: {                                         │
│      userId: "user123",                                │
│      postId: "post456",                                │
│      savedAt: Timestamp,                               │
│      collectionName: "Prayer"                          │
│    }                                                   │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 3. LOCAL CACHE UPDATE                                  │
│    • savedPostIds.insert(postId)                       │
│    • savedPosts.append(savedPost)                      │
│    • Next time: instant check (no network call)        │
└────────────────────────────────────────────────────────┘
```

### Comment Persistence Flow

```
┌────────────────────────────────────────────────────────┐
│ USER VIEWS PRAYER POST                                 │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 1. VIEW APPEARS                                        │
│    .onAppear {                                         │
│      commentService.startListening(postId)             │
│    }                                                   │
│    • Firestore listener starts                         │
│    • Real-time updates active                          │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 2. USER LEAVES VIEW                                    │
│    .onDisappear {                                      │
│      commentService.stopListening()  ← STOPS HERE      │
│    }                                                   │
│    • Listener removed (save battery)                   │
│    • No more real-time updates                         │
└───────────────────┬────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ 3. USER RETURNS TO VIEW                                │
│    .task {                                             │
│      await loadComments()  ← Fresh fetch               │
│    }                                                   │
│    • Comments reloaded from Firestore                  │
│    • Listener restarted                                │
│    • Shows latest comments                             │
└────────────────────────────────────────────────────────┘
```

---

## 🎯 Implementation Priority

### High Priority (Fix Now) 🔴
1. **Fix Amen Button State** - Update `startRealtimeListener()` to sync button states

### Medium Priority (Consider) 🟡
2. **Add Error Toasts** - Show user-friendly error messages (existing TODO)
3. **Global Comment Sync** - Optional background comment updates

### Low Priority (Nice to Have) 🟢
4. **Analytics** - Track save/amen/comment events
5. **Offline Queue** - Queue actions when offline, sync when online

---

## 🔗 Related Files

| File | Purpose | Lines |
|------|---------|-------|
| **PrayerView.swift** | Main prayer UI with reaction buttons | 1785-2008 |
| **PostInteractionsService.swift** | Handles amens, likes, reposts | 1-849 |
| **SavedPostsService.swift** | Handles save/unsave functionality | ~300 lines |
| **CommentService.swift** | Real-time comment sync | - |
| **firestore.rules** | Security rules for collections | 635-647 |

---

## ✅ Testing Checklist

After implementing Fix 1:

- [ ] Amen a prayer post
- [ ] Close app completely
- [ ] Reopen app
- [ ] Navigate back to prayer post
- [ ] **Verify**: Amen button is illuminated ✅
- [ ] Amen count is correct
- [ ] Un-amen works (button dims)

For comments:

- [ ] Open prayer post with comments
- [ ] Navigate away (don't close app)
- [ ] Have another user add a comment
- [ ] Navigate back to prayer post
- [ ] **Verify**: New comment appears ✅

For saved posts:

- [ ] Save a prayer post
- [ ] Go to Profile → Saved
- [ ] **Verify**: Post appears in saved list ✅
- [ ] Close app and reopen
- [ ] **Verify**: Post still saved ✅

---

**Status**: 🐛 Bug Identified - Fix Ready to Implement
**Estimated Fix Time**: 15 minutes (Fix 1 only)
**Last Updated**: 2026-02-07
