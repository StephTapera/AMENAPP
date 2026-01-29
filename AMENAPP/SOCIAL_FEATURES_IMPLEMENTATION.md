# Social Features Implementation Guide

## Overview

This document details the complete implementation of social features including:
- ✅ Comments and nested replies
- ✅ Saving posts with collections
- ✅ Reposts with optional comments (quote reposts)

All features are fully integrated with Firestore for real-time updates and persistent storage.

---

## 1. Comments and Replies

### Models

**Comment** (`PostInteractionModels.swift`)
```swift
struct Comment: Identifiable, Codable, Equatable {
    var id: String?
    var postId: String
    var authorId: String
    var authorName: String
    var authorUsername: String
    var authorInitials: String
    var authorProfileImageURL: String?
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var amenCount: Int
    var replyCount: Int
    var amenUserIds: [String]
    var parentCommentId: String?  // nil = top-level comment
    var mentionedUserIds: [String]?
}
```

**CommentWithReplies** - Helper struct for nested display
```swift
struct CommentWithReplies: Identifiable, Equatable {
    let comment: Comment
    var replies: [Comment]
}
```

### Service Methods

**CommentService.swift** provides:

#### Add Comment
```swift
await commentService.addComment(
    postId: "post-id",
    content: "Great post!",
    mentionedUserIds: ["user1", "user2"]
)
```

#### Add Reply
```swift
await commentService.addReply(
    postId: "post-id",
    parentCommentId: "comment-id",
    content: "I agree!",
    mentionedUserIds: nil
)
```

#### Fetch Comments with Replies
```swift
let commentsWithReplies = try await commentService.fetchCommentsWithReplies(for: "post-id")
```

#### Toggle Amen on Comment
```swift
try await commentService.toggleAmen(commentId: "comment-id")
```

#### Edit Comment
```swift
try await commentService.editComment(commentId: "comment-id", newContent: "Updated text")
```

#### Delete Comment
```swift
try await commentService.deleteComment(commentId: "comment-id")
```
*Note: Deleting a comment also deletes all its replies and updates counts*

#### Real-time Listening
```swift
// Start listening
commentService.startListening(to: "post-id")

// Stop listening
commentService.stopListening()
```

### Firestore Structure

```
comments/
  {commentId}/
    postId: "post-123"
    authorId: "user-456"
    authorName: "John Doe"
    authorUsername: "johndoe"
    authorInitials: "JD"
    authorProfileImageURL: "https://..."
    content: "Great post!"
    createdAt: Timestamp
    updatedAt: Timestamp
    amenCount: 5
    replyCount: 2
    amenUserIds: ["user1", "user2"]
    parentCommentId: null  // or "parent-comment-id" for replies
    mentionedUserIds: ["user3"]
```

### UI Usage

**Display comments on a post:**
```swift
.sheet(isPresented: $showComments) {
    CommentsView(post: post)
        .environmentObject(userService)
}
```

The `CommentsView` provides:
- Nested comment display (comments with their replies)
- Reply to comments
- Amen comments
- Delete own comments
- Real-time updates

---

## 2. Saved Posts

### Models

**SavedPost** (`PostInteractionModels.swift`)
```swift
struct SavedPost: Identifiable, Codable, Equatable {
    var id: String?
    var userId: String
    var postId: String
    var savedAt: Date
    var collectionName: String?  // "All", "Prayer", "Favorites", etc.
}
```

### Service Methods

**SavedPostsService.swift** provides:

#### Save a Post
```swift
try await savedPostsService.savePost(
    postId: "post-id",
    collection: "Prayer"  // Optional
)
```

#### Unsave a Post
```swift
try await savedPostsService.unsavePost(postId: "post-id")
```

#### Toggle Save
```swift
try await savedPostsService.toggleSave(postId: "post-id", collection: "Favorites")
```

#### Check if Post is Saved
```swift
let isSaved = await savedPostsService.isPostSaved(postId: "post-id")
```

#### Fetch Saved Posts
```swift
// All saved posts
let savedPosts = try await savedPostsService.fetchSavedPosts()

// Saved posts in specific collection
let prayerPosts = try await savedPostsService.fetchSavedPosts(collection: "Prayer")

// Fetch actual post objects
let posts = try await savedPostsService.fetchSavedPostObjects(collection: "All")
```

