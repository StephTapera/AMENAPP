# 🚀 ProfileView Quick Start Guide

## Copy-Paste Code Examples

### 1. Load Profile on View Appear

```swift
// In ProfileView.swift

.onAppear {
    Task {
        await loadProfileData()
    }
}

@MainActor
private func loadProfileData() async {
    isLoading = true
    
    // 1. Load user profile from Firestore
    let userService = UserService.shared
    await userService.fetchCurrentUser()
    
    guard let user = userService.currentUser else {
        isLoading = false
        return
    }
    
    // 2. Update UI data
    profileData = UserProfileData(
        name: user.displayName,
        username: user.username,
        bio: user.bio,
        initials: user.initials,
        profileImageURL: user.profileImageURL,
        interests: user.interests,
        socialLinks: user.socialLinks.map { link in
            SocialLinkUI(
                platform: SocialLinkUI.SocialPlatform(rawValue: link["platform"] ?? "") ?? .instagram,
                username: link["username"] ?? ""
            )
        }
    )
    
    // 3. Load posts, saved, reposts, replies
    guard let userId = Auth.auth().currentUser?.uid else {
        isLoading = false
        return
    }
    
    do {
        // Fetch all tab data
        async let posts = RealtimePostService.shared.fetchUserPosts(userId: userId)
        async let saved = RealtimeSavedPostsService.shared.fetchSavedPosts()
        async let reposts = RealtimeRepostsService.shared.fetchUserReposts(userId: userId)
        async let replies = RealtimeCommentsService.shared.fetchUserComments(userId: userId)
        
        // Wait for all to complete
        (userPosts, savedPosts, self.reposts, userReplies) = try await (posts, saved, reposts, replies)
        
        // 4. Setup real-time listeners
        setupRealtimeDatabaseListeners(userId: userId)
        listenersActive = true
        
    } catch {
        print("❌ Error loading profile data: \(error)")
    }
    
    isLoading = false
}
```

---

### 2. Setup Real-time Listeners

```swift
@MainActor
private func setupRealtimeDatabaseListeners(userId: String) {
    // Posts listener
    RealtimePostService.shared.observeUserPosts(userId: userId) { posts in
        self.userPosts = posts
        print("🔄 Posts updated: \(posts.count)")
    }
    
    // Saved posts listener
    RealtimeSavedPostsService.shared.observeSavedPosts { postIds in
        Task {
            do {
                let posts = try await RealtimeSavedPostsService.shared.fetchSavedPosts()
                await MainActor.run {
                    self.savedPosts = posts
                    print("🔄 Saved posts updated: \(posts.count)")
                }
            } catch {
                print("❌ Error fetching saved posts: \(error)")
            }
        }
    }
    
    // Reposts listener
    RealtimeRepostsService.shared.observeUserReposts(userId: userId) { posts in
        self.reposts = posts
        print("🔄 Reposts updated: \(posts.count)")
    }
    
    print("✅ Real-time listeners active")
}
```

---

### 3. Save Profile Changes (EditProfileView)

```swift
private func saveProfile() {
    guard !isSaving else { return }
    
    isSaving = true
    
    Task {
        do {
            // 1. Update display name and bio
            try await UserService.shared.updateProfile(
                displayName: name,
                bio: bio
            )
            
            // 2. Save interests (keep existing goals and prayer time)
            let currentGoals = UserService.shared.currentUser?.goals ?? []
            let currentPrayerTime = UserService.shared.currentUser?.preferredPrayerTime ?? "Morning"
            
            try await UserService.shared.saveOnboardingPreferences(
                interests: interests,
                goals: currentGoals,
                prayerTime: currentPrayerTime
            )
            
            // 3. Save social links if any
            if !socialLinks.isEmpty {
                let linkData = socialLinks.map { link in
                    SocialLinkData(
                        platform: link.platform.rawValue,
                        username: link.username
                    )
                }
                try await SocialLinksService.shared.updateSocialLinks(linkData)
            }
            
            // 4. Success feedback
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                isSaving = false
                dismiss()
            }
            
            print("✅ Profile saved successfully")
            
        } catch {
            print("❌ Save failed: \(error)")
            
            await MainActor.run {
                isSaving = false
                saveErrorMessage = "Failed to save profile. Please try again."
                showSaveError = true
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}
```

---

### 4. Upload Profile Image

