# UserProfileView - Missing Features & Implementation Guide

## ✅ Just Added
- **Report User Flow** - Complete reporting system with categories and descriptions

## 🔧 Still Missing / Needs Implementation

### **1. Messaging Integration** 🔴 HIGH PRIORITY
**Current State:** Button prints to console  
**Needed:**
- Navigate to MessagesView with pre-filled conversation
- Create new conversation if none exists
- Pass user data (userId, name, avatar) to messaging system
- Check if blocked before allowing messaging

**Implementation:**
```swift
// In sendMessage()
if isBlocked {
    // Show alert: "You cannot message blocked users"
    return
}

// Navigate to messaging
navigationPath.append(MessagingRoute.conversation(userId: userId))
// OR
showMessagingView = true
```

---

### **2. Follow/Unfollow API Integration** 🔴 HIGH PRIORITY
**Current State:** Toggles local state only  
**Needed:**
- Call backend API to follow/unfollow
- Update follower count in real-time
- Handle errors (network failure, already following, etc.)
- Sync with followers list
- Optimistic UI updates with rollback on failure

**Implementation:**
```swift
private func toggleFollow() async {
    let previousState = isFollowing
    
    // Optimistic update
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isFollowing.toggle()
        profileData.followersCount += isFollowing ? 1 : -1
    }
    
    do {
        if isFollowing {
            try await NetworkManager.shared.followUser(userId: userId)
        } else {
            try await NetworkManager.shared.unfollowUser(userId: userId)
        }
    } catch {
        // Rollback on error
        isFollowing = previousState
        profileData.followersCount += previousState ? 1 : -1
        showErrorAlert = true
    }
}
```

---

### **3. Block/Unblock API Integration** 🔴 HIGH PRIORITY
**Current State:** Updates local state only  
**Needed:**
- Call backend API to block/unblock
- Hide blocked user's content across app
- Prevent messaging and interactions
- Add to blocked users list in settings
- Show confirmation after blocking

**Implementation:**
```swift
private func toggleBlock() async {
    let previousState = isBlocked
    isBlocked.toggle()
    
    do {
        if isBlocked {
            try await NetworkManager.shared.blockUser(userId: userId)
            // Also unfollow
            isFollowing = false
        } else {
            try await NetworkManager.shared.unblockUser(userId: userId)
        }
        
        // Show success message
        showBlockSuccessMessage = true
    } catch {
        // Rollback
        isBlocked = previousState
        showErrorAlert = true
    }
}
```

---

### **4. Real User Data Loading** 🔴 HIGH PRIORITY
**Current State:** Uses sample data only  
**Needed:**
- Fetch user profile from backend using userId
- Load user's posts, replies, reposts
- Handle loading states
- Handle errors (user not found, network error)
- Implement pagination for posts
- Cache user data

**Implementation:**
```swift
@MainActor
private func loadProfileData() async {
    isLoading = true
    
    do {
        // Fetch user profile
        profileData = try await NetworkManager.shared.fetchUserProfile(userId: userId)
        
        // Fetch user content
        async let postsTask = NetworkManager.shared.fetchUserPosts(userId: userId, limit: 20)
        async let repliesTask = NetworkManager.shared.fetchUserReplies(userId: userId, limit: 20)
        async let repostsTask = NetworkManager.shared.fetchUserReposts(userId: userId, limit: 20)
        
        (posts, replies, reposts) = try await (postsTask, repliesTask, repostsTask)
        
        // Check if following
        isFollowing = try await NetworkManager.shared.isFollowing(userId: userId)
        
    } catch {
        showError(error)
    }
    
    isLoading = false
}
```

---

### **5. Pagination for Content** 🟡 MEDIUM PRIORITY
**Current State:** Loads all content at once  
**Needed:**
- Load posts/replies/reposts in batches (20-30 items)
- Implement "Load More" button or infinite scroll
- Track current page/offset
- Show loading indicator when fetching more

