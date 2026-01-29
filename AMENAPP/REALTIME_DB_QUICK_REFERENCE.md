# Firebase Realtime Database - Quick Reference

## When to Use What

### Use Firestore ✅
- User profiles
- Account settings  
- Social links
- Complex queries (search by username, filter by multiple fields)
- Data that changes infrequently

### Use Realtime Database ✅
- Posts and comments
- Like/amen/lightbulb counts
- Saved posts bookmarks
- Real-time feed updates
- High-frequency writes
- Data that needs instant sync

---

## Common Operations

### Create a Post
```swift
let post = try await RealtimePostService.shared.createPost(
    content: "Hello world!",
    category: .openTable,
    topicTag: "Relationships",
    visibility: .everyone,
    allowComments: true
)
```

### Toggle Amen
```swift
let hasAmen = try await RealtimeEngagementService.shared.toggleAmen(
    postId: post.id.uuidString
)
```

### Save a Post
```swift
let isSaved = try await RealtimeSavedPostsService.shared.toggleSavePost(
    postId: post.id.uuidString
)
```

### Add a Comment
```swift
let comment = try await RealtimeCommentsService.shared.createComment(
    postId: post.id.uuidString,
    content: "Great post!"
)
```

### Real-time Listeners
```swift
// Listen to posts
RealtimePostService.shared.observeUserPosts(userId: userId) { posts in
    self.posts = posts
}

// Listen to stats
RealtimeEngagementService.shared.observePostStats(postId: postId) { stats in
    self.amenCount = stats.amenCount
    self.lightbulbCount = stats.lightbulbCount
}

// Listen to comments
RealtimeCommentsService.shared.observeComments(postId: postId) { comments in
    self.comments = comments
}

// Listen to saved posts
RealtimeSavedPostsService.shared.observeSavedPosts { postIds in
    // Fetch full post details if needed
}
```

---

## Database Paths Reference

```
Firebase Realtime Database Structure:

/posts
  /{postId}
    - authorId
    - authorName
    - content
    - category
    - createdAt
    - ...

/user_posts
  /{userId}
    /{postId}: timestamp

/category_posts
  /openTable
    /{postId}: timestamp
  /testimonies
    /{postId}: timestamp
  /prayer
    /{postId}: timestamp

/post_stats
  /{postId}
    - amenCount: 0
    - lightbulbCount: 0
    - commentCount: 0
    - repostCount: 0

/post_interactions
  /{postId}
    /amen
      /{userId}: timestamp
    /lightbulb
      /{userId}: timestamp

/user_saved_posts
  /{userId}
    /{postId}: timestamp

/comments
  /{postId}
    /{commentId}
      - authorId
      - content
      - createdAt
      - ...

/comment_stats
  /{commentId}
    - amenCount: 0
    - replyCount: 0

/user_comments
  /{userId}
    /{commentId}: timestamp
```

---

## Error Handling

```swift
do {
    let post = try await RealtimePostService.shared.createPost(...)
    print("✅ Post created: \(post.id)")
} catch {
    print("❌ Error: \(error.localizedDescription)")
    // Show error to user
}
```

---

## Performance Tips

1. **Use Listeners Wisely**
   - Set up listeners when view appears
   - Remove listeners when view disappears
   - Don't create multiple listeners for same data

2. **Batch Operations**
   - Use multi-path updates for atomic writes
   - Group related operations together

3. **Optimize Data Size**
   - Only store necessary fields
   - Use references instead of duplicating data
   - Compress images before uploading

4. **Cache User Data**
   - Store display name, username in UserDefaults
   - Reduces database reads for common data

---

## Security Rules (TODO)

Create Realtime Database rules:
```json
{
  "rules": {
    "posts": {
      "$postId": {
        ".read": true,
        ".write": "auth != null && (!data.exists() || data.child('authorId').val() === auth.uid)"
      }
    },
    "user_posts": {
      "$userId": {
        ".read": true,
        ".write": "$userId === auth.uid"
      }
    },
    "post_interactions": {
      "$postId": {
        "amen": {
          "$userId": {
            ".write": "$userId === auth.uid"
          }
        }
      }
    },
    "user_saved_posts": {
      "$userId": {
        ".read": "$userId === auth.uid",
        ".write": "$userId === auth.uid"
      }
    }
  }
}
```

---

## Migration from Firestore

If you need to migrate existing data:

```swift
// Pseudo-code for migration
func migratePostsToRealtimeDB() async throws {
    let db = Firestore.firestore()
    let snapshot = try await db.collection("posts").getDocuments()
    
    for document in snapshot.documents {
        let data = document.data()
        
        // Create post in Realtime DB
        let postId = document.documentID
        let updates: [String: Any] = [
            "/posts/\(postId)": data,
            "/user_posts/\(data["authorId"])/\(postId)": data["createdAt"],
            "/category_posts/\(data["category"])/\(postId)": data["createdAt"]
        ]
        
        try await Database.database().reference().updateChildValues(updates)
    }
}
```

---

## Troubleshooting

### Issue: Posts not appearing
**Solution:** Check that user is authenticated and listeners are set up

### Issue: Counts not updating
**Solution:** Ensure atomic increment is used, not direct value set

### Issue: Slow performance
**Solution:** Add indexes, limit query results, use pagination

### Issue: Connection errors
**Solution:** Check Firebase console for database URL, verify network connection

---

## Useful Commands

```swift
// Remove all listeners
RealtimePostService.shared.removeAllListeners()
RealtimeEngagementService.shared.removeAllListeners()
RealtimeCommentsService.shared.removeAllListeners()
RealtimeSavedPostsService.shared.removeSavedPostsListener()

// Check if post is saved (sync)
let isSaved = RealtimeSavedPostsService.shared.isPostSavedSync(postId: postId)

// Increment comment count manually
try await RealtimeEngagementService.shared.incrementCommentCount(postId: postId)
```

---

## Testing

```swift
@Test("Create post in Realtime DB")
func testCreatePost() async throws {
    let service = RealtimePostService.shared
    
    let post = try await service.createPost(
        content: "Test post",
        category: .openTable
    )
    
    #expect(post.content == "Test post")
    #expect(post.category == .openTable)
}

@Test("Toggle amen")
func testToggleAmen() async throws {
    let service = RealtimeEngagementService.shared
    
    let hasAmen1 = try await service.toggleAmen(postId: testPostId)
    #expect(hasAmen1 == true)
    
    let hasAmen2 = try await service.toggleAmen(postId: testPostId)
    #expect(hasAmen2 == false)
}
```

---

## Resources

- Firebase Realtime Database Docs: https://firebase.google.com/docs/database
- Firebase Console: https://console.firebase.google.com
- Performance Monitoring: Firebase Console → Realtime Database → Usage
- Cost Calculator: https://firebase.google.com/pricing

---

**Pro Tip:** Use Firebase Local Emulator Suite for development to avoid costs and test faster!
