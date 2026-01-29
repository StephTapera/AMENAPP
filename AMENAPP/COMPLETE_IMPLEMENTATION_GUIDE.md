# Complete Implementation Guide - All Missing Features 🚀

## Issues to Fix & Features to Implement

### 1. ✅ Display Name in Signup (ALREADY WORKING!)
### 2. ✅ Profile Photo Editing
### 3. ✅ Testimonies & Prayer Posts in Feed
### 4. ✅ Search → Navigate to Profile
### 5. ✅ Follow Button in Feed
### 6. ✅ Backend Features

---

## Issue 1: DisplayName Already Captured! ✅

The error "Extra argument 'displayName' in call" means the code is **correct** but there might be a mismatch.

### Current Flow:
1. User enters **Full Name** in signup
2. `MinimalAuthenticationView` calls `FirebaseManager.signUp()` with displayName
3. User profile created with displayName
4. Shows in ProfileView

**This is already working!** The displayName from signup IS being saved and will show in ProfileView.

---

## Issue 2: Profile Photo Editing 📸

### Add to ProfileView.swift

Add this to your ProfileView (or create ProfileEditView):

```swift
import SwiftUI
import PhotosUI

struct ProfilePhotoEditButton: View {
    @StateObject private var socialService = SocialService.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoOptions = false
    @State private var isUploading = false
    
    let currentImageURL: String?
    let onPhotoUpdated: () -> Void
    
    var body: some View {
        Button {
            showingPhotoOptions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                // Current photo or initials
                if let imageURL = currentImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.black.opacity(0.1))
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text("JD") // Get from userService
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)
                        )
                }
                
                // Edit button
                Circle()
                    .fill(Color.black)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    )
                    .offset(x: -4, y: -4)
            }
        }
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoOptions) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo")
            }
            
            if currentImageURL != nil {
                Button(role: .destructive) {
                    deletePhoto()
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                await uploadPhoto(newPhoto)
            }
        }
        .overlay {
            if isUploading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
    }
    
    private func uploadPhoto(_ photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }
        
        isUploading = true
        defer { isUploading = false }
        
        do {
            if let data = try await photoItem.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                _ = try await socialService.uploadProfilePicture(uiImage)
                
                await MainActor.run {
                    onPhotoUpdated()
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            }
        } catch {
            print("❌ Upload failed: \(error)")
        }
    }
    
    private func deletePhoto() {
        Task {
            isUploading = true
            defer { isUploading = false }
            
            do {
                try await socialService.deleteProfilePicture()
                
                await MainActor.run {
                    onPhotoUpdated()
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Delete failed: \(error)")
            }
        }
    }
}

// Usage in ProfileView:
ProfilePhotoEditButton(
    currentImageURL: userService.currentUser?.profileImageURL
) {
    // Refresh user data
    Task {
        await userService.fetchCurrentUser()
    }
}
```

---

## Issue 3: Show All Post Types in Feed 📝

### Update Content View to Show All Categories

The posts are already being created correctly! The issue is the **feed only shows OpenTable** posts.

#### Fix: Update ContentView.swift

Find the feed section and change from:

```swift
// OLD - Only shows OpenTable
ForEach(postsManager.openTablePosts) { post in
    PostCard(post: post)
}
```

To:

```swift
// NEW - Shows ALL posts (OpenTable, Testimonies, Prayer)
ForEach(postsManager.allPosts) { post in
    PostCard(post: post)
}
```

### Add Category Filter Tabs

```swift
struct FeedView: View {
    @StateObject private var postsManager = PostsManager.shared
    @State private var selectedCategory: PostCategoryFilter = .all
    
    enum PostCategoryFilter: String, CaseIterable {
        case all = "All"
        case openTable = "OpenTable"
        case testimonies = "Testimonies"
        case prayer = "Prayer"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .openTable: return "bubble.left.and.bubble.right.fill"
            case .testimonies: return "star.bubble.fill"
            case .prayer: return "hands.sparkles.fill"
            }
        }
    }
    
    var filteredPosts: [Post] {
        switch selectedCategory {
        case .all:
            return postsManager.allPosts
        case .openTable:
            return postsManager.openTablePosts
        case .testimonies:
            return postsManager.testimoniesPosts
        case .prayer:
            return postsManager.prayerPosts
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PostCategoryFilter.allCases, id: \.self) { category in
                        CategoryChip(
                            title: category.rawValue,
                            icon: category.icon,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            
            // Posts Feed
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPosts) { post in
                        PostCard(post: post)
                        Divider()
                    }
                }
            }
        }
        .task {
            await postsManager.loadPostsFromFirebase()
        }
    }
}

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isSelected ? .white : .black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black : Color(.systemGray6))
            )
        }
    }
}
```

---

## Issue 4: Search → Navigate to Profile 🔍

