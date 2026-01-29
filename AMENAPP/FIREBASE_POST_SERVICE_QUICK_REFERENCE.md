# Firebase Post Service - Quick Reference Card

## 🎯 ONE-PAGE CHEAT SHEET

---

## 📦 Import
```swift
let postService = FirebasePostService.shared
```

---

## 🆕 CREATE

### Basic Post
```swift
try await postService.createPost(
    content: "My post",
    category: .openTable,
    visibility: .everyone
)
```

### With Images
```swift
try await postService.createPostWithImages(
    content: "My post",
    category: .testimonies,
    images: [image1, image2]
)
```

---

## 📖 FETCH

### All Posts
```swift
try await postService.fetchAllPosts()
// Access: postService.posts
```

### By Category
```swift
let posts = try await postService.fetchPosts(
    for: .openTable,
    filter: "popular"  // "all", "recent", "popular", "following"
)
```

### User Posts
```swift
let posts = try await postService.fetchUserPosts(userId: "user123")
let originals = try await postService.fetchUserOriginalPosts(userId: "user123")
let reposts = try await postService.fetchUserReposts(userId: "user123")
let saved = try await postService.fetchUserSavedPosts(userId: "user123")
```

---

## ✏️ UPDATE

### Edit
```swift
try await postService.editPost(postId: "post123", newContent: "Updated")
```

### Pin/Unpin
```swift
try await postService.pinPost(postId: "post123")
try await postService.unpinPost(postId: "post123")
```

---

## 🗑️ DELETE

```swift
try await postService.deletePost(postId: "post123")
```

---

## 🙏 INTERACTIONS

### Amen (Like)
```swift
try await postService.toggleAmen(postId: "post123")
let hasAmened = await postService.hasUserAmened(postId: "post123")
```

### Lightbulb (Insight)
```swift
try await postService.toggleLightbulb(postId: "post123")
let hasLit = await postService.hasUserLitLightbulb(postId: "post123")
```

### Comment
```swift
try await postService.incrementCommentCount(
    postId: "post123",
    commentText: "Great post!"
)
```

### Repost
```swift
try await postService.repostToProfile(originalPostId: "post123")
```

---

## 🔖 BOOKMARKS

### Save/Unsave
```swift
try await postService.savePost(postId: "post123")
try await postService.unsavePost(postId: "post123")
let isSaved = try await postService.isPostSaved(postId: "post123")
```

---

## 📊 ANALYTICS

### Track & Get Stats
```swift
try await postService.trackPostView(postId: "post123")
let analytics = try await postService.getPostAnalytics(postId: "post123")

print(analytics.viewCount)
print(analytics.engagementRate)
print(analytics.formattedEngagementRate) // "15.3%"
```

---

## 🚨 MODERATION

### Report
```swift
try await postService.reportPost(
    postId: "post123",
    reason: .spam,  // .spam, .harassment, .hateSpeech, etc.
    additionalDetails: "Details here"
)
```

### Hide
```swift
try await postService.hidePost(postId: "post123")
let isHidden = try await postService.isPostHidden(postId: "post123")
```

---

## 💾 DRAFTS

### Create & Manage
```swift
let draftId = try await postService.saveDraft(
    content: "Draft",
    category: .openTable,
    images: [image1]
)

let drafts = try await postService.loadDrafts()

try await postService.publishDraft(draftId: draftId)
try await postService.deleteDraft(draftId: draftId)
```

---

## 📅 SCHEDULING

### Schedule & Cancel
```swift
let scheduledId = try await postService.schedulePost(
    content: "Future post",
    category: .prayer,
    scheduledFor: futureDate
)

try await postService.cancelScheduledPost(scheduledPostId: scheduledId)
```

---

## 🔄 REAL-TIME

### Listen & Stop
```swift
postService.startListening()
postService.startListening(category: .openTable)
postService.stopListening()
```

---

## 📱 SWIFTUI INTEGRATION

