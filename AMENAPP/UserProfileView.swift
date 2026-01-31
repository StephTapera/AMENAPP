//
//  UserProfileView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import FirebaseFirestore
import Combine

// MARK: - Data Models

struct ProfilePost: Identifiable {
    let id: String  // Real Firestore post ID
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
    let postType: PostType?  // Type of post
    
    enum PostType: String {
        case prayer = "Prayer"
        case testimony = "Testimony"
        case openTable = "OpenTable"
        
        var icon: String {
            switch self {
            case .prayer: return "hands.sparkles.fill"
            case .testimony: return "quote.bubble.fill"
            case .openTable: return "book.closed.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .prayer: return .blue
            case .testimony: return .orange
            case .openTable: return .black  // Black for OpenTable
            }
        }
        
        // Liquid glass style - uses blur and transparency
        var isLiquidGlassStyle: Bool {
            switch self {
            case .prayer, .testimony: return true
            case .openTable: return false  // Simple black/white for OpenTable
            }
        }
    }
}

struct Reply: Identifiable {
    let id = UUID()
    let originalAuthor: String
    let originalContent: String
    let replyContent: String
    let timestamp: String
}

struct UserProfile {
    var userId: String
    var name: String
    var username: String
    var bio: String
    var initials: String
    var profileImageURL: String?
    var interests: [String]
    var socialLinks: [UserSocialLink]
    var followersCount: Int
    var followingCount: Int
    var isPrivateAccount: Bool = false  // Privacy indicator
}

struct UserSocialLink: Identifiable {
    let id = UUID()
    let platform: Platform
    let username: String
    
    enum Platform {
        case twitter
        case linkedin
        case instagram
        case website
        
        var icon: String {
            switch self {
            case .twitter: return "x.circle.fill"
            case .linkedin: return "link.circle.fill"
            case .instagram: return "camera.circle.fill"
            case .website: return "globe"
            }
        }
        
        var displayName: String {
            switch self {
            case .twitter: return "X (Twitter)"
            case .linkedin: return "LinkedIn"
            case .instagram: return "Instagram"
            case .website: return "Website"
            }
        }
    }
}

// MARK: - User Profile Enums

enum UserReportReason: String, CaseIterable {
    case spam = "Spam"
    case harassment = "Harassment or Bullying"
    case inappropriate = "Inappropriate Content"
    case impersonation = "Impersonation"
    case falseInfo = "False Information"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .spam: return "envelope.badge.fill"
        case .harassment: return "exclamationmark.triangle.fill"
        case .inappropriate: return "eye.slash.fill"
        case .impersonation: return "person.crop.circle.badge.exclamationmark"
        case .falseInfo: return "checkmark.circle.trianglebadge.exclamationmark"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum UserProfileTab: String, CaseIterable {
    case posts = "Posts"
    case reposts = "Reposts"
    
    var icon: String {
        switch self {
        case .posts: return "square.grid.2x2"
        case .reposts: return "arrow.2.squarepath"
        }
    }
}

/// User Profile View - For viewing other users' profiles
/// Threads-inspired with Black & White Design
struct UserProfileView: View {
    let userId: String // In a real app, this would be used to fetch the user's data
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: UserProfileTab = .posts
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var showFullScreenAvatar = false
    @State private var showReportOptions = false
    @State private var showBlockAlert = false
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    @State private var showMessaging = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isFollowing = false
    @State private var isBlocked = false
    @State private var isMuted = false  // Privacy: Mute status
    @State private var isHidden = false  // Privacy: Hidden from this user
    @State private var profileData: UserProfile?
    @State private var posts: [ProfilePost] = []
    @State private var reposts: [UserProfileRepost] = []
    @State private var selectedReportReason: UserReportReason?
    @State private var reportDescription = ""
    @State private var currentPage = 1
    @State private var hasMorePosts = true
    @State private var isLoadingMore = false
    @State private var followerCountListener: ListenerRegistration?
    @State private var selectedPostForComments: Post?
    @State private var showCommentsSheet = false
    @State private var showUnfollowAlert = false  // New: Unfollow confirmation
    @State private var scrollOffset: CGFloat = 0  // New: Track scroll position
    @State private var showBackToTop = false  // Smart scroll
    @State private var showInlineError = false  // Error recovery
    @State private var inlineErrorMessage = ""
    @StateObject private var scrollManager = SmartScrollManager()
    @Namespace private var tabNamespace
    
    // Computed property to determine if buttons should be in toolbar
    private var shouldShowToolbarButtons: Bool {
        scrollOffset > 200  // Show in toolbar after scrolling 200 points
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollViewWithOffset(offset: $scrollOffset) {
                    VStack(spacing: 0) {
                        // Inline error banner
                        if showInlineError {
                            InlineErrorBanner(
                                message: inlineErrorMessage,
                                onRetry: {
                                    await loadProfileData()
                                },
                                onDismiss: {
                                    withAnimation {
                                        showInlineError = false
                                    }
                                }
                            )
                            .padding(.top, 12)
                        }
                        
                        // Profile Header
                        profileHeaderView
                        
                        // Tab Selector
                        tabSelectorView
                        
                        // Content based on selected tab
                        if isLoading {
                            // Skeleton loading state
                            SkeletonProfileHeader()
                            
                            VStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { _ in
                                    SkeletonProfileCard()
                                }
                            }
                            .padding(.top, 12)
                        } else {
                            contentView
                        }
                    }
                }
                .onChange(of: scrollOffset) { _, newValue in
                    // Show/hide back to top button
                    showBackToTop = newValue > 500
                }
                .refreshable {
                    await refreshProfile()
                }
                .background(Color(white: 0.98))
                
