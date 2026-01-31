//
//  ProfileView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase

// MARK: - Profile Tab Enum

enum ProfileTab: String, CaseIterable {
    case posts = "Posts"
    case replies = "Replies"
    case saved = "Saved"
    case reposts = "Reposts"
    
    var icon: String {
        switch self {
        case .posts: return "square.grid.2x2"
        case .replies: return "bubble.left"
        case .saved: return "bookmark"
        case .reposts: return "arrow.2.squarepath"
        }
    }
}

/// Profile View - Threads-inspired with Black & White Design
struct ProfileView: View {
    // Remove ambiguous UserService reference - not needed since we fetch directly from Firebase
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var selectedTab = ProfileTab.posts
    @State private var showQRCode = false
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var avatarPressed = false
    @State private var showImagePicker = false
    @State private var showFullScreenAvatar = false
    
    // Profile data - initialized from Firebase
    @State private var profileData: UserProfileData = UserProfileData(
        name: "",
        username: "",
        bio: "",
        initials: "",
        profileImageURL: nil,
        interests: [],
        socialLinks: []
    )
    
    // Real backend data - no more fake posts!
    @State private var userPosts: [Post] = []
    @State private var userReplies: [AMENAPP.Comment] = []
    @State private var savedPosts: [Post] = []
    @State private var reposts: [Post] = []
    
    // Real-time listeners - track if listeners are active
    @State private var listenersActive = false
    
    // NEW: Login History state
    @State private var showLoginHistory = false
    
    // NEW: Stats Display
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    @StateObject private var followService = FollowService.shared
    
    @Namespace private var tabNamespace
    
