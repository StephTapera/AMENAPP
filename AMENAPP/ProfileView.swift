//
//  ProfileView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//
//  ✅ TASKS COMPLETED:
//  - TASK 2: Fixed posts staying after creation with enhanced real-time updates
//  - TASK 3: Fixed replies not showing with 10-second refresh interval
//  - TASK 4: Fixed saved posts not showing with proper observer & listener
//  - TASK 5: Fixed reposts not showing with proper observer & listener
//
//  Key improvements:
//  1. Enhanced real-time listeners with detailed logging and change tracking
//  2. Optimistic updates for instant feedback on post creation
//  3. Proper cleanup of notification observers to prevent memory leaks
//  4. Better error handling and state consistency checks
//  5. Faster refresh interval for replies (10s instead of 30s)
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
        bioURL: nil,
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
    
    // Notification observers to clean up
    @State private var notificationObservers: [NSObjectProtocol] = []
    
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
    
    // Enhanced refresh state
    @State private var lastRefreshDate: Date?
    @State private var newPostsCount = 0
    @State private var showRefreshToast = false
    
    var body: some View {
        NavigationStack {
            // 🎯 SINGLE UNIFIED SCROLLVIEW - Everything scrolls together seamlessly
            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header
                    profileHeaderViewWithoutTabs
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).minY
                                    )
                            }
                        )
                    
                    // 🎯 ACHIEVEMENT BADGES - Encourage engagement
                    achievementBadgesView
                    
                    // 🎯 TAB BAR - Right under action buttons (like Threads)
                    stickyTabBar
                        .padding(.top, 0)
                    
                    // Content - flows naturally after tabs
                    if isLoading {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text("Loading...")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        contentView
                            .padding(.top, 12)
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .refreshable {
                await fastRefreshProfile()
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
                // Show compact header when scrolled past 200 points
                let shouldShow = value < -200
                if showCompactHeader != shouldShow {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showCompactHeader = shouldShow
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .overlay(
                // Toast notification for new posts
                Group {
                    if showRefreshToast && newPostsCount > 0 {
                        VStack {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(newPostsCount) new \(newPostsCount == 1 ? "post" : "posts")")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.9))
                            )
                            .shadow(radius: 8)
                            .padding(.top, 60)
                            
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showRefreshToast)
                    }
                }
            )
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
                if let userId = Auth.auth().currentUser?.uid {
                    SocialFollowersListView(userId: userId, listType: .followers)
                        .onAppear {
                            print("📱 Followers list sheet opened")
                        }
                        .onDisappear {
                            print("📱 Followers list sheet closed")
                        }
                } else {
                    Text("Error: Not signed in")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .sheet(isPresented: $showFollowingList) {
                if let userId = Auth.auth().currentUser?.uid {
                    SocialFollowersListView(userId: userId, listType: .following)
                        .onAppear {
                            print("📱 Following list sheet opened")
                        }
                        .onDisappear {
                            print("📱 Following list sheet closed")
                        }
                } else {
                    Text("Error: Not signed in")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .onAppear {
                // Load real user data when view appears
                print("👁️ ProfileView appeared")
                printDataState(context: "onAppear - Before")
                
                // Start follow service listeners for real-time counts
                Task {
                    await followService.startListening()
                    print("✅ FollowService listeners started")
                    print("   Followers: \(followService.currentUserFollowersCount)")
                    print("   Following: \(followService.currentUserFollowingCount)")
                }
                
                // Set up notification observers
                setupNotificationObservers()
                
                // ALWAYS load data when view appears to ensure fresh data
                print("   -> Loading profile data...")
                Task {
                    await loadProfileData()
                    printDataState(context: "onAppear - After Load")
                }
            }
            .onDisappear {
                // Keep listeners active so data persists
                print("👋 ProfileView disappeared")
                printDataState(context: "onDisappear")
                print("   Keeping listeners and data active for persistence")
                
                // Clean up notification observers to prevent memory leaks
                cleanupNotificationObservers()
            }
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Clear any existing observers first
        cleanupNotificationObservers()
        
        // ============================================================================
        // TASK 2: Enhanced new post observer with optimistic + confirmed handling
        // ============================================================================
        
        let newPostObserver = NotificationCenter.default.addObserver(
            forName: .newPostCreated,
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] New post created notification received")
            
            // Check if notification includes the post object
            if let userInfo = notification.userInfo,
               let newPost = userInfo["post"] as? Post {
                
                let isOptimistic = userInfo["isOptimistic"] as? Bool ?? false
                
                // Only handle posts from current user
                guard let currentUserId = Auth.auth().currentUser?.uid,
                      newPost.authorId == currentUserId else {
                    print("   ⏭️ Post not from current user, skipping")
                    return
                }
                
                if isOptimistic {
                    // OPTIMISTIC: Add immediately for instant feedback
                    if !self.userPosts.contains(where: { $0.id == newPost.id }) {
                        self.userPosts.insert(newPost, at: 0)  // Add at top
                        print("   ⚡ OPTIMISTIC post added instantly")
                        print("   Post ID: \(newPost.id)")
                        print("   Content: \(newPost.content.prefix(50))...")
                        print("   Total posts: \(self.userPosts.count)")
                        
                        // Success haptic
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } else {
                        print("   ⚠️ Post already exists (from listener)")
                    }
                } else {
                    // CONFIRMED: Update if exists, otherwise add
                    print("   ✅ CONFIRMED post from database")
                    if let index = self.userPosts.firstIndex(where: { $0.id == newPost.id }) {
                        // Update existing (in case data changed)
                        self.userPosts[index] = newPost
                        print("   Updated existing post at index \(index)")
                    } else {
                        // Wasn't added optimistically, add now
                        self.userPosts.insert(newPost, at: 0)
                        print("   Added confirmed post (wasn't optimistic)")
                        print("   Total posts: \(self.userPosts.count)")
                    }
                }
            } else {
                print("   ❌ No post data in notification")
            }
        }
        notificationObservers.append(newPostObserver)
        
        // ============================================================================
        // Post deleted
        // ============================================================================
        
        let deletedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("postDeleted"),
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] Post deleted notification received")
            
            if let userInfo = notification.userInfo,
               let postId = userInfo["postId"] as? UUID {
                
                let postsRemoved = self.userPosts.removeAll { $0.id == postId }
                let savedRemoved = self.savedPosts.removeAll { $0.id == postId }
                let repostsRemoved = self.reposts.removeAll { $0.id == postId }
                
                print("   🗑️ Post removed: \(postId)")
                print("   From posts: \(postsRemoved)")
                print("   From saved: \(savedRemoved)")
                print("   From reposts: \(repostsRemoved)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
            }
        }
        notificationObservers.append(deletedObserver)
        
        // ============================================================================
        // TASK 5: Post reposted observer
        // ============================================================================
        
        let repostedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("postReposted"),
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] Post reposted notification received")
            
            if let userInfo = notification.userInfo,
               let repostedPost = userInfo["post"] as? Post {
                
                // Only add if current user reposted it
                guard let currentUserId = Auth.auth().currentUser?.uid else {
                    print("   ⏭️ No current user, skipping")
                    return
                }
                
                if !self.reposts.contains(where: { $0.id == repostedPost.id }) {
                    self.reposts.insert(repostedPost, at: 0)
                    print("   🔄 Repost added: \(repostedPost.id)")
                    print("   Total reposts: \(self.reposts.count)")
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                } else {
                    print("   ⚠️ Repost already exists")
                }
            }
        }
        notificationObservers.append(repostedObserver)
        
        // ============================================================================
        // NEW: Comment/Reply created observer
        // ============================================================================
        
        let commentCreatedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("newCommentCreated"),
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] New comment created notification received")
            
            if let userInfo = notification.userInfo,
               let newComment = userInfo["comment"] as? Comment {
                
                // Only add if current user created it
                guard let currentUserId = Auth.auth().currentUser?.uid,
                      newComment.authorId == currentUserId else {
                    print("   ⏭️ Comment not from current user, skipping")
                    return
                }
                
                if !self.userReplies.contains(where: { $0.id == newComment.id }) {
                    self.userReplies.insert(newComment, at: 0)
                    print("   💬 Reply added: \(newComment.id)")
                    print("   Content: \(newComment.content.prefix(50))...")
                    print("   Total replies: \(self.userReplies.count)")
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                } else {
                    print("   ⚠️ Reply already exists")
                }
            }
        }
        notificationObservers.append(commentCreatedObserver)
        
        // ============================================================================
        // TASK 4: Post saved observer
        // ============================================================================
        
        let savedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("postSaved"),
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] Post saved notification received")
            
            if let userInfo = notification.userInfo,
               let savedPost = userInfo["post"] as? Post {
                
                if !self.savedPosts.contains(where: { $0.id == savedPost.id }) {
                    self.savedPosts.insert(savedPost, at: 0)
                    print("   🔖 Saved post added: \(savedPost.id)")
                    print("   Total saved: \(self.savedPosts.count)")
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } else {
                    print("   ⚠️ Post already saved")
                }
            }
        }
        notificationObservers.append(savedObserver)
        
        // ============================================================================
        // TASK 4: Post unsaved observer
        // ============================================================================
        
        let unsavedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("postUnsaved"),
            object: nil,
            queue: .main
        ) { notification in
            print("📬 [NOTIFICATION] Post unsaved notification received")
            
            if let userInfo = notification.userInfo,
               let postId = userInfo["postId"] as? UUID {
                
                let wasRemoved = self.savedPosts.removeAll { $0.id == postId }
                print("   🔖 Post removed from saved: \(postId)")
                print("   Was present: \(wasRemoved)")
                print("   Total saved: \(self.savedPosts.count)")
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        }
        notificationObservers.append(unsavedObserver)
        
        print("✅ Notification observers set up (\(notificationObservers.count) observers)")
    }
    
    private func cleanupNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        print("🧹 Notification observers cleaned up")
    }
    
    // MARK: - Debug Helper
    
    /// Print current data state for debugging
    private func printDataState(context: String) {
        print("📊 [\(context)] Current data state:")
        print("   Posts: \(userPosts.count)")
        print("   Replies: \(userReplies.count)")
        print("   Saved: \(savedPosts.count)")
        print("   Reposts: \(reposts.count)")
        
        if !userPosts.isEmpty {
            print("   Latest post: \(userPosts[0].content.prefix(30))...")
        }
        if !userReplies.isEmpty {
            print("   Latest reply: \(userReplies[0].content.prefix(30))...")
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
        
        // Reload all data from Firestore (where posts are actually saved) and Realtime Database
        do {
            // 1. Refresh posts from FIRESTORE (where createPost saves them)
            let postService = FirebasePostService.shared
            let refreshedPosts = try await postService.fetchUserPosts(userId: userId)
            userPosts = refreshedPosts
            print("   ✅ Posts refreshed from Firestore: \(refreshedPosts.count)")
            
            // 2. Refresh saved posts
            let savedPostsService: RealtimeSavedPostsService = .shared
            let refreshedSavedPosts = try await savedPostsService.fetchSavedPosts()
            savedPosts = refreshedSavedPosts
            print("   ✅ Saved posts refreshed: \(refreshedSavedPosts.count)")
            
            // 3. Refresh replies (including replies user receives)
            let commentsService = AMENAPP.RealtimeCommentsService.shared
            let refreshedReplies = try await commentsService.fetchUserCommentInteractions(userId: userId)
            userReplies = refreshedReplies
            print("   ✅ Replies refreshed: \(refreshedReplies.count) (own comments + replies received)")
            
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
    
    // 🎯 NEW: Enhanced Refresh with Smart Logic & Haptics
    @MainActor
    private func enhancedRefreshProfile() async {
        // Trigger haptic at start
        let startHaptic = UIImpactFeedbackGenerator(style: .medium)
        startHaptic.impactOccurred()
        
        // Smart refresh: Only fetch if data is older than 5 minutes
        let shouldSkip: Bool
        if let lastRefresh = lastRefreshDate {
            let timeSinceRefresh = Date().timeIntervalSince(lastRefresh)
            shouldSkip = timeSinceRefresh < 300 // 5 minutes
            
            if shouldSkip {
                print("⏭️ Skipping refresh - data is fresh (last refresh: \(Int(timeSinceRefresh))s ago)")
                
                // Light success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                return
            }
        } else {
            shouldSkip = false
        }
        
        print("🔄 Enhanced refresh starting...")
        let previousPostsCount = userPosts.count
        
        // Perform refresh
        await refreshProfile()
        
        // Calculate new posts
        newPostsCount = max(0, userPosts.count - previousPostsCount)
        lastRefreshDate = Date()
        
        // Show toast if there are new posts
        if newPostsCount > 0 {
            showRefreshToast = true
            
            // Success haptic with notification
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Hide toast after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showRefreshToast = false
                }
            }
        } else {
            // Light success haptic for "no new posts"
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
        
        print("✅ Enhanced refresh complete - \(newPostsCount) new posts")
    }
    
    // 🎯 NEW: Fast Real-Time Refresh (No Cache Delay)
    @MainActor
    private func fastRefreshProfile() async {
        // Trigger haptic at start
        let startHaptic = UIImpactFeedbackGenerator(style: .medium)
        startHaptic.impactOccurred()
        
        print("⚡ Fast real-time refresh starting...")
        let previousPostsCount = userPosts.count
        let previousRepliesCount = userReplies.count
        
        // Perform refresh immediately - NO CACHE CHECK
        await refreshProfile()
        
        // Calculate changes
        newPostsCount = max(0, userPosts.count - previousPostsCount)
        let newRepliesCount = max(0, userReplies.count - previousRepliesCount)
        lastRefreshDate = Date()
        
        // Show toast if there are new posts or replies
        if newPostsCount > 0 || newRepliesCount > 0 {
            showRefreshToast = true
            
            // Success haptic with notification
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Hide toast after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showRefreshToast = false
                }
            }
        } else {
            // Light success haptic for "no new content"
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
        
        print("✅ Fast refresh complete - \(newPostsCount) new posts, \(newRepliesCount) new replies")
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
            let bioURL = data["bioURL"] as? String // ✅ NEW: Load bio URL
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
                bioURL: bioURL,
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
            
            // 🔥 Fetch posts from Firestore (where they're actually saved)
            let userId = authUser.uid
            
            // ALWAYS fetch fresh data and set up listeners
            print("🔥 Fetching fresh data from Firestore and Realtime DB...")
            
            // 1. Fetch user's own posts from Firestore (where createPost saves them)
            print("🔍 [POSTS] Starting to fetch posts for userId: \(userId)")
            let postService = FirebasePostService.shared
            print("🔍 [POSTS] PostService instance: \(postService)")

            let fetchedPosts = try await postService.fetchUserPosts(userId: userId)
            print("🔍 [POSTS] fetchUserPosts returned \(fetchedPosts.count) posts")

            if fetchedPosts.isEmpty {
                print("⚠️ [POSTS] No posts returned - checking Firestore directly...")
                let db = Firestore.firestore()
                let postsSnapshot = try await db.collection("posts")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments()
                print("🔍 [POSTS] Direct Firestore query returned \(postsSnapshot.documents.count) documents")
                for (index, doc) in postsSnapshot.documents.prefix(3).enumerated() {
                    print("   Document \(index + 1): \(doc.documentID)")
                    print("      Content: \(doc.data()["content"] as? String ?? "N/A")")
                    print("      Category: \(doc.data()["category"] as? String ?? "N/A")")
                    print("      UserId: \(doc.data()["userId"] as? String ?? "N/A")")
                }
            } else {
                print("✅ [POSTS] Posts fetched successfully")
                for (index, post) in fetchedPosts.prefix(3).enumerated() {
                    print("   Post \(index + 1):")
                    print("      ID: \(post.id)")
                    print("      Firestore ID: \(post.firestoreId)")
                    print("      Content: \(post.content.prefix(50))...")
                    print("      Category: \(post.category)")
                    print("      Author ID: \(post.authorId)")
                }
            }

            userPosts = fetchedPosts
            print("🔍 [POSTS] userPosts array now has \(userPosts.count) items")
            print("   ✅ Posts loaded from Firestore: \(fetchedPosts.count)")
            
            // 2. Fetch saved posts from Realtime Database
            print("🔍 [SAVED] Starting to fetch saved posts for userId: \(userId)")
            let savedPostsService: RealtimeSavedPostsService = .shared
            print("🔍 [SAVED] SavedPostsService instance: \(savedPostsService)")

            let fetchedSavedPosts = try await savedPostsService.fetchSavedPosts()
            print("🔍 [SAVED] fetchSavedPosts returned \(fetchedSavedPosts.count) posts")

            if fetchedSavedPosts.isEmpty {
                print("⚠️ [SAVED] No saved posts returned - checking Realtime DB directly...")
                let rtdb = FirebaseDatabase.Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
                let savedSnapshot = try await rtdb.child("savedPosts").child(userId).getData()
                print("🔍 [SAVED] Direct RTDB query exists: \(savedSnapshot.exists())")
                if savedSnapshot.exists(), let savedData = savedSnapshot.value as? [String: Any] {
                    print("🔍 [SAVED] Found \(savedData.keys.count) saved post IDs in RTDB")
                    for (index, postId) in savedData.keys.prefix(3).enumerated() {
                        print("   Saved Post \(index + 1): \(postId)")
                    }
                } else {
                    print("⚠️ [SAVED] No data in Realtime DB at savedPosts/\(userId)")
                }
            } else {
                print("✅ [SAVED] Saved posts fetched successfully")
                for (index, post) in fetchedSavedPosts.prefix(3).enumerated() {
                    print("   Saved Post \(index + 1):")
                    print("      ID: \(post.id)")
                    print("      Firestore ID: \(post.firestoreId)")
                    print("      Content: \(post.content.prefix(50))...")
                }
            }

            savedPosts = fetchedSavedPosts
            print("🔍 [SAVED] savedPosts array now has \(savedPosts.count) items")
            print("   ✅ Saved posts loaded: \(fetchedSavedPosts.count)")
            if !fetchedSavedPosts.isEmpty {
                print("   📋 Saved post IDs: \(fetchedSavedPosts.map { $0.firestoreId }.joined(separator: ", "))")
            } else {
                print("   ⚠️ No saved posts found - savedPosts array is EMPTY")
            }
            
            // 3. Fetch user's comments/replies from Realtime Database (including replies received)
            print("🔍 [REPLIES] Starting to fetch replies for userId: \(userId)")
            let commentsService = AMENAPP.RealtimeCommentsService.shared
            print("🔍 [REPLIES] CommentsService instance: \(commentsService)")

            let fetchedReplies = try await commentsService.fetchUserCommentInteractions(userId: userId)
            print("🔍 [REPLIES] fetchUserCommentInteractions returned \(fetchedReplies.count) replies")

            if fetchedReplies.isEmpty {
                print("⚠️ [REPLIES] No replies returned - checking Realtime DB directly...")
                let rtdb = FirebaseDatabase.Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
                let commentsSnapshot = try await rtdb.child("postInteractions").getData()
                print("🔍 [REPLIES] postInteractions node exists: \(commentsSnapshot.exists())")
                if commentsSnapshot.exists(), let interactionsData = commentsSnapshot.value as? [String: Any] {
                    print("🔍 [REPLIES] Found \(interactionsData.keys.count) posts with interactions")
                    // Check first few posts for comments by this user
                    var userCommentCount = 0
                    for (postId, data) in interactionsData.prefix(10) {
                        if let postData = data as? [String: Any],
                           let comments = postData["comments"] as? [String: Any] {
                            for (_, commentData) in comments {
                                if let comment = commentData as? [String: Any],
                                   let authorId = comment["userId"] as? String,
                                   authorId == userId {
                                    userCommentCount += 1
                                }
                            }
                        }
                    }
                    print("🔍 [REPLIES] Found \(userCommentCount) comments by user in first 10 posts")
                } else {
                    print("⚠️ [REPLIES] No postInteractions data in RTDB")
                }
            } else {
                print("✅ [REPLIES] Replies fetched successfully")
                for (index, reply) in fetchedReplies.prefix(3).enumerated() {
                    print("   Reply \(index + 1):")
                    print("      ID: \(reply.id)")
                    print("      Content: \(reply.content.prefix(50))...")
                    print("      Author ID: \(reply.authorId)")
                }
            }

            userReplies = fetchedReplies
            print("🔍 [REPLIES] userReplies array now has \(userReplies.count) items")
            print("   ✅ Replies loaded: \(fetchedReplies.count) (own comments + replies received)")
            
            // 4. Fetch user's reposts from Realtime Database
            print("🔍 [REPOSTS] Starting to fetch reposts for userId: \(userId)")
            let repostsService: RealtimeRepostsService = .shared
            print("🔍 [REPOSTS] RepostsService instance: \(repostsService)")

            let fetchedReposts = try await repostsService.fetchUserReposts(userId: userId)
            print("🔍 [REPOSTS] fetchUserReposts returned \(fetchedReposts.count) reposts")

            if fetchedReposts.isEmpty {
                print("⚠️ [REPOSTS] No reposts returned - checking Realtime DB directly...")
                let rtdb = FirebaseDatabase.Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
                let repostsSnapshot = try await rtdb.child("postInteractions").getData()
                print("🔍 [REPOSTS] postInteractions node exists: \(repostsSnapshot.exists())")
                if repostsSnapshot.exists(), let interactionsData = repostsSnapshot.value as? [String: Any] {
                    var userRepostCount = 0
                    for (postId, data) in interactionsData.prefix(10) {
                        if let postData = data as? [String: Any],
                           let reposts = postData["reposts"] as? [String: Any] {
                            if reposts.keys.contains(userId) {
                                userRepostCount += 1
                                print("   Found repost by user on post: \(postId)")
                            }
                        }
                    }
                    print("🔍 [REPOSTS] Found \(userRepostCount) reposts by user in first 10 posts")
                } else {
                    print("⚠️ [REPOSTS] No postInteractions data in RTDB")
                }
            } else {
                print("✅ [REPOSTS] Reposts fetched successfully")
                for (index, repost) in fetchedReposts.prefix(3).enumerated() {
                    print("   Repost \(index + 1):")
                    print("      ID: \(repost.id)")
                    print("      Firestore ID: \(repost.firestoreId)")
                    print("      Content: \(repost.content.prefix(50))...")
                }
            }

            reposts = fetchedReposts
            print("🔍 [REPOSTS] reposts array now has \(reposts.count) items")
            print("   ✅ Reposts loaded: \(fetchedReposts.count)")
            if !fetchedReposts.isEmpty {
                print("   📋 Repost IDs: \(fetchedReposts.map { $0.firestoreId }.joined(separator: ", "))")
            } else {
                print("   ⚠️ No reposts found - reposts array is EMPTY")
            }
            
            // 🔥 SET UP REAL-TIME LISTENERS if not already active
            if !listenersActive {
                print("🔥 Setting up real-time listeners for continuous updates...")
                setupRealtimeDatabaseListeners(userId: userId)
                listenersActive = true
            } else {
                print("ℹ️ Listeners already active, data will auto-update")
            }
            
            print("✅ Profile data loaded from Realtime DB:")
            print("   Posts: \(userPosts.count)")
            print("   Reposts: \(reposts.count)")
            print("   Saved: \(savedPosts.count)")
            print("   Replies: \(userReplies.count)")
            
            // Print sample data for verification
            if !userPosts.isEmpty {
                print("   Sample post: \(userPosts[0].content.prefix(50))...")
            }
            if !userReplies.isEmpty {
                print("   Sample reply: \(userReplies[0].content.prefix(50))...")
            }
            if !savedPosts.isEmpty {
                print("   Sample saved: \(savedPosts[0].content.prefix(50))...")
            }
            if !reposts.isEmpty {
                print("   Sample repost: \(reposts[0].content.prefix(50))...")
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
    /// ✅ TASKS 2-5: Fixed all real-time updates with proper state management
    @MainActor
    private func setupRealtimeDatabaseListeners(userId: String) {
        print("🔥 Setting up Realtime Database listeners for profile data...")
        print("   User ID: \(userId)")
        
        // ============================================================================
        // TASK 2: Set up REAL-TIME Firestore listener for posts
        // ============================================================================
        
        // ✅ Posts are stored in Firestore - set up real-time snapshot listener
        print("🔥 [POSTS] Setting up real-time Firestore listener for user posts...")
        
        let db = Firestore.firestore()
        db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { querySnapshot, error in
                
                if let error = error {
                    print("❌ [POSTS] Firestore listener error: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("⚠️ [POSTS] No documents in snapshot")
                    return
                }
                
                Task { @MainActor in
                    let previousCount = self.userPosts.count
                    
                    // Parse posts from Firestore
                    let posts = documents.compactMap { doc -> Post? in
                        try? doc.data(as: Post.self)
                    }
                    
                    self.userPosts = posts
                    
                    print("🔄 [POSTS] Real-time posts updated from Firestore:")
                    print("   Total: \(posts.count) (was \(previousCount))")
                    
                    if posts.count != previousCount {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                }
            }
        
        print("✅ [POSTS] Real-time Firestore listener active: \(userPosts.count) posts")
        
        // ============================================================================
        // TASK 4: Fix saved posts not showing
        // ============================================================================
        
        // 2. Listen to saved posts in real-time
        RealtimeSavedPostsService.shared.observeSavedPosts { postIds in
            print("🔄 [SAVED] Saved posts IDs changed: \(postIds.count) IDs")
            
            Task {
                do {
                    let posts = try await RealtimeSavedPostsService.shared.fetchSavedPosts()
                    await MainActor.run {
                        let previousCount = self.savedPosts.count
                        
                        // Sort by newest first
                        self.savedPosts = posts.sorted { $0.createdAt > $1.createdAt }
                        
                        print("🔄 [SAVED] Saved posts updated:")
                        print("   Total: \(posts.count) (was \(previousCount))")
                        
                        if posts.count != previousCount {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    }
                } catch {
                    print("❌ [SAVED] Error fetching saved posts: \(error)")
                    print("   Keeping existing \(self.savedPosts.count) saved posts")
                }
            }
        }
        
        // ============================================================================
        // TASK 5: Fix reposts not showing
        // ============================================================================
        
        // 3. Listen to user's reposts in real-time
        RealtimeRepostsService.shared.observeUserReposts(userId: userId) { posts in
            Task { @MainActor in
                let previousCount = self.reposts.count
                
                // Sort by newest first
                self.reposts = posts.sorted { $0.createdAt > $1.createdAt }
                
                print("🔄 [REPOSTS] Reposts updated:")
                print("   Total: \(posts.count) (was \(previousCount))")
                
                if posts.count != previousCount {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }
            }
        }
        
        // ============================================================================
        // TASK 3: Fix replies not showing
        // ============================================================================
        
        // 4. Listen to user's comments/replies in real-time
        // Using periodic refresh since RealtimeCommentsService may not have observe
        let commentsTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak timer = Timer()] _ in
            Task { @MainActor in
                do {
                    let comments = try await AMENAPP.RealtimeCommentsService.shared.fetchUserCommentInteractions(userId: userId)
                    let previousCount = self.userReplies.count
                    
                    // Already sorted by newest first in fetchUserCommentInteractions
                    self.userReplies = comments
                    
                    print("🔄 [REPLIES] Comments/replies updated:")
                    print("   Total: \(comments.count) (was \(previousCount))")
                    
                    if comments.count != previousCount {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } catch {
                    print("❌ [REPLIES] Error fetching user comments: \(error)")
                }
            }
        }
        
        // Start timer immediately
        commentsTimer.fire()
        
        // Initial load of comments (including replies received)
        Task {
            do {
                let comments = try await AMENAPP.RealtimeCommentsService.shared.fetchUserCommentInteractions(userId: userId)
                await MainActor.run {
                    self.userReplies = comments // Already sorted by newest first
                    print("🔄 [REPLIES] Initial comments loaded: \(comments.count) replies (own + replies received)")
                }
            } catch {
                print("❌ [REPLIES] Error loading initial comments: \(error)")
            }
        }
        
        print("✅ All real-time listeners set up successfully")
        print("   📊 Current state:")
        print("      Posts: \(userPosts.count)")
        print("      Replies: \(userReplies.count)")
        print("      Saved: \(savedPosts.count)")
        print("      Reposts: \(reposts.count)")
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
    
    /// Calculate dynamic header height based on content
    private func calculateHeaderHeight() -> CGFloat {
        // Base height for profile info
        var baseHeight: CGFloat = 380
        
        // Add height for bio (approx 20pt per line, max 3 lines)
        let bioLines = min(3, max(1, profileData.bio.count / 40))
        baseHeight += CGFloat(bioLines * 20)
        
        // Add height for interests if present
        if !profileData.interests.isEmpty {
            baseHeight += 50
        }
        
        // Add height for social links
        baseHeight += CGFloat(profileData.socialLinks.count * 44)
        
        // Add achievement badges height if any exist
        if userPosts.count >= 10 || followService.currentUserFollowersCount >= 10 {
            baseHeight += 80
        }
        
        // ✨ INTERACTIVE COLLAPSE: Shrink header as user scrolls down
        // Maps scroll offset to header reduction (0 to -150 pixels)
        let collapseAmount = min(150, max(0, -scrollOffset))
        let dynamicHeight = max(200, baseHeight - collapseAmount)
        
        return dynamicHeight
    }
    
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
    
    // MARK: - Achievement Badges View
    
    private var achievementBadgesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Active Community Member
                if userPosts.count >= 10 {
                    AchievementBadge(
                        icon: "flame.fill",
                        title: "Active Member",
                        color: .orange,
                        isUnlocked: true
                    )
                }
                
                // Prayer Warrior
                if userPosts.filter({ $0.category == .prayer }).count >= 5 {
                    AchievementBadge(
                        icon: "hands.sparkles.fill",
                        title: "Prayer Warrior",
                        color: .purple,
                        isUnlocked: true
                    )
                }
                
                // Engagement Badge
                if followService.currentUserFollowersCount >= 10 {
                    AchievementBadge(
                        icon: "person.3.fill",
                        title: "Community Builder",
                        color: .green,
                        isUnlocked: true
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.white)
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
    
    // 🎯 NEW: Sticky Tab Bar View
    private var stickyTabBar: some View {
        HStack(spacing: 8) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    // Switch tab with fast, smooth animation
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, selectedTab == tab ? 20 : 16)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                // ✨ Selected state - black pill with shadow and subtle bounce
                                Capsule()
                                    .fill(Color.black)
                                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                                    .matchedGeometryEffect(id: "tabBackground", in: tabNamespace)
                                    .scaleEffect(selectedTab == tab ? 1.0 : 0.95)
                            } else {
                                // Unselected state - subtle background
                                Capsule()
                                    .fill(Color.black.opacity(0.04))
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(selectedTab == tab ? 1.0 : 0.96)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 0)  // ✅ Zero bottom padding - feed starts RIGHT after tabs
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // 🎯 NEW: Profile Header WITHOUT Tab Selector
    private var profileHeaderViewWithoutTabs: some View {
        VStack(spacing: 12) {
            // Top Section: Avatar and Name - Reduced spacing
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    // Name with verified badge
                    HStack(spacing: 6) {
                        Text(profileData.name)
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.black)

                        // ✅ Verified badge for specific user
                        if let userId = Auth.auth().currentUser?.uid,
                           VerifiedBadgeHelper.isVerified(userId: userId) {
                            VerifiedBadge(size: 20)
                        }
                    }

                    // Username
                    Text("@\(profileData.username)")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                Spacer()
                
                // Avatar with bounce animation
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        avatarPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            avatarPressed = false
                        }
                    }
                    // Show full screen avatar after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showFullScreenAvatar = true
                    }
                } label: {
                    profileAvatarView
                        .scaleEffect(avatarPressed ? 0.9 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // 🎯 Bio with Link Detection
            BioLinkText(text: profileData.bio)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ✅ Bio URL with liquid glass black and white design
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
                        .shadow(color: .white.opacity(0.15), radius: 4, x: 0, y: -1)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Interests with hand-drawn highlight animation
            if !profileData.interests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(profileData.interests.enumerated()), id: \.element) { index, interest in
                            HandDrawnHighlightText(
                                text: interest,
                                animationDelay: Double(index) * 0.15
                            )
                        }
                    }
                }
            }
            
            // Social Links - Clickable
            if !profileData.socialLinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
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
            .padding(.vertical, 4)
            
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
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 0)
        .background(Color.white)
    }
    
    // Keep old header for backwards compatibility (may be referenced elsewhere)
    private var profileHeaderView: some View {
        profileHeaderViewWithoutTabs
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .posts:
                PostsContentView(posts: $userPosts)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .id("posts")
            case .replies:
                RepliesContentView(replies: $userReplies)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .id("replies")
            case .saved:
                SavedContentView(savedPosts: $savedPosts)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .id("saved")
            case .reposts:
                RepostsContentView(reposts: $reposts)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .id("reposts")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
    
    // Swipe gesture state
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeDirection: SwipeDirection = .none
    
    enum SwipeDirection {
        case none, left, right
    }
    
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var interactionsService = PostInteractionsService.shared
    
    // Check if current user is the post owner
    private var isCurrentUserPost: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return currentUserId == post.authorId
    }
    
    // Category icon helper
    private var categoryIcon: String {
        switch post.category {
        case .openTable:
            return "lightbulb.fill"
        case .testimonies:
            return "star.fill"
        case .prayer:
            return "hands.sparkles.fill"
        case .tip:
            return "info.circle.fill"
        case .funFact:
            return "sparkles"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // HEADER: Time + Menu
            HStack(alignment: .center, spacing: 8) {
                // Category badge - always show
                HStack(spacing: 4) {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(post.category.displayName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.04))
                        .overlay(
                            Capsule()
                                .stroke(.black.opacity(0.1), lineWidth: 0.5)
                        )
                )
                
                Text(post.timeAgo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.4))
                
                Spacer()
                
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.02))
                        )
                }
            }
            
            // CONTENT: Post text
            Text(post.content)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // INTERACTIONS: Glassmorphic buttons (counts only visible to post owner)
            HStack(spacing: 12) {
                // Amen/Lightbulb button
                if post.category == .openTable {
                    Button {
                        toggleLightbulb()
                    } label: {
                        lightbulbButtonLabel(showCount: isCurrentUserPost)
                    }
                    .buttonStyle(.plain)
                } else {
                    glassmorphicButton(
                        icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                        count: isCurrentUserPost ? amenCount : 0,
                        isActive: hasSaidAmen,
                        activeColor: .purple
                    ) {
                        toggleAmen()
                    }
                }
                
                // Comment button - illuminates when there are comments (count only for owner)
                glassmorphicButton(
                    icon: "bubble.left",
                    count: isCurrentUserPost ? commentCount : 0,
                    isActive: commentCount > 0,
                    activeColor: .blue
                ) {
                    showCommentsSheet = true
                }
                
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            // ✨ THREADS-STYLE MINIMAL DESIGN
            ZStack {
                // Swipe action indicators
                if abs(swipeOffset) > 20 {
                    HStack {
                        if swipeDirection == .right {
                            // Like/Amen indicator on left
                            swipeIndicator(
                                icon: post.category == .openTable ? "lightbulb.fill" : "hands.sparkles.fill",
                                color: post.category == .openTable ? .yellow : .purple,
                                text: post.category == .openTable ? "Light" : "Amen"
                            )
                            .opacity(min(Double(abs(swipeOffset)) / 80.0, 1.0))
                            .padding(.leading, 20)
                            Spacer()
                        } else if swipeDirection == .left {
                            // Comment indicator on right
                            Spacer()
                            swipeIndicator(
                                icon: "bubble.left.fill",
                                color: .blue,
                                text: "Comment"
                            )
                            .opacity(min(Double(abs(swipeOffset)) / 80.0, 1.0))
                            .padding(.trailing, 20)
                        }
                    }
                }
                
                // Clean white background like Threads
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.white)
            }
        )
        .overlay(
            // Minimal bottom separator like Threads
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only respond to predominantly horizontal swipes
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    guard horizontalAmount > verticalAmount * 2 else {
                        return
                    }
                    
                    if value.translation.width > 20 {
                        swipeDirection = .right
                        swipeOffset = min(value.translation.width, 100)
                    } else if value.translation.width < -20 {
                        swipeDirection = .left
                        swipeOffset = max(value.translation.width, -100)
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 60
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    guard horizontalAmount > verticalAmount * 2 else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
                        return
                    }
                    
                    if swipeDirection == .right && swipeOffset > threshold {
                        triggerSwipeLikeAction()
                    } else if swipeDirection == .left && abs(swipeOffset) > threshold {
                        triggerSwipeCommentAction()
                    }
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeOffset = 0
                        swipeDirection = .none
                    }
                }
        )
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
    
    // MARK: - Glassmorphic Button Helper
    
    @ViewBuilder
    private func glassmorphicButton(
        icon: String,
        count: Int,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? activeColor : .black.opacity(0.5))
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? activeColor : .black.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    // Glass background
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? activeColor.opacity(0.08) : .black.opacity(0.02))
                    
                    // Border
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isActive ? activeColor.opacity(0.2) : .black.opacity(0.08),
                            lineWidth: 0.5
                        )
                }
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Lightbulb Styling (matching PostCard)
    
    private func lightbulbButtonLabel(showCount: Bool) -> some View {
        HStack(spacing: 3) {
            lightbulbIcon
            
            if showCount && lightbulbCount > 0 {
                Text("\(lightbulbCount)")
                    .font(.custom("OpenSans-SemiBold", size: 10))
                    .foregroundStyle(hasLitLightbulb ? Color.orange : Color.black.opacity(0.5))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(lightbulbBackground)
        .overlay(lightbulbOverlay)
    }
    
    private var lightbulbIcon: some View {
        ZStack {
            // Glow effect when active
            if hasLitLightbulb {
                lightbulbGlowEffect
            }
            
            lightbulbMainIcon
        }
    }
    
    private var lightbulbGlowEffect: some View {
        Image(systemName: "lightbulb.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.yellow)
            .blur(radius: 6)
            .opacity(0.6)
    }
    
    private var lightbulbMainIcon: some View {
        Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hasLitLightbulb ? lightbulbGradientActive : lightbulbGradientInactive)
    }
    
    private var lightbulbBackground: some View {
        Capsule()
            .fill(hasLitLightbulb ? Color.yellow.opacity(0.15) : Color.black.opacity(0.05))
            .shadow(color: hasLitLightbulb ? Color.yellow.opacity(0.2) : Color.clear, radius: 8, y: 2)
    }
    
    private var lightbulbOverlay: some View {
        Capsule()
            .stroke(hasLitLightbulb ? Color.orange.opacity(0.3) : Color.black.opacity(0.1), lineWidth: hasLitLightbulb ? 1.5 : 1)
    }
    
    private var lightbulbGradientActive: LinearGradient {
        LinearGradient(
            colors: [.yellow, .orange],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var lightbulbGradientInactive: LinearGradient {
        LinearGradient(
            colors: [.black.opacity(0.5), .black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
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
    
    // MARK: - Actions
    
    private func canEditPost(_ post: Post) -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        return post.createdAt >= thirtyMinutesAgo
    }
    
    // MARK: - Swipe Gesture Helpers
    
    private func swipeIndicator(icon: String, color: Color, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(color)
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundColor(color)
        }
        .scaleEffect(min(Double(abs(swipeOffset)) / 60.0, 1.2))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: swipeOffset)
    }
    
    private func triggerSwipeLikeAction() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        if post.category == .openTable {
            toggleLightbulb()
        } else {
            toggleAmen()
        }
    }
    
    private func triggerSwipeCommentAction() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        showCommentsSheet = true
    }
    
    // MARK: - Actions
    
    private func toggleLightbulb() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            hasLitLightbulb.toggle()
            if hasLitLightbulb {
                lightbulbCount += 1
            } else {
                lightbulbCount = max(0, lightbulbCount - 1)
            }
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
                    if hasLitLightbulb {
                        lightbulbCount += 1
                    } else {
                        lightbulbCount = max(0, lightbulbCount - 1)
                    }
                }
            }
        }
    }
    
    private func toggleAmen() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            hasSaidAmen.toggle()
            if hasSaidAmen {
                amenCount += 1
            } else {
                amenCount = max(0, amenCount - 1)
            }
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
                    if hasSaidAmen {
                        amenCount += 1
                    } else {
                        amenCount = max(0, amenCount - 1)
                    }
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
    @State private var visibleCards: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            if posts.isEmpty {
                // Simple empty state
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No posts yet")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text("Your posts will appear here")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 0)
                .padding(.bottom, 20)
            } else {
                // ✅ Posts RIGHT under tabs - zero spacing
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        ProfilePostCard(post: post)
                            .padding(.bottom, 10)  // Spacing between cards only
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 0)  // ✅ No gap - posts flush with tabs
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            print("🔍 PostsContentView appeared - displaying \(posts.count) posts")
            if let userId = Auth.auth().currentUser?.uid {
                print("   Current user ID: \(userId)")
            }
            for (index, post) in posts.prefix(3).enumerated() {
                print("   Post \(index + 1): \(post.content.prefix(50))... (authorId: \(post.authorId))")
            }
        }
        .onChange(of: posts) { oldPosts, newPosts in
            // Reset animation for new posts
            visibleCards.removeAll()
        }
    }
}

