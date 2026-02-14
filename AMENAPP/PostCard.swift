//
//  PostCard.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Enhanced PostCard with edit/delete functionality and repost tracking
//

import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

struct PostCard: View {
    let post: Post?
    let authorName: String
    let timeAgo: String
    let content: String
    let category: PostCardCategory
    let topicTag: String?
    let isUserPost: Bool // Track if this is the current user's post
    
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
    @StateObject private var followService = FollowService.shared
    @StateObject private var moderationService = ModerationService.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared  // ✅ FIXED: Use @ObservedObject for singletons
    @State private var showingMenu = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingRepostConfirmation = false
    @State private var hasLitLightbulb = false
    @State private var hasSaidAmen = false
    @State private var isLightbulbAnimating = false
    @State private var showShareSheet = false
    @State private var showCommentsSheet = false
    @State private var isFollowing = false
    @State private var showReportSheet = false
    @State private var showUserProfile = false
    @State private var isSaved = false
    @State private var hasReposted = false
    @State private var isSaveInFlight = false
    @State private var isLightbulbToggleInFlight = false
    @State private var expectedLightbulbState = false
    @State private var isRepostToggleInFlight = false
    @State private var expectedRepostState = false
    @State private var lastSaveActionTimestamp: Date?  // ✅ NEW: Track last save action for debouncing
    @State private var saveActionCounter = 0  // ✅ NEW: Count save actions for debugging
    
    // Prayer activity
    @State private var isPraying = false
    @State private var prayingNowCount = 0
    
    // Animation timing constants
    private let fastAnimationDuration: Double = 0.15
    private let standardAnimationDuration: Double = 0.2
    private let springResponse: Double = 0.3
    private let springDamping: Double = 0.7
    
    // Moderation confirmations
    @State private var showMuteConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var showMuteSuccess = false
    @State private var showBlockSuccess = false
    
    // Error handling
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Real-time interaction counts
    @State private var lightbulbCount = 0
    @State private var amenCount = 0
    @State private var commentCount = 0
    @State private var repostCount = 0

    // Church Note
    @State private var showChurchNoteDetail = false
    @State private var churchNote: ChurchNote?
    
    // ✅ Real-time profile image
    @State private var currentProfileImageURL: String?
    
    enum PostCardCategory {
        case openTable
        case testimonies
        case prayer
        
        var icon: String {
            switch self {
            case .openTable: return "bubble.left.and.bubble.right.fill"
            case .testimonies: return "star.bubble.fill"
            case .prayer: return "hands.sparkles.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .openTable: return .orange
            case .testimonies: return .yellow
            case .prayer: return .blue
            }
        }
        
        var displayName: String {
            switch self {
            case .openTable: return "#OPENTABLE"
            case .testimonies: return "Testimonies"
            case .prayer: return "Prayer"
            }
        }
    }
    
    // Convenience initializer without post object
    init(
        authorName: String,
        timeAgo: String,
        content: String,
        category: PostCardCategory,
        topicTag: String? = nil,
        isUserPost: Bool = false
    ) {
        // Generate author initials from name
        let initials = authorName
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .prefix(2)
            .uppercased()
        
        // Create a mock Post object with example counts for preview
        let mockPost = Post(
            authorName: authorName,
            authorInitials: String(initials),
            timeAgo: timeAgo,
            content: content,
            category: category == .openTable ? .openTable : (category == .testimonies ? .testimonies : .prayer),
            topicTag: topicTag,
            lightbulbCount: category == .openTable ? Int.random(in: 45...156) : 0,
            commentCount: Int.random(in: 12...89),
            repostCount: Int.random(in: 5...34)
        )
        self.post = mockPost
        self.authorName = authorName
        self.timeAgo = timeAgo
        self.content = content
        self.category = category
        self.topicTag = topicTag
        self.isUserPost = isUserPost
    }
    
    // Full initializer with post object
    init(post: Post, isUserPost: Bool? = nil) {
        self.post = post
        self.authorName = post.authorName
        self.timeAgo = post.timeAgo
        self.content = post.content
        self.category = post.category.cardCategory
        self.topicTag = post.topicTag
        
        // Auto-detect if this is the user's post if not explicitly provided
        if let isUserPost = isUserPost {
            self.isUserPost = isUserPost
        } else {
            // Check against current user's Firebase Auth ID
            if let currentUserId = Auth.auth().currentUser?.uid {
                self.isUserPost = post.authorId == currentUserId
            } else {
                self.isUserPost = false
            }
        }
    }
    
    // MARK: - Debug State Tracking
    
    #if DEBUG
    @State private var showDebugOverlay = false
    @State private var debugLog: [String] = []
    
    private func logDebug(_ message: String, category: String = "GENERAL") {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logEntry = "[\(timestamp)][\(category)] \(message)"
        debugLog.append(logEntry)
        print("🔍 [POSTCARD-DEBUG][\(category)] \(message)")
        
        // Keep only last 50 entries
        if debugLog.count > 50 {
            debugLog.removeFirst(debugLog.count - 50)
        }
    }
    #else
    private func logDebug(_ message: String, category: String = "GENERAL") {
        // No-op in release builds
    }
    #endif
    
    // MARK: - Extracted Views
    
    private var avatarButton: some View {
        Button {
            // ✅ FIXED: Validate post and authorId before opening profile
            guard let post = post, !post.authorId.isEmpty else {
                print("❌ Cannot open profile: Invalid post or authorId")
                return
            }
            
            showUserProfile = true
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            avatarContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var avatarContent: some View {
        ZStack(alignment: .bottomTrailing) {
            // ✅ Show real-time profile image if available, otherwise fallback to post data, then initials
            Group {
                if let profileImageURL = currentProfileImageURL, !profileImageURL.isEmpty {
                    profileImageView(url: profileImageURL)
                        .onAppear {
                            #if DEBUG
                            print("🖼️ [POSTCARD] Showing current profile image: \(profileImageURL.prefix(50))...")
                            #endif
                        }
                        .id("current-\(profileImageURL)")
                } else if let post = post, let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                    profileImageView(url: profileImageURL)
                        .onAppear {
                            #if DEBUG
                            print("🖼️ [POSTCARD] Showing cached profile image: \(profileImageURL.prefix(50))...")
                            #endif
                        }
                        .id("cached-\(profileImageURL)")
                } else {
                    // Fallback to gradient with initials
                    avatarCircleWithInitials
                        .onAppear {
                            print("⚪️ [POSTCARD] No profile image - showing initials")
                            print("   Post author: \(post?.authorName ?? "unknown")")
                            print("   currentProfileImageURL: \(currentProfileImageURL ?? "nil")")
                            print("   post.authorProfileImageURL: \(post?.authorProfileImageURL ?? "nil")")
                        }
                        .id("initials")
                }
            }
            .id(currentProfileImageURL ?? post?.authorProfileImageURL ?? "no-image")
            .onChange(of: currentProfileImageURL) { oldValue, newValue in
                #if DEBUG
                print("🔄 [POSTCARD] currentProfileImageURL changed from \(oldValue?.prefix(30) ?? "nil") to \(newValue?.prefix(30) ?? "nil")")
                #endif
            }
            
            // Follow button - only show if not user's post AND post exists
            if !isUserPost && post != nil {
                followButton
            }
        }
        .task {
            // ✅ Fetch latest profile image URL in real-time
            await fetchLatestProfileImage()
        }
        .onChange(of: post?.authorProfileImageURL) { oldValue, newValue in
            // ✅ Sync currentProfileImageURL when Post updates from PostsManager
            if let newURL = newValue, !newURL.isEmpty, newURL != currentProfileImageURL {
                #if DEBUG
                print("🔄 [POSTCARD] Profile image updated in Post object: \(newURL.prefix(50))...")
                #endif
                currentProfileImageURL = newURL
            }
        }
    }
    
    private func profileImageView(url: String) -> some View {
        CachedAsyncImage(url: URL(string: url)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        } placeholder: {
            // Show placeholder while loading
            avatarCircleWithInitials
        }
    }
    
    private var avatarCircleWithInitials: some View {
        ZStack {
            avatarCircle
            
            // User initials - black text on white/gray background
            Text(userInitials)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.black)
        }
    }
    