    // Scroll offset tracking for header animation
    @State private var scrollOffset: CGFloat = 0
    @State private var showCompactHeader = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header with Liquid Glass
                    profileHeaderView
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).minY
                                    )
                            }
                        )
                    
                    // Tab Selector with Liquid Glass (flush underneath)
                    tabSelectorView
                    
                    // Content based on selected tab with loading state
                    Group {
                        if isLoading {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                
                                Text("Loading...")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            contentView
                        }
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
                // Show compact header when scrolled past 200 points
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompactHeader = value < -200
                }
            }
            .refreshable {
                await refreshProfile()
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // TOP LEFT: Compact Profile Header (shows when scrolled)
                ToolbarItem(placement: .topBarLeading) {
                    if showCompactHeader {
                        HStack(spacing: 12) {
                            // Compact Avatar
                            Circle()
                                .fill(Color.black)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(profileData.initials)
                                        .font(.custom("OpenSans-Bold", size: 12))
                                        .foregroundStyle(.white)
                                )
                            
                            // Name & Username
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileData.name)
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                
                                Text("@\(profileData.username)")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.black.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            showLoginHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        Button {
                            showQRCode = true
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        Button {
                            shareProfile()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(profileData: $profileData)
            }
            .sheet(isPresented: $showQRCode) {
                ProfileQRCodeView(username: "@\(profileData.username)", name: profileData.name)
            }
            .sheet(isPresented: $showFullScreenAvatar) {
                FullScreenAvatarView(name: profileData.name, initials: profileData.initials, profileImageURL: profileData.profileImageURL)
            }
            .sheet(isPresented: $showLoginHistory) {
                LoginHistoryView()
            }
            .sheet(isPresented: $showFollowersList) {
                SocialFollowersListView(userId: Auth.auth().currentUser?.uid ?? "", listType: .followers)
                    .onAppear {
                        print("📱 Followers list sheet opened")
                    }
                    .onDisappear {
                        print("📱 Followers list sheet closed")
                    }
            }
            .sheet(isPresented: $showFollowingList) {
                SocialFollowersListView(userId: Auth.auth().currentUser?.uid ?? "", listType: .following)
                    .onAppear {
                        print("📱 Following list sheet opened")
                    }
                    .onDisappear {
                        print("📱 Following list sheet closed")
                    }
            }
            .onAppear {
                // Load real user data when view appears
                print("👁️ ProfileView appeared")
                print("   Current state - Posts: \(userPosts.count), Replies: \(userReplies.count), Saved: \(savedPosts.count)")
                print("   Listeners active: \(listenersActive)")
                
                // Start follow service listeners for real-time counts
                Task {
                    await followService.startListening()
                    print("✅ FollowService listeners started")
                    print("   Followers: \(followService.currentUserFollowersCount)")
                    print("   Following: \(followService.currentUserFollowingCount)")
                }
                
                // Only load if we don't have data yet
                if userPosts.isEmpty && !listenersActive {
                    print("   -> Loading profile data for first time")
                    Task {
                        await loadProfileData()
                    }
                } else {
                    print("   -> Data already loaded, skipping reload")
                }
            }
            .onDisappear {
                // Keep listeners active so data persists
                print("👋 ProfileView disappeared - keeping listeners and data active")
                // Note: Data and listeners stay in memory so posts persist when switching tabs
                // Listeners will continue to receive real-time updates
            }
            .onReceive(NotificationCenter.default.publisher(for: .newPostCreated)) { notification in
                // Real-time update when user creates a new post (OPTIMIZED)
                print("📬 New post created notification received in ProfileView")
                
                Task {
                    // Check if notification includes the post object
                    if let userInfo = notification.userInfo,
                       let newPost = userInfo["post"] as? Post {
                        
                        let isOptimistic = userInfo["isOptimistic"] as? Bool ?? false
                        
                        // Only process optimistic updates - Firebase listener will handle confirmed posts
                        if isOptimistic {
                            await MainActor.run {
                                // Only add if it's not already there (avoid duplicates)
                                if !userPosts.contains(where: { $0.id == newPost.id }) {
                                    userPosts.insert(newPost, at: 0)  // Add to beginning of array
                                    print("⚡ Optimistic post added to profile feed INSTANTLY")
                                    print("   Post ID: \(newPost.id)")
                                    print("   Total posts now: \(userPosts.count)")
                                } else {
                                    print("⚠️ Post already exists in feed, skipping")
                                }
                            }
                        } else {
                            print("✅ Confirmed post - Firebase listener will handle it")
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("postDeleted"))) { notification in
                // Real-time update when a post is deleted
                if let userInfo = notification.userInfo,
                   let postId = userInfo["postId"] as? UUID {
                    
                    Task { @MainActor in
                        // Remove from all arrays
                        userPosts.removeAll { $0.id == postId }
                        savedPosts.removeAll { $0.id == postId }
                        reposts.removeAll { $0.id == postId }
                        
                        print("🗑️ Post removed from profile feed: \(postId)")
                        
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("postReposted"))) { notification in
                // Real-time update when user reposts
                if let userInfo = notification.userInfo,
                   let repostedPost = userInfo["post"] as? Post {
                    
                    Task { @MainActor in
                        // Add to reposts array
                        if !reposts.contains(where: { $0.id == repostedPost.id }) {
                            reposts.insert(repostedPost, at: 0)
                            print("🔄 Repost added to profile feed: \(repostedPost.id)")
                            
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.success)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("postSaved"))) { notification in
                // Real-time update when user saves a post
                if let userInfo = notification.userInfo,
                   let savedPost = userInfo["post"] as? Post {
                    
                    Task { @MainActor in
                        // Add to saved posts array
                        if !savedPosts.contains(where: { $0.id == savedPost.id }) {
                            savedPosts.insert(savedPost, at: 0)
                            print("🔖 Saved post added to profile: \(savedPost.id)")
                            
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("postUnsaved"))) { notification in
                // Real-time update when user unsaves a post
                if let userInfo = notification.userInfo,
                   let postId = userInfo["postId"] as? UUID {
                    
                    Task { @MainActor in
                        // Remove from saved posts
                        savedPosts.removeAll { $0.id == postId }
                        print("🔖 Post removed from saved: \(postId)")
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                }
            }
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
    
    private func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month, .year], from: date, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        }
        if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        if let week = components.weekOfYear, week > 0 {
            return "\(week)w"
        }
        if let day = components.day, day > 0 {
            return "\(day)d"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        }
        return "now"
    }
    
    // MARK: - Refresh Function
    
    @MainActor
    private func refreshProfile() async {
        isRefreshing = true
        
        print("🔄 Refreshing profile data...")
        
        // Get current user ID
        guard let userId = Auth.auth().currentUser?.uid else {
            isRefreshing = false
            return
        }
        
        // Reload all data from Firebase Realtime Database
        do {
            // 1. Refresh posts
            let postService = RealtimePostService.shared
            let refreshedPosts = try await postService.fetchUserPosts(userId: userId)
            userPosts = refreshedPosts
            print("   ✅ Posts refreshed: \(refreshedPosts.count)")
            
            // 2. Refresh saved posts
            let savedPostsService: RealtimeSavedPostsService = .shared
            let refreshedSavedPosts = try await savedPostsService.fetchSavedPosts()
            savedPosts = refreshedSavedPosts
            print("   ✅ Saved posts refreshed: \(refreshedSavedPosts.count)")
            
            // 3. Refresh replies
            let commentsService = AMENAPP.RealtimeCommentsService.shared
            let refreshedReplies = try await commentsService.fetchUserComments(userId: userId)
            userReplies = refreshedReplies
            print("   ✅ Replies refreshed: \(refreshedReplies.count)")
            
            // 4. Refresh reposts
            let repostsService: RealtimeRepostsService = .shared
            let refreshedReposts = try await repostsService.fetchUserReposts(userId: userId)
            reposts = refreshedReposts
            print("   ✅ Reposts refreshed: \(refreshedReposts.count)")
            
        } catch {
            print("❌ Error refreshing profile data: \(error)")
        }
        
        isRefreshing = false
        
        // Success haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ Profile refreshed successfully")
        print("   Posts: \(userPosts.count)")
        print("   Replies: \(userReplies.count)")
        print("   Saved: \(savedPosts.count)")
        print("   Reposts: \(reposts.count)")
    }
    
    @MainActor
    private func loadProfileData() async {
        isLoading = true
        
        // Get current Firebase Auth user
        guard let authUser = Auth.auth().currentUser else {
            print("❌ ProfileView: No Firebase Auth user")
            isLoading = false
            return
        }
        
        print("📱 ProfileView: Loading profile for user: \(authUser.uid)")
        
        // DEBUG: Test Realtime Database connection
        await testRealtimeDatabaseConnection()
        
        // DIRECT Firestore fetch for profile data (profile stays in Firestore)
        let db = Firestore.firestore()
        
        do {
            let doc = try await db.collection("users").document(authUser.uid).getDocument()
            
            guard doc.exists, let data = doc.data() else {
                print("❌ ProfileView: Firestore document not found for user: \(authUser.uid)")
                isLoading = false
                return
            }
            
            print("✅ ProfileView: Firestore document found")
            print("   Display Name: \(data["displayName"] as? String ?? "N/A")")
            print("   Username: \(data["username"] as? String ?? "N/A")")
            
            // Extract data directly from Firestore
            let displayName = data["displayName"] as? String ?? "User"
            let username = data["username"] as? String ?? "user"
            let bio = data["bio"] as? String ?? ""
            let profileImageURL = data["profileImageURL"] as? String
            let interests = data["interests"] as? [String] ?? []
            
            // Generate initials from display name
            let names = displayName.components(separatedBy: " ")
            let initials = names.compactMap { $0.first }.map { String($0) }.joined().prefix(2).uppercased()
            
            // Fetch social links from Firestore
            let socialLinksData = data["socialLinks"] as? [[String: Any]] ?? []
            let socialLinks = socialLinksData.compactMap { linkDict -> SocialLinkUI? in
                guard let platformStr = linkDict["platform"] as? String,
                      let username = linkDict["username"] as? String,
                      let platform = SocialLinkUI.SocialPlatform(rawValue: platformStr) else {
                    return nil
                }
                return SocialLinkUI(platform: platform, username: username)
            }
            
            print("📱 Loaded \(socialLinks.count) social links from Firestore")
            
            // Update profile data
            profileData = UserProfileData(
                name: displayName,
                username: username,
                bio: bio,
                initials: String(initials),
                profileImageURL: profileImageURL,
                interests: interests,
                socialLinks: socialLinks
            )
            
            print("✅ ProfileView: Profile data updated")
            print("   Name: \(profileData.name)")
            print("   Username: @\(profileData.username)")
            
            // Cache the user's name for messaging
            FirebaseMessagingService.shared.updateCurrentUserName(displayName)
            
            // 🚀 OPTIMIZATION: Cache user data for fast post creation
            UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
            UserDefaults.standard.set(username, forKey: "currentUserUsername")
            UserDefaults.standard.set(String(initials), forKey: "currentUserInitials")
            if let imageURL = profileImageURL {
                UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
            }
            print("✅ User data cached for optimized post creation")
            
            // 🔥 NEW: Fetch posts from Realtime Database instead of Firestore
            let userId = authUser.uid
            
            // Always fetch data and set up listeners if they're not active
            if !listenersActive {
                print("🔥 First load - fetching initial data from Realtime DB and setting up listeners")
                
                // 1. Fetch user's own posts from Realtime Database
                let postService = RealtimePostService.shared
                let fetchedPosts = try await postService.fetchUserPosts(userId: userId)
                userPosts = fetchedPosts
                
                // 2. Fetch saved posts from Realtime Database
                let savedPostsService: RealtimeSavedPostsService = .shared
                let fetchedSavedPosts = try await savedPostsService.fetchSavedPosts()
                savedPosts = fetchedSavedPosts
                
                // 3. Fetch user's comments/replies from Realtime Database
                let commentsService = AMENAPP.RealtimeCommentsService.shared
                let fetchedReplies = try await commentsService.fetchUserComments(userId: userId)
                userReplies = fetchedReplies
                
                // 4. Fetch user's reposts from Realtime Database
                let repostsService: RealtimeRepostsService = .shared
                let fetchedReposts = try await repostsService.fetchUserReposts(userId: userId)
                reposts = fetchedReposts
                
                // 🔥 SET UP REAL-TIME LISTENERS for continuous updates
                setupRealtimeDatabaseListeners(userId: userId)
                
                // Mark listeners as active
                listenersActive = true
                
                print("✅ Profile data loaded from Realtime DB:")
                print("   Posts: \(userPosts.count)")
                print("   Reposts: \(reposts.count)")
                print("   Saved: \(savedPosts.count)")
                print("   Replies: \(userReplies.count)")
            } else {
                // Listeners are active, but let's refresh the data
                print("🔥 Listeners active - refreshing data from Realtime DB")
                
                let postService = RealtimePostService.shared
                let fetchedPosts = try await postService.fetchUserPosts(userId: userId)
                userPosts = fetchedPosts
                
                let savedPostsService: RealtimeSavedPostsService = .shared
                let fetchedSavedPosts = try await savedPostsService.fetchSavedPosts()
                savedPosts = fetchedSavedPosts
                
                let commentsService = AMENAPP.RealtimeCommentsService.shared
                let fetchedReplies = try await commentsService.fetchUserComments(userId: userId)
                userReplies = fetchedReplies
                
                print("✅ Profile data refreshed:")
                print("   Posts: \(userPosts.count)")
                print("   Reposts: \(reposts.count)")
                print("   Saved: \(savedPosts.count)")
                print("   Replies: \(userReplies.count)")
            }
            
        } catch {
            print("❌ ProfileView: Error loading profile - \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Debug Realtime Database
    
    private func testRealtimeDatabaseConnection() async {
        print("🧪 Testing Realtime Database connection...")
        
        do {
            // Try to read from Realtime Database
            let testRef = FirebaseDatabase.Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
            let snapshot = try await testRef.child("test").getData()
            
            if snapshot.exists() {
                print("✅ Realtime Database connected and readable")
            } else {
                print("⚠️ Realtime Database connected but no test data")
            }
            
            // Try to write
            try await testRef.child("test").child("connection").setValue([
                "timestamp": Date().timeIntervalSince1970,
                "user": Auth.auth().currentUser?.uid ?? "unknown"
            ])
            print("✅ Realtime Database write successful")
            
        } catch {
            print("❌ Realtime Database error: \(error.localizedDescription)")
            print("   Error details: \(error)")
        }
    }
    
    // MARK: - Share Profile Function
    
    private func shareProfile() {
        let username = "@\(profileData.username)"
        let shareText = "Check out \(profileData.name)'s AMEN profile: \(username)"
        
        guard let shareURL = URL(string: "https://amenapp.com/\(profileData.username)") else {
            print("❌ Invalid profile URL")
            return
        }
        
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
    
    // MARK: - Open Social Link Function
    
    private func openSocialLink(_ link: SocialLinkUI) {
        var urlString = ""
        
        switch link.platform {
        case .twitter:
            urlString = "https://twitter.com/\(link.username)"
        case .instagram:
            urlString = "https://instagram.com/\(link.username)"
        case .linkedin:
            urlString = "https://linkedin.com/in/\(link.username)"
        case .youtube:
            urlString = "https://youtube.com/@\(link.username)"
        case .tiktok:
            urlString = "https://tiktok.com/@\(link.username)"
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid social link URL: \(urlString)")
            return
        }
        
        UIApplication.shared.open(url)
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        print("🔗 Opened social link: \(link.platform.rawValue) - \(link.username)")
    }
    
    // MARK: - Real-time Listeners (Realtime Database)
    
    /// Set up Realtime Database listeners for posts, saved posts, and replies
    @MainActor
    private func setupRealtimeDatabaseListeners(userId: String) {
        print("🔥 Setting up Realtime Database listeners for profile data...")
        
        // Don't remove existing listeners - just set up new ones if needed
        // This ensures continuous real-time updates
        
        // 1. Listen to user's posts in real-time
        RealtimePostService.shared.observeUserPosts(userId: userId) { posts in
            Task { @MainActor in
                self.userPosts = posts
                print("🔄 Real-time update: \(posts.count) posts")
            }
        }
        
        // 2. Listen to saved posts in real-time
        RealtimeSavedPostsService.shared.observeSavedPosts { postIds in
            Task {
                // Fetch full post details for saved posts
                do {
                    let posts = try await RealtimeSavedPostsService.shared.fetchSavedPosts()
                    await MainActor.run {
                        self.savedPosts = posts
                        print("🔄 Real-time update: \(posts.count) saved posts")
                    }
                } catch {
                    print("❌ Error fetching saved posts details: \(error)")
                }
            }
        }
        
        // 3. Listen to user's reposts in real-time
        RealtimeRepostsService.shared.observeUserReposts(userId: userId) { posts in
            Task { @MainActor in
                self.reposts = posts
                print("🔄 Real-time update: \(posts.count) reposts")
            }
        }
        
        // 4. TODO: Listen to user's comments (implement when needed)
        // Note: Comments can be fetched on-demand since they update less frequently
        
        print("✅ Realtime Database listeners set up successfully")
    }
    
    /// Remove all Realtime Database listeners
    @MainActor
    private func removeRealtimeDatabaseListeners() {
        // Note: We're NOT actually removing listeners here
        // They stay active to keep receiving real-time updates
        // This is intentional to keep data persistent across tab switches
        print("🔇 Keeping Realtime Database listeners active (not removing)")
    }
    
    // MARK: - View Helpers
    
    private func liquidGlassButtonLabel(text: String) -> some View {
        Text(text)
            .font(.custom("OpenSans-Bold", size: 15))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(liquidGlassBackground)
    }
    
    private var liquidGlassBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(white: 0.93))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Profile Header
    
    // Extract complex avatar view to help compiler
    @ViewBuilder
    private var profileAvatarView: some View {
        if let profileImageURL = profileData.profileImageURL, !profileImageURL.isEmpty {
            AsyncImage(url: URL(string: profileImageURL)) { phase in
                switch phase {
                case .empty:
                    avatarPlaceholder(showProgress: true)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                case .failure:
                    avatarInitials
                @unknown default:
                    avatarInitials
                }
            }
            .frame(width: 80, height: 80)
        } else {
            avatarInitials
        }
    }
    
    private var avatarInitials: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: 80, height: 80)
            
            Text(profileData.initials)
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
        }
    }
    
    private func avatarPlaceholder(showProgress: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 80, height: 80)
            if showProgress {
                ProgressView()
            }
        }
    }
    
    private var profileHeaderView: some View {
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
                
                // Avatar with bounce animation
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        avatarPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            avatarPressed = false
                        }
                    }
                    // Show full screen avatar after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showFullScreenAvatar = true
                    }
                } label: {
                    profileAvatarView
                        .scaleEffect(avatarPressed ? 0.9 : 1.0)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profileData.interests, id: \.self) { interest in
                            Text(interest)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.08))
                                )
                        }
                    }
                }
            }
            
            // Social Links - Clickable
            if !profileData.socialLinks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profileData.socialLinks) { link in
                        Button {
                            openSocialLink(link)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: link.platform.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(link.platform.color)
                                
                                Text(link.username)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.black.opacity(0.7))
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.black.opacity(0.3))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Follower/Following Stats - Tappable (Left Aligned)
            HStack(spacing: 24) {
                Button {
                    print("👥 Opening followers list...")
                    print("   Current followers count: \(followService.currentUserFollowersCount)")
                    showFollowersList = true
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(followService.currentUserFollowersCount)")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.black)
                        Text("followers")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button {
                    print("👥 Opening following list...")
                    print("   Current following count: \(followService.currentUserFollowingCount)")
                    showFollowingList = true
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(followService.currentUserFollowingCount)")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.black)
                        Text("following")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            // Action Buttons (Full Width - Expanded)
            HStack(spacing: 8) {
                Button {
                    showEditProfile = true
                } label: {
                    Text("Edit profile")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.93))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        )
                }
                
                Button {
                    shareProfile()
                } label: {
                    Text("Share profile")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(white: 0.93))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        )
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
                .padding(.horizontal, 20), 
            alignment: .bottom
        )
    }
    
    // MARK: - Tab Selector (Floating Pill Design)
    
    private var tabSelectorView: some View {
        HStack(spacing: 8) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    // Switch tab with animation
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                    
                    // Analytics tracking
                    print("📊 Tab switched to: \(tab.rawValue)")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .black.opacity(0.6))
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, selectedTab == tab ? 20 : 16)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                // Selected state - black pill with shadow
                                Capsule()
                                    .fill(Color.black)
                                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                                    .matchedGeometryEffect(id: "tabBackground", in: tabNamespace)
                            } else {
                                // Unselected state - subtle background
                                Capsule()
                                    .fill(Color.black.opacity(0.04))
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1), 
            alignment: .bottom
        )
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .posts:
                PostsContentView(posts: $userPosts)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity),
                        removal: AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity)
                    ))
            case .replies:
                RepliesContentView(replies: $userReplies)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity),
                        removal: AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity)
                    ))
            case .saved:
                SavedContentView(savedPosts: $savedPosts)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity),
                        removal: AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity)
                    ))
            case .reposts:
                RepostsContentView(reposts: $reposts)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity),
                        removal: AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity)
                    ))
            }
        }
    }
}



