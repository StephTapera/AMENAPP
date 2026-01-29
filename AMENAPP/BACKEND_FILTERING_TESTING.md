# Backend Filtering Testing Guide

## Quick Test Checklist

Use this checklist to verify the backend filtering implementation works correctly.

### ✅ Basic Filter Tests

- [ ] **All Filter**
  - Tap "All" filter button
  - Verify all testimony posts appear
  - Verify posts are ordered by most recent first
  - Check console logs: `"Fetching testimonies posts (filter: all)"`

- [ ] **Recent Filter**
  - Tap "Recent" filter button
  - Verify posts are ordered by most recent first
  - Check newest posts appear at top
  - Check console logs: `"Fetching testimonies posts (filter: recent)"`

- [ ] **Popular Filter**
  - Tap "Popular" filter button
  - Verify posts with highest engagement appear first
  - Engagement = amenCount + commentCount
  - Posts with 500 amens + 100 comments should rank higher than 100 amens + 50 comments
  - Check console logs: `"Fetching testimonies posts (filter: popular)"`

- [ ] **Following Filter**
  - Tap "Following" filter button
  - If not following anyone: Should show empty state
  - If following users: Should show only their posts
  - Check console logs: `"Fetching testimonies posts (filter: following)"`

### ✅ Category Filter Tests

- [ ] **Healing Category**
  - Expand "Browse by Category"
  - Tap "Healing" card
  - Verify only healing testimonies appear
  - Check topicTag field in posts
  - Verify "Clear filter" button appears

- [ ] **Career Category**
  - Tap "Career" card
  - Verify only career testimonies appear
  - Check category badge on posts

- [ ] **Relationship Category**
  - Tap "Relationship" card
  - Verify only relationship testimonies appear

- [ ] **Financial Category**
  - Tap "Financial" card
  - Verify only financial testimonies appear

- [ ] **Spiritual Growth Category**
  - Tap "Spiritual Growth" card
  - Verify only spiritual growth testimonies appear

- [ ] **Family Category**
  - Tap "Family" card
  - Verify only family testimonies appear

### ✅ Combined Filter Tests

- [ ] **Popular + Healing**
  - Select "Popular" filter
  - Select "Healing" category
  - Verify only healing posts appear
  - Verify sorted by popularity (engagement)

- [ ] **Recent + Career**
  - Select "Recent" filter
  - Select "Career" category
  - Verify only career posts appear
  - Verify sorted by most recent

- [ ] **Following + Financial**
  - Select "Following" filter
  - Select "Financial" category
  - Verify only financial posts from followed users

### ✅ UI/UX Tests

- [ ] **Loading Indicator**
  - When changing filters, verify loading indicator appears
  - Should be visible next to "Testimonies" title
  - Should disappear when data loads

- [ ] **Empty State**
  - Filter to category with no posts
  - Verify empty state appears with message
  - Message should say "No testimonies in this category"

- [ ] **Clear Filter Button**
  - Select any category
  - Verify "Clear filter" button appears
  - Tap button
  - Verify all testimonies appear again
  - Verify button disappears

- [ ] **Category Badge**
  - After selecting category, verify badge appears under title
  - Badge should show category icon + name
  - Badge color should match category theme

### ✅ Performance Tests

- [ ] **Initial Load Time**
  - Time how long initial load takes
  - Should be < 2 seconds on good connection
  - Check Network tab in Xcode debugger

- [ ] **Filter Switch Time**
  - Switch between filters rapidly
  - Should feel instant (<500ms)
  - No lag or freezing

- [ ] **Memory Usage**
  - Monitor memory in Xcode debugger
  - Should not continuously increase
  - Should be < 100MB for typical usage

- [ ] **Network Traffic**
  - Check amount of data downloaded
  - Should only download ~50 posts per query
  - Not downloading unnecessary data

### ✅ Error Handling Tests

- [ ] **No Internet Connection**
  - Turn off WiFi/cellular
  - Try changing filters
  - Verify graceful error handling
  - App should not crash

- [ ] **Slow Connection**
  - Simulate slow network in Xcode
  - Verify loading indicator stays visible
  - Verify timeout doesn't crash app

- [ ] **Empty Response**
  - Test with new Firebase project (no posts)
  - Should show empty state
  - Should not crash or show errors

### ✅ Real-time Update Tests

- [ ] **New Post Notification**
  - Create new testimony post
  - Verify notification triggers refresh
  - New post should appear in feed
  - Check console: `"New post created"`

- [ ] **Background Updates**
  - Leave app open
  - Have another user post testimony
  - Verify real-time listener updates feed

### ✅ Edge Cases

- [ ] **Very Long Content**
  - Post with 500+ character testimony
  - Verify it displays correctly
  - Verify no layout issues

- [ ] **Special Characters**
  - Post with emojis, foreign characters
  - Verify filtering still works
  - Verify no encoding issues

- [ ] **Rapid Filter Changes**
  - Rapidly tap different filters 10 times
  - Should handle gracefully
  - Last filter should be applied