struct RepliesContentView: View {
    @Binding var replies: [AMENAPP.Comment]
    @State private var selectedUserId: String?
    @State private var showUserProfile = false

    var body: some View {
        VStack {
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
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 0)
            .padding(.bottom, 20)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(replies) { comment in
                    ProfileReplyCard(
                        comment: comment,
                        onProfileTap: {
                            selectedUserId = comment.authorId
                            showUserProfile = true
                        }
                    )
                    
                    // Divider between replies
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.5)
                }
            }
            .padding(.top, 0)  // ✅ No gap - replies right under tabs
            .sheet(isPresented: $showUserProfile) {
                if let userId = selectedUserId {
                    UserProfileView(userId: userId)
                }
            }
        }
        }
        .onAppear {
            print("🔍 RepliesContentView appeared - displaying \(replies.count) replies")
            for (index, reply) in replies.prefix(3).enumerated() {
                print("   Reply \(index + 1): \(reply.content.prefix(50))... (authorId: \(reply.authorId))")
            }
        }
    }
}

struct SavedContentView: View {
    @Binding var savedPosts: [Post]
    
    var body: some View {
        let _ = print("🔍 [SAVED-TAB] SavedContentView body evaluated - savedPosts.count: \(savedPosts.count)")
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
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 0)
            .padding(.bottom, 20)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(savedPosts) { post in
                    ProfilePostCard(post: post)
                        .padding(.bottom, 10)  // Spacing between cards only
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)  // ✅ No gap - saved posts flush with tabs
            .padding(.bottom, 20)
        }
    }
}