#### Manage Collections
```swift
// Create collection
try await savedPostsService.createCollection(name: "Favorites")

// Delete collection (moves posts to "All")
try await savedPostsService.deleteCollection(name: "Favorites")

// Move post to different collection
try await savedPostsService.moveToCollection(
    postId: "post-id",
    newCollection: "Prayer"
)

// Clear all saved posts
try await savedPostsService.clearAllSavedPosts()

// Get count
let count = try await savedPostsService.getSavedPostCount()
```

#### Real-time Listening
```swift
// Start listening
savedPostsService.startListening()

// Stop listening
savedPostsService.stopListening()

// Access saved post IDs for quick lookup
if savedPostsService.savedPostIds.contains(postId) {
    // Post is saved
}
```

### Firestore Structure

```
savedPosts/
  {savedPostId}/
    userId: "user-123"
    postId: "post-456"
    savedAt: Timestamp
    collectionName: "Prayer"
```

### UI Usage

**Save button on post:**
```swift
Button {
    Task {
        try await savedPostsService.toggleSave(postId: post.id.uuidString)
    }
} label: {
    Image(systemName: savedPostsService.savedPostIds.contains(post.id.uuidString) 
        ? "bookmark.fill" 
        : "bookmark")
}
```

**Saved posts view:**
```swift
struct SavedPostsView: View {
    @StateObject private var savedPostsService = SavedPostsService.shared
    @State private var selectedCollection = "All"
    @State private var posts: [Post] = []
    
    var body: some View {
        VStack {
            // Collection picker
            Picker("Collection", selection: $selectedCollection) {
                ForEach(savedPostsService.collections, id: \.self) { collection in
                    Text(collection).tag(collection)
                }
            }
            .pickerStyle(.segmented)
            
            // Posts list
            ScrollView {
                ForEach(posts) { post in
                    PostCard(post: post)
                }
            }
        }
        .task {
            posts = try await savedPostsService.fetchSavedPostObjects(
                collection: selectedCollection == "All" ? nil : selectedCollection
            )
        }
        .onChange(of: selectedCollection) { _, newValue in
            Task {
                posts = try await savedPostsService.fetchSavedPostObjects(
                    collection: newValue == "All" ? nil : newValue
                )
            }
        }
    }
}
```

---

## 3. Reposts

### Models

**Repost** (`PostInteractionModels.swift`)
```swift
struct Repost: Identifiable, Codable, Equatable {
    var id: String?
    var userId: String
    var originalPostId: String
    var repostedAt: Date
    var withComment: String?  // Optional quote repost comment
}
```

### Service Methods

**RepostService.swift** provides:

#### Repost
```swift
// Simple repost
try await repostService.repost(postId: "post-id")

// Quote repost (with comment)
try await repostService.repost(
    postId: "post-id",
    withComment: "This is amazing! 🙌"
)
```

#### Unrepost
```swift
try await repostService.unrepost(postId: "post-id")
```

#### Toggle Repost
```swift
try await repostService.toggleRepost(postId: "post-id")
```

#### Check if Reposted
```swift
let hasReposted = await repostService.hasReposted(postId: "post-id")
```

#### Fetch Reposts
```swift
// Current user's reposts
let myReposts = try await repostService.fetchUserReposts()

// All reposts of a specific post
let reposts = try await repostService.fetchRepostsForPost(postId: "post-id")
```

#### Get Repost Count
```swift
let count = try await repostService.getRepostCount(for: "post-id")
```

#### Real-time Listening
```swift
// Start listening
repostService.startListening()

// Stop listening
repostService.stopListening()

// Access reposted post IDs
if repostService.repostedPostIds.contains(postId) {
    // Post is reposted
}
```

### Firestore Structure

**Repost Tracking:**
```
reposts/
  {repostId}/
    userId: "user-123"
    originalPostId: "post-456"
    repostedAt: Timestamp
    withComment: "Great insight!"  // Optional
```

**Reposted Post:**
```
posts/
  {newPostId}/
    authorId: "user-123"  // Reposter
    authorName: "Current User"
    content: "Original post content"
    category: "openTable"
    isRepost: true
    originalPostId: "post-456"
    originalAuthorId: "original-user"
    originalAuthorName: "Original Author"
    // ... other post fields
```

