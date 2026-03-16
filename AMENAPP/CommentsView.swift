//
//  CommentsView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  View for displaying and managing comments and replies on a post
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
// Combine removed — all patterns use async/await or NotificationCenter
import PhotosUI
import Vision

struct CommentsView: View {
    let post: Post
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var commentService = CommentService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    @ObservedObject private var userService = UserService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    
    // P0 FIX: Lazy load AI services - only initialize when needed, not on sheet open
    @State private var summarizationService: AIThreadSummarizationService?
    @State private var toneGuidanceService: AIToneGuidanceService?
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?

    // @mention picker state
    @State private var showMentionPicker = false
    @State private var mentionResults: [AlgoliaUser] = []
    @State private var mentionDebounceTask: Task<Void, Never>?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var isLoading = true  // P1 FIX: Start as true to show skeleton immediately
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isListening = false
    
    // P0-1 FIX: Prevent duplicate submissions
    @State private var isSubmittingComment = false
    @State private var currentUserProfileImageURL: String?
    @State private var currentUserInitials: String = "U"
    @State private var selectedUserId: String?
    @State private var showUserProfile = false
    @State private var pollingTask: Task<Void, Never>?  // ✅ Store polling task
    @State private var expandedThreads: Set<String> = []  // Track expanded reply threads
    @State private var newCommentIds: Set<String> = []  // Track newly added comments for animation
    // P1 PERF FIX: Cache expensive participant computation; rebuilt only when comments change.
    @State private var cachedTopParticipants: [ParticipantInfo] = []
    @State private var participantsRebuildTask: Task<Void, Never>? // Debounce rapid streaming updates
    @State private var scrollProxy: ScrollViewProxy?  // For smooth scrolling to replies
    @Namespace private var animationNamespace  // For matched geometry effects
    @State private var threadSummaries: [String: AIThreadSummarizationService.ThreadSummary] = [:]  // Cache thread summaries
    
    // ✅ Timestamp auto-refresh (updates "5m ago" -> "6m ago")
    @State private var currentTime = Date()
    
    // ✅ Emoji picker state
    @State private var showEmojiPicker = false
    
    // Photo upload state
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var commentPhotoData: Data?
    @State private var isModeratingPhoto = false
    @State private var photoModerationError: String?
    
    // Berean AI rewrite assist
    @State private var bereanSuggestion: String?
    @State private var isLoadingBereanSuggestion = false

    // Smart reply chips
    @State private var smartReplySuggestions: [String] = []
    @State private var isLoadingSmartReplies = false
    
    // Berean AI integration
    @State private var showBerean = false
    @State private var bereanQuery = ""

    // Slow mode cooldown: store end date; remaining time is computed from currentTime
    @State private var cooldownEndDate: Date?

    /// Seconds remaining in comment slow-mode cooldown (0 when inactive).
    private var cooldownRemaining: TimeInterval {
        guard let end = cooldownEndDate else { return 0 }
        let _ = currentTime // re-evaluate when the 1-second timer ticks
        return max(0, end.timeIntervalSince(Date()))
    }

    // Comment approval queue (pending comments waiting for post author review)
    @State private var pendingComments: [Comment] = []
    @State private var showPendingQueue = false

    // Community guidelines prompt (shown once on first comment)
    @State private var showCommentGuidelines = false
    @State private var pendingCommentSubmit = false

    // Proactive rate limit banner (shown immediately if daily limit already hit)
    @State private var rateLimitMessage: String? = nil
    
    // Use full firestoreId — RTDB listener paths use the same full UUID as Firestore.
    // PostDetailView uses post.firestoreId directly; CommentsView must match.
    private var postId: String { post.firestoreId }
    
    @FocusState private var isInputFocused: Bool
    
    // MARK: - Top Participants Algorithm

    /// Returns cached participants list. Rebuilt via rebuildTopParticipants() when commentsWithReplies changes.
    private var topParticipants: [ParticipantInfo] {
        cachedTopParticipants
    }

    /// Computes top 8-12 participants to show in avatar row.
    /// Priority: Post author > Recent commenters > Frequent commenters > High-reaction comments.
    /// Called only when commentsWithReplies changes (via .onChange), not on every render.
    private func rebuildTopParticipants() {
        var participants: [ParticipantInfo] = []
        var seenUserIds = Set<String>()

        // 1. Always include post author first
        if !post.authorId.isEmpty, !seenUserIds.contains(post.authorId) {
            participants.append(ParticipantInfo(
                userId: post.authorId,
                initials: post.authorInitials,
                profileImageURL: post.authorProfileImageURL,
                score: 1000 // Highest priority
            ))
            seenUserIds.insert(post.authorId)
        }
        
        // 2. Collect all unique commenters with scores
        var userScores: [String: (info: ParticipantInfo, score: Double)] = [:]
        
        for (index, commentWithReplies) in commentsWithReplies.enumerated() {
            let comment = commentWithReplies.comment
            
            if !seenUserIds.contains(comment.authorId) {
                let recencyScore = Double(commentsWithReplies.count - index) * 2.0 // Recent = higher
                let reactionScore = Double(comment.amenCount) * 1.5
                let replyScore = Double(comment.replyCount) * 1.0
                let totalScore = recencyScore + reactionScore + replyScore
                
                let info = ParticipantInfo(
                    userId: comment.authorId,
                    initials: comment.authorInitials,
                    profileImageURL: comment.authorProfileImageURL,
                    score: totalScore
                )
                
                if let existing = userScores[comment.authorId] {
                    // Update score if this comment has better metrics
                    if totalScore > existing.score {
                        userScores[comment.authorId] = (info, totalScore)
                    }
                } else {
                    userScores[comment.authorId] = (info, totalScore)
                }
            }
            
            // Also check replies
            for reply in commentWithReplies.replies {
                if !seenUserIds.contains(reply.authorId) {
                    let reactionScore = Double(reply.amenCount) * 1.5
                    let totalScore = reactionScore + 1.0 // Base score for replying
                    
                    let info = ParticipantInfo(
                        userId: reply.authorId,
                        initials: reply.authorInitials,
                        profileImageURL: reply.authorProfileImageURL,
                        score: totalScore
                    )
                    
                    if let existing = userScores[reply.authorId] {
                        if totalScore > existing.score {
                            userScores[reply.authorId] = (info, totalScore)
                        }
                    } else {
                        userScores[reply.authorId] = (info, totalScore)
                    }
                }
            }
        }
        
        // 3. Sort by score and add top participants
        let sortedUsers = userScores.values
            .sorted { $0.score > $1.score }
            .prefix(11) // Get top 11 (since author is already added)
        
        for userScore in sortedUsers {
            if !seenUserIds.contains(userScore.info.userId) {
                participants.append(userScore.info)
                seenUserIds.insert(userScore.info.userId)
            }
        }
        
        // Limit to 12 total avatars
        cachedTopParticipants = Array(participants.prefix(12))
    }

    // MARK: - Top Avatar Row (Premium iOS Style with Real-time Updates)
    
