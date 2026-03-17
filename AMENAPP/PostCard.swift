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
    
    // PERF: Only observe services whose published properties are actually read in the view body.
    // postsManager and moderationService are only used in action handlers — not observed.
    // Not @ObservedObject — prevents all PostCards from re-rendering when any save changes.
    // isSaved state is managed locally; service is only used for action calls and initial load.
    private let savedPostsService = RealtimeSavedPostsService.shared
    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var pinnedPostService = PinnedPostService.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared
    // Action-only singletons — accessed directly without observation to avoid render storms
    private let postsManager = PostsManager.shared
    private let moderationService = ModerationService.shared
    @State private var showingMenu = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingRepostConfirmation = false
    @State private var hasLitLightbulb = false

    // Staggered entrance animation
    @State private var cardAppeared = false
    @State private var hasSaidAmen = false
    @State private var isLightbulbAnimating = false
    @State private var showShareSheet = false
    @State private var showPostDetail = false  // ✅ Show PostDetailView (for tapping header/content)
    @State private var showCommentsSheet = false  // ✅ Show CommentsView (for comment button and swipe)
    // ❌ REMOVED: @State private var isFollowing = false  // P0 FIX: Replaced with computed property
    @State private var showReportSheet = false
    @State private var showUserProfile = false
    @State private var lastProfileNavDate: Date = .distantPast
    @State private var tappedMentionUserId: String? = nil
    @State private var showMentionedUserProfile = false
    @State private var isSaved = false
    @State private var showBereanSheet = false  // AI sparkle → Berean AI
    @State private var hasReposted = false
    @State private var hasCommented = false  // illuminates comment button after user comments
    @State private var isSaveInFlight = false
    @State private var isLightbulbToggleInFlight = false
    @State private var expectedLightbulbState = false
    @State private var isRepostToggleInFlight = false
    @State private var expectedRepostState = false
    @State private var isAmenToggleInFlight = false  // P0 FIX: Prevent duplicate amen toggles
    @State private var amenShakeError = false         // H) Triggers shake on backend failure
    @State private var lightbulbShakeError = false    // H) Shake on lightbulb backend failure
    @State private var saveShakeError = false         // H) Shake on save backend failure
    @State private var repostShakeError = false       // H) Shake on repost backend failure
    @State private var lastSaveActionTimestamp: Date?  // ✅ NEW: Track last save action for debouncing
    @State private var saveActionCounter = 0  // ✅ NEW: Count save actions for debugging
    @State private var isFollowInFlight = false  // P0 FIX: Prevent duplicate follow operations
    
    // Prayer activity
    @State private var isPraying = false
    @State private var prayingNowCount = 0
    
    // Animation timing constants
    private let fastAnimationDuration: Double = 0.15
    private let standardAnimationDuration: Double = 0.2
    private let springResponse: Double = 0.12
    private let springDamping: Double = 0.75
    
    // Moderation confirmations
    @State private var showMuteConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var showMuteSuccess = false
    @State private var showBlockSuccess = false
    @State private var showNotInterestedConfirmation = false
    @State private var showNotInterestedSuccess = false
    
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
    
    // Translation state — managed by TranslationService
    @State private var showTranslatedContent = false
    @State private var translatedContent: String?
    @State private var detectedLanguage: String?
    @State private var translationUIState: TranslationUIState = .available
    @State private var showTranslationInfoSheet = false
    @State private var isTranslating = false
    // PERF: Legacy translationService kept for backward compat; new service is action-only (not observed)
    private let translationService = PostTranslationService.shared
    private let newTranslationService = TranslationService.shared
    
    // P1-B FIX: Content expansion state now lives in PostInteractionsService
    // (keyed by stablePostId) so it survives SwiftUI view recycling during scroll.
    // Reading and writing goes through interactionsService.isExpanded / toggleExpanded.
    
    // P0 FIX: Stable post ID for reactions/interactions
    // Always use firebaseId if available, fallback to UUID
    // This prevents reactions from being tied to wrong IDs when firestoreId changes
    private var stablePostId: String {
        post?.firebaseId ?? post?.id.uuidString ?? ""
    }
    
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
            case .openTable: return .primary // Changed from orange to neutral
            case .testimonies: return .yellow
            case .prayer: return .blue
            }
        }
        
        var displayName: String {
            switch self {
            case .openTable: return "" // Remove #OPENTABLE badge entirely
            case .testimonies: return "Testimonies"
            case .prayer: return "" // Prayer Request topic tag is shown instead
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
        #if DEBUG
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logEntry = "[\(timestamp)][\(category)] \(message)"
        debugLog.append(logEntry)
        dlog("🔍 [POSTCARD-DEBUG][\(category)] \(message)")
        
        // Keep only last 50 entries
        if debugLog.count > 50 {
            debugLog.removeFirst(debugLog.count - 50)
        }
        #endif
    }
    #else
    private func logDebug(_ message: String, category: String = "GENERAL") {
        // No-op in release builds
    }
    #endif
    
    // MARK: - Extracted Views
    
    private var avatarButton: some View {
        ZStack(alignment: .bottomTrailing) {
            // Profile image button (tappable to view profile)
            Button {
                // ✅ FIXED: Validate post and authorId before opening profile
                guard let post = post, !post.authorId.isEmpty else {
                    dlog("❌ Cannot open profile: Invalid post or authorId")
                    return
                }
                // Dedicated profile debounce — independent of shared NavigationGuard
                let now = Date()
                guard now.timeIntervalSince(lastProfileNavDate) > 0.35 else { return }
                lastProfileNavDate = now
                showUserProfile = true
                HapticManager.impact(style: .light)
            } label: {
                avatarContent
            }
            .buttonStyle(.liquidGlass)  // P0 FIX: Instant visual press feedback
            
            // Follow button - positioned outside the avatar button to avoid nesting
            if !isUserPost && post != nil {
                followButton
            }
        }
    }
    
    private var avatarContent: some View {
        Group {
            // ✅ Show real-time profile image if available, otherwise fallback to post data, then initials
            if let profileImageURL = currentProfileImageURL, !profileImageURL.isEmpty {
                profileImageView(url: profileImageURL)
                    .id("current-\(profileImageURL)")
            } else if let post = post, let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                profileImageView(url: profileImageURL)
                    .id("cached-\(profileImageURL)")
            } else {
                // Fallback to gradient with initials
                avatarCircleWithInitials
                    .id("initials")
            }
        }
        // P1 FIX: Single .onChange to sync currentProfileImageURL from Post; removed duplicate
        // outer .id() (each branch already has its own .id()) and redundant empty .onChange.
        .task {
            // Set initial value on appear — covers first render before any onChange fires
            if let post = post, let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                currentProfileImageURL = profileImageURL
            }
        }
        .onChange(of: post?.authorProfileImageURL) { oldValue, newValue in
            // Sync currentProfileImageURL when Post updates from PostsManager
            if let newURL = newValue, !newURL.isEmpty, newURL != currentProfileImageURL {
                dlog("🔄 [POSTCARD] Profile image updated: \(newURL.prefix(50))...")
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
        .buttonStyle(.instantFeedback)  // ✅ P0 FIX: INSTANT touch-down feedback
        .symbolEffect(.bounce, value: isFollowing)
        .offset(x: 2, y: 2)
        // P0 FIX: Removed .task - no longer needed since isFollowing is computed from FollowService
    }
    
    private var followButtonIcon: some View {
        ZStack {
            // Tap target — invisible, keeps hit area generous
            Circle()
                .fill(Color.clear)
                .frame(width: 30, height: 30)

            // Visual circle — smaller
            Circle()
                .fill(isFollowing ? Color.black : Color.white)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            
            // Icon
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isFollowing ? .white : .black)
        }
    }
    
    // MARK: - Follow Actions
    
    // P0 FIX: Computed property that observes FollowService.shared.following Set
    // This ensures ALL PostCards for the same author share the same follow state
    private var isFollowing: Bool {
        guard let post = post else { return false }
        return followService.following.contains(post.authorId)
    }
    
    private func handleFollowButtonTap() {
        // P0 FIX: Prevent duplicate follow operations
        guard !isFollowInFlight else {
            dlog("⚠️ Follow operation already in progress")
            return
        }
        
        Task {
            guard let post = post else { 
                dlog("⚠️ No post available for follow action")
                return 
            }
            
            let authorId = post.authorId
            
            // Prevent following yourself
            if let currentUserId = Auth.auth().currentUser?.uid,
               authorId == currentUserId {
                dlog("⚠️ Cannot follow yourself")
                return
            }
            
            // Set in-flight flag
            await MainActor.run {
                isFollowInFlight = true
            }
            
            // P0 FIX: No local state to update - FollowService.shared.following Set updates automatically
            // The computed property 'isFollowing' will reflect the change immediately across ALL PostCards
            
            do {
                try await followService.toggleFollow(userId: authorId)
                HapticManager.notification(type: isFollowing ? .success : .warning)
            } catch {
                #if DEBUG
                dlog("❌ Follow error: \(error.localizedDescription)")
                #endif
                // FollowService already handles rollback in its optimistic update logic
                HapticManager.notification(type: .error)
            }
            
            // P0 FIX: Reset in-flight flag
            await MainActor.run {
                isFollowInFlight = false
            }
        }
    }
    
    private func checkFollowStatus() async {
        // P0 FIX: No longer needed - isFollowing is now a computed property
        // that automatically derives from followService.following Set
        // Keeping this function stub in case it's called elsewhere, but it's now a no-op
        return
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
        // Pin/Unpin post (like Threads)
        if let post = post {
            let isPinned = pinnedPostService.isPostPinned(post.firestoreId)
            Button {
                Task {
                    do {
                        try await pinnedPostService.togglePin(postId: post.firestoreId)
                        HapticManager.notification(type: .success)
                    } catch {
                        dlog("❌ Pin error: \(error)")
                        HapticManager.notification(type: .error)
                    }
                }
            } label: {
                Label(
                    isPinned ? "Unpin from profile" : "Pin to profile",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }
        
        Divider()
        
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
        Button {
            showNotInterestedConfirmation = true
        } label: {
            Label("Not Interested", systemImage: "eye.slash")
        }
        
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
        
        if let postAuthorId = post?.authorId {
            Button {
                Task {
                    await RestrictService.shared.loadIfNeeded()
                    await RestrictService.shared.toggleRestrict(postAuthorId)
                    let isNowRestricted = RestrictService.shared.isRestricted(postAuthorId)
                    ToastManager.shared.success(isNowRestricted ? "\(authorName) restricted" : "\(authorName) unrestricted")
                }
            } label: {
                let isRestricted = RestrictService.shared.isRestricted(postAuthorId)
                Label(isRestricted ? "Unrestrict \(authorName)" : "Restrict \(authorName)", systemImage: isRestricted ? "checkmark.circle" : "hand.raised.slash")
            }
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
            colors: [.red, .red.opacity(0.8)],
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
                HapticManager.notification(type: .warning)
                dlog("⚠️ Users cannot light their own posts")
            }
        } label: {
            lightbulbButtonLabel
        }
        .buttonStyle(.instantFeedback)  // P0 FIX: INSTANT touch-down feedback
        .symbolEffect(.bounce, value: hasLitLightbulb)
        .disabled(isUserPost)
        .opacity(isUserPost ? 0.5 : 1.0)
        .shakeOnError(lightbulbShakeError)
        // P2-B FIX: VoiceOver label so the button is not announced as "lightbulb" image
        .accessibilityLabel(hasLitLightbulb ? "Remove lightbulb reaction" : "Add lightbulb reaction")
        .accessibilityHint(isUserPost ? "You cannot react to your own post" : "")
    }
    
    private var lightbulbButtonLabel: some View {
        HStack(spacing: 6) {
            lightbulbIcon
            // Reaction counts are private — not shown publicly.
            // The icon state (filled/outlined) reflects the user's own action only.
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    private var lightbulbIcon: some View {
        ZStack {
            // Enhanced glow effect when active
            if hasLitLightbulb {
                lightbulbGlowEffect
            }
            
            lightbulbMainIcon
        }
    }
    
    private var lightbulbGlowEffect: some View {
        // P1 FIX: Reduced blur for performance (12px -> 4px, removed double layer)
        Image(systemName: "lightbulb.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.red)
            .blur(radius: 4)
            .opacity(0.3)
    }
    
    private var lightbulbMainIcon: some View {
        Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(hasLitLightbulb ? lightbulbGradientActive : lightbulbGradientInactive)
            .shadow(color: hasLitLightbulb ? Color.red.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 2)
            .shadow(color: hasLitLightbulb ? Color.red.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 1)
    }
    
    private var lightbulbBackground: some View {
        Capsule()
            .fill(hasLitLightbulb ? Color.red.opacity(0.15) : Color.black.opacity(0.05))
            .shadow(color: hasLitLightbulb ? Color.red.opacity(0.2) : Color.clear, radius: 8, y: 2)
    }
    
    private var lightbulbOverlay: some View {
        Capsule()
            .stroke(hasLitLightbulb ? Color.red.opacity(0.3) : Color.black.opacity(0.1), lineWidth: hasLitLightbulb ? 1.5 : 1)
    }
    
    private var amenButton: some View {
        Button {
            // Prevent users from amening their own posts
            if !isUserPost {
                toggleAmen()
            } else {
                HapticManager.notification(type: .warning)
                dlog("⚠️ Users cannot amen their own posts")
            }
        } label: {
            amenButtonLabel
        }
        .buttonStyle(.instantFeedback)  // P0 FIX: INSTANT touch-down feedback
        .symbolEffect(.bounce, value: hasSaidAmen)
        .disabled(isUserPost)
        .opacity(isUserPost ? 0.5 : 1.0)
        .shakeOnError(amenShakeError)
        // P2-B FIX: VoiceOver label
        .accessibilityLabel(hasSaidAmen ? "Remove Amen" : "Say Amen")
        .accessibilityHint(isUserPost ? "You cannot react to your own post" : "")
    }
    
    private var amenButtonLabel: some View {
        HStack(spacing: 6) {
            ZStack {
                // P1 FIX: Simplified glow for performance (12px -> 4px, single layer)
                if hasSaidAmen {
                    Image(systemName: "hands.clap.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.blue)
                        .blur(radius: 4)
                        .opacity(0.25)
                }
                
                // Main icon
                Image(systemName: hasSaidAmen ? "hands.clap.fill" : "hands.clap")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(hasSaidAmen ? Color.blue : Color.secondary)
                    .shadow(color: hasSaidAmen ? Color.blue.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 1)
            }
            
            // Amen count is private — not shown publicly.
            // Icon state (filled/outlined) reflects user's own amen only.
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
                dlog("❌ Cannot open profile: Invalid post or authorId")
                return
            }
            // Dedicated profile debounce — independent of shared NavigationGuard
            let now = Date()
            guard now.timeIntervalSince(lastProfileNavDate) > 0.35 else { return }
            lastProfileNavDate = now
            showUserProfile = true
            HapticManager.impact(style: .light)
        } label: {
            authorInfoContent
        }
        .buttonStyle(.liquidGlass)  // P0 FIX: Instant visual press feedback
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
            
            // 📌 Pinned post indicator (like Threads)
            if let post = post, pinnedPostService.isPostPinned(post.firestoreId) {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Pinned")
                        .font(.custom("OpenSans-Bold", size: 11))
                }
                .foregroundStyle(.gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
            }

            // Category badge - only show if category allows it (not for Tip, Fun Fact)
            if let post = post, post.category.showCategoryBadge {
                categoryBadge
            } else if post == nil && category != .openTable {
                // Fallback for preview posts without full Post object
                categoryBadge
            }

            // AI-generated content label (shown when user chose to add a source label)
            if let post = post, let source = post.contentSource, !source.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                    Text("via \(source)")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.purple.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.8))
            }
        }
    }
    
    private var categoryBadge: some View {
        Group {
            if !category.displayName.isEmpty {
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
        }
    }
    
    private var translationToggleButton: some View {
        Group {
            switch translationUIState {
            case .loading:
                // Pulsing loading chip — matches AMEN design language
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                    Text("Translating…")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .modifier(PulsingOpacityModifier())

            case .translated(let variant):
                HStack(spacing: 8) {
                    // Source language label
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .medium))
                        Text("Translated from \(SupportedLanguage.displayName(for: variant.sourceLanguage))")
                            .font(.custom("OpenSans-Regular", size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .onTapGesture { showTranslationInfoSheet = true }

                    // Toggle original/translated
                    Button {
                        HapticManager.impact(style: .light)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showTranslatedContent.toggle()
                        }
                    } label: {
                        Text(showTranslatedContent ? "View original" : "View translation")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showTranslationInfoSheet) {
                    TranslationInfoSheet(variant: variant, isPresented: $showTranslationInfoSheet)
                }

            case .available:
                // "See Translation" button
                Button {
                    HapticManager.impact(style: .light)
                    Task { await triggerTranslation() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 11, weight: .medium))
                        Text("See translation")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(.primary.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)

            case .error(let err):
                HStack(spacing: 6) {
                    Text(err.userFacingMessage)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await triggerTranslation() }
                    }
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(.secondary)
                }

            case .notNeeded, .disabled:
                EmptyView()
            }
        }
    }
    
    private var timeAndTagRow: some View {
        HStack(spacing: 6) {
            Text(timeAgo)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            
            if let tag = topicTag, !tag.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
                // Topic tag as neutral pill
                Text(tag)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            
            // Source label badge — shown when content was labeled as AI/external
            if let source = post?.contentSource, !source.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .semibold))
                    Text("via \(source)")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.80))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.50))
                )
            }
        }
    }
    
    /// Controls visibility of the translation affordance row
    private var shouldShowTranslationAffordance: Bool {
        switch translationUIState {
        case .notNeeded, .disabled: return false
        case .available: return detectedLanguage != nil && detectedLanguage != translationService.getDeviceLanguage()
        case .loading, .translated, .error: return true
        }
    }

    private var bereanInitialQuery: String {
        let text = post?.content ?? content
        if category == .testimonies {
            return "I'd like to reflect on this testimony: \"\(text)\"\n\nWhat scripture speaks to this, and what can I learn from it?"
        } else {
            return "Someone shared this thought: \"\(text)\"\n\nWhat does scripture say about this topic? Please ground your answer in specific Bible verses."
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
    
    // Break up the modifier chain into intermediate steps so the Swift type-checker
    // can resolve each piece independently (avoids "expression too complex" timeout).

    @ViewBuilder
    private var cardWithSheets: some View {
        cardContent
            .contextMenu {
                menuContent
            }
            .modifier(PostCardSheetsModifier(
                showUserProfile: $showUserProfile,
                showingEditSheet: $showingEditSheet,
                showShareSheet: $showShareSheet,
                showPostDetail: $showPostDetail,
                showCommentsSheet: $showCommentsSheet,
                showingDeleteAlert: $showingDeleteAlert,
                showReportSheet: $showReportSheet,
                showChurchNoteDetail: $showChurchNoteDetail,
                churchNote: $churchNote,
                showMentionedUserProfile: $showMentionedUserProfile,
                tappedMentionUserId: $tappedMentionUserId,
                hasCommented: $hasCommented,
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
                isSaveInFlight: $isSaveInFlight,
                isLightbulbToggleInFlight: $isLightbulbToggleInFlight,
                expectedLightbulbState: $expectedLightbulbState,
                isRepostToggleInFlight: $isRepostToggleInFlight,
                expectedRepostState: $expectedRepostState,
                hasCommented: $hasCommented
            ))
    }

    @ViewBuilder
    private var cardWithAlerts: some View {
        cardWithSheets
            .alert("Mute \(authorName)?", isPresented: $showMuteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Mute", role: .destructive) { muteAuthor() }
            } message: {
                Text("You won't see posts from \(authorName) in your feed anymore. You can unmute them from your settings.")
            }
            .alert("Block \(authorName)?", isPresented: $showBlockConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) { blockAuthor() }
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
            .alert("Not Interested?", isPresented: $showNotInterestedConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") { markNotInterested() }
            } message: {
                Text("You'll see fewer posts like this. This helps us personalize your feed.")
            }
            .alert("Feedback Received", isPresented: $showNotInterestedSuccess) {
                Button("OK") { }
            } message: {
                Text("We'll show you fewer posts like this.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
    }
    
    var body: some View {
        cardWithAlerts
            .pressableCard(scale: 0.985)   // A) Subtle press-down on the whole card
            .onAppear {
                guard !cardAppeared else { return }
                withAnimation { cardAppeared = true }
            }
            .sheet(isPresented: $showBereanSheet) {
                BereanAIAssistantView(initialQuery: bereanInitialQuery)
            }
            .sheet(isPresented: Binding(
                get: { BereanLiveActivityService.shared.showFallbackSheet },
                set: { BereanLiveActivityService.shared.showFallbackSheet = $0 }
            )) {
                BereanFallbackSheet()
            }
            .task(id: content) {
                await detectAndTranslatePost()
            }
    }
    
    // MARK: - Translation Logic

    /// Called on appear to detect language and set initial translation UI state.
    private func detectAndTranslatePost() async {
        guard !content.isEmpty else { return }

        // Detect language on-device (instant, private)
        let detection = await newTranslationService.detectLanguage(content)
        guard detection.isReliable else { return }

        detectedLanguage = detection.languageCode

        let settings = TranslationSettingsManager.shared
        let postId = post?.firestoreId ?? "unknown"

        // Check if we should auto-translate or just offer a button
        if settings.shouldAutoTranslate(detectedLang: detection.languageCode, contentType: .post) {
            await triggerTranslation()
        } else if settings.shouldOfferTranslation(detectedLang: detection.languageCode, contentType: .post) {
            translationUIState = .available
        } else {
            translationUIState = .notNeeded
        }
        _ = postId // suppress unused warning
    }

    /// Manually or automatically trigger translation for this post.
    private func triggerTranslation() async {
        guard translationUIState != .loading else { return }

        let postId = post?.firestoreId ?? UUID().uuidString
        let visibility = post?.visibility

        // Determine if content is public (affects caching tier)
        let isPublic: Bool
        switch visibility {
        case .everyone: isPublic = true
        case .followers, .community: isPublic = false
        case .none: isPublic = true
        }

        translationUIState = .loading

        let result = await newTranslationService.translate(
            text: content,
            contentType: .post,
            contentId: postId,
            surface: .feed,
            isPublicContent: isPublic
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            translationUIState = result
            if let translated = result.translatedText {
                translatedContent = translated
                showTranslatedContent = true
            }
        }
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
            // Moderation status banner — only visible to post author
            if isUserPost, let post = post {
                if post.flaggedForReview {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Under review")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.08))
                } else if post.removed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("Removed — violated community guidelines")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                }
            }

            // Header with author info and menu
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tap on header opens post detail — C) tap-guard
                    guard NavigationGuard.shared.shouldNavigate() else { return }
                    showPostDetail = true
                }
                .offset(y: cardAppeared ? 0 : 18)
                .opacity(cardAppeared ? 1 : 0)
                .blur(radius: cardAppeared ? 0 : 4)
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.0), value: cardAppeared)
            
            // Post content with mention support
            VStack(alignment: .leading, spacing: 8) {
                MentionTextView(
                    text: showTranslatedContent ? (translatedContent ?? content) : content,
                    mentions: post?.mentions,
                    font: .custom("OpenSans-Regular", size: 16),
                    fontSize: 16,
                    lineSpacing: 6
                ) { mention in
                    guard NavigationGuard.shared.shouldNavigate() else { return }
                    tappedMentionUserId = mention.userId
                    showMentionedUserProfile = true
                    HapticManager.impact(style: .light)
                }
                .foregroundStyle(.primary)
                // Fix: Constrain text to available width so long unbreakable words don't overflow
                .frame(maxWidth: .infinity, alignment: .leading)
                // P1-B FIX: Read expansion state from the service (survives scroll recycle)
                .lineLimit(interactionsService.isExpanded(stablePostId) ? nil : 10)
                .frame(maxHeight: interactionsService.isExpanded(stablePostId) ? nil : 400)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tap on content opens post detail — C) tap-guard
                    guard NavigationGuard.shared.shouldNavigate() else { return }
                    showPostDetail = true
                }

                // Show More button for long content
                if !interactionsService.isExpanded(stablePostId) && content.count > 300 {
                    Button {
                        HapticManager.impact(style: .light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            interactionsService.toggleExpanded(stablePostId)
                        }
                    } label: {
                        Text("Show more")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .offset(y: cardAppeared ? 0 : 18)
            .opacity(cardAppeared ? 1 : 0)
            .blur(radius: cardAppeared ? 0 : 4)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.12), value: cardAppeared)

            // Translation affordance — driven by translationUIState state machine
            // Shows: "See Translation" | loading chip | "Translated from X / View original" | error
            if shouldShowTranslationAffordance {
                translationToggleButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            
            // ✅ Display post images if available
            if let post = post, let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                PostImagesView(imageURLs: imageURLs)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            // ✅ Church Note Preview (if post contains a church note)
            if let post = post, let churchNoteId = post.churchNoteId {
                churchNotePreview(churchNoteId: churchNoteId)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            // ✅ Link / Verse Preview Card if post has a link
            if let post = post,
               let linkURLString = post.linkURL,
               !linkURLString.isEmpty,
               let linkURL = URL(string: linkURLString) {
                // Reconstruct metadata from post fields (prefer cached metadata)
                let cachedMeta = LinkPreviewService.shared.getCached(for: linkURL)
                let meta = cachedMeta ?? LinkPreviewMetadata(
                    url: linkURL,
                    previewType: post.linkPreviewType == "verse" ? .verse : .link,
                    title: post.linkPreviewTitle,
                    description: post.linkPreviewDescription,
                    imageURL: post.linkPreviewImageURL.flatMap { URL(string: $0) },
                    siteName: post.linkPreviewSiteName,
                    verseReference: post.verseReference,
                    verseText: post.verseText
                )
                FeedLinkPreviewCard(url: linkURL, metadata: meta)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            
            // Repost indicator if this is a repost.
            // Fall back to authorName if originalAuthorName is absent (older posts).
            if let post = post, post.isRepost {
                let originalAuthor = post.originalAuthorName ?? post.authorName
                repostIndicator(originalAuthor: originalAuthor)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            
            // Interaction buttons (no divider)
            interactionButtons
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .offset(y: cardAppeared ? 0 : 18)
                .opacity(cardAppeared ? 1 : 0)
                .blur(radius: cardAppeared ? 0 : 4)
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.36), value: cardAppeared)
        }
        .background(
            ZStack {
                // Swipe action indicators
                if abs(swipeOffset) > 20 {
                    HStack {
                        if swipeDirection == .right {
                            // Like/Amen/Pray indicator on left
                            swipeIndicator(
                                icon: category == .openTable ? "lightbulb.fill" : (category == .prayer ? "hands.sparkles.fill" : "hands.clap.fill"),
                                color: category == .openTable ? .yellow : (category == .prayer ? .black : .blue),
                                text: category == .openTable ? "Light" : (category == .prayer ? "Pray" : "Amen")
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
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }
        )
        .offset(x: swipeOffset)
        // FIX: Use .simultaneousGesture so the parent ScrollView keeps priority for vertical scrolling
        // Direction guards (3x horizontal:vertical ratio) prevent accidental horizontal triggers
        .simultaneousGesture(
            DragGesture(minimumDistance: 30) // Increased from 20 to reduce false triggers
                .onChanged { value in
                    // Only respond to predominantly horizontal swipes
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Require horizontal movement to be significantly more than vertical
                    // This allows vertical scrolling to work normally
                    guard horizontalAmount > verticalAmount * 3 else { // Increased from 2x to 3x
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
                        
                        // Reset with animation
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
                    } else if swipeDirection == .left && abs(swipeOffset) > threshold {
                        // Trigger comment action - delay reset to allow sheet to present
                        triggerSwipeCommentAction()
                        
                        // Small delay before reset to ensure sheet presents properly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                swipeOffset = 0
                                swipeDirection = .none
                            }
                        }
                    } else {
                        // Reset with animation if threshold not met
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
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
        // P0 PERF FIX: Removed nested animation - scale effect updates implicitly with swipeOffset
        // The parent .offset(x: swipeOffset) already animates, no need for duplicate animation here
        .scaleEffect(min(Double(abs(swipeOffset)) / 60.0, 1.2))
    }
    
    private func triggerSwipeLikeAction() {
        // Prevent users from liking their own posts
        guard !isUserPost else {
            HapticManager.notification(type: .warning)
            dlog("⚠️ Users cannot like their own posts")
            return
        }

        // Haptic fires inside each toggle function now (at optimistic update time)
        if category == .openTable {
            // Toggle lightbulb
            toggleLightbulb()
        } else if category == .prayer {
            // Toggle praying
            togglePraying()
        } else {
            // Toggle amen
            toggleAmen()
        }
    }
    
    private func triggerSwipeCommentAction() {
        HapticManager.impact(style: .light)
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
                HapticManager.impact(style: .light)
                showChurchNoteDetail = true
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
                dlog("⚠️ Church note reference exists but document not found: \(id.prefix(8))")
                #endif
                return
            }

            await MainActor.run {
                churchNote = note
            }
        } catch {
            // Network or parsing error - only log in debug mode
            #if DEBUG
            dlog("⚠️ Error loading church note \(id.prefix(8)): \(error.localizedDescription)")
            #endif
        }
    }

    private var interactionButtons: some View {
        HStack(spacing: 16) {
            // 1. Lightbulb (OpenTable) / Praying hands (Prayer) / Amen clap (other)
            if category == .openTable {
                circularInteractionButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: nil,
                    isActive: hasLitLightbulb,
                    activeColor: .black,
                    disabled: isUserPost
                ) {
                    if !isUserPost { toggleLightbulb() }
                }
            } else if category == .prayer {
                circularInteractionButton(
                    icon: isPraying ? "hands.sparkles.fill" : "hands.sparkles",
                    count: prayingNowCount > 0 ? prayingNowCount : nil,
                    isActive: isPraying,
                    activeColor: .black,
                    disabled: false
                ) {
                    togglePraying()
                }
            } else {
                circularInteractionButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: nil,
                    isActive: hasSaidAmen,
                    activeColor: .black,
                    disabled: isUserPost
                ) {
                    if !isUserPost { toggleAmen() }
                }
            }

            // 2. Comment — illuminates when current user has commented
            circularInteractionButton(
                icon: hasCommented ? "bubble.fill" : "bubble",
                count: commentCount > 0 ? commentCount : nil,
                isActive: hasCommented,
                activeColor: .black,
                disabled: false,
                enableBounce: false,
                accessibilityLabel: "Comment"
            ) {
                showCommentsSheet = true
            }

            // 3. Repost (repeat — illuminates when active)
            circularInteractionButton(
                icon: "repeat",
                count: nil,
                isActive: hasReposted,
                activeColor: .black,
                disabled: isUserPost,  // only disable for own posts; in-flight guard is inside toggleRepost
                accessibilityLabel: hasReposted ? "Remove repost" : "Repost"
            ) {
                if !isUserPost { toggleRepost() }
            }
            .shakeOnError(repostShakeError)

            // 4. Bookmark (next to repost)
            circularInteractionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                count: nil,
                isActive: isSaved,
                activeColor: .black,
                disabled: false,  // in-flight guard is inside toggleSave; always show press feedback
                enableBounce: false,
                accessibilityLabel: isSaved ? "Remove bookmark" : "Bookmark post"
            ) {
                toggleSave()
            }
            .shakeOnError(saveShakeError)

            Spacer()

            // 5. Berean AI sparkle (far right, testimonies + OpenTable + prayer)
            if category == .testimonies || category == .openTable || category == .prayer {
                AISparkleSearchButton {
                    HapticManager.impact(style: .light)
                    // Launch Berean Live Activity (Dynamic Island) or fallback sheet
                    if let post = post {
                        BereanLiveActivityService.shared.startActivity(for: post)
                    } else {
                        showBereanSheet = true
                    }
                }
                .frame(width: 20, height: 20)
            }
        }
    }
    
    // MARK: - Minimal Outline/Filled Reaction Button (Instagram/Threads Style)
    
    private func circularInteractionButton(
        icon: String,
        count: Int?,
        isActive: Bool,
        activeColor: Color,
        disabled: Bool,
        enableBounce: Bool = true,
        // P2-B FIX: Accessibility label so VoiceOver announces the action rather than
        // reading the raw SF Symbol name (e.g. "repeat" -> "Repost" / "Remove repost").
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // Threads-style: small, uniform icons; filled/bold weight when active
            Image(systemName: icon)
                .font(.system(size: 17, weight: isActive ? .semibold : .thin))
                .foregroundStyle(isActive ? Color.black : Color.black.opacity(0.55))
                .contentTransition(.identity)  // instant swap — spring handles the visual transition
                // E) Reaction pop/dip on toggle — only when bounce is enabled
                .reactionPop(isActive: enableBounce ? isActive : false)
        }
        .buttonStyle(MinimalReactionButtonStyle(isActive: isActive))
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
        // Fast spring so icon color/weight change feels instant on tap
        .animation(.spring(response: 0.12, dampingFraction: 0.75), value: isActive)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
    
    private var prayingNowButton: some View {
        Button {
            togglePraying()
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    // Glow effect when praying
                    if isPraying {
                        // P1 FIX: Reduced blur for performance (6px -> 3px)
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                            .blur(radius: 3)
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
        .buttonStyle(.instantFeedback)  // ✅ P0 FIX: INSTANT touch-down feedback
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
            dlog("ℹ️ Cannot open profile for own post")
            return
        }
        // Dedicated profile debounce — independent of shared NavigationGuard
        let now = Date()
        guard now.timeIntervalSince(lastProfileNavDate) > 0.35 else { return }
        lastProfileNavDate = now
        HapticManager.impact(style: .light)
        showUserProfile = true
        dlog("👤 Opening profile for: \(authorName) (ID: \(post.authorId))")
    }
    
    /// Check if post can be edited (within 30 minutes of creation)
    private func canEditPost(_ post: Post) -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60) // 30 minutes = 1800 seconds
        return post.createdAt >= thirtyMinutesAgo
    }
    
    // REMOVED: fetchLatestProfileImage() - P0-2 Performance Fix
    // Profile images now come pre-populated from PostsManager migration
    // This eliminates N Firestore reads (where N = number of posts on screen)
    // Performance improvement: 2x faster feed loading
    
    private func toggleLightbulb() {
        // P0 FIX: Check in-flight flag BEFORE processing
        guard !isLightbulbToggleInFlight else {
            logDebug("⚠️ Lightbulb toggle already in progress", category: "LIGHTBULB")
            return
        }
        
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

        // Haptic + optimistic update fire immediately — before the network round-trip
        HapticManager.impact(style: .medium)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            hasLitLightbulb.toggle()
            isLightbulbAnimating = true
        }

        logDebug("  OPTIMISTIC: hasLitLightbulb=\(hasLitLightbulb), count=\(lightbulbCount)", category: "LIGHTBULB")

        Task { @MainActor in
            // Guarantee in-flight flag is cleared when this task exits, regardless of outcome
            defer { isLightbulbToggleInFlight = false }

            do {
                logDebug("📤 Calling PostInteractionsService.toggleLightbulb...", category: "LIGHTBULB")

                // P0 FIX: Use stable ID for toggle
                // Call Realtime Database to toggle lightbulb
                // The count will be updated by the real-time observer
                let stableId = post.firebaseId ?? post.id.uuidString
                try await interactionsService.toggleLightbulb(postId: stableId)

                logDebug("✅ Backend write SUCCESS", category: "LIGHTBULB")
                logDebug("  AFTER: hasLitLightbulb=\(hasLitLightbulb), count=\(lightbulbCount)", category: "LIGHTBULB")
                logDebug("  Note: Count will update via real-time observer", category: "LIGHTBULB")

                // Reset animation state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isLightbulbAnimating = false
                }

            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "LIGHTBULB")
                logDebug("  ROLLBACK: Reverting to hasLitLightbulb=\(previousState)", category: "LIGHTBULB")

                // Revert optimistic update on error
                withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                    hasLitLightbulb = previousState
                }
                isLightbulbAnimating = false
                lightbulbShakeError.toggle()
                HapticManager.notification(type: .error)

                logDebug("  AFTER ROLLBACK: hasLitLightbulb=\(hasLitLightbulb)", category: "LIGHTBULB")
            }
        }
    }
    
    private func toggleAmen() {
        // P0 FIX: Prevent duplicate amen toggles during in-flight operation
        guard !isAmenToggleInFlight else {
            logDebug("⚠️ Amen toggle already in progress", category: "AMEN")
            return
        }
        
        guard let post = post else {
            logDebug("❌ No post object available", category: "AMEN")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "AMEN")
            return
        }
        
        isAmenToggleInFlight = true

        // Store previous state for rollback
        let previousState = hasSaidAmen
        let previousCount = amenCount

        logDebug("USER_ACTION: toggleAmen() called", category: "AMEN")
        logDebug("  postId: \(post.firestoreId)", category: "AMEN")
        logDebug("  currentUserId: \(currentUserId)", category: "AMEN")
        logDebug("  BEFORE: hasSaidAmen=\(previousState), count=\(previousCount)", category: "AMEN")
        logDebug("  Source: Local @State", category: "AMEN")

        // Haptic + optimistic update fire immediately — before the network round-trip
        HapticManager.notification(type: .success)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            hasSaidAmen.toggle()
        }

        logDebug("  OPTIMISTIC: hasSaidAmen=\(hasSaidAmen), count=\(amenCount)", category: "AMEN")

        Task { @MainActor in
            // Guarantee in-flight flag is cleared when this task exits, regardless of outcome
            defer { isAmenToggleInFlight = false }
            do {
                logDebug("📤 Calling PostInteractionsService.toggleAmen...", category: "AMEN")

                // P0 FIX: Use stable ID for toggle
                // Call Realtime Database to toggle amen
                // The count will be updated by the real-time observer
                let stableId = post.firebaseId ?? post.id.uuidString
                try await interactionsService.toggleAmen(postId: stableId)

                logDebug("✅ Backend write SUCCESS", category: "AMEN")
                logDebug("  AFTER: hasSaidAmen=\(hasSaidAmen), count=\(amenCount)", category: "AMEN")
                logDebug("  Note: Count will update via real-time observer", category: "AMEN")

                // Record engagement for ML training (only on amen, not un-amen)
                if hasSaidAmen, let userId = Auth.auth().currentUser?.uid {
                    let event = EngagementEvent(
                        userId: userId,
                        postId: stableId,
                        eventType: .reaction,
                        timestamp: Date(),
                        duration: nil,
                        metadata: nil
                    )
                    try? await VertexAIPersonalizationService.shared.recordEngagement(event)
                }

            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "AMEN")
                logDebug("  ROLLBACK: Reverting to hasSaidAmen=\(previousState)", category: "AMEN")

                // Revert optimistic update on error
                withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                    hasSaidAmen = previousState
                }
                amenShakeError.toggle()
                HapticManager.notification(type: .error)

                logDebug("  AFTER ROLLBACK: hasSaidAmen=\(hasSaidAmen)", category: "AMEN")
            }
        }
    }
    
    // P0 FIX: openComments() removed - users now tap the post to open PostDetailView with comments

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
        
        dlog("🗑️ Post deleted - notification sent")
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
        
        // P0 FIX: Use defer instead of delayed reset to prevent missed cleanup
        defer {
            Task { @MainActor in
                // Wait for animation to complete before resetting flag
                try? await Task.sleep(for: .seconds(0.6))
                isRepostToggleInFlight = false
            }
        }
        
        // Haptic + optimistic update fire immediately — before the network round-trip
        HapticManager.notification(type: .success)
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
                }

                logDebug("  AFTER: hasReposted=\(hasReposted), count=\(repostCount)", category: "REPOST")

                if isReposted {
                    postsManager.repostToProfile(originalPost: post)
                    NotificationCenter.default.post(
                        name: Notification.Name("postReposted"),
                        object: nil,
                        userInfo: ["post": post]
                    )
                    logDebug("✅ Reposted to profile", category: "REPOST")
                } else {
                    postsManager.removeRepost(postId: post.id, firestoreId: post.firestoreId)
                    NotificationCenter.default.post(
                        name: Notification.Name("repostRemoved"),
                        object: nil,
                        userInfo: ["postId": post.id]
                    )
                    logDebug("✅ Repost removed from profile", category: "REPOST")
                }

            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "REPOST")
                logDebug("  ROLLBACK: Reverting to hasReposted=\(previousState)", category: "REPOST")

                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        hasReposted = previousState
                    }
                    repostShakeError.toggle()
                    errorMessage = "Failed to toggle repost. Please try again."
                    showErrorAlert = true
                }
                HapticManager.notification(type: .error)

                logDebug("  AFTER ROLLBACK: hasReposted=\(hasReposted)", category: "REPOST")
            }
        }
    }
    

    private func sharePost() {
        HapticManager.impact(style: .light)
        showShareSheet = true
        
        // Record share engagement for ML training
        if let post = post, let userId = Auth.auth().currentUser?.uid {
            let postId = post.firebaseId ?? post.id.uuidString
            Task {
                let event = EngagementEvent(
                    userId: userId,
                    postId: postId,
                    eventType: .share,
                    timestamp: Date(),
                    duration: nil,
                    metadata: nil
                )
                try? await VertexAIPersonalizationService.shared.recordEngagement(event)
            }
        }
    }
    
    private func copyLink() {
        guard let post = post else { return }

        // ✅ Generate deep link URL for production
        let deepLink = "amenapp://post/\(post.id.uuidString)"

        UIPasteboard.general.string = deepLink
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Link copied")
        dlog("🔗 Deep link copied to clipboard: \(deepLink)")
    }
    
    private func copyPostText() {
        UIPasteboard.general.string = content
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Text copied")
        dlog("📋 Post text copied to clipboard")
    }
    
    private func muteAuthor() {
        guard let post = post else { return }
        let authorId = post.authorId
        
        Task {
            do {
                try await moderationService.muteUser(userId: authorId)
                dlog("🔇 Muted \(authorName)")
                
                await MainActor.run {
                    showMuteSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to mute: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to mute user. Please try again."
                    showErrorAlert = true
                    HapticManager.notification(type: .error)
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
                dlog("🚫 Blocked \(authorName)")
                
                await MainActor.run {
                    showBlockSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to block: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to block user. Please try again."
                    showErrorAlert = true
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
    
    private func markNotInterested() {
        guard let post = post else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let db = Firestore.firestore()
                
                // Store "not interested" feedback for personalization
                try await db.collection("users")
                    .document(currentUserId)
                    .collection("notInterested")
                    .document(post.firestoreId)
                    .setData([
                        "postId": post.firestoreId,
                        "postCategory": post.category.rawValue,
                        "postAuthorId": post.authorId,
                        "timestamp": FieldValue.serverTimestamp()
                    ])
                
                dlog("👎 Marked post as not interested: \(post.firestoreId)")
                
                await MainActor.run {
                    showNotInterestedSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to mark not interested: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to save feedback. Please try again."
                    showErrorAlert = true
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
    
    private func toggleSave() {
        // ✅ IDEMPOTENCY CHECK #1: Prevent saves already in flight
        guard !isSaveInFlight else {
            logDebug("⚠️ Save already in flight, ignoring", category: "SAVE")
            dlog("⚠️ [SAVE-GUARD-1] Blocked duplicate save attempt (already in flight)")
            return
        }
        
        guard let post = post else {
            logDebug("❌ No post object available", category: "SAVE")
            dlog("❌ [SAVE-GUARD-2] No post object - cannot save")
            return
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            logDebug("❌ No current user ID", category: "SAVE")
            dlog("❌ [SAVE-GUARD-3] No current user - not authenticated")
            return
        }
        
        // ✅ IDEMPOTENCY CHECK #2: Debounce rapid taps (prevent saves within 300ms)
        if let lastTimestamp = lastSaveActionTimestamp {
            let timeSinceLastSave = Date().timeIntervalSince(lastTimestamp)
            if timeSinceLastSave < 0.3 {
                dlog("⚠️ [SAVE-GUARD-4] Debounced: \(Int(timeSinceLastSave * 1000))ms since last save (min 300ms)")
                return
            }
        }
        
        // ✅ Check network first
        guard AMENNetworkMonitor.shared.isConnected else {
            logDebug("📱 Offline - cannot save/unsave posts", category: "SAVE")
            dlog("📱 [SAVE-GUARD-5] Offline - save blocked")
            errorMessage = "You're offline. Please check your connection and try again."
            showErrorAlert = true
            
            HapticManager.notification(type: .warning)
            return
        }

        // Record this save action
        saveActionCounter += 1
        lastSaveActionTimestamp = Date()
        isSaveInFlight = true

        // ✅ DESYNC FIX: If local isSaved and global savedPostIds disagree, trust the
        // global set (it's the authoritative source from Firestore/RTDB).
        // This prevents the wrong operation when the local state drifted.
        let globalIsSaved = savedPostsService.savedPostIds.contains(post.firestoreId)
        if isSaved != globalIsSaved {
            logDebug("  ⚠️ DESYNC DETECTED: isSaved=\(isSaved) but savedPostIds.contains=\(globalIsSaved). Correcting local state.", category: "SAVE")
            isSaved = globalIsSaved
        }

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

        // Haptic + optimistic update fire immediately — before the network round-trip
        HapticManager.impact(style: .medium)
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
                ToastManager.shared.success(isSavedNow ? "Post saved" : "Post unsaved")
                
                // ✅ Post notification with full Post object for ProfileView
                if isSavedNow {
                    NotificationCenter.default.post(
                        name: Notification.Name("postSaved"),
                        object: nil,
                        userInfo: ["post": post]
                    )
                    logDebug("📬 Posted postSaved notification", category: "SAVE")
                    
                    // Record save engagement for ML training
                    if let userId = Auth.auth().currentUser?.uid {
                        let event = EngagementEvent(
                            userId: userId,
                            postId: post.firestoreId,
                            eventType: .save,
                            timestamp: Date(),
                            duration: nil,
                            metadata: nil
                        )
                        try? await VertexAIPersonalizationService.shared.recordEngagement(event)
                    }
                } else {
                    NotificationCenter.default.post(
                        name: Notification.Name("postUnsaved"),
                        object: nil,
                        userInfo: ["postId": post.id]
                    )
                    logDebug("📬 Posted postUnsaved notification", category: "SAVE")
                }

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
                    saveShakeError.toggle() // H) Shake save/bookmark button
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func togglePraying() {
        dlog("🙏 togglePraying() called")
        
        guard let post = post else {
            dlog("❌ No post object available")
            return
        }
        
        guard category == .prayer else {
            dlog("⚠️ Not a prayer post")
            return
        }
        
        dlog("   - Post ID: \(post.firestoreId)")
        dlog("   - Current state: \(isPraying ? "praying" : "not praying")")
        
        // Store previous state for rollback
        let previousState = isPraying
        
        // Haptic + optimistic update fire immediately — before the network round-trip
        HapticManager.impact(style: .medium)
        withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
            isPraying.toggle()
        }

        let rtdb = RealtimeDatabaseManager.shared

        Task {
            let success: Bool

            if isPraying {
                success = await withCheckedContinuation { continuation in
                    rtdb.startPraying(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            } else {
                success = await withCheckedContinuation { continuation in
                    rtdb.stopPraying(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            }

            if success {
                dlog("✅ \(isPraying ? "Started" : "Stopped") praying for post")
            } else {
                dlog("❌ Failed to \(isPraying ? "start" : "stop") praying")
                await MainActor.run {
                    withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) {
                        isPraying = previousState
                    }
                    HapticManager.notification(type: .error)
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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Report Reasons
                    VStack(spacing: 12) {
                        ForEach(ReportReason.allCases) { reason in
                            ReportReasonCard(
                                reason: reason,
                                isSelected: selectedReason == reason
                            ) {
                                HapticManager.impact(style: .light)
                                selectedReason = reason
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    
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
                        .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
                    
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
                .padding(.horizontal, 16)
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
                
                dlog("✅ Report submitted successfully")
                
                await MainActor.run {
                    showSuccessAlert = true
                }
                
            } catch {
                dlog("❌ Failed to submit report: \(error)")
                
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
    @Binding var showPostDetail: Bool  // ✅ Shows full post detail view
    @Binding var showCommentsSheet: Bool  // ✅ Shows dedicated comments UI
    @Binding var showingDeleteAlert: Bool
    @Binding var showReportSheet: Bool
    @Binding var showChurchNoteDetail: Bool
    @Binding var churchNote: ChurchNote?
    @Binding var showMentionedUserProfile: Bool
    @Binding var tappedMentionUserId: String?

    @Binding var hasCommented: Bool

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
            // ✅ Mentioned user profile — tapping @username in post text
            .sheet(isPresented: $showMentionedUserProfile, onDismiss: {
                tappedMentionUserId = nil
            }) {
                if let uid = tappedMentionUserId {
                    UserProfileView(userId: uid, showsDismissButton: true)
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
                        // ✅ Show new share options sheet with "Send in Message" and "Share Externally"
                        PostShareOptionsSheet(post: post)
                    }
                }
            }
            // ✅ Full PostDetailView - shown when tapping header/content
            .sheet(isPresented: $showPostDetail) {
                if let post = post {
                    PostDetailView(post: post)
                }
            }
            // ✅ CommentsView - shown for comment button tap and swipe-to-comment
            .sheet(isPresented: $showCommentsSheet, onDismiss: {
                // Re-check if user has commented after dismissing the sheet
                if let post = post, let userId = Auth.auth().currentUser?.uid {
                    let postId = post.firestoreId
                    Task {
                        let ref = Database.database().reference()
                            .child("user_comments").child(userId)
                        let snapshot = try? await ref.getData()
                        if let children = snapshot?.children.allObjects as? [DataSnapshot] {
                            let didComment = children.contains {
                                ($0.childSnapshot(forPath: "postId").value as? String) == postId
                            }
                            await MainActor.run {
                                withAnimation(.spring(response: 0.12, dampingFraction: 0.75)) {
                                    hasCommented = didComment
                                }
                            }
                        }
                    }
                }
            }) {
                if let post = post {
                    CommentsView(post: post)
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
    // Not @ObservedObject — we don't want every card to re-render when ANY post is saved/unsaved.
    // State sync happens through the isSaved @Binding + isSaveInFlight guard.
    let savedPostsService: RealtimeSavedPostsService
    
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
    @Binding var isSaveInFlight: Bool
    @Binding var isLightbulbToggleInFlight: Bool
    @Binding var expectedLightbulbState: Bool
    @Binding var isRepostToggleInFlight: Bool
    @Binding var expectedRepostState: Bool
    @Binding var hasCommented: Bool
    
    @State private var hasCompletedInitialLoad = false
    
    // PERF: Single narrow value watched by ONE onChange — replaces 4 separate dictionary-level
    // observers. Each PostCard only re-evaluates its own 4 counts, not the full global dict.
    private struct PostCounts: Equatable {
        var lightbulbs: Int
        var amens: Int
        var comments: Int
        var reposts: Int
    }
    private var countsForThisPost: PostCounts {
        let id = post?.firebaseId ?? post?.id.uuidString ?? ""
        return PostCounts(
            lightbulbs: interactionsService.postLightbulbs[id] ?? lightbulbCount,
            amens:      interactionsService.postAmens[id]      ?? amenCount,
            comments:   interactionsService.postComments[id]   ?? commentCount,
            reposts:    interactionsService.postReposts[id]    ?? repostCount
        )
    }

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
            .task(priority: .userInitiated) { // P0 PERF FIX: Set explicit priority
                guard let post = post else { return }
                // P0 FIX: Use firebaseId if available, fallback to UUID for stable ID
                let postId = post.firebaseId ?? post.id.uuidString
                guard Auth.auth().currentUser?.uid != nil else { return }
                
                // P0 PERF FIX: Start observation WITHOUT blocking the main thread
                // This allows the PostCard to render immediately while interactions load in background
                interactionsService.observePostInteractions(postId: postId)
                
                // Record view engagement for ML training (fire-and-forget, low priority)
                if let userId = Auth.auth().currentUser?.uid {
                    Task(priority: .background) {
                        let event = EngagementEvent(
                            userId: userId,
                            postId: postId,
                            eventType: .view,
                            timestamp: Date(),
                            duration: nil,
                            metadata: nil
                        )
                        try? await VertexAIPersonalizationService.shared.recordEngagement(event)
                    }
                }
                
                // P0 PERF FIX: Removed cache wait loop - causes 150 tasks to poll simultaneously
                // InteractionsService publishes updates via Combine, so state syncs automatically
                // No need to block here - the UI will update reactively when cache loads
                
                // P0 PERF FIX: Load state synchronously from cache (no await)
                // This is instant and doesn't block scroll rendering
                await MainActor.run {
                    hasLitLightbulb = interactionsService.userLightbulbedPosts.contains(postId)
                    hasSaidAmen = interactionsService.userAmenedPosts.contains(postId)
                    if !isRepostToggleInFlight {
                        hasReposted = interactionsService.userRepostedPosts.contains(postId)
                    }
                }
                
                // Load hasCommented in background — checks RTDB user_comments index
                if let userId = Auth.auth().currentUser?.uid {
                    let firestoreId = post.firestoreId
                    Task(priority: .background) {
                        let ref = Database.database().reference()
                            .child("user_comments").child(userId)
                        if let snapshot = try? await ref.getData(),
                           let children = snapshot.children.allObjects as? [DataSnapshot] {
                            let didComment = children.contains {
                                ($0.childSnapshot(forPath: "postId").value as? String) == firestoreId
                            }
                            await MainActor.run { hasCommented = didComment }
                        }
                    }
                }
                
                // P0 PERF FIX: Load counts and saved status asynchronously in background
                // Don't block PostCard rendering - let .onChange handle updates
                Task(priority: .utility) {
                    let stableId = post.firebaseId ?? post.id.uuidString
                    let savedStatus = await checkSavedStatusSafely(postId: stableId)
                    let lightbulbs = await interactionsService.getLightbulbCount(postId: stableId)
                    let amens = await interactionsService.getAmenCount(postId: stableId)
                    let comments = await interactionsService.getCommentCount(postId: stableId)
                    let reposts = await interactionsService.getRepostCount(postId: stableId)
                    
                    await MainActor.run {
                        // Only apply saved status on the FIRST load. After that, the user's
                        // taps and the real-time listener own the state. Re-applying on every
                        // scroll-triggered task re-run caused the bookmark to flip by itself.
                        if !hasCompletedInitialLoad && !isSaveInFlight {
                            isSaved = savedStatus
                        }
                        lightbulbCount = lightbulbs
                        amenCount = amens
                        commentCount = comments
                        repostCount = reposts
                        hasCompletedInitialLoad = true
                    }
                    
                    // Prayer-specific state
                    if post.category == .prayer {
                        let praying = await checkIfPraying(postId: stableId)
                        await MainActor.run {
                            isPraying = praying
                        }
                        observePrayingCount(postId: stableId)
                    }
                }
            }
            .onDisappear {
                if let post = post {
                    // P0 FIX: Use stable ID for stop observing
                    let stableId = post.firebaseId ?? post.id.uuidString
                    interactionsService.stopObservingPost(postId: stableId)
                }
            }
            // PERF: Single observer on a narrow Equatable value keyed to THIS post only.
            // Previously 4 separate onChange(of: [String:Int]) handlers fired for EVERY
            // PostCard whenever any post's count changed — O(visible cards) re-renders
            // per interaction. Now only this card re-evaluates its own counts.
            .onChange(of: countsForThisPost) { _, counts in
                lightbulbCount = counts.lightbulbs
                amenCount      = counts.amens
                commentCount   = counts.comments
                repostCount    = counts.reposts
            }
            // ✅ Update lightbulb state when userLightbulbedPosts changes
            .onChange(of: isPostLightbulbed) { oldState, newState in
                guard post != nil else { return }
                guard oldState != newState else { return }
                
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                if isLightbulbToggleInFlight {
                    if newState == expectedLightbulbState {
                        if hasLitLightbulb != newState {
                            withAnimation(animation) {
                                hasLitLightbulb = newState
                            }
                        }
                        isLightbulbToggleInFlight = false
                    }
                    return
                }
                
                if hasLitLightbulb != newState {
                    withAnimation(animation) {
                        hasLitLightbulb = newState
                    }
                }
            }
            // ✅ Update amen state when userAmenedPosts changes
            .onChange(of: isPostAmened) { oldState, newState in
                guard post != nil else { return }
                guard oldState != newState else { return }
                
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                if hasSaidAmen != newState {
                    withAnimation(animation) {
                        hasSaidAmen = newState
                    }
                }
            }
            // ✅ Update repost state when userRepostedPosts changes (after initial load only)
            .onChange(of: isPostReposted) { oldState, newState in
                guard post != nil else { return }
                guard oldState != newState else { return }
                
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                
                if isRepostToggleInFlight {
                    if newState == expectedRepostState {
                        if hasReposted != newState {
                            withAnimation(animation) {
                                hasReposted = newState
                            }
                        }
                        isRepostToggleInFlight = false
                    }
                    return
                }
                
                if hasReposted != newState {
                    withAnimation(animation) {
                        hasReposted = newState
                    }
                }
            }
            // NOTE: We intentionally do NOT observe savedPostsService.savedPostIds here.
            // Observing the shared singleton would cause EVERY PostCard to re-render
            // (and animate its bookmark icon) whenever any user saves any post.
            // isSaved is kept correct by: (1) initial task load, (2) toggleSave() reconciliation.
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
            } withCancel: { _ in
                // Permission denied or network error — treat as not praying.
                continuation.resume(returning: false)
            }
        }
    }
    
    /// ✅ Check saved status with offline handling
    private func checkSavedStatusSafely(postId: String) async -> Bool {
        // Always use the authoritative in-memory set from RealtimeSavedPostsService.
        // The per-post RTDB getData() can return stale offline-cached data during the
        // brief DISCONNECTED→CONNECTED window on startup, causing all bookmarks to
        // illuminate incorrectly. The savedPostIds set is populated by fetchSavedPostIds()
        // which does a single authoritative read of the full saved set.
        return savedPostsService.isPostSavedSync(postId: postId)
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

// MARK: - Edit Comment Sheet

struct EditCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commentService = CommentService.shared
    
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
                .padding(.horizontal, 16)
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
                    HapticManager.notification(type: .success)
                    dismiss()
                }

                dlog("✅ Comment updated successfully")

            } catch {
                dlog("❌ Failed to update comment: \(error)")
                await MainActor.run {
                    isSaving = false
                    HapticManager.notification(type: .error)
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
            dlog("❌ Invalid URL: \(url)")
            return
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Open in Safari
        UIApplication.shared.open(url)
        dlog("✅ Opening URL: \(url)")
    }
}

// MARK: - Minimal Reaction Button Style (Instagram/Threads Style)
/// Custom button style for minimal outline/filled reactions.
/// Press-down: immediate tight spring. Release: crisp snap back via Motion presets.
struct MinimalReactionButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(
                Motion.adaptive(
                    configuration.isPressed ? Motion.springPress : Motion.springRelease
                ),
                value: configuration.isPressed
            )
    }
}



