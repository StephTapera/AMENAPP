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
    let createdAt: Date  // ✅ NEW: For chronological sorting
    
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

// ✅ NEW: Unified feed item for Threads-like chronological feed
struct ProfileFeedItem: Identifiable {
    let id: String
    let type: FeedItemType
    let content: String
    let timestamp: String
    let createdAt: Date
    var likes: Int
    var replies: Int
    let postType: ProfilePost.PostType?
    let originalAuthor: String?  // For reposts
    
    enum FeedItemType {
        case post
        case repost
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
    var bioURL: String?  // Bio link URL
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
///
/// **🎯 PRODUCTION-READY ENHANCEMENTS RECOMMENDED:**
///
/// **1. Post Preview with Tap-to-Expand**
///    - Currently: Posts are limited to 4 lines but have no expansion
///    - Improvement: Add "See More" button for truncated posts
///    - Benefit: Better content discovery while maintaining clean layout
///    - Implementation: Add `@State var expandedPosts: Set<String>` and toggle logic
///
/// **2. Profile Action Analytics & Tracking**
///    - Currently: No tracking of user interactions on profile
///    - Improvement: Track follows, unfollows, message attempts, blocks, reports
///    - Benefit: Understand user engagement patterns and improve UX
///    - Implementation: Add `ProfileAnalyticsService.track(event:userId:)` calls
///
/// **3. Swipe Actions on Post Cards**
///    - Currently: Must tap buttons for like/comment actions
///    - Improvement: Add swipe-to-amen (right) and swipe-to-comment (left)
///    - Benefit: Faster interactions, more mobile-native feel
///    - Implementation: Wrap cards in SwiftUI `.swipeActions()` or custom gesture
///
/// **Additional Considerations:**
/// - Post cards now use compact glassmorphic design (smaller, translucent)
/// - Amen button has NO count display (minimalist approach)
/// - Comment button shows badge count only when > 0
/// - All designs use black and white color scheme exclusively
///
struct UserProfileView: View {
    let userId: String // In a real app, this would be used to fetch the user's data
    let showsDismissButton: Bool

    init(userId: String, showsDismissButton: Bool = false) {
        self.userId = userId
        self.showsDismissButton = showsDismissButton
    }
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: UserProfileTab = .posts
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var showFullScreenAvatar = false
    @State private var showReportOptions = false
    @State private var showBlockAlert = false
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    @State private var isFollowActionInProgress = false
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
    @State private var feedItems: [ProfileFeedItem] = []  // ✅ NEW: Unified Threads-like feed
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
    
    // Additional production-ready states
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var notificationsEnabled = false  // Post notifications for this user
    @State private var hasLoadedInitially = false  // Prevent duplicate loads
    @State private var profileImageCache: UIImage?  // Cache for avatar
    
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
                            inlineErrorBannerView
                                .padding(.top, 12)
                        }
                        
                        // Profile Header
                        profileHeaderView
                        
                        // Tab Selector (Posts / Reposts)
                        tabSelectorView
                        