### Basic View
```swift
struct FeedView: View {
    @StateObject private var postService = FirebasePostService.shared
    
    var body: some View {
        ScrollView {
            ForEach(postService.posts) { post in
                PostCard(post: post)
            }
        }
        .task {
            try? await postService.fetchAllPosts()
            postService.startListening()
        }
        .onDisappear {
            postService.stopListening()
        }
    }
}
```

### Post Card
```swift
struct PostCard: View {
    let post: Post
    
    var body: some View {
        VStack {
            Text(post.content)
            
            HStack {
                Button {
                    Task {
                        try? await FirebasePostService.shared.toggleAmen(
                            postId: post.id.uuidString
                        )
                    }
                } label: {
                    Label("\(post.amenCount)", systemImage: "hands.clap.fill")
                }
            }
        }
    }
}
```

---

## 📊 PUBLISHED PROPERTIES

```swift
postService.posts              // All posts
postService.openTablePosts     // OpenTable only
postService.testimoniesPosts   // Testimonies only
postService.prayerPosts        // Prayer only
postService.isLoading          // Loading state
postService.error              // Error message
```

---

## 🧪 TESTING

```swift
// Delete all posts
try await postService.deleteAllPosts()

// Delete fake data
try await postService.deleteFakePosts()

// Delete by author
try await postService.deletePostsByAuthorName("Test User")
```

---

## 🎨 POST CATEGORIES

```swift
Post.PostCategory.openTable
Post.PostCategory.testimonies
Post.PostCategory.prayer
```

---

## 🔐 VISIBILITY OPTIONS

```swift
Post.PostVisibility.everyone
Post.PostVisibility.followers
Post.PostVisibility.community
```

---

## 🚨 REPORT REASONS

```swift
ReportReason.spam
ReportReason.harassment
ReportReason.hateSpeech
ReportReason.violence
ReportReason.sexualContent
ReportReason.misinformation
ReportReason.other
```

---

## 📈 ANALYTICS MODEL

```swift
struct PostAnalytics {
    let postId: String
    let viewCount: Int
    let amenCount: Int
    let lightbulbCount: Int
    let commentCount: Int
    let repostCount: Int
    let totalEngagements: Int
    let engagementRate: Double
    var formattedEngagementRate: String // "15.3%"
}
```

---

## 💡 COMMON PATTERNS

### Create Post Button
```swift
Button("Post") {
    Task {
        try await postService.createPost(
            content: content,
            category: selectedCategory,
            visibility: .everyone
        )
    }
}
```

### Amen Button
```swift
Button {
    Task {
        try await postService.toggleAmen(postId: post.id.uuidString)
    }
} label: {
    Label("\(post.amenCount)", systemImage: "hands.clap.fill")
}
```

### Save Button
```swift
Button {
    Task {
        if isSaved {
            try await postService.unsavePost(postId: post.id.uuidString)
        } else {
            try await postService.savePost(postId: post.id.uuidString)
        }
        isSaved.toggle()
    }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
}
```

---

## 🔥 FIRESTORE PATHS

```
posts/{postId}
savedPosts/{userId}_{postId}
postDrafts/{draftId}
scheduledPosts/{scheduledId}
hiddenPosts/{userId}_{postId}
postReports/{reportId}
notifications/{notificationId}
```

---

## ⚡ TIPS

1. Always use `try await` for async operations
2. Call `startListening()` in `.task` or `.onAppear`
3. Call `stopListening()` in `.onDisappear`
4. Use `@StateObject` for service instance
5. Access posts via published properties
6. Handle errors with do-catch blocks
7. Use haptic feedback for better UX (built-in)

---

## 📚 FULL DOCS

- `FIREBASE_POST_SERVICE_COMPLETE.md` - All features
- `FIREBASE_POST_SERVICE_USAGE_GUIDE.md` - Detailed examples
- `FIREBASE_POST_SERVICE_ARCHITECTURE.md` - Architecture
- `README_FIREBASE_POST_SERVICE.md` - Summary

---

## ✅ YOU'RE READY!

**Everything works. Just build your UI!** 🚀
