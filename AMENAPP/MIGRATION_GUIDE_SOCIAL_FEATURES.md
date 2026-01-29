# Migration Guide: Adding Social Features

## Overview

This guide will help you integrate the new social features (comments, saved posts, reposts) into your existing AMENAPP codebase.

---

## Step 1: Add New Files to Xcode

Add these new files to your Xcode project:

### Models
- ✅ `PostInteractionModels.swift` - Comment, SavedPost, Repost models

### Services
- ✅ `CommentService.swift` - Comment and reply management
- ✅ `SavedPostsService.swift` - Save posts and collections
- ✅ `RepostService.swift` - Repost functionality

### Views
- ✅ `CommentsView.swift` - Full comment UI with replies
- ✅ `EnhancedPostCard.swift` - Updated PostCard with all features

### Documentation
- ✅ `SOCIAL_FEATURES_IMPLEMENTATION.md` - Technical documentation
- ✅ `QUICK_START_SOCIAL_FEATURES.md` - Quick reference guide

---

## Step 2: Update FirebaseManager.swift

Add new collection paths (already done):

```swift
extension FirebaseManager {
    enum CollectionPath {
        static let users = "users"
        static let posts = "posts"
        static let testimonies = "testimonies"
        static let prayers = "prayers"
        static let comments = "comments"  // ✅ Already exists
        static let messages = "messages"
        static let notifications = "notifications"
        static let follows = "follows"
        static let savedPosts = "savedPosts"  // ✅ NEW
        static let reposts = "reposts"  // ✅ NEW
    }
}
```

---

## Step 3: Update Firestore Security Rules