                // Back to top button
                if showBackToTop {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    scrollOffset = 0
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back to top")
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.8))
                                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                                )
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarButtonsView
                }
            }
            .fullScreenCover(isPresented: $showFullScreenAvatar) {
                if let profileData = profileData {
                    FullScreenAvatarView(name: profileData.name, initials: profileData.initials, profileImageURL: profileData.profileImageURL)
                }
            }
            .alert("Block User", isPresented: $showBlockAlert) {
                Button("Cancel", role: .cancel) { }
                Button(isBlocked ? "Unblock" : "Block", role: .destructive) {
                    toggleBlock()
                }
            } message: {
                Text(isBlocked ? "Are you sure you want to unblock \(profileData?.name ?? "this user")?" : "Are you sure you want to block \(profileData?.name ?? "this user")? You won't see their posts or be able to message them.")
            }
            .alert("Unfollow", isPresented: $showUnfollowAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unfollow", role: .destructive) {
                    Task {
                        await performFollowAction()
                    }
                }
            } message: {
                Text("Are you sure you want to unfollow \(profileData?.name ?? "this user")?")
            }
            .sheet(isPresented: $showReportOptions) {
                if let profileData = profileData {
                    ReportUserView(
                        userName: profileData.name,
                        userId: userId,
                        onSubmit: { reason, description in
                            submitReport(reason: reason, description: description)
                        }
                    )
                }
            }
            .sheet(isPresented: $showFollowersList) {
                FollowersListView(userId: userId, type: .followers)
            }
            .sheet(isPresented: $showFollowingList) {
                FollowersListView(userId: userId, type: .following)
            }
            .sheet(isPresented: $showMessaging) {
                if let profileData = profileData {
                    ChatConversationLoader(
                        userId: profileData.userId,
                        userName: profileData.name
                    )
                }
            }
            .sheet(isPresented: $showCommentsSheet) {
                if let post = selectedPostForComments {
                    PostCommentsView(post: post)
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
                Button("Retry") {
                    Task { await loadProfileData() }
                }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await loadProfileData()
        }
        .onDisappear {
            // Clean up listener when leaving profile
            removeFollowerCountListener()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fK", thousands)
        }
        return "\(count)"
    }
    
    // MARK: - Refresh Function
    
    /// Set up real-time listener for follower/following counts on viewed profile
    @MainActor
    private func setupFollowerCountListener() {
        print("🔊 Setting up real-time listener for user \(userId)'s follower counts...")
        
        // Remove existing listener if any
        followerCountListener?.remove()
        
        // Listen to Firestore user document for count updates
        let db = Firestore.firestore()
        followerCountListener = db.collection("users").document(userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Follower count listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists, let data = snapshot.data() else {
                    print("⚠️ User document not found or has no data")
                    return
                }
                
                let followersCount = data["followersCount"] as? Int ?? 0
                let followingCount = data["followingCount"] as? Int ?? 0
                
                Task { @MainActor in
                    // Update profile data with new counts
                    if var profile = self.profileData {
                        profile.followersCount = followersCount
                        profile.followingCount = followingCount
                        self.profileData = profile
                        
                        print("✅ Real-time follower count update: \(followersCount) followers, \(followingCount) following")
                    }
                }
            }
    }
    
    /// Remove follower count listener
    @MainActor
    private func removeFollowerCountListener() {
        followerCountListener?.remove()
        followerCountListener = nil
        print("🔇 Removed follower count listener")
    }
    
    // MARK: - Profile Data Loading
    
    @MainActor
    private func refreshProfile() async {
        isRefreshing = true
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Reload profile data
        await loadProfileData()
        
        isRefreshing = false
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    @MainActor
    private func loadProfileData() async {
        isLoading = true
        errorMessage = ""
        
        do {
            print("👤 Loading profile data for user ID: \(userId)")
            
            // Validate userId is not empty
            guard !userId.isEmpty else {
                print("❌ User ID is empty!")
                throw NSError(domain: "UserProfileView", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid user ID. Please try again."
                ])
            }
            
            // Fetch user profile directly from Firestore
            let db = Firestore.firestore()
            
            print("📡 Attempting to fetch document from Firestore...")
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            print("📄 Document fetch completed. Exists: \(userDoc.exists)")
            
            guard userDoc.exists else {
                print("❌ User document does not exist for ID: \(userId)")
                print("   This could mean:")
                print("   1. The user was deleted")
                print("   2. The userId is incorrect")
                print("   3. The document path is wrong")
                throw NSError(domain: "UserProfileView", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "User not found. This profile may no longer exist."
                ])
            }
            
            guard let data = userDoc.data() else {
                print("❌ User document exists but has no data for ID: \(userId)")
                throw NSError(domain: "UserProfileView", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "User data could not be loaded. Please try again later."
                ])
            }
            
            print("✅ Found user document with data: \(data.keys)")
            
            // Extract user data with detailed logging
            let displayName = data["displayName"] as? String ?? "Unknown User"
            let username = data["username"] as? String ?? "unknown"
            let bio = data["bio"] as? String ?? ""
            let profileImageURL = data["profileImageURL"] as? String
            let interests = data["interests"] as? [String] ?? []
            let followersCount = data["followersCount"] as? Int ?? 0
            let followingCount = data["followingCount"] as? Int ?? 0
            let isPrivateAccount = data["isPrivateAccount"] as? Bool ?? false  // ✅ FIX: Actually load from Firestore
            
            print("📋 User data extracted:")
            print("   - displayName: \(displayName)")
            print("   - username: \(username)")
            print("   - bio length: \(bio.count)")
            print("   - followersCount: \(followersCount)")
            print("   - followingCount: \(followingCount)")
            print("   - isPrivateAccount: \(isPrivateAccount)")
            
            // Generate initials
            let names = displayName.components(separatedBy: " ")
            let initials = names.compactMap { $0.first }.map { String($0) }.joined().prefix(2).uppercased()
            
            print("✅ Fetched user: \(displayName) (@\(username))")
            
            // Convert to UserProfile
            profileData = UserProfile(
                userId: userId,  // Store the real userId
                name: displayName,
                username: username,
                bio: bio,
                initials: String(initials),
                profileImageURL: profileImageURL,
                interests: interests,
                socialLinks: [], // TODO: Add social links to UserModel if needed
                followersCount: followersCount,
                followingCount: followingCount,
                isPrivateAccount: isPrivateAccount  // ✅ FIX: Include in UserProfile
            )
            
            print("✅ Profile data converted successfully")
            
            // Fetch user's content in parallel
            print("📥 Starting parallel fetch for posts, reposts, follow status, and privacy status...")
            
            async let postsTask = fetchUserPosts(page: 1)
            async let repostsTask = fetchUserReposts()
            async let followStatusTask = checkFollowStatus()
            async let privacyStatusTask = checkPrivacyStatus()  // ✅ FIX: Actually load privacy status
            
            // Await all tasks
            (posts, reposts, isFollowing) = try await (postsTask, repostsTask, followStatusTask)
            await privacyStatusTask  // ✅ FIX: Privacy check doesn't return a value
            
            print("✅ Parallel fetch completed:")
            print("   - Posts: \(posts.count)")
            print("   - Reposts: \(reposts.count)")
            print("   - Following: \(isFollowing)")
            
            // 🔊 SET UP REAL-TIME LISTENER for follower/following counts
            setupFollowerCountListener()
            
            currentPage = 1
            hasMorePosts = posts.count >= 20
            
        } catch {
            print("❌ Error in loadProfileData:")
            print("   - Error type: \(type(of: error))")
            print("   - Error description: \(error.localizedDescription)")
            print("   - Error: \(error)")
            
            // 🔌 OFFLINE HANDLING: Check if error is network-related
            let isOfflineError = error.localizedDescription.contains("offline") ||
                                 error.localizedDescription.contains("network") ||
                                 error.localizedDescription.contains("no active listeners") ||
                                 (error as NSError).domain == NSURLErrorDomain
            
            if isOfflineError {
                // Handle offline gracefully with user-friendly message
                print("📵 Device appears to be offline. Using cached data if available.")
                errorMessage = "You're offline. Showing cached data."
                inlineErrorMessage = "No internet connection. Some content may be outdated."
                withAnimation {
                    showInlineError = true
                }
                
                // Try to use cached data if we have it
                if profileData == nil {
                    // No cached profile data, show placeholder
                    errorMessage = "Unable to load profile. Please check your internet connection."
                    showErrorAlert = true
                }
            } else {
                // Handle other errors normally
                errorMessage = handleError(error)
                
                // Show inline error for minor issues, full alert for critical
                if error.localizedDescription.contains("not found") || error.localizedDescription.contains("404") {
                    showErrorAlert = true
                } else {
                    inlineErrorMessage = errorMessage
                    withAnimation {
                        showInlineError = true
                    }
                }
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Network Calls
    
    private func fetchUserPosts(page: Int) async throws -> [ProfilePost] {
        print("📥 Fetching posts for user: \(userId) (page: \(page))")
        
        // Use FirebasePostService to fetch real user posts
        let firebasePostService = FirebasePostService.shared
        let userPosts = try await firebasePostService.fetchUserOriginalPosts(userId: userId)
        
        print("✅ Fetched \(userPosts.count) posts for user")
        
        // Convert Post to ProfilePost with real IDs and post types
        return userPosts.map { post in
            // Determine post type from category field
            let postType: ProfilePost.PostType?
            switch post.category {
            case .prayer:
                postType = .prayer
            case .testimonies:
                postType = .testimony
            case .openTable:
                postType = .openTable
            }
            
            // Convert post.id (UUID) to String, or generate new UUID string if nil
            let postId = post.id.uuidString ?? UUID().uuidString
            
            return ProfilePost(
                id: postId,  // Real Firestore post ID
                content: post.content,
                timestamp: post.timeAgo,
                likes: post.amenCount,
                replies: post.commentCount,
                postType: postType
            )
        }
    }
    
    private func fetchUserReplies() async throws -> [Reply] {
        // Replies are now private - not shown on public profile
        print("📥 Replies are hidden from public profiles")
        return []
    }
    
    private func fetchUserReposts() async throws -> [UserProfileRepost] {
        print("📥 Fetching reposts for user: \(userId)")
        
        // Use FirebasePostService to fetch real user reposts
        let firebasePostService = FirebasePostService.shared
        let userReposts = try await firebasePostService.fetchUserReposts(userId: userId)
        
        print("✅ Fetched \(userReposts.count) reposts for user")
        
        // Convert Post to UserProfileRepost
        return userReposts.map { post in
            UserProfileRepost(
                originalAuthor: post.originalAuthorName ?? "Unknown",
                content: post.content,
                timestamp: post.timeAgo,
                likes: post.amenCount,
                replies: post.commentCount
            )
        }
    }
    
    private func checkFollowStatus() async throws -> Bool {
        // Use FollowService to check if current user is following this profile
        let followService = FollowService.shared
        let isFollowing = await followService.isFollowing(userId: userId)
        
        print("✅ Follow status for \(userId): \(isFollowing ? "following" : "not following")")
        
        return isFollowing
    }
    
    /// Check privacy status (mute, hide, block)
    @MainActor
    private func checkPrivacyStatus() async {
        do {
            let moderationService = ModerationService.shared
            
            // Check if user is blocked
            isBlocked = await moderationService.isBlocked(userId: userId)
            
            // Check if user is muted
            isMuted = await moderationService.isMuted(userId: userId)
            
            // Check if profile is hidden from this user
            isHidden = await moderationService.isHiddenFrom(userId: userId)
            
            print("✅ Privacy status loaded:")
            print("   - Blocked: \(isBlocked)")
            print("   - Muted: \(isMuted)")
            print("   - Hidden: \(isHidden)")
            
        } catch {
            print("⚠️ Failed to load privacy status: \(error)")
            // Don't show error to user, just use default values
        }
    }
    
    private func loadMorePosts() async {
        guard !isLoadingMore && hasMorePosts else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            let newPosts = try await fetchUserPosts(page: currentPage)
            
            await MainActor.run {
                posts.append(contentsOf: newPosts)
                hasMorePosts = newPosts.count >= 20
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
                currentPage -= 1
            }
        }
    }
    
    private func handleError(_ error: Error) -> String {
        print("🔍 Analyzing error in UserProfileView:")
        print("   - Error type: \(type(of: error))")
        print("   - Localized description: \(error.localizedDescription)")
        
        // Handle Firestore errors
        if let firestoreError = error as NSError? {
            print("   - Error code: \(firestoreError.code)")
            print("   - Error domain: \(firestoreError.domain)")
            
            // Check for specific Firestore error codes
            if firestoreError.domain == "FIRFirestoreErrorDomain" {
                switch firestoreError.code {
                case 7: // Permission denied - Only show this for ACTUAL permission errors
                    return "You don't have permission to view this profile."
                case 5: // Not found
                    return "User not found. This profile may no longer exist."
                case 14: // Unavailable (network)
                    return "Unable to connect to server. Please check your connection."
                case 2: // Aborted
                    return "Request was aborted. Please try again."
                case 4: // Deadline exceeded
                    return "Request timed out. Please try again."
                default:
                    // Don't treat unknown errors as permission errors
                    print("   ⚠️ Unknown Firestore error code: \(firestoreError.code)")
                    break
                }
            }
        }
        
        // Handle network errors
        if let networkError = error as? URLError {
            switch networkError.code {
            case .notConnectedToInternet:
                return "No internet connection. Please check your network settings."
            case .timedOut:
                return "Request timed out. Please try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Cannot reach server. Please try again later."
            default:
                return "Network error occurred. Please try again."
            }
        }
        
        // Handle custom errors
        if let nsError = error as NSError?, nsError.domain == "UserProfileView" {
            return nsError.localizedDescription
        }
        
        // Log the full error for debugging
        print("⚠️ Unhandled error type: \(error)")
        
        // Default fallback - don't mention permissions unless it's confirmed
        if error.localizedDescription.lowercased().contains("permission") {
            return "Permission issue. Please try signing out and back in."
        }
        
        return "Unable to load profile. Please check your connection and try again."
    }
    
    // MARK: - Actions
    
    private func toggleFollow() {
        // If currently following, show confirmation alert
        if isFollowing {
            showUnfollowAlert = true
        } else {
            // If not following, follow immediately
            Task {
                await performFollowAction()
            }
        }
    }
    
    @MainActor
    private func performFollowAction() async {
        guard let profile = profileData else { return }
        
        let previousState = isFollowing
        
        // Only toggle the button state optimistically, not the count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFollowing.toggle()
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            // Use FollowService to toggle follow
            let followService = FollowService.shared
            try await followService.toggleFollow(userId: userId)
            
            print("✅ Successfully \(isFollowing ? "followed" : "unfollowed") user: \(userId)")
            
            // Refetch the profile to get the updated follower count from backend
            await refreshFollowerCount()
            
        } catch {
            // Rollback on error
            await MainActor.run {
                isFollowing = previousState
                
                // Provide more specific error message
                if let nsError = error as NSError? {
                    print("❌ Failed to toggle follow: \(nsError)")
                    print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                    print("   Description: \(nsError.localizedDescription)")
                    
                    // Show more helpful error based on error type
                    if nsError.domain == NSURLErrorDomain {
                        errorMessage = "Network error. Check your connection and try again."
                    } else if nsError.localizedDescription.contains("permission") || nsError.localizedDescription.contains("unauthorized") {
                        errorMessage = "Permission denied. Please try signing out and back in."
                    } else {
                        errorMessage = "Failed to \(previousState ? "unfollow" : "follow") user. Please try again.\n\nError: \(nsError.localizedDescription)"
                    }
                } else {
                    errorMessage = "Failed to \(previousState ? "unfollow" : "follow") user. Please try again."
                    print("❌ Failed to toggle follow: \(error)")
                }
                
                showErrorAlert = true
            }
        }
    }
    
    @MainActor
    private func refreshFollowerCount() async {
        do {
            // Fetch updated counts from Firestore directly
            let db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            guard let data = userDoc.data() else { return }
            
            let followersCount = data["followersCount"] as? Int ?? 0
            let followingCount = data["followingCount"] as? Int ?? 0
            
            // Only update the counts, preserve other data
            if var profile = profileData {
                profile.followersCount = followersCount
                profile.followingCount = followingCount
                profileData = profile
            }
            
            print("✅ Refreshed follower count: \(followersCount)")
        } catch {
            print("⚠️ Failed to refresh follower count: \(error)")
            // Don't show error to user, counts will update on next refresh
        }
    }
    
    private func sendMessage() {
        // Check if user is blocked
        guard !isBlocked else {
            errorMessage = "You cannot message blocked users."
            showErrorAlert = true
            return
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Navigate to messaging
        showMessaging = true
        
        // TODO: Alternative navigation using NavigationPath
        // navigationPath.append(MessagingRoute.conversation(userId: userId))
    }
    
    private func shareProfile() {
        guard let profileData = profileData else { return }
        
        let username = "@\(profileData.username)"
        let shareText = "Check out \(profileData.name)'s AMEN profile: \(username)"
        let shareURL = URL(string: "https://amenapp.com/\(profileData.username)")!
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText, shareURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true)
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func reportUser() {
        showReportOptions = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func submitReport(reason: UserReportReason, description: String) {
        Task {
            do {
                // Real backend call using ModerationService
                let moderationService = ModerationService.shared
                
                // Convert UserReportReason to ModerationReportReason
                let moderationReason = convertToModerationReason(reason)
                
                try await moderationService.reportUser(
                    userId: userId,
                    reason: moderationReason,
                    additionalDetails: description
                )
                
                print("✅ Successfully reported user: \(userId) for: \(reason.rawValue)")
                
                // Show confirmation
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
                
            } catch {
                print("❌ Failed to report user: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to submit report. Please try again."
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func convertToModerationReason(_ reason: UserReportReason) -> ModerationReportReason {
        switch reason {
        case .spam: return .spam
        case .harassment: return .harassment
        case .inappropriate: return .inappropriateContent
        case .impersonation: return .other  // Map to .other since impersonation isn't available
        case .falseInfo: return .falseInformation
        case .other: return .other
        }
    }
    
    private func toggleBlock() {
        Task {
            await performBlockAction()
        }
    }
    
    @MainActor
    private func performBlockAction() async {
        let previousState = isBlocked
        isBlocked.toggle()
        
        // If blocking, automatically unfollow and unmute
        if isBlocked {
            isFollowing = false
            isMuted = false  // ✅ FIX: Blocking overrides mute
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(isBlocked ? .warning : .success)
        
        do {
            // Real backend call using ModerationService
            let moderationService = ModerationService.shared
            if isBlocked {
                try await moderationService.blockUser(userId: userId)
                print("✅ Successfully blocked user: \(userId)")
            } else {
                try await moderationService.unblockUser(userId: userId)
                print("✅ Successfully unblocked user: \(userId)")
            }
            
        } catch {
            // Rollback on error
            await MainActor.run {
                isBlocked = previousState
                errorMessage = "Failed to \(previousState ? "unblock" : "block") user. Please try again."
                showErrorAlert = true
            }
            print("❌ Failed to toggle block: \(error)")
        }
    }
    
    // MARK: - Privacy Controls
    
    /// **Privacy Control Features:**
    /// 
    /// **1. Mute User**
    /// - Hides posts from this user in your feed without unfollowing
    /// - User is not notified when muted
    /// - Can be toggled on/off at any time
    /// - Automatically cleared when user is blocked
    ///
    /// **2. Hide from User**
    /// - Hides YOUR profile from THIS specific user
    /// - They won't be able to see your profile or posts
    /// - Useful for privacy without full blocking
    /// - Can be reversed at any time
    ///
    /// **3. Block User**
    /// - Strongest privacy control
    /// - Automatically unfollows and clears mute status
    /// - Prevents all interactions between users
    /// - Can view and manage in settings
    ///
    /// **4. Private Account Indicator**
    /// - Shows lock badge next to name for private accounts
    /// - Indicates content is only visible to approved followers
    /// - Stored in user's Firestore document as `isPrivateAccount`
    
    /// Toggle mute status for this user
    private func toggleMute() {
        Task {
            await performMuteAction()
        }
    }
    
    @MainActor
    private func performMuteAction() async {
        let previousState = isMuted
        isMuted.toggle()
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            // Real backend call using ModerationService
            let moderationService = ModerationService.shared
            if isMuted {
                try await moderationService.muteUser(userId: userId)
                print("✅ Successfully muted user: \(userId)")
            } else {
                try await moderationService.unmuteUser(userId: userId)
                print("✅ Successfully unmuted user: \(userId)")
            }
            
        } catch {
            // Rollback on error
            await MainActor.run {
                isMuted = previousState
                errorMessage = "Failed to \(previousState ? "unmute" : "mute") user. Please try again."
                showErrorAlert = true
            }
            print("❌ Failed to toggle mute: \(error)")
        }
    }
    
    /// Toggle hide status - hide your profile from this user
    private func toggleHide() {
        Task {
            await performHideAction()
        }
    }
    
    @MainActor
    private func performHideAction() async {
        let previousState = isHidden
        isHidden.toggle()
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            // Real backend call using privacy service
            // This would hide YOUR profile from THIS user
            let moderationService = ModerationService.shared
            if isHidden {
                // Hide your profile from this user
                try await moderationService.hideProfileFromUser(userId: userId)
                print("✅ Successfully hid profile from user: \(userId)")
            } else {
                // Unhide your profile from this user
                try await moderationService.unhideProfileFromUser(userId: userId)
                print("✅ Successfully unhid profile from user: \(userId)")
            }
            
        } catch {
            // Rollback on error
            await MainActor.run {
                isHidden = previousState
                errorMessage = "Failed to \(previousState ? "unhide from" : "hide from") user. Please try again."
                showErrorAlert = true
            }
            print("❌ Failed to toggle hide: \(error)")
        }
    }
    
    // MARK: - Deep Linking
    
    private func handleDeepLink(_ url: URL) {
        // Handle deep links like amenapp://user/username or https://amenapp.com/user/username
        print("Handling deep link: \(url)")
        
        // TODO: Parse URL and navigate accordingly
        // if url.pathComponents.contains("user") {
        //     // Already on user profile, potentially reload with different user
        // }
    }
    
    // MARK: - Toolbar Buttons
    
    @ViewBuilder
    private var toolbarButtonsView: some View {
        HStack(spacing: 12) {
            // Show Follow/Message buttons in toolbar when scrolled
            if shouldShowToolbarButtons {
                Button {
                    toggleFollow()
                } label: {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFollowing ? .blue : .black)
                }
                .transition(.scale.combined(with: .opacity))
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "message.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            Button {
                shareProfile()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
            }
            
            Menu {
                // Privacy Controls Section
                Section {
                    Button {
                        toggleMute()
                    } label: {
                        Label(isMuted ? "Unmute User" : "Mute User", systemImage: isMuted ? "speaker.wave.2" : "speaker.slash")
                    }
                    
                    Button {
                        toggleHide()
                    } label: {
                        Label(isHidden ? "Unhide from User" : "Hide from User", systemImage: isHidden ? "eye" : "eye.slash")
                    }
                }
                
                // Reporting Section
                Section {
                    Button {
                        reportUser()
                    } label: {
                        Label("Report User", systemImage: "exclamationmark.triangle")
                    }
                }
                
                // Blocking Section
                Section {
                    Button(role: .destructive) {
                        showBlockAlert = true
                    } label: {
                        Label(isBlocked ? "Unblock User" : "Block User", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowToolbarButtons)
    }
    
    // MARK: - Profile Header
    
    private var messageButtonBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(white: 0.93))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var profileHeaderView: some View {
        VStack(spacing: 0) {
            if let profileData = profileData {
                VStack(spacing: 20) {
                    // Top Section: Avatar and Name
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Name with private account badge
                            HStack(spacing: 8) {
                                Text(profileData.name)
                                    .font(.custom("OpenSans-Bold", size: 28))
                                    .foregroundStyle(.black)
                                
                                // Private account indicator
                                if profileData.isPrivateAccount {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Private")
                                            .font(.custom("OpenSans-SemiBold", size: 11))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.7))
                                    )
                                }
                            }
                            
                            // Username
                            Text("@\(profileData.username)")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.black.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        // Avatar (tappable for full screen)
                        Button {
                            showFullScreenAvatar = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 80, height: 80)
                                
                                Text(profileData.initials)
                                    .font(.custom("OpenSans-Bold", size: 28))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Bio
                    Text(profileData.bio)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(4)
                    
                    // Interests
                    if !profileData.interests.isEmpty {
                        InterestTagsView(interests: profileData.interests)
                    }
                    
                    // Social Links
                    if !profileData.socialLinks.isEmpty {
                        SocialLinksView(socialLinks: profileData.socialLinks)
                    }
                    
                    // Stats (Tappable)
                    HStack(spacing: 24) {
                        Button {
                            showFollowersList = true
                        } label: {
                            StatView(count: formatCount(profileData.followersCount), label: "followers")
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 2, height: 2)
                        
                        Button {
                            showFollowingList = true
                        } label: {
                            StatView(count: formatCount(profileData.followingCount), label: "following")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        // Follow/Following Button (hide when scrolled to toolbar)
                        if !shouldShowToolbarButtons {
                            Button {
                                toggleFollow()
                            } label: {
                                Text(isFollowing ? "Following" : "Follow")
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(isFollowing ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(isFollowing ? Color(white: 0.93) : Color.black)
                                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                                    )
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
                            .transition(.scale.combined(with: .opacity))
                            
                            // Message Button (hide when scrolled to toolbar)
                            Button {
                                sendMessage()
                            } label: {
                                Text("Message")
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(messageButtonBackground)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowToolbarButtons)
                    
                    // Privacy Status Indicators
                    if isMuted || isHidden {
                        VStack(spacing: 8) {
                            if isMuted {
                                PrivacyStatusBadge(
                                    icon: "speaker.slash.fill",
                                    text: "You've muted this user",
                                    color: .orange
                                )
                            }
                            
                            if isHidden {
                                PrivacyStatusBadge(
                                    icon: "eye.slash.fill",
                                    text: "Your profile is hidden from this user",
                                    color: .purple
                                )
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMuted)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHidden)
                    }
                }
                .padding(20)
                .background(Color.white)
            } else {
                // Loading placeholder
                LoadingStateView()
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(UserProfileTab.allCases, id: \.self) { tab in
                Button {
                    // Prevent re-selecting same tab
                    guard selectedTab != tab else { return }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        // Tab label with icon (optional - uncomment to show icons)
                        HStack(spacing: 6) {
                            // Uncomment to show icons alongside text:
                            // Image(systemName: tab.icon)
                            //     .font(.system(size: 14, weight: .semibold))
                            
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 15))
                        }
                        .foregroundStyle(selectedTab == tab ? .black : .black.opacity(0.4))
                        
                        // Active indicator with smooth animation
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.black)
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "tab", in: tabNamespace)
                        } else {
                            Capsule()
                                .fill(Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle()) // Expand tap area
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(tab.rawValue)
                .accessibilityHint("Shows \(tab.rawValue.lowercased()) from this user")
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 20)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .posts:
                UserPostsContentView(
                    posts: posts,
                    onLoadMore: loadMorePosts,
                    hasMorePosts: hasMorePosts,
                    isLoadingMore: isLoadingMore
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case .reposts:
                UserRepostsContentView(reposts: reposts)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
    }
}

// MARK: - Content Views

struct UserPostsContentView: View {
    let posts: [ProfilePost]
    @State private var likedPosts: Set<String> = []
    var onLoadMore: (() async -> Void)?
    var hasMorePosts: Bool = false
    var isLoadingMore: Bool = false
    @State private var selectedPostForComments: Post?
    @State private var showCommentsSheet = false
    @StateObject private var scrollManager = SmartScrollManager()
    
    var body: some View {
        LazyVStack(spacing: 0) {
            if posts.isEmpty {
                UserProfileEmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No Posts Yet",
                    message: "This user hasn't posted anything yet."
                )
                .padding(.top, 20)
            } else {
                ForEach(posts.indices, id: \.self) { index in
                    ReadOnlyProfilePostCard(
                        post: posts[index],
                        isLiked: likedPosts.contains(posts[index].id),
                        onLike: {
                            Task {
                                await handleLike(postId: posts[index].id)
                            }
                        },
                        onReply: {
                            handleReply(postId: posts[index].id)
                        }
                    )
                    
                    // Smart prefetch trigger - loads 5 posts before reaching end
                    if scrollManager.shouldPrefetch(currentIndex: index, totalCount: posts.count, threshold: 5) && hasMorePosts {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                if let onLoadMore = onLoadMore {
                                    scrollManager.prefetch(loadMore: onLoadMore)
                                }
                            }
                    }
                }
                
                // Loading indicator at bottom
                if hasMorePosts && scrollManager.isPrefetching {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Loading more posts...")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .padding(.top, 12)
        .sheet(isPresented: $showCommentsSheet) {
            if let post = selectedPostForComments {
                PostCommentsView(post: post)
            }
        }
        .onDisappear {
            scrollManager.cancel()
        }
    }
    
    @MainActor
    private func handleLike(postId: String) async {
        let wasLiked = likedPosts.contains(postId)
        
        // Optimistic update
        if wasLiked {
            likedPosts.remove(postId)
        } else {
            likedPosts.insert(postId)
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        do {
            // Real API call using PostInteractionsService
            let interactionsService = PostInteractionsService.shared
            try await interactionsService.toggleAmen(postId: postId)
            print("✅ Toggled amen on post: \(postId)")
        } catch {
            // Rollback on error
            await MainActor.run {
                if wasLiked {
                    likedPosts.insert(postId)
                } else {
                    likedPosts.remove(postId)
                }
            }
            print("❌ Failed to toggle amen: \(error)")
        }
    }
    
    private func handleReply(postId: String) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Fetch full post and show comments
        Task {
            do {
                let firebasePostService = FirebasePostService.shared
                // Fetch the full post object by ID
                if let post = try await firebasePostService.fetchPostById(postId: postId) {
                    await MainActor.run {
                        selectedPostForComments = post
                        showCommentsSheet = true
                    }
                } else {
                    print("⚠️ Post not found: \(postId)")
                }
            } catch {
                print("❌ Failed to fetch post for comments: \(error)")
            }
        }
    }
}

// MARK: - User Profile Reply Card (Legacy - Not Used)
// Keeping for potential future use in own profile view

struct UserProfileReplyCard: View {
    let originalAuthor: String
    let originalContent: String
    let replyContent: String
    let timestamp: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Original Post Context
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 10))
                        .foregroundStyle(.black.opacity(0.4))
                    
                    Text("Replying to \(originalAuthor)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                Text(originalContent)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.5))
                    .lineSpacing(3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.03))
            )
            
            // Reply Content
            Text(replyContent)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black)
                .lineSpacing(4)
            
            // Timestamp
            Text(timestamp)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.black.opacity(0.4))
        }
        .padding(20)
    }
}

struct UserRepostsContentView: View {
    let reposts: [UserProfileRepost]
    
    var body: some View {
        LazyVStack(spacing: 0) {
            if reposts.isEmpty {
                UserProfileEmptyStateView(
                    icon: "arrow.2.squarepath",
                    title: "No Reposts Yet",
                    message: "This user hasn't reposted anything yet."
                )
                .padding(.top, 20)
            } else {
                ForEach(reposts.indices, id: \.self) { index in
                    ProfileRepostCard(
                        originalAuthor: reposts[index].originalAuthor,
                        content: reposts[index].content,
                        timestamp: reposts[index].timestamp,
                        likes: reposts[index].likes,
                        replies: reposts[index].replies
                    )
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .padding(.top, 12)
    }
}

// MARK: - Read-Only Post Card

struct ReadOnlyProfilePostCard: View {
    let post: ProfilePost
    let isLiked: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Post content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Time stamp with post type indicator
            HStack(spacing: 8) {
                Text(post.timestamp)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                
                // Post type indicator with liquid glass style for prayer/testimony
                if let postType = post.postType {
                    if postType.isLiquidGlassStyle {
                        // Liquid glass style for Prayer and Testimony
                        HStack(spacing: 4) {
                            Image(systemName: postType.icon)
                                .font(.system(size: 11))
                            Text(postType.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(postType.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                // Frosted glass background
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                
                                // Color tint overlay
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(postType.color.opacity(0.15))
                                
                                // Subtle border
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(postType.color.opacity(0.3), lineWidth: 0.5)
                            }
                        )
                        .shadow(color: postType.color.opacity(0.2), radius: 4, y: 2)
                    } else {
                        // Simple black/white style for OpenTable
                        HStack(spacing: 4) {
                            Image(systemName: postType.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(postType.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // Interaction buttons
            HStack(spacing: 24) {
                // Amen (Like) Button
                Button {
                    onLike()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "hands.clap.fill" : "hands.clap")
                            .font(.system(size: 18))
                            .foregroundStyle(isLiked ? .orange : .secondary)
                        
                        Text("\(post.likes + (isLiked ? 1 : 0))")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Comment Button
                Button {
                    onReply()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        
                        Text("\(post.replies)")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(
            ZStack {
                // Liquid glass effect background
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay for depth
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Inner glow border
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(isPressed ? 0.12 : 0.08), radius: isPressed ? 8 : 16, x: 0, y: isPressed ? 4 : 8)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Add subtle press animation
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
        }
    }
}

// MARK: - User Profile Empty State View

struct UserProfileEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            // Neumorphic icon container
            ZStack {
                Circle()
                    .fill(
                        Color(white: 0.95)
                            .shadow(.inner(color: Color.black.opacity(0.1), radius: 8, x: 4, y: 4))
                            .shadow(.inner(color: Color.white.opacity(0.8), radius: 8, x: -4, y: -4))
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.black.opacity(0.3))
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.black)
                
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Sample Data Extensions

extension UserProfile {
    static let sampleUser = UserProfile(
        userId: "sample-user-id-123",
        name: "Sarah Chen",
        username: "sarahchen",
        bio: "Entrepreneur | Faith-driven leader 🙏\nBuilding tech solutions with purpose",
        initials: "SC",
        interests: ["Entrepreneurship", "Faith", "Mentorship"],
        socialLinks: [
            UserSocialLink(platform: .linkedin, username: "sarahchen"),
            UserSocialLink(platform: .twitter, username: "@sarahchen")
        ],
        followersCount: 3456,
        followingCount: 892,
        isPrivateAccount: false
    )
}

extension ProfilePost {
    static let sampleUserPosts: [ProfilePost] = [
        ProfilePost(
            id: "post-1",
            content: "Just launched our new faith-based networking app! So grateful for God's guidance throughout this journey. Check it out! 🚀",
            timestamp: "3h ago",
            likes: 234,
            replies: 45,
            postType: .testimony
        ),
        ProfilePost(
            id: "post-2",
            content: "Morning devotional reminder: 'Trust in the Lord with all your heart.' - Proverbs 3:5. Start your day with faith! ☀️",
            timestamp: "1d ago",
            likes: 189,
            replies: 23,
            postType: .prayer
        ),
        ProfilePost(
            id: "post-3",
            content: "Excited to announce I'll be speaking at the Christian Entrepreneurs Summit next month! Who's attending?",
            timestamp: "2d ago",
            likes: 156,
            replies: 67,
            postType: nil
        ),
        ProfilePost(
            id: "post-4",
            content: "Reminder: Your worth is not determined by your productivity. Rest is biblical. Take care of yourself today. 💙",
            timestamp: "3d ago",
            likes: 412,
            replies: 89,
            postType: .openTable
        )
    ]
}

extension Reply {
    static let sampleUserReplies: [Reply] = [
        Reply(
            originalAuthor: "John Disciple",
            originalContent: "Anyone know good resources for Christian entrepreneurs?",
            replyContent: "I highly recommend 'Business as Mission' by C. Neal Johnson. It's been transformative for my approach to business!",
            timestamp: "5h ago"
        ),
        Reply(
            originalAuthor: "Michael Pastor",
            originalContent: "Looking for speakers for our youth conference. Any recommendations?",
            replyContent: "I'd love to help! I've spoken at several youth events. Feel free to DM me for details.",
            timestamp: "1d ago"
        )
    ]
}

// Mock Repost model for UserProfile view (separate from Firestore Repost)
struct UserProfileRepost: Identifiable {
    let id = UUID()
    let originalAuthor: String
    let content: String
    let timestamp: String
    var likes: Int = 0
    var replies: Int = 0
    
    static let sampleUserReposts: [UserProfileRepost] = [
        UserProfileRepost(
            originalAuthor: "David Martinez",
            content: "Just finished a 40-day prayer challenge. God showed up in ways I never expected. Don't underestimate the power of consistent prayer! 🙏",
            timestamp: "6h ago",
            likes: 567,
            replies: 123
        ),
        UserProfileRepost(
            originalAuthor: "Grace Williams",
            content: "New podcast episode: 'Finding Your Purpose in Your 20s' is now live! Featuring incredible testimonies from young believers.",
            timestamp: "2d ago",
            likes: 234,
            replies: 56
        )
    ]
}

// MARK: - Followers/Following List View

struct FollowersListView: View {
    @Environment(\.dismiss) var dismiss
    let userId: String
    let type: ListType
    
    enum ListType {
        case followers
        case following
        
        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }
    }
    
    @State private var users: [UserProfile] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if users.isEmpty {
                        UserProfileEmptyStateView(
                            icon: type == .followers ? "person.2" : "person.2.fill",
                            title: "No \(type.title)",
                            message: type == .followers ? "This user has no followers yet." : "This user isn't following anyone yet."
                        )
                    } else {
                        ForEach(users, id: \.username) { user in
                            UserListRow(user: user)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color(white: 0.98))
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .task {
                await loadUsers()
            }
        }
    }
    
    @MainActor
    private func loadUsers() async {
        isLoading = true
        
        do {
            // Use real FollowService to fetch followers/following
            let followService = FollowService.shared
            
            let followUserProfiles: [FollowUserProfile]
            
            switch type {
            case .followers:
                followUserProfiles = try await followService.fetchFollowers(userId: userId)
            case .following:
                followUserProfiles = try await followService.fetchFollowing(userId: userId)
            }
            
            print("✅ Loaded \(followUserProfiles.count) \(type.title)")
            
            // Convert FollowUserProfile to UserProfile
            users = followUserProfiles.map { followUser in
                UserProfile(
                    userId: followUser.id,  // FollowUserProfile uses 'id' not 'userId'
                    name: followUser.displayName,
                    username: followUser.username,
                    bio: followUser.bio ?? "",
                    initials: String(followUser.displayName.prefix(2)).uppercased(),
                    profileImageURL: followUser.profileImageURL,
                    interests: [],
                    socialLinks: [],
                    followersCount: followUser.followersCount,
                    followingCount: followUser.followingCount
                )
            }
            
        } catch {
            print("❌ Failed to load \(type.title): \(error)")
            users = []
        }
        
        isLoading = false
    }
}

struct UserListRow: View {
    let user: UserProfile
    @State private var isFollowing = false
    @State private var isLoading = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.black)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.black)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.black.opacity(0.5))
            }
            
            Spacer()
            
            // Follow button with real backend integration
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
            // Check initial follow status when row appears
            await checkFollowStatus()
        }
    }
    
    private func toggleFollow() async {
        isLoading = true
        let previousState = isFollowing
        
        // Optimistic update
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFollowing.toggle()
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            // Real backend call using FollowService
            try await FollowService.shared.toggleFollow(userId: user.userId)
            print("✅ Successfully \(isFollowing ? "followed" : "unfollowed") \(user.name)")
        } catch {
            // Rollback on error
            await MainActor.run {
                withAnimation {
                    isFollowing = previousState
                }
            }
            print("❌ Failed to toggle follow: \(error)")
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
        
        isLoading = false
    }
    
    private func checkFollowStatus() async {
        isFollowing = await FollowService.shared.isFollowing(userId: user.userId)
    }
}

// MARK: - Report User View

struct ReportUserView: View {
    @Environment(\.dismiss) var dismiss
    let userName: String
    let userId: String
    let onSubmit: (UserReportReason, String) -> Void
    
    @State private var selectedReason: UserReportReason?
    @State private var description = ""
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        
                        Text("Report \(userName)")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.black)
                        
                        Text("Help us understand what's happening")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Reason Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Why are you reporting this account?")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.black)
                        
                        ForEach(UserReportReason.allCases, id: \.self) { reason in
                            ReportReasonRow(
                                reason: reason,
                                isSelected: selectedReason == reason
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedReason = reason
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Optional Description
                    if selectedReason != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Additional Details (Optional)")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.black)
                            
                            TextEditor(text: $description)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .frame(height: 120)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Submit Button
                    if selectedReason != nil {
                        Button {
                            submitReport()
                        } label: {
                            Text("Submit Report")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Info Text
                    Text("Your report is anonymous. If someone is in immediate danger, call local emergency services.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Report Submitted", isPresented: $showingConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for helping keep our community safe. We'll review this report and take appropriate action.")
            }
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        onSubmit(reason, description)
        showingConfirmation = true
    }
}

struct ReportReasonRow: View {
    let reason: UserReportReason
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: reason.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .red : .black.opacity(0.6))
                    .frame(width: 32)
                
                Text(reason.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.black)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: isSelected ? .red.opacity(0.2) : .black.opacity(0.08), radius: isSelected ? 10 : 6, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.red.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Helper Views

struct StatView: View {
    let count: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(count)
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.black)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black.opacity(0.5))
        }
    }
}

struct InterestTagsView: View {
    let interests: [String]
    
    var body: some View {
        if !interests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                    
                    Text("Interests")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                HStack(spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        Text(interest)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.black.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.08))
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SocialLinksView: View {
    let socialLinks: [UserSocialLink]
    
    var body: some View {
        if !socialLinks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                    
                    Text("Social Links")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                VStack(spacing: 8) {
                    ForEach(socialLinks) { link in
                        HStack(spacing: 10) {
                            Image(systemName: link.platform.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            
                            Text("@\(link.username)")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.black)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.3))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.03))
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProfileRepostCard: View {
    let originalAuthor: String
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repost indicator with liquid glass effect
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("Reposted from \(originalAuthor)")
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    Capsule()
                        .fill(Color.purple.opacity(0.12))
                    
                    Capsule()
                        .strokeBorder(Color.purple.opacity(0.3), lineWidth: 0.5)
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Content
            Text(content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            
            // Time stamp
            Text(timestamp)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            // Stats (non-interactive)
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "hands.clap")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    
                    Text("\(likes)")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    
                    Text("\(replies)")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(
            ZStack {
                // Liquid glass effect background
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay for depth
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Purple tint for reposts
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.purple.opacity(0.03))
                
                // Inner glow border
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 🎨 Production-Ready UX Enhancements

// MARK: - 1. Skeleton Loading

// MARK: - Shimmer Effect

/// Shimmer effect for skeleton loading states
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    let duration: Double
    
    init(duration: Double = 1.5) {
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (phase * geometry.size.width * 2))
                    .mask(content)
                }
            )
            .onAppear {
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Adds a shimmer effect to the view
    func shimmerEffect(duration: Double = 1.5) -> some View {
        modifier(ShimmerEffect(duration: duration))
    }
}

/// Skeleton card for loading state
struct SkeletonProfileCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content placeholder
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity * 0.8)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity * 0.6)
            }
            
            // Timestamp placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 80, height: 12)
            
            // Buttons placeholder
            HStack(spacing: 20) {
                ForEach(0..<2) { _ in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 20, height: 20)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 30, height: 12)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .shimmerEffect()
    }
}

