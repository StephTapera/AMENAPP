//
//  UserProfileView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Data Models

struct ProfilePost: Identifiable {
    let id = UUID()
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
}

struct Reply: Identifiable {
    let id = UUID()
    let originalAuthor: String
    let originalContent: String
    let replyContent: String
    let timestamp: String
}

struct UserProfile {
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
    @State private var profileData: UserProfile?
    @State private var posts: [ProfilePost] = []
    @State private var replies: [Reply] = []
    @State private var reposts: [UserProfileRepost] = []
    @State private var selectedReportReason: ReportReason?
    @State private var reportDescription = ""
    @State private var currentPage = 1
    @State private var hasMorePosts = true
    @State private var isLoadingMore = false
    @State private var followerCountListener: ListenerRegistration?
    @Namespace private var tabNamespace
    
    enum ReportReason: String, CaseIterable {
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
        case replies = "Replies"
        case reposts = "Reposts"
        
        var icon: String {
            switch self {
            case .posts: return "square.grid.2x2"
            case .replies: return "bubble.left"
            case .reposts: return "arrow.2.squarepath"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header
                    profileHeaderView
                    
                    // Tab Selector
                    tabSelectorView
                    
                    // Content based on selected tab
                    if isLoading {
                        LoadingStateView()
                    } else {
                        contentView
                    }
                }
            }
            .refreshable {
                await refreshProfile()
            }
            .background(Color(white: 0.98))
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
                    HStack(spacing: 12) {
                        Button {
                            shareProfile()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        Menu {
                            Button {
                                reportUser()
                            } label: {
                                Label("Report User", systemImage: "exclamationmark.triangle")
                            }
                            
                            Button(role: .destructive) {
                                showBlockAlert = true
                            } label: {
                                Label(isBlocked ? "Unblock User" : "Block User", systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
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
                    ModernConversationDetailView(
                        conversation: ChatConversation(
                            name: profileData.name,
                            lastMessage: "",
                            timestamp: "Now",
                            isGroup: false,
                            unreadCount: 0,
                            avatarColor: .blue
                        )
                    )
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
    
    // MARK: - Refresh Function
    
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
            
            print("📋 User data extracted:")
            print("   - displayName: \(displayName)")
            print("   - username: \(username)")
            print("   - bio length: \(bio.count)")
            print("   - followersCount: \(followersCount)")
            print("   - followingCount: \(followingCount)")
            
            // Generate initials
            let names = displayName.components(separatedBy: " ")
            let initials = names.compactMap { $0.first }.map { String($0) }.joined().prefix(2).uppercased()
            
            print("✅ Fetched user: \(displayName) (@\(username))")
            
            // Convert to UserProfile
            profileData = UserProfile(
                name: displayName,
                username: username,
                bio: bio,
                initials: String(initials),
                profileImageURL: profileImageURL,
                interests: interests,
                socialLinks: [], // TODO: Add social links to UserModel if needed
                followersCount: followersCount,
                followingCount: followingCount
            )
            
            print("✅ Profile data converted successfully")
            
            // Fetch user's content in parallel
            print("📥 Starting parallel fetch for posts, replies, reposts, and follow status...")
            
            async let postsTask = fetchUserPosts(page: 1)
            async let repliesTask = fetchUserReplies()
            async let repostsTask = fetchUserReposts()
            async let followStatusTask = checkFollowStatus()
            
            // Await all tasks
            (posts, replies, reposts, isFollowing) = try await (postsTask, repliesTask, repostsTask, followStatusTask)
            
            print("✅ Parallel fetch completed:")
            print("   - Posts: \(posts.count)")
            print("   - Replies: \(replies.count)")
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
            
            errorMessage = handleError(error)
            showErrorAlert = true
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
        
        // Convert Post to ProfilePost
        return userPosts.map { post in
            ProfilePost(
                content: post.content,
                timestamp: post.timeAgo,
                likes: post.amenCount,
                replies: post.commentCount
            )
        }
    }
    
    private func fetchUserReplies() async throws -> [Reply] {
        print("📥 Fetching replies for user: \(userId)")
        
        // Use FirebasePostService to fetch real user replies
        let firebasePostService = FirebasePostService.shared
        let userComments = try await firebasePostService.fetchUserReplies(userId: userId)
        
        print("✅ Fetched \(userComments.count) replies for user")
        
        // Convert Comment to Reply
        return userComments.compactMap { comment in
            // Only show top-level comments (not nested replies)
            guard comment.parentCommentId == nil else { return nil }
            
            return Reply(
                originalAuthor: "Unknown", // We'd need to fetch the post author
                originalContent: "...", // We'd need to fetch the original post
                replyContent: comment.content,
                timestamp: comment.createdAt.timeAgoDisplay()
            )
        }
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
        Task {
            await performFollowAction()
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
    
    private func submitReport(reason: ReportReason, description: String) {
        // In a real app, send to backend API
        print("Reporting user \(userId) for: \(reason.rawValue)")
        print("Description: \(description)")
        
        // Show confirmation
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // TODO: Call API endpoint
        // NetworkManager.shared.reportUser(userId: userId, reason: reason, description: description)
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
        
        // If blocking, automatically unfollow
        if isBlocked {
            isFollowing = false
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(isBlocked ? .warning : .success)
        
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
            
        } catch {
            // Rollback on error
            await MainActor.run {
                isBlocked = previousState
                errorMessage = "Failed to \(previousState ? "unblock" : "block") user. Please try again."
                showErrorAlert = true
            }
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
                            // Name
                            Text(profileData.name)
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.black)
                            
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
                        // Follow/Following Button
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
                        
                        // Message Button
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
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        // Selected tab background (glass pill)
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .matchedGeometryEffect(id: "tab", in: tabNamespace)
                        }
                        
                        // Icon
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .black : .black.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(white: 0.92))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .frame(maxWidth: 280)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
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
            case .replies:
                UserRepliesContentView(replies: replies)
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
    @State private var likedPosts: Set<UUID> = []
    var onLoadMore: (() async -> Void)?
    var hasMorePosts: Bool = false
    var isLoadingMore: Bool = false
    
    var body: some View {
        LazyVStack(spacing: 0) {
            if posts.isEmpty {
                UserProfileEmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No Posts Yet",
                    message: "This user hasn't posted anything yet."
                )
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
                    
                    if index < posts.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                    
                    // Load more trigger
                    if index == posts.count - 3 && hasMorePosts && !isLoadingMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await onLoadMore?()
                                }
                            }
                    }
                }
                
                // Load more button
                if hasMorePosts {
                    Button {
                        Task {
                            await onLoadMore?()
                        }
                    } label: {
                        if isLoadingMore {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading...")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            Text("Load More Posts")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                                )
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.white)
    }
    
    @MainActor
    private func handleLike(postId: UUID) async {
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
        } catch {
            // Rollback on error
            if wasLiked {
                likedPosts.insert(postId)
            } else {
                likedPosts.remove(postId)
            }
        }
    }
    
    private func handleReply(postId: UUID) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // TODO: Navigate to reply composer or post detail
        // navigationPath.append(PostRoute.detail(postId: postId))
        print("Reply to post: \(postId)")
    }
}

struct UserRepliesContentView: View {
    let replies: [Reply]
    
    var body: some View {
        LazyVStack(spacing: 0) {
            if replies.isEmpty {
                UserProfileEmptyStateView(
                    icon: "bubble.left",
                    title: "No Replies Yet",
                    message: "This user hasn't replied to any posts yet."
                )
            } else {
                ForEach(replies.indices, id: \.self) { index in
                    UserProfileReplyCard(
                        originalAuthor: replies[index].originalAuthor,
                        originalContent: replies[index].originalContent,
                        replyContent: replies[index].replyContent,
                        timestamp: replies[index].timestamp
                    )
                    
                    if index < replies.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .background(Color.white)
    }
}

// MARK: - User Profile Reply Card

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
            } else {
                ForEach(reposts.indices, id: \.self) { index in
                    ProfileRepostCard(
                        originalAuthor: reposts[index].originalAuthor,
                        content: reposts[index].content,
                        timestamp: reposts[index].timestamp,
                        likes: reposts[index].likes,
                        replies: reposts[index].replies
                    )
                    
                    if index < reposts.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .background(Color.white)
    }
}

// MARK: - Read-Only Post Card

struct ReadOnlyProfilePostCard: View {
    let post: ProfilePost
    let isLiked: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black)
                .lineSpacing(4)
            
            // Interaction Row
            HStack(spacing: 20) {
                Text(post.timestamp)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.4))
                
                Spacer()
                
                // Like Button
                Button {
                    onLike()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(isLiked ? .red : .black.opacity(0.5))
                        Text("\(post.likes + (isLiked ? 1 : 0))")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Reply Button
                Button {
                    onReply()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14))
                        Text("\(post.replies)")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
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
        followingCount: 892
    )
}

extension ProfilePost {
    static let sampleUserPosts: [ProfilePost] = [
        ProfilePost(
            content: "Just launched our new faith-based networking app! So grateful for God's guidance throughout this journey. Check it out! 🚀",
            timestamp: "3h ago",
            likes: 234,
            replies: 45
        ),
        ProfilePost(
            content: "Morning devotional reminder: 'Trust in the Lord with all your heart.' - Proverbs 3:5. Start your day with faith! ☀️",
            timestamp: "1d ago",
            likes: 189,
            replies: 23
        ),
        ProfilePost(
            content: "Excited to announce I'll be speaking at the Christian Entrepreneurs Summit next month! Who's attending?",
            timestamp: "2d ago",
            likes: 156,
            replies: 67
        ),
        ProfilePost(
            content: "Reminder: Your worth is not determined by your productivity. Rest is biblical. Take care of yourself today. 💙",
            timestamp: "3d ago",
            likes: 412,
            replies: 89
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
            
            // Follow button
            Button {
                isFollowing.toggle()
            } label: {
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
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Report User View

struct ReportUserView: View {
    @Environment(\.dismiss) var dismiss
    let userName: String
    let userId: String
    let onSubmit: (UserProfileView.ReportReason, String) -> Void
    
    @State private var selectedReason: UserProfileView.ReportReason?
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
                        
                        ForEach(UserProfileView.ReportReason.allCases, id: \.self) { reason in
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
    let reason: UserProfileView.ReportReason
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
        VStack(alignment: .leading, spacing: 12) {
            // Repost indicator
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.4))
                
                Text("Reposted from \(originalAuthor)")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.black.opacity(0.5))
            }
            
            // Content
            Text(content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black)
                .lineSpacing(4)
            
            // Stats
            HStack(spacing: 20) {
                Text(timestamp)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.4))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 14))
                    Text("\(likes)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(.black.opacity(0.5))
                
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14))
                    Text("\(replies)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(.black.opacity(0.5))
            }
        }
        .padding(20)
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

#Preview {
    UserProfileView(userId: "sample-user-id")
}