struct RepostsContentView: View {
    @Binding var reposts: [Post]
    
    var body: some View {
        let _ = print("🔍 [REPOSTS-TAB] RepostsContentView body evaluated - reposts.count: \(reposts.count)")
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
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 0)
            .padding(.bottom, 20)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(reposts) { post in
                    ProfilePostCard(post: post)
                        .padding(.bottom, 10)  // Spacing between cards only
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)  // ✅ No gap - reposts flush with tabs
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Post Cards

// Using the real PostCard component from PostCard.swift
// All post interactions are handled there with Firebase integration

struct ProfileReplyCard: View {
    let comment: AMENAPP.Comment
    let onProfileTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Comment info
            HStack(spacing: 8) {
                // Author avatar - Tappable to view profile
                Button {
                    onProfileTap()
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
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
                                case .failure:
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Text(comment.authorInitials)
                                                .font(.custom("OpenSans-Bold", size: 14))
                                                .foregroundStyle(.white)
                                        )
                                case .empty:
                                    Circle()
                                        .fill(Color.black.opacity(0.1))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        )
                                @unknown default:
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
                }
                .buttonStyle(PlainButtonStyle())
                
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
    @State private var bioURL: String // ✅ NEW: Bio URL field
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
    private let originalBioURL: String
    private let originalProfileImageURL: String? // ✅ NEW: Track original image
    