```swift
// In ProfilePhotoEditView or similar

private func uploadProfilePhoto() {
    guard let image = selectedImage else { return }
    
    isUploading = true
    errorMessage = nil
    
    Task {
        do {
            print("📤 Uploading profile photo...")
            
            // Upload to Firebase Storage
            let downloadURL = try await UserService.shared.uploadProfileImage(
                image,
                compressionQuality: 0.7
            )
            
            print("✅ Image uploaded: \(downloadURL)")
            
            // Update local state
            await MainActor.run {
                onPhotoUpdated(downloadURL)
                isUploading = false
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                // Dismiss after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
            
        } catch {
            print("❌ Upload failed: \(error)")
            
            await MainActor.run {
                errorMessage = "Upload failed. Please try again."
                isUploading = false
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}
```

---

### 5. Remove Profile Image

```swift
private func removeProfilePhoto() {
    Task {
        do {
            print("🗑️ Removing profile photo...")
            
            try await UserService.shared.removeProfileImage()
            
            print("✅ Profile photo removed")
            
            await MainActor.run {
                onPhotoUpdated(nil)
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                dismiss()
            }
            
        } catch {
            print("❌ Failed to remove photo: \(error)")
            
            await MainActor.run {
                errorMessage = "Failed to remove photo. Please try again."
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}
```

---

### 6. Add/Remove Interests

```swift
// Add interest
private func addInterest() {
    let trimmedInterest = newInterest.trimmingCharacters(in: .whitespaces)
    
    // Validate
    guard !trimmedInterest.isEmpty else { return }
    guard interests.count < 3 else {
        showErrorAlert(title: "Maximum Reached", message: "You can add up to 3 interests")
        return
    }
    guard !interests.contains(where: { $0.lowercased() == trimmedInterest.lowercased() }) else {
        showErrorAlert(title: "Duplicate", message: "You've already added this interest")
        return
    }
    
    // Add with animation
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        interests.append(trimmedInterest)
        hasChanges = true
    }
    
    newInterest = ""
    
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.success)
}

// Remove interest
private func removeInterest(_ interest: String) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        interests.removeAll { $0 == interest }
        hasChanges = true
    }
    
    let haptic = UIImpactFeedbackGenerator(style: .medium)
    haptic.impactOccurred()
}
```

---

### 7. Add/Update Social Links

```swift
// In SocialLinksEditView

private func saveSocialLinks() {
    guard !isSaving else { return }
    
    isSaving = true
    
    Task {
        do {
            // Convert UI links to service model
            let linkData = links.map { link in
                SocialLinkData(
                    platform: link.platform.rawValue,
                    username: link.username
                )
            }
            
            // Save to Firebase
            try await SocialLinksService.shared.updateSocialLinks(linkData)
            
            print("✅ Social links saved")
            
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                isSaving = false
                dismiss()
            }
            
        } catch {
            print("❌ Save failed: \(error)")
            
            await MainActor.run {
                isSaving = false
                showError = true
                errorMessage = "Failed to save social links"
            }
        }
    }
}
```

---

### 8. Pull to Refresh Profile

```swift
// In ProfileView

.refreshable {
    await refreshProfile()
}

@MainActor
private func refreshProfile() async {
    isRefreshing = true
    
    guard let userId = Auth.auth().currentUser?.uid else {
        isRefreshing = false
        return
    }
    
    do {
        // Reload all data
        async let posts = RealtimePostService.shared.fetchUserPosts(userId: userId)
        async let saved = RealtimeSavedPostsService.shared.fetchSavedPosts()
        async let reposts = RealtimeRepostsService.shared.fetchUserReposts(userId: userId)
        async let replies = RealtimeCommentsService.shared.fetchUserComments(userId: userId)
        
        (userPosts, savedPosts, self.reposts, userReplies) = try await (posts, saved, reposts, replies)
        
        print("✅ Profile refreshed")
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
    } catch {
        print("❌ Refresh failed: \(error)")
    }
    
    isRefreshing = false
}
```

---

### 9. Handle NotificationCenter Events