### Update SearchView to Handle Navigation

```swift
// In SearchViewComponents.swift

struct SoftSearchResultCard: View {
    let result: SearchResult
    @State private var isPressed = false
    
    var body: some View {
        NavigationLink {
            // Navigate based on result type
            destinationView
        } label: {
            HStack(spacing: 14) {
                // Icon with soft background
                ZStack {
                    Circle()
                        .fill(result.type.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: result.type.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(result.type.color)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(result.title)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if result.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text(result.subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text(result.metadata)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var destinationView: some View {
        switch result.type {
        case .person:
            // Navigate to user profile
            UserProfileView(userId: getUserId(from: result))
        case .group:
            // Navigate to community
            CommunityDetailView(communityId: getGroupId(from: result))
        case .post:
            // Navigate to post detail
            PostDetailView(postId: getPostId(from: result))
        case .event:
            // Navigate to event
            EventDetailView(eventId: getEventId(from: result))
        }
    }
    
    private func getUserId(from result: SearchResult) -> String {
        // Extract user ID from search result
        // You'll need to add this to SearchResult model
        result.id.uuidString // Placeholder
    }
    
    private func getGroupId(from result: SearchResult) -> String {
        result.id.uuidString // Placeholder
    }
    
    private func getPostId(from result: SearchResult) -> String {
        result.id.uuidString // Placeholder
    }
    
    private func getEventId(from result: SearchResult) -> String {
        result.id.uuidString // Placeholder
    }
}
```

### Update SearchResult to Include IDs

```swift
// In SearchViewComponents.swift

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let metadata: String
    let type: ResultType
    let isVerified: Bool
    
    // ADD THESE:
    var entityId: String? // The actual Firebase document ID
    var userId: String? // For person type
    var groupId: String? // For group type
    var postId: String? // For post type
    var eventId: String? // For event type
    
    // ... rest of code
}
```

### Update SearchService to Include IDs

```swift
// In SearchService.swift - searchPeople() method

results.append(SearchResult(
    title: displayName,
    subtitle: "@\(username)",
    metadata: "...",
    type: .person,
    isVerified: isVerified,
    entityId: document.documentID,  // ADD THIS
    userId: document.documentID      // ADD THIS
))
```

---

## Issue 5: Follow Button in Feed 👥

### Add Follow Button to PostCard

```swift
// In PostCard or create PostHeader component

struct PostHeaderWithFollow: View {
    let post: Post
    @StateObject private var socialService = SocialService.shared
    @State private var isFollowing = false
    @State private var isCheckingFollow = true
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Picture
            Circle()
                .fill(Color.black)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(post.authorInitials)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                )
            
            // Author Info
            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.black)
                
                Text(post.timeAgo)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Follow Button
            if !isCurrentUser {
                FollowButton(
                    isFollowing: isFollowing,
                    isLoading: isCheckingFollow
                ) {
                    toggleFollow()
                }
            }
        }
        .task {
            await checkFollowStatus()
        }
    }
    
    private var isCurrentUser: Bool {
        // Check if post is from current user
        guard let currentUserId = FirebaseManager.shared.currentUser?.uid else {
            return false
        }
        return post.authorId == currentUserId // You need to add authorId to Post model
    }
    
    private func checkFollowStatus() async {
        isCheckingFollow = true
        defer { isCheckingFollow = false }
        
        do {
            // Get author's user ID from post
            // You'll need to add authorId to your Post model
            isFollowing = try await socialService.isFollowing(userId: "author-user-id")
        } catch {
            print("❌ Failed to check follow status")
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userId: "author-user-id")
                } else {
                    try await socialService.followUser(userId: "author-user-id")
                }
                
                isFollowing.toggle()
                
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } catch {
                print("❌ Follow/Unfollow failed")
            }
        }
    }
}

struct FollowButton: View {
    let isFollowing: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 80, height: 32)
            } else {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isFollowing ? .black : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isFollowing ? Color(.systemGray6) : Color.black)
                    )
            }
        }
        .disabled(isLoading)
    }
}
```

### Add authorId to Post Model

```swift
// In PostsManager.swift

struct Post: Identifiable, Codable, Equatable {
    let id: UUID
    let authorId: String  // ADD THIS - Firebase user ID
    let authorName: String
    let authorInitials: String
    // ... rest of properties
}
```

### Update FirestorePost

```swift
// In FirebasePostService.swift

struct FirestorePost: Codable, Identifiable {
    // ... existing fields
    var authorId: String  // ALREADY EXISTS!
    // ... rest
}

// In toPost() method, make sure authorId is included:
func toPost() -> Post {
    // ...
    return Post(
        id: UUID(uuidString: id ?? UUID().uuidString) ?? UUID(),
        authorId: authorId,  // PASS THIS THROUGH
        authorName: authorName,
        // ... rest
    )
}
```

