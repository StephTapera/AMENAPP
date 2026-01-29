# Quick Start: Using Social Features

## 🚀 Integration Checklist

### 1. Replace PostCard with EnhancedPostCard

**Before:**
```swift
PostCard(post: post)
```

**After:**
```swift
EnhancedPostCard(post: post, isUserPost: isOwnPost)
    .environmentObject(userService)
```

### 2. Initialize Services in Your App

In your main app file or ContentView:

```swift
struct ContentView: View {
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var repostService = RepostService.shared
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService()
    
    var body: some View {
        TabView {
            // Your views
        }
        .task {
            // Start listening for real-time updates
            savedPostsService.startListening()
            repostService.startListening()
        }
        .environmentObject(userService)
    }
}
```

---

## 📝 Common Use Cases

### Add Comments to a Post

```swift
// Show comments view
.sheet(isPresented: $showComments) {
    CommentsView(post: post)
        .environmentObject(userService)
}
```

The CommentsView handles:
- ✅ Loading all comments and replies
- ✅ Adding new comments
- ✅ Replying to comments
- ✅ Amenning comments
- ✅ Deleting own comments
- ✅ Real-time updates

### Save/Unsave a Post

```swift
Button {
    Task {
        try await SavedPostsService.shared.toggleSave(
            postId: post.id.uuidString
        )
    }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
}
```

Check if saved:
```swift
.task {
    isSaved = await SavedPostsService.shared.isPostSaved(
        postId: post.id.uuidString
    )
}
```

### Repost a Post

Simple repost:
```swift
Button("Repost") {
    Task {
        try await RepostService.shared.repost(
            postId: post.id.uuidString
        )
    }
}
```

Quote repost (with comment):
```swift
Button("Quote Repost") {
    showQuoteRepost = true
}

.sheet(isPresented: $showQuoteRepost) {
    QuoteRepostView(post: post)
}
```

Check if reposted:
```swift
.task {
    hasReposted = await RepostService.shared.hasReposted(
        postId: post.id.uuidString
    )
}
```

---

## 💾 Display Saved Posts

Create a SavedPostsView:

```swift
struct SavedPostsView: View {
    @StateObject private var savedPostsService = SavedPostsService.shared
    @State private var posts: [Post] = []
    @State private var selectedCollection = "All"
    
    var body: some View {
        VStack {
            // Collection selector
            Picker("Collection", selection: $selectedCollection) {
                ForEach(savedPostsService.collections, id: \.self) { collection in
                    Text(collection).tag(collection)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Posts list
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        EnhancedPostCard(post: post)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Saved Posts")
        .task {
            await loadPosts()
        }
        .onChange(of: selectedCollection) { _, _ in
            Task {
                await loadPosts()
            }
        }
    }
    
    private func loadPosts() async {
        do {
            posts = try await savedPostsService.fetchSavedPostObjects(
                collection: selectedCollection == "All" ? nil : selectedCollection
            )
        } catch {
            print("Error loading saved posts: \(error)")
        }
    }
}
```

---

## 📱 Collection Management

### Create a Collection

```swift
Button("New Collection") {
    showCreateCollection = true
}

.sheet(isPresented: $showCreateCollection) {
    CreateCollectionView(postId: post.id.uuidString)
}
```

### Move Post to Collection

```swift
Menu {
    ForEach(savedPostsService.collections, id: \.self) { collection in
        Button("Move to \(collection)") {
            Task {
                try await savedPostsService.moveToCollection(
                    postId: post.id.uuidString,
                    newCollection: collection
                )
            }
        }
    }
} label: {
    Label("Move to Collection", systemImage: "folder")
}
```

---

## 💬 Working with Comments

### Fetch Comments for a Post

```swift
@StateObject private var commentService = CommentService.shared
@State private var comments: [CommentWithReplies] = []

var body: some View {
    VStack {
        // Your UI
    }
    .task {
        comments = try await commentService.fetchCommentsWithReplies(
            for: post.id.uuidString
        )
    }
}
```

### Add a Comment

```swift
Button("Post Comment") {
    Task {
        let comment = try await commentService.addComment(
            postId: post.id.uuidString,
            content: commentText
        )
    }
}
```

### Add a Reply

```swift
Button("Reply") {
    Task {
        let reply = try await commentService.addReply(
            postId: post.id.uuidString,
            parentCommentId: comment.id ?? "",
            content: replyText
        )
    }
}
```

### Real-time Comment Updates

```swift
.task {
    commentService.startListening(to: post.id.uuidString)
}
.onDisappear {
    commentService.stopListening()
}
```

---

## 🔔 Getting Counts

### Saved Posts Count

```swift
let count = try await SavedPostsService.shared.getSavedPostCount()
```