/// Skeleton header for profile loading
struct SkeletonProfileHeader: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 24)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 100, height: 16)
                }
                
                Spacer()
                
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity * 0.7)
            }
            
            HStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 100, height: 16)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 100, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 44)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 44)
            }
        }
        .padding(20)
        .background(Color.white)
        .shimmerEffect()
    }
}

// MARK: - 2. Smart Infinite Scroll

/// Smart scroll manager with prefetching
@MainActor
class SmartScrollManager: ObservableObject {
    @Published var isPrefetching = false
    private var prefetchTask: Task<Void, Never>?
    
    /// Check if should prefetch based on scroll position
    func shouldPrefetch(currentIndex: Int, totalCount: Int, threshold: Int = 5) -> Bool {
        return currentIndex >= totalCount - threshold && !isPrefetching
    }
    
    /// Prefetch next page
    func prefetch(loadMore: @escaping () async -> Void) {
        guard !isPrefetching else { return }
        
        isPrefetching = true
        prefetchTask?.cancel()
        
        prefetchTask = Task {
            await loadMore()
            isPrefetching = false
        }
    }
    
    func cancel() {
        prefetchTask?.cancel()
        isPrefetching = false
    }
}

/// Back to top button
struct BackToTopButton: View {
    let action: () -> Void
    @State private var isVisible = false
    