// MARK: - QR Code View

struct ProfileQRCodeView: View {
    @Environment(\.dismiss) var dismiss
    let username: String
    let name: String
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Profile Info
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(name.prefix(2).uppercased())
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                        )
                    
                    Text(name)
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.black)
                    
                    Text(username)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                // QR Code
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .frame(width: 280, height: 280)
                            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                        
                        // Generate QR Code
                        if let qrImage = generateQRCode(from: "https://amenapp.com/\(username)") {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 240, height: 240)
                        } else {
                            // Placeholder
                            Image(systemName: "qrcode")
                                .font(.system(size: 120))
                                .foregroundStyle(.black.opacity(0.2))
                        }
                    }
                    
                    Text("Scan to view profile")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.black.opacity(0.6))
                }
                
                Spacer()
                
                // Share Button
                Button {
                    shareQRCode()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Share QR Code")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Profile QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                }
            }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .ascii)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            
            if let output = filter.outputImage?.transformed(by: transform) {
                let context = CIContext()
                if let cgImage = context.createCGImage(output, from: output.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        
        return nil
    }
    
    private func shareQRCode() {
        guard let qrImage = generateQRCode(from: "https://amenapp.com/\(username)") else { return }
        
        let items = [qrImage, "Check out my profile on AMEN: \(username)"] as [Any]
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(av, animated: true)
        }
    }
}

// MARK: - Supporting Views

// Note: Using SocialLinkUI from SocialLinksEditView.swift
// No need to define a separate SocialLink model here

// MARK: - Profile Post Card (Minimal Glass Design)

/// A minimal, glass-morphic post card specifically designed for ProfileView
/// Inspired by iOS design language with smooth translucent aesthetics
struct ProfilePostCard: View {
    let post: Post
    