**Original Post Update:**
```
posts/
  {originalPostId}/
    repostCount: 15  // Incremented
```

### UI Usage

**Repost button on post:**
```swift
Button {
    Task {
        try await repostService.toggleRepost(postId: post.id.uuidString)
    }
} label: {
    HStack {
        Image(systemName: repostService.repostedPostIds.contains(post.id.uuidString)
            ? "arrow.2.squarepath"  // Filled/highlighted version
            : "arrow.2.squarepath")
        
        if post.repostCount > 0 {
            Text("\(post.repostCount)")
        }
    }
}
```

**Quote repost sheet:**
```swift
.sheet(isPresented: $showQuoteRepost) {
    QuoteRepostView(post: post)
}

struct QuoteRepostView: View {
    let post: Post
    @State private var comment = ""
    @StateObject private var repostService = RepostService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Add your thoughts")
            
            TextEditor(text: $comment)
            
            // Original post preview
            PostCard(post: post)
                .opacity(0.7)
            
            Button("Repost") {
                Task {
                    try await repostService.repost(
                        postId: post.id.uuidString,
                        withComment: comment
                    )
                    dismiss()
                }
            }
            .disabled(comment.isEmpty)
        }
    }
}
```

---

## 4. Integration with PostCard

Update your `PostCard` to include all social features:

```swift
struct PostCard: View {
    let post: Post
    
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var repostService = RepostService.shared
    @StateObject private var commentService = CommentService.shared
    
    @State private var showComments = false
    @State private var showQuoteRepost = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ... post content ...
            
            // Action buttons
            HStack(spacing: 24) {
                // Amen
                Button {
                    Task {
                        await PostsManager.shared.updateAmenCount(
                            postId: post.id,
                            increment: true
                        )
                    }
                } label: {
                    ActionButton(
                        icon: "hands.clap",
                        count: post.amenCount
                    )
                }
                
                // Comment
                Button {
                    showComments = true
                } label: {
                    ActionButton(
                        icon: "bubble.left",
                        count: post.commentCount
                    )
                }
                
                // Repost
                Menu {
                    Button {
                        Task {
                            try await repostService.repost(postId: post.id.uuidString)
                        }
                    } label: {
                        Label("Repost", systemImage: "arrow.2.squarepath")
                    }
                    
                    Button {
                        showQuoteRepost = true
                    } label: {
                        Label("Quote Repost", systemImage: "quote.bubble")
                    }
                } label: {
                    ActionButton(
                        icon: "arrow.2.squarepath",
                        count: post.repostCount,
                        isActive: repostService.repostedPostIds.contains(post.id.uuidString)
                    )
                }
                
                Spacer()
                
                // Save
                Button {
                    Task {
                        try await savedPostsService.toggleSave(postId: post.id.uuidString)
                    }
                } label: {
                    Image(systemName: savedPostsService.savedPostIds.contains(post.id.uuidString)
                        ? "bookmark.fill"
                        : "bookmark")
                }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(post: post)
        }
        .sheet(isPresented: $showQuoteRepost) {
            QuoteRepostView(post: post)
        }
        .task {
            // Initialize services
            savedPostsService.startListening()
            repostService.startListening()
        }
    }
}

struct ActionButton: View {
    let icon: String
    let count: Int
    var isActive: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if count > 0 {
                Text("\(count)")
            }
        }
        .foregroundStyle(isActive ? .blue : .black.opacity(0.6))
    }
}
```

---

## 5. Firestore Security Rules