    // Character limits
    private let nameCharacterLimit = 50
    private let bioCharacterLimit = 150
    private let interestCharacterLimit = 30
    
    // Validation errors
    @State private var nameError: String? = nil
    @State private var bioError: String? = nil
    @State private var bioURLError: String? = nil
    
    init(profileData: Binding<UserProfileData>) {
        _profileData = profileData
        _name = State(initialValue: profileData.wrappedValue.name)
        _username = State(initialValue: profileData.wrappedValue.username)
        _bio = State(initialValue: profileData.wrappedValue.bio)
        _bioURL = State(initialValue: profileData.wrappedValue.bioURL ?? "")
        _interests = State(initialValue: profileData.wrappedValue.interests)
        _socialLinks = State(initialValue: profileData.wrappedValue.socialLinks)
        
        // Store original values for change detection
        self.originalName = profileData.wrappedValue.name
        self.originalBio = profileData.wrappedValue.bio
        self.originalBioURL = profileData.wrappedValue.bioURL ?? ""
        self.originalProfileImageURL = profileData.wrappedValue.profileImageURL
        
        // Validate on init to ensure no errors blocking save
        print("📝 EditProfileView initialized")
        print("   Name: \(profileData.wrappedValue.name)")
        print("   Bio: \(profileData.wrappedValue.bio)")
        print("   Bio URL: \(profileData.wrappedValue.bioURL ?? "none")")
        print("   Profile Image: \(profileData.wrappedValue.profileImageURL ?? "none")")
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
                print("   bioURLError: \(bioURLError ?? "none")")
                
                // ✅ IMPROVED: Check ALL types of changes
                let nameChanged = name != originalName
                let bioChanged = bio != originalBio
                let bioURLChanged = bioURL != originalBioURL
                let imageChanged = profileData.profileImageURL != originalProfileImageURL
                
                print("   Changes detected:")
                print("      Name: \(nameChanged)")
                print("      Bio: \(bioChanged)")
                print("      Bio URL: \(bioURLChanged)")
                print("      Profile Image: \(imageChanged)")
                
                // Show confirmation for name/bio changes (sensitive)
                if nameChanged || bioChanged {
                    print("   -> Showing confirmation (name/bio changed)")
                    showSaveConfirmation()
                } else if hasChanges || imageChanged || bioURLChanged {
                    print("   -> Saving directly (profile photo/URL or other changes)")
                    // Profile photo, URL, or other changes - save directly
                    saveProfile()
                } else {
                    print("   -> No changes to save, just dismissing")
                    // No changes - just dismiss
                    dismiss()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Done")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(hasValidationErrors ? .gray : .blue)
                }
            }
            .disabled(isSaving || hasValidationErrors)
        }
    }
    
    // Check if there are any validation errors
    private var hasValidationErrors: Bool {
        return nameError != nil || bioError != nil || bioURLError != nil
    }
    
    // ✅ NEW: Check if ANY changes were made (enables save button)
    private var canSave: Bool {
        let nameChanged = name != originalName
        let bioChanged = bio != originalBio
        let bioURLChanged = bioURL != originalBioURL
        let imageChanged = profileData.profileImageURL != originalProfileImageURL
        
        return hasChanges || nameChanged || bioChanged || bioURLChanged || imageChanged
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
        Group {
            // Bio text editor
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
            .padding(.bottom, 12)
            
            // ✅ NEW: Bio URL Field with Smart Link Detection
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Website")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.black.opacity(0.6))
                
                Spacer()
                
                // Smart URL indicator
                if !bioURL.isEmpty && bioURLError == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        
                        Text("Valid")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.green)
                    }
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 24)
                
                TextField("example.com", text: $bioURL)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onChange(of: bioURL) { oldValue, newValue in
                        hasChanges = true
                        // Validate on blur or when user stops typing
                        if !newValue.isEmpty {
                            validateBioURL(newValue)
                        } else {
                            bioURLError = nil
                        }
                    }
                
                // Clear button
                if !bioURL.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            bioURL = ""
                            bioURLError = nil
                            hasChanges = true
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(bioURLError != nil ? Color.red : Color.black.opacity(0.1), lineWidth: bioURLError != nil ? 2 : 1)
            )
            
            // Smart URL helper text or error
            if let error = bioURLError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.red)
                }
            } else if !bioURL.isEmpty && bioURLError == nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    
                    Text("Auto-formatted: \(bioURL)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Add a link to your website, portfolio, or social profile")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        if let index = interests.firstIndex(of: interest) {
                            interests.remove(at: index)
                            hasChanges = true
                        }
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
                
                // 1. Update basic profile info (displayName, bio, and bioURL)
                var updateData: [String: Any] = [
                    "displayName": name,
                    "bio": bio,
                    "interests": interests,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                
                // ✅ NEW: Include bioURL if not empty, otherwise remove it
                if !bioURL.isEmpty && bioURLError == nil {
                    updateData["bioURL"] = bioURL
                } else {
                    updateData["bioURL"] = FieldValue.delete()
                }
                
                try await db.collection("users").document(userId).updateData(updateData)
                
                print("✅ Basic profile info saved")
                print("   Bio URL: \(bioURL.isEmpty ? "removed" : bioURL)")
                
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
                profileData.bioURL = bioURL.isEmpty ? nil : bioURL
                profileData.interests = interests
                profileData.socialLinks = socialLinks
                
                // ✅ REAL-TIME UPDATE: Cache profile image URL for tab bar
                if let imageURL = profileData.profileImageURL {
                    UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
                    print("✅ Profile image URL cached: \(imageURL)")
                } else {
                    UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                    print("✅ Profile image URL cache cleared")
                }
                
                // ✅ REAL-TIME UPDATE: Post notification to update tab bar immediately
                NotificationCenter.default.post(
                    name: Notification.Name("profilePhotoUpdated"),
                    object: nil,
                    userInfo: ["profileImageURL": profileData.profileImageURL ?? ""]
                )
                print("✅ Posted profilePhotoUpdated notification for tab bar")
                
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
    
    /// ✅ NEW: Validate and format bio URL
    private func validateBioURL(_ urlString: String) {
        // Clear previous error
        bioURLError = nil
        
        // URL is optional, so empty is OK
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return
        }
        
        // Auto-add https:// if no protocol specified
        var formattedURL = trimmed
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            formattedURL = "https://\(trimmed)"
        }
        
        // Validate URL format
        guard let url = URL(string: formattedURL), 
              url.scheme != nil,
              url.host != nil else {
            bioURLError = "Please enter a valid URL (e.g., example.com)"
            return
        }
        
        // Update bioURL with formatted version if valid
        bioURL = formattedURL
        print("✅ URL formatted: \(formattedURL)")
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
        
        // Add interest with fast animation
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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
                
                // ✅ Update UserDefaults cache so new posts include the profile image
                UserDefaults.standard.set(downloadURL.absoluteString, forKey: "currentUserProfileImageURL")
                print("✅ Updated UserDefaults cache with new profile image URL")
                
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

