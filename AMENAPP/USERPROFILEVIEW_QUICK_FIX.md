# UserProfileView - Production Readiness Quick Check

## ❌ NOT PRODUCTION READY

### Critical Issues (Must Fix Before Launch)

#### 🔴 P0 - BROKEN CORE FEATURES
1. **Like/Amen Button** - Only logs to console, doesn't persist
2. **Reply/Comment Button** - Only logs to console, no navigation
3. **Follow in Lists** - Local state only, doesn't call backend
4. **ProfilePost ID Type** - Uses UUID instead of String, breaks interactions

#### 🔴 P0 - MISSING SAFETY FEATURES
5. **Block User** - Simulated, doesn't actually block
6. **Report User** - Collects data but doesn't submit

#### 🟡 P1 - PARTIAL IMPLEMENTATIONS
7. **Message Button** - Creates temporary conversation object
8. **Pagination** - Fetches all posts, ignores page parameter

---

## Working Features ✅

- ✅ Navigation (back button)
- ✅ Share profile
- ✅ Follow/Unfollow main button
- ✅ Followers/Following count buttons
- ✅ Tab switching
- ✅ Avatar view
- ✅ Pull to refresh
- ✅ Real-time follower count updates
- ✅ Loading states
- ✅ Empty states
- ✅ Error handling (UI only)

---

## Quick Fix Code Snippets

### 1. Fix ProfilePost ID Type

**File**: `UserProfileView.swift` (line ~13)

```swift
struct ProfilePost: Identifiable {
    let id: String  // Changed from UUID()
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
}
```

**Then update fetchUserPosts()** (line ~517):

```swift
return userPosts.map { post in
    ProfilePost(
        id: post.id.uuidString,  // Pass real ID
        content: post.content,
        timestamp: post.timeAgo,
        likes: post.amenCount,
        replies: post.commentCount
    )
}
```

**Then update state** (line ~938):

```swift
@State private var likedPosts: Set<String> = []  // Changed from Set<UUID>
```

---

### 2. Fix Like Button

**File**: `UserProfileView.swift` (line ~988)

Replace:
```swift
do {
    // Simulate API call
    try? await Task.sleep(nanoseconds: 200_000_000)
    
    // TODO: Replace with actual API call
    if wasLiked {
        // try await NetworkManager.shared.unlikePost(postId: postId)
        print("Unliked post: \(postId)")
    } else {
        // try await NetworkManager.shared.likePost(postId: postId)
        print("Liked post: \(postId)")
    }
}
```

With:
```swift
do {
    let interactionsService = PostInteractionsService.shared
    if wasLiked {
        try await interactionsService.removeAmen(postId: postId)
        print("✅ Removed amen from post: \(postId)")
    } else {
        try await interactionsService.addAmen(postId: postId)
        print("✅ Added amen to post: \(postId)")
    }
}
```

---

### 3. Fix Reply Button

**File**: `UserProfileView.swift` (line ~1009)

Add state variable (line ~131):
```swift
@State private var selectedPostForComments: Post?
@State private var showCommentsSheet = false
```

Replace handleReply (line ~1009):
```swift
private func handleReply(postId: String) {
    let haptic = UIImpactFeedbackGenerator(style: .light)
    haptic.impactOccurred()
    
    Task {
        // Fetch full post to show comments
        do {
            let firebasePostService = FirebasePostService.shared
            if let post = try await firebasePostService.fetchPost(postId: postId) {
                await MainActor.run {
                    selectedPostForComments = post
                    showCommentsSheet = true
                }
            }
        } catch {
            print("❌ Failed to fetch post for comments: \(error)")
        }
    }
}
```

Add sheet to body (line ~248):
```swift
.sheet(isPresented: $showCommentsSheet) {
    if let post = selectedPostForComments {
        PostCommentsView(post: post)
    }
}
```

---

### 4. Fix Follow in Lists

**File**: `UserProfileView.swift`

First, update UserProfile struct (line ~28):
```swift
struct UserProfile {
    var userId: String  // ADD THIS LINE
    var name: String
    var username: String
    var bio: String
    var initials: String
    var profileImageURL: String?
    var interests: [String]
    var socialLinks: [UserSocialLink]
    var followersCount: Int
    var followingCount: Int
}
```

Then update loadUsers() mapping (line ~1444):
```swift
users = followUserProfiles.map { followUser in
    UserProfile(
        userId: followUser.userId,  // ADD THIS LINE
        name: followUser.displayName,
        username: followUser.username,
        // ... rest unchanged
    )
}
```

