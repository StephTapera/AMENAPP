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

struct PostCard: View {
    let post: Post?
    let authorName: String
    let timeAgo: String
    let content: String
    let category: PostCardCategory
    let topicTag: String?
    let isUserPost: Bool // Track if this is the current user's post
    
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var followService = FollowService.shared
    @StateObject private var moderationService = ModerationService.shared
    @StateObject private var interactionsService = PostInteractionsService.shared
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
    @State private var showRepostOptions = false
    
    // Prayer activity
    @State private var isPraying = false
    @State private var prayingNowCount = 0
    
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
    
    // MARK: - Extracted Views
    
    private var avatarButton: some View {
        Button {
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
            avatarCircle
            
            // User initials - black text on white/gray background
            Text(userInitials)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.black)
            
            // Follow button - only show if not user's post
            if !isUserPost {
                followButton
            }
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
            
            // Icon
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 11, weight: .bold))
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
            
            do {
                try await followService.toggleFollow(userId: authorId)
                
                // Update UI with animation
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing.toggle()
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(isFollowing ? .success : .warning)
                
                print("✅ Follow status changed: \(isFollowing ? "Following" : "Unfollowed")")
                
            } catch {
                print("❌ Follow error: \(error.localizedDescription)")
                
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
            repostToProfile()
        } label: {
            Label("Repost to Profile", systemImage: "arrow.triangle.2.circlepath")
        }
        
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
                // Optional: Show a message or haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                print("⚠️ Users cannot light their own posts")
            }
        } label: {
            lightbulbButtonLabel
        }
        .symbolEffect(.bounce, value: hasLitLightbulb)
        .disabled(isUserPost) // Disable for user's own posts
        .opacity(isUserPost ? 0.5 : 1.0) // Visual feedback that it's disabled
    }
    
    private var lightbulbButtonLabel: some View {
        HStack(spacing: 4) {
            lightbulbIcon
            
            Text("\(lightbulbCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(hasLitLightbulb ? Color.orange : Color.black.opacity(0.5))
                .contentTransition(.numericText())
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
                // Optional: Show a message or haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                print("⚠️ Users cannot amen their own posts")
            }
        } label: {
            amenButtonLabel
        }
        .symbolEffect(.bounce, value: hasSaidAmen)
        .disabled(isUserPost) // Disable for user's own posts
        .opacity(isUserPost ? 0.5 : 1.0) // Visual feedback that it's disabled
    }
    
    private var amenButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: hasSaidAmen ? "hands.clap.fill" : "hands.clap")
                .font(.system(size: 13, weight: .semibold))
            Text("\(amenCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(hasSaidAmen ? Color.black : Color.black.opacity(0.5))
        .contentTransition(.numericText())
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
            Text(authorName)
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.primary)
            
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
    }
    
    var body: some View {
        cardContent
            .modifier(PostCardSheetsModifier(
                showUserProfile: $showUserProfile,
                showingEditSheet: $showingEditSheet,
                showShareSheet: $showShareSheet,
                showCommentsSheet: $showCommentsSheet,
                showingDeleteAlert: $showingDeleteAlert,
                showReportSheet: $showReportSheet,
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
                prayingNowCount: $prayingNowCount
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
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with author info and menu
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Post content
            Text(content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
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
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
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
    
    private var interactionButtons: some View {
        HStack(spacing: 16) {
            // Primary Action (Lightbulb/Amen)
            if category == .openTable {
                circularInteractionButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: lightbulbCount,
                    isActive: hasLitLightbulb,
                    activeColor: .orange,
                    disabled: isUserPost
                ) {
                    if !isUserPost { toggleLightbulb() }
                }
            } else {
                circularInteractionButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: amenCount,
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
            
            // Comment
            circularInteractionButton(
                icon: "bubble.left.fill",
                count: commentCount > 0 ? commentCount : nil,
                isActive: false,
                activeColor: .blue,
                disabled: false
            ) {
                openComments()
            }
            
            // Repost
            circularInteractionButton(
                icon: hasReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                count: repostCount > 0 ? repostCount : nil,
                isActive: hasReposted,
                activeColor: .green,
                disabled: isUserPost
            ) {
                if !isUserPost { showRepostOptions = true }
            }
            
            Spacer()
            
            // Bookmark (right aligned)
            circularInteractionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                count: nil,
                isActive: isSaved,
                activeColor: .orange,
                disabled: false
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Icon with black/white design
                ZStack {
                    // Background circle - black and white only
                    Circle()
                        .fill(isActive ? Color.black : Color(.systemGray6))
                        .frame(width: 32, height: 32)
                    
                    // Icon - white when active, black when inactive
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? Color.white : Color.black)
                }
                
                // Count label next to icon (Threads style)
                if let count = count {
                    Text("\(count)")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(Color.primary)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .symbolEffect(.bounce, value: isActive)
        .opacity(disabled ? 0.4 : 1.0)
    }
    
    private var commentButton: some View {
        Button {
            openComments()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(commentCount)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
            }
            .foregroundStyle(Color.black.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var repostButton: some View {
        Button {
            // Prevent users from reposting their own posts
            if !isUserPost {
                showRepostOptions = true
            } else {
                // Show feedback that you can't repost your own post
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                print("⚠️ Users cannot repost their own posts")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasReposted ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath")
                    .font(.system(size: 12, weight: .semibold))
                if repostCount > 0 {
                    Text("\(repostCount)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(hasReposted ? Color.green : Color.black.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(hasReposted ? Color.green.opacity(0.1) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(hasReposted ? Color.green.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
        .symbolEffect(.bounce, value: hasReposted)
        .disabled(isUserPost)
        .opacity(isUserPost ? 0.5 : 1.0)
        .confirmationDialog("Repost Options", isPresented: $showRepostOptions) {
            if hasReposted {
                Button("Remove Repost", role: .destructive) {
                    removeRepost()
                }
            } else {
                Button("Repost to Your Profile") {
                    repostToProfile()
                }
                Button("Quote Repost (Coming Soon)", role: .cancel) {
                    // Future feature: Add your own comment
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if hasReposted {
                Text("This post is currently on your profile")
            } else {
                Text("Share this post with your followers")
            }
        }
    }
    
    private var saveButton: some View {
        Button {
            toggleSave()
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSaved ? Color.orange : Color.black.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSaved ? Color.orange.opacity(0.1) : Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(isSaved ? Color.orange.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
                )
        }
        .symbolEffect(.bounce, value: isSaved)
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
        https://amenapp.com/post/\(post.id.uuidString)
        """
    }
    
    // MARK: - Actions
    
    /// Check if post can be edited (within 30 minutes of creation)
    private func canEditPost(_ post: Post) -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60) // 30 minutes = 1800 seconds
        return post.createdAt >= thirtyMinutesAgo
    }
    
    private func toggleLightbulb() {
        print("💡 toggleLightbulb() called")
        
        guard let post = post else {
            print("❌ No post object available")
            return
        }
        
        print("   - Post ID: \(post.id.uuidString)")
        print("   - Current state: \(hasLitLightbulb ? "lit" : "unlit")")
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            hasLitLightbulb.toggle()
            isLightbulbAnimating = true
        }
        
        Task {
            do {
                print("📤 Calling PostInteractionsService.toggleLightbulb...")
                
                // Call Realtime Database to toggle lightbulb
                // The count will be updated by the real-time observer
                try await interactionsService.toggleLightbulb(postId: post.id.uuidString)
                
                print("✅ Lightbulb toggled successfully")
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                // Reset animation state
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isLightbulbAnimating = false
                    }
                }
                
            } catch {
                print("❌ Failed to toggle lightbulb: \(error)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    withAnimation {
                        hasLitLightbulb.toggle()
                    }
                    isLightbulbAnimating = false
                }
            }
        }
    }
    
    private func toggleAmen() {
        print("🙏 toggleAmen() called")
        
        guard let post = post else {
            print("❌ No post object available")
            return
        }
        
        print("   - Post ID: \(post.id.uuidString)")
        print("   - Current state: \(hasSaidAmen ? "amened" : "not amened")")
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasSaidAmen.toggle()
        }
        
        Task {
            do {
                print("📤 Calling PostInteractionsService.toggleAmen...")
                
                // Call Realtime Database to toggle amen
                // The count will be updated by the real-time observer
                try await interactionsService.toggleAmen(postId: post.id.uuidString)
                
                print("✅ Amen toggled successfully")
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Failed to toggle amen: \(error)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    withAnimation {
                        hasSaidAmen.toggle()
                    }
                }
            }
        }
    }
    
    private func openComments() {
        print("💬 openComments() called")
        
        if let post = post {
            print("   - Post ID: \(post.id.uuidString)")
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
    
    private func repostToProfile() {
        print("🔄 repostToProfile() called")
        
        guard let post = post else {
            print("❌ No post object available")
            return
        }
        
        print("   - Post ID: \(post.id.uuidString)")
        print("   - Original author: \(post.authorName)")
        
        Task {
            do {
                // Toggle repost in Realtime Database
                let isReposted = try await interactionsService.toggleRepost(postId: post.id.uuidString)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasReposted = isReposted
                    }
                }
                
                if isReposted {
                    // Also create repost via PostsManager for user's profile
                    postsManager.repostToProfile(originalPost: post)
                    
                    // Send notification for real-time ProfileView update
                    NotificationCenter.default.post(
                        name: Notification.Name("postReposted"),
                        object: nil,
                        userInfo: ["post": post]
                    )
                    
                    print("✅ Reposted to your profile")
                } else {
                    print("✅ Repost removed")
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Failed to toggle repost: \(error)")
                
                // Show error to user
                await MainActor.run {
                    // Could show an alert here
                }
            }
        }
    }
    
    private func removeRepost() {
        print("🗑️ removeRepost() called")
        
        guard let post = post else {
            print("❌ No post object available")
            return
        }
        
        Task {
            do {
                // Remove repost in Realtime Database
                _ = try await interactionsService.toggleRepost(postId: post.id.uuidString)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasReposted = false
                    }
                }
                
                // Remove from PostsManager
                // Note: You'll need to add a removeRepost method to PostsManager
                // postsManager.removeRepost(postId: post.id)
                
                // Send notification for real-time ProfileView update
                NotificationCenter.default.post(
                    name: Notification.Name("repostRemoved"),
                    object: nil,
                    userInfo: ["postId": post.id]
                )
                
                print("✅ Repost removed from your profile")
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Failed to remove repost: \(error)")
            }
        }
    }
    
    private func sharePost() {
        showShareSheet = true
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func copyLink() {
        // TODO: Generate and copy post link
        UIPasteboard.general.string = "https://amenapp.com/post/\(post?.id.uuidString ?? "")"
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔗 Link copied to clipboard")
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
        guard let post = post else { return }
        
        Task {
            do {
                if isSaved {
                    // Unsave the post
                    try await savedPostsService.unsavePost(postId: post.id.uuidString)
                    
                    // Update local state
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSaved = false
                    }
                    
                    print("🗑️ Post unsaved")
                } else {
                    // Save the post (pass post object for notification)
                    try await savedPostsService.savePost(postId: post.id.uuidString, post: post)
                    
                    // Update local state
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSaved = true
                    }
                    
                    print("💾 Post saved")
                }
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
            } catch {
                print("❌ Failed to toggle save: \(error)")
                
                // Show error to user
                await MainActor.run {
                    errorMessage = "Failed to save post. Please try again."
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
        
        print("   - Post ID: \(post.id.uuidString)")
        print("   - Current state: \(isPraying ? "praying" : "not praying")")
        
        // Optimistic UI update for the active state only (not the count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isPraying.toggle()
        }
        
        let rtdb = RealtimeDatabaseManager.shared
        
        if isPraying {
            // Start praying
            rtdb.startPraying(postId: post.id.uuidString) { success in
                if success {
                    print("✅ Started praying for post")
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } else {
                    print("❌ Failed to start praying")
                    // Revert on error
                    Task { @MainActor in
                        withAnimation {
                            isPraying = false
                        }
                    }
                }
            }
        } else {
            // Stop praying
            rtdb.stopPraying(postId: post.id.uuidString) { success in
                if success {
                    print("✅ Stopped praying for post")
                    
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } else {
                    print("❌ Failed to stop praying")
                    // Revert on error
                    Task { @MainActor in
                        withAnimation {
                            isPraying = true
                        }
                    }
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
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedReason = reason
                                }
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
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                    postId: post.id.uuidString,
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
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
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
    
    let post: Post?
    let authorName: String
    let category: PostCard.PostCardCategory
    let deleteAction: () -> Void
    
    func body(content: Content) -> some View {
        content
            // User Profile Sheet - Opens when tapping avatar or author name
            .sheet(isPresented: $showUserProfile) {
                if let post = post {
                    NavigationStack {
                        UserProfileView(userId: post.authorId)
                    }
                } else {
                    // Fallback if no post data
                    Text("Unable to load profile")
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let post = post {
                    EditPostSheet(post: post)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let post = post {
                    ShareSheet(items: [shareText(for: post)])
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
        https://amenapp.com/post/\(post.id.uuidString)
        """
    }
}

/// Handles all interaction observers and state updates
private struct PostCardInteractionsModifier: ViewModifier {
    let post: Post?
    let interactionsService: PostInteractionsService
    let savedPostsService: SavedPostsService
    
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
    
    func body(content: Content) -> some View {
        content
            .task {
                guard let post = post else { return }
                let postId = post.id.uuidString
                
                // Start observing real-time interactions
                interactionsService.observePostInteractions(postId: postId)
                
                // Load initial states
                hasLitLightbulb = await interactionsService.hasLitLightbulb(postId: postId)
                hasSaidAmen = await interactionsService.hasAmened(postId: postId)
                isSaved = await savedPostsService.isPostSaved(postId: postId)
                hasReposted = await interactionsService.hasReposted(postId: postId)
                
                // Check if currently praying (if prayer post)
                if post.category == .prayer {
                    isPraying = await checkIfPraying(postId: postId)
                }
                
                // Load counts
                lightbulbCount = await interactionsService.getLightbulbCount(postId: postId)
                amenCount = await interactionsService.getAmenCount(postId: postId)
                commentCount = await interactionsService.getCommentCount(postId: postId)
                repostCount = await interactionsService.getRepostCount(postId: postId)
                
                // Observe praying count for prayer posts
                if post.category == .prayer {
                    observePrayingCount(postId: postId)
                }
            }
            .onDisappear {
                if let post = post {
                    interactionsService.stopObservingPost(postId: post.id.uuidString)
                }
            }
            .onChange(of: interactionsService.postLightbulbs) { _, _ in
                if let post = post, let count = interactionsService.postLightbulbs[post.id.uuidString] {
                    lightbulbCount = count
                }
            }
            .onChange(of: interactionsService.postAmens) { _, _ in
                if let post = post, let count = interactionsService.postAmens[post.id.uuidString] {
                    amenCount = count
                }
            }
            .onChange(of: interactionsService.postComments) { _, _ in
                if let post = post, let count = interactionsService.postComments[post.id.uuidString] {
                    commentCount = count
                }
            }
            .onChange(of: interactionsService.postReposts) { _, _ in
                if let post = post, let count = interactionsService.postReposts[post.id.uuidString] {
                    repostCount = count
                }
            }
    }
    
    private func checkIfPraying(postId: String) async -> Bool {
        // Check if current user is praying for this post
        let rtdb = RealtimeDatabaseManager.shared
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
        commentService.comments[post.id.uuidString] ?? []
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
                commentService.startListening(to: post.id.uuidString)
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
            _ = try await commentService.fetchComments(for: post.id.uuidString)
            
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
                    postId: post.id.uuidString,
                    parentCommentId: replyingTo.id ?? "",
                    content: commentText
                )
            } else {
                // Submit as a top-level comment
                _ = try await commentService.addComment(
                    postId: post.id.uuidString,
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showReplies.toggle()
                        }
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
            hasLitLightbulb = await commentService.hasUserAmened(commentId: commentId)
            hasAmen = hasLitLightbulb // Same function for both
        }
    }
    
    // MARK: - Avatar View
    
    private var avatarView: some View {
        Group {
            if let profileImageURL = comment.authorProfileImageURL, !profileImageURL.isEmpty {
                AsyncImage(url: URL(string: profileImageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    default:
                        defaultAvatar
                    }
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
                
                do {
                    try await commentService.toggleAmen(commentId: commentId)
                    
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasLitLightbulb.toggle()
                            localLightbulbCount += hasLitLightbulb ? 1 : -1
                        }
                    }
                } catch {
                    print("❌ Failed to toggle lightbulb: \(error)")
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
        .symbolEffect(.bounce, value: hasLitLightbulb)
    }
    
    private var amenButton: some View {
        Button {
            Task {
                guard let commentId = comment.id else { return }
                
                do {
                    try await commentService.toggleAmen(commentId: commentId)
                    
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            hasAmen.toggle()
                            localAmenCount += hasAmen ? 1 : -1
                        }
                    }
                } catch {
                    print("❌ Failed to toggle amen: \(error)")
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