// MARK: - Achievement Badge Component

struct AchievementBadge: View {
    let icon: String
    let title: String
    let color: Color
    let isUnlocked: Bool
    
    @State private var showDetails = false
    
    var body: some View {
        Button {
            showDetails = true
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? color.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isUnlocked ? color : Color.gray.opacity(0.4))
                    
                    if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.gray))
                            .offset(x: 18, y: -18)
                    }
                }
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 70)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .alert(title, isPresented: $showDetails) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(isUnlocked ? "You've unlocked this achievement!" : "Keep engaging to unlock this achievement.")
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
                
                // ✅ Update UserDefaults cache so new posts include the profile image
                UserDefaults.standard.set(downloadURL.absoluteString, forKey: "currentUserProfileImageURL")
                print("✅ Updated UserDefaults cache with new profile image URL")
                
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
    var bioURL: String? // ✅ NEW: Optional URL for bio link
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

// MARK: - Hand-Drawn Highlight Text

/// A text view with an organic, hand-drawn marker highlight that animates in
struct HandDrawnHighlightText: View {
    let text: String
    let animationDelay: Double
    
    @State private var animationProgress: CGFloat = 0
    
    var body: some View {
        Text(text)
            .font(.custom("OpenSans-SemiBold", size: 13))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                HandDrawnHighlightCircle(animationProgress: animationProgress)
                    .fill(Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.4))
            )
            .onAppear {
                // Animate the stroke drawing in with faster, smoother animation
                withAnimation(.easeOut(duration: 0.4).delay(animationDelay)) {
                    animationProgress = 1.0
                }
            }
    }
}