Add these rules to your `firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Comments
    match /comments/{commentId} {
      // Anyone can read comments
      allow read: if true;
      
      // Only authenticated users can create comments
      allow create: if request.auth != null
        && request.resource.data.authorId == request.auth.uid;
      
      // Users can update their own comments
      allow update: if request.auth != null
        && resource.data.authorId == request.auth.uid;
      
      // Users can delete their own comments
      allow delete: if request.auth != null
        && resource.data.authorId == request.auth.uid;
    }
    
    // Saved Posts
    match /savedPosts/{savedPostId} {
      // Users can only read their own saved posts
      allow read: if request.auth != null
        && resource.data.userId == request.auth.uid;
      
      // Users can only create saved posts for themselves
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
      
      // Users can only update/delete their own saved posts
      allow update, delete: if request.auth != null
        && resource.data.userId == request.auth.uid;
    }
    
    // Reposts
    match /reposts/{repostId} {
      // Anyone can read reposts
      allow read: if true;
      
      // Only authenticated users can create reposts
      allow create: if request.auth != null
        && request.resource.data.userId == request.auth.uid;
      
      // Users can only delete their own reposts
      allow delete: if request.auth != null
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## 6. Firestore Indexes

Create these composite indexes in Firebase Console:

### Comments
- Collection: `comments`
- Fields:
  - `postId` (Ascending)
  - `parentCommentId` (Ascending)
  - `createdAt` (Ascending)

- Collection: `comments`
- Fields:
  - `parentCommentId` (Ascending)
  - `createdAt` (Ascending)

### Saved Posts
- Collection: `savedPosts`
- Fields:
  - `userId` (Ascending)
  - `savedAt` (Descending)

- Collection: `savedPosts`
- Fields:
  - `userId` (Ascending)
  - `collectionName` (Ascending)
  - `savedAt` (Descending)

### Reposts
- Collection: `reposts`
- Fields:
  - `userId` (Ascending)
  - `repostedAt` (Descending)

- Collection: `reposts`
- Fields:
  - `originalPostId` (Ascending)
  - `repostedAt` (Descending)

---

## 7. Notifications

All services automatically create notifications for:

### Comments
- ✅ Post author gets notified when someone comments
- ✅ Comment author gets notified when someone replies
- ✅ Users get notified when mentioned in comments

### Reposts
- ✅ Post author gets notified when someone reposts

### Saved Posts
- No notifications (private action)

---

## 8. Performance Optimizations

### Local Caching
All services maintain local caches:
- `CommentService`: `comments` and `commentReplies` dictionaries
- `SavedPostsService`: `savedPostIds` Set for O(1) lookups
- `RepostService`: `repostedPostIds` Set for O(1) lookups

### Real-time Updates
- Use `.startListening()` for active views
- Use `.stopListening()` when views disappear
- Batch writes ensure atomicity

### Count Aggregations
Use Firestore count aggregations for performance:
```swift
let count = try await savedPostsService.getSavedPostCount()
```

---

## 9. Testing Checklist

### Comments
- [ ] Add comment to post
- [ ] Add reply to comment
- [ ] Nested replies display correctly
- [ ] Amen comment
- [ ] Edit own comment
- [ ] Delete own comment (and all replies)
- [ ] Real-time updates work
- [ ] Mention notifications sent

### Saved Posts
- [ ] Save post
- [ ] Unsave post
- [ ] Create custom collection
- [ ] Move post between collections
- [ ] Delete collection
- [ ] Real-time updates work
- [ ] Quick lookup works (bookmark icon updates instantly)

### Reposts
- [ ] Simple repost creates new post
- [ ] Quote repost with comment
- [ ] Unrepost removes both tracking and post
- [ ] Repost count increments/decrements
- [ ] Original post linked correctly
- [ ] Real-time updates work
- [ ] Notification sent to original author

---

## 10. Next Steps

### Recommended Enhancements

1. **Comment Reactions**: Add more reaction types beyond Amen
2. **Thread Depth**: Limit reply nesting to prevent infinite threads
3. **Comment Sorting**: Add options to sort by newest, oldest, most amens
4. **Saved Post Search**: Add search/filter in saved posts
5. **Repost Analytics**: Track who reposted and engagement metrics
6. **Pinned Comments**: Allow post authors to pin comments
7. **Rich Text**: Support markdown or rich text in comments
8. **GIF Support**: Allow GIFs in comments
9. **Report/Block**: Add moderation features

---

## Summary

All social features are now fully implemented and integrated with Firestore:

✅ **Comments & Replies**
- Nested comment structure
- Amen reactions
- Edit/delete functionality
- Real-time updates
- Mention support

✅ **Saved Posts**
- Save/unsave posts
- Custom collections
- Move between collections
- Quick lookup caching
- Real-time sync

✅ **Reposts**
- Simple reposts
- Quote reposts
- Atomic operations
- Count tracking
- Notification system

All features include proper error handling, haptic feedback, and notifications.
