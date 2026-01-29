# Firebase Posts Implementation Checklist

Use this checklist to verify your Firestore posts implementation is working correctly.

## ✅ Firebase Console Setup

- [ ] Firestore Database created
- [ ] Security rules configured and published
- [ ] Composite indexes created (posts by category, posts by author)
- [ ] Test data seeded (optional, for development)

## ✅ Code Integration

- [ ] `FirebasePostService.swift` added to project
- [ ] `FirebaseDataSeeder.swift` added to project (optional, for dev)
- [ ] `PostsManager.swift` updated to use Firebase
- [ ] Firebase SDK packages imported (FirebaseAuth, FirebaseFirestore, FirebaseStorage)
- [ ] `FirebaseApp.configure()` called in app initialization

## ✅ Create Post Functionality

- [ ] User can create a new post
- [ ] Post appears in Firestore Console
- [ ] Post includes all required fields (authorId, content, category, etc.)
- [ ] User's `postsCount` incremented in profile
- [ ] Post appears in feed immediately
- [ ] Haptic feedback triggers on success

**Test:**
```swift
// Create a post
PostsManager.shared.createPost(
    content: "Test post",
    category: .openTable
)

// Check Firebase Console → Firestore → posts
// Verify new document exists with correct data
```

## ✅ Read/Fetch Posts

- [ ] Posts load on app launch
- [ ] Posts filtered by category correctly
- [ ] Posts sorted by date (newest first)
- [ ] Loading state shows while fetching
- [ ] Error handling works for failed fetches
- [ ] Offline mode works (cached posts shown)

**Test:**
```swift
// Clear app data, relaunch
// Check posts load from Firestore
// Turn off WiFi, verify cached posts still show
```

## ✅ Real-time Updates

- [ ] Real-time listener starts when view appears
- [ ] New posts appear automatically without refresh
- [ ] Listener stops when view disappears
- [ ] Multiple devices receive updates simultaneously
- [ ] No duplicate listeners created

**Test:**
```swift
// Open app on two devices/simulators
// Create post on Device A
// Verify it appears on Device B within 1-2 seconds
```

## ✅ Edit Post

- [ ] Edit button appears only on user's own posts
- [ ] Edit sheet opens with current content
- [ ] Updated content saves to Firestore
- [ ] `updatedAt` timestamp updated
- [ ] Changes reflect in Firebase Console
- [ ] Changes appear in feed immediately
- [ ] Authorization check prevents editing others' posts

**Test:**
```swift
// Tap "..." on your post → Edit
// Change content, save
// Check Firebase Console for updated content
// Try editing another user's post (should fail)
```

## ✅ Delete Post

- [ ] Delete button appears only on user's own posts
- [ ] Confirmation alert shows before deletion
- [ ] Post deleted from Firestore
- [ ] User's `postsCount` decremented
- [ ] Post removed from feed
- [ ] Authorization check prevents deleting others' posts

**Test:**
```swift
// Tap "..." on your post → Delete → Confirm
// Check Firebase Console (post should be gone)
// Check user's postsCount (should decrement by 1)
```

## ✅ Amen Interaction (Prayer Posts)

- [ ] Amen button works on prayer posts
- [ ] Count increments/decrements correctly
- [ ] Current user's ID added to `amenUserIds` array
- [ ] Prevents duplicate amens from same user
- [ ] Haptic feedback on interaction
- [ ] Changes sync to Firestore
- [ ] Real-time updates on other devices

**Test:**
```swift
// Tap Amen on a prayer post
// Check Firebase Console:
//   - amenCount should increment
//   - amenUserIds should include your user ID
// Tap again to remove amen
// Verify count decrements and ID removed
```

## ✅ Lightbulb Interaction (OpenTable Posts)

- [ ] Lightbulb button works on OpenTable posts
- [ ] Count increments/decrements correctly
- [ ] Current user's ID added to `lightbulbUserIds` array
- [ ] Prevents duplicate lightbulbs from same user
- [ ] Animation plays on interaction
- [ ] Haptic feedback triggers
- [ ] Changes sync to Firestore

**Test:**
```swift
// Tap lightbulb on an OpenTable post
// Check Firebase Console:
//   - lightbulbCount should increment
//   - lightbulbUserIds should include your user ID
```

## ✅ Repost Functionality

- [ ] Repost button appears on all posts
- [ ] Repost creates new post document
- [ ] New post has `isRepost: true`
- [ ] Original post ID referenced
- [ ] Original author name included
- [ ] Repost count incremented on original
- [ ] User's `postsCount` incremented
- [ ] Repost appears in feed

**Test:**
```swift
// Tap "..." → Repost to Profile
// Check Firebase Console:
//   - New post document created with isRepost: true
//   - Original post's repostCount incremented
```

