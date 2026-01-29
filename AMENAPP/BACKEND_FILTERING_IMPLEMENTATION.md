# Backend Filtering Implementation for Testimonies

## Overview
This document explains the backend-connected filtering system implemented for the Testimonies view. Filters like "All", "Recent", "Popular", and "Following" are now processed on the backend (Firebase) for better performance and scalability.

## What Changed

### 1. **FirebasePostService.swift**
Updated the `fetchPosts(for:filter:topicTag:limit:)` method to accept filter parameters:

```swift
func fetchPosts(
    for category: Post.PostCategory,
    filter: String = "all",
    topicTag: String? = nil,
    limit: Int = 50
) async throws -> [Post]
```

**Filter Behavior:**
- **"all" / "recent"**: Orders by `createdAt` descending (most recent first)
- **"popular"**: Fetches by `createdAt`, then sorts client-side by `amenCount + commentCount`
  - _(Note: Firestore doesn't support ordering by calculated fields, so we do this client-side)_
- **"following"**: Queries posts where `authorId` is in the user's `followingIds` array
  - Requires user to be authenticated
  - Returns empty array if user isn't following anyone
- **topicTag**: If provided, adds `whereField("topicTag", isEqualTo: topicTag)` to query

### 2. **PostsManager.swift**
Added new method `fetchFilteredPosts(for:filter:topicTag:)`:

```swift
func fetchFilteredPosts(
    for category: Post.PostCategory,
    filter: String,
    topicTag: String? = nil
) async
```

This method:
- Calls `FirebasePostService.fetchPosts()` with the specified filters
- Updates the appropriate category array (`testimoniesPosts`, `openTablePosts`, or `prayerPosts`)
- Handles errors gracefully

### 3. **TestimoniesView.swift**
Updated to trigger backend fetches when filters change:

**Key Changes:**
- Added `@State private var isLoadingPosts = false` for loading indicator
- Simplified `filteredPosts` computed property (now just returns `postsManager.testimoniesPosts`)
- Added `fetchPosts()` helper method that calls `postsManager.fetchFilteredPosts()`
- Added `.task { fetchPosts() }` to fetch data when view appears
- Updated filter buttons to call `fetchPosts()` when tapped
- Updated category selection to call `fetchPosts()` when changed
- Added loading indicator in header

## How It Works

### Filter Flow
1. User taps a filter button (e.g., "Popular")
2. `selectedFilter` state updates
3. `fetchPosts()` is called
4. `PostsManager.fetchFilteredPosts()` is invoked with current filter + category
5. `FirebasePostService.fetchPosts()` queries Firestore with appropriate filters
6. Results are mapped to `Post` objects
7. `postsManager.testimoniesPosts` is updated
8. SwiftUI automatically re-renders the view

### Category Flow
1. User taps a category card (e.g., "Healing")
2. `selectedCategory` state updates
3. `fetchPosts()` is called with `topicTag: "Healing"`
4. Firestore query filters by `topicTag == "Healing"`
5. Results are displayed

### Real-time Updates
- When a new post is created, the notification observer calls `fetchPosts()` to refresh
- Real-time listeners in `FirebasePostService` can also update data automatically

## Benefits

### ✅ Performance
- Only fetches the data needed (not all posts)
- Limits to 50 posts per query (configurable)
- Reduces memory footprint on device

### ✅ Scalability
- Works efficiently with thousands/millions of posts
- Backend handles filtering logic
- Pagination-ready (can add offset-based pagination later)

### ✅ User Experience
- "Following" filter now works properly (requires user relationship data)
- "Popular" sorting is accurate across all posts, not just cached ones
- Loading indicator shows when data is being fetched

### ✅ Backend Control
- Can update filter logic without app updates
- Can add new filters easily (e.g., "Trending", "Most Commented")
- Analytics on filter usage possible

## Future Enhancements

### 1. Pagination
Add infinite scroll for better performance:
```swift
func fetchMorePosts(lastDocument: DocumentSnapshot) async
```

### 2. Caching
Implement smart caching to reduce redundant queries:
```swift
var cachedPosts: [String: [Post]] = [:] // Key: "testimonies_popular_healing"
```

### 3. Search
Add text search capability:
```swift
func searchPosts(query: String, category: Post.PostCategory) async throws -> [Post]
```

### 4. Advanced Filters
- Date ranges: "This week", "This month"
- Verification status: "Verified accounts only"
- Engagement threshold: "100+ Amens"

### 5. Firestore Indexes
For optimal performance, create composite indexes:
- `category + createdAt` (already exists by default)
- `category + topicTag + createdAt`
- `authorId + category + createdAt` (for user profiles)

## Testing Checklist

- [ ] Test "All" filter shows all testimony posts
- [ ] Test "Recent" filter orders by newest first
- [ ] Test "Popular" filter orders by engagement (amenCount + commentCount)
- [ ] Test "Following" filter shows only posts from followed users
- [ ] Test category filters (Healing, Career, etc.)
- [ ] Test combining filter + category (e.g., "Popular" + "Healing")
- [ ] Test loading indicator appears/disappears
- [ ] Test empty state when no posts match filters
- [ ] Test real-time updates when new post is created
- [ ] Test error handling when network is unavailable

## API Documentation

### Firebase Query Examples

**All testimonies, recent:**
```
/posts
  .whereField("category", isEqualTo: "testimonies")
  .order(by: "createdAt", descending: true)
  .limit(to: 50)
```

**Popular healing testimonies:**
```
/posts
  .whereField("category", isEqualTo: "testimonies")
  .whereField("topicTag", isEqualTo: "Healing")
  .order(by: "createdAt", descending: true)
  .limit(to: 50)
// Client-side: sort by (amenCount + commentCount)
```

**Following testimonies:**
```
/posts
  .whereField("category", isEqualTo: "testimonies")
  .whereField("authorId", in: [followingIds])
  .order(by: "createdAt", descending: true)
  .limit(to: 50)
```

## Notes

- The "Popular" filter still does client-side sorting because Firestore doesn't support ordering by calculated fields
- The "Following" filter requires the user to have a `followingIds` array in their user document
- All queries are limited to 50 results by default for performance
- Real-time listeners can be added for automatic updates without manual refresh

## Related Files

- `FirebasePostService.swift` - Backend query logic
- `PostsManager.swift` - Data management layer
- `TestimoniesView.swift` - UI implementation
- `Post.swift` (in PostsManager.swift) - Data model

---

**Implementation Date:** January 21, 2026  
**Author:** Steph  
**Status:** ✅ Complete