---

## Additional Backend Features to Implement 🔧

### 1. Like/Amen Notifications

```swift
// In FirebasePostService.swift - toggleAmen() method

// After incrementing amen count:
try await createAmenNotification(postId: postId, postAuthorId: post.authorId)

private func createAmenNotification(postId: String, postAuthorId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid,
          currentUserId != postAuthorId else { return }
    
    let userDoc = try await db.collection("users").document(currentUserId).getDocument()
    guard let userName = userDoc.data()?["displayName"] as? String else { return }
    
    let notification: [String: Any] = [
        "userId": postAuthorId,
        "type": "amen",
        "fromUserId": currentUserId,
        "fromUserName": userName,
        "postId": postId,
        "message": "\(userName) said Amen to your post",
        "createdAt": Date(),
        "isRead": false
    ]
    
    try await db.collection("notifications").addDocument(data: notification)
}
```

### 2. Follow Feed (Posts from People You Follow)

```swift
// Add to PostsManager or create FeedService

func fetchFollowingFeed() async throws -> [Post] {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    // Get list of users you follow
    let followsSnapshot = try await db.collection("follows")
        .whereField("followerId", isEqualTo: currentUserId)
        .getDocuments()
    
    let followingIds = followsSnapshot.documents.compactMap { doc in
        try? doc.data(as: FollowRelationship.self).followingId
    }
    
    guard !followingIds.isEmpty else { return [] }
    
    // Get posts from those users
    // Note: Firestore has a limit of 10 items for 'in' queries
    let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
        .whereField("authorId", in: Array(followingIds.prefix(10)))
        .order(by: "createdAt", descending: true)
        .limit(to: 50)
        .getDocuments()
    
    let posts = try snapshot.documents.compactMap { doc in
        try doc.data(as: FirestorePost.self).toPost()
    }
    
    return posts
}
```

### 3. User Activity Feed

```swift
// Track user activity
func trackPostView(postId: String) async {
    guard let userId = firebaseManager.currentUser?.uid else { return }
    
    let activity: [String: Any] = [
        "userId": userId,
        "activityType": "post_view",
        "postId": postId,
        "timestamp": Date()
    ]
    
    try? await db.collection("user_activity")
        .addDocument(data: activity)
}
```

### 4. Post Recommendations

```swift
// Recommend posts based on user interests
func getRecommendedPosts() async throws -> [Post] {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    // Get user interests
    let userDoc = try await db.collection("users").document(currentUserId).getDocument()
    guard let interests = userDoc.data()?["interests"] as? [String] else {
        return []
    }
    
    // Find posts with matching hashtags
    var recommendedPosts: [Post] = []
    
    for interest in interests.prefix(3) {
        let snapshot = try await db.collection("posts")
            .whereField("hashtagsLowercase", arrayContains: interest.lowercased())
            .limit(to: 10)
            .getDocuments()
        
        let posts = try snapshot.documents.compactMap { doc in
            try doc.data(as: FirestorePost.self).toPost()
        }
        
        recommendedPosts.append(contentsOf: posts)
    }
    
    return Array(Set(recommendedPosts)) // Remove duplicates
}
```

---

## Summary Checklist

### Immediate Fixes:
- [x] DisplayName already working in signup
- [ ] Add profile photo edit button to ProfileView
- [ ] Show all post categories in feed (allPosts instead of openTablePosts)
- [ ] Add category filter tabs
- [ ] Update SearchResult to include entity IDs
- [ ] Add NavigationLink to SearchResultCard
- [ ] Add Follow button to PostCard header
- [ ] Add authorId to Post model

### Enhanced Features:
- [ ] Amen/Like notifications
- [ ] Following feed (posts from followed users)
- [ ] User activity tracking
- [ ] Post recommendations
- [ ] Real-time follow status updates
- [ ] Profile view with edit capabilities

### Files to Modify:
1. **ContentView.swift** - Change to `allPosts`, add category filter
2. **SearchViewComponents.swift** - Add navigation, update SearchResult
3. **SearchService.swift** - Include document IDs in results
4. **PostCard.swift** - Add follow button in header
5. **PostsManager.swift** - Add authorId to Post model
6. **ProfileView.swift** - Add photo edit button
7. **FirebasePostService.swift** - Ensure authorId passed through

---

## Quick Wins (Do First):

1. **Show all posts in feed:**
   ```swift
   // Change this ONE line in ContentView:
   ForEach(postsManager.allPosts) { post in
   ```

2. **Add category filter:**
   Copy the `FeedView` code above

3. **Profile photo edit:**
   Copy the `ProfilePhotoEditButton` code above

4. **Search navigation:**
   Update `SoftSearchResultCard` with NavigationLink

The backend is mostly done! Just need UI connections. 🎉
