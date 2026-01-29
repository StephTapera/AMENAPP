# Search Backend Setup Guide 🔍

## Overview

Your SearchView is NOW hooked up to a **real Firebase backend**! 

The new `SearchService.swift` provides full search functionality for:
- ✅ **People** (users)
- ✅ **Communities** (groups)
- ✅ **Posts**
- ✅ **Events**

---

## What's Changed

### Before (Mock Data) ❌
```swift
private func performSearch(query: String) {
    // Simulate search delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        searchResults = generateMockResults(for: query) // Hardcoded data
    }
}
```

### After (Real Backend) ✅
```swift
private func performSearch(query: String) {
    Task {
        do {
            // Real Firebase search!
            searchResults = try await searchService.search(query: query, filter: selectedFilter)
        } catch {
            print("❌ Search error: \(error.localizedDescription)")
        }
    }
}
```

---

## Features Implemented

### 1. **Multi-Category Search**
Search across all categories or filter by:
- People (users)
- Groups (communities) 
- Posts
- Events

### 2. **Real-time Results**
- Queries Firestore collections
- Returns actual user/community/post data
- Relevance-based sorting

### 3. **Recent Searches**
- Automatically saves search history
- Persisted in UserDefaults
- Up to 10 recent searches

### 4. **Hashtag Support**
- Search posts by hashtags (e.g., `#Prayer`)
- Special handling for hashtag queries

### 5. **Trending Topics**
- Aggregates hashtags from recent posts
- Shows top 10 trending topics

---

## Required Setup Steps

### Step 1: Update Your Firestore Data Model

Your documents **must include lowercase fields** for searching:

#### Users Collection
```swift
// When creating/updating users:
let userData: [String: Any] = [
    "username": "JohnDoe",
    "usernameLowercase": "johndoe",  // ← ADD THIS
    "displayName": "John Doe",
    "displayNameLowercase": "john doe",  // ← ADD THIS
    "bio": "Faith-driven developer",
    "followerCount": 234,
    "isVerified": false
]
```

#### Communities Collection
```swift
// When creating/updating communities:
let communityData: [String: Any] = [
    "name": "Prayer Warriors",
    "nameLowercase": "prayer warriors",  // ← ADD THIS
    "description": "Daily prayer group",
    "memberCount": 150,
    "isPrivate": false,
    "isVerified": true
]
```

#### Posts Collection
```swift
// When creating/updating posts:
let postData: [String: Any] = [
    "content": "Grateful for God's blessings #Faith #Prayer",
    "contentLowercase": "grateful for god's blessings #faith #prayer",  // ← ADD THIS
    "hashtags": ["Faith", "Prayer"],
    "hashtagsLowercase": ["faith", "prayer"],  // ← ADD THIS
    "authorName": "John Doe",
    "amenCount": 42,
    "commentCount": 8
]
```

#### Events Collection
```swift
// When creating/updating events:
let eventData: [String: Any] = [
    "title": "Sunday Service",
    "titleLowercase": "sunday service",  // ← ADD THIS
    "location": "Main Church",
    "date": Timestamp(date: Date()),
    "attendeeCount": 120,
    "isVerified": true
]
```

### Step 2: Create Firestore Indexes

Firestore requires indexes for these queries. You have 2 options:

#### Option A: Auto-Create (Recommended)
1. Run your app
2. Perform a search
3. Check Xcode console for error messages like:
   ```
   The query requires an index. You can create it here: 
   https://console.firebase.google.com/...
   ```
4. Click the link to auto-create the index
5. Wait 2-3 minutes for index to build

#### Option B: Manual Creation
Go to [Firebase Console](https://console.firebase.google.com) → Your Project → Firestore Database → Indexes

Create these **Composite Indexes**:

**For Users (People Search):**
- Collection: `users`
- Fields: `usernameLowercase` (Ascending), `__name__` (Ascending)

- Collection: `users`
- Fields: `displayNameLowercase` (Ascending), `__name__` (Ascending)

**For Communities (Groups Search):**
- Collection: `communities`
- Fields: `nameLowercase` (Ascending), `__name__` (Ascending)

**For Posts:**
- Collection: `posts`
- Fields: `contentLowercase` (Ascending), `__name__` (Ascending)

- Collection: `posts`
- Fields: `hashtagsLowercase` (Array), `createdAt` (Descending)

**For Events:**
- Collection: `events`
- Fields: `titleLowercase` (Ascending), `__name__` (Ascending)

### Step 3: Update Your Create/Update Functions

Make sure when you create or update documents, you add the lowercase fields:

```swift
// Example: Creating a user
func createUser(username: String, displayName: String) async throws {
    let userData: [String: Any] = [
        "username": username,
        "usernameLowercase": username.lowercased(),  // ← Important!
        "displayName": displayName,
        "displayNameLowercase": displayName.lowercased(),  // ← Important!
        // ... other fields
    ]
    
    try await db.collection("users").addDocument(data: userData)
}

// Example: Creating a post with hashtags
func createPost(content: String) async throws {
    let hashtags = extractHashtags(from: content)
    
    let postData: [String: Any] = [
        "content": content,
        "contentLowercase": content.lowercased(),  // ← Important!
        "hashtags": hashtags,
        "hashtagsLowercase": hashtags.map { $0.lowercased() },  // ← Important!
        // ... other fields
    ]
    
    try await db.collection("posts").addDocument(data: postData)
}
```

---

## Testing Your Search

### 1. Add Test Data
Use the Firebase Console or your app to create some test data:

```swift
// Test users
- username: "johndoe", displayName: "John Doe"
- username: "sarahchen", displayName: "Sarah Chen"

// Test communities
- name: "Prayer Warriors"
- name: "Bible Study Group"

// Test posts
- content: "Grateful for today #Faith #Prayer"
- content: "Amazing sermon today! #Church"
```

### 2. Test Search Queries

In your app:
- Search for "john" → should find John Doe
- Search for "prayer" → should find Prayer Warriors community & posts
- Search for "#Faith" → should find posts with #Faith hashtag
- Test filters (People, Groups, Posts, Events)

### 3. Verify Results
- Check that results appear
- Verify sorting by relevance
- Test recent searches functionality

---

## Search Limitations (Firestore)

### Current Limitations:
1. **Prefix matching only** - Can search "john" but not "ohn"
2. **No fuzzy search** - Typos won't work ("jhon" won't find "john")
3. **Case-sensitive without lowercase fields** - That's why we need `usernameLowercase`
4. **No full-text search** - Can't search within middle of words

