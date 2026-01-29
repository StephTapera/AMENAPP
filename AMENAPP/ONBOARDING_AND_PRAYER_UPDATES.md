# Onboarding & Prayer View Backend Integration

## Changes Made - January 21, 2026

### 1. Personalized Onboarding Welcome Screen ✅

**File:** `OnboardingOnboardingView.swift`

**Change:** Updated `WelcomePage` to personalize the welcome message with the user's display name.

**Before:**
```swift
Text("Welcome to AMEN")
    .font(.custom("OpenSans-Bold", size: 36))
    .foregroundStyle(.white)
```

**After:**
```swift
@StateObject private var userService = UserService()

// In body:
if let user = userService.currentUser {
    Text("Welcome, \(user.displayName)!")
        .font(.custom("OpenSans-Bold", size: 36))
        .foregroundStyle(.white)
} else {
    Text("Welcome to AMEN")
        .font(.custom("OpenSans-Bold", size: 36))
        .foregroundStyle(.white)
}
```

**What it does:**
- Fetches the current user's data from Firestore on page load
- Displays personalized welcome message: "Welcome, [Display Name]!"
- Falls back to generic welcome if user data isn't loaded yet

---

### 2. Prayer View Backend Integration ✅

**File:** `PrayerView.swift`

**Changes Made:**

#### A. Removed Fake Interaction Counts

**Before:**
```swift
@State private var amenCount = Int.random(in: 5...150)
@State private var commentCount = Int.random(in: 1...25)
@State private var repostCount = Int.random(in: 1...15)
```

**After:**
```swift
@State private var amenCount: Int
@State private var commentCount: Int
@State private var repostCount: Int

init(post: FirestorePost, onAuthorTap: (() -> Void)? = nil) {
    self.post = post
    self.onAuthorTap = onAuthorTap
    // Initialize with real counts from backend
    _amenCount = State(initialValue: post.amenCount)
    _commentCount = State(initialValue: post.commentCount)
    _repostCount = State(initialValue: post.repostCount)
}
```

#### B. Updated to Use FirestorePost Model

**Before:**
```swift
struct PrayerPostCard: View {
    let authorName: String
    let timeAgo: String
    let content: String
    let category: PrayerCategory
    let topicTag: String?
    // ...
}
```

**After:**
```swift
struct PrayerPostCard: View {
    let post: FirestorePost  // Use actual post data
    // Computed properties for backward compatibility
    private var authorName: String { post.authorName }
    private var timeAgo: String { post.timeAgo }
    private var content: String { post.content }
    // ...
}
```

#### C. Simplified Prayer Post Display

**Before:**
```swift
ForEach(filteredPrayerPosts) { post in
    PrayerPostCard(
        authorName: post.authorName,
        timeAgo: post.timeAgo,
        content: post.content,
        category: prayerCategoryFrom(topicTag: post.topicTag ?? ""),
        topicTag: post.topicTag
    )
}
```

**After:**
```swift
ForEach(filteredPrayerPosts) { post in
    PrayerPostCard(post: post)
}
```

#### D. Added timeAgo Computed Property to FirestorePost

**File:** `FirebasePostService.swift`

```swift
// Computed property for "time ago" display
var timeAgo: String {
    createdAt.timeAgoDisplay()
}
```

This uses the existing `timeAgoDisplay()` extension on `Date` to convert timestamps to human-readable formats (e.g., "2h", "1d", "3w").

---

### 3. Testimonies View Status ✅

**File:** `TestimoniesView.swift`

**Status:** Already properly hooked up to backend!

The testimonies view was already using real backend data with proper initialization:

```swift
init(post: Post, onDelete: @escaping () -> Void, onEdit: @escaping () -> Void, onRepost: @escaping () -> Void) {
    self.post = post
    self.onDelete = onDelete
    self.onEdit = onEdit
    self.onRepost = onRepost
    _amenCount = State(initialValue: post.amenCount)
    _commentCount = State(initialValue: post.commentCount)
    _repostCount = State(initialValue: post.repostCount)
    _hasReposted = State(initialValue: post.isRepost)
}
```

**No changes needed!** ✨

---

## Backend Integration Summary

### What's Now Connected:

1. **Onboarding Welcome Screen**
   - ✅ Fetches user data from Firestore
   - ✅ Displays personalized welcome with display name
   - ✅ Graceful fallback if data not loaded

2. **Prayer View Posts**
   - ✅ Real amen counts from Firestore
   - ✅ Real comment counts from Firestore
   - ✅ Real repost counts from Firestore
   - ✅ Actual post data (author, content, timestamps)
   - ✅ Dynamic "time ago" calculation from createdAt

3. **Testimonies View Posts**
   - ✅ Already using real backend data
   - ✅ All interaction counts from Firestore

---

## What Still Needs Backend Connection:

Based on earlier analysis, here are the main areas still needing backend integration:

1. **Like/Amen Functionality**
   - Need to implement actual like/amen toggle that updates Firestore
   - Need to track `amenUserIds` array
   - Need to check if current user has already amened

2. **Bookmark/Save Posts**
   - Create `BookmarkService` 
   - Implement save/unsave functionality
   - Track saved posts per user

3. **Repost Functionality**
   - `RepostService` exists but needs full integration
   - Implement actual repost creation in Firestore
   - Update repost counts on original posts

4. **Comments**
   - `CommentService` exists
   - Need to fully integrate comment creation/display
   - Hook up comment count updates

5. **Follow/Unfollow Users**
   - Implement follow toggle on prayer/testimony posts
   - Update follower/following counts
   - Use `SocialService` for backend calls

6. **Notifications**
   - Set up push notifications
   - Create in-app notification feed
   - Implement notification preferences

---

## Testing Recommendations

1. **Test Onboarding Flow:**
   - Sign up new user
   - Verify display name shows on welcome screen
   - Check that onboarding data saves to Firestore

2. **Test Prayer View:**
   - Create prayer requests
   - Verify counts show real Firestore data (should be 0 for new posts)
   - Check that post updates reflect in real-time

3. **Test Testimonies:**
   - Already working, but verify counts are accurate
   - Test post creation and updates

---

## Next Steps

1. Implement like/amen backend functionality
2. Create bookmark/save service
3. Complete repost integration
4. Hook up comment display and creation
5. Implement follow/unfollow on post cards
6. Set up push notifications

---

**Updated:** January 21, 2026
**Files Modified:** 
- OnboardingOnboardingView.swift
- PrayerView.swift
- FirebasePostService.swift
