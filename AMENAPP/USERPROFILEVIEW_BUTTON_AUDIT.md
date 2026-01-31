# UserProfileView Button Implementation Audit

## Executive Summary
**Status**: ⚠️ **NOT FULLY PRODUCTION READY**

Multiple buttons have TODO/placeholder implementations that need to be completed before production deployment.

---

## Button Inventory & Status

### ✅ PRODUCTION READY (Fully Implemented)

#### 1. **Back Button (Dismiss)**
- **Location**: Navigation bar leading
- **Action**: `dismiss()`
- **Implementation**: ✅ Complete
- **Notes**: Uses SwiftUI Environment dismiss

#### 2. **Share Profile Button**
- **Location**: Navigation bar trailing
- **Action**: `shareProfile()`
- **Implementation**: ✅ Complete
- **Features**:
  - Uses `UIActivityViewController`
  - Shares text and URL
  - Haptic feedback
  - Proper window scene handling

#### 3. **Report User Menu Item**
- **Location**: Navigation bar menu
- **Action**: `reportUser()`
- **Implementation**: ✅ Complete
- **Features**:
  - Shows `ReportUserView` sheet
  - Reason selection UI
  - Submit functionality (logs to console)
  - Haptic feedback
- **Notes**: Backend API call is TODO but UI is complete

#### 4. **Block User Menu Item**
- **Location**: Navigation bar menu
- **Action**: `toggleBlock()`
- **Implementation**: ⚠️ PARTIAL (See Issues)
- **Features**:
  - Alert confirmation
  - Optimistic UI update
  - Haptic feedback
- **Issues**: Backend API call is simulated, needs real implementation

#### 5. **Follow/Following Button**
- **Location**: Profile header
- **Action**: `toggleFollow()`
- **Implementation**: ✅ Complete
- **Features**:
  - Uses `FollowService.shared.toggleFollow()`
  - Optimistic UI updates
  - Error rollback
  - Real-time count refresh
  - Haptic feedback
  - Spring animation

#### 6. **Message Button**
- **Location**: Profile header
- **Action**: `sendMessage()`
- **Implementation**: ⚠️ PARTIAL
- **Features**:
  - Block check
  - Opens `ModernConversationDetailView` sheet
  - Haptic feedback
- **Issues**: Creates temporary `ChatConversation` object, should fetch or create real conversation

#### 7. **Followers Count Button**
- **Location**: Profile header stats
- **Action**: `showFollowersList = true`
- **Implementation**: ✅ Complete
- **Features**:
  - Opens `FollowersListView` sheet
  - Fetches real data using `FollowService`
  - Loading states
  - Empty states

#### 8. **Following Count Button**
- **Location**: Profile header stats
- **Action**: `showFollowingList = true`
- **Implementation**: ✅ Complete
- **Features**:
  - Opens `FollowersListView` sheet
  - Fetches real data using `FollowService`
  - Loading states
  - Empty states

#### 9. **Tab Selector Buttons (Posts/Reposts)**
- **Location**: Tab bar
- **Action**: Changes `selectedTab`
- **Implementation**: ✅ Complete
- **Features**:
  - Smooth animation with `matchedGeometryEffect`
  - Haptic feedback
  - Spring animation

#### 10. **Avatar Button**
- **Location**: Profile header
- **Action**: `showFullScreenAvatar = true`
- **Implementation**: ✅ Complete
- **Features**:
  - Opens `FullScreenAvatarView` fullscreen cover
  - Displays name, initials, and profile image

---

### ⚠️ PARTIALLY IMPLEMENTED (Needs Work)

#### 11. **Amen/Like Button (Post Cards)**
- **Location**: `ReadOnlyProfilePostCard`
- **Action**: `handleLike(postId:)`
- **Implementation**: ⚠️ SIMULATED
- **Current Behavior**: Optimistic UI update + console log
- **Missing**:
  ```swift
  // TODO: Replace with actual API call
  if wasLiked {
      // try await NetworkManager.shared.unlikePost(postId: postId)
      print("Unliked post: \(postId)")
  } else {
      // try await NetworkManager.shared.likePost(postId: postId)
      print("Liked post: \(postId)")
  }
  ```