    var body: some View {
        if isVisible {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back to top")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                )
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    func show() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = true
        }
    }
    
    func hide() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = false
        }
    }
}

// MARK: - 3. Pull-to-Refresh Animation

/// Custom refresh control with animation
struct CustomRefreshControl: View {
    let isRefreshing: Bool
    let progress: CGFloat
    
    var body: some View {
        ZStack {
            // Rotating ring
            Circle()
                .trim(from: 0, to: isRefreshing ? 1 : progress)
                .stroke(
                    Color.black.opacity(0.3),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .none,
                    value: isRefreshing
                )
            
            // Center dot
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 8, height: 8)
                .scaleEffect(isRefreshing ? 1.2 : 0.8)
                .animation(
                    isRefreshing ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .none,
                    value: isRefreshing
                )
        }
        .opacity(progress > 0.1 || isRefreshing ? 1 : 0)
    }
}

/// Pull to refresh wrapper
struct PullToRefreshView<Content: View>: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () async -> Void
    @ViewBuilder let content: Content
    
    @State private var refreshProgress: CGFloat = 0
    @State private var isUserDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Refresh indicator
                    HStack {
                        Spacer()
                        CustomRefreshControl(
                            isRefreshing: isRefreshing,
                            progress: refreshProgress
                        )
                        Spacer()
                    }
                    .frame(height: 50)
                    .offset(y: isRefreshing ? 0 : -50)
                    
                    content
                }
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear.preference(
                            key: RefreshOffsetKey.self,
                            value: contentGeometry.frame(in: .named("refresh")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "refresh")
            .onPreferenceChange(RefreshOffsetKey.self) { offset in
                handleRefreshOffset(offset)
            }
        }
    }
    
    private func handleRefreshOffset(_ offset: CGFloat) {
        if isRefreshing { return }
        
        let threshold: CGFloat = 80
        refreshProgress = min(offset / threshold, 1.0)
        
        if offset > threshold && !isUserDragging {
            triggerRefresh()
        }
    }
    
    private func triggerRefresh() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        Task {
            await onRefresh()
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isRefreshing = false
                    refreshProgress = 0
                }
                
                let successHaptic = UINotificationFeedbackGenerator()
                successHaptic.notificationOccurred(.success)
            }
        }
    }
}