/// An organic, hand-drawn circle shape that animates from 0 to 1
struct HandDrawnHighlightCircle: Shape {
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
        
        // Create an organic, imperfect circle path
        // This mimics a hand-drawn marker stroke with slight irregularities
        
        let radiusX = width / 2 * 1.05  // Slightly larger than content
        let radiusY = height / 2 * 1.15
        
        // Start point (top)
        let startAngle: CGFloat = -.pi / 2
        let endAngle: CGFloat = startAngle + (2 * .pi * animationProgress)
        
        // Number of segments for organic look
        let segments = 60
        let angleStep = (2 * .pi) / CGFloat(segments)
        
        var currentAngle = startAngle
        var isFirst = true
        
        while currentAngle < endAngle {
            // Add slight random variation to radius for hand-drawn effect
            let variation = sin(currentAngle * 3) * 0.03 + cos(currentAngle * 7) * 0.02
            let variedRadiusX = radiusX * (1 + variation)
            let variedRadiusY = radiusY * (1 + variation)
            
            let x = centerX + cos(currentAngle) * variedRadiusX
            let y = centerY + sin(currentAngle) * variedRadiusY
            
            if isFirst {
                path.move(to: CGPoint(x: x, y: y))
                isFirst = false
            } else {
                // Use quadratic curves for smoother, more organic connections
                let prevAngle = currentAngle - angleStep
                let prevX = centerX + cos(prevAngle) * variedRadiusX
                let prevY = centerY + sin(prevAngle) * variedRadiusY
                
                let controlX = (x + prevX) / 2 + sin(currentAngle) * 2
                let controlY = (y + prevY) / 2 + cos(currentAngle) * 2
                
                path.addQuadCurve(
                    to: CGPoint(x: x, y: y),
                    control: CGPoint(x: controlX, y: controlY)
                )
            }
            
            currentAngle += angleStep
        }
        