                        // Content - Posts or Reposts based on selected tab
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
                ToolbarItem(placement: .cancellationAction) {
                    if showsDismissButton {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
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
            .sheet(isPresented: $showShareSheet) {
                if !shareItems.isEmpty {
                    ActivityViewController(activityItems: shareItems)
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
            // Prevent duplicate loads
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            
            let startTime = Date()
            await loadProfileData()
            trackLoadPerformance(startTime: startTime)
            
            // Announce for accessibility
            if profileData != nil {
                announceProfileLoaded()
            }
        }
        .onDisappear {
            // Clean up listener when leaving profile
            removeFollowerCountListener()
            
            // Cache profile for offline viewing
            cacheProfileData()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }
    
    // MARK: - Helper Functions
    
    private var inlineErrorBannerView: some View {
        HStack {
            InlineErrorBanner(
                message: inlineErrorMessage,
                retryAction: {
                    Task {
                        await handleErrorRetry()
                    }
                }
            )
            
            // Dismiss button
            Button {
                handleErrorDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            }
            .padding(.trailing, 8)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func handleErrorRetry() async {
        withAnimation {
            showInlineError = false
        }
        await loadProfileData()
    }
    
    private func handleErrorDismiss() {
        withAnimation {
            showInlineError = false
        }
    }
    
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
                
                // ✅ FIX: Ensure counts are never negative
                var followersCount = data["followersCount"] as? Int ?? 0
                var followingCount = data["followingCount"] as? Int ?? 0
                
                // Defensive programming: clamp negative values to 0
                if followersCount < 0 {
                    print("⚠️ WARNING: Negative followersCount in real-time update (\(followersCount)), clamping to 0")
                    followersCount = 0
                }
                
                if followingCount < 0 {
                    print("⚠️ WARNING: Negative followingCount in real-time update (\(followingCount)), clamping to 0")
                    followingCount = 0
                }
                
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
    
    // ✅ NEW: Set up real-time listeners for posts and reposts (Threads-like instant updates)
    @MainActor
    private func setupRealtimeListeners() {
        print("🔊 Setting up real-time listeners for posts and reposts...")
        
        // ✅ Firestore snapshot listener for real-time posts
        let db = Firestore.firestore()
        db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Firestore listener error: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else { return }
                
                print("🔄 Real-time: Posts updated for user \(self.userId)")
                
                // Parse posts from Firestore
                let updatedPosts = documents.compactMap { doc -> ProfilePost? in
                    guard let data = doc.data() as? [String: Any],
                          let content = data["content"] as? String,
                          let timestamp = data["createdAt"] as? Timestamp else {
                        return nil
                    }
                    
                    let categoryStr = data["category"] as? String ?? ""
                    let postType: ProfilePost.PostType?
                    switch categoryStr {
                    case "prayer": postType = .prayer
                    case "testimonies": postType = .testimony
                    case "openTable": postType = .openTable
                    default: postType = nil
                    }
                    
                    return ProfilePost(
                        id: doc.documentID,
                        content: content,
                        timestamp: self.formatTimestamp(timestamp.dateValue()),
                        likes: data["amenCount"] as? Int ?? 0,
                        replies: data["commentCount"] as? Int ?? 0,
                        postType: postType,
                        createdAt: timestamp.dateValue()
                    )
                }
                
                // Update posts array
                self.posts = updatedPosts
                
                // Rebuild unified feed
                self.buildUnifiedFeed()
                
                print("✅ Real-time: \(updatedPosts.count) posts loaded")
            }
        
        // Also keep NotificationCenter for optimistic updates
        NotificationCenter.default.addObserver(
            forName: .newPostCreated,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let post = userInfo["post"] as? Post,
                  post.authorId == self.userId else { return }
            
            print("✅ Real-time: Optimistic post detected for user \(self.userId)")
            // Firestore listener will handle the update
        }
        
        // Listen for new reposts
        NotificationCenter.default.addObserver(
            forName: Notification.Name("postReposted"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let post = userInfo["post"] as? Post,
                  let reposterId = userInfo["userId"] as? String,
                  reposterId == self.userId else { return }
            
            print("✅ Real-time: New repost detected for user \(self.userId)")
            
            // Convert and add to reposts array
            let repost = UserProfileRepost(
                originalAuthor: post.authorName,
                content: post.content,
                timestamp: post.timeAgo,
                likes: post.amenCount,
                replies: post.commentCount
            )
            
            // Insert at beginning (newest first)
            self.reposts.insert(repost, at: 0)
            
            // Rebuild unified feed
            self.buildUnifiedFeed()
        }
        
        print("✅ Real-time listeners set up successfully")
    }
    
    /// Fix corrupted follower counts by recalculating from actual follow relationships
    @MainActor
    private func fixFollowerCounts(userId: String) async {
        print("🔧 Attempting to fix follower counts for user: \(userId)")
        
        do {
            let db = Firestore.firestore()
            
            // Count actual followers
            let followersSnapshot = try await db.collection("follows")
                .whereField("followingId", isEqualTo: userId)
                .getDocuments()
            let actualFollowersCount = followersSnapshot.documents.count
            
            // Count actual following
            let followingSnapshot = try await db.collection("follows")
                .whereField("followerId", isEqualTo: userId)
                .getDocuments()
            let actualFollowingCount = followingSnapshot.documents.count
            
            // Update Firestore with correct counts
            try await db.collection("users").document(userId).updateData([
                "followersCount": actualFollowersCount,
                "followingCount": actualFollowingCount,
                "updatedAt": Date()
            ])
            
            print("✅ Fixed follower counts:")
            print("   - Followers: \(actualFollowersCount)")
            print("   - Following: \(actualFollowingCount)")
            
            // Update local state
            if var profile = profileData {
                profile.followersCount = actualFollowersCount
                profile.followingCount = actualFollowingCount
                profileData = profile
            }
            
        } catch {
            print("❌ Error fixing follower counts: \(error)")
        }
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
            let bioURL = data["bioURL"] as? String
            let profileImageURL = data["profileImageURL"] as? String
            let interests = data["interests"] as? [String] ?? []
            
            // ✅ FIX: Ensure counts are never negative
            var followersCount = data["followersCount"] as? Int ?? 0
            var followingCount = data["followingCount"] as? Int ?? 0
            
            // Defensive programming: fix negative counts
            let hasNegativeCounts = followersCount < 0 || followingCount < 0
            
            if followersCount < 0 {
                print("⚠️ WARNING: Negative followersCount detected (\(followersCount)), will recalculate")
                followersCount = 0
            }
            
            if followingCount < 0 {
                print("⚠️ WARNING: Negative followingCount detected (\(followingCount)), will recalculate")
                followingCount = 0
            }
            
            // If we detected negative counts, schedule a fix
            if hasNegativeCounts {
                Task {
                    await self.fixFollowerCounts(userId: userId)
                }
            }
            
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
                bioURL: bioURL,
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
            
            // ✅ NEW: Build unified Threads-like feed
            buildUnifiedFeed()
            
            // 🔊 SET UP REAL-TIME LISTENER for follower/following counts
            setupFollowerCountListener()
            
            // ✅ NEW: Set up real-time listeners for posts and reposts
            setupRealtimeListeners()
            
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
        
        // ✅ FIX: Use Firestore where posts are actually saved
        let postService = FirebasePostService.shared
        let userPosts = try await postService.fetchUserPosts(userId: userId)
        
        print("✅ Fetched \(userPosts.count) posts from Firestore for user")
        
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
            
            return ProfilePost(
                id: post.id.uuidString,  // Use UUID string as ID
                content: post.content,
                timestamp: post.timeAgo,
                likes: post.amenCount,
                replies: post.commentCount,
                postType: postType,
                createdAt: post.createdAt  // ✅ Include timestamp for sorting
            )
        }
    }
    
    // ✅ NEW: Build unified Threads-like feed from posts and reposts
    @MainActor
    private func buildUnifiedFeed() {
        var items: [ProfileFeedItem] = []
        
        // Add all posts to feed
        items += posts.map { post in
            ProfileFeedItem(
                id: "post-\(post.id)",
                type: .post,
                content: post.content,
                timestamp: post.timestamp,
                createdAt: post.createdAt,
                likes: post.likes,
                replies: post.replies,
                postType: post.postType,
                originalAuthor: nil
            )
        }
        
        // Add all reposts to feed
        items += reposts.map { repost in
            ProfileFeedItem(
                id: "repost-\(UUID().uuidString)",
                type: .repost,
                content: repost.content,
                timestamp: repost.timestamp,
                createdAt: Date(),  // Use current date as fallback
                likes: repost.likes,
                replies: repost.replies,
                postType: nil,
                originalAuthor: repost.originalAuthor
            )
        }
        
        // Sort chronologically (newest first) like Threads
        feedItems = items.sorted { $0.createdAt > $1.createdAt }
        
        print("✅ Built unified feed: \(feedItems.count) items (\(posts.count) posts + \(reposts.count) reposts)")
    }
    
    private func fetchUserReplies() async throws -> [Reply] {
        // Replies are now private - not shown on public profile
        print("📥 Replies are hidden from public profiles")
        return []
    }
    
    private func fetchUserReposts() async throws -> [UserProfileRepost] {
        print("📥 Fetching reposts for user: \(userId)")
        
        // ✅ FIX: Use Realtime Database instead of Firestore for consistency
        let realtimeRepostsService = RealtimeRepostsService.shared
        let userReposts = try await realtimeRepostsService.fetchUserReposts(userId: userId)
        
        print("✅ Fetched \(userReposts.count) reposts from Realtime DB for user")
        
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
                case 5: // Not found
                    return "This user's profile could not be found. They may have deleted their account."
                case 7: // Permission denied - Only show this for ACTUAL permission errors
                    return "You don't have permission to view this profile. This may be a private account."
                case 14: // Unavailable (network)
                    return "Unable to connect. Please check your internet connection and try again."
                case 2: // Aborted
                    return "Request was cancelled. Please try again."
                case 4: // Deadline exceeded
                    return "Request timed out. Please check your connection and try again."
                case 8: // Already exists (shouldn't happen for profile view)
                    return "A conflict occurred. Please refresh and try again."
                case 13: // Internal error
                    return "A server error occurred. Please try again later."
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
                return "No internet connection. Please check your network settings and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Cannot reach the server. Please try again later."
            case .networkConnectionLost:
                return "Network connection was lost. Please reconnect and try again."
            case .dataNotAllowed:
                return "Data usage is restricted. Please check your device settings."
            default:
                return "A network error occurred. Please check your connection and try again."
            }
        }
        
        // Handle custom errors
        if let nsError = error as NSError?, nsError.domain == "UserProfileView" {
            return nsError.localizedDescription
        }
        
        // Log the full error for debugging
        print("⚠️ Unhandled error type: \(error)")
        
        // Check error description for common patterns
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("permission") || errorString.contains("insufficient") {
            return "Permission denied. This might be a private account or your session expired. Try signing out and back in."
        }
        
        if errorString.contains("network") || errorString.contains("offline") {
            return "Network connection issue. Please check your internet and try again."
        }
        
        if errorString.contains("not found") || errorString.contains("404") {
            return "This profile could not be found. The user may have deleted their account."
        }
        
        if errorString.contains("timeout") {
            return "Request timed out. Please try again."
        }
        
        // Default fallback with helpful suggestions
        return "Unable to load profile. Please try:\n\n• Checking your internet connection\n• Refreshing by pulling down\n• Signing out and back in if the problem continues\n\nError: \(error.localizedDescription)"
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
        
        // Prevent duplicate taps
        guard !isFollowActionInProgress else {
            print("⚠️ Follow action already in progress, ignoring duplicate tap")
            return
        }
        
        isFollowActionInProgress = true
        defer { isFollowActionInProgress = false }
        
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
        // Use enhanced share sheet with QR code
        showAdvancedShareSheet()
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
                // Post Notifications
                Section {
                    Button {
                        toggleNotifications()
                    } label: {
                        Label(
                            notificationsEnabled ? "Turn Off Notifications" : "Turn On Notifications",
                            systemImage: notificationsEnabled ? "bell.fill" : "bell"
                        )
                    }
                }
                
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
                
                // Advanced Share
                Section {
                    Button {
                        showAdvancedShareSheet()
                    } label: {
                        Label("Share with QR Code", systemImage: "qrcode")
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
                            
                            // Bio URL Link (moved to top)
                            if let bioURL = profileData.bioURL, !bioURL.isEmpty {
                                Link(destination: URL(string: bioURL)!) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.black)

                                        Text(bioURL.replacingOccurrences(of: "https://", with: "")
                                                .replacingOccurrences(of: "http://", with: ""))
                                            .font(.custom("OpenSans-SemiBold", size: 11))
                                            .foregroundStyle(.black)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        ZStack {
                                            // Base frosted glass layer
                                            Capsule()
                                                .fill(.ultraThinMaterial)

                                            // Inner glow effect (white from top)
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.5),
                                                            Color.white.opacity(0.2),
                                                            Color.clear
                                                        ],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )

                                            // Rim light (highlight on edges)
                                            Capsule()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.7),
                                                            Color.white.opacity(0.4),
                                                            Color.white.opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )

                                            // Outer border (black)
                                            Capsule()
                                                .strokeBorder(
                                                    Color.black.opacity(0.25),
                                                    lineWidth: 1
                                                )
                                                .padding(0.5)
                                        }
                                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                                    )
                                }
                            }
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
                                
                                if let profileImageURL = profileData.profileImageURL, !profileImageURL.isEmpty {
                                    AsyncImage(url: URL(string: profileImageURL)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipShape(Circle())
                                        case .failure(_):
                                            Text(profileData.initials)
                                                .font(.custom("OpenSans-Bold", size: 28))
                                                .foregroundStyle(.white)
                                        case .empty:
                                            ProgressView()
                                                .tint(.white)
                                        @unknown default:
                                            Text(profileData.initials)
                                                .font(.custom("OpenSans-Bold", size: 28))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                } else {
                                    Text(profileData.initials)
                                        .font(.custom("OpenSans-Bold", size: 28))
                                        .foregroundStyle(.white)
                                }
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
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .posts:
            // Show user's posts
            postsTabContent
            
        case .reposts:
            // Show user's reposts
            repostsTabContent
        }
    }
    
    private var postsTabContent: some View {
        UserPostsContentView(
            posts: posts,
            hasMorePosts: hasMorePosts,
            isLoadingMore: isLoadingMore
        )
    }
    
    private var repostsTabContent: some View {
        UserRepostsContentView(reposts: reposts)
    }
}