struct RefreshOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 4. Error Recovery UI

/// Error recovery view with retry
struct ErrorRecoveryView: View {
    let error: String
    let onRetry: () async -> Void
    let onDismiss: (() -> Void)?
    
    @State private var isRetrying = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Error icon with animation
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
            }
            
            // Error message
            VStack(spacing: 8) {
                Text("Oops!")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.black)
                
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button {
                    retry()
                } label: {
                    HStack(spacing: 8) {
                        if isRetrying {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        
                        Text(isRetrying ? "Retrying..." : "Try Again")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                    )
                }
                .disabled(isRetrying)
                
                if let onDismiss = onDismiss {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.black.opacity(0.6))
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.98))
    }
    
    private func retry() {
        guard !isRetrying else { return }
        
        isRetrying = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        Task {
            await onRetry()
            await MainActor.run {
                isRetrying = false
            }
        }
    }
}

/// Inline error banner
struct InlineErrorBanner: View {
    let message: String
    let onRetry: (() async -> Void)?
    let onDismiss: () -> Void
    
    @State private var isRetrying = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.black)
                
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let onRetry = onRetry {
                Button {
                    retry(onRetry)
                } label: {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(isRetrying)
            }
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.4))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func retry(_ action: @escaping () async -> Void) {
        guard !isRetrying else { return }
        
        isRetrying = true
        Task {
            await action()
            await MainActor.run {
                isRetrying = false
            }
        }
    }
}