- **Issues**:
  - No real backend integration
  - Uses UUID instead of real post ID
  - No persistence
- **Risk Level**: 🔴 HIGH - Users expect likes to persist

#### 12. **Reply/Comment Button (Post Cards)**
- **Location**: `ReadOnlyProfilePostCard`
- **Action**: `handleReply(postId:)`
- **Implementation**: ⚠️ PLACEHOLDER
- **Current Behavior**: Console log only
- **Missing**:
  ```swift
  // TODO: Navigate to reply composer or post detail
  // navigationPath.append(PostRoute.detail(postId: postId))
  print("Reply to post: \(postId)")
  ```
- **Issues**:
  - No navigation
  - No composer sheet
  - Button does nothing visible to user
- **Risk Level**: 🔴 HIGH - Broken user experience

#### 13. **Follow Button (User List Rows)**
- **Location**: `UserListRow` in followers/following lists
- **Action**: `isFollowing.toggle()`
- **Implementation**: ⚠️ LOCAL STATE ONLY
- **Issues**:
  - No backend call to `FollowService`
  - State doesn't persist
  - No error handling
  - No initial state check
- **Risk Level**: 🔴 HIGH - Users can't actually follow from list

#### 14. **Load More Posts Button**
- **Location**: Bottom of posts list
- **Action**: `onLoadMore?()`
- **Implementation**: ✅ WORKING but limited
- **Features**:
  - Pagination logic
  - Loading states
  - Auto-trigger near bottom
- **Issues**:
  - `fetchUserPosts(page:)` ignores page parameter
  - Always fetches all posts, doesn't paginate
- **Risk Level**: 🟡 MEDIUM - Works but inefficient

---

### 🔴 NOT IMPLEMENTED (Placeholders Only)

#### 15. **Block User Backend**
- **Location**: `performBlockAction()`
- **Current Code**:
  ```swift
  // TODO: Replace with actual API call
  if isBlocked {
      // try await NetworkManager.shared.blockUser(userId: userId)
      print("Blocked user: \(userId)")
  } else {
      // try await NetworkManager.shared.unblockUser(userId: userId)
      print("Unblocked user: \(userId)")
  }
  ```
- **Risk Level**: 🔴 CRITICAL - Security/harassment feature

#### 16. **Report User Backend**
- **Location**: `submitReport(reason:description:)`
- **Current Code**:
  ```swift
  // TODO: Call API endpoint
  // NetworkManager.shared.reportUser(userId: userId, reason: reason, description: description)
  ```
- **Risk Level**: 🔴 CRITICAL - Safety/moderation feature

---

## Critical Issues Preventing Production

### 🚨 MUST FIX

1. **Post Interactions Don't Work**
   - Like button doesn't persist
   - Reply button doesn't navigate
   - **Impact**: Users will be confused and frustrated
   - **Fix Required**: Integrate with PostInteractionsService

2. **Follow in Lists Broken**
   - Follow buttons in follower/following lists are fake
   - **Impact**: Users can't follow people from lists
   - **Fix Required**: Call FollowService.toggleFollow()

3. **Block Feature Not Functional**
   - Shows UI but doesn't actually block
   - **Impact**: Safety issue - users can't block harassers
   - **Fix Required**: Implement BlockService or ModerationService call

4. **Report Feature Not Functional**
   - Collects data but doesn't send
   - **Impact**: Safety issue - reports don't reach moderators
   - **Fix Required**: Implement report submission API

5. **Message Button Creates Fake Conversation**
   - Creates temporary ChatConversation object
   - **Impact**: Messages may not work or create duplicates
   - **Fix Required**: Fetch/create real conversation from backend

---

## Data Model Issues

### ProfilePost vs Post Mismatch

**Problem**: `ProfilePost` uses UUID, but real posts use String IDs

```swift
struct ProfilePost: Identifiable {
    let id = UUID()  // ❌ Should be String from Firestore
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
}
```

**Impact**: 
- Can't interact with real posts
- Like/comment actions use wrong ID type
- Can't navigate to post detail

**Fix Required**:
```swift
struct ProfilePost: Identifiable {
    let id: String  // Real Firestore post ID
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
}
```