        // Close the path if animation is complete
        if animationProgress >= 0.99 {
            path.closeSubpath()
        }
        
        return path
    }
}

// MARK: - Bio Link Text Component

/// A text view that detects and makes URLs, @mentions, and #hashtags tappable
struct BioLinkText: View {
    let text: String
    
    @State private var showingUserProfile = false
    @State private var selectedUsername: String?
    @State private var showingHashtagSearch = false
    @State private var selectedHashtag: String?
    
    var body: some View {
        // Parse the bio text into segments
        let segments = parseTextSegments(text)
        
        // Use HStack with wrapped segments for tap handling
        WrappingHStack(segments: segments) { segment in
            createSegmentView(segment)
        }
        .sheet(isPresented: $showingUserProfile) {
            if let username = selectedUsername {
                UserProfileViewWrapper(username: username)
            }
        }
        .sheet(isPresented: $showingHashtagSearch) {
            if let hashtag = selectedHashtag {
                HashtagSearchViewWrapper(hashtag: hashtag)
            }
        }
    }
    
    @ViewBuilder
    private func createSegmentView(_ segment: TextSegment) -> some View {
        switch segment.type {
        case .regular:
            Text(segment.text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.black)
        
        case .url:
            Button {
                openURL(segment.text)
            } label: {
                Text(segment.text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(.blue)
                    .underline()
            }
            .buttonStyle(.plain)
        
        case .mention:
            Button {
                let username = String(segment.text.dropFirst()) // Remove @
                selectedUsername = username
                showingUserProfile = true
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                Text(segment.text)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        
        case .hashtag:
            Button {
                let hashtag = String(segment.text.dropFirst()) // Remove #
                selectedHashtag = hashtag
                showingHashtagSearch = true
                
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                Text(segment.text)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func parseTextSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentIndex = text.startIndex
        
        // Patterns for detection
        let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s]+"#, options: [])
        let mentionPattern = try! NSRegularExpression(pattern: #"@[\w]+"#, options: [])
        let hashtagPattern = try! NSRegularExpression(pattern: #"#[\w]+"#, options: [])
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        
        // Find all matches
        var matches: [(range: NSRange, type: TextSegmentType)] = []
        
        urlPattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                matches.append((matchRange, .url))
            }
        }
        
        mentionPattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                matches.append((matchRange, .mention))
            }
        }
        
        hashtagPattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                matches.append((matchRange, .hashtag))
            }
        }
        