// MARK: - Content Views

struct UserPostsContentView: View {
    let posts: [ProfilePost]
    @State private var likedPosts: Set<String> = []
    @State private var expandedPosts: Set<String> = []  // ✅ NEW: Track expanded posts
    var onLoadMore: (() async -> Void)?
    var hasMorePosts: Bool = false
    var isLoadingMore: Bool = false
    @State private var selectedPostForComments: Post?
    @State private var showCommentsSheet = false
    @StateObject private var scrollManager = SmartScrollManager()
    
    var body: some View {
        LazyVStack(spacing: 10) {  // ✅ 10pt spacing between cards
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
                        isExpanded: expandedPosts.contains(posts[index].id),  // ✅ NEW: Pass expansion state
                        onLike: {
                            Task {
                                await handleLike(postId: posts[index].id)
                            }
                        },
                        onReply: {
                            handleReply(postId: posts[index].id)
                        },
                        onToggleExpand: {  // ✅ NEW: Toggle expansion
                            toggleExpanded(postId: posts[index].id)
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
        .padding(.top, 0)  // ✅ Zero padding - posts RIGHT under tabs
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
    
    // ✅ NEW: Toggle post expansion
    private func toggleExpanded(postId: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            if expandedPosts.contains(postId) {
                expandedPosts.remove(postId)
            } else {
                expandedPosts.insert(postId)
            }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
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
        LazyVStack(spacing: 10) {  // ✅ 10pt spacing between cards
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

// MARK: - Unified Feed Content View (Threads-like)

/// ✅ NEW: Unified feed showing posts and reposts chronologically like Threads
struct UnifiedFeedContentView: View {
    let feedItems: [ProfileFeedItem]
    @State private var likedItems: Set<String> = []
    @State private var expandedItems: Set<String> = []
    
    var body: some View {
        LazyVStack(spacing: 0) {
            if feedItems.isEmpty {
                UserProfileEmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No Posts Yet",
                    message: "This user hasn't posted anything yet."
                )
                .padding(.top, 20)
            } else {
                ForEach(feedItems.indices, id: \.self) { index in
                    let item = feedItems[index]
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Show repost indicator if it's a repost
                        if item.type == .repost {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.4))
                                
                                Text("Reposted from \(item.originalAuthor ?? "Unknown")")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        }
                        
                        // Show post content
                        UnifiedFeedItemCard(
                            item: item,
                            isLiked: likedItems.contains(item.id),
                            isExpanded: expandedItems.contains(item.id),
                            onLike: { handleLike(itemId: item.id) },
                            onReply: { handleReply(itemId: item.id) },
                            onToggleExpand: { toggleExpand(itemId: item.id) }
                        )
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .padding(.top, 12)
    }
    
    private func handleLike(itemId: String) {
        if likedItems.contains(itemId) {
            likedItems.remove(itemId)
        } else {
            likedItems.insert(itemId)
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func handleReply(itemId: String) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        // TODO: Show comments sheet
    }
    
    private func toggleExpand(itemId: String) {
        if expandedItems.contains(itemId) {
            expandedItems.remove(itemId)
        } else {
            expandedItems.insert(itemId)
        }
    }
}

/// Card for unified feed items
struct UnifiedFeedItemCard: View {
    let item: ProfileFeedItem
    let isLiked: Bool
    let isExpanded: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    let onToggleExpand: () -> Void
    
    private var needsExpansion: Bool {
        item.content.count > 120
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post content
            Text(item.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 4)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
            
            // See More button
            if needsExpansion {
                Button {
                    onToggleExpand()
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "See Less" : "See More")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                }
            }
            
            // Timestamp and actions
            HStack {
                Text(item.timestamp)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.4))
                
                Spacer()
                
                // Actions
                HStack(spacing: 16) {
                    // Amen button
                    Button(action: onLike) {
                        HStack(spacing: 6) {
                            Image(systemName: isLiked ? "hands.sparkles.fill" : "hands.sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isLiked ? .blue : .black.opacity(0.6))
                            
                            if item.likes > 0 {
                                Text("\(item.likes)")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                    }
                    
                    // Reply button
                    Button(action: onReply) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.6))
                            
                            if item.replies > 0 {
                                Text("\(item.replies)")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.black.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Read-Only Post Card (Smaller Glassmorphic Design with Tap-to-Expand & Swipe Actions)

struct ReadOnlyProfilePostCard: View {
    let post: ProfilePost
    let isLiked: Bool
    let isExpanded: Bool  // ✅ NEW: Expansion state
    let onLike: () -> Void
    let onReply: () -> Void
    let onToggleExpand: () -> Void  // ✅ NEW: Toggle expansion callback
    
    @State private var isPressed = false
    @State private var swipeOffset: CGFloat = 0  // ✅ NEW: Swipe gesture tracking
    @State private var swipeDirection: SwipeDirection?  // ✅ NEW: Swipe direction
    @State private var showSwipeHint = false  // ✅ NEW: Show swipe icons
    @State private var showShareSheet = false  // ✅ Share sheet
    @State private var showMoreOptions = false  // ✅ More options menu
    
    // ✅ NEW: Swipe direction enum
    enum SwipeDirection {
        case left, right
    }
    
    // ✅ NEW: Check if content needs expansion
    private var needsExpansion: Bool {
        post.content.count > 120  // Threshold for "See More"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Post content - Expandable
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .lineLimit(isExpanded ? nil : 4)  // ✅ UPDATED: Conditional line limit
                .animation(.easeInOut(duration: 0.3), value: isExpanded)  // ✅ NEW: Smooth expansion
            
            // ✅ NEW: "See More" / "See Less" button
            if needsExpansion {
                Button {
                    onToggleExpand()
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "See Less" : "See More")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity.combined(with: .scale))
            }
            
            // Time stamp with post type indicator - Smaller
            HStack(spacing: 6) {
                Text(post.timestamp)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.black.opacity(0.5))
                
                // Post type indicator - Minimal black and white
                if let postType = post.postType {
                    HStack(spacing: 3) {
                        Image(systemName: postType.icon)
                            .font(.system(size: 9, weight: .medium))
                        Text(postType.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 9))
                    }
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .strokeBorder(.black.opacity(0.15), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            
            // Interaction buttons - Minimal, production-ready
            HStack(spacing: 16) {
                // Amen Button (NO COUNT - just icon)
                Button {
                    onLike()
                } label: {
                    Image(systemName: isLiked ? "hands.clap.fill" : "hands.clap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isLiked ? .black : .black.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isLiked ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLiked)
                
                // Comment Button - Production ready with count badge
                Button {
                    onReply()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.black.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                        
                        // Comment count badge (only if > 0)
                        if post.replies > 0 {
                            Text("\(post.replies)")
                                .font(.custom("OpenSans-Bold", size: 9))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black)
                                )
                                .offset(x: 8, y: -4)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Share Button
                Button {
                    sharePost()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Like count indicator (subtle, right-aligned)
                if post.likes > 0 {
                    Text("\(post.likes)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.black.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                // Glassmorphic background - Black and white translucent
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                
                // White overlay for brightness
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.7),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Subtle border
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(isPressed ? 0.15 : 0.06), radius: isPressed ? 6 : 12, x: 0, y: isPressed ? 2 : 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // ✅ NEW: Swipe gesture for quick actions
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    handleSwipeChanged(value: value)
                }
                .onEnded { value in
                    handleSwipeEnded(value: value)
                }
        )
        // ✅ NEW: Swipe action icons
        .overlay(alignment: .leading) {
            if swipeDirection == .right && swipeOffset > 20 {
                swipeAmenIcon
                    .padding(.leading, 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            if swipeDirection == .left && swipeOffset < -20 {
                swipeCommentIcon
                    .padding(.trailing, 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [
                "Check out this post on AMEN!",
                "https://amenapp.com/post/\(post.id)"
            ])
        }
    }
    
    // MARK: - Helper Functions
    
    /// Share the post
    private func sharePost() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        showShareSheet = true
    }
    
    // ✅ NEW: Swipe Amen Icon
    private var swipeAmenIcon: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 50, height: 50)
            
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
        }
    }
    
    // ✅ NEW: Swipe Comment Icon
    private var swipeCommentIcon: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 50, height: 50)
            
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
        }
    }
    
    // ✅ NEW: Handle swipe gesture changes
    private func handleSwipeChanged(value: DragGesture.Value) {
        let maxSwipe: CGFloat = 80
        swipeOffset = max(-maxSwipe, min(maxSwipe, value.translation.width))
        
        // Determine swipe direction
        if value.translation.width > 20 {
            withAnimation(.easeOut(duration: 0.2)) {
                swipeDirection = .right  // Amen
            }
        } else if value.translation.width < -20 {
            withAnimation(.easeOut(duration: 0.2)) {
                swipeDirection = .left  // Comment
            }
        } else {
            swipeDirection = nil
        }
    }
    
    // ✅ NEW: Handle swipe gesture end
    private func handleSwipeEnded(value: DragGesture.Value) {
        let threshold: CGFloat = 60
        
        if swipeOffset > threshold {
            // Trigger amen
            triggerAmenSwipe()
        } else if swipeOffset < -threshold {
            // Trigger comment
            triggerCommentSwipe()
        }
        
        // Reset swipe
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            swipeOffset = 0
            swipeDirection = nil
        }
    }
    
    // ✅ NEW: Trigger amen from swipe
    private func triggerAmenSwipe() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            swipeOffset = 0
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Small delay for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onLike()
        }
    }
    
    // ✅ NEW: Trigger comment from swipe
    private func triggerCommentSwipe() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            swipeOffset = 0
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Small delay for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onReply()
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
            postType: .testimony,
            createdAt: Date().addingTimeInterval(-3600) // 1 hour ago
        ),
        ProfilePost(
            id: "post-2",
            content: "Morning devotional reminder: 'Trust in the Lord with all your heart.' - Proverbs 3:5. Start your day with faith! ☀️",
            timestamp: "1d ago",
            likes: 189,
            replies: 23,
            postType: .prayer,
            createdAt: Date().addingTimeInterval(-86400) // 1 day ago
        ),
        ProfilePost(
            id: "post-3",
            content: "Excited to announce I'll be speaking at the Christian Entrepreneurs Summit next month! Who's attending?",
            timestamp: "2d ago",
            likes: 156,
            replies: 67,
            postType: nil,
            createdAt: Date().addingTimeInterval(-172800) // 2 days ago
        ),
        ProfilePost(
            id: "post-4",
            content: "Reminder: Your worth is not determined by your productivity. Rest is biblical. Take care of yourself today. 💙",
            timestamp: "3d ago",
            likes: 412,
            replies: 89,
            postType: .openTable,
            createdAt: Date().addingTimeInterval(-259200) // 3 days ago
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
                    bioURL: nil,  // FollowUserProfile doesn't include bioURL
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
                
                FlowLayout(spacing: 8) {
                    ForEach(Array(interests.enumerated()), id: \.offset) { index, interest in
                        HandDrawnInterestTag(interest: interest, index: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Hand-Drawn Interest Tag

struct HandDrawnInterestTag: View {
    let interest: String
    let index: Int
    @State private var animateStroke: CGFloat = 0
    
    var body: some View {
        Text(interest)
            .font(.custom("OpenSans-SemiBold", size: 13))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                HandDrawnCircle(animationProgress: animateStroke)
                    .stroke(
                        Color.orange,
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(-4)
            )
            .onAppear {
                // Stagger animation by index
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .delay(Double(index) * 0.15)
                ) {
                    animateStroke = 1.0
                }
            }
    }
}

// MARK: - Hand-Drawn Circle Shape

struct HandDrawnCircle: Shape {
    var animationProgress: CGFloat
    
    var animatableData: CGFloat {
        get { animationProgress }
        set { animationProgress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        let centerY = height / 2
        
        // Create imperfect ellipse with hand-drawn feel
        // Add subtle variations to make it look hand-drawn
        let radiusX = width / 2
        let radiusY = height / 2
        
        // Start from the left side
        let startAngle = CGFloat.pi
        let endAngle = startAngle + (2 * .pi * animationProgress)
        
        // Number of points for the curve (more = smoother but still imperfect)
        let segments = 60
        let angleStep = (2 * .pi) / CGFloat(segments)
        
        var isFirst = true
        
        for i in 0...segments {
            let angle = startAngle + (angleStep * CGFloat(i))
            
            // Only draw up to the animated progress
            if angle > endAngle { break }
            
            // Add subtle random-ish variations for hand-drawn effect
            // Use deterministic "randomness" based on angle for consistency
            let wobbleX = sin(angle * 7) * 1.5  // Frequency 7 creates natural wobble
            let wobbleY = cos(angle * 11) * 1.5  // Different frequency for Y
            
            // Calculate point on ellipse with wobble
            let x = centerX + (radiusX * cos(angle)) + wobbleX
            let y = centerY + (radiusY * sin(angle)) + wobbleY
            
            if isFirst {
                path.move(to: CGPoint(x: x, y: y))
                isFirst = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
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
            // Repost indicator - Smaller, black and white
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .medium))
                Text("Reposted from \(originalAuthor)")
                    .font(.custom("OpenSans-SemiBold", size: 10))
            }
            .foregroundStyle(.black.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .strokeBorder(.black.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Content - More compact
            Text(content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .lineLimit(4) // Limit for compactness
            
            // Time stamp
            Text(timestamp)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.black.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.top, 6)
            
            // Stats - Right aligned, subtle
            HStack {
                Spacer()
                
                HStack(spacing: 12) {
                    if likes > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.clap")
                                .font(.system(size: 11))
                            Text("\(likes)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(.black.opacity(0.4))
                    }
                    
                    if replies > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 11))
                            Text("\(replies)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                        .foregroundStyle(.black.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                // Glassmorphic background - Black and white
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                
                // White overlay with subtle gradient
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Subtle border
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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

/// MARK: - 2. Smart Infinite Scroll

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

// MARK: - Scroll View with Offset Tracking

/// Custom ScrollView that tracks scroll offset
struct ScrollViewWithOffset<Content: View>: View {
    @Binding var offset: CGFloat
    let content: Content
    
    init(offset: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        self._offset = offset
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).minY
                    )
                }
                .frame(height: 0)
                
                content
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            offset = -value  // Negative because scroll offset is inverted
        }
    }
}

/// Preference key for tracking scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// UIActivityViewController wrapper for SwiftUI
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Inline Error Banner

/// Inline error banner for recoverable errors
struct InlineErrorBanner: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.black.opacity(0.7))
                .lineLimit(2)
            
            Spacer()
            
            Button {
                retryAction()
            } label: {
                Text("Retry")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
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
                // ✅ Success - Open UnifiedChatView with the conversation
                UnifiedChatView(
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

// MARK: - 📱 Production-Ready Advanced Features

// MARK: - 1. Post Notifications Toggle

extension UserProfileView {
    /// Enable/disable notifications for this user's posts
    private func toggleNotifications() {
        Task {
            await performNotificationToggle()
        }
    }
    
    @MainActor
    private func performNotificationToggle() async {
        let previousState = notificationsEnabled
        notificationsEnabled.toggle()
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            // TODO: Implement notification service
            // await NotificationService.shared.toggleUserNotifications(userId: userId, enabled: notificationsEnabled)
            print("✅ \(notificationsEnabled ? "Enabled" : "Disabled") notifications for user: \(userId)")
            
        } catch {
            // Rollback on error
            await MainActor.run {
                notificationsEnabled = previousState
                errorMessage = "Failed to update notification settings. Please try again."
                showErrorAlert = true
            }
            print("❌ Failed to toggle notifications: \(error)")
        }
    }
}

// MARK: - 2. Advanced Share Options

extension UserProfileView {
    /// Show advanced share sheet with profile link
    private func showAdvancedShareSheet() {
        guard let profileData = profileData else { return }
        
        let username = "@\(profileData.username)"
        let shareText = "Check out \(profileData.name)'s AMEN profile: \(username)"
        
        // ✅ FIXED: Safe URL creation with proper encoding and validation
        guard let encodedUsername = profileData.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let shareURL = URL(string: "https://amenapp.com/\(encodedUsername)") else {
            print("❌ Failed to create share URL for username: \(profileData.username)")
            // Fallback to text-only sharing
            shareItems = [shareText]
            showShareSheet = true
            return
        }
        
        // Create QR code for profile (optional enhancement)
        let qrImage = generateQRCode(from: shareURL.absoluteString)
        
        var items: [Any] = [shareText, shareURL]
        if let qrImage = qrImage {
            items.append(qrImage)
        }
        
        shareItems = items
        showShareSheet = true
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Generate QR code for profile URL
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 3. Profile Analytics (Optional - for your own profile view)

extension UserProfileView {
    /// Fetch profile view analytics (if viewing own profile)
    private func fetchProfileAnalytics() async {
        // TODO: Implement analytics
        // - Profile views count
        // - Most viewed post
        // - Follower growth
        print("📊 Analytics feature - implement when needed")
    }
}

// MARK: - 4. Offline Support Improvements

extension UserProfileView {
    /// Save profile to local cache for offline viewing
    private func cacheProfileData() {
        guard let profileData = profileData else { return }
        
        // TODO: Implement UserDefaults or CoreData caching
        // UserDefaults.standard.set(encodedProfile, forKey: "cached_profile_\(userId)")
        print("💾 Caching profile data for offline support")
    }
    
    /// Load cached profile data
    private func loadCachedProfile() -> UserProfile? {
        // TODO: Implement cache retrieval
        // return try? JSONDecoder().decode(UserProfile.self, from: cachedData)
        return nil
    }
}

// MARK: - 5. Accessibility Improvements

extension UserProfileView {
    /// Announce profile loaded for VoiceOver users
    private func announceProfileLoaded() {
        guard let profileData = profileData else { return }
        
        let announcement = """
        Profile loaded. \(profileData.name), username \(profileData.username). \
        \(profileData.followersCount) followers, \(profileData.followingCount) following. \
        \(profileData.isPrivateAccount ? "Private account." : "Public account.")
        """
        
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

// MARK: - 6. Performance Monitoring

extension UserProfileView {
    /// Track profile load performance
    private func trackLoadPerformance(startTime: Date) {
        let loadTime = Date().timeIntervalSince(startTime)
        print("⏱️ Profile loaded in \(String(format: "%.2f", loadTime))s")
        
        // TODO: Send to analytics service
        // Analytics.track("profile_load_time", properties: ["duration": loadTime, "userId": userId])
    }
    
    /// Format timestamp to relative time string (e.g., "2h ago")
    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks)w"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - 7. Enhanced Toolbar with Notifications Toggle

// Note: enhancedToolbarMenu is already defined in toolbarButtonsView
// This extension is kept for documentation purposes only

#Preview {
    UserProfileView(userId: "sample-user-id")
}
