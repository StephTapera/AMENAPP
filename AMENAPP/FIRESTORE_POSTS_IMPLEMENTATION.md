# Firestore Posts Implementation Guide

## Overview

This guide explains how posts are now fully integrated with Firebase Firestore in the AMENAPP. All post operations (create, read, update, delete, and interactions) are now persisted to the cloud and synced in real-time across devices.

## Architecture

### Key Components

1. **FirebasePostService** (`FirebasePostService.swift`)
   - Handles all Firestore operations for posts
   - Provides real-time listeners for live updates
   - Manages post interactions (amen, lightbulb, comments, reposts)

2. **PostsManager** (`PostsManager.swift`)
   - SwiftUI-friendly observable object
   - Bridges UI with FirebasePostService
   - Maintains local cache for performance
   - Falls back to mock data if Firebase is unavailable

3. **FirestorePost** Model
   - Firestore-optimized post model
   - Includes Codable conformance for Firebase
   - Converts to/from local `Post` model

## Firestore Data Structure

### Posts Collection (`posts`)

```
posts/
  ├── {postId}/
      ├── authorId: String
      ├── authorName: String
      ├── authorUsername: String
      ├── authorInitials: String
      ├── authorProfileImageURL: String?
      ├── content: String
      ├── category: String ("openTable", "testimonies", "prayer")
      ├── topicTag: String?
      ├── visibility: String ("everyone", "followers", "community")
      ├── allowComments: Bool
      ├── imageURLs: [String]?
      ├── linkURL: String?
      ├── createdAt: Timestamp
      ├── updatedAt: Timestamp
      ├── amenCount: Int
      ├── lightbulbCount: Int
      ├── commentCount: Int
      ├── repostCount: Int
      ├── isRepost: Bool
      ├── originalPostId: String?
      ├── originalAuthorId: String?
      ├── originalAuthorName: String?
      ├── amenUserIds: [String]
      └── lightbulbUserIds: [String]
```

## Key Features

### 1. Create Post

```swift
// In your view or view model
Task {
    try await FirebasePostService.shared.createPost(
        content: "My post content",
        category: .openTable,
        topicTag: "Tech & Faith",
        visibility: .everyone,
        allowComments: true
    )
}

// Or use PostsManager (recommended for UI)
PostsManager.shared.createPost(
    content: "My post content",
    category: .openTable,
    topicTag: "Tech & Faith"
)
```

**What happens:**
1. Fetches current user info from Firestore (`users/{userId}`)
2. Creates a new post document in `posts` collection
3. Increments user's `postsCount` in their profile
4. Real-time listener automatically updates all connected clients
5. Triggers haptic feedback for success

### 2. Fetch Posts

```swift
// Fetch all posts
Task {
    try await FirebasePostService.shared.fetchAllPosts()
}

// Fetch by category
Task {
    let prayers = try await FirebasePostService.shared.fetchPosts(for: .prayer)
}

// Fetch user's posts
Task {
    let userPosts = try await FirebasePostService.shared.fetchUserPosts(userId: "user123")
}
```

### 3. Real-time Updates

```swift
// Start listening to all posts
FirebasePostService.shared.startListening()

// Listen to specific category
FirebasePostService.shared.startListening(category: .prayer)

// Stop listening (important for cleanup)
FirebasePostService.shared.stopListening()
```

**Best Practice:** Start listening when view appears, stop when it disappears:

```swift
struct FeedView: View {
    @StateObject private var postsManager = PostsManager.shared
    
    var body: some View {
        // Your UI here
        .onAppear {
            FirebasePostService.shared.startListening()
        }
        .onDisappear {
            FirebasePostService.shared.stopListening()
        }
    }
}
```

### 4. Edit Post

```swift
Task {
    try await FirebasePostService.shared.editPost(
        postId: "post123",
        newContent: "Updated content"
    )
}

// Or via PostsManager
PostsManager.shared.editPost(postId: postUUID, newContent: "Updated")
```

**Security:**
- Only the post author can edit their posts
- Verification happens server-side before update

### 5. Delete Post

```swift
Task {
    try await FirebasePostService.shared.deletePost(postId: "post123")
}

// Or via PostsManager
PostsManager.shared.deletePost(postId: postUUID)
```

**What happens:**
1. Verifies user owns the post
2. Deletes post document from Firestore
3. Decrements user's `postsCount`
4. Removes from local cache
5. Updates all connected clients via real-time listener

### 6. Interactions

#### Toggle Amen (Prayer Posts)

```swift
Task {
    try await FirebasePostService.shared.toggleAmen(postId: "post123")
}

// Or via PostsManager
PostsManager.shared.updateAmenCount(postId: postUUID, increment: true)
```

**Features:**
- Tracks which users have "Amened" (`amenUserIds` array)
- Prevents duplicate amens from same user
- Updates count atomically with `FieldValue.increment()`
- Provides haptic feedback

#### Toggle Lightbulb (Open Table Posts)

```swift
Task {
    try await FirebasePostService.shared.toggleLightbulb(postId: "post123")
}

// Or via PostsManager
PostsManager.shared.updateLightbulbCount(postId: postUUID, increment: true)
```

#### Repost

```swift
Task {
    try await FirebasePostService.shared.repostToProfile(originalPostId: "post123")
}

// Or via PostsManager
PostsManager.shared.repostToProfile(originalPost: post)
```

**What happens:**
1. Fetches original post from Firestore
2. Creates new post with `isRepost: true` and references to original
3. Increments `repostCount` on original post
4. Increments user's `postsCount`
5. Updates all feeds via real-time listener

### 7. Check User Interactions