    @State private var showingMenu = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showCommentsSheet = false
    @State private var hasLitLightbulb = false
    @State private var hasSaidAmen = false
    @State private var lightbulbCount = 0
    @State private var amenCount = 0
    @State private var commentCount = 0
    
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var interactionsService = PostInteractionsService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            contentView
            interactionBar
        }
        .padding(16)
        .background(cardBackground)
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
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack(alignment: .center) {
            Text(post.timeAgo)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
    }
    
    private var contentView: some View {
        Text(post.content)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(.primary)
            .lineSpacing(5)
            .multilineTextAlignment(.leading)
    }
    
    private var interactionBar: some View {
        HStack(spacing: 0) {
            // Lightbulb/Amen button
            if post.category == .openTable {
                interactionButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: lightbulbCount,
                    isActive: hasLitLightbulb
                ) {
                    toggleLightbulb()
                }
            } else {
                interactionButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: amenCount,
                    isActive: hasSaidAmen
                ) {
                    toggleAmen()
                }
            }
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 8)
            
            // Comment button
            interactionButton(
                icon: "bubble.left",
                count: commentCount,
                isActive: false
            ) {
                showCommentsSheet = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(interactionBarBackground)
    }
    
    private var interactionBarBackground: some View {
        Capsule()
            .fill(Color.white)
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.black.opacity(0.2),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(0.2),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
    
    // MARK: - Menu Content
    
    @ViewBuilder
    private var menuContent: some View {
        // Edit (if within 30 minutes)
        if canEditPost(post) {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit Post", systemImage: "pencil")
            }
        }
        
        // Delete
        Button(role: .destructive) {
            showingDeleteAlert = true
        } label: {
            Label("Delete Post", systemImage: "trash")
        }
        
        Divider()
        
        // Share
        Button {
            sharePost()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        // Copy Link
        Button {
            copyLink()
        } label: {
            Label("Copy Link", systemImage: "link")
        }
    }
    
    // MARK: - Interaction Button
    
    private func interactionButton(
        icon: String,
        count: Int,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Actions
    
    private func canEditPost(_ post: Post) -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        return post.createdAt >= thirtyMinutesAgo
    }
    
    private func toggleLightbulb() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasLitLightbulb.toggle()
        }
        
        Task {
            do {
                try await interactionsService.toggleLightbulb(postId: post.id.uuidString)
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } catch {
                print("❌ Failed to toggle lightbulb: \(error)")
                await MainActor.run {
                    hasLitLightbulb.toggle()
                }
            }
        }
    }
    
    private func toggleAmen() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasSaidAmen.toggle()
        }
        
        Task {
            do {
                try await interactionsService.toggleAmen(postId: post.id.uuidString)
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Failed to toggle amen: \(error)")
                await MainActor.run {
                    hasSaidAmen.toggle()
                }
            }
        }
    }
    
    private func deletePost() {
        postsManager.deletePost(postId: post.id)
        
        NotificationCenter.default.post(
            name: Notification.Name("postDeleted"),
            object: nil,
            userInfo: ["postId": post.id]
        )
        
        print("🗑️ Post deleted")
    }
    
    private func sharePost() {
        let shareText = """
        \(post.content)
        
        Join the conversation on AMEN APP!
        https://amenapp.com/post/\(post.id.uuidString)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func copyLink() {
        UIPasteboard.general.string = "https://amenapp.com/post/\(post.id.uuidString)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    private func loadInteractions() async {
        let postId = post.id.uuidString
        
        // Start observing
        interactionsService.observePostInteractions(postId: postId)
        
        // Load initial states
        hasLitLightbulb = await interactionsService.hasLitLightbulb(postId: postId)
        hasSaidAmen = await interactionsService.hasAmened(postId: postId)
        
        // Load counts
        lightbulbCount = await interactionsService.getLightbulbCount(postId: postId)
        amenCount = await interactionsService.getAmenCount(postId: postId)
        commentCount = await interactionsService.getCommentCount(postId: postId)
    }
}

// MARK: - Content Views

struct PostsContentView: View {
    @Binding var posts: [Post]
    
    var body: some View {
        if posts.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("No posts yet")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("Your posts will appear here")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    ProfilePostCard(post: post)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

struct RepliesContentView: View {
    @Binding var replies: [AMENAPP.Comment]
    
    var body: some View {
        if replies.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.secondary)
                
                Text("No replies yet")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(Color.primary)
                
                Text("Your replies to others will appear here")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(replies) { comment in
                    ProfileReplyCard(comment: comment)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

struct SavedContentView: View {
    @Binding var savedPosts: [Post]
    
    var body: some View {
        if savedPosts.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("No saved posts")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("Posts you save will appear here")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(savedPosts) { post in
                    ProfilePostCard(post: post)
                        .overlay(
                            // Saved indicator
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                        .padding(5)
                                        .background(
                                            Circle()
                                                .fill(Color.blue)
                                                .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
                                        )
                                        .padding(12)
                                }
                                Spacer()
                            }
                        )
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

struct RepostsContentView: View {
    @Binding var reposts: [Post]
    
    var body: some View {
        if reposts.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("No reposts yet")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("Posts you repost will appear here")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(reposts) { post in
                    VStack(spacing: 8) {
                        // Repost indicator
                        HStack {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("You reposted")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        ProfilePostCard(post: post)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Post Cards

// Using the real PostCard component from PostCard.swift
// All post interactions are handled there with Firebase integration

struct ProfileReplyCard: View {
    let comment: AMENAPP.Comment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Comment info
            HStack(spacing: 8) {
                // Author avatar (inline to avoid compiler issues)
                Group {
                    if let profileImageURL = comment.authorProfileImageURL, 
                       !profileImageURL.isEmpty,
                       let url = URL(string: profileImageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            default:
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(comment.authorInitials)
                                            .font(.custom("OpenSans-Bold", size: 14))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(comment.authorInitials)
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.black)
                    
                    Text(comment.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
            }
            
            // Reply content
            Text(comment.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black.opacity(0.9))
                .lineSpacing(4)
            
            // Replied to post indicator
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                
                Text("Replying to post")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color.secondary)
            }
            
            // Interaction stats
            HStack(spacing: 16) {
                if comment.amenCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "hands.clap")
                            .font(.system(size: 11))
                        Text("\(comment.amenCount)")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(Color.secondary)
                }
                
                if comment.replyCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 11))
                        Text("\(comment.replyCount)")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }
}



// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var profileData: UserProfileData
    @State private var name: String
    @State private var username: String
    @State private var bio: String
    @State private var interests: [String]
    @State private var socialLinks: [SocialLinkUI]
    @State private var showAddInterest = false
    @State private var showAddSocialLink = false
    @State private var showImagePicker = false
    @State private var newInterest = ""
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showUnsavedChangesAlert = false
    @State private var showSaveConfirmationAlert = false
    
    // Track original values to detect changes
    private let originalName: String
    private let originalBio: String
    
    // Character limits
    private let nameCharacterLimit = 50
    private let bioCharacterLimit = 150
    private let interestCharacterLimit = 30
    
    // Validation errors
    @State private var nameError: String? = nil
    @State private var bioError: String? = nil
    
    init(profileData: Binding<UserProfileData>) {
        _profileData = profileData
        _name = State(initialValue: profileData.wrappedValue.name)
        _username = State(initialValue: profileData.wrappedValue.username)
        _bio = State(initialValue: profileData.wrappedValue.bio)
        _interests = State(initialValue: profileData.wrappedValue.interests)
        _socialLinks = State(initialValue: profileData.wrappedValue.socialLinks)
        
        // Store original values
        self.originalName = profileData.wrappedValue.name
        self.originalBio = profileData.wrappedValue.bio
        
        // Validate on init to ensure no errors blocking save
        print("📝 EditProfileView initialized")
        print("   Name: \(profileData.wrappedValue.name)")
        print("   Bio: \(profileData.wrappedValue.bio)")
        print("   Interests: \(profileData.wrappedValue.interests)")
        print("   Social Links: \(profileData.wrappedValue.socialLinks.count)")
    }
    
    // Validate initial values when view appears
    private func validateInitialValues() {
        validateName(name)
        validateBio(bio)
        
        print("🔍 Initial validation complete")
        print("   Name error: \(nameError ?? "none")")
        print("   Bio error: \(bioError ?? "none")")
    }
    
    var body: some View {
        NavigationStack {
            scrollContent
                .background(Color(white: 0.98))
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                .alert("Add Interest", isPresented: $showAddInterest) {
                    TextField("Interest name", text: $newInterest)
                        .autocapitalization(.words)
                    Button("Cancel", role: .cancel) { 
                        newInterest = ""
                    }
                    Button("Add") {
                        addInterest()
                    }
                    .disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
                } message: {
                    Text("Add an interest (3-\(interestCharacterLimit) characters). You can add up to 3 interests.")
                }
                .sheet(isPresented: $showImagePicker) {
                    ProfilePhotoEditView(
                        currentImageURL: profileData.profileImageURL,
                        onPhotoUpdated: { newURL in
                            profileData.profileImageURL = newURL
                            hasChanges = true
                        }
                    )
                }
                .alert("Save Failed", isPresented: $showSaveError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(saveErrorMessage)
                }
                .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Discard Changes", role: .destructive) {
                        dismiss()
                    }
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
                .alert("Confirm Changes", isPresented: $showSaveConfirmationAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Save Changes", role: .none) {
                        saveProfile()
                    }
                } message: {
                    let nameChanged = name != originalName
                    let bioChanged = bio != originalBio
                    
                    var changedFields: [String] = []
                    if nameChanged { changedFields.append("Name") }
                    if bioChanged { changedFields.append("Bio") }
                    
                    return Text("You're about to change your \(changedFields.joined(separator: " and ")). This will be visible to all users. Are you sure?")
                }
                .onAppear {
                    // Validate initial values to ensure no blocking errors
                    validateInitialValues()
                }
        }
    }
    
    // MARK: - Content Views
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                avatarSection
                    .padding(.top, 20)
                
                profileFieldsSection
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                // Check for unsaved changes
                if hasChanges {
                    showUnsavedChangesAlert = true
                } else {
                    dismiss()
                }
            }
            .font(.custom("OpenSans-SemiBold", size: 16))
            .disabled(isSaving)
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                print("🔵 Done button tapped!")
                print("   hasChanges: \(hasChanges)")
                print("   isSaving: \(isSaving)")
                print("   hasValidationErrors: \(hasValidationErrors)")
                print("   nameError: \(nameError ?? "none")")
                print("   bioError: \(bioError ?? "none")")
                
                // Check if name or bio changed - show confirmation
                let nameChanged = name != originalName
                let bioChanged = bio != originalBio
                
                if nameChanged || bioChanged {
                    print("   -> Showing confirmation (name/bio changed)")
                    // Show confirmation alert before saving
                    showSaveConfirmation()
                } else {
                    print("   -> Saving directly (no sensitive changes)")
                    // No sensitive changes, save directly
                    saveProfile()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Done")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(hasChanges && !hasValidationErrors ? .blue : .gray)
                }
            }
            .disabled(isSaving || !hasChanges || hasValidationErrors)
        }
    }
    
    // Check if there are any validation errors
    private var hasValidationErrors: Bool {
        return nameError != nil || bioError != nil
    }
    
    private var profileFieldsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name field with character counter and validation
            nameFieldWithValidation
            
            // Username - Read-only (cannot be changed)
            usernameReadOnlyField
            
            // Bio editor with character counter and validation
            bioEditorWithValidation
            
            interestsSection
            
            socialLinksSection
        }
    }
    
    // MARK: - Name Field with Validation
    
    private var nameFieldWithValidation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Name")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                // Character counter
                Text("\(name.count)/\(nameCharacterLimit)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(name.count > nameCharacterLimit ? .red : .secondary)
            }
            
            TextField("Your name", text: $name)
                .font(.custom("OpenSans-Regular", size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(nameError != nil ? Color.red : Color.black.opacity(0.1), lineWidth: nameError != nil ? 2 : 1)
                )
                .onChange(of: name) { oldValue, newValue in
                    hasChanges = true
                    validateName(newValue)
                }
            
            // Error message
            if let error = nameError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    // MARK: - Username Read-only Field
    
    private var usernameReadOnlyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.black.opacity(0.6))
            
            HStack(spacing: 8) {
                Text("@")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.4))
                
                Text(username)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            
            Text("Username cannot be changed")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Bio Editor with Validation
    
    private var bioEditorWithValidation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bio")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                // Character counter
                Text("\(bio.count)/\(bioCharacterLimit)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(bio.count > bioCharacterLimit ? .red : .secondary)
            }
            
            ZStack(alignment: .topLeading) {
                // Placeholder text
                if bio.isEmpty {
                    Text("Tell us about yourself...")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
                
                TextEditor(text: $bio)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .frame(height: 100)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: bio) { oldValue, newValue in
                        hasChanges = true
                        validateBio(newValue)
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(bioError != nil ? Color.red : Color.black.opacity(0.1), lineWidth: bioError != nil ? 2 : 1)
            )
            
            // Error message
            if let error = bioError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interests (Max 3)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                if interests.count < 3 {
                    Button {
                        showAddInterest = true
                        // Haptic feedback
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.black)
                    }
                }
            }
            
            if interests.isEmpty {
                // Empty state - encourage adding interests
                VStack(alignment: .leading, spacing: 8) {
                    Text("No interests added yet")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text("Add up to 3 interests to help others connect with you")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Display interests as chips with flexible wrapping
                FlexibleInterestsView(interests: interests) { interest in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        interests.removeAll { $0 == interest }
                        hasChanges = true
                    }
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                }
            }
        }
    }
    
    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Social Links")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                Button {
                    showAddSocialLink = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Edit")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                }
            }
            
            if socialLinks.isEmpty {
                Text("No social links added")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(socialLinks) { link in
                        HStack(spacing: 12) {
                            Image(systemName: link.platform.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(link.platform.color)
                                .frame(width: 24)
                            
                            Text(link.username)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.black)
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSocialLink) {
            SocialLinksEditView(socialLinks: $socialLinks)
                .onDisappear {
                    // Check if social links changed
                    if socialLinks != profileData.socialLinks {
                        hasChanges = true
                    }
                }
        }
        .sheet(isPresented: $showImagePicker) {
            ProfileImagePicker(profileData: $profileData)
        }
    }
    
    // MARK: - Avatar Section
    
    private var avatarSection: some View {
        VStack(spacing: 12) {
            avatarWithCameraButton
            
            Button {
                showImagePicker = true
            } label: {
                Text("Change photo")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black)
            }
        }
    }
    
    private var avatarWithCameraButton: some View {
        ZStack(alignment: .bottomTrailing) {
            // Show current profile image or initials
            if let imageURL = profileData.profileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    case .failure, .empty:
                        avatarCircle
                    @unknown default:
                        avatarCircle
                    }
                }
                .frame(width: 100, height: 100)
            } else {
                avatarCircle
            }
            
            cameraButton
        }
    }
    
    private var avatarCircle: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 100, height: 100)
            .overlay(
                Text(profileData.initials)
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(.white)
            )
    }
    
    private var cameraButton: some View {
        Button {
            showImagePicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black))
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
        }
    }
    
    private func saveProfile() {
        // Prevent double-saves
        guard !isSaving else { return }
        
        // Start saving state
        isSaving = true
        
        // Save to Firestore FIRST, then dismiss
        Task { @MainActor in
            do {
                // Use FirebaseManager directly for profile updates
                guard let userId = Auth.auth().currentUser?.uid else {
                    isSaving = false
                    saveErrorMessage = "User not authenticated"
                    showSaveError = true
                    return
                }
                
                print("💾 Saving profile changes to Firestore...")
                print("   Name: \(name)")
                print("   Username: @\(username)")
                print("   Bio: \(bio)")
                print("   Interests: \(interests)")
                print("   Social Links: \(socialLinks.count)")
                
                let db = Firestore.firestore()
                
                // 1. Update basic profile info (displayName and bio)
                try await db.collection("users").document(userId).updateData([
                    "displayName": name,
                    "bio": bio,
                    "interests": interests,  // Include interests in same update
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                print("✅ Basic profile info saved")
                
                // 2. Save social links
                let linkData = socialLinks.map { link in
                    link.toData()
                }
                
                // Convert SocialLinkData to dictionary format
                let linksArray = linkData.map { link -> [String: Any] in
                    return [
                        "platform": link.platform,
                        "username": link.username,
                        "url": link.url
                    ]
                }
                
                try await db.collection("users").document(userId).updateData([
                    "socialLinks": linksArray
                ])
                
                print("✅ Social links saved (\(linksArray.count) links)")
                
                // Update local profile data after successful save
                profileData.name = name
                profileData.username = username
                profileData.bio = bio
                profileData.interests = interests
                profileData.socialLinks = socialLinks
                
                print("✅ Profile saved successfully!")
                
                // Success haptic
                let successHaptic = UINotificationFeedbackGenerator()
                successHaptic.notificationOccurred(.success)
                
                isSaving = false
                
                // Dismiss AFTER successful save
                dismiss()
                
            } catch {
                print("❌ Failed to save profile: \(error.localizedDescription)")
                print("   Error details: \(error)")
                
                isSaving = false
                
                // Show error to user
                await MainActor.run {
                    if let firestoreError = error as NSError?, 
                       firestoreError.domain == "FIRFirestoreErrorDomain" {
                        switch firestoreError.code {
                        case 7: // Permission denied
                            saveErrorMessage = "Permission denied. Please sign out and sign in again."
                        case 14: // Network error
                            saveErrorMessage = "Network error. Please check your connection and try again."
                        default:
                            saveErrorMessage = "Failed to save profile: \(error.localizedDescription)"
                        }
                    } else {
                        saveErrorMessage = "Failed to save profile changes. Please try again.\n\nError: \(error.localizedDescription)"
                    }
                    
                    showSaveError = true
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // MARK: - Validation Functions
    
    /// Validate name field
    private func validateName(_ name: String) {
        // Clear previous error
        nameError = nil
        
        // Check if empty
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            nameError = "Name is required"
            return
        }
        
        // Check length
        if name.count > nameCharacterLimit {
            nameError = "Name must be \(nameCharacterLimit) characters or less"
            return
        }
        
        // Check for invalid characters (must be letters, spaces, hyphens, apostrophes only)
        let allowedCharacterSet = CharacterSet.letters
            .union(CharacterSet.whitespaces)
            .union(CharacterSet(charactersIn: "-'"))
        
        if name.rangeOfCharacter(from: allowedCharacterSet.inverted) != nil {
            nameError = "Name can only contain letters, spaces, hyphens, and apostrophes"
            return
        }
        
        // Check minimum length
        if trimmedName.count < 2 {
            nameError = "Name must be at least 2 characters"
            return
        }
    }
    
    /// Validate bio field
    private func validateBio(_ bio: String) {
        // Clear previous error
        bioError = nil
        
        // Bio is optional, so empty is OK
        if bio.isEmpty {
            return
        }
        
        // Check length
        if bio.count > bioCharacterLimit {
            bioError = "Bio must be \(bioCharacterLimit) characters or less"
            return
        }
        
        // Check for excessive newlines (max 3 line breaks)
        let newlineCount = bio.components(separatedBy: .newlines).count - 1
        if newlineCount > 3 {
            bioError = "Bio can contain a maximum of 3 line breaks"
            return
        }
    }
    
    /// Show confirmation alert for name/bio changes
    private func showSaveConfirmation() {
        showSaveConfirmationAlert = true
    }
    
    /// Add a new interest with validation
    private func addInterest() {
        // Trim whitespace
        let trimmedInterest = newInterest.trimmingCharacters(in: .whitespaces)
        
        // Validate - must not be empty
        guard !trimmedInterest.isEmpty else {
            newInterest = ""
            return
        }
        
        // Validate - max 3 interests
        guard interests.count < 3 else {
            newInterest = ""
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            
            // Show alert
            showErrorAlert(title: "Maximum Interests Reached", message: "You can add a maximum of 3 interests. Remove one to add another.")
            return
        }
        
        // Validate - no duplicates (case-insensitive)
        guard !interests.contains(where: { $0.lowercased() == trimmedInterest.lowercased() }) else {
            // Haptic feedback for duplicate
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            newInterest = ""
            
            showErrorAlert(title: "Duplicate Interest", message: "You've already added this interest.")
            return
        }
        
        // Validate - reasonable length (3-30 characters)
        guard trimmedInterest.count >= 3 else {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            newInterest = ""
            
            showErrorAlert(title: "Interest Too Short", message: "Interest must be at least 3 characters.")
            return
        }
        
        guard trimmedInterest.count <= interestCharacterLimit else {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            newInterest = ""
            
            showErrorAlert(title: "Interest Too Long", message: "Interest must be \(interestCharacterLimit) characters or less.")
            return
        }
        
        // Add interest with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            interests.append(trimmedInterest)
            hasChanges = true
        }
        
        // Success haptic
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Clear input
        newInterest = ""
        
        print("✅ Interest added: \(trimmedInterest)")
    }
    
    /// Show error alert helper
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
}

struct EditFieldView: View {
    let title: String
    @Binding var text: String
    var prefix: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.black.opacity(0.6))
            
            HStack(spacing: 8) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.4))
                }
                
                TextField("", text: $text)
                    .font(.custom("OpenSans-Regular", size: 15))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct InterestChip: View {
    let interest: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(interest)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.black)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.08))
        )
    }
}

// MARK: - Flexible Interests View (with proper wrapping)

struct FlexibleInterestsView: View {
    let interests: [String]
    let onRemove: (String) -> Void
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(interests, id: \.self) { interest in
                InterestChip(interest: interest) {
                    onRemove(interest)
                }
            }
        }
    }
}

// MARK: - Flow Layout (for wrapping chips)
// Note: FlowLayout is defined in OnboardingAdvancedComponents.swift and reused here

// MARK: - Old Components (Keep for compatibility)

struct ProfileSection: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Button {
            // Section action
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - About AMEN View
// NOTE: This view might be defined in AboutAmenView.swift
// Using this implementation in ProfileView.swift

struct AboutAmenView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "hands.sparkles")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    Text("AMEN")
                        .font(.custom("OpenSans-Bold", size: 36))
                    
                    Text("Version 1.0.0 (Build 100)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                // Tagline
                VStack(spacing: 8) {
                    Text("Where Faith Meets Innovation")
                        .font(.custom("OpenSans-SemiBold", size: 18))
                    
                    Text("Your digital companion for spiritual growth, authentic community, and AI-powered Bible study")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Contact Information
                VStack(alignment: .leading, spacing: 16) {
                    AboutInfoRow(
                        icon: "building.2.fill",
                        label: "Developer",
                        value: "AMEN Team",
                        color: .blue
                    )
                    AboutInfoRow(
                        icon: "envelope.fill",
                        label: "Support",
                        value: "support@amenapp.com",
                        color: .green,
                        isEmail: true
                    )
                    AboutInfoRow(
                        icon: "globe",
                        label: "Website",
                        value: "www.amenapp.com",
                        color: .purple,
                        isURL: true
                    )
                    
                    // Privacy Policy
                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.orange)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Privacy Policy")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.secondary)
                                
                                Text("View Policy")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.blue)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Terms of Service
                    Button {
                        showTermsOfService = true
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Color.red)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Terms of Service")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.secondary)
                                
                                Text("View Terms")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.blue)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 30)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Features
                VStack(alignment: .leading, spacing: 16) {
                    Text("Key Features")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .padding(.horizontal, 30)
                    
                    VStack(spacing: 12) {
                        ProfileFeatureRow(icon: "sparkles", title: "Berean AI Assistant", description: "AI-powered Bible study companion")
                        ProfileFeatureRow(icon: "table.furniture", title: "#OPENTABLE", description: "Faith-based idea sharing platform")
                        ProfileFeatureRow(icon: "hands.sparkles", title: "Prayer Network", description: "Share and support prayer requests")
                        ProfileFeatureRow(icon: "person.3", title: "Community", description: "Connect with believers worldwide")
                        ProfileFeatureRow(icon: "book", title: "Daily Devotionals", description: "Start each day with God's Word")
                    }
                    .padding(.horizontal, 30)
                }
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Copyright and Mission
                VStack(spacing: 16) {
                    Text("Our Mission")
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    Text("To empower believers with technology that deepens their faith, strengthens their community, and spreads the Gospel worldwide.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Text("© 2026 AMEN App. All rights reserved.")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    
                    Text("Made with ❤️ for the Body of Christ")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color(white: 0.98))
        .navigationTitle("About AMEN")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showTermsOfService) {
            TermsOfServiceView()
        }
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Last Updated: January 28, 2026")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    PolicySection(
                        title: "1. Information We Collect",
                        content: """
                        We collect information you provide directly to us, including:
                        
                        • Account information (name, email, username)
                        • Profile information (bio, interests, profile photo)
                        • Content you create (posts, comments, prayers)
                        • Messages and communications
                        • Usage data and analytics
                        """
                    )
                    
                    PolicySection(
                        title: "2. How We Use Your Information",
                        content: """
                        We use the information we collect to:
                        
                        • Provide and maintain our services
                        • Improve and personalize your experience
                        • Send you updates and notifications
                        • Ensure safety and security
                        • Analyze usage patterns
                        • Comply with legal obligations
                        """
                    )
                    
                    PolicySection(
                        title: "3. Information Sharing",
                        content: """
                        We do not sell your personal information. We may share information:
                        
                        • With your consent
                        • With service providers who assist us
                        • To comply with legal requirements
                        • To protect rights and safety
                        • In connection with business transfers
                        """
                    )
                    
                    PolicySection(
                        title: "4. Data Security",
                        content: """
                        We implement appropriate security measures to protect your information, including:
                        
                        • Encryption of data in transit and at rest
                        • Regular security audits
                        • Access controls and authentication
                        • Secure cloud infrastructure (Firebase/Google Cloud)
                        """
                    )
                    
                    PolicySection(
                        title: "5. Your Rights",
                        content: """
                        You have the right to:
                        
                        • Access your personal data
                        • Correct inaccurate information
                        • Delete your account and data
                        • Export your data
                        • Opt-out of communications
                        • Object to certain processing
                        """
                    )
                    
                    PolicySection(
                        title: "6. Children's Privacy",
                        content: """
                        AMEN is not intended for children under 13. We do not knowingly collect information from children under 13. If you believe we have collected information from a child, please contact us.
                        """
                    )
                    
                    PolicySection(
                        title: "7. Contact Us",
                        content: """
                        For questions about this Privacy Policy or our data practices, contact us at:
                        
                        Email: privacy@amenapp.com
                        Website: www.amenapp.com/privacy
                        """
                    )
                }
                .padding()
            }
            .background(Color(white: 0.98))
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Last Updated: January 28, 2026")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    PolicySection(
                        title: "1. Acceptance of Terms",
                        content: """
                        By accessing or using AMEN, you agree to be bound by these Terms of Service and all applicable laws and regulations. If you do not agree with any of these terms, you are prohibited from using this service.
                        """
                    )
                    
                    PolicySection(
                        title: "2. User Accounts",
                        content: """
                        To use certain features, you must create an account. You agree to:
                        
                        • Provide accurate and complete information
                        • Maintain the security of your account
                        • Notify us of any unauthorized access
                        • Be responsible for all activity under your account
                        • Not share your account credentials
                        """
                    )
                    
                    PolicySection(
                        title: "3. Community Guidelines",
                        content: """
                        You agree not to:
                        
                        • Post harmful, offensive, or illegal content
                        • Harass, bully, or threaten others
                        • Impersonate others or misrepresent yourself
                        • Spam or engage in misleading practices
                        • Violate others' privacy or intellectual property
                        • Share false or misleading information
                        """
                    )
                    
                    PolicySection(
                        title: "4. Content Ownership",
                        content: """
                        You retain ownership of content you post. By posting content, you grant AMEN a worldwide, non-exclusive, royalty-free license to use, display, and distribute your content in connection with the service.
                        """
                    )
                    
                    PolicySection(
                        title: "5. Prohibited Activities",
                        content: """
                        You may not:
                        
                        • Use the service for illegal purposes
                        • Attempt to gain unauthorized access
                        • Interfere with service operations
                        • Use automated systems without permission
                        • Reverse engineer or copy our technology
                        """
                    )
                    
                    PolicySection(
                        title: "6. Termination",
                        content: """
                        We reserve the right to suspend or terminate your account at any time for violations of these terms. You may also delete your account at any time through the app settings.
                        """
                    )
                    
                    PolicySection(
                        title: "7. Disclaimers",
                        content: """
                        AMEN is provided "as is" without warranties of any kind. We do not guarantee:
                        
                        • Uninterrupted or error-free service
                        • Accuracy of content posted by users
                        • Security of data transmission
                        • Availability of specific features
                        """
                    )
                    
                    PolicySection(
                        title: "8. Limitation of Liability",
                        content: """
                        To the maximum extent permitted by law, AMEN shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the service.
                        """
                    )
                    
                    PolicySection(
                        title: "9. Changes to Terms",
                        content: """
                        We may update these terms from time to time. Continued use of AMEN after changes constitutes acceptance of the new terms. We will notify you of significant changes.
                        """
                    )
                    
                    PolicySection(
                        title: "10. Contact Information",
                        content: """
                        For questions about these Terms of Service, contact us at:
                        
                        Email: legal@amenapp.com
                        Website: www.amenapp.com/terms
                        """
                    )
                }
                .padding()
            }
            .background(Color(white: 0.98))
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
}

// MARK: - Policy Section Component

struct PolicySection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text(content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(6)
        }
    }
}

struct AboutInfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var isEmail: Bool = false
    var isURL: Bool = false
    var isLink: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                
                if isEmail || isURL || isLink {
                    Button {
                        if isEmail {
                            if let url = URL(string: "mailto:\(value)") {
                                UIApplication.shared.open(url)
                            }
                        } else if isURL {
                            if let url = URL(string: "https://\(value)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        Text(value)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.blue)
                    }
                } else {
                    Text(value)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                }
            }
            
            Spacer()
            
            if isEmail || isURL || isLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfileFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Button {
            // Navigate to setting
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.black)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.3))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}



// MARK: - Full Screen Avatar View
// NOTE: This view is defined in FullScreenAvatarView.swift
// The implementation below is commented out to avoid redeclaration errors

/*
struct FullScreenAvatarView: View {
    @Environment(\.dismiss) var dismiss
    let name: String
    let initials: String
    let profileImageURL: String?
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Blurred background
            Color.black
                .ignoresSafeArea()
                .opacity(opacity)
            
            VStack {
                Spacer()
                
                // Avatar
                Group {
                    if let profileImageURL = profileImageURL,
                       !profileImageURL.isEmpty,
                       let url = URL(string: profileImageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 300, height: 300)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                    )
                            default:
                                avatarPlaceholder
                            }
                        }
                    } else {
                        avatarPlaceholder
                    }
                }
                .scaleEffect(scale)
                .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
                
                // Name
                Text(name)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                    .opacity(opacity)
                
                Spacer()
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scale = 0.8
                            opacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(24)
                    }
                }
                Spacer()
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 300, height: 300)
            .overlay(
                Text(initials)
                    .font(.custom("OpenSans-Bold", size: 80))
                    .foregroundStyle(.white)
            )
    }
}
*/

// MARK: - Profile Photo Edit View
// NOTE: This view is defined in a separate file
// The implementation below is commented out to avoid redeclaration errors

/*
struct ProfilePhotoEditView: View {
    @Environment(\.dismiss) var dismiss
    let currentImageURL: String?
    let onPhotoUpdated: (String?) -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current/Selected Photo Preview
                    photoPreview
                        .padding(.top, 20)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Select New Photo
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18, weight: .semibold))
                                Text(currentImageURL != nil ? "Change Photo" : "Select Photo")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                        }
                        .padding(.horizontal)
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    selectedImage = uiImage
                                }
                            }
                        }
                        
                        // Save Button (only show if new image selected)
                        if selectedImage != nil {
                            Button {
                                uploadProfilePhoto()
                            } label: {
                                HStack {
                                    if isUploading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Uploading...")
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Save Photo")
                                    }
                                }
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green)
                                )
                            }
                            .disabled(isUploading)
                            .padding(.horizontal)
                        }
                        
                        // Remove Photo (only if current photo exists)
                        if currentImageURL != nil && selectedImage == nil {
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Remove Photo")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red, lineWidth: 2)
                                )
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    // Tips
                    tipsSection
                        .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Remove Profile Photo?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeProfilePhoto()
                }
            } message: {
                Text("Your profile will show your initials instead.")
            }
        }
    }
    
    private var photoPreview: some View {
        VStack(spacing: 16) {
            if let image = selectedImage {
                // Show newly selected image
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 3)
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("New photo selected")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.blue)
            } else if let currentImageURL = currentImageURL,
                      !currentImageURL.isEmpty,
                      let url = URL(string: currentImageURL) {
                // Show current image
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                    default:
                        placeholderAvatar
                    }
                }
                
                Text("Current photo")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            } else {
                // No photo placeholder
                placeholderAvatar
                
                Text("No photo set")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.black.opacity(0.1))
            .frame(width: 200, height: 200)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.black.opacity(0.3))
            )
    }
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tips for a great profile photo:")
                .font(.custom("OpenSans-Bold", size: 16))
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                TipRow(icon: "face.smiling", text: "Use a clear photo of your face")
                TipRow(icon: "sun.max", text: "Choose good lighting")
                TipRow(icon: "square.and.arrow.up", text: "High quality images work best")
                TipRow(icon: "person.circle", text: "Center yourself in the frame")
            }
            .padding(.horizontal)
        }
    }
    
    private func uploadProfilePhoto() {
        guard let image = selectedImage else { return }
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in"
            return
        }
        
        isUploading = true
        errorMessage = nil
        
        Task {
            do {
                print("📤 Uploading profile photo...")
                
                // Upload to Firebase Storage
                let firebaseManager = FirebaseManager.shared
                let path = "profile_images/\(userId)/profile.jpg"
                let downloadURL = try await firebaseManager.uploadImage(image, to: path, compressionQuality: 0.7)
                
                print("✅ Image uploaded to: \(downloadURL.absoluteString)")
                
                // Update Firestore
                try await firebaseManager.updateDocument([
                    "profileImageURL": downloadURL.absoluteString,
                    "updatedAt": Date()
                ], at: "users/\(userId)")
                
                print("✅ Profile updated with new image URL")
                
                // Update local state
                await MainActor.run {
                    onPhotoUpdated(downloadURL.absoluteString)
                    isUploading = false
                    
                    // Show success feedback
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
    
    private func removeProfilePhoto() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in"
            return
        }
        
        Task {
            do {
                print("🗑️ Removing profile photo...")
                
                // Update Firestore (set to null)
                let firebaseManager = FirebaseManager.shared
                try await firebaseManager.updateDocument([
                    "profileImageURL": NSNull(),
                    "updatedAt": Date()
                ], at: "users/\(userId)")
                
                print("✅ Profile photo removed")
                
                // Update local state
                await MainActor.run {
                    onPhotoUpdated(nil)
                    
                    // Show success feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss
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
}
*/

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Image Picker (Legacy - Keep for compatibility)

import PhotosUI

struct ProfileImagePicker: View {
    @Environment(\.dismiss) var dismiss
    @Binding var profileData: UserProfileData
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = selectedImage {
                    // Show selected image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    // Show current or placeholder
                    Circle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.black.opacity(0.3))
                        )
                }
                
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Select Photo", systemImage: "photo")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black)
                        )
                }
                .padding(.horizontal)
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }
                
                if selectedImage != nil {
                    Button {
                        uploadProfilePhoto()
                    } label: {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Uploading...")
                            } else {
                                Text("Save Photo")
                            }
                        }
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                    }
                    .disabled(isUploading)
                    .padding(.horizontal)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("Select Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func uploadProfilePhoto() {
        guard let image = selectedImage else { return }
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in"
            return
        }
        
        isUploading = true
        errorMessage = nil
        
        Task {
            do {
                print("📤 Uploading profile photo...")
                
                // Upload to Firebase Storage
                let firebaseManager = FirebaseManager.shared
                let path = "profile_images/\(userId).jpg"
                let downloadURL = try await firebaseManager.uploadImage(image, to: path, compressionQuality: 0.7)
                
                print("✅ Image uploaded to: \(downloadURL.absoluteString)")
                
                // Update Firestore
                let db = Firestore.firestore()
                try await db.collection("users").document(userId).updateData([
                    "profileImageURL": downloadURL.absoluteString,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                print("✅ Firestore updated with profile image URL")
                
                // Update local state
                await MainActor.run {
                    profileData.profileImageURL = downloadURL.absoluteString
                    isUploading = false
                    
                    // Show success feedback
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
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                    isUploading = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Data Models

struct UserProfileData {
    var name: String
    var username: String
    var bio: String
    var initials: String
    var profileImageURL: String?
    var interests: [String]
    var socialLinks: [SocialLinkUI]
}



struct ProfileInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.black.opacity(0.6))
            
            Spacer()
            
            Text(value)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appTheme") private var appTheme: String = "auto"
    @AppStorage("fontSize") private var fontSize: String = "medium"
    @AppStorage("reduceMotion") private var reduceMotion: Bool = false
    @AppStorage("highContrast") private var highContrast: Bool = false
    @AppStorage("showProfileBadges") private var showProfileBadges: Bool = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Theme", selection: $appTheme) {
                        Label("Light", systemImage: "sun.max.fill").tag("light")
                        Label("Dark", systemImage: "moon.fill").tag("dark")
                        Label("Auto", systemImage: "circle.lefthalf.filled").tag("auto")
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("COLOR SCHEME")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Choose your preferred color scheme or let the system decide")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Picker("Font Size", selection: $fontSize) {
                        Text("Small").tag("small")
                        Text("Medium").tag("medium")
                        Text("Large").tag("large")
                        Text("Extra Large").tag("xlarge")
                    }
                    .pickerStyle(.segmented)
                    
                    // Preview Text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text("This is how text will appear in the app")
                            .font(previewFont)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("TEXT SIZE")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Adjust the size of text throughout the app")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Toggle(isOn: $reduceMotion) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reduce Motion")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Text("Minimize animations and transitions")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Toggle(isOn: $highContrast) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High Contrast")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Text("Increase contrast for better readability")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                } header: {
                    Text("ACCESSIBILITY")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("These settings improve accessibility for users with visual or motion sensitivities")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Toggle(isOn: $showProfileBadges) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Profile Badges")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Text("Display verification and achievement badges on profiles")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                } header: {
                    Text("DISPLAY")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
    
    private var previewFont: Font {
        switch fontSize {
        case "small":
            return .custom("OpenSans-Regular", size: 13)
        case "large":
            return .custom("OpenSans-Regular", size: 17)
        case "xlarge":
            return .custom("OpenSans-Regular", size: 19)
        default: // medium
            return .custom("OpenSans-Regular", size: 15)
        }
    }
}

// MARK: - Safety & Security View

struct SafetySecurityView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var twoFactorEnabled = false
    @State private var loginAlerts = true
    @State private var showSensitiveContent = false
    @State private var requirePasswordForPurchases = true
    @State private var showTwoFactorSetup = false
    @State private var showLoginHistory = false
    @State private var showPrivacyInfo = false
    @State private var isLoading = true
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    securitySettingsList
                }
            }
            .navigationTitle("Safety & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .sheet(isPresented: $showTwoFactorSetup) {
                TwoFactorSetupView()
            }
            .sheet(isPresented: $showLoginHistory) {
                LoginHistoryView()
            }
            .onAppear {
                loadSecuritySettings()
            }
        }
    }
    
    private var securitySettingsList: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Two-Factor Authentication")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text(twoFactorEnabled ? "Enabled" : "Not enabled")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(twoFactorEnabled ? .green : .secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showTwoFactorSetup = true
                    } label: {
                        Text(twoFactorEnabled ? "Manage" : "Enable")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("AUTHENTICATION")
                    .font(.custom("OpenSans-Bold", size: 12))
            } footer: {
                Text("Add an extra layer of security to your account by requiring a code in addition to your password")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
            
            Section {
                Toggle(isOn: $loginAlerts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Login Alerts")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Get notified when your account is accessed from a new device")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .disabled(isSaving)
                .onChange(of: loginAlerts) { _, newValue in
                    saveSecuritySettings()
                }
                
                Button {
                    showLoginHistory = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Login History")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            Text("View devices where you're logged in")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } header: {
                Text("ACCOUNT ACTIVITY")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            Section {
                Toggle(isOn: $showSensitiveContent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Sensitive Content")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("See content that may be sensitive or mature")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .disabled(isSaving)
                .onChange(of: showSensitiveContent) { _, newValue in
                    saveSecuritySettings()
                }
                
                Toggle(isOn: $requirePasswordForPurchases) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Require Password for Purchases")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Always require your password before making in-app purchases")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .disabled(isSaving)
                .onChange(of: requirePasswordForPurchases) { _, newValue in
                    saveSecuritySettings()
                }
            } header: {
                Text("CONTENT & PURCHASES")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            Section {
                securityTipsView
            } header: {
                Text("SECURITY TIPS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            Section {
                Button {
                    if let url = URL(string: "https://www.amenapp.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Privacy Policy")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button {
                    if let url = URL(string: "https://www.amenapp.com/terms") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("Terms of Service")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } header: {
                Text("LEGAL")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
        }
    }
    
    private func loadSecuritySettings() {
        Task {
            guard let userId = Auth.auth().currentUser?.uid else {
                isLoading = false
                return
            }
            
            let db = Firestore.firestore()
            
            do {
                let doc = try await db.collection("users").document(userId).getDocument()
                
                if let data = doc.data() {
                    await MainActor.run {
                        loginAlerts = data["loginAlerts"] as? Bool ?? true
                        showSensitiveContent = data["showSensitiveContent"] as? Bool ?? false
                        requirePasswordForPurchases = data["requirePasswordForPurchases"] as? Bool ?? true
                        isLoading = false
                        
                        print("✅ Security settings loaded from Firestore")
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                        print("⚠️ No user data found, using defaults")
                    }
                }
            } catch {
                print("❌ Error loading security settings: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private var securityTipsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecurityTipRow(
                icon: "lock.shield.fill",
                title: "Use a Strong Password",
                description: "Combine uppercase, lowercase, numbers, and symbols",
                color: .blue
            )
            
            Divider()
            
            SecurityTipRow(
                icon: "key.fill",
                title: "Enable Two-Factor Authentication",
                description: "Add an extra layer of protection to your account",
                color: .green
            )
            
            Divider()
            
            SecurityTipRow(
                icon: "hand.raised.fill",
                title: "Be Cautious of Phishing",
                description: "Never share your password with anyone",
                color: .orange
            )
            
            Divider()
            
            SecurityTipRow(
                icon: "checkmark.shield.fill",
                title: "Review Login Activity",
                description: "Regularly check where you're logged in",
                color: .purple
            )
        }
        .padding(.vertical, 8)
    }
    
    private func saveSecuritySettings() {
        guard !isSaving else { return }
        
        isSaving = true
        
        Task {
            guard let userId = Auth.auth().currentUser?.uid else {
                await MainActor.run { isSaving = false }
                return
            }
            
            let db = Firestore.firestore()
            
            do {
                try await db.collection("users").document(userId).updateData([
                    "loginAlerts": loginAlerts,
                    "showSensitiveContent": showSensitiveContent,
                    "requirePasswordForPurchases": requirePasswordForPurchases,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                await MainActor.run {
                    isSaving = false
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    print("✅ Security settings saved to Firestore")
                }
            } catch {
                print("❌ Failed to update security settings: \(error)")
                
                await MainActor.run {
                    isSaving = false
                    
                    // Haptic error feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Security Tip Row

struct SecurityTipRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Two-Factor Setup View (Placeholder)

struct TwoFactorSetupView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue)
                        .padding(.top, 40)
                    
                    Text("Two-Factor Authentication")
                        .font(.custom("OpenSans-Bold", size: 24))
                    
                    Text("Add an extra layer of security to your account")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 16) {
                        SetupStepRow(number: 1, title: "Download Authenticator App", description: "Get Google Authenticator, Authy, or similar")
                        SetupStepRow(number: 2, title: "Scan QR Code", description: "Use the app to scan the QR code we'll provide")
                        SetupStepRow(number: 3, title: "Enter Verification Code", description: "Complete setup with the 6-digit code")
                    }
                    .padding()
                    
                    Text("Two-factor authentication setup will be available in a future update")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Enable 2FA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SetupStepRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
    }
}

// MARK: - Login History View

struct LoginHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var loginSessions: [LoginSession] = []
    @State private var isLoading = true
    @State private var showSignOutAllAlert = false
    
    private let loginHistoryService = LoginHistoryService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if loginSessions.isEmpty {
                    emptyHistoryState
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Login History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showSignOutAllAlert = true
                        } label: {
                            Label("Sign Out All Devices", systemImage: "arrow.right.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Sign Out All Devices?", isPresented: $showSignOutAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out All", role: .destructive) {
                    signOutAllDevices()
                }
            } message: {
                Text("This will sign you out from all devices including this one. You'll need to sign in again.")
            }
            .task {
                await loadLoginHistory()
            }
        }
    }
    
    private var sessionsList: some View {
        List {
            Section {
                ForEach(loginSessions) { session in
                    LoginSessionRow(session: session, onRemove: {
                        removeSession(session)
                    })
                }
            } header: {
                Text("Recent Sessions")
            } footer: {
                Text("If you see any unfamiliar activity, sign out all other devices and change your password.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
        }
    }
    
    private var emptyHistoryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No login history")
                .font(.custom("OpenSans-Bold", size: 18))
            
            Text("Your login activity will appear here")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }
    
    private func loadLoginHistory() async {
        do {
            let sessions = try await loginHistoryService.fetchLoginHistory()
            loginSessions = sessions
            isLoading = false
        } catch {
            print("❌ Error loading login history: \(error)")
            isLoading = false
        }
    }
    
    private func removeSession(_ session: LoginSession) {
        Task {
            do {
                try await loginHistoryService.signOutFromSession(sessionId: session.id)
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Error removing session: \(error)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func signOutAllDevices() {
        Task {
            do {
                try await loginHistoryService.signOutAllDevices()
                dismiss()
                
                // This will sign out the user and take them back to sign-in screen
            } catch {
                print("❌ Error signing out all devices: \(error)")
            }
        }
    }
}

// MARK: - Login Session Row

struct LoginSessionRow: View {
    let session: LoginSession
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceIcon)
                .font(.system(size: 24))
                .foregroundStyle(session.isCurrent ? .blue : .secondary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.deviceType)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    
                    if session.isCurrent {
                        Text("• Current")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.blue)
                    }
                }
                
                Text(session.osVersion)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                
                Text(session.formattedTime)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !session.isCurrent {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Text("Remove")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var deviceIcon: String {
        if session.deviceType.contains("iPhone") {
            return "iphone"
        } else if session.deviceType.contains("iPad") {
            return "ipad"
        } else if session.deviceType.contains("Mac") {
            return "laptopcomputer"
        } else {
            return "desktopcomputer"
        }
    }
}

// MARK: - Array Extension for Batching

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    ProfileView()
}