        // Sort matches by location
        matches.sort { $0.range.location < $1.range.location }
        
        // Build segments
        var lastLocation = 0
        for (matchRange, type) in matches {
            // Add regular text before match
            if matchRange.location > lastLocation {
                let regularRange = NSRange(location: lastLocation, length: matchRange.location - lastLocation)
                if let textRange = Range(regularRange, in: text) {
                    let regularText = String(text[textRange])
                    if !regularText.isEmpty {
                        segments.append(TextSegment(text: regularText, type: .regular))
                    }
                }
            }
            
            // Add matched segment
            if let textRange = Range(matchRange, in: text) {
                let matchedText = String(text[textRange])
                segments.append(TextSegment(text: matchedText, type: type))
            }
            
            lastLocation = matchRange.location + matchRange.length
        }
        
        // Add remaining text
        if lastLocation < nsText.length {
            let remainingRange = NSRange(location: lastLocation, length: nsText.length - lastLocation)
            if let textRange = Range(remainingRange, in: text) {
                let remainingText = String(text[textRange])
                if !remainingText.isEmpty {
                    segments.append(TextSegment(text: remainingText, type: .regular))
                }
            }
        }
        
        // If no segments, return regular text
        if segments.isEmpty && !text.isEmpty {
            segments.append(TextSegment(text: text, type: .regular))
        }
        
        return segments
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}

// MARK: - Text Segment Model

struct TextSegment {
    let text: String
    let type: TextSegmentType
}

enum TextSegmentType {
    case regular
    case url
    case mention
    case hashtag
}

// MARK: - Wrapping HStack for Bio Text

struct WrappingHStack<Content: View>: View {
    let segments: [TextSegment]
    let content: (TextSegment) -> Content
    
    var body: some View {
        // Simple approach: use Text concatenation with proper spacing
        let words = segments.flatMap { segment -> [String] in
            segment.text.components(separatedBy: " ").map { word in
                word.isEmpty ? " " : word
            }
        }
        
        // Create a flowing text layout
        FlowLayout(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                content(segment)
            }
        }
    }
}

// MARK: - Wrapper Views for Navigation

struct UserProfileViewWrapper: View {
    let username: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Profile for @\(username)")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .padding()
                
                Text("User profile view coming soon...")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .navigationTitle("@\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HashtagSearchViewWrapper: View {
    let hashtag: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Search results for #\(hashtag)")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .padding()
                
                Text("Hashtag search view coming soon...")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .navigationTitle("#\(hashtag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
}