### These Are Normal!
Firestore is **not designed for full-text search**. For production apps, you need a dedicated search service.

---

## Upgrade to Production Search (Optional)

For **better search experience**, integrate **Algolia**:

### Why Algolia?
- ✅ Full-text search
- ✅ Typo tolerance  
- ✅ Instant results
- ✅ Faceted search
- ✅ Geo-search
- ✅ Analytics

### Setup Algolia (Quick Guide)

1. **Install Firebase Extension**
   - Go to Firebase Console → Extensions
   - Install "Search with Algolia"
   - This automatically syncs Firestore → Algolia

2. **Add Algolia SDK**
   ```swift
   // In your Package Dependencies:
   https://github.com/algolia/instantsearch-ios
   ```

3. **Update SearchService**
   ```swift
   import InstantSearchSwiftUI
   
   class SearchService {
       let client = SearchClient(
           appID: "YOUR_APP_ID",
           apiKey: "YOUR_SEARCH_KEY"
       )
       
       func search(query: String) async throws -> [SearchResult] {
           let index = client.index(withName: "users")
           let response = try await index.search(query: query)
           // Convert to SearchResult
       }
   }
   ```

### Algolia Pricing
- **Free tier**: 10K searches/month
- **Perfect for development & small apps**
- Upgrade as you grow

---

## Usage in Your App

### Basic Search
```swift
// In SearchView or any view
@StateObject private var searchService = SearchService.shared

// Perform search
Task {
    let results = try await searchService.search(
        query: "prayer",
        filter: .all
    )
}
```

### Filtered Search
```swift
// Search only people
let people = try await searchService.search(
    query: "john",
    filter: .people
)

// Search only posts
let posts = try await searchService.search(
    query: "#Faith",
    filter: .posts
)
```

### Get Trending Topics
```swift
let trending = try await searchService.getTrendingTopics()
```

### Recent Searches
```swift
// Load recent searches
searchService.loadRecentSearches()

// Access recent searches
let recent = searchService.recentSearches

// Clear recent searches
searchService.clearRecentSearches()
```

---

## Troubleshooting

### "The query requires an index"
**Solution:** Click the link in the error message to create the index

### No results found
**Checklist:**
1. ✅ Did you add lowercase fields to your documents?
2. ✅ Did you create the Firestore indexes?
3. ✅ Did you wait for indexes to build? (takes 2-3 minutes)
4. ✅ Do you have test data in Firestore?

### Search is slow
**Solutions:**
1. Reduce search scope (use specific filters)
2. Limit results (already set to 20 per category)
3. Consider Algolia for production

### Case-sensitive results
**Solution:** Make sure you're using lowercase fields in queries

---

## Next Steps

### Immediate:
1. ✅ Add lowercase fields to existing Firestore documents
2. ✅ Create Firestore indexes
3. ✅ Test search functionality

### Short-term:
1. Add loading states/skeletons
2. Add empty state illustrations
3. Implement result navigation (tap to view profile/post/etc)

### Long-term:
1. Consider Algolia for production
2. Add search analytics
3. Implement saved searches
4. Add search suggestions/autocomplete

---

## Files Modified

1. **SearchService.swift** (NEW) - Backend search logic
2. **SearchViewComponents.swift** (UPDATED) - Connected to SearchService
3. **Post+Extensions.swift** - Already has `timeAgoDisplay()` for formatting

---

## Summary

🎉 **Your search is now live!**

You can now search for:
- **People** by username or name
- **Communities** by name
- **Posts** by content or hashtags
- **Events** by title

Just follow the setup steps above to get everything working!

**Questions?** Check the inline comments in `SearchService.swift` for detailed documentation.
