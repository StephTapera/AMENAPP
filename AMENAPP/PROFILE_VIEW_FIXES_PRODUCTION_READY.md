# ProfileView.swift - Production-Ready Fixes

## Overview
This document outlines the fixes needed to make ProfileView production-ready with:
1. ✅ Compact, Threads-inspired post cards
2. ✅ Real-time updates with listeners
3. ✅ Posts persisting after creation
4. ✅ Replies showing correctly
5. ✅ Saved posts displaying
6. ✅ Reposts displaying

---

## TASK 1: Make Post Cards Compact (Threads-Style)

### Location: Lines 1348-1470 (`ProfilePostCard`)

### Problem
- Cards are too big with excessive padding (16px all around)
- Bulky interaction bar with capsule background
- Too much spacing between elements (12px)

### Solution: Replace ProfilePostCard body with Threads-inspired design

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        // COMPACT HEADER: Time + Menu (Threads-style)
        HStack(alignment: .center, spacing: 8) {
            Text(post.timeAgo)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        
        // CONTENT: Post text (Threads-style line spacing)
        Text(post.content)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(.primary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        
        // COMPACT INTERACTIONS: Inline buttons (Threads-style)
        HStack(spacing: 16) {
            // Amen/Lightbulb button
            if post.category == .openTable {
                compactButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: lightbulbCount,
                    isActive: hasLitLightbulb
                ) {
                    toggleLightbulb()
                }
            } else {
                compactButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: amenCount,
                    isActive: hasSaidAmen
                ) {
                    toggleAmen()
                }
            }
            
            // Comment button
            compactButton(
                icon: "bubble.left",
                count: commentCount,
                isActive: false
            ) {
                showCommentsSheet = true
            }
        }
        .padding(.top, 4)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.white)
    .overlay(
        // Subtle divider (Threads-style)
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5),
        alignment: .bottom
    )
    .sheet(isPresented: $showingEditSheet) {
        EditPostSheet(post: post)
    }
    .sheet(isPresented: $showCommentsSheet) {
        CommentsView(post: post)
    }
    .alert("Delete Post", isPresented: $showingDeleteAlert) {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            deletePost()
        }
    } message: {
        Text("Are you sure you want to delete this post? This action cannot be undone.")
    }
    .task {
        await loadInteractions()
    }
}