    private var avatarCircle: some View {
        Circle()
            .fill(avatarGradient)
            .frame(width: 44, height: 44)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var avatarGradient: LinearGradient {
        // Black and white gradient
        LinearGradient(
            colors: [Color.white, Color(.systemGray6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Extract user initials from author name (up to 2 characters)
    private var userInitials: String {
        // Try to get from post first (if available)
        if let post = post, !post.authorInitials.isEmpty {
            return post.authorInitials
        }
        
        // Otherwise, calculate from author name
        let components = authorName.components(separatedBy: " ")
        let initials = components
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .prefix(2)
            .uppercased()
        
        return String(initials)
    }
    
    private var followButton: some View {
        Button {
            handleFollowButtonTap()
        } label: {
            followButtonIcon
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: isFollowing)
        .offset(x: 2, y: 2)
        .task {
            // Check follow status on appear
            await checkFollowStatus()
        }
    }
    
    private var followButtonIcon: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(isFollowing ? Color.green : Color.blue)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            
            // Icon - smaller "+" symbol
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
    
    // MARK: - Follow Actions
    
    private func handleFollowButtonTap() {
        Task {
            guard let post = post else { 
                print("⚠️ No post available for follow action")
                return 
            }
            
            let authorId = post.authorId
            
            // Prevent following yourself
            if let currentUserId = Auth.auth().currentUser?.uid,
               authorId == currentUserId {
                print("⚠️ Cannot follow yourself")
                return
            }
            
            // Optimistic UI update
            let previousState = isFollowing
            withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                isFollowing.toggle()
            }
            
            do {
                try await followService.toggleFollow(userId: authorId)
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(isFollowing ? .success : .warning)
                
                print("✅ Follow status changed: \(isFollowing ? "Following" : "Unfollowed")")
                
            } catch {
                print("❌ Follow error: \(error.localizedDescription)")
                
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        isFollowing = previousState
                    }
                }
                
                // Show error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func checkFollowStatus() async {
        guard let post = post else { return }
        
        // Don't check if it's your own post
        if isUserPost {
            isFollowing = false
            return
        }
        
        isFollowing = await followService.isFollowing(userId: post.authorId)
        print("📊 Follow status for \(post.authorName): \(isFollowing)")
    }
    
    @ViewBuilder
    private var menuContent: some View {
        if isUserPost {
            userPostMenuOptions
            Divider()
        }
        
        commonMenuOptions
        
        if !isUserPost {
            Divider()
            moderationMenuOptions
        }
    }
    
    @ViewBuilder
    private var userPostMenuOptions: some View {
        // Check if post is within 30-minute edit window
        if let post = post, canEditPost(post) {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit Post", systemImage: "pencil")
            }
        }
        
        // Users can always delete their posts
        Button(role: .destructive) {
            showingDeleteAlert = true
        } label: {
            Label("Delete Post", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var commonMenuOptions: some View {
        Button {
            sharePost()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Button {
            copyLink()
        } label: {
            Label("Copy Link", systemImage: "link")
        }
        
        Button {
            copyPostText()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
    }
    
    @ViewBuilder
    private var moderationMenuOptions: some View {
        Button(role: .destructive) {
            showReportSheet = true
        } label: {
            Label("Report Post", systemImage: "exclamationmark.triangle")
        }
        
        Button(role: .destructive) {
            showMuteConfirmation = true
        } label: {
            Label("Mute \(authorName)", systemImage: "speaker.slash")
        }
        
        Button(role: .destructive) {
            showBlockConfirmation = true
        } label: {
            Label("Block \(authorName)", systemImage: "hand.raised")
        }
    }
    
    // MARK: - Interaction Buttons
    
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
    
    private var lightbulbButton: some View {
        Button {
            // Prevent users from lighting their own posts
            if !isUserPost {
                toggleLightbulb()
            } else {
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                print("⚠️ Users cannot light their own posts")
            }
        } label: {
            lightbulbButtonLabel
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: hasLitLightbulb)
        .disabled(isUserPost) // Disable for user's own posts
        .opacity(isUserPost ? 0.5 : 1.0) // Visual feedback that it's disabled
    }
    
    private var lightbulbButtonLabel: some View {
        HStack(spacing: 4) {
            lightbulbIcon
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.yellow)
            .blur(radius: 8)
            .opacity(0.6)
    }
    
    private var lightbulbMainIcon: some View {
        Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: 13, weight: .semibold))
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
    
    private var amenButton: some View {
        Button {
            // Prevent users from amening their own posts
            if !isUserPost {
                toggleAmen()
            } else {
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                print("⚠️ Users cannot amen their own posts")
            }
        } label: {
            amenButtonLabel
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: hasSaidAmen)
        .disabled(isUserPost) // Disable for user's own posts
        .opacity(isUserPost ? 0.5 : 1.0) // Visual feedback that it's disabled
    }
    
    private var amenButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: hasSaidAmen ? "hands.clap.fill" : "hands.clap")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(hasSaidAmen ? Color.black : Color.black.opacity(0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(amenBackground)
        .overlay(amenOverlay)
    }
    
    private var amenBackground: some View {
        Capsule()
            .fill(hasSaidAmen ? Color.white : Color.black.opacity(0.05))
            .shadow(color: hasSaidAmen ? Color.black.opacity(0.15) : Color.clear, radius: 8, y: 2)
    }
    
    private var amenOverlay: some View {
        Capsule()
            .stroke(hasSaidAmen ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: hasSaidAmen ? 1.5 : 1)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Avatar with Follow Button (TAPPABLE)
            avatarButton
            
            // Name and info (TAPPABLE)
            authorInfoButton
            
            Spacer()
            
            // Three-dots menu
            menuButton
        }
    }
    
    private var authorInfoButton: some View {
        Button {
            // ✅ FIXED: Validate post and authorId before opening profile
            guard let post = post, !post.authorId.isEmpty else {
                print("❌ Cannot open profile: Invalid post or authorId")
                return
            }
            
            showUserProfile = true
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            authorInfoContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var authorInfoContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            authorNameRow
            timeAndTagRow
        }
    }
    
    private var authorNameRow: some View {
        HStack(spacing: 8) {
            // Make author name tappable to view profile
            Button {
                openAuthorProfile()
            } label: {
                HStack(spacing: 4) {
                    Text(authorName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)

                    // ✅ Verified badge
                    if let post = post, VerifiedBadgeHelper.isVerified(userId: post.authorId) {
                        VerifiedBadge(size: 14)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Category badge - only show for non-OpenTable posts
            if category != .openTable {
                categoryBadge
            }
        }
    }
    
    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(category.displayName)
                .font(.custom("OpenSans-Bold", size: 11))
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(category.color.opacity(0.15))
        )
    }
    
    private var timeAndTagRow: some View {
        HStack(spacing: 6) {
            Text(timeAgo)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            
            if let tag = topicTag {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(tag)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(category.color)
            }
        }
    }
    
    private var menuButton: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .modifier(PostCardSheetsModifier(
                showUserProfile: $showUserProfile,
                showingEditSheet: $showingEditSheet,
                showShareSheet: $showShareSheet,
                showCommentsSheet: $showCommentsSheet,
                showingDeleteAlert: $showingDeleteAlert,
                showReportSheet: $showReportSheet,
                showChurchNoteDetail: $showChurchNoteDetail,
                churchNote: $churchNote,
                post: post,
                authorName: authorName,
                category: category,
                deleteAction: deletePost
            ))
            .modifier(PostCardInteractionsModifier(
                post: post,
                interactionsService: interactionsService,
                savedPostsService: savedPostsService,
                hasLitLightbulb: $hasLitLightbulb,
                hasSaidAmen: $hasSaidAmen,
                isSaved: $isSaved,
                hasReposted: $hasReposted,
                isPraying: $isPraying,
                lightbulbCount: $lightbulbCount,
                amenCount: $amenCount,
                commentCount: $commentCount,
                repostCount: $repostCount,
                prayingNowCount: $prayingNowCount,
                isLightbulbToggleInFlight: $isLightbulbToggleInFlight,
                expectedLightbulbState: $expectedLightbulbState,
                isRepostToggleInFlight: $isRepostToggleInFlight,
                expectedRepostState: $expectedRepostState
            ))

            .alert("Mute \(authorName)?", isPresented: $showMuteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Mute", role: .destructive) {
                    muteAuthor()
                }
            } message: {
                Text("You won't see posts from \(authorName) in your feed anymore. You can unmute them from your settings.")
            }
            .alert("Block \(authorName)?", isPresented: $showBlockConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) {
                    blockAuthor()
                }
            } message: {
                Text("\(authorName) won't be able to see your posts or interact with you. You can unblock them from your settings.")
            }
            .alert("User Muted", isPresented: $showMuteSuccess) {
                Button("OK") { }
            } message: {
                Text("\(authorName) has been muted.")
            }
            .alert("User Blocked", isPresented: $showBlockSuccess) {
                Button("OK") { }
            } message: {
                Text("\(authorName) has been blocked.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            
            #if DEBUG
            // Debug overlay - tap post card 3 times quickly to toggle
            if showDebugOverlay {
                debugOverlayView
            }
            #endif
        }
        #if DEBUG
        .onTapGesture(count: 3) {
            withAnimation {
                showDebugOverlay.toggle()
            }
            let haptic = UIImpactFeedbackGenerator(style: .heavy)
            haptic.impactOccurred()
            logDebug("Debug overlay toggled: \(showDebugOverlay)", category: "DEBUG")
        }
        #endif
    }
    
    #if DEBUG
    private var debugOverlayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔍 DEBUG STATE")
                    .font(.caption.bold())
                Spacer()
                Button("×") {
                    withAnimation {
                        showDebugOverlay = false
                    }
                }
                .font(.title2)
                .foregroundStyle(.secondary)
            }
            
            Divider()
            
            if let post = post, let currentUserId = Auth.auth().currentUser?.uid {
                debugStateRow(label: "Post ID", value: String(post.firestoreId.prefix(12)))
                debugStateRow(label: "User ID", value: String(currentUserId.prefix(12)))
                
                Divider()
                
                debugStateRow(label: "Lightbulb (UI)", value: "\(hasLitLightbulb)")
                debugStateRow(label: "Lightbulb (Backend)", value: "\(interactionsService.userLightbulbedPosts.contains(post.firestoreId))")
                debugStateRow(label: "Lightbulb Count", value: "\(lightbulbCount)")
                
                Divider()
                
                debugStateRow(label: "Amen (UI)", value: "\(hasSaidAmen)")
                debugStateRow(label: "Amen (Backend)", value: "\(interactionsService.userAmenedPosts.contains(post.firestoreId))")
                debugStateRow(label: "Amen Count", value: "\(amenCount)")
                
                Divider()
                
                debugStateRow(label: "Repost (UI)", value: "\(hasReposted)")
                debugStateRow(label: "Repost (Backend)", value: "\(interactionsService.userRepostedPosts.contains(post.firestoreId))")
                debugStateRow(label: "Repost Count", value: "\(repostCount)")
                
                Divider()
                
                debugStateRow(label: "Saved (UI)", value: "\(isSaved)")
                debugStateRow(label: "Comment Count", value: "\(commentCount)")
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Logs:")
                            .font(.caption2.bold())
                        ForEach(debugLog.suffix(10).reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        )
        .padding(8)
    }
    
    private func debugStateRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption2.bold())
            Spacer()
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    #endif
    
    // MARK: - Card Content
    
    // MARK: - Swipe Gesture State
    @State private var swipeOffset: CGFloat = 0
    @State private var showSwipeAction = false
    @State private var swipeDirection: SwipeDirection = .none
    
    enum SwipeDirection {
        case none, left, right
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with author info and menu
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Post content with mention support
            MentionTextView(
                text: content,
                mentions: post?.mentions,
                font: .custom("OpenSans-Regular", size: 16),
                lineSpacing: 6
            ) { mention in
                // Navigate to mentioned user's profile
                print("📧 Tapped mention: @\(mention.username) (\(mention.userId))")
                // TODO: Navigate to user profile
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // ✅ Display post images if available
            if let post = post, let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                PostImagesView(imageURLs: imageURLs)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            // ✅ Church Note Preview (if post contains a church note)
            if let post = post, let churchNoteId = post.churchNoteId {
                churchNotePreview(churchNoteId: churchNoteId)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            // ✅ Link Preview Card if post has a link
            if let post = post, 
               let linkURLString = post.linkURL, 
               !linkURLString.isEmpty,
               let linkURL = URL(string: linkURLString) {
                // Create metadata from post fields
                let metadata = LinkPreviewMetadata(
                    url: linkURL,
                    title: post.linkPreviewTitle,
                    description: post.linkPreviewDescription,
                    imageURL: post.linkPreviewImageURL != nil ? URL(string: post.linkPreviewImageURL!) : nil,
                    siteName: post.linkPreviewSiteName
                )
                
                LinkPreviewCard(metadata: metadata) {
                    // Open link in Safari when tapped
                    UIApplication.shared.open(linkURL)
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            
            // Repost indicator if this is a repost
            if let post = post, post.isRepost, let originalAuthor = post.originalAuthorName {
                repostIndicator(originalAuthor: originalAuthor)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            
            // Interaction buttons (no divider)
            interactionButtons
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
        .background(
            ZStack {
                // Swipe action indicators
                if abs(swipeOffset) > 20 {
                    HStack {
                        if swipeDirection == .right {
                            // Like/Amen indicator on left
                            swipeIndicator(
                                icon: category == .openTable ? "lightbulb.fill" : "hands.sparkles.fill",
                                color: category == .openTable ? .yellow : .purple,
                                text: category == .openTable ? "Light" : "Amen"
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
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            }
        )
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only respond to predominantly horizontal swipes
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Require horizontal movement to be significantly more than vertical
                    // This allows vertical scrolling to work normally
                    guard horizontalAmount > verticalAmount * 2 else {
                        return
                    }
                    
                    // Determine swipe direction
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
                    
                    // Only trigger action if this was a horizontal swipe
                    guard horizontalAmount > verticalAmount * 2 else {
                        // Reset without triggering action
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
                        return
                    }
                    
                    if swipeDirection == .right && swipeOffset > threshold {
                        // Trigger like/amen action
                        triggerSwipeLikeAction()
                    } else if swipeDirection == .left && abs(swipeOffset) > threshold {
                        // Trigger comment action
                        triggerSwipeCommentAction()
                    }
                    
                    // Reset with animation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeOffset = 0
                        swipeDirection = .none
                    }
                }
        )
    }
    
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
        
        if category == .openTable {
            // Toggle lightbulb
            Task {
                await toggleLightbulb()
            }
        } else {
            // Toggle amen
            Task {
                await toggleAmen()
            }
        }
    }
    
    private func triggerSwipeCommentAction() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Open comments sheet
        showCommentsSheet = true
    }
    
    private func repostIndicator(originalAuthor: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text("Reposted from \(originalAuthor)")
                .font(.custom("OpenSans-SemiBold", size: 13))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Church Note Preview

    @ViewBuilder
    private func churchNotePreview(churchNoteId: String) -> some View {
        if let note = churchNote {
            ChurchNotePreviewCard(note: note) {
                showChurchNoteDetail = true
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        } else {
            // Loading state
            ProgressView()
                .task {
                    await loadChurchNote(id: churchNoteId)
                }
        }
    }

    private func loadChurchNote(id: String) async {
        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("churchNotes").document(id).getDocument()

            guard doc.exists, let note = try? doc.data(as: ChurchNote.self) else {
                // Church note reference exists but document is missing (deleted or invalid)
                // This is a non-critical error - silently skip showing the preview
                #if DEBUG
                print("⚠️ Church note reference exists but document not found: \(id.prefix(8))")
                #endif
                return
            }

            await MainActor.run {
                churchNote = note
            }
        } catch {
            // Network or parsing error - only log in debug mode
            #if DEBUG
            print("⚠️ Error loading church note \(id.prefix(8)): \(error.localizedDescription)")
            #endif
        }
    }

    private var interactionButtons: some View {
        HStack(spacing: 16) {
            // Primary Action (Lightbulb/Amen)
            if category == .openTable {
                circularInteractionButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: nil,  // ✅ No count - just illuminate when active
                    isActive: hasLitLightbulb,
                    activeColor: .orange,
                    disabled: isUserPost
                ) {
                    if !isUserPost { toggleLightbulb() }
                }
            } else {
                circularInteractionButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: nil,  // ✅ No count - just illuminate when active
                    isActive: hasSaidAmen,
                    activeColor: .black,
                    disabled: isUserPost
                ) {
                    if !isUserPost { toggleAmen() }
                }
            }
            
            // Prayer button (if applicable)
            if category == .prayer {
                circularInteractionButton(
                    icon: isPraying ? "hands.sparkles.fill" : "hands.sparkles",
                    count: prayingNowCount > 0 ? prayingNowCount : nil,
                    isActive: isPraying,
                    activeColor: .blue,
                    disabled: false
                ) {
                    togglePraying()
                }
            }
            
            // Comment - illuminate if there are comments
            circularInteractionButton(
                icon: "bubble.left.fill",
                count: nil,  // ✅ No count - just illuminate when there are comments
                isActive: commentCount > 0,
                activeColor: .blue,
                disabled: false
            ) {
                openComments()
            }
            
            // Repost - illuminate when user has reposted
            circularInteractionButton(
                icon: hasReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                count: nil,  // ✅ No count - just illuminate when active
                isActive: hasReposted,
                activeColor: .green,
                disabled: isUserPost || isRepostToggleInFlight  // ✅ Prevent double-tap
            ) {
                // ✅ Instant toggle - no confirmation needed
                if !isUserPost && !isRepostToggleInFlight {
                    toggleRepost()
                }
            }
            
            Spacer()
            
            // Share Church Note (if post has church note)
            if let _ = post?.churchNoteId, let _ = churchNote {
                circularInteractionButton(
                    icon: "square.and.arrow.up",
                    count: nil,
                    isActive: false,
                    activeColor: .blue,
                    disabled: false,
                    enableBounce: false
                ) {
                    showShareSheet = true
                }
            }
            
            // Bookmark (right aligned)
            circularInteractionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                count: nil,
                isActive: isSaved,
                activeColor: .orange,
                disabled: isSaveInFlight,
                enableBounce: false
            ) {
                toggleSave()
            }
        }
    }
    
    // MARK: - Threads-Style Interaction Button
    
    private func circularInteractionButton(
        icon: String,
        count: Int?,
        isActive: Bool,
        activeColor: Color,
        disabled: Bool,
        enableBounce: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // Just show the icon - no count numbers
            ZStack {
                // Background circle - black and white only
                Circle()
                    .fill(isActive ? Color.black : Color(.systemGray6))
                    .frame(width: 32, height: 32)
                
                // Subtle gradient accent border when active
                if isActive {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    activeColor.opacity(0.4),
                                    activeColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 32, height: 32)
                }
                
                // Icon - white when active, black when inactive
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.black)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .symbolEffect(.bounce, value: enableBounce ? isActive : false)
        .opacity(disabled ? 0.4 : 1.0)
    }
    
    private var prayingNowButton: some View {
        Button {
            togglePraying()
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    // Glow effect when praying
                    if isPraying {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                            .blur(radius: 6)
                            .opacity(0.6)
                    }
                    
                    Image(systemName: isPraying ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPraying ? 
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [.black.opacity(0.5), .black.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                if prayingNowCount > 0 {
                    Text("\(prayingNowCount)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(isPraying ? Color.blue : Color.black.opacity(0.5))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isPraying ? Color.blue.opacity(0.15) : Color.black.opacity(0.05))
                    .shadow(color: isPraying ? Color.blue.opacity(0.2) : Color.clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isPraying ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), lineWidth: isPraying ? 1.5 : 1)
            )
        }
        .symbolEffect(.bounce, value: isPraying)
    }
    
    // MARK: - Share Text Helper
    
    private func shareText(for post: Post) -> String {
        """
        \(category.displayName) by \(authorName)
        
        \(post.content)
        
        Join the conversation on AMEN APP!
        https://amenapp.com/post/\(post.firestoreId)
        """
    }
    
    // MARK: - Actions
    
    /// Open the author's profile (if not the current user)
    private func openAuthorProfile() {
        // Don't open profile for current user's own posts
        guard !isUserPost, let post = post else {
            print("ℹ️ Cannot open profile for own post")
            return
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        showUserProfile = true
        print("👤 Opening profile for: \(authorName) (ID: \(post.authorId))")
    }
    
    /// Check if post can be edited (within 30 minutes of creation)
    private func canEditPost(_ post: Post) -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60) // 30 minutes = 1800 seconds
        return post.createdAt >= thirtyMinutesAgo
    }
    
    /// ✅ Fetch latest profile image URL from Firestore in real-time
    private func fetchLatestProfileImage() async {
        guard let post = post, !post.authorId.isEmpty else {
            print("⚠️ [POSTCARD] No post or author ID for fetching profile image")
            return
        }
        
        #if DEBUG
        print("🔍 [POSTCARD] Fetching profile image for user: \(post.authorId)")
        print("   Post already has URL: \(post.authorProfileImageURL ?? "none")")
        #endif
        
        do {
            let db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(post.authorId).getDocument()
            
            // ✅ Handle both String values and null values from Firestore
            if let userData = userDoc.data() {
                let rawValue = userData["profileImageURL"]

                // Handle case where value is explicitly null (NSNull)
                if rawValue is NSNull {
                    print("⚠️ [POSTCARD] profileImageURL is explicitly null in Firestore")
                    return
                }

                // Try to get as String
                if let profileImageURL = rawValue as? String, !profileImageURL.isEmpty {
                    #if DEBUG
                    print("✅ [POSTCARD] Found profile image URL: \(profileImageURL.prefix(50))...")
                    #endif
                    await MainActor.run {
                        currentProfileImageURL = profileImageURL
                    }
                } else {
                    print("⚠️ [POSTCARD] No valid profile image URL")
                    print("   Raw value: \(String(describing: rawValue))")
                    print("   Type: \(type(of: rawValue))")
                }
            }
        } catch {
            print("❌ [POSTCARD] Error fetching profile image for user \(post.authorId): \(error.localizedDescription)")
        }
    }
    
    private func toggleLightbulb() {
        guard let post = post else {
            logDebug("❌ No post object available", category: "LIGHTBULB")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "LIGHTBULB")
            return
        }
        
        // Store previous state for rollback
        let previousState = hasLitLightbulb
        let previousCount = lightbulbCount
        
        logDebug("USER_ACTION: toggleLightbulb() called", category: "LIGHTBULB")
        logDebug("  postId: \(post.firestoreId)", category: "LIGHTBULB")
        logDebug("  currentUserId: \(currentUserId)", category: "LIGHTBULB")
        logDebug("  BEFORE: hasLitLightbulb=\(previousState), count=\(previousCount)", category: "LIGHTBULB")
        logDebug("  Source: Local @State", category: "LIGHTBULB")
        
        expectedLightbulbState = !previousState
        isLightbulbToggleInFlight = true
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            hasLitLightbulb.toggle()
            isLightbulbAnimating = true
        }
        
        logDebug("  OPTIMISTIC: hasLitLightbulb=\(hasLitLightbulb), count=\(lightbulbCount)", category: "LIGHTBULB")
        
        Task {
            do {
                logDebug("📤 Calling PostInteractionsService.toggleLightbulb...", category: "LIGHTBULB")
                
                // Call Realtime Database to toggle lightbulb
                // The count will be updated by the real-time observer
                try await interactionsService.toggleLightbulb(postId: post.firestoreId)
                
                logDebug("✅ Backend write SUCCESS", category: "LIGHTBULB")
                logDebug("  AFTER: hasLitLightbulb=\(hasLitLightbulb), count=\(lightbulbCount)", category: "LIGHTBULB")
                logDebug("  Note: Count will update via real-time observer", category: "LIGHTBULB")
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                // Reset animation state
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isLightbulbAnimating = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if isLightbulbToggleInFlight {
                            isLightbulbToggleInFlight = false
                        }
                    }
                }
                
            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "LIGHTBULB")
                logDebug("  ROLLBACK: Reverting to hasLitLightbulb=\(previousState)", category: "LIGHTBULB")
                
                // Revert optimistic update on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        hasLitLightbulb = previousState
                    }
                    isLightbulbAnimating = false
                    isLightbulbToggleInFlight = false
                }
                
                logDebug("  AFTER ROLLBACK: hasLitLightbulb=\(hasLitLightbulb)", category: "LIGHTBULB")
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func toggleAmen() {
        guard let post = post else {
            logDebug("❌ No post object available", category: "AMEN")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "AMEN")
            return
        }
        
        // Store previous state for rollback
        let previousState = hasSaidAmen
        let previousCount = amenCount
        
        logDebug("USER_ACTION: toggleAmen() called", category: "AMEN")
        logDebug("  postId: \(post.firestoreId)", category: "AMEN")
        logDebug("  currentUserId: \(currentUserId)", category: "AMEN")
        logDebug("  BEFORE: hasSaidAmen=\(previousState), count=\(previousCount)", category: "AMEN")
        logDebug("  Source: Local @State", category: "AMEN")
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            hasSaidAmen.toggle()
        }
        
