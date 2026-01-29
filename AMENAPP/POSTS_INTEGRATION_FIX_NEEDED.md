# Posts Integration Fix Needed

## Current Problem

**Posts are NOT being saved or shared between Testimonies and Prayer views!**

Both `TestimoniesView` and `PrayerView` are using **hardcoded sample data** instead of the centralized `PostsManager`.

### What's Wrong:

1. **TestimoniesView.swift**
   - Uses `sampleTestimonies` array (hardcoded)
   - Has `PostsManager.shared` but doesn't use it
   - Uses custom `TestimonyPost` model instead of unified `Post` model
   - Delete/Edit/Repost functions just print to console

2. **PrayerView.swift**
   - Uses `prayerWallPosts` array (hardcoded)
   - Doesn't use `PostsManager` at all
   - Uses custom `PrayerWallPost` model instead of unified `Post` model

3. **PostsManager.swift** (The RIGHT way - already implemented!)
   - ✅ Has `testimoniesPosts: [Post]` array
   - ✅ Has `prayerPosts: [Post]` array  
   - ✅ Has `createPost()` method that saves to Firebase
   - ✅ Has `deletePost()`, `editPost()`, `repostToProfile()` methods
   - ✅ Syncs with Firebase in real-time
   - ✅ Posts notifications when posts are created/edited/deleted

---

## How to Fix This

### Step 1: Update TestimoniesView.swift

#### Change the filteredPosts computed property:

```swift
// OLD - Uses sample data
var filteredPosts: [TestimonyPost] {
    var posts = sampleTestimonies  // ❌ WRONG
    // ...
}

// NEW - Uses PostsManager
var filteredPosts: [Post] {
    var posts = postsManager.testimoniesPosts  // ✅ CORRECT
    
    // Filter by category if selected
    if let category = selectedCategory {
        posts = posts.filter { post in
            post.topicTag?.lowercased() == category.title.lowercased() ||
            post.content.lowercased().contains(category.title.lowercased())
        }
    }
    
    // Apply additional filters
    switch selectedFilter {
    case .all:
        return posts
    case .recent:
        return posts.sorted { $0.createdAt > $1.createdAt }
    case .popular:
        return posts.sorted { $0.amenCount + $0.commentCount > $1.amenCount + $1.commentCount }
    case .following:
        return posts  // TODO: Filter by following
    }
}
```

#### Update the ForEach to use PostCard:

```swift
// OLD - Uses custom TestimonyPostCard
ForEach(filteredPosts) { post in
    TestimonyPostCard(
        post: post,
        onDelete: { deletePost(post) },
        onEdit: { editPost(post) },
        onRepost: { repostPost(post) }
    )
}

// NEW - Uses unified PostCard
ForEach(filteredPosts) { post in
    PostCard(
        authorName: post.authorName,
        authorInitials: post.authorInitials,
        timeAgo: post.timeAgo,
        content: post.content,
        category: .testimonies,
        amenCount: post.amenCount,
        commentCount: post.commentCount,
        onDelete: {
            postsManager.deletePost(postId: post.id)
        }
    )
}
```

#### Update the delete/edit/repost functions:

```swift
// OLD - Just prints to console
private func deletePost(_ post: TestimonyPost) {
    print("🗑️ Deleting post: \(post.id)")
}

// NEW - Actually deletes from PostsManager
private func deletePost(_ post: Post) {
    postsManager.deletePost(postId: post.id)
}

private func editPost(_ post: Post, newContent: String) {
    postsManager.editPost(postId: post.id, newContent: newContent)
}

private func repostPost(_ post: Post) {
    postsManager.repostToProfile(originalPost: post)
}
```

#### Update the notification handler:

```swift
.onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
    // OLD - Just plays haptic
    if let userInfo = notification.userInfo,
       let category = userInfo["category"] as? String,
       category == Post.PostCategory.testimonies.rawValue {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

// NEW - Refresh posts from PostsManager
.onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
    Task {
        await postsManager.refreshPosts()
    }
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.success)
}
```

---

### Step 2: Update PrayerView.swift

Same changes as above, but:
- Use `postsManager.prayerPosts` instead of `prayerWallPosts`
- Use `Post` model instead of `PrayerWallPost`
- Use `PostCard` with `category: .prayer`

---

### Step 3: Ensure Post Creation Works

When creating a post in `CreatePostSheet`, make sure it's calling:

```swift
PostsManager.shared.createPost(
    content: postContent,
    category: .testimonies,  // or .prayer
    topicTag: selectedCategory?.title,
    visibility: .everyone,
    allowComments: true
)
```

This will:
1. ✅ Save to Firebase
2. ✅ Post `NotificationCenter` notification
3. ✅ Update all views listening to `PostsManager.shared`
4. ✅ Show in both Testimonies and Prayer views (based on category)

---

## Benefits After Fix

✅ **Unified Post Model** - One `Post` struct for all categories  
✅ **Real Firebase Integration** - Posts persist across app launches  
✅ **Real-time Updates** - All views sync automatically  
✅ **Proper CRUD Operations** - Create, Read, Update, Delete all work  
✅ **Cross-View Sharing** - Posts created in one view show in others  
✅ **Repost Functionality** - Users can repost to their profile  
✅ **Edit & Delete** - Full post management

---

## Testing After Fix

1. Create a testimony post → Should appear in TestimoniesView
2. Create a prayer request → Should appear in PrayerView
3. Delete a post → Should disappear from view immediately
4. Edit a post → Should update content in real-time
5. Repost → Should create new post on user's profile
6. Close and reopen app → Posts should persist (from Firebase)

---

## Current Status

- ❌ TestimoniesView uses sample data
- ❌ PrayerView uses sample data
- ✅ PostsManager has all the right functionality (just not being used!)
- ✅ Firebase integration works (already implemented)
- ✅ Real-time listeners work (already implemented)

**The infrastructure is already built - views just need to be connected to it!**