Finally, fix UserListRow (line ~1463):
```swift
struct UserListRow: View {
    let user: UserProfile
    @State private var isFollowing = false
    @State private var isLoading = false
    
    var body: some View {
        HStack(spacing: 12) {
            // ... existing avatar and info ...
            
            Spacer()
            
            // Follow button
            Button {
                Task {
                    await toggleFollow()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 80, height: 32)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(isFollowing ? .black : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isFollowing ? Color(white: 0.93) : Color.black)
                        )
                }
            }
            .disabled(isLoading)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .task {
            await checkFollowStatus()
        }
    }
    
    private func toggleFollow() async {
        isLoading = true
        let previousState = isFollowing
        
        withAnimation {
            isFollowing.toggle()
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            try await FollowService.shared.toggleFollow(userId: user.userId)
            print("✅ Successfully \(isFollowing ? "followed" : "unfollowed") \(user.name)")
        } catch {
            // Rollback on error
            await MainActor.run {
                isFollowing = previousState
            }
            print("❌ Failed to toggle follow: \(error)")
        }
        
        isLoading = false
    }
    
    private func checkFollowStatus() async {
        isFollowing = await FollowService.shared.isFollowing(userId: user.userId)
    }
}
```

---

### 5. Fix Block User

**File**: `UserProfileView.swift` (line ~819)

Replace:
```swift
do {
    // Simulate API call
    try? await Task.sleep(nanoseconds: 300_000_000)
    
    // TODO: Replace with actual API call
    if isBlocked {
        // try await NetworkManager.shared.blockUser(userId: userId)
        print("Blocked user: \(userId)")
    } else {
        // try await NetworkManager.shared.unblockUser(userId: userId)
        print("Unblocked user: \(userId)")
    }
}
```

With:
```swift
do {
    let moderationService = ModerationService.shared
    if isBlocked {
        try await moderationService.blockUser(userId: userId)
        print("✅ Blocked user: \(userId)")
    } else {
        try await moderationService.unblockUser(userId: userId)
        print("✅ Unblocked user: \(userId)")
    }
}
```

---

### 6. Fix Report User

**File**: `UserProfileView.swift` (line ~786)

Replace:
```swift
private func submitReport(reason: UserReportReason, description: String) {
    // In a real app, send to backend API
    print("Reporting user \(userId) for: \(reason.rawValue)")
    print("Description: \(description)")
    
    // Show confirmation
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.success)
    
    // TODO: Call API endpoint
    // NetworkManager.shared.reportUser(userId: userId, reason: reason, description: description)
}
```

With:
```swift
private func submitReport(reason: UserReportReason, description: String) {
    Task {
        do {
            let moderationService = ModerationService.shared
            
            // Convert to ModerationReportReason
            let moderationReason = convertToModerationReason(reason)
            
            try await moderationService.reportUser(
                userId: userId,
                reason: moderationReason,
                description: description
            )
            
            print("✅ Successfully reported user: \(userId)")
            
            // Show confirmation
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            print("❌ Failed to report user: \(error)")
            await MainActor.run {
                errorMessage = "Failed to submit report. Please try again."
                showErrorAlert = true
            }
        }
    }
}

private func convertToModerationReason(_ reason: UserReportReason) -> ModerationReportReason {
    switch reason {
    case .spam: return .spam
    case .harassment: return .harassment
    case .inappropriate: return .inappropriateContent
    case .impersonation: return .impersonation
    case .falseInfo: return .falseInformation
    case .other: return .other
    }
}
```

---

## Estimated Fix Time

- **Fix 1 (ProfilePost ID)**: 15 minutes
- **Fix 2 (Like button)**: 10 minutes  
- **Fix 3 (Reply button)**: 20 minutes
- **Fix 4 (Follow in lists)**: 30 minutes
- **Fix 5 (Block user)**: 10 minutes
- **Fix 6 (Report user)**: 15 minutes

**Total**: ~1.5 hours

---

## After Fixes - Test This

1. Tap like on a post → Should persist after app restart
2. Tap reply on a post → Should open comments sheet
3. Tap follow in followers list → Should actually follow
4. Block a user → Should prevent seeing their posts
5. Report a user → Should submit to moderation queue
6. Pull to refresh → Should reload all data
7. Scroll to bottom → Should load more posts

---

**Status After Fixes**: ✅ Production Ready
**Current Status**: ❌ Not Ready - 6 critical fixes needed