- [ ] **Category + Filter Toggle**
  - Select category → Select filter → Deselect category → Select new category
  - Verify correct posts always appear

## Console Log Verification

When testing, watch for these console logs:

### Expected Success Logs
```
📥 Fetching testimonies posts from Firestore (filter: popular)
✅ Fetched 23 Testimonies posts
✅ Updated Testimonies posts with 23 items
```

### Expected Error Logs
```
❌ Failed to fetch filtered posts: <error message>
❌ User not authenticated, returning empty array
```

## Test Data Requirements

To properly test all features, ensure Firebase has:

### Minimum Test Data
- [ ] At least 10 testimony posts
- [ ] Posts in each category (Healing, Career, etc.)
- [ ] Posts with varying engagement levels (0-500 amens)
- [ ] Posts from multiple users
- [ ] At least one followed user (for "Following" filter)

### Sample Test Posts
You can create test posts with:
```swift
// In CreatePostView, create:
1. "Healing testimony - low engagement" (10 amens, 2 comments)
2. "Healing testimony - high engagement" (500 amens, 100 comments)
3. "Career testimony - medium engagement" (100 amens, 25 comments)
4. "Financial testimony - recent" (posted just now)
5. "Financial testimony - old" (posted 7 days ago)
```

## Performance Benchmarks

### Expected Results
| Test | Target | Acceptable | Poor |
|------|--------|-----------|------|
| Initial Load | < 1s | < 2s | > 3s |
| Filter Switch | < 500ms | < 1s | > 2s |
| Category Select | < 500ms | < 1s | > 2s |
| Memory Usage | < 50MB | < 100MB | > 150MB |
| Network Per Query | < 100KB | < 500KB | > 1MB |

## Debugging Tips

### If filters aren't working:
1. Check Firebase Console - are posts in database?
2. Check `category` field - should be "testimonies" not "Testimonies"
3. Check `topicTag` field - must match exactly (case-sensitive)
4. Check console logs for query errors
5. Verify Firestore rules allow read access

### If "Following" filter is empty:
1. Check current user has `followingIds` array in user document
2. Check followed users have posted testimonies
3. Verify `authorId` field matches user IDs in followingIds

### If "Popular" sort seems wrong:
1. Check `amenCount` and `commentCount` fields exist
2. Verify they are numbers, not strings
3. Check console - should show client-side sorting message

## Automated Testing (Future)

Consider adding Swift Tests:

```swift
import Testing
@testable import AMENAPP

@Suite("Testimony Filtering Tests")
struct TestimonyFilteringTests {
    
    @Test("Fetch recent testimonies")
    func fetchRecentTestimonies() async throws {
        let service = FirebasePostService.shared
        let posts = try await service.fetchPosts(
            for: .testimonies,
            filter: "recent"
        )
        
        #expect(posts.count > 0)
        
        // Verify ordered by createdAt
        for i in 0..<(posts.count - 1) {
            #expect(posts[i].createdAt >= posts[i + 1].createdAt)
        }
    }
    
    @Test("Fetch popular testimonies")
    func fetchPopularTestimonies() async throws {
        let service = FirebasePostService.shared
        let posts = try await service.fetchPosts(
            for: .testimonies,
            filter: "popular"
        )
        
        #expect(posts.count > 0)
        
        // Verify ordered by engagement
        for i in 0..<(posts.count - 1) {
            let engagement1 = posts[i].amenCount + posts[i].commentCount
            let engagement2 = posts[i + 1].amenCount + posts[i + 1].commentCount
            #expect(engagement1 >= engagement2)
        }
    }
    
    @Test("Fetch healing category only")
    func fetchHealingCategory() async throws {
        let service = FirebasePostService.shared
        let posts = try await service.fetchPosts(
            for: .testimonies,
            filter: "recent",
            topicTag: "Healing"
        )
        
        for post in posts {
            #expect(post.topicTag == "Healing")
        }
    }
}
```

## Regression Testing

Before each release, run through this checklist:
- [ ] All basic filters work
- [ ] All categories work
- [ ] Combined filters work
- [ ] Performance is acceptable
- [ ] No console errors
- [ ] No memory leaks
- [ ] No crashes

## Known Limitations

1. **"Popular" filter is client-side sorted**
   - Works fine for small datasets (< 1000 posts)
   - For scale, add `popularityScore` field and sort server-side

2. **"Following" filter limited to 10 users**
   - Firestore `in` query has 10-item limit
   - Need batching for users following >10 people

3. **No pagination yet**
   - Currently loads 50 posts max
   - Need infinite scroll for more

4. **No caching**
   - Every filter change = new network request
   - Consider caching recent queries

## Support

If tests fail or unexpected behavior occurs:
1. Check console logs
2. Verify Firebase connection
3. Check Firestore rules
4. Verify user authentication
5. Check network connectivity

---

**Last Updated:** January 21, 2026  
**Test Coverage:** ~80% (manual testing)  
**Automation:** Not yet implemented