**Implementation:**
```swift
struct UserPostsContentView: View {
    let posts: [ProfilePost]
    @State private var isLoadingMore = false
    @State private var hasMorePosts = true
    let onLoadMore: () async -> Void
    
    var body: some View {
        LazyVStack(spacing: 0) {
            // ... posts ...
            
            if hasMorePosts {
                Button {
                    Task { await onLoadMore() }
                } label: {
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Text("Load More")
                    }
                }
            }
        }
    }
}
```

---

### **6. Like/Reply Post Actions** 🟡 MEDIUM PRIORITY
**Current State:** Local state tracking only  
**Needed:**
- Call API to like/unlike posts
- Navigate to post detail for replies
- Update like counts in real-time
- Show reply composer sheet
- Sync liked state across app

**Implementation:**
```swift
private func handleLike(postId: UUID) async {
    let wasLiked = likedPosts.contains(postId)
    
    // Optimistic update
    if wasLiked {
        likedPosts.remove(postId)
    } else {
        likedPosts.insert(postId)
    }
    
    do {
        if wasLiked {
            try await NetworkManager.shared.unlikePost(postId: postId)
        } else {
            try await NetworkManager.shared.likePost(postId: postId)
        }
    } catch {
        // Rollback
        if wasLiked {
            likedPosts.insert(postId)
        } else {
            likedPosts.remove(postId)
        }
    }
}

private func handleReply(postId: UUID) {
    // Show reply composer
    selectedPostForReply = postId
    showReplyComposer = true
}
```

---

### **7. Profile Stats Interaction** 🟢 LOW PRIORITY
**Current State:** Stats are display-only  
**Needed:**
- Tap "followers" to show followers list
- Tap "following" to show following list
- Navigate to respective views
- Show mutual connections

**Implementation:**
```swift
Button {
    showFollowersList = true
} label: {
    StatView(count: formatCount(profileData.followersCount), label: "followers")
}
.sheet(isPresented: $showFollowersList) {
    FollowersListView(userId: userId, type: .followers)
}
```

---

### **8. Social Links Integration** 🟢 LOW PRIORITY
**Current State:** Opens in Safari  
**Needed:**
- Option to open in native apps (Instagram app, Twitter app, etc.)
- Fallback to Safari if app not installed
- Show loading indicator
- Handle invalid/broken links

**Implementation:**
```swift
private func openSocialLink(_ link: SocialLink) {
    // Try native app first
    if let nativeURL = link.platform.nativeAppURL(username: link.username),
       UIApplication.shared.canOpenURL(nativeURL) {
        UIApplication.shared.open(nativeURL)
    } else if let webURL = link.platform.webURL(username: link.username) {
        // Fallback to Safari
        UIApplication.shared.open(webURL)
    }
}
```

---

### **9. Error Handling & Edge Cases** 🟡 MEDIUM PRIORITY
**Current State:** Minimal error handling  
**Needed:**
- Network error alerts
- User not found handling
- Deleted account handling
- Private account handling
- Rate limiting messages
- Retry mechanisms

**Implementation:**
```swift
@State private var errorMessage: String?
@State private var showError = false

// In body
.alert("Error", isPresented: $showError) {
    Button("OK") { }
    if isNetworkError {
        Button("Retry") {
            Task { await loadProfileData() }
        }
    }
} message: {
    Text(errorMessage ?? "Something went wrong")
}
```

---

### **10. Analytics & Tracking** 🟢 LOW PRIORITY
**Needed:**
- Track profile views
- Track button clicks (follow, message, etc.)
- Track time spent on profile
- Track which tab users view most

**Implementation:**
```swift
.onAppear {
    Analytics.log(.profileViewed(userId: userId))
}

private func toggleFollow() {
    Analytics.log(isFollowing ? .unfollowUser : .followUser, userId: userId)
    // ... rest of implementation
}
```

---

### **11. Deep Linking Support** 🟡 MEDIUM PRIORITY
**Needed:**
- Support opening profile from deep links
- Handle universal links (amenapp.com/user/username)
- Support sharing profile links
- Handle QR code scans

**Implementation:**
```swift
// In App.swift or SceneDelegate
.onOpenURL { url in
    if url.pathComponents.contains("user"),
       let username = url.pathComponents.last {
        // Navigate to UserProfileView
        navigationPath.append(ProfileRoute.user(username: username))
    }
}
```