## ✅ Category Filtering

- [ ] OpenTable posts filter correctly
- [ ] Testimonies posts filter correctly
- [ ] Prayer posts filter correctly
- [ ] All posts view shows all categories
- [ ] Real-time updates work per category

**Test:**
```swift
// Create posts in each category
// Navigate to each category tab
// Verify only posts of that category show
```

## ✅ Error Handling

- [ ] Network errors handled gracefully
- [ ] Permission errors show appropriate message
- [ ] Failed operations don't crash app
- [ ] Fallback to mock data if Firebase unavailable
- [ ] User feedback provided for errors

**Test:**
```swift
// Turn off WiFi
// Try to create a post
// Verify error message shows
// Turn on WiFi, verify retry works
```

## ✅ Performance

- [ ] Posts load within 2 seconds
- [ ] Scroll performance smooth with 50+ posts
- [ ] No memory leaks from listeners
- [ ] Offline persistence working
- [ ] Images load efficiently (if implemented)

**Test:**
```swift
// Seed 100+ posts
// Scroll through feed
// Check Xcode Memory Graph for leaks
// Monitor network requests
```

## ✅ Security

- [ ] Users can only edit their own posts
- [ ] Users can only delete their own posts
- [ ] Firestore rules enforce authorization
- [ ] User IDs properly validated
- [ ] No client-side security bypasses

**Test:**
```swift
// Try to edit/delete another user's post
// Should fail with permission error
// Check Firebase Console rules tab
```

## ✅ Data Integrity

- [ ] All required fields present on posts
- [ ] Timestamps use server time
- [ ] User data consistent with profile
- [ ] Counts accurate (amen, lightbulb, comments, reposts)
- [ ] No orphaned data

**Test:**
```swift
// Create post, check all fields in Firebase Console
// Delete post, verify no orphaned references
```

## ✅ User Experience

- [ ] Loading states show while data fetches
- [ ] Pull-to-refresh works
- [ ] Empty states show when no posts
- [ ] Haptic feedback on interactions
- [ ] Animations smooth
- [ ] Error messages clear and actionable

**Test:**
```swift
// Pull down to refresh feed
// Delete all posts, verify empty state
// Create post, verify success feedback
```

## ✅ Development Tools

- [ ] Firebase Seeder works
- [ ] Debug logs provide useful info
- [ ] Mock data mode can be toggled
- [ ] Firestore emulator compatible (if using)

**Test:**
```swift
#if DEBUG
// Use FirebaseSeederDebugView
// Seed sample data
// Clear all data
// Toggle between real/mock data
#endif
```

## Common Issues Checklist

If something isn't working, check:

- [ ] User is authenticated (FirebaseManager.shared.isAuthenticated)
- [ ] Firestore rules allow the operation
- [ ] Indexes are created for queries
- [ ] Real-time listener is started
- [ ] Network connection available
- [ ] Firebase SDK initialized (FirebaseApp.configure())
- [ ] Console shows detailed error logs

## Production Readiness

Before deploying to production:

- [ ] Security rules in production mode (not test mode)
- [ ] All indexes created
- [ ] Error tracking implemented (Crashlytics)
- [ ] Analytics events logged
- [ ] Offline persistence enabled
- [ ] Rate limiting considered
- [ ] Backup strategy in place
- [ ] Cost monitoring set up

## Testing Scenarios

### Scenario 1: New User First Post
```
1. New user signs up
2. Profile created in Firestore
3. User creates first post
4. Post appears in feed
5. User's postsCount = 1
```

### Scenario 2: Multi-Device Sync
```
1. Open app on Device A and Device B
2. Create post on Device A
3. Post appears on Device B within 2 seconds
4. Like post on Device B
5. Like count updates on Device A
```

### Scenario 3: Offline Mode
```
1. Load posts while online
2. Turn off network
3. Posts still visible (cached)
4. Create new post (queued)
5. Turn on network
6. Queued post syncs to Firestore
```

### Scenario 4: Error Recovery
```
1. Network connection drops mid-operation
2. Error message shows to user
3. Operation retried when connection restored
4. Data consistency maintained
```

## Sign-off

- [ ] All critical features tested
- [ ] No blockers or critical bugs
- [ ] Firebase costs reviewed
- [ ] Security rules validated
- [ ] Performance acceptable
- [ ] User feedback positive
- [ ] Documentation complete

---

**Implementation Status:** 

- Date: ________________
- Tested By: ________________
- Sign-off: ________________

**Notes:**
_________________________________
_________________________________
_________________________________

---

✅ **Checklist Complete!** Your Firebase Posts implementation is production-ready.