```swift
// Check if current user has amened a post
let hasAmened = await FirebasePostService.shared.hasUserAmened(postId: "post123")

// Check if current user has lit lightbulb
let hasLit = await FirebasePostService.shared.hasUserLitLightbulb(postId: "post123")
```

## Security Rules (Firestore)

Add these rules to your Firebase Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Posts collection
    match /posts/{postId} {
      // Anyone can read posts
      allow read: if true;
      
      // Only authenticated users can create posts
      allow create: if request.auth != null
                    && request.resource.data.authorId == request.auth.uid;
      
      // Only post author can update or delete
      allow update, delete: if request.auth != null
                           && resource.data.authorId == request.auth.uid;
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone can read user profiles
      allow read: if true;
      
      // Only the user can update their own profile
      allow create, update: if request.auth != null
                           && request.auth.uid == userId;
      
      // Users cannot delete their profiles
      allow delete: if false;
    }
  }
}
```

## Firestore Indexes

For optimal performance, create these composite indexes in Firebase Console:

1. **Posts by Category and Date:**
   - Collection: `posts`
   - Fields: `category` (Ascending), `createdAt` (Descending)

2. **Posts by Author and Date:**
   - Collection: `posts`
   - Fields: `authorId` (Ascending), `createdAt` (Descending)

3. **Posts by Visibility and Date:**
   - Collection: `posts`
   - Fields: `visibility` (Ascending), `createdAt` (Descending)

Firebase will usually suggest these automatically when you first query.

## Error Handling

All Firebase operations are wrapped in `do-catch` blocks:

```swift
Task {
    do {
        try await FirebasePostService.shared.createPost(...)
        print("✅ Success")
    } catch FirebaseError.unauthorized {
        print("❌ User not authenticated")
    } catch FirebaseError.documentNotFound {
        print("❌ Document not found")
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}
```

## Performance Optimizations

### 1. Local Caching
- Posts are cached locally in `PostsManager`
- UI reads from cache for instant rendering
- Background sync keeps cache updated

### 2. Pagination (Coming Soon)
```swift
// Future implementation
func fetchMorePosts(after lastPost: Post, limit: Int = 20) async throws {
    // Use Firestore's startAfter for pagination
}
```

### 3. Batch Operations
For bulk updates (e.g., importing sample data):

```swift
let batch = db.batch()

for post in posts {
    let docRef = db.collection("posts").document()
    batch.setData(from: post, forDocument: docRef)
}

try await batch.commit()
```

## Testing

### Mock Mode
Toggle mock data for testing without Firebase:

```swift
// In PostsManager.swift
private var useMockData = true  // Set to true for testing
```

### Debugging
Enable verbose logging:

```swift
// All Firebase operations include console logs:
print("📝 Creating new post...")
print("✅ Post created with ID: \(postId)")
print("❌ Failed: \(error)")
```

## Migration from Mock Data

If you have existing posts in the local `PostsManager`, migrate them:

```swift
func migrateLocalPostsToFirebase() async {
    for post in allPosts {
        do {
            try await FirebasePostService.shared.createPost(
                content: post.content,
                category: post.category,
                topicTag: post.topicTag,
                visibility: post.visibility,
                allowComments: post.allowComments,
                imageURLs: post.imageURLs,
                linkURL: post.linkURL
            )
            print("✅ Migrated post: \(post.id)")
        } catch {
            print("❌ Failed to migrate post: \(error)")
        }
    }
}
```

## Common Issues & Solutions

### Issue: Posts not appearing
**Solution:** Check that:
1. User is authenticated (`FirebaseManager.shared.isAuthenticated`)
2. Real-time listener is active
3. Firestore rules allow read access
4. Posts collection exists in Firebase

### Issue: "Permission denied" errors
**Solution:** Update Firestore security rules (see above)

### Issue: Duplicate posts appearing
**Solution:** 
- Ensure you're not calling `fetchAllPosts()` multiple times
- Stop listeners when view disappears
- Check for duplicate real-time listener subscriptions

### Issue: Slow performance
**Solution:**
- Add Firestore indexes (see above)
- Implement pagination for large datasets
- Limit real-time listener scope to specific categories
- Use `.limit(to: N)` in queries

## Next Steps

1. **Comments System:** Implement Firestore subcollection for comments
   ```
   posts/{postId}/comments/{commentId}
   ```

2. **Image Upload:** Use Firebase Storage for post images
   ```swift
   let imageURL = try await FirebaseManager.shared.uploadImage(image, to: "post_images/\(postId)")
   ```

3. **Push Notifications:** Notify users when their posts get interactions
   ```swift
   // Cloud Functions trigger on new amen/comment
   ```

4. **Analytics:** Track post engagement
   ```swift
   Analytics.logEvent("post_created", parameters: ["category": category])
   ```

5. **Offline Support:** Firestore has built-in offline persistence
   ```swift
   // Enable offline persistence
   let settings = FirestoreSettings()
   settings.isPersistenceEnabled = true
   db.settings = settings
   ```

## Resources

- [Firebase Firestore Documentation](https://firebase.google.com/docs/firestore)
- [SwiftUI + Firebase Best Practices](https://firebase.google.com/docs/firestore/solutions/ios)
- [Security Rules Guide](https://firebase.google.com/docs/firestore/security/get-started)

## Support

For issues or questions:
1. Check console logs (extensive logging is implemented)
2. Verify Firebase Console for data structure
3. Test with Firebase Emulator for local development
4. Review Firestore rules and indexes

---

**Last Updated:** January 20, 2026
**Version:** 1.0
**Status:** ✅ Fully Implemented