// ADD THIS NEW COMPACT BUTTON HELPER (after body)
@ViewBuilder
private func compactButton(icon: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isActive ? .black : .secondary)
            
            if count > 0 {
                Text("\(count)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### DELETE THESE OLD METHODS
- `private var headerView`
- `private var contentView`
- `private var interactionBar`
- `private var interactionBarBackground`
- `private func interactionButton(...)` 
- `private var cardBackground`

---

## TASK 2: Fix Real-Time Updates (Posts Not Staying)

### Location: Lines 710-750 (`setupRealtimeDatabaseListeners`)

### Problem
Current listener setup observes posts but may not update state correctly

### Solution: Enhanced listener with proper state updates

```swift
@MainActor
private func setupRealtimeDatabaseListeners(userId: String) {
    print("🔥 Setting up Realtime Database listeners for profile data...")
    
    // 1. Listen to user's posts in real-time with enhanced handling
    RealtimePostService.shared.observeUserPosts(userId: userId) { [weak self] posts in
        guard let self = self else { return }
        Task { @MainActor in
            // Sort by newest first
            self.userPosts = posts.sorted { $0.createdAt > $1.createdAt }
            print("🔄 Real-time update: \(posts.count) posts (sorted by newest)")
            
            // Haptic feedback for new posts
            if posts.count > self.userPosts.count {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        }
    }
    
    // 2. Listen to saved posts in real-time
    RealtimeSavedPostsService.shared.observeSavedPosts { [weak self] postIds in
        guard let self = self else { return }
        Task {
            do {
                let posts = try await RealtimeSavedPostsService.shared.fetchSavedPosts()
                await MainActor.run {
                    self.savedPosts = posts.sorted { $0.createdAt > $1.createdAt }
                    print("🔄 Real-time update: \(posts.count) saved posts")
                }
            } catch {
                print("❌ Error fetching saved posts details: \(error)")
            }
        }
    }
    
    // 3. Listen to user's reposts in real-time
    RealtimeRepostsService.shared.observeUserReposts(userId: userId) { [weak self] posts in
        guard let self = self else { return }
        Task { @MainActor in
            self.reposts = posts.sorted { $0.createdAt > $1.createdAt }
            print("🔄 Real-time update: \(posts.count) reposts")
        }
    }
    
    // 4. Listen to user's comments/replies in real-time
    Task { [weak self] in
        guard let self = self else { return }
        // Set up periodic refresh for comments (every 30 seconds)
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                do {
                    let comments = try await AMENAPP.RealtimeCommentsService.shared.fetchUserComments(userId: userId)
                    await MainActor.run {
                        self.userReplies = comments.sorted { $0.createdAt > $1.createdAt }
                        print("🔄 Comments refreshed: \(comments.count) replies")
                    }
                } catch {
                    print("❌ Error fetching user comments: \(error)")
                }
            }
        }
    }
    
    print("✅ Realtime Database listeners set up successfully")
}
```

---

## TASK 3: Fix Replies Not Showing

### Location: Lines 1702-1750 (`RepliesContentView`)

### Problem
Replies might be loading but not displaying correctly due to empty state or missing UI

### Current Code Issue
Check if `userReplies` is actually populated by adding debug logging

### Solution: Enhanced RepliesContentView with better loading states

```swift
struct RepliesContentView: View {
    @Binding var replies: [AMENAPP.Comment]
    @State private var selectedUserId: String?
    @State private var showUserProfile = false
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if replies.isEmpty {
                // Empty state with debug info
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No replies yet")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text("Your comments will appear here")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    // DEBUG: Show if data exists
                    Text("DEBUG: \(replies.count) replies loaded")
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else {
                // Show replies in compact list
                LazyVStack(spacing: 0) {
                    ForEach(replies) { reply in
                        CompactReplyCard(reply: reply)
                            .onTapGesture {
                                // Navigate to original post
                                print("🔗 Tapped reply: \(reply.id ?? "unknown")")
                            }
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            print("📱 RepliesContentView appeared with \(replies.count) replies")
        }
    }
}

// NEW: Compact reply card (Threads-style)
struct CompactReplyCard: View {
    let reply: AMENAPP.Comment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Time
            Text(reply.createdAt.timeAgoDisplay())
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
            
            // Content
            Text(reply.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(3)
            
            // Interaction count
            if reply.amenCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text("\(reply.amenCount)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
```

---

## TASK 4: Fix Saved Posts Not Showing

### Location: Lines 1750-1800 (`SavedContentView`)

### Problem
Saved posts might not be loading from Realtime Database correctly

### Solution: Enhanced SavedContentView with proper error handling

```swift
struct SavedContentView: View {
    @Binding var savedPosts: [Post]
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Error Loading Saved Posts")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Retry") {
                        Task {
                            await reloadSavedPosts()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 80)
            } else if savedPosts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No saved posts")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("Posts you save will appear here")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    // DEBUG
                    Text("DEBUG: \(savedPosts.count) saved posts")
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else {
                // Show saved posts
                LazyVStack(spacing: 0) {
                    ForEach(savedPosts) { post in
                        ProfilePostCard(post: post)
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            print("📱 SavedContentView appeared with \(savedPosts.count) posts")
            // Force reload on appear
            Task {
                await reloadSavedPosts()
            }
        }
    }
    
    private func reloadSavedPosts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let posts = try await RealtimeSavedPostsService.shared.fetchSavedPosts()
            await MainActor.run {
                savedPosts = posts.sorted { $0.createdAt > $1.createdAt }
                print("✅ Saved posts reloaded: \(posts.count)")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                print("❌ Error loading saved posts: \(error)")
            }
        }
        
        isLoading = false
    }
}
```

---

## TASK 5: Fix Reposts Not Showing

### Location: Lines 1800-1850 (`RepostsContentView`)

### Problem
Reposts might not be fetching correctly from Realtime Database

### Solution: Enhanced RepostsContentView

```swift
struct RepostsContentView: View {
    @Binding var reposts: [Post]
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let error = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Error Loading Reposts")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Retry") {
                        Task {
                            await reloadReposts()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 80)
            } else if reposts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No reposts")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("Posts you repost will appear here")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    // DEBUG
                    Text("DEBUG: \(reposts.count) reposts")
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else {
                // Show reposts
                LazyVStack(spacing: 0) {
                    ForEach(reposts) { post in
                        VStack(alignment: .leading, spacing: 4) {
                            // Repost indicator
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Text("You reposted")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            
                            ProfilePostCard(post: post)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            print("📱 RepostsContentView appeared with \(reposts.count) reposts")
            // Force reload on appear
            Task {
                await reloadReposts()
            }
        }
    }
    
    private func reloadReposts() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let posts = try await RealtimeRepostsService.shared.fetchUserReposts(userId: userId)
            await MainActor.run {
                reposts = posts.sorted { $0.createdAt > $1.createdAt }
                print("✅ Reposts reloaded: \(posts.count)")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                print("❌ Error loading reposts: \(error)")
            }
        }
        
        isLoading = false
    }
}
```

---

## ADDITIONAL FIX: Ensure Posts Persist After Creation

### Location: Lines 250-350 (Notification Observers)

### Current Implementation is CORRECT ✅
The notification observers are already set up to handle new posts:
- `newPostObserver` adds new posts to `userPosts`
- `postSavedObserver` adds to `savedPosts`
- `postRepostedObserver` adds to `reposts`

### Verify Post Creation Flow
Make sure `CreatePostView` (or whatever creates posts) calls:
```swift
NotificationCenter.default.post(
    name: NSNotification.Name("NewPostCreated"),
    object: nil,
    userInfo: ["post": newPost]
)
```

---

## TESTING CHECKLIST

After implementing these fixes, test:

1. **Compact Cards** ✅
   - [ ] Posts are visually smaller (less padding)
   - [ ] Interactions are inline, not in a capsule
   - [ ] Divider lines appear between posts

2. **Real-Time Updates** ✅
   - [ ] Create a new post → it appears immediately in Posts tab
   - [ ] Posts persist when switching tabs
   - [ ] Counts update in real-time

3. **Replies** ✅
   - [ ] Comment on a post → appears in Replies tab
   - [ ] Replies show correct content and time
   - [ ] Empty state shows when no replies

4. **Saved Posts** ✅
   - [ ] Save a post → appears in Saved tab
   - [ ] Unsave removes it from Saved tab
   - [ ] Saved posts persist across app restarts

5. **Reposts** ✅
   - [ ] Repost a post → appears in Reposts tab
   - [ ] Shows "You reposted" indicator
   - [ ] Remove repost updates the tab

---

## IMPLEMENTATION ORDER

1. **Start with Task 1 (Compact Cards)** - Visual improvement, easier to test
2. **Then Task 2 (Real-Time)** - Foundation for other features
3. **Tasks 3-5 (Replies, Saved, Reposts)** - Fix data display issues

This ensures each fix builds on the previous one and makes debugging easier.