Then update `fetchUserPosts()`:
```swift
return userPosts.map { post in
    ProfilePost(
        id: post.id.uuidString,  // Convert from Post's ID
        content: post.content,
        timestamp: post.timeAgo,
        likes: post.amenCount,
        replies: post.commentCount
    )
}
```

---

## Recommended Fixes (Priority Order)

### Phase 1: Critical Fixes (Before Beta)

1. **Fix ProfilePost ID Type**
   - Change UUID to String
   - Store real post IDs
   - Update all references

2. **Implement Like/Amen Functionality**
   ```swift
   private func handleLike(postId: String) async {
       guard let post = posts.first(where: { $0.id == postId }) else { return }
       
       let wasLiked = likedPosts.contains(postId)
       
       // Optimistic update
       if wasLiked {
           likedPosts.remove(postId)
       } else {
           likedPosts.insert(postId)
       }
       
       do {
           let interactionsService = PostInteractionsService.shared
           if wasLiked {
               try await interactionsService.removeAmen(postId: postId)
           } else {
               try await interactionsService.addAmen(postId: postId)
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
   ```

3. **Implement Reply/Comment Navigation**
   ```swift
   @State private var selectedPostForComments: Post?
   @State private var showCommentsSheet = false
   
   private func handleReply(postId: String) {
       // Fetch full post object
       if let post = /* fetch from FirebasePostService */ {
           selectedPostForComments = post
           showCommentsSheet = true
       }
   }
   
   // Then in body:
   .sheet(isPresented: $showCommentsSheet) {
       if let post = selectedPostForComments {
           PostCommentsView(post: post)
       }
   }
   ```

4. **Fix Follow in User Lists**
   ```swift
   struct UserListRow: View {
       let user: UserProfile
       @State private var isFollowing = false
       @State private var isLoading = false
       
       var body: some View {
           // ... existing UI ...
           
           Button {
               Task {
                   await toggleFollow()
               }
           } label: {
               if isLoading {
                   ProgressView()
                       .scaleEffect(0.8)
               } else {
                   Text(isFollowing ? "Following" : "Follow")
                       // ... existing styling ...
               }
           }
           .disabled(isLoading)
           .task {
               // Check initial follow status
               await checkFollowStatus()
           }
       }
       
       private func toggleFollow() async {
           isLoading = true
           let previousState = isFollowing
           isFollowing.toggle()
           
           do {
               // Need userId from UserProfile - add it!
               guard let userId = user.userId else { return }
               try await FollowService.shared.toggleFollow(userId: userId)
           } catch {
               isFollowing = previousState
           }
           
           isLoading = false
       }
       
       private func checkFollowStatus() async {
           guard let userId = user.userId else { return }
           isFollowing = await FollowService.shared.isFollowing(userId: userId)
       }
   }
   ```

   **Also need to update UserProfile struct**:
   ```swift
   struct UserProfile {
       var userId: String  // ADD THIS
       var name: String
       var username: String
       // ... rest of fields
   }
   ```

### Phase 2: Safety Features (Before Launch)

5. **Implement Block Service**
   ```swift
   // Create BlockService or use ModerationService
   private func performBlockAction() async {
       // ... existing optimistic update ...
       
       do {
           if isBlocked {
               try await ModerationService.shared.blockUser(userId: userId)
           } else {
               try await ModerationService.shared.unblockUser(userId: userId)
           }
       } catch {
           // Rollback
           isBlocked = previousState
           errorMessage = "Failed to \(previousState ? "unblock" : "block") user."
           showErrorAlert = true
       }
   }
   ```