Replace your `firestore.rules` with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }
    
    // Users
    match /users/{userId} {
      allow read: if true;
      allow create: if isOwner(userId);
      allow update, delete: if isOwner(userId);
    }
    
    // Posts
    match /posts/{postId} {
      allow read: if true;
      allow create: if isSignedIn() 
        && request.resource.data.authorId == request.auth.uid;
      allow update: if isSignedIn()
        && (resource.data.authorId == request.auth.uid 
            || request.resource.data.keys().hasOnly(['amenCount', 'lightbulbCount', 'commentCount', 'repostCount', 'amenUserIds', 'lightbulbUserIds', 'updatedAt']));
      allow delete: if isSignedIn()
        && resource.data.authorId == request.auth.uid;
    }
    
    // Comments - NEW
    match /comments/{commentId} {
      allow read: if true;
      allow create: if isSignedIn()
        && request.resource.data.authorId == request.auth.uid;
      allow update: if isSignedIn()
        && (resource.data.authorId == request.auth.uid
            || request.resource.data.keys().hasOnly(['amenCount', 'replyCount', 'amenUserIds', 'updatedAt']));
      allow delete: if isSignedIn()
        && resource.data.authorId == request.auth.uid;
    }
    
    // Saved Posts - NEW
    match /savedPosts/{savedPostId} {
      allow read: if isSignedIn()
        && resource.data.userId == request.auth.uid;
      allow create: if isSignedIn()
        && request.resource.data.userId == request.auth.uid;
      allow update, delete: if isSignedIn()
        && resource.data.userId == request.auth.uid;
    }
    
    // Reposts - NEW
    match /reposts/{repostId} {
      allow read: if true;
      allow create: if isSignedIn()
        && request.resource.data.userId == request.auth.uid;
      allow delete: if isSignedIn()
        && resource.data.userId == request.auth.uid;
    }
    
    // Follows
    match /follows/{followId} {
      allow read: if true;
      allow create: if isSignedIn()
        && request.resource.data.followerId == request.auth.uid;
      allow delete: if isSignedIn()
        && resource.data.followerId == request.auth.uid;
    }
    
    // Notifications
    match /notifications/{notificationId} {
      allow read: if isSignedIn()
        && resource.data.userId == request.auth.uid;
      allow create: if isSignedIn();
      allow update, delete: if isSignedIn()
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## Step 4: Create Firestore Indexes

Go to Firebase Console > Firestore > Indexes and create these composite indexes:

### Comments
1. Collection: `comments`
   - `postId` (Ascending)
   - `parentCommentId` (Ascending)
   - `createdAt` (Ascending)

2. Collection: `comments`
   - `postId` (Ascending)
   - `createdAt` (Descending)

3. Collection: `comments`
   - `parentCommentId` (Ascending)
   - `createdAt` (Ascending)

### Saved Posts
1. Collection: `savedPosts`
   - `userId` (Ascending)
   - `savedAt` (Descending)

2. Collection: `savedPosts`
   - `userId` (Ascending)
   - `collectionName` (Ascending)
   - `savedAt` (Descending)

### Reposts
1. Collection: `reposts`
   - `userId` (Ascending)
   - `repostedAt` (Descending)

2. Collection: `reposts`
   - `originalPostId` (Ascending)
   - `repostedAt` (Descending)

**Tip**: You can also let Firestore auto-create indexes when you see errors in the console.

---

## Step 5: Update ContentView or Main App

Initialize the new services:

```swift
import SwiftUI

@main
struct AMENAPPApp: App {
    init() {
        // Configure Firebase (if not already done)
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var userService = UserService()
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var repostService = RepostService.shared
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
                    .environmentObject(userService)
                    .task {
                        // Fetch current user
                        await userService.fetchCurrentUser()
                        
                        // Start real-time listeners
                        savedPostsService.startListening()
                        repostService.startListening()
                    }
            } else {
                SignInView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
```

---

## Step 6: Update Existing Views

### A. Replace PostCard with EnhancedPostCard

**Find all instances of:**
```swift
PostCard(post: post)
```

**Replace with:**
```swift
EnhancedPostCard(post: post, isUserPost: isOwnPost)
    .environmentObject(userService)
```

**Or keep using PostCard and add a bookmark button:**

```swift
// In PostCard.swift, find the save/bookmark button and update it:

@StateObject private var savedPostsService = SavedPostsService.shared
@State private var isSaved = false

// In the button:
Button {
    Task {
        try await savedPostsService.toggleSave(postId: post?.id.uuidString ?? "")
    }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
        .foregroundStyle(isSaved ? .blue : .black.opacity(0.5))
}
.task {
    if let postId = post?.id.uuidString {
        isSaved = await savedPostsService.isPostSaved(postId: postId)
    }
}
.onChange(of: savedPostsService.savedPostIds) { _, _ in
    if let postId = post?.id.uuidString {
        isSaved = savedPostsService.savedPostIds.contains(postId)
    }
}
```

### B. Add Comments Button

In your PostCard, find the comments button and update the action:

```swift
@State private var showComments = false

// Comments button
Button {
    showComments = true
} label: {
    HStack {
        Image(systemName: "bubble.left.fill")
        Text("\(post.commentCount)")
    }
}

// Add sheet
.sheet(isPresented: $showComments) {
    if let post = post {
        CommentsView(post: post)
            .environmentObject(userService)
    }
}
```

### C. Add Repost Menu

Update the repost button to show a menu:

```swift
@StateObject private var repostService = RepostService.shared
@State private var hasReposted = false
@State private var showQuoteRepost = false

Menu {
    Button {
        Task {
            if hasReposted {
                try await repostService.unrepost(postId: post.id.uuidString)
            } else {
                try await repostService.repost(postId: post.id.uuidString)
            }
        }
    } label: {
        Label(hasReposted ? "Unrepost" : "Repost", 
              systemImage: "arrow.2.squarepath")
    }
    
    Button {
        showQuoteRepost = true
    } label: {
        Label("Quote Repost", systemImage: "quote.bubble")
    }
} label: {
    HStack {
        Image(systemName: "arrow.2.squarepath")
        if post.repostCount > 0 {
            Text("\(post.repostCount)")
        }
    }
    .foregroundStyle(hasReposted ? .green : .black.opacity(0.5))
}

.task {
    hasReposted = await repostService.hasReposted(postId: post.id.uuidString)
}
.sheet(isPresented: $showQuoteRepost) {
    QuoteRepostView(post: post)
}
```

---

## Step 7: Add Saved Posts View

Create a new view for saved posts:

```swift
struct SavedPostsView: View {
    @StateObject private var savedPostsService = SavedPostsService.shared
    @EnvironmentObject var userService: UserService
    
    @State private var posts: [Post] = []
    @State private var selectedCollection = "All"
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Collection picker
                if savedPostsService.collections.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(savedPostsService.collections, id: \.self) { collection in
                                Button {
                                    selectedCollection = collection
                                } label: {
                                    Text(collection)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(selectedCollection == collection ? .white : .black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedCollection == collection ? Color.black : Color(.systemGray6))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    
                    Divider()
                }
                
                // Posts list
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if posts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.black.opacity(0.3))
                        
                        Text("No saved posts")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                        
                        Text("Posts you save will appear here")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(posts) { post in
                                EnhancedPostCard(post: post)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Saved Posts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            // Create new collection
                        } label: {
                            Label("New Collection", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadPosts()
        }
        .onChange(of: selectedCollection) { _, _ in
            Task { await loadPosts() }
        }
    }
    
    private func loadPosts() async {
        isLoading = true
        do {
            posts = try await savedPostsService.fetchSavedPostObjects(
                collection: selectedCollection == "All" ? nil : selectedCollection
            )
        } catch {
            print("Error loading saved posts: \(error)")
        }
        isLoading = false
    }
}
```

### Add to Tab Bar

```swift
TabView {
    // ... existing tabs
    
    SavedPostsView()
        .tabItem {
            Label("Saved", systemImage: "bookmark")
        }
}
```

---

## Step 8: Update Post Creation

In your `CreatePostView`, ensure the post is properly created with all fields:

```swift
// This is already handled by FirebasePostService.createPost()
// No changes needed if you're using PostsManager
```

---

## Step 9: Test Everything

### Test Comments
1. ✅ Create a post
2. ✅ Add a comment
3. ✅ Reply to the comment
4. ✅ Amen a comment
5. ✅ Delete a comment (and verify replies are deleted)
6. ✅ Check real-time updates

### Test Saved Posts
1. ✅ Save a post
2. ✅ View saved posts
3. ✅ Create a collection
4. ✅ Save post to collection
5. ✅ Move post between collections
6. ✅ Unsave a post
7. ✅ Check bookmark icon updates instantly

### Test Reposts
1. ✅ Repost a post
2. ✅ Create a quote repost
3. ✅ View repost count increment
4. ✅ Unrepost
5. ✅ Check repost count decrement
6. ✅ Verify original post link

---

## Step 10: Deploy

1. **Update Firestore Rules** in Firebase Console
2. **Create Indexes** (or wait for auto-creation)
3. **Test in Simulator**
4. **Test on Device**
5. **Submit to TestFlight**

---

## Troubleshooting

### Issue: "Missing index" error

**Solution**: Firebase will show a link in the console. Click it to auto-create the index, or manually create it in Firebase Console.

### Issue: Comments not showing

**Solution**: 
- Check Firestore rules are updated
- Verify indexes are created
- Check console for errors
- Ensure `startListening()` is called

### Issue: Saved state not updating

**Solution**:
- Ensure `savedPostsService.startListening()` is called in `.task`
- Check `.onChange(of: savedPostsService.savedPostIds)`

### Issue: Repost creates duplicate

**Solution**:
- The service automatically checks for existing reposts
- If you see duplicates, check the `hasReposted()` logic

### Issue: Counts not animating

**Solution**:
- Use `.contentTransition(.numericText())` on Text views with counts
- Add `.animation(.easeInOut, value: count)` if needed

---

## Optional Enhancements

### 1. Add Pull-to-Refresh

```swift
.refreshable {
    await loadPosts()
}
```

### 2. Add Search to Saved Posts

```swift
@State private var searchText = ""

.searchable(text: $searchText)
```

### 3. Add Analytics

```swift
// Track user engagement
Analytics.logEvent("comment_added", parameters: ["post_id": postId])
Analytics.logEvent("post_saved", parameters: ["collection": collection])
Analytics.logEvent("post_reposted", parameters: ["is_quote": withComment != nil])
```

### 4. Add Notifications Badge

```swift
// Show unread comment count
TabView {
    // ...
}
.badge(unreadCommentCount)
```

---

## Migration Complete! 🎉

Your app now has:
- ✅ Full comment system with nested replies
- ✅ Save posts with custom collections
- ✅ Repost and quote repost functionality
- ✅ Real-time updates across all features
- ✅ Proper error handling and user feedback

**Next**: Test thoroughly and deploy to TestFlight!

---

## Need Help?

Refer to:
- `SOCIAL_FEATURES_IMPLEMENTATION.md` - Full technical documentation
- `QUICK_START_SOCIAL_FEATURES.md` - Quick reference guide
- Firebase Console - Check Firestore data directly
- Xcode Console - Look for emoji-prefixed logs (💬, 💾, 🔄)