// MARK: - Privacy Status Badge

/// Badge to show privacy status (muted, hidden, etc.)
struct PrivacyStatusBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 13))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Chat Conversation Loader

/// Loader view that gets or creates a conversation before showing the chat
/// Uses the production ChatViewLiquidGlass with full messaging functionality
struct ChatConversationLoader: View {
    let userId: String
    let userName: String
    
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var conversationId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        Group {
            if isLoading {
                // Loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Starting conversation with \(userName)...")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else if let conversationId = conversationId {
                // ✅ Success - Open ChatViewLiquidGlass with the conversation
                ChatViewLiquidGlass(
                    conversation: ChatConversation(
                        id: conversationId,
                        name: userName,
                        lastMessage: "",
                        timestamp: "Now",
                        isGroup: false,
                        unreadCount: 0,
                        avatarColor: .blue
                    )
                )
            } else {
                // Error state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundStyle(.red)
                    
                    Text("Unable to start conversation")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black)
                            )
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .task {
            await loadConversation()
        }
    }
    
    @MainActor
    private func loadConversation() async {
        isLoading = true
        
        do {
            print("📱 Getting or creating conversation with user: \(userName) (ID: \(userId))")
            
            let convId = try await messagingService.getOrCreateDirectConversation(
                withUserId: userId,
                userName: userName
            )
            
            print("✅ Got conversation ID: \(convId)")
            conversationId = convId
            
        } catch let error as FirebaseMessagingError {
            print("❌ FirebaseMessagingError: \(error)")
            
            // Handle specific error cases
            switch error {
            case .permissionDenied:
                errorMessage = "Unable to start conversation. This user may have blocked you or restricted messaging."
            case .notAuthenticated:
                errorMessage = "You must be signed in to send messages. Please sign in and try again."
            case .userBlocked:
                errorMessage = "You have blocked this user. Unblock them to send messages."
            case .followRequired:
                errorMessage = "You must follow this user before messaging them."
            case .messagesNotAllowed:
                errorMessage = "This user doesn't accept messages."
            case .selfConversation:
                errorMessage = "You cannot message yourself."
            case .networkError(let underlyingError):
                // Check if it's a Firestore permission error
                let errorString = underlyingError.localizedDescription.lowercased()
                if errorString.contains("permission") || errorString.contains("insufficient") {
                    errorMessage = "Unable to access messaging. Please check your internet connection and try again. If the problem persists, try signing out and back in."
                } else {
                    errorMessage = "Network error: \(underlyingError.localizedDescription)"
                }
            default:
                errorMessage = error.localizedDescription ?? "An error occurred while creating the conversation."
            }
            
            showError = true
        } catch {
            print("❌ Unexpected error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            // Check for common Firestore errors
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("permission") || errorString.contains("insufficient") {
                errorMessage = "Unable to start conversation due to permissions. This might happen if:\n\n• You need to sign out and back in\n• Your account doesn't have messaging enabled\n• There's a temporary server issue\n\nPlease try again or contact support if this continues."
            } else if errorString.contains("network") || errorString.contains("connection") {
                errorMessage = "Network connection error. Please check your internet connection and try again."
            } else {
                errorMessage = "Unable to start conversation. Please try again later.\n\nError: \(error.localizedDescription)"
            }
            
            showError = true
        }
        
        isLoading = false
    }
}

#Preview {
    UserProfileView(userId: "sample-user-id")
}