6. **Implement Report Submission**
   ```swift
   private func submitReport(reason: UserReportReason, description: String) {
       Task {
           do {
               try await ModerationService.shared.reportUser(
                   userId: userId,
                   reason: convertToModerationReason(reason),
                   description: description
               )
               
               // Show success
               let haptic = UINotificationFeedbackGenerator()
               haptic.notificationOccurred(.success)
               
           } catch {
               errorMessage = "Failed to submit report. Please try again."
               showErrorAlert = true
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

### Phase 3: Enhancements (Post-Launch)

7. **Fix Message Button**
   ```swift
   private func sendMessage() {
       guard !isBlocked else {
           errorMessage = "You cannot message blocked users."
           showErrorAlert = true
           return
       }
       
       Task {
           do {
               // Fetch or create conversation
               let conversationId = try await MessagingService.shared
                   .getOrCreateConversation(with: userId)
               
               // Navigate to real conversation
               showMessagingWithId = conversationId
               
           } catch {
               errorMessage = "Failed to start conversation."
               showErrorAlert = true
           }
       }
   }
   ```

8. **Implement Real Pagination**
   ```swift
   private func fetchUserPosts(page: Int) async throws -> [ProfilePost] {
       print("📥 Fetching posts for user: \(userId) (page: \(page))")
       
       let firebasePostService = FirebasePostService.shared
       let userPosts = try await firebasePostService.fetchUserOriginalPosts(
           userId: userId,
           limit: 20,
           offset: (page - 1) * 20  // Add pagination support
       )
       
       return userPosts.map { post in
           ProfilePost(
               id: post.id.uuidString,  // Fixed ID
               content: post.content,
               timestamp: post.timeAgo,
               likes: post.amenCount,
               replies: post.commentCount
           )
       }
   }
   ```

---

## Services Required

### Already Available
- ✅ `FollowService` - For follow/unfollow
- ✅ `FirebasePostService` - For fetching posts
- ✅ `PostInteractionsService` - For likes/amens
- ✅ `CommentService` - For comments/replies

### Need to Create or Verify
- ❓ `BlockService` or use `ModerationService`
- ❓ `ReportService` or use `ModerationService`
- ❓ `MessagingService` or `ConversationService`

---

## Testing Checklist

### Before Production

- [ ] **Back button** dismisses view
- [ ] **Share button** opens share sheet with correct data
- [ ] **Report user** submits to backend and shows confirmation
- [ ] **Block user** actually blocks and prevents interactions
- [ ] **Follow button** works and persists
- [ ] **Unfollow button** works and persists
- [ ] **Message button** creates/opens real conversation
- [ ] **Followers list** shows correct data and follow buttons work
- [ ] **Following list** shows correct data and follow buttons work
- [ ] **Tab switching** is smooth with animation
- [ ] **Avatar button** shows full-screen view
- [ ] **Amen/Like button** persists and updates count
- [ ] **Reply button** opens comment sheet
- [ ] **Load more** fetches next page of posts
- [ ] **Follow in lists** actually follows users
- [ ] **Error handling** shows appropriate messages
- [ ] **Loading states** display correctly
- [ ] **Empty states** display when no content
- [ ] **Haptic feedback** on all button taps
- [ ] **Real-time updates** for follower counts
- [ ] **Pull to refresh** reloads data

---

## Risk Assessment

| Feature | Status | Risk | Impact | Priority |
|---------|--------|------|--------|----------|
| Like/Amen | Not Working | 🔴 High | Users frustrated | P0 |
| Reply/Comment | Not Working | 🔴 High | Users frustrated | P0 |
| Follow in Lists | Not Working | 🔴 High | Can't follow users | P0 |
| Block User | Not Working | 🔴 Critical | Safety issue | P0 |
| Report User | Not Working | 🔴 Critical | Safety issue | P0 |
| Message | Partial | 🟡 Medium | May cause issues | P1 |
| Load More | Inefficient | 🟡 Medium | Performance | P2 |
| ProfilePost IDs | Wrong Type | 🔴 High | Breaks interactions | P0 |

---

## Conclusion

### ❌ NOT PRODUCTION READY

**Critical Blockers**:
1. Post interactions (like/comment) don't work
2. Follow buttons in lists don't work
3. Block feature is not functional
4. Report feature is not functional
5. Data model mismatch (UUID vs String IDs)

**Estimated Fix Time**: 2-3 days
- Day 1: Fix data model and post interactions
- Day 2: Fix safety features (block/report)
- Day 3: Testing and polish

**Recommendation**: 
⚠️ **DO NOT DEPLOY** until at least P0 items are fixed. Users will have a broken experience with core features not working.

---

**Last Updated**: January 29, 2026
**Audited By**: AI Assistant
**Status**: ⚠️ NEEDS WORK