    private var topAvatarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -8) {  // Overlapping avatars for premium look
                ForEach(Array(topParticipants.enumerated()), id: \.element.id) { index, participant in
                    Button {
                        selectedUserId = participant.userId
                        showUserProfile = true
                        
                        // haptic
                        HapticManager.impact(style: .light)
                    } label: {
                        ZStack {
                            // Avatar with premium styling - using CachedAsyncImage for faster loading
                            if let imageURL = participant.profileImageURL,
                               !imageURL.isEmpty,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                } placeholder: {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.black, Color.black.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Text(participant.initials)
                                                .font(.custom("OpenSans-Bold", size: 15))
                                                .foregroundStyle(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                }
                                .id(participant.profileImageURL)  // Force refresh on URL change
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.black, Color.black.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Text(participant.initials)
                                            .font(.custom("OpenSans-Bold", size: 15))
                                            .foregroundStyle(.white)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color(.systemBackground), lineWidth: 3)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            
                            // Post author indicator (only for first avatar)
                            if index == 0 {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 16, height: 16)
                                            .overlay(
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(.white)
                                            )
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                                            )
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    }
                                }
                                .frame(width: 48, height: 48)
                            }
                        }
                    }
                    .zIndex(Double(topParticipants.count - index))  // Stack properly
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: topParticipants.count)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.systemBackground).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Header with Avatar Row
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // Avatar Row
            topAvatarRow
            
            Divider()
                .padding(.horizontal, 20)
            
            // Header with title and close button
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Comments")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    Text("\(commentsWithReplies.count) \(commentsWithReplies.count == 1 ? "comment" : "comments")")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()

                // Premium styled close button
                Button {
                    dismiss()
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                // Glass morphic background
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.8)
                                
                                // Subtle gradient overlay
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.15),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // Border with gradient
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.5
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Color(.systemBackground)
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            
            Divider()
        }
    }
    
    // MARK: - Pending Comment Approval Banner (visible to post author only)

    @ViewBuilder
    private var pendingApprovalBanner: some View {
        if (FirebaseManager.shared.currentUser?.uid ?? "") == post.authorId, !pendingComments.isEmpty {
            Button {
                showPendingQueue = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(pendingComments.count) comment\(pendingComments.count == 1 ? "" : "s") waiting for approval")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Tap to review")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            headerView

            pendingApprovalBanner
            
            // Comments List with ScrollViewReader for smooth scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isLoading {
                            // P0 FIX: Skeleton loading UI - shows immediately, no blocking
                            commentsSkeletonView
                                .transition(.opacity.combined(with: .scale))
                        } else if commentsWithReplies.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.black.opacity(0.3))
                                
                                Text("No comments yet")
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .foregroundStyle(.black.opacity(0.6))
                                
                                Text("Be the first to comment!")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.black.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            ForEach(Array(commentsWithReplies.enumerated()), id: \.element.id) { index, commentWithReplies in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Main Comment with animation
                                    PostCommentRow(
                                        comment: commentWithReplies.comment,
                                        isNew: newCommentIds.contains(commentWithReplies.comment.id ?? ""),
                                        onReply: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                replyingTo = commentWithReplies.comment
                                                isInputFocused = true
                                            }
                                            
                                            // Haptic feedback
                                            // haptic
                                            HapticManager.impact(style: .light)
                                        },
                                        onDelete: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                deleteComment(commentWithReplies.comment)
                                            }
                                        },
                                        onAmen: {
                                            toggleAmen(comment: commentWithReplies.comment)
                                        },
                                        onProfileTap: {
                                            selectedUserId = commentWithReplies.comment.authorId
                                            showUserProfile = true
                                        },
                                        onToggleThread: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                if expandedThreads.contains(commentWithReplies.comment.id ?? "") {
                                                    expandedThreads.remove(commentWithReplies.comment.id ?? "")
                                                } else {
                                                    expandedThreads.insert(commentWithReplies.comment.id ?? "")
                                                    
                                                    // Load thread summary for 10+ reply threads
                                                    if commentWithReplies.replies.count >= 10,
                                                       let commentId = commentWithReplies.comment.id,
                                                       threadSummaries[commentId] == nil {
                                                        Task {
                                                            do {
                                                                // P0 FIX: Use optional chaining for lazy-loaded service
                                                                if let summary = try await summarizationService?.getSummary(
                                                                    for: commentId,
                                                                    replies: commentWithReplies.replies
                                                                ) {
                                                                    await MainActor.run {
                                                                        threadSummaries[commentId] = summary
                                                                    }
                                                                }
                                                            } catch {
                                                                print("❌ [SUMMARY] Failed to load: \(error)")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        },
                                        isThreadExpanded: expandedThreads.contains(commentWithReplies.comment.id ?? ""),
                                        replyCount: commentWithReplies.replies.count,
                                        currentTime: currentTime
                                    )
                                    .id("\(commentWithReplies.comment.id ?? "")-main")
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                                    
                                    // Replies with expand/collapse animation
                                    if !commentWithReplies.replies.isEmpty && 
                                       expandedThreads.contains(commentWithReplies.comment.id ?? "") {
                                        VStack(spacing: 0) {
                                            // Thread Summary (for 10+ replies)
                                            if commentWithReplies.replies.count >= 10,
                                               let commentId = commentWithReplies.comment.id {
                                                if let summary = threadSummaries[commentId] {
                                                    ThreadSummaryView(summary: summary)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 12)
                                                        .transition(.move(edge: .top).combined(with: .opacity))
                                                } else if summarizationService?.isGeneratingSummary == true {
                                                    // Loading state
                                                    HStack(spacing: 12) {
                                                        ProgressView()
                                                            .tint(.secondary)
                                                        
                                                        Text("Generating thread summary...")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 16)
                                                    .transition(.move(edge: .top).combined(with: .opacity))
                                                }
                                            }
                                            
                                            ForEach(commentWithReplies.replies, id: \.stableId) { reply in
                                                HStack(spacing: 0) {
                                                    // Animated reply indicator line
                                                    Rectangle()
                                                        .fill(.black.opacity(0.1))
                                                        .frame(width: 2)
                                                        .padding(.leading, 28)
                                                        .transition(.scale(scale: 0.1, anchor: .top))
                                                    
                                                    PostCommentRow(
                                                        comment: reply,
                                                        isReply: true,
                                                        isNew: newCommentIds.contains(reply.id ?? ""),
                                                        onReply: {
                                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                                replyingTo = commentWithReplies.comment
                                                                isInputFocused = true
                                                            }
                                                            
                                                            // haptic
                                                            HapticManager.impact(style: .light)
                                                        },
                                                        onDelete: {
                                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                                deleteComment(reply)
                                                            }
                                                        },
                                                        onAmen: {
                                                            toggleAmen(comment: reply)
                                                        },
                                                        onProfileTap: {
                                                            selectedUserId = reply.authorId
                                                            showUserProfile = true
                                                        },
                                                        currentTime: currentTime
                                                    )
                                                }
                                                .id("\(reply.id ?? "")-reply")
                                                .transition(.asymmetric(
                                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)
                                                ))
                                            }
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .padding(.vertical, 8)
                                .id(commentWithReplies.comment.id ?? UUID().uuidString)
                                // B) Staggered cascade reveal — header at 0ms, body +40ms, capped at 200ms
                                .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.20)
                                
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
            
            Divider()
            
            // Input Area with Liquid Glass Buttons
            VStack(spacing: 0) {
                // Replying indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorUsername.hasPrefix("@") ? replyingTo.authorUsername : "@\(replyingTo.authorUsername)")")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                }
                
                // Smart reply chips — shown when input is empty and suggestions exist
                if commentText.isEmpty && !smartReplySuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(smartReplySuggestions, id: \.self) { suggestion in
                                Button {
                                    HapticManager.impact(style: .light)
                                    commentText = suggestion
                                    isInputFocused = true
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input field with glass buttons
                HStack(alignment: .bottom, spacing: 12) {
                    // User avatar - Show actual profile photo with caching
                    if let imageURL = currentUserProfileImageURL,
                       !imageURL.isEmpty,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(.black)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(currentUserInitials)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.white)
                                )
                        }
                    } else {
                        Circle()
                            .fill(.black)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(currentUserInitials)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Text field
                        TextField(replyingTo != nil ? "Write a reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .lineLimit(1...4)
                            .focused($isInputFocused)
                            .onChange(of: commentText) { _, newValue in
                                // P0 FIX: Trigger debounced tone analysis only if service loaded
                                toneGuidanceService?.analyzeText(newValue)
                                // Detect @mention typing
                                handleMentionDetection(in: newValue)
                                // Clear smart reply chips once user starts typing
                                if !newValue.isEmpty { smartReplySuggestions = [] }
                            }

                        // @mention picker row
                        if showMentionPicker && !mentionResults.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(mentionResults, id: \.objectID) { user in
                                        Button {
                                            insertCommentMention(user)
                                        } label: {
                                            HStack(spacing: 6) {
                                                Group {
                                                    if let urlStr = user.profileImageURL,
                                                       let url = URL(string: urlStr) {
                                                        CachedAsyncImage(url: url) { img in
                                                            img.resizable().scaledToFill()
                                                        } placeholder: {
                                                            Circle().fill(Color.purple.opacity(0.15))
                                                                .overlay(
                                                                    Text(user.displayName.prefix(1))
                                                                        .font(.custom("OpenSans-Bold", size: 11))
                                                                        .foregroundStyle(.purple)
                                                                )
                                                        }
                                                        .frame(width: 26, height: 26)
                                                        .clipShape(Circle())
                                                    } else {
                                                        Circle()
                                                            .fill(Color.purple.opacity(0.15))
                                                            .frame(width: 26, height: 26)
                                                            .overlay(
                                                                Text(user.displayName.prefix(1))
                                                                    .font(.custom("OpenSans-Bold", size: 11))
                                                                    .foregroundStyle(.purple)
                                                            )
                                                    }
                                                }
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(user.displayName)
                                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                                        .foregroundStyle(.primary)
                                                    Text("@\(user.username)")
                                                        .font(.custom("OpenSans-Regular", size: 11))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Tone guidance feedback (if present)
                        if let feedback = toneGuidanceService?.currentFeedback {
                            ToneFeedbackView(feedback: feedback) {
                                // Use suggestion
                                if let suggestion = feedback.suggestion {
                                    commentText = suggestion
                                    toneGuidanceService?.clearFeedback()
                                    bereanSuggestion = nil
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Berean AI rewrite suggestion banner
                        if let suggestion = bereanSuggestion {
                            VStack(alignment: .leading, spacing: 8) {
                                // Header row
                                HStack(spacing: 6) {
                                    Image("amen-logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14, height: 14)
                                    Text("Berean suggested a rewrite")
                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            bereanSuggestion = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                // Divider between header and suggestion text
                                Rectangle()
                                    .fill(Color.purple.opacity(0.2))
                                    .frame(height: 1)
                                // Suggested text — always rendered as plain text
                                Text(suggestion)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(5)
                                    .fixedSize(horizontal: false, vertical: true)
                                // Action buttons
                                HStack(spacing: 8) {
                                    Button {
                                        commentText = suggestion
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            bereanSuggestion = nil
                                        }
                                    } label: {
                                        Text("Use this")
                                            .font(.custom("OpenSans-SemiBold", size: 12))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.purple, in: Capsule())
                                    }
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            bereanSuggestion = nil
                                        }
                                    } label: {
                                        Text("Keep mine")
                                            .font(.custom("OpenSans-Regular", size: 12))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color(uiColor: .systemFill), in: Capsule())
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.18), lineWidth: 1)
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Attached photo preview
                        if let photoData = commentPhotoData,
                           let uiImage = UIImage(data: photoData) {
                            HStack(spacing: 8) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
                                    )
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        commentPhotoData = nil
                                        selectedPhotoItem = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .background(Color(uiColor: .systemBackground), in: Circle())
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }

                        // Slow mode cooldown indicator
                        if cooldownRemaining > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.orange)
                                Text("Comment in \(Int(cooldownRemaining))s")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.orange)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Rate limit banner — shown proactively if daily limit is already hit
                        if let limitMsg = rateLimitMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.badge.xmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.8))
                                Text(limitMsg)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Action buttons row
                        HStack(spacing: 12) {
                            // Emoji button
                            Button {
                                showEmojiPicker = true
                                // haptic
                                HapticManager.impact(style: .light)
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.7))
                                    .frame(width: 24, height: 24)
                            }
                            
                            // Photo button — opens picker with AI moderation gate
                            PhotosPicker(selection: $selectedPhotoItem,
                                         matching: .images,
                                         photoLibrary: .shared()) {
                                ZStack {
                                    if isModeratingPhoto {
                                        ProgressView()
                                            .frame(width: 24, height: 24)
                                            .scaleEffect(0.7)
                                    } else if commentPhotoData != nil {
                                        Image(systemName: "photo.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(.black.opacity(0.7))
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                guard let newItem else { return }
                                isModeratingPhoto = true
                                photoModerationError = nil
                                Task {
                                    await moderateAndAttachPhoto(item: newItem)
                                }
                            }
                            
                            // Berean AI rewrite assist button — icon-only, black/white
                            if !commentText.isEmpty {
                                Button {
                                    requestBereanRewrite()
                                } label: {
                                    ZStack {
                                        // Match other Berean AI buttons: ultraThinMaterial so
                                        // .multiply blendMode reveals the dark logo correctly in
                                        // both light and dark mode.
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 28, height: 28)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                                            )
                                        if isLoadingBereanSuggestion {
                                            // Staggered dots while AI thinks
                                            HStack(spacing: 2) {
                                                ForEach(0..<3) { i in
                                                    Circle()
                                                        .fill(Color.purple)
                                                        .frame(width: 3, height: 3)
                                                        .opacity(isLoadingBereanSuggestion ? 1 : 0)
                                                        .animation(
                                                            .easeInOut(duration: 0.5)
                                                                .repeatForever()
                                                                .delay(Double(i) * 0.16),
                                                            value: isLoadingBereanSuggestion
                                                        )
                                                }
                                            }
                                        } else {
                                            Image("amen-logo")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 16, height: 16)
                                                .blendMode(.multiply)
                                        }
                                    }
                                }
                                .disabled(isLoadingBereanSuggestion)
                                .accessibilityLabel("Berean tone assist")
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            Spacer()
                            
                            // Glass Circular Send Button
                            GlassCircularButton(
                                icon: "paperplane.fill",
                                action: {
                                    submitComment()
                                },
                                isDisabled: commentText.isEmpty || isSubmittingComment || rateLimitMessage != nil
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .gesture(
            // Tap to dismiss keyboard
            TapGesture()
                .onEnded { _ in
                    if isInputFocused {
                        isInputFocused = false
                    }
                }
        )
        .sheet(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(userId: userId)
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiQuickPickerView { emoji in
                // Insert emoji at cursor position
                commentText += emoji
                showEmojiPicker = false
            }
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBerean) {
            BereanAIAssistantView(initialQuery: bereanQuery.isEmpty ? nil : bereanQuery)
        }
        .sheet(isPresented: $showCommentGuidelines) {
            CommunityGuidelinesPrompt {
                showCommentGuidelines = false
                UserDefaults.standard.set(true, forKey: "hasSeenCommentGuidelines")
                if pendingCommentSubmit {
                    pendingCommentSubmit = false
                    submitComment()
                }
            }
        }
        .sheet(isPresented: $showPendingQueue) {
            PendingCommentsQueueView(
                pendingComments: pendingComments,
                onApprove: { comment in approveComment(comment, approved: true) },
                onReject: { comment in approveComment(comment, approved: false) }
            )
        }
        .alert("Photo Not Allowed", isPresented: Binding(get: { photoModerationError != nil }, set: { if !$0 { photoModerationError = nil; selectedPhotoItem = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(photoModerationError ?? "This image cannot be uploaded.")
        }
        .task {
            // P0 FIX: Lazy load AI services in background (don't block sheet appearance)
            Task(priority: .userInitiated) {
                await MainActor.run {
                    summarizationService = AIThreadSummarizationService.shared
                    toneGuidanceService = AIToneGuidanceService.shared
                }
            }

            // Proactive rate limit check — show banner immediately if daily limit already hit,
            // so the user knows they can't comment before typing anything.
            Task(priority: .background) {
                let check = await NewAccountRestrictionService.shared.canComment()
                if !check.allowed, let reason = check.reason {
                    await MainActor.run {
                        rateLimitMessage = reason
                    }
                }
            }

            // ✅ Start real-time listener FIRST so it picks up cached data immediately
            startRealtimeListener()

            // Build initial participants cache
            rebuildTopParticipants()

            // Load current user data
            loadCurrentUserData()

            // ✅ DON'T call loadComments() - the real-time listener will populate the UI
            // The listener fires immediately with cached data, then updates with server data
        }
        .onDisappear {
            stopRealtimeListener()
            participantsRebuildTask?.cancel()
            participantsRebuildTask = nil
        }
        // P1 PERF FIX: Rebuild top participants only when comments actually change.
        // Debounced — rapid streaming inserts batch into one rebuild instead of N.
        .onChange(of: commentsWithReplies.count) { oldCount, newCount in
            participantsRebuildTask?.cancel()
            participantsRebuildTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s debounce
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    rebuildTopParticipants()
                    loadPendingComments()
                }
            }
            // Refresh smart reply chips when a new comment arrives
            if newCount > oldCount { refreshSmartReplies() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("commentsUpdated"))) { notification in
            // Check if this notification is for our post
            if let notificationPostId = notification.userInfo?["postId"] as? String,
               notificationPostId == self.postId {
                // Call synchronously on main actor — no Task.sleep, no async hop.
                // The listener has already committed its writes to commentService before
                // posting this notification, so no delay is needed. The delay + async Task
                // was causing a second SwiftUI layout pass over an already-updating LazyVStack,
                // corrupting its internal cell buffer (SIGABRT heap corruption).
                Task { @MainActor in
                    _ = await updateCommentsFromService()
                }
            }
        }
        // Remove ghost optimistic comment if all server retries failed
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("commentFailed"))) { notification in
            guard let tempId = notification.userInfo?["tempId"] as? String,
                  let notificationPostId = notification.userInfo?["postId"] as? String,
                  notificationPostId == self.postId else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                commentsWithReplies.removeAll { $0.comment.id == tempId }
            }
            errorMessage = "Comment failed to send. Please try again."
            showError = true
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // ✅ Timestamp auto-refresh: Update current time every 60 seconds
            // This triggers view refresh, causing "5m ago" → "6m ago" updates
            currentTime = Date()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }

        // Premium reaction tray overlay — sits above all comments content
        ReactionTrayOverlay(state: ReactionPresentationState.shared)
        } // end ZStack
    }
    
    // MARK: - Load Current User Data
    
    private func loadCurrentUserData() {
        // Get cached user data
        currentUserInitials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "U"
        currentUserProfileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        // Current user data loaded for comment input
    }
    
    // MARK: - Actions
    
    // MARK: - @Mention helpers

    /// Detects if the user is typing @<query> and triggers a debounced user search.
    // MARK: - Smart Reply Chips

    private func refreshSmartReplies() {
        guard !isLoadingSmartReplies, commentText.isEmpty else { return }
        // Use the most recent top-level comment (not from current user) as context
        let lastIncoming = commentsWithReplies.last(where: { $0.comment.authorId != (Auth.auth().currentUser?.uid ?? "") })
        guard let lastComment = lastIncoming?.comment, !lastComment.content.isEmpty else {
            smartReplySuggestions = []; return
        }
        isLoadingSmartReplies = true
        Task {
            let request = SmartReplySuggestionRequest(
                mode: .smartReply,
                contextExcerpt: String(lastComment.content.prefix(200)),
                actorDisplayName: nil,
                actorIsMinor: false
            )
            let result = await SmartReplySuggestionService.shared.generate(request: request)
            await MainActor.run {
                var chips: [String] = []
                for s in [result.suggestion1, result.suggestion2, result.suggestion3] {
                    if !s.isEmpty, !chips.contains(s) { chips.append(s) }
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    smartReplySuggestions = chips
                }
                isLoadingSmartReplies = false
            }
        }
    }

    // MARK: - Berean AI Rewrite
    
    private func requestBereanRewrite() {
        guard !commentText.isEmpty, !isLoadingBereanSuggestion else { return }
        isLoadingBereanSuggestion = true
        let draft = commentText
        let context = "Post: \(post.content.prefix(200))"
        let userId = Auth.auth().currentUser?.uid ?? ""
        Task {
            do {
                let suggestion = try await BereanOrchestrator.shared.getCommentRewriteSuggestion(
                    draft: draft,
                    context: context,
                    userId: userId
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        bereanSuggestion = suggestion
                        isLoadingBereanSuggestion = false
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .soft)
                    HapticManager.impact(style: .light)
                }
            } catch {
                print("⚠️ [Berean] Comment rewrite unavailable: \(error)")
                await MainActor.run {
                    isLoadingBereanSuggestion = false
                }
            }
        }
    }
    
    private func handleMentionDetection(in text: String) {
        // Find the word being typed that starts with @
        let words = text.components(separatedBy: .whitespaces)
        if let lastWord = words.last, lastWord.hasPrefix("@"), lastWord.count > 1 {
            let query = String(lastWord.dropFirst())
            mentionDebounceTask?.cancel()
            mentionDebounceTask = nil
            mentionDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
                guard !Task.isCancelled else { return }
                do {
                    let results = try await AlgoliaSearchService.shared.searchUsers(query: query)
                    withAnimation(.easeOut(duration: 0.15)) {
                        mentionResults = Array(results.prefix(5))
                        showMentionPicker = !mentionResults.isEmpty
                    }
                } catch {
                    // Silent fail — mention search is best-effort
                }
            }
        } else {
            mentionDebounceTask?.cancel()
            mentionDebounceTask = nil
            if showMentionPicker {
                withAnimation(.easeOut(duration: 0.15)) {
                    showMentionPicker = false
                    mentionResults = []
                }
            }
        }
    }

    /// Replaces the current @<partial> token with the selected user's @username.
    private func insertCommentMention(_ user: AlgoliaUser) {
        if let lastAtIndex = commentText.lastIndex(of: "@") {
            let before = commentText[..<lastAtIndex]
            commentText = before + "@\(user.username) "
        }
        withAnimation(.easeOut(duration: 0.15)) {
            showMentionPicker = false
            mentionResults = []
        }
        HapticManager.impact(style: .light)
    }

    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        // P0-1 FIX: Prevent duplicate submissions
        guard !isSubmittingComment else { return }

        // Community guidelines check — show once on first comment
        if !UserDefaults.standard.bool(forKey: "hasSeenCommentGuidelines") {
            pendingCommentSubmit = true
            showCommentGuidelines = true
            return
        }

        // Slow mode: check per-post cooldown (if creator enabled it)
        let slowModeCooldown: TimeInterval = UserDefaults.standard.double(forKey: "commentSlowModeSeconds_\(postId)")
        if slowModeCooldown > 0 {
            let userId = FirebaseManager.shared.currentUser?.uid ?? ""
            let remaining = InteractionThrottleService.shared.commentCooldownRemaining(
                userId: userId, postId: postId, cooldownSeconds: slowModeCooldown
            )
            if remaining > 0 {
                // Start visual countdown timer
                startCooldownTimer(remaining: remaining)
                errorMessage = "Please wait \(Int(remaining)) more second\(Int(remaining) == 1 ? "" : "s") before commenting."
                showError = true
                return
            }
        }

        let text = commentText
        
        isSubmittingComment = true
        
        Task {
            // ── P0 Block check: reject comments across a block relationship ─
            // Run both directions concurrently before any content analysis.
            let postAuthorId = post.authorId
            if !postAuthorId.isEmpty {
                async let currentUserBlockedAuthor = BlockService.shared.isBlocked(userId: postAuthorId)
                async let authorBlockedCurrentUser  = BlockService.shared.isBlockedBy(userId: postAuthorId)
                let (blockedAuthor, blockedByAuthor) = await (currentUserBlockedAuthor, authorBlockedCurrentUser)
                if blockedAuthor || blockedByAuthor {
                    await MainActor.run {
                        isSubmittingComment = false
                        commentText = text
                        // Neutral message — don't reveal block direction
                        errorMessage = "Unable to post comment."
                        showError = true
                    }
                    return
                }

                // ── Privacy gate: enforce private-account comment restrictions ─
                let visibilityString: String
                switch post.visibility {
                case .everyone: visibilityString = "everyone"
                case .followers: visibilityString = "followers"
                case .community: visibilityString = "everyone" // community posts allow comments
                }
                let canPost = await PrivacyAccessControl.shared.canComment(
                    onPostBy: postAuthorId,
                    postVisibility: visibilityString,
                    isAuthorPrivate: false // Firestore rules enforce server-side; this is client-side best effort
                )
                if !canPost {
                    await MainActor.run {
                        errorMessage = "You must follow this person to comment on their posts."
                        showError = true
                        isSubmittingComment = false
                        commentText = text
                    }
                    return
                }
                // ─────────────────────────────────────────────────────────────
            }
            // ───────────────────────────────────────────────────────────────

            // ── Tier 0: instant client-side hard block ─────────────────
            let localGuard = LocalContentGuard.check(text)
            if localGuard.isBlocked {
                await MainActor.run {
                    errorMessage = localGuard.userMessage
                    showError = true
                    isSubmittingComment = false
                    commentText = text // restore so user can edit
                }
                return
            }
            // ─────────────────────────────────────────────────────────

            // P0 FIX: Validate tone before submitting only if service loaded
            if let feedback = await toneGuidanceService?.analyzeTextImmediate(text),
               feedback.type == .flagged {
                // Block flagged content
                await MainActor.run {
                    errorMessage = feedback.message
                    showError = true
                    isSubmittingComment = false  // ✅ Re-enable button on error
                }
                return
            }
            
            // P0-2 FIX: Run client-side safety guardrails before writing to Firestore.
            // This catches PII, hate, harassment, threats, self-harm patterns instantly
            // without a network round-trip. The full server-side moderation pipeline
            // runs asynchronously after the write (in the Cloud Function trigger).
            let guardrailResult = await ThinkFirstGuardrailsService.shared.checkContent(
                text, context: .comment
            )
            if guardrailResult.action == .block {
                let reason = guardrailResult.violations.first?.message
                    ?? "This content violates community guidelines."
                await MainActor.run {
                    errorMessage = reason
                    showError = true
                    isSubmittingComment = false
                    commentText = text // restore so user can edit
                }
                return
            }
            
            // Clear comment text after validation passes
            await MainActor.run {
                commentText = ""
                toneGuidanceService?.clearFeedback()
                bereanSuggestion = nil  // Dismiss any pending Berean suggestion
                // Keep isSubmittingComment = true until the write completes to prevent duplicates
            }
            
            do {
                var newCommentId: String?
                
                if let replyingTo = replyingTo {
                    // Validate parent comment ID
                    guard let parentCommentId = replyingTo.id, !parentCommentId.isEmpty else {
                        await MainActor.run {
                            errorMessage = "Invalid parent comment"
                            showError = true
                            commentText = text // Restore text
                        }
                        return
                    }
                    
                    // Submit reply
                    // ✅ CRITICAL FIX: Pass Post object to avoid Firestore lookup
                    let newComment = try await commentService.addReply(
                        postId: postId,
                        parentCommentId: parentCommentId,
                        content: text,
                        post: self.post  // ✅ Pass Post object to bypass Firestore lookup
                    )
                    newCommentId = newComment.id
                    
                    // ✅ DON'T add reply to local UI - let the real-time listener handle it
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            // Expand parent thread and clear reply state
                            expandedThreads.insert(parentCommentId)
                            self.replyingTo = nil
                        }
                    }
                } else {
                    // Submit comment
                    // ✅ CRITICAL FIX: Pass Post object to avoid Firestore lookup with short ID
                    // We pass postId (short ID) for Realtime DB operations, but also pass
                    // the full Post object to avoid needing to fetch from Firestore
                    let newComment = try await commentService.addComment(
                        postId: postId,
                        content: text,
                        post: self.post  // ✅ Pass the Post object to bypass Firestore lookup
                    )
                    newCommentId = newComment.id
                    // Record for slow mode cooldown tracking and start visual timer
                    let currentUID = FirebaseManager.shared.currentUser?.uid ?? ""
                    InteractionThrottleService.shared.recordCommentPosted(userId: currentUID, postId: postId)
                    // Start visible countdown if slow mode is active
                    let slowModeCooldown2: TimeInterval = UserDefaults.standard.double(forKey: "commentSlowModeSeconds_\(postId)")
                    if slowModeCooldown2 > 0 {
                        await MainActor.run { startCooldownTimer(remaining: slowModeCooldown2) }
                    }
                    
                    // ✅ DON'T add to local UI - let the real-time listener handle it
                    await MainActor.run {
                        if let id = newCommentId {
                            expandedThreads.insert(id)
                        }
                    }
                }
                
                // Track new comment for highlight animation
                if let id = newCommentId {
                    await MainActor.run {
                        _ = withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            newCommentIds.insert(id)
                        }
                        
                        // Remove highlight after 2 seconds
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            _ = withAnimation {
                                newCommentIds.remove(id)
                            }
                        }
                        
                        // Scroll to new comment
                        if let scrollProxy = scrollProxy {
                            withAnimation(.easeOut(duration: 0.4)) {
                                scrollProxy.scrollTo("\(id)-main", anchor: .top)
                            }
                        }
                    }
                }
                
                // Haptic feedback
                await MainActor.run {
                    // haptic
                    HapticManager.notification(type: .success)
                    isSubmittingComment = false  // Re-enable after write completes
                }
            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    if nsError.domain == "CommentService" && nsError.code == -11 {
                        // Rate limit hit — show inline banner and disable send button
                        rateLimitMessage = nsError.localizedDescription
                    } else {
                        errorMessage = error.localizedDescription
                        showError = true
                        commentText = text // Restore text on error
                    }
                    isSubmittingComment = false
                }
            }
        }
    }

    private func deleteComment(_ comment: Comment) {
        Task {
            guard let commentId = comment.id, !commentId.isEmpty else {
                await MainActor.run {
                    errorMessage = "Invalid comment ID"
                    showError = true
                }
                return
            }
            
            do {
                // ✅ OPTIMISTIC UPDATE: Remove from UI immediately for better UX
                await MainActor.run {
                    if comment.isReply, let parentId = comment.parentCommentId {
                        // Remove reply from parent's replies
                        for i in 0..<commentsWithReplies.count {
                            if commentsWithReplies[i].comment.id == parentId {
                                commentsWithReplies[i].replies.removeAll { $0.id == commentId }
                                break
                            }
                        }
                    } else {
                        // Remove top-level comment
                        commentsWithReplies.removeAll { $0.comment.id == commentId }
                    }
                }
                
                // Then delete from Firebase (real-time listener will confirm)
                try await commentService.deleteComment(commentId: commentId, postId: postId)
                
                // Haptic feedback
                await MainActor.run {
                    // haptic
                    HapticManager.notification(type: .success)
                }
            } catch {
                // If deletion failed, reload comments to restore state
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                
                // ✅ DON'T reload - the real-time listener will restore the UI automatically
                // The optimistic delete already happened, listener will revert if delete failed
            }
        }
    }
    
    private func toggleAmen(comment: Comment) {
        // Optimistic UI update with animation
        let commentId = comment.id ?? ""
        
        // Haptic feedback immediately
        // haptic
        HapticManager.impact(style: .light)
        
        Task {
            guard !commentId.isEmpty else {
                await MainActor.run {
                    errorMessage = "Invalid comment ID"
                    showError = true
                }
                return
            }
            
            do {
                // Derive amen state from the already-populated amenUserIds on the Comment model.
                // This avoids a Firebase getData() round-trip that returns stale offline-cached
                // values and always resolves to "true" after the first like.
                let currentUserId = FirebaseManager.shared.currentUser?.uid ?? ""
                let wasAmened = !currentUserId.isEmpty && comment.amenUserIds.contains(currentUserId)
                
                // Optimistic UI update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        if comment.isReply {
                            // Find and update reply
                            for i in 0..<commentsWithReplies.count {
                                if let replyIndex = commentsWithReplies[i].replies.firstIndex(where: { $0.id == commentId }) {
                                    var updatedReply = commentsWithReplies[i].replies[replyIndex]
                                    updatedReply.amenCount += wasAmened ? -1 : 1
                                    commentsWithReplies[i].replies[replyIndex] = updatedReply
                                }
                            }
                        } else {
                            // Find and update comment
                            if let index = commentsWithReplies.firstIndex(where: { $0.comment.id == commentId }) {
                                var updatedComment = commentsWithReplies[index].comment
                                updatedComment.amenCount += wasAmened ? -1 : 1
                                commentsWithReplies[index] = CommentWithReplies(comment: updatedComment, replies: commentsWithReplies[index].replies)
                            }
                        }
                    }
                }
                
                // Sync to Firebase in background
                try await commentService.toggleAmen(commentId: commentId, postId: postId, currentlyAmened: wasAmened)
                
            } catch {
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if comment.isReply {
                            for i in 0..<commentsWithReplies.count {
                                if let replyIndex = commentsWithReplies[i].replies.firstIndex(where: { $0.id == commentId }) {
                                    var updatedReply = commentsWithReplies[i].replies[replyIndex]
                                    updatedReply.amenCount = comment.amenCount // Revert to original
                                    commentsWithReplies[i].replies[replyIndex] = updatedReply
                                }
                            }
                        } else {
                            if let index = commentsWithReplies.firstIndex(where: { $0.comment.id == commentId }) {
                                var updatedComment = commentsWithReplies[index].comment
                                updatedComment.amenCount = comment.amenCount // Revert to original
                                commentsWithReplies[index] = CommentWithReplies(comment: updatedComment, replies: commentsWithReplies[index].replies)
                            }
                        }
                    }
                    
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Skeleton Loading UI
    
    /// P0 FIX: Skeleton loading shown immediately while comments load
    /// Provides instant visual feedback, no blocking
    private var commentsSkeletonView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    // Avatar placeholder
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Name placeholder
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 14)
                        
                        // Comment text placeholder (multiple lines)
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 200, height: 12)
                        }
                        
                        // Action buttons placeholder
                        HStack(spacing: 16) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 50, height: 10)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .padding(.top, 20)
        .redacted(reason: .placeholder)  // iOS built-in shimmer effect
    }
    
    // MARK: - Real-time Updates
    
    private func startRealtimeListener() {
        guard !isListening else { return }
        
        commentService.startListening(to: postId)
        isListening = true
        
        // ✅ Load initial data immediately from service cache
        Task {
            // Small delay to let listener initialize
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            _ = await updateCommentsFromService()
            
            // Turn off loading state
            await MainActor.run {
                isLoading = false
            }
        }
        
        // Real-time listener + commentsUpdated notification handles live updates.
        // Polling removed — it fired 120+ Firestore reads/hour per user.
    }
    
    private func stopRealtimeListener() {
        guard isListening else { return }
        
        // Cancel polling task
        pollingTask?.cancel()
        pollingTask = nil
        
        // P0-3 FIX: Stop listener for this specific post (not all listeners)
        commentService.stopListening(to: postId)
        isListening = false
    }
    
    @MainActor
    private func updateCommentsFromService() async -> Bool {
        // Get updated comments from service cache (only top-level comments)
        let rawComments = commentService.comments[postId] ?? []

        // Block filter: hide comments from users the current user has blocked or who blocked them.
        let blockedUsers = BlockService.shared.blockedUsers
        let allComments: [Comment]
        if blockedUsers.isEmpty {
            allComments = rawComments
        } else {
            allComments = rawComments.filter { !blockedUsers.contains($0.authorId) }
        }

        // Build commentsWithReplies from service data
        var newCommentsWithReplies: [CommentWithReplies] = []

        for comment in allComments {
            guard let commentId = comment.id else {
                continue
            }
            
            // Also filter replies from blocked users
            let rawReplies = commentService.commentReplies[commentId] ?? []
            let replies = blockedUsers.isEmpty ? rawReplies : rawReplies.filter { !blockedUsers.contains($0.authorId) }

            // Update reply count
            var updatedComment = comment
            updatedComment.replyCount = replies.count
            
            let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
            newCommentsWithReplies.append(commentWithReplies)
        }
        
        // ✅ CRITICAL FIX: Only update if there are actual changes
        // This prevents duplicate IDs and unnecessary re-renders
        if hasCommentsChanged(newCommentsWithReplies) {
            // Plain assignment — no withAnimation wrapper here.
            // SwiftUI computes its own diff and applies transitions declared on the
            // ForEach rows (e.g. .transition(.asymmetric(...))). Wrapping a full-array
            // replacement in withAnimation from inside an async Task caused reentrancy
            // into LazyVStack's internal cell recycling buffer → SIGABRT heap corruption.
            commentsWithReplies = newCommentsWithReplies
            return true
        }
        
        return false
    }
    
    /// Check if comments have actually changed (prevents duplicate updates)
    private func hasCommentsChanged(_ newComments: [CommentWithReplies]) -> Bool {
        // Different count = changed
        if newComments.count != commentsWithReplies.count {
            return true
        }
        
        // Check if IDs match in order
        for i in 0..<newComments.count {
            guard i < commentsWithReplies.count else {
                return true
            }
            
            let newComment = newComments[i]
            let oldComment = commentsWithReplies[i]
            
            // Different comment ID = changed
            if newComment.comment.id != oldComment.comment.id {
                return true
            }
            
            // Different reply count = changed
            if newComment.replies.count != oldComment.replies.count {
                return true
            }
            
            // Different amen count = changed
            if newComment.comment.amenCount != oldComment.comment.amenCount {
                return true
            }
            
            // Check reply IDs with bounds checking
            for j in 0..<newComment.replies.count {
                guard j < oldComment.replies.count else {
                    return true
                }
                if newComment.replies[j].id != oldComment.replies[j].id {
                    return true
                }
            }
        }
        
        // No changes detected
        return false
    }
    
    // MARK: - Timestamp Auto-Refresh Helper
    
    /// ✅ Computes relative time string that updates when currentTime changes
    private func timeAgoString(for date: Date) -> String {
        let _ = currentTime
        return date.timeAgoDisplay()
    }

    // MARK: - Cooldown Timer

    private func startCooldownTimer(remaining: TimeInterval) {
        cooldownEndDate = Date().addingTimeInterval(remaining)
    }

    // MARK: - Pending Comment Approval

    private func loadPendingComments() {
        let currentUserId = FirebaseManager.shared.currentUser?.uid ?? ""
        guard currentUserId == post.authorId else { return }
        let pending = commentsWithReplies
            .map(\.comment)
            .filter { $0.approvalStatus == "pending" }
        withAnimation { pendingComments = pending }
    }

    // MARK: - Photo moderation + attach

    private func moderateAndAttachPhoto(item: PhotosPickerItem) async {
        defer {
            Task { @MainActor in isModeratingPhoto = false }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run {
                photoModerationError = "Could not load image. Please try again."
                selectedPhotoItem = nil
            }
            return
        }

        // Vision-based adult content classification (on-device, no network)
        if await isImageExplicit(data: data) {
            await MainActor.run {
                photoModerationError = "This image was flagged by our safety system and cannot be posted."
                selectedPhotoItem = nil
                commentPhotoData = nil
            }
            return
        }

        // ContentRiskAnalyzer pass (text-based signals won't apply to images,
        // but we check a synthetic descriptor for future extensibility)
        // Image passes — attach it
        await MainActor.run {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                commentPhotoData = data
            }
            // haptic
            HapticManager.notification(type: .success)
        }
    }

    /// Returns true if Vision detects significant adult/racy content.
    private func isImageExplicit(data: Data) async -> Bool {
        guard let cgImage = UIImage(data: data)?.cgImage else { return false }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNClassifyImageRequest()
        do {
            try handler.perform([request])
            guard let observations = request.results else { return false }
            let adultScore = observations.first(where: { $0.identifier == "explicit" })?.confidence ?? 0
            let racyScore  = observations.first(where: { $0.identifier == "suggestive" })?.confidence ?? 0
            return adultScore > 0.6 || racyScore > 0.85
        } catch {
            return false // fail open — let server-side moderation catch edge cases
        }
    }

    private func approveComment(_ comment: Comment, approved: Bool) {
        guard let commentId = comment.id else { return }
        let newStatus = approved ? "approved" : "rejected"
        Task {
            do {
                try await Firestore.firestore()
                    .collection("posts").document(post.firestoreId)
                    .collection("comments").document(commentId)
                    .updateData(["approvalStatus": newStatus])
                await MainActor.run {
                    pendingComments.removeAll { $0.id == commentId }
                    ToastManager.shared.success(approved ? "Comment approved" : "Comment rejected")
                }
            } catch {
                print("❌ [APPROVAL] Failed to update comment status: \(error)")
            }
        }
    }
}