```swift
// In ProfileView

.onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
    guard let userInfo = notification.userInfo,
          let newPost = userInfo["post"] as? Post,
          let isOptimistic = userInfo["isOptimistic"] as? Bool,
          isOptimistic else { return }
    
    // Add optimistic post to UI
    if !userPosts.contains(where: { $0.id == newPost.id }) {
        userPosts.insert(newPost, at: 0)
        print("⚡ Optimistic post added instantly")
    }
}

.onReceive(NotificationCenter.default.publisher(for: Notification.Name("postDeleted"))) { notification in
    guard let userInfo = notification.userInfo,
          let postId = userInfo["postId"] as? UUID else { return }
    
    // Remove from all arrays
    userPosts.removeAll { $0.id == postId }
    savedPosts.removeAll { $0.id == postId }
    reposts.removeAll { $0.id == postId }
    
    print("🗑️ Post removed: \(postId)")
}

.onReceive(NotificationCenter.default.publisher(for: Notification.Name("postSaved"))) { notification in
    guard let userInfo = notification.userInfo,
          let post = userInfo["post"] as? Post else { return }
    
    if !savedPosts.contains(where: { $0.id == post.id }) {
        savedPosts.insert(post, at: 0)
        print("🔖 Post saved: \(post.id)")
    }
}

.onReceive(NotificationCenter.default.publisher(for: Notification.Name("postUnsaved"))) { notification in
    guard let userInfo = notification.userInfo,
          let postId = userInfo["postId"] as? UUID else { return }
    
    savedPosts.removeAll { $0.id == postId }
    print("🔖 Post unsaved: \(postId)")
}

.onReceive(NotificationCenter.default.publisher(for: Notification.Name("postReposted"))) { notification in
    guard let userInfo = notification.userInfo,
          let post = userInfo["post"] as? Post else { return }
    
    if !reposts.contains(where: { $0.id == post.id }) {
        reposts.insert(post, at: 0)
        print("🔄 Post reposted: \(post.id)")
    }
}
```

---

### 10. Error Handling Pattern

```swift
// Standard error handling pattern for all service calls

Task {
    do {
        // Attempt operation
        try await serviceOperation()
        
        // Success feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("✅ Operation successful")
        }
        
    } catch FirebaseError.unauthorized {
        await MainActor.run {
            showError("You must be signed in")
        }
        
    } catch FirebaseError.documentNotFound {
        await MainActor.run {
            showError("Data not found")
        }
        
    } catch FirebaseError.imageCompressionFailed {
        await MainActor.run {
            showError("Failed to process image")
        }
        
    } catch {
        await MainActor.run {
            showError(error.localizedDescription)
        }
    }
}

private func showError(_ message: String) {
    errorMessage = message
    showErrorAlert = true
    
    let haptic = UINotificationFeedbackGenerator()
    haptic.notificationOccurred(.error)
    
    print("❌ Error: \(message)")
}
```

---

## 🎯 Complete Integration Example

Here's a complete example showing ProfileView with all services integrated:

```swift
struct ProfileView: View {
    // Services
    @StateObject private var userService = UserService.shared
    @StateObject private var followService = FollowService.shared
    
    // State
    @State private var profileData = UserProfileData(
        name: "",
        username: "",
        bio: "",
        initials: "",
        profileImageURL: nil,
        interests: [],
        socialLinks: []
    )
    
    @State private var userPosts: [Post] = []
    @State private var savedPosts: [Post] = []
    @State private var reposts: [Post] = []
    @State private var userReplies: [Comment] = []
    
    @State private var isLoading = false
    @State private var listenersActive = false
    @State private var selectedTab = ProfileTab.posts
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeaderView
                    tabSelectorView
                    
                    if isLoading {
                        ProgressView()
                            .padding(.top, 100)
                    } else {
                        contentView
                    }
                }
            }
            .refreshable {
                await refreshProfile()
            }
        }
        .onAppear {
            if !listenersActive {
                Task {
                    await loadProfileData()
                }
            }
        }
    }
    
    @MainActor
    private func loadProfileData() async {
        isLoading = true
        
        // 1. Load user profile
        await userService.fetchCurrentUser()
        
        guard let user = userService.currentUser,
              let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        // 2. Update profile data
        profileData = UserProfileData(
            name: user.displayName,
            username: user.username,
            bio: user.bio,
            initials: user.initials,
            profileImageURL: user.profileImageURL,
            interests: user.interests,
            socialLinks: convertSocialLinks(user.socialLinks)
        )
        
        // 3. Load all tab data
        do {
            async let posts = RealtimePostService.shared.fetchUserPosts(userId: userId)
            async let saved = RealtimeSavedPostsService.shared.fetchSavedPosts()
            async let reposted = RealtimeRepostsService.shared.fetchUserReposts(userId: userId)
            async let replies = RealtimeCommentsService.shared.fetchUserComments(userId: userId)
            
            (userPosts, savedPosts, reposts, userReplies) = try await (posts, saved, reposted, replies)
            
            // 4. Setup listeners
            setupRealtimeDatabaseListeners(userId: userId)
            listenersActive = true
            
            print("✅ Profile loaded successfully")
            
        } catch {
            print("❌ Error loading profile: \(error)")
        }
        
        isLoading = false
    }
    
    @MainActor
    private func setupRealtimeDatabaseListeners(userId: String) {
        RealtimePostService.shared.observeUserPosts(userId: userId) { posts in
            self.userPosts = posts
        }
        
        RealtimeSavedPostsService.shared.observeSavedPosts { _ in
            Task {
                if let posts = try? await RealtimeSavedPostsService.shared.fetchSavedPosts() {
                    await MainActor.run {
                        self.savedPosts = posts
                    }
                }
            }
        }
        
        RealtimeRepostsService.shared.observeUserReposts(userId: userId) { posts in
            self.reposts = posts
        }
        
        print("✅ Real-time listeners active")
    }
    
    @MainActor
    private func refreshProfile() async {
        // Implementation from example 8 above
    }
    
    private func convertSocialLinks(_ links: [[String: String]]) -> [SocialLinkUI] {
        return links.compactMap { dict in
            guard let platform = dict["platform"],
                  let username = dict["username"],
                  let platformEnum = SocialLinkUI.SocialPlatform(rawValue: platform) else {
                return nil
            }
            return SocialLinkUI(platform: platformEnum, username: username)
        }
    }
}
```