### Repost Count

```swift
let count = try await RepostService.shared.getRepostCount(
    for: post.id.uuidString
)
```

### Who Reposted

```swift
let reposts = try await RepostService.shared.fetchRepostsForPost(
    postId: post.id.uuidString
)

ForEach(reposts) { repost in
    Text("@\(repost.userId) reposted")
}
```

---

## 🎨 UI Patterns

### Action Button with Count

```swift
Button {
    // Action
} label: {
    HStack(spacing: 4) {
        Image(systemName: icon)
        if count > 0 {
            Text("\(count)")
                .contentTransition(.numericText())
        }
    }
    .foregroundStyle(isActive ? .blue : .secondary)
}
```

### Save with Collection Options

```swift
Menu {
    Button("Save to All") {
        Task {
            try await savedPostsService.savePost(postId: postId)
        }
    }
    
    Divider()
    
    ForEach(collections, id: \.self) { collection in
        Button("Save to \(collection)") {
            Task {
                try await savedPostsService.savePost(
                    postId: postId,
                    collection: collection
                )
            }
        }
    }
    
    Divider()
    
    Button("New Collection...") {
        showCreateCollection = true
    }
} label: {
    Label("Save", systemImage: "bookmark")
}
```

### Repost Menu

```swift
Menu {
    Button {
        Task {
            try await repostService.repost(postId: postId)
        }
    } label: {
        Label("Repost", systemImage: "arrow.2.squarepath")
    }
    
    Button {
        showQuoteRepost = true
    } label: {
        Label("Quote Repost", systemImage: "quote.bubble")
    }
    
    if hasReposted {
        Divider()
        
        Button(role: .destructive) {
            Task {
                try await repostService.unrepost(postId: postId)
            }
        } label: {
            Label("Unrepost", systemImage: "arrow.uturn.backward")
        }
    }
} label: {
    Image(systemName: "arrow.2.squarepath")
}
```

---

## ⚡️ Performance Tips

1. **Use Local Caching**: Services maintain local state for quick lookups
   ```swift
   // O(1) lookup instead of async Firestore query
   if savedPostsService.savedPostIds.contains(postId) {
       // Post is saved
   }
   ```

2. **Real-time Listeners**: Only activate when needed
   ```swift
   .task {
       service.startListening()
   }
   .onDisappear {
       service.stopListening()
   }
   ```

3. **Batch Operations**: Services use Firestore batch writes for atomicity

4. **Pagination**: For large lists, implement pagination
   ```swift
   func loadMore() async {
       // Load next batch
   }
   ```

---

## 🐛 Debugging

Enable detailed logging:

```swift
// All services log with emoji prefixes:
// 💬 CommentService
// 💾 SavedPostsService
// 🔄 RepostService

// Look for these in console:
// ✅ Success
// ❌ Error
// ⚠️ Warning
// 📥 Fetching
// 📤 Saving
```

Check Firestore in Firebase Console:
- `/comments` - All comments
- `/savedPosts` - Saved posts tracking
- `/reposts` - Repost tracking

---

## 🔐 Security

All services respect Firestore security rules:
- Users can only modify their own data
- Comments are public (readable by all)
- Saved posts are private
- Reposts are public

---

## 📊 Analytics

Track engagement:

```swift
// Track when users interact
Button("Save") {
    Task {
        try await savedPostsService.savePost(postId: postId)
        
        // Analytics
        Analytics.logEvent("post_saved", parameters: [
            "post_id": postId,
            "category": post.category.rawValue
        ])
    }
}
```

---

## 🎯 Next Steps

1. ✅ Replace all PostCard instances with EnhancedPostCard
2. ✅ Add CommentsView to your navigation
3. ✅ Create SavedPostsView
4. ✅ Test all features in simulator
5. ✅ Deploy Firestore indexes
6. ✅ Update security rules
7. ✅ Test on device
8. ✅ Submit to TestFlight

---

## 🆘 Common Issues

**Issue**: Comments not showing
- **Solution**: Check Firestore indexes, ensure listener is started

**Issue**: Saved state not updating
- **Solution**: Call `startListening()` in `.task` modifier

**Issue**: Repost creates duplicate
- **Solution**: Check for existing repost before creating new one

**Issue**: Counts not updating
- **Solution**: Use `.contentTransition(.numericText())` for smooth updates

---

## 📚 Additional Resources

- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [SwiftUI Animations](https://developer.apple.com/documentation/swiftui/animations)
- [SOCIAL_FEATURES_IMPLEMENTATION.md](./SOCIAL_FEATURES_IMPLEMENTATION.md) - Full technical docs

---

**You're all set! 🎉**

Your app now has full social features with comments, saved posts, and reposts, all powered by Firestore.