// MARK: - Comment Row

private struct PostCommentRow: View {
    let comment: Comment
    var isReply: Bool = false
    var isNew: Bool = false
    let onReply: () -> Void
    let onDelete: () -> Void
    let onAmen: () -> Void
    let onProfileTap: () -> Void
    var onToggleThread: (() -> Void)? = nil
    var isThreadExpanded: Bool = true
    var replyCount: Int = 0
    var currentTime: Date = Date() // ✅ For timestamp auto-refresh
    
    @ObservedObject private var followService = FollowService.shared

    @State private var showOptions = false
    @State private var hasAmened = false
    @State private var localAmenCount: Int = 0
    @State private var didJustFollow = false  // Optimistic follow state
    @State private var showReportSheet = false  // Report reason picker
    // reaction picker is handled by AMENReactionSystem (.reactionPicker modifier on MentionTextView)
    
    private var isOwnComment: Bool {
        comment.authorId == FirebaseManager.shared.currentUser?.uid
    }
    
    /// True when the current user should see the follow chip for this commenter.
    private var showFollowChip: Bool {
        guard !isOwnComment else { return false }
        guard !didJustFollow else { return false }
        return !followService.following.contains(comment.authorId)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar - Tappable to view profile with cached image loading
            Button {
                onProfileTap()
                
                // Haptic feedback
                // haptic
                HapticManager.impact(style: .light)
            } label: {
                if let imageURL = comment.authorProfileImageURL,
                   !imageURL.isEmpty,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(.black)
                            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                            .overlay(
                                Text(comment.authorInitials)
                                    .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                    .foregroundStyle(.white)
                            )
                    }
                } else {
                    Circle()
                        .fill(.black)
                        .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                        .overlay(
                            Text(comment.authorInitials)
                                .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                                .foregroundStyle(.white)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                            .foregroundStyle(.black)

                        // ✅ Verified badge
                        if VerifiedBadgeHelper.isVerified(userId: comment.authorId) {
                            VerifiedBadge(size: isReply ? 12 : 13)
                        }
                    }

                    Text(comment.authorUsername.hasPrefix("@") ? comment.authorUsername : "@\(comment.authorUsername)")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))

                    // Subtle follow chip — only shown when not yet following this commenter
                    if showFollowChip {
                        Button {
                            didJustFollow = true
                            // haptic
                            HapticManager.impact(style: .light)
                            Task {
                                try? await FollowService.shared.followUser(userId: comment.authorId)
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: isReply ? 8 : 9, weight: .semibold))
                                Text("Follow")
                                    .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 11))
                            }
                            .foregroundStyle(.black.opacity(0.55))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: didJustFollow)
                    }

                    Text("•")
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.3))

                    // ✅ Timestamp auto-refresh: Recomputes when currentTime changes
                    Text(timeAgoString(for: comment.createdAt, currentTime: currentTime))
                        .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                // Content with @mention highlight + link detection
                // Long-press opens the AMEN reaction tray (AMENReactionSystem)
                MentionTextView(
                    text: comment.content,
                    autoDetectMentions: true,
                    font: .custom("OpenSans-Regular", size: isReply ? 13 : 14),
                    fontSize: isReply ? 13 : 14,
                    lineSpacing: 3
                )
                .fixedSize(horizontal: false, vertical: true)
                .reactionPicker(
                    id: comment.id ?? UUID().uuidString,
                    isFromCurrentUser: false,
                    context: .comment,
                    selectedEmoji: hasAmened ? "❤️" : nil,
                    onSelect: { emoji in
                        if emoji == "❤️" || emoji == "🙏" {
                            // Map heart/amen reactions to the existing amen toggle
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                hasAmened.toggle()
                            }
                            onAmen()
                        }
                        // Future: route other emoji reactions to their own handlers
                    }
                )

                // Translation affordance (lightweight, inline, non-blocking)
                CommentTranslationRow(
                    text: comment.content,
                    commentId: comment.id ?? "unknown",
                    isPublicContent: true
                )

                // Actions
                HStack(spacing: 20) {
                    // Amen with animation (heart icon like reference)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            hasAmened.toggle()
                        }
                        onAmen()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: hasAmened ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(hasAmened ? Color.red : Color.black.opacity(0.5))
                                .scaleEffect(hasAmened ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hasAmened)
                            
                            if comment.amenCount > 0 {
                                Text("\(comment.amenCount)")
                                    .font(.custom("OpenSans-Medium", size: 13))
                                    .foregroundStyle(hasAmened ? Color.red : Color.black.opacity(0.5))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    
                    // Reply with count badge
                    if !isReply {
                        Button {
                            onReply()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                
                                if comment.replyCount > 0 {
                                    Text("\(comment.replyCount)")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                }
                            }
                            .foregroundStyle(.black.opacity(0.6))
                        }
                        
                        // Thread expand/collapse button
                        if replyCount > 0, let onToggleThread = onToggleThread {
                            Button {
                                onToggleThread()
                                
                                // haptic
                                HapticManager.impact(style: .light)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isThreadExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                    
                                    Text(isThreadExpanded ? "Hide" : "View")
                                        .font(.custom("OpenSans-SemiBold", size: 11))
                                }
                                .foregroundStyle(.black.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.05))
                                )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Options (delete if own comment)
                    if isOwnComment {
                        Button {
                            showOptions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        .confirmationDialog("Comment Options", isPresented: $showOptions) {
                            Button("Delete Comment", role: .destructive) {
                                onDelete()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isReply ? 12 : 16)
        .contextMenu {
            // Copy comment text
            Button {
                UIPasteboard.general.string = comment.content
                ToastManager.shared.success("Comment copied")
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            // Reply (top-level comments only)
            if !isReply {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }

            Divider()

            if isOwnComment {
                // Delete own comment
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Comment", systemImage: "trash")
                }
            } else {
                // Restrict/Unrestrict
                Button {
                    Task {
                        await RestrictService.shared.loadIfNeeded()
                        await RestrictService.shared.toggleRestrict(comment.authorId)
                        let isNowRestricted = RestrictService.shared.isRestricted(comment.authorId)
                        ToastManager.shared.success(isNowRestricted ? "User restricted" : "User unrestricted")
                    }
                } label: {
                    let isRestricted = RestrictService.shared.isRestricted(comment.authorId)
                    Label(isRestricted ? "Unrestrict" : "Restrict", systemImage: isRestricted ? "checkmark.circle" : "hand.raised")
                }

                // Block comment author
                Button(role: .destructive) {
                    Task {
                        do {
                            try await BlockService.shared.blockUser(userId: comment.authorId)
                            ToastManager.shared.success("User blocked")
                        } catch {
                            print("❌ Failed to block user: \(error)")
                        }
                    }
                } label: {
                    Label("Block User", systemImage: "hand.raised.slash")
                }

                // Mute comment author
                Button {
                    Task {
                        do {
                            try await ModerationService.shared.muteUser(userId: comment.authorId)
                            ToastManager.shared.success("User muted")
                        } catch {
                            print("❌ Failed to mute user: \(error)")
                        }
                    }
                } label: {
                    Label("Mute User", systemImage: "speaker.slash")
                }

                // Report another user's comment — opens reason picker sheet
                Button(role: .destructive) {
                    showReportSheet = true
                } label: {
                    Label("Report Comment", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            CommentReportSheet(comment: comment)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        // Long-press reaction is handled by AMENReactionSystem via .reactionPicker() on MentionTextView
        .onAppear {
            // Seed hasAmened from the listener-populated amenUserIds so the heart
            // icon reflects the real state immediately, without an async network call.
            let uid = FirebaseManager.shared.currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && comment.amenUserIds.contains(uid)
            localAmenCount = comment.amenCount
        }
        .onChange(of: comment.amenUserIds) { _, newIds in
            let uid = FirebaseManager.shared.currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && newIds.contains(uid)
        }
        .onChange(of: comment.amenCount) { _, newCount in
            localAmenCount = newCount
        }
    }

    // MARK: - Timestamp Auto-Refresh Helper

    private func timeAgoString(for date: Date, currentTime: Date) -> String {
        let _ = currentTime
        return date.timeAgoDisplay()
    }
}

// MARK: - Pending Comments Queue View

struct PendingCommentsQueueView: View {
    let pendingComments: [Comment]
    let onApprove: (Comment) -> Void
    let onReject: (Comment) -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if pendingComments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                        Text("All caught up!")
                            .font(.system(size: 18, weight: .semibold))
                        Text("No comments waiting for review.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(pendingComments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(comment.authorName)
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(comment.createdAt.timeAgoDisplay())
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.content)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                            HStack(spacing: 12) {
                                Button {
                                    onApprove(comment)
                                } label: {
                                    Label("Approve", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    onReject(comment)
                                } label: {
                                    Label("Reject", systemImage: "xmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Pending Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Participant Info Model

struct ParticipantInfo: Identifiable {
    let id = UUID()
    let userId: String
    let initials: String
    let profileImageURL: String?
    let score: Double
}

// MARK: - Linked Text View

struct LinkedText: View {
    let text: String
    let fontSize: CGFloat
    
    init(_ text: String, fontSize: CGFloat = 14) {
        self.text = text
        self.fontSize = fontSize
    }
    
    var body: some View {
        Text(attributedString)
            .font(.custom("OpenSans-Regular", size: fontSize))
    }
    
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        attributedString.foregroundColor = .black
        
        // Detect URLs using NSDataDetector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsString = text as NSString
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            guard let lowerIndex = AttributedString.Index(range.lowerBound, within: attributedString),
                  let upperIndex = AttributedString.Index(range.upperBound, within: attributedString) else { continue }
            let attributedRange = lowerIndex ..< upperIndex
            
            // Make link blue and underlined
            attributedString[attributedRange].foregroundColor = .blue
            attributedString[attributedRange].underlineStyle = .single
            
            // Add URL for tapping
            if let url = match.url {
                attributedString[attributedRange].link = url
            }
        }
        
        return attributedString
    }
}

// MARK: - Emoji Quick Picker

struct EmojiQuickPickerView: View {
    let onSelect: (String) -> Void
    
    // 5 quick reaction emojis commonly used in faith discussions
    let quickEmojis = ["🙏", "❤️", "🔥", "✨", "💯"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Quick Reactions")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Emoji buttons
            HStack(spacing: 16) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        
                        // Haptic feedback
                        // haptic
                        HapticManager.impact(style: .light)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 40))
                            .frame(width: 60, height: 60)
                            .background(
                                ZStack {
                                    // Glass morphic background
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.8)
                                    
                                    // Subtle gradient overlay
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.15),
                                                    Color.white.opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Border with gradient
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                }
                            )
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(EmojiButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

// Custom button style for emoji buttons with smooth press animation
struct EmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Comment Report Sheet

struct CommentReportSheet: View {
    let comment: Comment
    @Environment(\.dismiss) private var dismiss

    enum ReportReason: String, CaseIterable {
        case spam              = "Spam or scam"
        case hateSpeech        = "Hate speech or slurs"
        case harassment        = "Harassment or bullying"
        case misinformation    = "False or misleading content"
        case inappropriate     = "Sexually explicit or inappropriate"
        case selfHarm          = "Self-harm or crisis content"
        case violence          = "Violence or threats"
        case other             = "Something else"

        var icon: String {
            switch self {
            case .spam: return "envelope.badge.fill"
            case .hateSpeech: return "exclamationmark.bubble.fill"
            case .harassment: return "person.fill.xmark"
            case .misinformation: return "questionmark.circle.fill"
            case .inappropriate: return "eye.slash.fill"
            case .selfHarm: return "heart.slash.fill"
            case .violence: return "bolt.shield.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
    }

    @State private var submitted = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    submittedView
                } else {
                    reasonList
                }
            }
            .navigationTitle("Report Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    private var reasonList: some View {
        List {
            Section {
                Text("Why are you reporting this comment?")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                ForEach(Array(ReportReason.allCases.enumerated()), id: \.offset) { _, reason in
                    Button {
                        submitReport(reason: reason)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: reason.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                                .frame(width: 22)
                            Text(reason.rawValue)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSubmitting {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var submittedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Report Submitted")
                .font(.system(size: 20, weight: .bold))
            Text("Thank you for helping keep AMEN safe. We review every report.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color(uiColor: .label), in: Capsule())
                .foregroundStyle(Color(uiColor: .systemBackground))
            Spacer()
        }
    }

    private func submitReport(reason: ReportReason) {
        guard let commentId = comment.id, !isSubmitting else { return }
        isSubmitting = true
        Task {
            do {
                try await ModerationService.shared.reportComment(
                    commentId: commentId,
                    commentAuthorId: comment.authorId,
                    postId: comment.postId,
                    reason: .inappropriateContent,
                    additionalDetails: reason.rawValue
                )
                await MainActor.run {
                    isSubmitting = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        submitted = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    ToastManager.shared.showError("Failed to submit report. Please try again.")
                }
            }
        }
    }
}

// MARK: - iOS Messages-Style Reaction Picker

struct CommentReactionPicker: View {
    @Binding var isPresented: Bool
    let onReact: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // AMEN spiritual + standard reactions
    private let reactions: [(emoji: String, label: String)] = [
        ("🙏", "Pray"),
        ("❤️", "Love"),
        ("🔥", "Fire"),
        ("✝️", "Amen"),
        ("😢", "Sad"),
        ("😂", "Joy"),
    ]

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(reactions.enumerated()), id: \.offset) { index, reaction in
                Button {
                    onReact(reaction.emoji)
                    // haptic
                    HapticManager.impact(style: .light)
                } label: {
                    Text(reaction.emoji)
                        .font(.system(size: 26))
                        .frame(width: 42, height: 42)
                        .background(Color(uiColor: .systemBackground).opacity(0.01), in: Circle())
                }
                .buttonStyle(EmojiButtonStyle())
                .scaleEffect(appeared ? 1.0 : 0.4)
                .opacity(appeared ? 1.0 : 0.0)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.32, dampingFraction: 0.65).delay(Double(index) * 0.03),
                    value: appeared
                )
                .accessibilityLabel(reaction.label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        .onAppear {
            withAnimation { appeared = true }
        }
        // Dismiss on tap outside
        .onTapGesture { }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    CommentsView(post: Post(
        authorName: "Test User",
        authorInitials: "TU",
        content: "Test post",
        category: .openTable
    ))
    .environmentObject(UserService())
}