---

## 📚 Service Reference Quick Guide

### UserService
```swift
// Fetch profile
await UserService.shared.fetchCurrentUser()
let user = UserService.shared.currentUser

// Update profile
try await UserService.shared.updateProfile(displayName: "Name", bio: "Bio")

// Upload avatar
let url = try await UserService.shared.uploadProfileImage(image)

// Remove avatar
try await UserService.shared.removeProfileImage()

// Save interests
try await UserService.shared.saveOnboardingPreferences(
    interests: ["Faith"],
    goals: ["Prayer"],
    prayerTime: "Morning"
)
```

### SocialLinksService
```swift
// Update links
let links = [SocialLinkData(platform: "Instagram", username: "user")]
try await SocialLinksService.shared.updateSocialLinks(links)

// Add link
try await SocialLinksService.shared.addSocialLink(platform: "Twitter", username: "user")

// Remove link
try await SocialLinksService.shared.removeSocialLink(platform: "Instagram")

// Fetch links
let links = try await SocialLinksService.shared.fetchSocialLinks()
```

### RealtimePostService
```swift
// Fetch posts
let posts = try await RealtimePostService.shared.fetchUserPosts(userId: userId)

// Observe posts
RealtimePostService.shared.observeUserPosts(userId: userId) { posts in
    self.userPosts = posts
}

// Fetch single post
let post = try await RealtimePostService.shared.fetchPost(postId: postId)
```

### RealtimeSavedPostsService
```swift
// Toggle save
let isSaved = try await RealtimeSavedPostsService.shared.toggleSavePost(postId: postId)

// Fetch saved
let saved = try await RealtimeSavedPostsService.shared.fetchSavedPosts()

// Observe saved
RealtimeSavedPostsService.shared.observeSavedPosts { postIds in
    // Handle update
}
```

### RealtimeRepostsService
```swift
// Repost
try await RealtimeRepostsService.shared.repostPost(postId: postId, originalPost: post)

// Undo repost
try await RealtimeRepostsService.shared.undoRepost(postId: postId)

// Fetch reposts
let reposts = try await RealtimeRepostsService.shared.fetchUserReposts(userId: userId)

// Observe reposts
RealtimeRepostsService.shared.observeUserReposts(userId: userId) { posts in
    self.reposts = posts
}
```

### RealtimeCommentsService
```swift
// Create comment
let comment = try await RealtimeCommentsService.shared.createComment(
    postId: postId,
    content: "Great post!",
    authorId: userId,
    authorName: name,
    authorUsername: username,
    authorInitials: initials,
    authorProfileImageURL: imageURL
)

// Fetch user comments
let replies = try await RealtimeCommentsService.shared.fetchUserComments(userId: userId)

// Observe comments
RealtimeCommentsService.shared.observeComments(postId: postId) { comments in
    self.comments = comments
}

// Delete comment
try await RealtimeCommentsService.shared.deleteComment(
    commentId: commentId,
    postId: postId,
    authorId: userId
)
```

---

## ✅ That's Everything!

All the code you need to integrate the complete profile system is now in these examples. Just copy and paste into your project!

**Ready to ship! 🚀**
