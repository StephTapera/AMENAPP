# Quick Reference: All New Services

## 1. FollowService

```swift
// Follow
try await FollowService.shared.followUser(userId: "user123")

// Unfollow
try await FollowService.shared.unfollowUser(userId: "user123")

// Check status
let following = await FollowService.shared.isFollowing(userId: "user123")

// Get lists
let followers = try await FollowService.shared.fetchFollowers(userId: "user123")
let following = try await FollowService.shared.fetchFollowing(userId: "user123")
```

## 2. ProfilePhotoEditView

```swift
.sheet(isPresented: $showPhotoEdit) {
    ProfilePhotoEditView(
        currentImageURL: user.profileImageURL,
        onPhotoUpdated: { newURL in
            // Handle update
        }
    )
}
```

## 3. SearchService

```swift
// Search
await SearchService.shared.search(query: "faith", filters: [])

// Autocomplete
let suggestions = await SearchService.shared.quickSearch(query: "jo")

// Trending
await SearchService.shared.fetchTrendingHashtags()
```

## 4. ModerationService

```swift
// Report
try await ModerationService.shared.reportPost(
    postId: "post123",
    postAuthorId: "user456",
    reason: .spam,
    additionalDetails: nil
)

// Block
try await ModerationService.shared.blockUser(userId: "user456")

// Mute
try await ModerationService.shared.muteUser(userId: "user456")
```

## 5. SocialLinksService

```swift
// Add link
try await SocialLinksService.shared.addSocialLink(
    platform: "Instagram",
    username: "johndoe"
)

// Get links
let links = try await SocialLinksService.shared.fetchSocialLinks()
```

## Initialize on App Launch

```swift
// In ContentView.onAppear or App init
Task {
    await FollowService.shared.loadCurrentUserFollowing()
    FollowService.shared.startListening()
    await ModerationService.shared.loadCurrentUserModeration()
}
```