---

### **12. Offline Mode** 🟢 LOW PRIORITY
**Needed:**
- Cache profile data locally
- Show last loaded data when offline
- Indicate offline status
- Queue actions (follow, like) for when online

**Implementation:**
```swift
// Use CoreData or Realm
private func loadProfileData() async {
    // Try network first
    do {
        let data = try await NetworkManager.shared.fetchUserProfile(userId: userId)
        profileData = data
        
        // Cache locally
        ProfileCache.save(data, forUserId: userId)
    } catch {
        // Fallback to cache
        if let cachedData = ProfileCache.load(userId: userId) {
            profileData = cachedData
            showOfflineIndicator = true
        }
    }
}
```

---

### **13. Mutual Connections Display** 🟢 LOW PRIORITY
**Needed:**
- Show "Followed by X and Y" under bio
- Show mutual connections count
- Link to mutual connections list

**Implementation:**
```swift
if !mutualConnections.isEmpty {
    Text("Followed by \(mutualConnections.prefix(2).joined(separator: ", ")) and \(mutualConnections.count - 2) others")
        .font(.custom("OpenSans-Regular", size: 13))
        .foregroundStyle(.black.opacity(0.6))
}
```

---

### **14. Profile Action Sheet** 🟢 LOW PRIORITY
**Needed:**
- Copy profile link
- QR code for profile
- Mute user option
- Add to close friends
- Suggest to friend

**Implementation:**
```swift
.contextMenu {
    Button("Copy Profile Link") {
        UIPasteboard.general.string = "https://amenapp.com/\(profileData.username)"
    }
    
    Button("Show QR Code") {
        showQRCode = true
    }
    
    Button("Mute \(profileData.name)") {
        muteUser()
    }
}
```

---

## 📋 Implementation Priority

### Phase 1 - Core Functionality (Week 1)
1. ✅ Report User Flow (DONE)
2. Follow/Unfollow API
3. Real User Data Loading
4. Messaging Integration
5. Block/Unblock API

### Phase 2 - Enhanced Features (Week 2)
6. Like/Reply Post Actions
7. Pagination for Content
8. Error Handling
9. Profile Stats Interaction

### Phase 3 - Polish & Extras (Week 3)
10. Deep Linking
11. Social Links Enhancement
12. Analytics Tracking
13. Mutual Connections
14. Offline Mode
15. Profile Action Sheet

---

## 🧪 Testing Checklist

- [ ] Profile loads correctly with real user data
- [ ] Follow/Unfollow updates correctly
- [ ] Block/Unblock prevents interactions
- [ ] Messaging opens conversation
- [ ] Report user submits successfully
- [ ] Like/Reply updates in real-time
- [ ] Pagination loads more content
- [ ] Error states display properly
- [ ] Offline mode shows cached data
- [ ] Deep links navigate correctly
- [ ] Social links open correctly
- [ ] Empty states show when appropriate
- [ ] Loading states show during API calls

---

## 📱 API Endpoints Needed

```swift
// User Profile
GET  /api/users/:userId/profile
GET  /api/users/:userId/posts?page=1&limit=20
GET  /api/users/:userId/replies?page=1&limit=20
GET  /api/users/:userId/reposts?page=1&limit=20

// Follow System
POST   /api/users/:userId/follow
DELETE /api/users/:userId/follow
GET    /api/users/:userId/followers
GET    /api/users/:userId/following
GET    /api/users/:userId/is-following

// Block System
POST   /api/users/:userId/block
DELETE /api/users/:userId/block
GET    /api/users/blocked

// Report System
POST /api/reports/user
Body: { userId, reason, description }

// Interactions
POST   /api/posts/:postId/like
DELETE /api/posts/:postId/like
POST   /api/posts/:postId/reply

// Analytics
POST /api/analytics/profile-view
Body: { userId, timestamp }
```

---

## 🎯 Success Metrics

- Profile load time < 1 second
- Follow action completes < 500ms
- 95%+ uptime for profile views
- < 1% error rate on interactions
- Zero crashes related to profile viewing