        logDebug("  OPTIMISTIC: hasSaidAmen=\(hasSaidAmen), count=\(amenCount)", category: "AMEN")
        
        Task {
            do {
                logDebug("📤 Calling PostInteractionsService.toggleAmen...", category: "AMEN")
                
                // Call Realtime Database to toggle amen
                // The count will be updated by the real-time observer
                try await interactionsService.toggleAmen(postId: post.firestoreId)
                
                logDebug("✅ Backend write SUCCESS", category: "AMEN")
                logDebug("  AFTER: hasSaidAmen=\(hasSaidAmen), count=\(amenCount)", category: "AMEN")
                logDebug("  Note: Count will update via real-time observer", category: "AMEN")
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "AMEN")
                logDebug("  ROLLBACK: Reverting to hasSaidAmen=\(previousState)", category: "AMEN")
                
                // Revert optimistic update on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        hasSaidAmen = previousState
                    }
                }
                
                logDebug("  AFTER ROLLBACK: hasSaidAmen=\(hasSaidAmen)", category: "AMEN")
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func openComments() {
        print("💬 openComments() called")
        
        if let post = post {
            print("   - Post ID: \(post.firestoreId)")
            showCommentsSheet = true
            print("   - Comments sheet should appear")
        } else {
            print("❌ No post object available - cannot show comments")
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func deletePost() {
        guard let post = post else { return }
        
        // Delete from PostsManager
        postsManager.deletePost(postId: post.id)
        
        // Send notification for real-time ProfileView update
        NotificationCenter.default.post(
            name: Notification.Name("postDeleted"),
            object: nil,
            userInfo: ["postId": post.id]
        )
        
        print("🗑️ Post deleted - notification sent")
    }
    
    private func toggleRepost() {
        guard let post = post else {
            logDebug("❌ No post object available", category: "REPOST")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "REPOST")
            return
        }
        
        // ✅ Prevent double-tap: Exit if toggle already in flight
        guard !isRepostToggleInFlight else {
            logDebug("⏭️ SKIPPED: Repost toggle already in flight", category: "REPOST")
            return
        }
        
        // Store previous state for rollback
        let previousState = hasReposted
        let previousCount = repostCount
        
        logDebug("USER_ACTION: toggleRepost() called", category: "REPOST")
        logDebug("  postId: \(post.firestoreId)", category: "REPOST")
        logDebug("  currentUserId: \(currentUserId)", category: "REPOST")
        logDebug("  BEFORE: hasReposted=\(previousState), count=\(previousCount)", category: "REPOST")
        logDebug("  Source: Local @State", category: "REPOST")
        
        expectedRepostState = !previousState
        isRepostToggleInFlight = true
        
        // Optimistic UI update
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            hasReposted.toggle()
        }
        
        logDebug("  OPTIMISTIC: hasReposted=\(hasReposted), count=\(repostCount)", category: "REPOST")
        
        Task {
            do {
                logDebug("📤 Calling PostInteractionsService.toggleRepost...", category: "REPOST")
                
                // Toggle repost in Realtime Database
                let isReposted = try await interactionsService.toggleRepost(postId: post.firestoreId)
                
                logDebug("✅ Backend write SUCCESS", category: "REPOST")
                logDebug("  Backend returned: isReposted=\(isReposted)", category: "REPOST")
                
                // Update UI to match database state
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        hasReposted = isReposted
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if isRepostToggleInFlight {
                            isRepostToggleInFlight = false
                        }
                    }
                }
                
                logDebug("  AFTER: hasReposted=\(hasReposted), count=\(repostCount)", category: "REPOST")
                
                if isReposted {
                    // Create repost via PostsManager for user's profile
                    postsManager.repostToProfile(originalPost: post)
                    
                    // Send notification for real-time ProfileView update
                    NotificationCenter.default.post(
                        name: Notification.Name("postReposted"),
                        object: nil,
                        userInfo: ["post": post]
                    )
                    
                    logDebug("✅ Reposted to profile", category: "REPOST")
                } else {
                    // Remove repost from PostsManager
                    // ✅ Pass Firestore ID for proper repost removal
                    postsManager.removeRepost(postId: post.id, firestoreId: post.firestoreId)
                    
                    // Send notification for real-time ProfileView update
                    NotificationCenter.default.post(
                        name: Notification.Name("repostRemoved"),
                        object: nil,
                        userInfo: ["postId": post.id]
                    )
                    
                    logDebug("✅ Repost removed from profile", category: "REPOST")
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "REPOST")
                logDebug("  ROLLBACK: Reverting to hasReposted=\(previousState)", category: "REPOST")
                
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        hasReposted = previousState
                    }
                    isRepostToggleInFlight = false
                    
                    errorMessage = "Failed to toggle repost. Please try again."
                    showErrorAlert = true
                }
                
                logDebug("  AFTER ROLLBACK: hasReposted=\(hasReposted)", category: "REPOST")
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    

    private func sharePost() {
        showShareSheet = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func copyLink() {
        guard let post = post else { return }

        // ✅ Generate deep link URL for production
        let deepLink = "amenapp://post/\(post.id.uuidString)"

        UIPasteboard.general.string = deepLink

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔗 Deep link copied to clipboard: \(deepLink)")
    }
    
    private func copyPostText() {
        UIPasteboard.general.string = content
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("📋 Post text copied to clipboard")
    }
    
    private func muteAuthor() {
        guard let post = post else { return }
        let authorId = post.authorId
        
        Task {
            do {
                try await moderationService.muteUser(userId: authorId)
                print("🔇 Muted \(authorName)")
                
                await MainActor.run {
                    showMuteSuccess = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Failed to mute: \(error)")
                
                await MainActor.run {
                    errorMessage = "Failed to mute user. Please try again."
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func blockAuthor() {
        guard let post = post else { return }
        let authorId = post.authorId
        
        Task {
            do {
                try await moderationService.blockUser(userId: authorId)
                print("🚫 Blocked \(authorName)")
                
                await MainActor.run {
                    showBlockSuccess = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Failed to block: \(error)")
                
                await MainActor.run {
                    errorMessage = "Failed to block user. Please try again."
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func toggleSave() {
        // ✅ IDEMPOTENCY CHECK #1: Prevent saves already in flight
        guard !isSaveInFlight else {
            logDebug("⚠️ Save already in flight, ignoring", category: "SAVE")
            print("⚠️ [SAVE-GUARD-1] Blocked duplicate save attempt (already in flight)")
            return
        }
        
        guard let post = post else {
            logDebug("❌ No post object available", category: "SAVE")
            print("❌ [SAVE-GUARD-2] No post object - cannot save")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "SAVE")
            print("❌ [SAVE-GUARD-3] No current user - not authenticated")
            return
        }
        
        // ✅ IDEMPOTENCY CHECK #2: Debounce rapid taps (prevent saves within 500ms)
        if let lastTimestamp = lastSaveActionTimestamp {
            let timeSinceLastSave = Date().timeIntervalSince(lastTimestamp)
            if timeSinceLastSave < 0.5 {
                print("⚠️ [SAVE-GUARD-4] Debounced: \(Int(timeSinceLastSave * 1000))ms since last save (min 500ms)")
                return
            }
        }
        
        // ✅ Check network first
        guard AMENNetworkMonitor.shared.isConnected else {
            logDebug("📱 Offline - cannot save/unsave posts", category: "SAVE")
            print("📱 [SAVE-GUARD-5] Offline - save blocked")
            errorMessage = "You're offline. Please check your connection and try again."
            showErrorAlert = true
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            return
        }
        
        // Record this save action
        saveActionCounter += 1
        lastSaveActionTimestamp = Date()
        isSaveInFlight = true
        
        // Store previous state for rollback
        let previousState = isSaved
        
        logDebug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: "SAVE")
        logDebug("USER_ACTION #\(saveActionCounter): toggleSave() called", category: "SAVE")
        logDebug("  postId: \(post.firestoreId)", category: "SAVE")
        logDebug("  currentUserId: \(currentUserId)", category: "SAVE")
        logDebug("  BEFORE: isSaved=\(previousState)", category: "SAVE")
        logDebug("  savedPostIds.contains: \(savedPostsService.savedPostIds.contains(post.firestoreId))", category: "SAVE")
        logDebug("  Source: User tap on bookmark button", category: "SAVE")
        logDebug("  Timestamp: \(Date())", category: "SAVE")
        logDebug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: "SAVE")
        
        // Optimistic UI update
        logDebug("  📤 Performing OPTIMISTIC UI update...", category: "SAVE")
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            isSaved.toggle()
        }
        
        logDebug("  ✅ OPTIMISTIC UPDATE COMPLETE: isSaved=\(isSaved)", category: "SAVE")
        logDebug("  Expected outcome: \(isSaved ? "SAVED" : "UNSAVED")", category: "SAVE")
        
        Task {
            defer {
                Task { @MainActor in
                    isSaveInFlight = false
                }
            }
            do {
                logDebug("📤 Calling savedPostsService.toggleSavePost...", category: "SAVE")
                
                // Toggle using RTDB service (returns true if saved, false if unsaved)
                let isSavedNow = try await savedPostsService.toggleSavePost(postId: post.firestoreId)
                
                logDebug("✅ Backend write SUCCESS", category: "SAVE")
                logDebug("  Backend returned: isSaved=\(isSavedNow)", category: "SAVE")
                
                // Ensure UI matches server state
                await MainActor.run {
                    if isSaved != isSavedNow {
                        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                            isSaved = isSavedNow
                        }
                    }
                }
                
                logDebug("  AFTER: isSaved=\(isSaved)", category: "SAVE")
                logDebug(isSavedNow ? "💾 Post saved" : "🗑️ Post unsaved", category: "SAVE")
                
                // ✅ Post notification with full Post object for ProfileView
                if isSavedNow {
                    NotificationCenter.default.post(
                        name: Notification.Name("postSaved"),
                        object: nil,
                        userInfo: ["post": post]
                    )
                    logDebug("📬 Posted postSaved notification", category: "SAVE")
                } else {
                    NotificationCenter.default.post(
                        name: Notification.Name("postUnsaved"),
                        object: nil,
                        userInfo: ["postId": post.id]
                    )
                    logDebug("📬 Posted postUnsaved notification", category: "SAVE")
                }
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "SAVE")
                logDebug("  ROLLBACK: Reverting to isSaved=\(previousState)", category: "SAVE")
                
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        isSaved = previousState
                    }
                    
                    // ✅ Better error message based on error type
                    if let urlError = error as? URLError {
                        if urlError.code == .notConnectedToInternet {
                            errorMessage = "No internet connection. Please try again when online."
                        } else if urlError.code == .timedOut {
                            errorMessage = "Request timed out. Please try again."
                        } else {
                            errorMessage = "Network error. Please check your connection."
                        }
                    } else {
                        errorMessage = "Failed to save post. Please try again."
                    }
                    
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func togglePraying() {
        print("🙏 togglePraying() called")
        
        guard let post = post else {
            print("❌ No post object available")
            return
        }
        
        guard category == .prayer else {
            print("⚠️ Not a prayer post")
            return
        }
        
        print("   - Post ID: \(post.firestoreId)")
        print("   - Current state: \(isPraying ? "praying" : "not praying")")
        
        // Store previous state for rollback
        let previousState = isPraying
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            isPraying.toggle()
        }
        
        let rtdb = RealtimeDatabaseManager.shared
        
        Task {
            let success: Bool
            
            if isPraying {
                // Start praying
                success = await withCheckedContinuation { continuation in
                    rtdb.startPraying(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            } else {
                // Stop praying
                success = await withCheckedContinuation { continuation in
                    rtdb.stopPraying(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            }
            
            if success {
                print("✅ \(isPraying ? "Started" : "Stopped") praying for post")
                
                // Haptic feedback
                await MainActor.run {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                }
            } else {
                print("❌ Failed to \(isPraying ? "start" : "stop") praying")
                
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        isPraying = previousState
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Report Post Sheet

struct ReportPostSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    let postAuthor: String
    let category: PostCard.PostCardCategory
    
    @State private var selectedReason: ReportReason?
    @State private var additionalDetails = ""
    @State private var showSuccessAlert = false
    @FocusState private var isTextFieldFocused: Bool
    
    enum ReportReason: String, CaseIterable, Identifiable {
        case spam = "Spam or misleading"
        case harassment = "Harassment or bullying"
        case hateSpeech = "Hate speech or violence"
        case inappropriateContent = "Inappropriate content"
        case falseInformation = "False information"
        case offTopic = "Off-topic or irrelevant"
        case copyright = "Copyright violation"
        case other = "Other"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .spam: return "envelope.badge.fill"
            case .harassment: return "exclamationmark.bubble.fill"
            case .hateSpeech: return "hand.raised.fill"
            case .inappropriateContent: return "eye.slash.fill"
            case .falseInformation: return "checkmark.seal.fill"
            case .offTopic: return "arrow.triangle.branch"
            case .copyright: return "c.circle.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
        
        var description: String {
            switch self {
            case .spam:
                return "Unwanted commercial content or repetitive posts"
            case .harassment:
                return "Targeted harassment, threats, or bullying"
            case .hateSpeech:
                return "Content promoting violence or hatred"
            case .inappropriateContent:
                return "Sexually explicit or disturbing content"
            case .falseInformation:
                return "Deliberately misleading or false claims"
            case .offTopic:
                return "Content that doesn't fit this category"
            case .copyright:
                return "Unauthorized use of copyrighted material"
            case .other:
                return "Something else that violates community guidelines"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Post")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Help us keep AMEN safe. Why are you reporting this post?")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Report Reasons
                    VStack(spacing: 12) {
                        ForEach(ReportReason.allCases) { reason in
                            ReportReasonCard(
                                reason: reason,
                                isSelected: selectedReason == reason
                            ) {
                                selectedReason = reason
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Additional Details (optional)
                    if selectedReason != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Additional Details (Optional)")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.primary)
                            
                            ZStack(alignment: .topLeading) {
                                if additionalDetails.isEmpty {
                                    Text("Provide any additional context that might help us review this report...")
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                }
                                
                                TextEditor(text: $additionalDetails)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .frame(minHeight: 100)
                                    .focused($isTextFieldFocused)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            
                            Text("\(additionalDetails.count)/500 characters")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(additionalDetails.count > 500 ? .red : .secondary)
                        }
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.2)))
                    }
                    
                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            
                            Text("Your report is confidential")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.primary)
                        }
                        
                        Text("We'll review this report and take appropriate action. The person who posted this won't know you reported it.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.08))
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 100)
                }
                .padding(.vertical, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Submit Button
                Button {
                    submitReport()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("Submit Report")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedReason != nil ? Color.red : Color.red.opacity(0.3))
                    )
                }
                .disabled(selectedReason == nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
            }
        }
        .alert("Report Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for helping keep AMEN safe. We'll review this report and take appropriate action.")
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        Task {
            do {
                try await ModerationService.shared.reportPost(
                    postId: post.firestoreId,
                    postAuthorId: post.authorId,
                    reason: convertToModerationReason(reason),
                    additionalDetails: additionalDetails.isEmpty ? nil : additionalDetails
                )
                
                print("✅ Report submitted successfully")
                
                await MainActor.run {
                    showSuccessAlert = true
                }
                
            } catch {
                print("❌ Failed to submit report: \(error)")
                
                await MainActor.run {
                    // Show error to user
                    dismiss()
                }
            }
        }
    }
    
    private func convertToModerationReason(_ reason: ReportReason) -> ModerationReportReason {
        switch reason {
        case .spam: return .spam
        case .harassment: return .harassment
        case .hateSpeech: return .hateSpeech
        case .inappropriateContent: return .inappropriateContent
        case .falseInformation: return .falseInformation
        case .offTopic: return .offTopic
        case .copyright: return .copyright
        case .other: return .other
        }
    }
}

// MARK: - Report Reason Card

struct ReportReasonCard: View {
    let reason: ReportPostSheet.ReportReason
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.red.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: reason.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.red : Color.secondary)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.rawValue)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(reason.description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                
                Spacer()
                
                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.red : Color(.systemGray4))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.red.opacity(0.3) : Color(.systemGray5), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? Color.red.opacity(0.1) : Color.black.opacity(0.04), radius: isSelected ? 12 : 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - View Modifiers

/// Handles all sheet presentations and alerts
private struct PostCardSheetsModifier: ViewModifier {
    @Binding var showUserProfile: Bool
    @Binding var showingEditSheet: Bool
    @Binding var showShareSheet: Bool
    @Binding var showCommentsSheet: Bool
    @Binding var showingDeleteAlert: Bool
    @Binding var showReportSheet: Bool
    @Binding var showChurchNoteDetail: Bool
    @Binding var churchNote: ChurchNote?

    let post: Post?
    let authorName: String
    let category: PostCard.PostCardCategory
    let deleteAction: () -> Void
    
    func body(content: Content) -> some View {
        content
            // User Profile Sheet - Opens when tapping avatar or author name
            .sheet(isPresented: $showUserProfile) {
                if let post = post, !post.authorId.isEmpty {
                    UserProfileView(userId: post.authorId, showsDismissButton: true)
                } else {
                    // Fallback if no post data or invalid authorId
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Unable to load profile")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.primary)
                        Text("The user information is not available")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let post = post {
                    EditPostSheet(post: post)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let post = post {
                    // If post has a church note, show church note share options
                    if post.churchNoteId != nil, let note = churchNote {
                        ChurchNoteShareOptionsSheet(note: note)
                    } else {
                        // Otherwise show standard post sharing
                        ShareSheet(items: [shareText(for: post)])
                    }
                }
            }
            .sheet(isPresented: $showCommentsSheet) {
                if let post = post {
                    CommentsView(post: post)
                        .environmentObject(UserService())
                }
            }
            .sheet(isPresented: $showReportSheet) {
                if let post = post {
                    ReportPostSheet(
                        post: post,
                        postAuthor: authorName,
                        category: category
                    )
                }
            }
            .sheet(isPresented: $showChurchNoteDetail) {
                if let note = churchNote {
                    ChurchNoteDetailModal(note: note)
                }
            }
            .alert("Delete Post", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAction()
                }
            } message: {
                Text("Are you sure you want to delete this post? This action cannot be undone.")
            }
    }
    
    private func shareText(for post: Post) -> String {
        """
        \(category.displayName) by \(post.authorName)
        
        \(post.content)
        
        Join the conversation on AMEN APP!
        https://amenapp.com/post/\(post.firestoreId)
        """
    }
}

/// Handles all interaction observers and state updates
private struct PostCardInteractionsModifier: ViewModifier {
    let post: Post?
    @ObservedObject var interactionsService: PostInteractionsService  // ✅ FIXED: Observe changes
    @ObservedObject var savedPostsService: RealtimeSavedPostsService  // ✅ FIXED: Observe changes
    
    @Binding var hasLitLightbulb: Bool
    @Binding var hasSaidAmen: Bool
    @Binding var isSaved: Bool
    @Binding var hasReposted: Bool
    @Binding var isPraying: Bool
    @Binding var lightbulbCount: Int
    @Binding var amenCount: Int
    @Binding var commentCount: Int
    @Binding var repostCount: Int
    @Binding var prayingNowCount: Int
    @Binding var isLightbulbToggleInFlight: Bool
    @Binding var expectedLightbulbState: Bool
    @Binding var isRepostToggleInFlight: Bool
    @Binding var expectedRepostState: Bool
    
    @State private var hasCompletedInitialLoad = false
    
    // Helper computed properties to simplify onChange expressions
    private var isPostLightbulbed: Bool {
        guard let post = post else { return false }
        return interactionsService.userLightbulbedPosts.contains(post.firestoreId)
    }
    
    private var isPostAmened: Bool {
        guard let post = post else { return false }
        return interactionsService.userAmenedPosts.contains(post.firestoreId)
    }
    
    private var isPostReposted: Bool {
        guard let post = post else { return false }
        return interactionsService.userRepostedPosts.contains(post.firestoreId)
    }
    
    func body(content: Content) -> some View {
        content
            .task {
                guard let post = post else { return }
                let postId = post.firestoreId
                guard let currentUserId = Auth.auth().currentUser?.uid else { return }
                
                #if DEBUG
                print("🔍 [LIFECYCLE][TASK] PostCard.task started for post: \(postId.prefix(8))")
                print("  currentUserId: \(currentUserId)")
                #endif
                
                // Start observing real-time interactions
                interactionsService.observePostInteractions(postId: postId)
                #if DEBUG
                print("  ✅ Started observing real-time interactions")
                #endif
                
                // ✅ Wait for initial cache to load before checking state
                if !interactionsService.hasLoadedInitialCache {
                    var attempts = 0
                    // ✅ Increased timeout to 3 seconds (150 attempts × 20ms)
                    // Cache-first reads should be instant, but this provides safety margin
                    while !interactionsService.hasLoadedInitialCache && attempts < 150 {
                        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                        attempts += 1
                    }
                    #if DEBUG
                    if attempts >= 150 {
                        print("    ⚠️ Cache load timeout after 3 seconds")
                    } else if attempts > 0 {
                        print("    ✅ Cache loaded after \(attempts * 20)ms")
                    }
                    #endif
                }
                
                // Load lightbulb state from userLightbulbedPosts
                let lightbulbedStatus = interactionsService.userLightbulbedPosts.contains(postId)
                withTransaction(Transaction(animation: nil)) {
                    hasLitLightbulb = lightbulbedStatus
                }
                print("    hasLitLightbulb=\(hasLitLightbulb) (postId: \(String(postId.prefix(8))))")
                
                // Load amen state from userAmenedPosts
                let amenedStatus = interactionsService.userAmenedPosts.contains(postId)
                withTransaction(Transaction(animation: nil)) {
                    hasSaidAmen = amenedStatus
                }
                print("    hasSaidAmen=\(hasSaidAmen) (from userAmenedPosts)")
                
                // Check saved status with offline handling
                // ✅ Disable animation for initial load to prevent auto-toggle appearance
                print("  📊 CHECKING SAVED STATUS...")
                print("    - Method: checkSavedStatusSafely()")
                print("    - PostId: \(postId.prefix(8))")
                let savedStatus = await checkSavedStatusSafely(postId: postId)
                print("    - Result from checkSavedStatusSafely: \(savedStatus)")
                print("    - savedPostIds.contains: \(savedPostsService.savedPostIds.contains(postId))")
                
                withTransaction(Transaction(animation: nil)) {
                    isSaved = savedStatus
                }
                print("    ✅ isSaved set to: \(isSaved) (NO ANIMATION)")
                
                // ✅ Disable animation for initial repost load to prevent auto-toggle appearance
                let repostedStatus = interactionsService.userRepostedPosts.contains(postId)
                withTransaction(Transaction(animation: nil)) {
                    if !isRepostToggleInFlight {
                        hasReposted = repostedStatus
                    }
                }
                print("    hasReposted=\(hasReposted) (from userRepostedPosts)")
                
                // Check if currently praying (if prayer post)
                if post.category == .prayer {
                    isPraying = await checkIfPraying(postId: postId)
                    print("    isPraying=\(isPraying) (prayer post)")
                }
                
                // Load counts
                lightbulbCount = await interactionsService.getLightbulbCount(postId: postId)
                amenCount = await interactionsService.getAmenCount(postId: postId)
                commentCount = await interactionsService.getCommentCount(postId: postId)
                repostCount = await interactionsService.getRepostCount(postId: postId)
                
                print("  📊 COUNTS LOADED:")
                print("    lightbulbCount=\(lightbulbCount)")
                print("    amenCount=\(amenCount)")
                print("    commentCount=\(commentCount)")
                print("    repostCount=\(repostCount)")
                
                // Observe praying count for prayer posts
                if post.category == .prayer {
                    observePrayingCount(postId: postId)
                }
                
                // Mark initial load as complete
                hasCompletedInitialLoad = true
                #if DEBUG
                print("  ✅ Initial load complete, real-time observers active")
                #endif
            }
            .onDisappear {
                if let post = post {
                    #if DEBUG
                    print("🔍 [LIFECYCLE][DISAPPEAR] PostCard disappeared for post: \(post.firestoreId.prefix(8))")
                    print("  Stopping observation of interactions")
                    #endif
                    interactionsService.stopObservingPost(postId: post.firestoreId)
                }
            }
            .onChange(of: interactionsService.postLightbulbs) { oldValue, newValue in
                if let post = post, let count = interactionsService.postLightbulbs[post.firestoreId] {
                    print("🔍 [BACKEND][COUNT] Lightbulb count updated for \(post.firestoreId.prefix(8))")
                    print("  BEFORE: \(lightbulbCount)")
                    print("  AFTER: \(count)")
                    print("  Source: Real-time observer (postLightbulbs)")
                    lightbulbCount = count
                }
            }
            .onChange(of: interactionsService.postAmens) { oldValue, newValue in
                if let post = post, let count = interactionsService.postAmens[post.firestoreId] {
                    print("🔍 [BACKEND][COUNT] Amen count updated for \(post.firestoreId.prefix(8))")
                    print("  BEFORE: \(amenCount)")
                    print("  AFTER: \(count)")
                    print("  Source: Real-time observer (postAmens)")
                    amenCount = count
                }
            }
            .onChange(of: interactionsService.postComments) { oldValue, newValue in
                if let post = post, let count = interactionsService.postComments[post.firestoreId] {
                    print("🔍 [BACKEND][COUNT] Comment count updated for \(post.firestoreId.prefix(8))")
                    print("  BEFORE: \(commentCount)")
                    print("  AFTER: \(count)")
                    print("  Source: Real-time observer (postComments)")
                    commentCount = count
                }
            }
            .onChange(of: interactionsService.postReposts) { oldValue, newValue in
                if let post = post, let count = interactionsService.postReposts[post.firestoreId] {
                    print("🔍 [BACKEND][COUNT] Repost count updated for \(post.firestoreId.prefix(8))")
                    print("  BEFORE: \(repostCount)")
                    print("  AFTER: \(count)")
                    print("  Source: Real-time observer (postReposts)")
                    repostCount = count
                }
            }
            // ✅ Update lightbulb state when userLightbulbedPosts changes
            .onChange(of: isPostLightbulbed) { oldState, newState in
                guard let post = post else { return }
                
                print("🔍 [BACKEND][STATE] isPostLightbulbed changed for \(post.firestoreId.prefix(8))")
                print("  BEFORE: \(oldState)")
                print("  AFTER: \(newState)")
                print("  Source: userLightbulbedPosts (backend)")
                print("  hasCompletedInitialLoad: \(hasCompletedInitialLoad)")
                print("  isLightbulbToggleInFlight: \(isLightbulbToggleInFlight)")
                
                // Only update if state actually changed
                guard oldState != newState else {
                    print("  ⏭️ SKIPPED: No actual change")
                    return
                }
                
                // ✅ Allow updates during initial load to reflect cached data
                // But use no animation to prevent visual "toggling"
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                if isLightbulbToggleInFlight {
                    print("  🔄 Toggle in flight, expected state: \(expectedLightbulbState)")
                    if newState == expectedLightbulbState {
                        print("  ✅ Backend state matches expected")
                        // Only update if UI state doesn't already match
                        if hasLitLightbulb != newState {
                            print("  📝 Updating hasLitLightbulb: \(hasLitLightbulb) → \(newState)")
                            withAnimation(animation) {
                                hasLitLightbulb = newState
                            }
                        } else {
                            print("  ⏭️ SKIPPED: hasLitLightbulb already matches backend state")
                        }
                        isLightbulbToggleInFlight = false
                    } else {
                        print("  ⚠️ Backend state doesn't match expected, keeping toggle in flight")
                    }
                    return
                }
                
                // Only update if UI state doesn't already match backend
                if hasLitLightbulb != newState {
                    print("  ✅ Updating hasLitLightbulb: \(oldState) → \(newState)")
                    withAnimation(animation) {
                        hasLitLightbulb = newState
                    }
                } else {
                    print("  ⏭️ SKIPPED: hasLitLightbulb already matches backend state \(newState)")
                }
            }
            // ✅ Update amen state when userAmenedPosts changes
            .onChange(of: isPostAmened) { oldState, newState in
                guard let post = post else { return }
                
                print("🔍 [BACKEND][STATE] isPostAmened changed for \(post.firestoreId.prefix(8))")
                print("  BEFORE: \(oldState)")
                print("  AFTER: \(newState)")
                print("  Source: userAmenedPosts (backend)")
                print("  hasCompletedInitialLoad: \(hasCompletedInitialLoad)")
                
                guard oldState != newState else {
                    print("  ⏭️ SKIPPED: No actual change")
                    return
                }
                
                // ✅ Allow updates during initial load to reflect cached data
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                // Only update if UI state doesn't already match backend
                if hasSaidAmen != newState {
                    print("  ✅ Updating hasSaidAmen: \(oldState) → \(newState)")
                    withAnimation(animation) {
                        hasSaidAmen = newState
                    }
                } else {
                    print("  ⏭️ SKIPPED: hasSaidAmen already matches backend state \(newState)")
                }
            }
            // ✅ Update repost state when userRepostedPosts changes (after initial load only)
            .onChange(of: isPostReposted) { oldState, newState in
                guard let post = post else { return }
                
                print("🔍 [BACKEND][STATE] isPostReposted changed for \(post.firestoreId.prefix(8))")
                print("  BEFORE: \(oldState)")
                print("  AFTER: \(newState)")
                print("  Source: userRepostedPosts (backend)")
                print("  hasCompletedInitialLoad: \(hasCompletedInitialLoad)")
                print("  isRepostToggleInFlight: \(isRepostToggleInFlight)")
                
                guard oldState != newState else {
                    print("  ⏭️ SKIPPED: No actual change")
                    return
                }
                
                // ✅ Allow updates during initial load to reflect cached data
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                if isRepostToggleInFlight {
                    print("  🔄 Toggle in flight, expected state: \(expectedRepostState)")
                    if newState == expectedRepostState {
                        print("  ✅ Backend state matches expected")
                        // Only update if UI state doesn't already match
                        if hasReposted != newState {
                            print("  📝 Updating hasReposted: \(hasReposted) → \(newState)")
                            withAnimation(animation) {
                                hasReposted = newState
                            }
                        } else {
                            print("  ⏭️ SKIPPED: hasReposted already matches backend state")
                        }
                        isRepostToggleInFlight = false
                    } else {
                        print("  ⚠️ Backend state doesn't match expected, keeping toggle in flight")
                    }
                    return
                }
                
                // Only update if UI state doesn't already match backend
                if hasReposted != newState {
                    print("  ✅ Updating hasReposted: \(oldState) → \(newState)")
                    withAnimation(animation) {
                        hasReposted = newState
                    }
                } else {
                    print("  ⏭️ SKIPPED: hasReposted already matches backend state \(newState)")
                }
            }
            // ✅ NEW: Monitor savedPostIds changes and sync to local state
            .onChange(of: savedPostsService.savedPostIds) { oldValue, newValue in
                guard let post = post, hasCompletedInitialLoad else { return }
                let postId = post.firestoreId
                
                let wasInOldSet = oldValue.contains(postId)
                let isInNewSet = newValue.contains(postId)
                
                // Only log and act if THIS specific post's state changed
                guard wasInOldSet != isInNewSet else { return }
                
                print("🔍 [BACKEND][SAVED] savedPostIds changed for post: \(postId.prefix(8))")
                print("  Was in set: \(wasInOldSet) → Now in set: \(isInNewSet)")
                print("  Current local state: isSaved=\(isSaved)")
                
                // Sync local state to match backend truth
                // The binding will update the @State in the parent PostCard
                if isSaved != isInNewSet {
                    print("  🔄 SYNCING isSaved: \(isSaved) → \(isInNewSet)")
                    // ✅ Disable animation to prevent visual "auto-toggle" when switching tabs
                    withTransaction(Transaction(animation: nil)) {
                        isSaved = isInNewSet
                    }
                } else {
                    print("  ✅ Already in sync")
                }
            }
    }
    
    private func checkIfPraying(postId: String) async -> Bool {
        // Check if current user is praying for this post
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        
        return await withCheckedContinuation { continuation in
            let ref = Database.database().reference()
                .child("prayerActivity")
                .child(postId)
                .child("prayingUsers")
                .child(userId)
            
            ref.observeSingleEvent(of: .value) { snapshot in
                continuation.resume(returning: snapshot.exists())
            }
        }
    }
    
    /// ✅ Check saved status with offline handling
    private func checkSavedStatusSafely(postId: String) async -> Bool {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 [CHECK-SAVED-STATUS] Starting check for post: \(postId.prefix(8))")
        
        // First, check if we're online
        let isOnline = AMENNetworkMonitor.shared.isConnected
        print("  Network status: \(isOnline ? "ONLINE" : "OFFLINE")")
        
        guard isOnline else {
            print("  📱 Using CACHED saved status (offline)")
            let cached = savedPostsService.isPostSavedSync(postId: postId)
            print("  Result from cache: \(cached)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return cached
        }
        
        // We're online - try the async check with error handling
        print("  🌐 Querying Firebase RTDB...")
        do {
            let saved = try await savedPostsService.isPostSaved(postId: postId)
            print("  ✅ Firebase query SUCCESS")
            print("  Result: \(saved)")
            print("  savedPostIds updated: \(savedPostsService.savedPostIds.contains(postId))")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return saved
        } catch {
            // If Firebase query fails (permissions, timeout, etc.), fall back to cache
            print("  ⚠️ Firebase query FAILED: \(error.localizedDescription)")
            print("  📱 Falling back to CACHE")
            let cached = savedPostsService.isPostSavedSync(postId: postId)
            print("  Result from cache: \(cached)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return savedPostsService.isPostSavedSync(postId: postId)
        }
    }
    
    private func observePrayingCount(postId: String) {
        let rtdb = RealtimeDatabaseManager.shared
        _ = rtdb.observePrayingNowCount(postId: postId) { count in
            Task { @MainActor in
                prayingNowCount = count
            }
        }
    }
}

// MARK: - Post Comments View

struct PostCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var commentService = CommentService.shared
    @StateObject private var postsManager = PostsManager.shared
    
    let post: Post
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var isLoading = true
    @FocusState private var isCommentFocused: Bool
    
    // Computed property for real-time comments
    private var comments: [Comment] {
        commentService.comments[post.firestoreId] ?? []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Comments List
                    ScrollView {
                        VStack(spacing: 16) {
                            // Original post preview
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(post.authorInitials)
                                                .font(.custom("OpenSans-Bold", size: 14))
                                                .foregroundStyle(.orange)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(post.authorName)
                                            .font(.custom("OpenSans-Bold", size: 15))
                                            .foregroundStyle(.primary)
                                        
                                        Text(post.timeAgo)
                                            .font(.custom("OpenSans-Regular", size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Text(post.content)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            
                            // Comments
                            if isLoading {
                                ProgressView()
                                    .padding(.vertical, 40)
                            } else if comments.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("No comments yet")
                                        .font(.custom("OpenSans-Bold", size: 18))
                                        .foregroundStyle(.primary)
                                    
                                    Text("Be the first to share your thoughts!")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(comments) { comment in
                                        RealCommentCardView(
                                            comment: comment,
                                            postCategory: post.category,
                                            onReply: { replyingTo = comment }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.bottom, 80)
                    }
                    
                    Spacer()
                }
                
                // Comment Input at Bottom
                VStack {
                    Spacer()
                    commentInputView
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
            }
            .task {
                await loadComments()
            }
            .onAppear {
                // Start listening for real-time updates
                commentService.startListening(to: post.firestoreId)
            }
            .onDisappear {
                // Stop listening when view disappears
                commentService.stopListening()
            }
        }
    }
    
    // MARK: - Load Comments
    
    private func loadComments() async {
        isLoading = true
        
        do {
            // Fetch initial comments (will be updated by real-time listener)
            _ = try await commentService.fetchComments(for: post.firestoreId)
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            print("❌ Failed to load comments: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - Comment Input View
    
    private var commentInputView: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            
            VStack(spacing: 12) {
                // Reply indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorName)")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Input container
                HStack(alignment: .center, spacing: 12) {
                    // Avatar
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text("JD")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(.blue)
                        )
                    
                    // Text field with liquid glass effect
                    HStack(spacing: 8) {
                        TextField("Add a comment...", text: $commentText, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                            .lineLimit(1...4)
                            .focused($isCommentFocused)
                            .padding(.leading, 16)
                            .padding(.trailing, 8)
                            .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                            
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    
                    // Send button
                    if !commentText.isEmpty {
                        Button {
                            Task {
                                await submitComment()
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
    }
    
    // MARK: - Actions
    
    private func submitComment() async {
        guard !commentText.isEmpty else { return }
        
        do {
            if let replyingTo = replyingTo {
                // Submit as a reply
                _ = try await commentService.addReply(
                    postId: post.firestoreId,
                    parentCommentId: replyingTo.id ?? "",
                    content: commentText
                )
            } else {
                // Submit as a top-level comment
                _ = try await commentService.addComment(
                    postId: post.firestoreId,
                    content: commentText
                )
            }
            
            await MainActor.run {
                // Real-time listener will update the comments array automatically
                commentText = ""
                replyingTo = nil
                isCommentFocused = false
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        } catch {
            print("❌ Failed to submit comment: \(error)")
        }
    }
}

// MARK: - Real Comment Card View (Using Firebase Comment Model)

private struct RealCommentCardView: View {
    let comment: Comment
    let postCategory: Post.PostCategory
    let onReply: () -> Void
    
    @State private var hasLitLightbulb = false
    @State private var localLightbulbCount: Int
    @State private var hasAmen = false
    @State private var localAmenCount: Int
    @State private var showReplies = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showMenu = false
    @StateObject private var commentService = CommentService.shared
    
    // Check if this is the current user's comment
    private var isUserComment: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return comment.authorId == currentUserId
    }
    
    // Get replies for this comment
    private var replies: [Comment] {
        commentService.commentReplies[comment.id ?? ""] ?? []
    }
    
    init(comment: Comment, postCategory: Post.PostCategory, onReply: @escaping () -> Void) {
        self.comment = comment
        self.postCategory = postCategory
        self.onReply = onReply
        _localLightbulbCount = State(initialValue: comment.lightbulbCount)
        _localAmenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                avatarView
                
                VStack(alignment: .leading, spacing: 8) {
                    // Header with menu
                    HStack(spacing: 6) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.primary)
                        
                        Text("•")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text(comment.createdAt.timeAgoDisplay())
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        if comment.isEdited {
                            Text("• edited")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        // Menu button for user's own comments
                        if isUserComment {
                            Menu {
                                Button {
                                    showEditSheet = true
                                } label: {
                                    Label("Edit Comment", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete Comment", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.5))
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                    
                    // Content
                    Text(comment.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                    
                    // Actions
                    interactionButtonsView
                }
                
                Spacer()
            }
            
            // Nested replies
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Show/Hide replies button
                    Button {
                        showReplies.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        .foregroundStyle(.blue)
                        .padding(.leading, 52)  // Indent to align with comment content
                    }
                    .buttonStyle(.plain)
                    .animation(.easeOut(duration: 0.15), value: showReplies)
                    
                    // Replies list
                    if showReplies {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(replies) { reply in
                                RealCommentCardView(
                                    comment: reply,
                                    postCategory: postCategory,
                                    onReply: onReply
                                )
                                .padding(.leading, 40)  // Indent replies
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.15)))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
        .sheet(isPresented: $showEditSheet) {
            EditCommentSheet(comment: comment)
        }
        .alert("Delete Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteComment()
            }
        } message: {
            Text("Are you sure you want to delete this comment? This action cannot be undone.")
        }
        .task {
            // Check if user has lit lightbulb on this comment
            guard let commentId = comment.id else { return }
            hasLitLightbulb = await commentService.hasUserAmened(commentId: commentId, postId: comment.postId)
            hasAmen = hasLitLightbulb // Same function for both
        }
    }
    
    // MARK: - Avatar View
    
    private var avatarView: some View {
        Group {
            if let profileImageURL = comment.authorProfileImageURL, !profileImageURL.isEmpty {
                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } placeholder: {
                    defaultAvatar
                }
            } else {
                defaultAvatar
            }
        }
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(postCategory.cardCategory.color.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(
                Text(comment.authorInitials)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(postCategory.cardCategory.color)
            )
    }
    
    // MARK: - Interaction Buttons
    
    private var interactionButtonsView: some View {
        HStack(spacing: 16) {
            // Lightbulb/Amen button based on category
            if postCategory == .openTable {
                lightbulbButton
            } else {
                amenButton
            }
            
            // Reply button
            replyButton
        }
        .padding(.top, 4)
    }
    
    private var lightbulbButton: some View {
        Button {
            Task {
                guard let commentId = comment.id else { return }
                
                // Store previous state for rollback
                let previousLit = hasLitLightbulb
                let previousCount = localLightbulbCount
                
                // Optimistic update
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasLitLightbulb.toggle()
                    localLightbulbCount += hasLitLightbulb ? 1 : -1
                }
                
                do {
                    try await commentService.toggleAmen(commentId: commentId, postId: comment.postId)
                } catch {
                    print("❌ Failed to toggle lightbulb: \(error)")
                    
                    // Revert on error
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasLitLightbulb = previousLit
                            localLightbulbCount = previousCount
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    if hasLitLightbulb {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.yellow)
                            .blur(radius: 6)
                            .opacity(0.6)
                    }
                    
                    Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hasLitLightbulb ?
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [.secondary, .secondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                if localLightbulbCount > 0 {
                    Text("\(localLightbulbCount)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(hasLitLightbulb ? .orange : .secondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: hasLitLightbulb)
    }
    
    private var amenButton: some View {
        Button {
            Task {
                guard let commentId = comment.id else { return }
                
                // Store previous state for rollback
                let previousAmen = hasAmen
                let previousCount = localAmenCount
                
                // Optimistic update
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasAmen.toggle()
                    localAmenCount += hasAmen ? 1 : -1
                }
                
                do {
                    try await commentService.toggleAmen(commentId: commentId, postId: comment.postId)
                } catch {
                    print("❌ Failed to toggle amen: \(error)")
                    
                    // Revert on error
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasAmen = previousAmen
                            localAmenCount = previousCount
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasAmen ? "hands.clap.fill" : "hands.clap")
                    .font(.system(size: 11, weight: .semibold))
                
                if localAmenCount > 0 {
                    Text("\(localAmenCount)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(hasAmen ? .black : .secondary)
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: hasAmen)
    }
    
    private var replyButton: some View {
        Button {
            onReply()
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 11))
                Text("Reply")
                    .font(.custom("OpenSans-SemiBold", size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func deleteComment() {
        Task {
            guard let commentId = comment.id else { return }
            
            do {
                try await commentService.deleteComment(commentId: commentId, postId: comment.postId)
                print("✅ Comment deleted")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Failed to delete comment: \(error)")
            }
        }
    }
}

// ReportPostSheet and ReportReasonCard have been moved earlier in the file

// MARK: - Edit Comment Sheet

struct EditCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var commentService = CommentService.shared
    
    let comment: Comment
    @State private var editedContent: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool
    
    init(comment: Comment) {
        self.comment = comment
        _editedContent = State(initialValue: comment.content)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text editor
                TextEditor(text: $editedContent)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding(16)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                
                Spacer()
                
                // Character count
                HStack {
                    Text("\(editedContent.count) characters")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Edit Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedContent == comment.content || isSaving)
                }
            }
            .onAppear {
                // Auto-focus the text editor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
        }
    }
    
    private func saveChanges() {
        Task {
            guard let commentId = comment.id else { return }
            
            isSaving = true
            
            do {
                try await commentService.editComment(
                    commentId: commentId,
                    postId: comment.postId,
                    newContent: editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
                }
                
                print("✅ Comment updated successfully")
                
            } catch {
                print("❌ Failed to update comment: \(error)")
                
                await MainActor.run {
                    isSaving = false
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

#Preview("Post Cards") {
    VStack {
        PostCard(
            authorName: "User",
            timeAgo: "2h",
            content: "Sample post content",
            category: .openTable,
            topicTag: "Sample",
            isUserPost: true
        )
        .padding()
        
        PostCard(
            authorName: "User",
            timeAgo: "45m",
            content: "Sample post content",
            category: .testimonies,
            isUserPost: false
        )
        .padding()
    }
}
#Preview("Report Sheet") {
    let samplePost = Post(
        id: UUID(),
        authorId: "preview-user",
        authorName: "John Doe",
        authorInitials: "JD",
        timeAgo: "2h",
        content: "Sample post content",
        category: .openTable,
        topicTag: nil,
        visibility: .everyone,
        allowComments: true,
        imageURLs: nil,
        linkURL: nil,
        createdAt: Date(),
        amenCount: 0,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0,
        isRepost: false,
        originalAuthorName: nil,
        originalAuthorId: nil
    )
    
    ReportPostSheet(
        post: samplePost,
        postAuthor: "John Doe",
        category: .openTable
    )
}

// MARK: - Post Link Button Component
/// Button to open external links from posts
struct PostLinkButton: View {
    let url: String
    @State private var isPressed = false
    
    var body: some View {
        Button {
            openURL()
        } label: {
            HStack(spacing: 12) {
                // Link icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                
                // URL text (shortened)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Link")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    
                    Text(displayURL)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // External link indicator
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private var displayURL: String {
        // Remove protocol and www for display
        var display = url
        display = display.replacingOccurrences(of: "https://", with: "")
        display = display.replacingOccurrences(of: "http://", with: "")
        display = display.replacingOccurrences(of: "www.", with: "")
        
        // Limit length
        if display.count > 40 {
            return String(display.prefix(37)) + "..."
        }
        return display
    }
    
    private func openURL() {
        guard let url = URL(string: url) else {
            print("❌ Invalid URL: \(url)")
            return
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Open in Safari
        UIApplication.shared.open(url)
        print("✅ Opening URL: \(url)")
    }
}

