//
//  CommentsView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  View for displaying and managing comments and replies on a post
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Combine  // Required for Timer.publish().autoconnect()
import PhotosUI
import Vision
import NaturalLanguage

private struct CommentsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CommentsBottomAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CommentsScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CommentsView: View {
    let post: Post
    let prefillText: String?
    /// Canonical Replies thread category override (e.g. "church_note", "verse_discussion", "berean").
    /// When nil, category is derived from `post.category` inside CommentService.
    let threadCategoryOverride: String?

    // [AGENT-4] Color scheme for adaptive reply hairline rail
    @Environment(\.colorScheme) private var colorSchemeForReplyRail
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var commentService = CommentService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    @ObservedObject private var userService = UserService.shared  // P0 FIX: ObservedObject for singletons (faster init)
    @ObservedObject private var commentBridge = CommentTranslationBridge.shared
    @ObservedObject private var mediaMomentInteraction = MediaMomentInteractionService.shared
    
    // P0 FIX: Lazy load AI services - only initialize when needed, not on sheet open
    @State private var summarizationService: AIThreadSummarizationService?
    @State private var toneGuidanceService: AIToneGuidanceService?
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @ObservedObject private var smartAttachmentResolver = AmenSmartAttachmentResolverService.shared // PERF: singleton → @ObservedObject
    @State private var commentAttachmentState: AmenAttachmentComposerState = .empty
    @State private var commentSmartAttachment: AmenSmartAttachment?
    @State private var commentMentionedLinks: [URL] = []
    @State private var commentAttachmentTask: Task<Void, Never>?

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
    // FIX: Temporary ID for the optimistic placeholder inserted while a new top-level
    // comment is in-flight; cleared when the RTDB listener delivers the real comment
    // or when the write fails and the placeholder is rolled back.
    @State private var optimisticCommentTempId: String?
    @StateObject private var commentSeal = SuccessSealController()
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
    @State private var alignmentPreviewTask: Task<Void, Never>?
    @State private var spiritualComposeAnalysis = AmenComposeAnalysis(intent: .unknown, suggestions: [], shouldShowDiscernmentGate: false, discernmentTitle: nil, discernmentMessage: nil)
    @State private var showSpiritualDiscernmentGate = false
    @State private var bypassSpiritualDiscernmentGate = false
    @State private var safetyOSTriggers: [AmenTriggerResult] = []
    @State private var activeSafetyOSTrigger: AmenTriggerResult?
    @State private var activeSafetyOSEffectPolicy: AmenReactionEffectPolicy?
    @State private var safetyOSEffectSeed = UUID()
    @State private var safetyOSCanonicalTask: Task<Void, Never>?
    @State private var pendingWellnessContext: WellnessInterventionContext? = nil
    @State private var wellnessClearedForComment = false
    @State private var showBotChallenge = false
    @State private var botChallengeCleared = false
    @StateObject private var contextualComposerObserver = AmenMagicWordComposerObserver()
    @StateObject private var safetyComposer = SafetyComposerState()

    // Smart reply chips
    @State private var smartReplySuggestions: [String] = []
    @State private var isLoadingSmartReplies = false

    // Scripture reference detection in composer
    @State private var detectedComposerScriptureRefs: [ScriptureVerificationService.ScriptureReference] = []
    @State private var scriptureDetectionTask: Task<Void, Never>?
    @State private var showScripturePreview = false
    @State private var scripturePreviewRef: ScriptureVerificationService.ScriptureReference?

    // Smart prompts (behind commentsSmartPromptsV1 flag)
    @State private var smartPromptIdleTimer: Task<Void, Never>?
    @State private var showIdleReplyPrompt = false

    @StateObject private var successChips = SuccessChipCenter()
    @State private var scrollViewHeight: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = 0
    @State private var contentOffsetY: CGFloat = 0
    @State private var lastContentOffsetY: CGFloat = 0
    @State private var isScrollingDown: Bool = false
    @State private var showJumpToLatest: Bool = false
    @State private var sendSweepTrigger: Bool = false
    
    // Berean AI integration
    @State private var showBerean = false
    @State private var bereanQuery = ""

    // Phase 4: Bilingual reply — detected language of the post being commented on
    @State private var detectedPostLanguage: String?

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
    @State private var silentReactionSummaryOverride: AmenSilentReactionSummary?
    @State private var showContextualMemoryLayer = false
    @State private var contextualMemoryLayer: AmenContextualMemoryLayer?

    // When set, CommentsView scrolls to the first target comment and briefly highlights
    // related comments on appear. Used by the dynamic reply preview routing.
    var highlightedCommentIds: [String] = []
    @State private var transientHighlightedCommentIds: Set<String> = []

    init(post: Post, prefillText: String? = nil, threadCategoryOverride: String? = nil, highlightedCommentId: String? = nil, highlightedCommentIds: [String] = []) {
        self.post = post
        self.prefillText = prefillText
        if let highlightedCommentId, !highlightedCommentId.isEmpty {
            self.highlightedCommentIds = [highlightedCommentId]
        } else {
            self.highlightedCommentIds = highlightedCommentIds
        }
        // An explicit override always wins. Otherwise, auto-derive "verse_discussion"
        // for posts that carry a scripture reference so the Replies filter tab is truthful.
        if let explicit = threadCategoryOverride, !explicit.isEmpty {
            self.threadCategoryOverride = explicit
        } else if let ref = post.verseReference, !ref.isEmpty {
            self.threadCategoryOverride = "verse_discussion"
        } else {
            self.threadCategoryOverride = nil
        }
        _commentText = State(initialValue: prefillText ?? "")
    }

    // Use full firestoreId — RTDB listener paths use the same full UUID as Firestore.
    // PostDetailView uses post.firestoreId directly; CommentsView must match.
    private var postId: String { post.firestoreId }
    private var activeMomentAnchor: MediaMomentAnchor? {
        guard let anchor = mediaMomentInteraction.activeCommentAnchor, anchor.postId == postId else { return nil }
        return anchor
    }
    
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
                                                colors: [Color(.label), Color(.label).opacity(0.8)],
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
                                            colors: [Color(.label), Color(.label).opacity(0.8)],
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
                                                    .font(.systemScaled(8, weight: .bold))
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
                        .font(.systemScaled(15, weight: .semibold))
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
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(pendingComments.count) comment\(pendingComments.count == 1 ? "" : "s") waiting for approval")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Tap to review")
                            .font(.systemScaled(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .medium))
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

    // MARK: - Post Interaction Row

    @ViewBuilder
    private var postInteractionRow: some View {
        if let summary = silentReactionSummaryOverride ?? AmenSpiritualSystemsService.shared.silentReactionSummary(
            for: post, isAuthor: post.authorId == (Auth.auth().currentUser?.uid ?? "")
        ) {
            SilentReactionSummaryView(summary: summary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        if post.authorId != (Auth.auth().currentUser?.uid ?? "") {
            SilentReactionBar { reaction in
                Task {
                    await AmenSpiritualCloudService.shared.addSilentReaction(
                        sourceId: post.firestoreId.isEmpty ? post.id.uuidString : post.firestoreId,
                        sourceType: "post",
                        reactionType: reaction
                    )
                    await MainActor.run {
                        silentReactionSummaryOverride = AmenSilentReactionSummary(
                            summaryText: "\(reaction.title) recorded privately.",
                            reactionTypes: [reaction]
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        Button {
            Task {
                contextualMemoryLayer = await AmenSpiritualSystemsService.shared.contextualMemoryLayer(for: post)
                showContextualMemoryLayer = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up")
                    .font(.systemScaled(11))
                Text("Open deeper context")
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var mainStack: some View {
        ZStack {
        VStack(spacing: 0) {
            headerView
                .modifier(SoftStickyHeaderModifier(isActive: true, intensity: 0.25))

            pendingApprovalBanner
            
            // Comments List with ScrollViewReader for smooth scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: CommentsScrollOffsetKey.self,
                            value: geometry.frame(in: .named("commentsScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    LazyVStack(spacing: 0) {
                        postInteractionRow
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                        if isLoading {
                            // P0 FIX: Skeleton loading UI - shows immediately, no blocking
                            commentsSkeletonView
                                .transition(.opacity.combined(with: .scale))
                        } else if commentsWithReplies.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left")
                                    .font(.systemScaled(48))
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
                            // Phase 6: Multilingual thread summary
                            if let langSummary = commentBridge.threadLanguageSummary {
                                ThreadLanguageSummaryView(summary: langSummary)
                            }

                            ForEach(Array(commentsWithReplies.enumerated()), id: \.element.id) { index, commentWithReplies in
                                VStack(alignment: .leading, spacing: 8) {
                                    mainCommentRow(for: commentWithReplies)

                                    expandedRepliesSection(for: commentWithReplies)
                                }
                                // [AGENT-4] Spec: 16pt between top-level comments
                                .padding(.vertical, 16)
                                .id(commentWithReplies.comment.id ?? UUID().uuidString)
                                // B) Staggered cascade reveal — header at 0ms, body +40ms, capped at 200ms
                                .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.20)
                                
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    // Voice Prayer & Testimony Comments section
                    // Only renders when voicePrayerCommentsEnabled or voiceTestimonyCommentsEnabled
                    // and the post is a prayer or testimony. No-op otherwise.
                    VoicePrayerCommentsSection(
                        post: post,
                        currentUserId: Auth.auth().currentUser?.uid ?? ""
                    )

                    Color.clear
                        .frame(height: 1)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(
                                key: CommentsBottomAnchorKey.self,
                                value: proxy.frame(in: .named("commentsScroll")).maxY
                            )
                        })
                        .id("commentsBottom")
                }
                .coordinateSpace(name: "commentsScroll")
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CommentsScrollViewHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(CommentsScrollOffsetKey.self) { value in
                    contentOffsetY = value
                    isScrollingDown = value < lastContentOffsetY - 4
                    lastContentOffsetY = value
                }
                .onPreferenceChange(CommentsBottomAnchorKey.self) { value in
                    bottomAnchorY = value
                    let isAtBottom = bottomAnchorY <= scrollViewHeight + 24
                    showJumpToLatest = !isAtBottom
                }
                .onPreferenceChange(CommentsScrollViewHeightKey.self) { value in
                    scrollViewHeight = value
                }
                .onAppear {
                    scrollProxy = proxy
                    // If opened from a dynamic reply preview chip, scroll to
                    // and briefly highlight the specific reply after load settles.
                    if let targetId = highlightedCommentIds.first {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            transientHighlightedCommentIds = Set(highlightedCommentIds)
                            withAnimation(.easeOut(duration: 0.35)) {
                                proxy.scrollTo("\(targetId)-main", anchor: .center)
                            }
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            transientHighlightedCommentIds.removeAll()
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if LiquidGlassEffectsFlags.jumpToLatestPill && showJumpToLatest {
                    JumpToLatestPill {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy?.scrollTo("commentsBottom", anchor: .bottom)
                            showJumpToLatest = false
                        }
                    }
                    .accessibilityLabel("Jump to latest comments")
                    .padding(.trailing, 16)
                    .padding(.bottom, 140)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            Divider()
            
            // Input Area with Liquid Glass Buttons
            VStack(spacing: 0) {
                if LiquidGlassEffectsFlags.floatingStatusPill && isSubmittingComment {
                    FloatingStatusPillView(text: "Posting...", systemIcon: "arrow.up")
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                // Replying indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorUsername.hasPrefix("@") ? replyingTo.authorUsername : "@\(replyingTo.authorUsername)")")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                        
                        Spacer()
                        
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                }
                
                // Phase 4: Bilingual reply preview — shown when replying to a post in a different language
                if let postLang = detectedPostLanguage, !commentText.isEmpty {
                    BilingualReplyComposer(
                        replyText: commentText,
                        postAuthorLanguage: postLang
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                if commentText.isEmpty {
                    commentReflectionChipRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .autoHideChips(isScrollingDown || isInputFocused)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Smart reply chips — shown when input is empty and suggestions exist
                if commentText.isEmpty && !smartReplySuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(smartReplySuggestions, id: \.self) { suggestion in
                                AmenSmartPill(
                                    title: suggestion,
                                    systemImage: nil,
                                    variant: .regular,
                                    accessibilityHint: "Inserts suggested response"
                                ) {
                                    HapticManager.impact(style: .light)
                                    commentText = suggestion
                                    isInputFocused = true
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .autoHideChips(isScrollingDown || isInputFocused)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Safety OS: tone check banner — appears when typing slows
                if let suggestion = safetyComposer.toneCheckSuggestion {
                    ToneCheckBanner(
                        suggestion: suggestion,
                        onApply: { commentText = safetyComposer.applyToneSuggestion($0) },
                        onDismiss: { safetyComposer.dismissToneSuggestion() }
                    )
                    .padding(.bottom, 4)
                }

                // Safety OS: rewrite panel — shown when content is blocked by moderation
                if safetyComposer.showRewritePanel {
                    TextRewriteView(
                        blockedText: $commentText,
                        harmCategoryId: safetyComposer.blockedCategoryId ?? "harassment",
                        contentType: "comment"
                    ) { accepted in
                        safetyComposer.onRewriteDecision(
                            accepted,
                            harmCategoryId: safetyComposer.blockedCategoryId ?? "harassment",
                            contentType: "comment"
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
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
                            .accessibilityLabel(replyingTo != nil ? "Reply" : "Comment")
                            .onChange(of: commentText) { _, newValue in
                                onCommentTextChanged(newValue)
                            }

                        commentAttachmentPreview

                        composerAnnotations

                        // Action buttons row
                        HStack(spacing: 12) {
                            // Emoji button
                            Button {
                                showEmojiPicker = true
                                // haptic
                                HapticManager.impact(style: .light)
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.systemScaled(18, weight: .medium))
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
                                            .font(.systemScaled(18, weight: .medium))
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.systemScaled(18, weight: .medium))
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
                                                .renderingMode(.original)
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
                                icon: safetyOSTriggers.contains(where: { $0.type == .shameTone || $0.type == .conflictTone })
                                    ? "pause.fill"
                                    : "paperplane.fill",
                                action: {
                                    sendSweepTrigger = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                        sendSweepTrigger = false
                                    }
                                    Task {
                                        let ok = await safetyComposer.checkBeforeSubmit(text: commentText, contentType: "comment")
                                        guard ok else { return }
                                        submitComment()
                                    }
                                },
                                isDisabled: commentText.isEmpty || isSubmittingComment || rateLimitMessage != nil || cooldownRemaining > 0
                            )
                            .accessibilityLabel(safetyOSTriggers.contains(where: { $0.type == .shameTone || $0.type == .conflictTone }) ? "Paused — review tone" : "Send comment")
                            .accessibilityHint("Double tap to post your comment")
                            .keyboardShortcut(.return, modifiers: .command)
                            .highlightSweep(trigger: sendSweepTrigger)
                            .successSeal(
                                isActive: commentSeal.isVisible,
                                label: "Sent",
                                yOffset: -46
                            )
                        }
                    }
                }

                momentAnchorCapsuleRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .composerCompression(isInputFocused || !commentText.isEmpty)
                    .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .successChips(successChips)
        .overlay {
            if let activeSafetyOSEffectPolicy {
                AmenReactionEffectHost(policy: activeSafetyOSEffectPolicy)
                    .id(safetyOSEffectSeed)
                    .padding(.horizontal, 18)
            }
        }
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
        .sheet(isPresented: $showSpiritualDiscernmentGate) {
            DiscernmentGateSheet(
                title: spiritualComposeAnalysis.discernmentTitle ?? "Discernment Moment",
                message: spiritualComposeAnalysis.discernmentMessage ?? "This may land differently than intended.",
                rewrite: discernmentRewriteText,
                onEdit: {
                    bypassSpiritualDiscernmentGate = false
                    showSpiritualDiscernmentGate = false
                    isInputFocused = true
                },
                onRewrite: {
                    if let replacement = discernmentRewriteText {
                        commentText = replacement
                        spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: replacement)
                    }
                    bypassSpiritualDiscernmentGate = false
                    showSpiritualDiscernmentGate = false
                    isInputFocused = true
                },
                onPause: {
                    commentText = "I want to pause and pray before I say more."
                    spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: commentText)
                    bypassSpiritualDiscernmentGate = false
                    showSpiritualDiscernmentGate = false
                    isInputFocused = true
                },
                onSendAnyway: {
                    bypassSpiritualDiscernmentGate = true
                    showSpiritualDiscernmentGate = false
                    submitComment()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeSafetyOSTrigger) { trigger in
            AmenDiscernmentSheet(
                trigger: trigger,
                originalText: commentText,
                suggestedRewrite: AmenLocalTriggerEngine.shared.suggestedRewrite(for: trigger, originalText: commentText)
            ) { action in
                handleSafetyOSComposerAction(action, trigger: trigger)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingWellnessContext) { ctx in
            WellnessPauseSheet(
                context: ctx,
                onContinue: {
                    wellnessClearedForComment = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        submitComment()
                    }
                },
                onPause: {}
            )
        }
        .sheet(isPresented: $showBotChallenge) {
            BotSuspicionFrictionView(
                onChallengePassed: {
                    AmenBotDefenseService.shared.markChallengeCompleted()
                    botChallengeCleared = true
                    showBotChallenge = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        submitComment()
                    }
                },
                onCancel: {
                    showBotChallenge = false
                }
            )
            .presentationDetents([.medium])
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
        .sheet(isPresented: $showContextualMemoryLayer) {
            if let layer = contextualMemoryLayer {
                ContextualMemoryLayerSheet(
                    layer: layer,
                    sourceTitle: post.authorName
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showScripturePreview) {
            if let ref = scripturePreviewRef {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.amenBlue)
                        Text(ref.fullReference)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Tap \"Open in Bible\" to read this passage in the Selah Bible reader.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button {
                            showScripturePreview = false
                            // Navigate to Selah reader — post notification for nav layer to handle
                            NotificationCenter.default.post(
                                name: Notification.Name("openSelahScriptureRef"),
                                object: nil,
                                userInfo: ["reference": ref.fullReference]
                            )
                        } label: {
                            Label("Open in Bible", systemImage: "book.pages")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Capsule().fill(Color.amenBlue))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        Spacer()
                    }
                    .padding(.top, 32)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showScripturePreview = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
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

            // Phase 4: Detect post language for bilingual reply composer
            Task(priority: .background) {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(post.content)
                if let lang = recognizer.dominantLanguage {
                    let code = lang.rawValue.components(separatedBy: "-").first ?? lang.rawValue
                    await MainActor.run {
                        detectedPostLanguage = code
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
            scriptureDetectionTask?.cancel()
            scriptureDetectionTask = nil
            smartPromptIdleTimer?.cancel()
            smartPromptIdleTimer = nil
            commentBridge.reset()
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
            let isAtBottom = bottomAnchorY <= scrollViewHeight + 24
            showJumpToLatest = !isAtBottom
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("commentsUpdated"))) { notification in
            // Check if this notification is for our post
            if let notificationPostId = notification.userInfo?["postId"] as? String,
               notificationPostId == self.postId {
                // [AGENT-4] Wrap real-time inserts in spec animation so new comments
                // animate in with opacity+offset(y:12) spring(0.4, 0.85).
                // Reduce Motion is handled inside PostCommentRow's transition.
                Task { @MainActor in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        Task { _ = await updateCommentsFromService() }
                    }
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
        // [AGENT-3] Per-second tick to drive the rolling-window rate-limit countdown.
        // Only active while a cooldown is in progress to avoid unnecessary redraws.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard cooldownRemaining > 0 else {
                // Cooldown expired — clear the banner if it was set by a rolling-window error
                if rateLimitMessage == "Slow down — give the conversation room to breathe." {
                    rateLimitMessage = nil
                }
                return
            }
            // Force recompute of cooldownRemaining (it reads Date() directly)
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

    var body: some View {
        mainStack
    }

    private var discernmentRewriteText: String? {
        spiritualComposeAnalysis.suggestions.first {
            $0.id == "soften" || $0.id == "clarify"
        }?.replacementText
    }

    private var commentReflectionChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AmenSmartPill(
                    title: "Pray",
                    systemImage: "hands.sparkles",
                    accessibilityHint: "Insert a prayerful response starter"
                ) {
                    applyReflectionStarter("I’m praying for you.")
                    AmenPrivateResonanceStore.shared.recordPray(contentId: postId)
                }
                AmenSmartPill(
                    title: "Encourage",
                    systemImage: "heart",
                    accessibilityHint: "Insert an encouragement starter"
                ) {
                    applyReflectionStarter("Thank you for sharing this. Be encouraged.")
                }
                AmenSmartPill(
                    title: "Ask",
                    systemImage: "questionmark.circle",
                    accessibilityHint: "Insert a thoughtful question starter"
                ) {
                    applyReflectionStarter("What stood out most to you?")
                }
                AmenSmartPill(
                    title: "Reflect",
                    systemImage: "sparkles",
                    accessibilityHint: "Insert a reflection starter"
                ) {
                    applyReflectionStarter("What stood out to me was")
                }
            }
        }
    }

    private func applyReflectionStarter(_ text: String) {
        HapticManager.impact(style: .light)
        commentText = text
        isInputFocused = true
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
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
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
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
                        bereanSuggestion = suggestion
                        isLoadingBereanSuggestion = false
                    }
                    HapticManager.impact(style: .light)
                }
            } catch {
                dlog("⚠️ [Berean] Comment rewrite unavailable: \(error)")
                await MainActor.run {
                    isLoadingBereanSuggestion = false
                }
            }
        }
    }
    
    // Extracted to avoid Swift type-checker complexity limit on the deeply-nested VStack body
    // that held 12+ conditional child views — broken into commentAttachmentPreview + composerAnnotations.
    @ViewBuilder private var composerAnnotations: some View {
        if !detectedComposerScriptureRefs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(detectedComposerScriptureRefs.enumerated()), id: \.offset) { _, ref in
                        Button {
                            scripturePreviewRef = ref
                            showScripturePreview = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(ref.fullReference)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.amenBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.amenBlue.opacity(0.1))
                                    .overlay(Capsule().strokeBorder(Color.amenBlue.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View scripture: \(ref.fullReference)")
                    }
                }
                .padding(.vertical, 2)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if AMENFeatureFlags.shared.smartContextualPromptsEnabled, safetyComposer.toneCheckSuggestion != nil {
            AmenSmartPill(title: "Want help rephrasing this kindly?", systemImage: "sparkles", variant: .regular,
                          accessibilityHint: "Tap to get a Berean AI rewrite suggestion") { requestBereanRewrite() }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if AMENFeatureFlags.shared.smartContextualPromptsEnabled, replyingTo == nil,
           post.category == .prayer, commentText.isEmpty {
            AmenSmartPill(title: "Need help responding with care?", systemImage: "heart", variant: .regular,
                          accessibilityHint: "Tap to get compassionate response suggestions") {
                Task {
                    let request = SmartReplySuggestionRequest(
                        mode: .smartReply, contextExcerpt: String(post.content.prefix(200)),
                        actorDisplayName: nil, actorIsMinor: false)
                    let result = await SmartReplySuggestionService.shared.generate(request: request)
                    var chips: [String] = []
                    for s in [result.suggestion1, result.suggestion2, result.suggestion3] {
                        if !s.isEmpty, !chips.contains(s) { chips.append(s) }
                    }
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                        smartReplySuggestions = chips.isEmpty
                            ? ["I'm praying for you.", "You're not alone.", "Thank you for sharing."]
                            : chips
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if AMENFeatureFlags.shared.smartContextualPromptsEnabled, showIdleReplyPrompt,
           replyingTo != nil, commentText.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["I hear you", "Praying for you", "Share scripture", "Ask a follow-up"], id: \.self) { starter in
                        AmenSmartPill(title: starter, systemImage: nil, variant: .regular,
                                      accessibilityHint: "Insert \(starter) as starter text") {
                            applyReflectionStarter(starter)
                            showIdleReplyPrompt = false
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if showMentionPicker && !mentionResults.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mentionResults, id: \.objectID) { user in
                        mentionSuggestionButton(for: user).buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let feedback = toneGuidanceService?.currentFeedback {
            ToneFeedbackView(feedback: feedback) {
                if let suggestion = feedback.suggestion {
                    commentText = suggestion
                    toneGuidanceService?.clearFeedback()
                    bereanSuggestion = nil
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        IntentComposeAssistantBar(
            analysis: spiritualComposeAnalysis,
            onApplySuggestion: { suggestion in
                if let replacement = suggestion.replacementText {
                    commentText = replacement
                    spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: replacement)
                }
            },
            onDismissSuggestion: { suggestion in
                spiritualComposeAnalysis = AmenComposeAnalysis(
                    intent: spiritualComposeAnalysis.intent,
                    suggestions: spiritualComposeAnalysis.suggestions.filter { $0.id != suggestion.id },
                    shouldShowDiscernmentGate: spiritualComposeAnalysis.shouldShowDiscernmentGate,
                    discernmentTitle: spiritualComposeAnalysis.discernmentTitle,
                    discernmentMessage: spiritualComposeAnalysis.discernmentMessage
                )
            },
            onWhy: { suggestion in errorMessage = suggestion.reason; showError = true }
        )
        AmenComposerDiscernmentOverlay(triggers: safetyOSTriggers)
        AmenContextualReactionLayer(results: contextualComposerObserver.results, maxVisible: 3)
        if let suggestion = bereanSuggestion { bereanSuggestionBanner(suggestion) }
        if let photoData = commentPhotoData, let uiImage = UIImage(data: photoData) {
            attachedPhotoPreview(uiImage)
        }
        if cooldownRemaining > 0 {
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.systemScaled(12, weight: .medium)).foregroundStyle(.orange)
                Text("Comment in \(Int(cooldownRemaining))s").font(.systemScaled(12, weight: .medium)).foregroundStyle(.orange)
                Spacer()
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let limitMsg = rateLimitMessage {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.xmark").font(.systemScaled(12, weight: .medium)).foregroundStyle(.red.opacity(0.8))
                Text(limitMsg).font(.systemScaled(12, weight: .medium)).foregroundStyle(.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if Double(commentText.count) / 800.0 > 0.8 {
            HStack {
                Spacer()
                Text("\(commentText.count) / 800")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(commentText.count >= 800 ? Color.red.opacity(0.85) : Color.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4).padding(.bottom, 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder private var commentAttachmentPreview: some View {
        if case .resolving = commentAttachmentState {
            Text("Analyzing link...")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        } else if let attachment = commentSmartAttachment {
            AmenUniversalLinkCard(attachment: attachment, mode: .composerPreview)
            if !commentMentionedLinks.isEmpty {
                Text("Mentioned Links (\(commentMentionedLinks.count))")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
        } else if case .blocked = commentAttachmentState {
            Text("Link restricted. Comment will post with plain URL.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        } else if case .failed = commentAttachmentState {
            Text("Preview unavailable. Comment will post normally.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        }
    }

    // Extracted from onChange(of: commentText) to avoid Swift type-checker timeout on the
    // combined closure body (7 nested Tasks + multiple service calls in one expression).
    private func onCommentTextChanged(_ newValue: String) {
        safetyComposer.onTextChange(newValue, contentType: "comment")
        toneGuidanceService?.analyzeText(newValue)
        handleMentionDetection(in: newValue)
        if !newValue.isEmpty { smartReplySuggestions = [] }
        spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: newValue)
        safetyOSTriggers = AmenLocalTriggerEngine.shared.analyze(
            text: newValue,
            surface: replyingTo == nil ? .comment : .reply
        )
        contextualComposerObserver.update(text: newValue)
        resolveCommentAttachmentIfNeeded(for: newValue)
        scriptureDetectionTask?.cancel()
        if newValue.isEmpty {
            detectedComposerScriptureRefs = []
        } else {
            scriptureDetectionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                detectedComposerScriptureRefs = ScriptureVerificationService.shared.detectScriptures(in: newValue)
            }
        }
        if AMENFeatureFlags.shared.smartContextualPromptsEnabled {
            smartPromptIdleTimer?.cancel()
            showIdleReplyPrompt = false
            if replyingTo != nil && newValue.isEmpty {
                smartPromptIdleTimer = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled, commentText.isEmpty, replyingTo != nil else { return }
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                        showIdleReplyPrompt = true
                    }
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

    private func mentionSuggestionButton(for user: AlgoliaUser) -> some View {
        Button {
            insertCommentMention(user)
        } label: {
            HStack(spacing: 6) {
                mentionSuggestionAvatar(for: user)

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
    }

    @ViewBuilder
    private func mentionSuggestionAvatar(for user: AlgoliaUser) -> some View {
        if let urlStr = user.profileImageURL,
           let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                mentionSuggestionAvatarPlaceholder(for: user)
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
        } else {
            mentionSuggestionAvatarPlaceholder(for: user)
        }
    }

    private func mentionSuggestionAvatarPlaceholder(for user: AlgoliaUser) -> some View {
        Circle()
            .fill(Color.purple.opacity(0.15))
            .frame(width: 26, height: 26)
            .overlay(
                Text(user.displayName.prefix(1))
                    .font(.custom("OpenSans-Bold", size: 11))
                    .foregroundStyle(.purple)
            )
    }

    private func bereanSuggestionBanner(_ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("Berean suggested a rewrite")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.purple)
                Spacer()
                Button {
                    dismissBereanSuggestion()
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Rectangle()
                .fill(Color.purple.opacity(0.2))
                .frame(height: 1)

            Text(suggestion)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    applyBereanSuggestion(suggestion)
                } label: {
                    Text("Use this")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.purple, in: Capsule())
                }

                Button {
                    dismissBereanSuggestion()
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

    private func applyBereanSuggestion(_ suggestion: String) {
        commentText = suggestion
        dismissBereanSuggestion()
    }

    private func dismissBereanSuggestion() {
        withAnimation(.easeOut(duration: 0.2)) {
            bereanSuggestion = nil
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotionForInsert

    private func mainCommentRow(for commentWithReplies: CommentWithReplies) -> some View {
        let comment = commentWithReplies.comment
        // [AGENT-4] Insert animation: spec opacity+offset(y:12) with spring(0.4, 0.85)
        // Reduce Motion: opacity-only fade (0.15s)
        let insertTransition: AnyTransition = reduceMotionForInsert
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 12)),
                removal: .opacity
              )

        return PostCommentRow(
            post: post,
            comment: comment,
            isNew: newCommentIds.contains(comment.id ?? ""),
            isHighlighted: transientHighlightedCommentIds.contains(comment.id ?? ""),
            onReply: {
                focusReplyComposer(for: comment)
                HapticManager.impact(style: .light)
            },
            onReplyWithQuote: { quoteText in
                focusReplyComposer(for: comment, quoteText: quoteText)
            },
            onDelete: {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    deleteComment(comment)
                }
            },
            onAmen: {
                toggleAmen(comment: comment)
            },
            onProfileTap: {
                selectedUserId = comment.authorId
                showUserProfile = true
            },
            onToggleThread: {
                toggleThread(for: commentWithReplies)
            },
            isThreadExpanded: expandedThreads.contains(comment.id ?? ""),
            replyCount: commentWithReplies.replies.count,
            currentTime: currentTime
        )
        .id("\(comment.id ?? "")-main")
        .transition(insertTransition)
    }

    private func focusReplyComposer(for comment: Comment, quoteText: String? = nil) {
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            replyingTo = comment
            if let quoteText {
                commentText = quoteText
            }
            isInputFocused = true
        }
        // Scroll composer into view so the "Replying to" chip is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("commentsBottom", anchor: .bottom)
            }
        }
    }

    private func toggleThread(for commentWithReplies: CommentWithReplies) {
        let commentId = commentWithReplies.comment.id ?? ""

        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
            if expandedThreads.contains(commentId) {
                expandedThreads.remove(commentId)
            } else {
                expandedThreads.insert(commentId)
                loadThreadSummaryIfNeeded(for: commentWithReplies)
            }
        }
    }

    private func loadThreadSummaryIfNeeded(for commentWithReplies: CommentWithReplies) {
        guard commentWithReplies.replies.count >= 10,
              let commentId = commentWithReplies.comment.id,
              threadSummaries[commentId] == nil else {
            return
        }

        Task {
            do {
                if let summary = try await summarizationService?.getSummary(
                    for: commentId,
                    replies: commentWithReplies.replies
                ) {
                    await MainActor.run {
                        threadSummaries[commentId] = summary
                    }
                }
            } catch {
                dlog("❌ [SUMMARY] Failed to load: \(error)")
            }
        }
    }

    @ViewBuilder private var momentAnchorCapsuleRow: some View {
        if let anchor = activeMomentAnchor {
            activeMomentAnchorCapsule(anchor)
        }
    }

    private func activeMomentAnchorCapsule(_ anchor: MediaMomentAnchor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
            Text("Commenting on \(anchor.displayLabel)")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
            Spacer()
            Button {
                mediaMomentInteraction.clearActiveCommentAnchor()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(.black.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.05)))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func attachedPhotoPreview(_ uiImage: UIImage) -> some View {
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
                clearAttachedPhoto()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(18))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .background(Color(uiColor: .systemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func clearAttachedPhoto() {
        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
            commentPhotoData = nil
            selectedPhotoItem = nil
        }
    }

    @ViewBuilder
    private func replyRow(_ reply: Comment, parent: Comment) -> some View {
        HStack(spacing: 0) {
            // [AGENT-4] Spec hairline rail: 1pt width, 12pt left padding
            // Light: Color.primary.opacity(0.08) | Dark: amenGold.opacity(0.2)
            Rectangle()
                .fill(colorSchemeForReplyRail == .dark
                      ? Color.amenGold.opacity(0.2)
                      : Color.primary.opacity(0.08))
                .frame(width: 1)
                .padding(.leading, 12)
                .transition(.scale(scale: 0.1, anchor: .top))

            PostCommentRow(
                post: post,
                comment: reply,
                isReply: true,
                isNew: newCommentIds.contains(reply.id ?? ""),
                isHighlighted: transientHighlightedCommentIds.contains(reply.id ?? ""),
                onReply: {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                        replyingTo = parent
                        isInputFocused = true
                    }
                    HapticManager.impact(style: .light)
                },
                onReplyWithQuote: { quoteText in
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                        replyingTo = parent
                        commentText = quoteText
                        isInputFocused = true
                    }
                },
                onDelete: {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
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
    }

    @ViewBuilder
    private func expandedRepliesSection(for commentWithReplies: CommentWithReplies) -> some View {
        let commentId = commentWithReplies.comment.id ?? ""
        if !commentWithReplies.replies.isEmpty && expandedThreads.contains(commentId) {
            // [AGENT-4] Spec: 10pt spacing between replies
            VStack(spacing: 10) {
                threadSummarySection(for: commentWithReplies)

                ForEach(commentWithReplies.replies, id: \.stableId) { reply in
                    replyRow(reply, parent: commentWithReplies.comment)
                        .id(replyRowID(for: reply))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func threadSummarySection(for commentWithReplies: CommentWithReplies) -> some View {
        if commentWithReplies.replies.count >= 10,
           let commentId = commentWithReplies.comment.id {
            if let summary = threadSummaries[commentId] {
                ThreadSummaryView(summary: summary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if summarizationService?.isGeneratingSummary == true {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.secondary)

                    Text("Generating thread summary...")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func replyRowID(for reply: Comment) -> String {
        (reply.id ?? reply.stableId) + "-reply"
    }

    private func resolveCommentAttachmentIfNeeded(for text: String) {
        commentAttachmentTask?.cancel()
        commentAttachmentTask = Task { @MainActor in
            let urls = smartAttachmentResolver.extractSupportedURLs(from: text)
            guard let url = urls.first else {
                commentSmartAttachment = nil
                commentMentionedLinks = []
                commentAttachmentState = .empty
                return
            }
            commentMentionedLinks = Array(urls.dropFirst())
            if commentSmartAttachment?.canonicalUrl == url.absoluteString { return }
            commentAttachmentState = .resolving
            do {
                let resolved = try await smartAttachmentResolver.resolve(url: url, source: "commentPaste")
                if resolved.safetyStatus == .blocked {
                    commentSmartAttachment = nil
                    commentAttachmentState = .blocked("blocked")
                    return
                }
                commentSmartAttachment = resolved
                commentAttachmentState = .resolved(resolved)
            } catch {
                commentAttachmentState = .failed(.resolveFailed)
            }
        }
    }

    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        // P0-1 FIX: Prevent duplicate submissions
        guard !isSubmittingComment else { return }

        if let trigger = safetyOSTriggers.first(where: \.shouldShowDiscernmentSheet),
           !bypassSpiritualDiscernmentGate {
            activeSafetyOSTrigger = trigger
            return
        }

        if spiritualComposeAnalysis.shouldShowDiscernmentGate && !bypassSpiritualDiscernmentGate {
            showSpiritualDiscernmentGate = true
            return
        }
        bypassSpiritualDiscernmentGate = false

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
        let submittedSafetyOSTriggers = AmenLocalTriggerEngine.shared.analyze(
            text: text,
            surface: replyingTo == nil ? .comment : .reply
        )

        // Wellness pause: offer reflection on borderline session content
        if !wellnessClearedForComment,
           let wellnessCtx = AmenWellnessInterventionService.shared.checkBeforePost(text: text) {
            pendingWellnessContext = wellnessCtx
            return
        }
        wellnessClearedForComment = false

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
                case .underReview: visibilityString = "everyone" // treat as public for comment gating
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

            // ── Trust + Safety backend preflight (authoritative) ──────────────
            if AmenSafetyFeatureFlags.shared.contentPreflightEnabled,
               !AmenSafetyFeatureFlags.shared.trustSafetyKillSwitch {
                let surface: ContentSurface = replyingTo == nil ? .comment : .reply
                if !botChallengeCleared {
                    let botOutcome = await AmenBotDefenseService.shared.evaluateBeforeAction(type: .comment)
                    if botOutcome != .proceed {
                        await MainActor.run {
                            isSubmittingComment = false
                            commentText = text
                            if botOutcome == .challengeRequired {
                                showBotChallenge = true
                            } else {
                                errorMessage = "Please slow down before commenting again."
                                showError = true
                            }
                        }
                        return
                    }
                }
                botChallengeCleared = false
                let tsCanPost = await AmenContentPreflightService.shared.runFinalPreflight(
                    text: text,
                    surface: surface,
                    contentId: UUID().uuidString
                )
                if !tsCanPost {
                    await MainActor.run {
                        errorMessage = AmenTrustSafetyService.shared.lastDecision?.userFacingReason
                            ?? "This comment cannot be posted."
                        showError = true
                        isSubmittingComment = false
                        commentText = text
                    }
                    return
                }
                AmenBotDefenseService.shared.trackComment(text)
            }
            // ─────────────────────────────────────────────────────────────────

            // Clear comment text after validation passes
            await MainActor.run {
                commentText = ""
                toneGuidanceService?.clearFeedback()
                bereanSuggestion = nil  // Dismiss any pending Berean suggestion
                // Keep isSubmittingComment = true until the write completes to prevent duplicates
            }

            // FIX: Insert an optimistic placeholder for top-level comments so the user
            // sees their comment immediately while the RTDB write is in-flight.
            // Replies expand an existing thread row, so they don't need a separate placeholder.
            // The placeholder is removed: (a) on success — the RTDB listener delivers the real
            //   comment and the listener's de-duplication by commentId replaces it naturally,
            //   or (b) on error — we roll back by filtering it out and restoring commentText.
            let optimisticId: String? = replyingTo == nil ? UUID().uuidString : nil
            if let oid = optimisticId {
                let uid = FirebaseManager.shared.currentUser?.uid ?? ""
                let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName")
                    ?? Auth.auth().currentUser?.displayName
                    ?? ""
                let username = UserDefaults.standard.string(forKey: "currentUserUsername") ?? ""
                let placeholder = Comment(
                    id: oid,
                    postId: postId,
                    authorId: uid,
                    authorName: displayName,
                    authorUsername: username,
                    authorInitials: currentUserInitials,
                    authorProfileImageURL: currentUserProfileImageURL,
                    content: text,
                    createdAt: Date(),
                    updatedAt: Date(),
                    isEdited: false,
                    amenCount: 0,
                    lightbulbCount: 0,
                    replyCount: 0,
                    amenUserIds: []
                )
                await MainActor.run {
                    optimisticCommentTempId = oid
                    commentsWithReplies.append(CommentWithReplies(comment: placeholder))
                }
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
                        post: self.post
                    )
                    newCommentId = newComment.id
                    
                    // ✅ DON'T add reply to local UI - let the real-time listener handle it
                    await MainActor.run {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
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
                        post: self.post
                    )
                    newCommentId = newComment.id
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "comment"))
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
                        mediaMomentInteraction.clearActiveCommentAnchor()
                    }
                }
                
                // Track new comment for highlight animation
                if let id = newCommentId {
                    await MainActor.run {
                        _ = withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.6))) {
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
                
                // Haptic feedback + success seal
                await MainActor.run {
                    // Remove the optimistic placeholder now that the write succeeded.
                    // The RTDB real-time listener will deliver the authoritative comment
                    // within milliseconds; removing the placeholder first prevents a
                    // brief duplicate row while the listener catches up.
                    if let oid = optimisticId {
                        commentsWithReplies.removeAll { $0.id == oid }
                        optimisticCommentTempId = nil
                    }
                    // haptic
                    HapticManager.notification(type: .success)
                    commentSeal.trigger()
                    successChips.show("Comment sent")
                    triggerCommentSafetyOSFeedback(for: submittedSafetyOSTriggers)
                    isSubmittingComment = false  // Re-enable after write completes
                }
            } catch {
                await MainActor.run {
                    // Roll back the optimistic placeholder and restore text so the user
                    // can edit and retry.
                    if let oid = optimisticId {
                        commentsWithReplies.removeAll { $0.id == oid }
                        optimisticCommentTempId = nil
                    }
                    let nsError = error as NSError
                    if nsError.domain == "CommentService" && nsError.code == -11 {
                        // Firestore daily rate limit — show inline banner and disable send button
                        rateLimitMessage = nsError.localizedDescription
                    } else if nsError.domain == "CommentService" && nsError.code == -20 {
                        // [AGENT-3] Rolling-window rate limit — show cooldown timer
                        // Extract retryAfter from userInfo if present; fall back to 60 s.
                        let retryAfter = nsError.userInfo["retryAfter"] as? TimeInterval ?? 60
                        rateLimitMessage = "Slow down — give the conversation room to breathe."
                        if retryAfter > 0 {
                            startCooldownTimer(remaining: retryAfter)
                        }
                        commentText = text // Restore text so the user can retry
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

    private func triggerCommentSafetyOSFeedback(for triggers: [AmenTriggerResult]) {
        guard let policy = AmenLocalTriggerEngine.shared.effectPolicy(for: triggers) else {
            return
        }

        activeSafetyOSEffectPolicy = policy
        safetyOSEffectSeed = UUID()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(policy.durationMs) * 1_000_000)
            if activeSafetyOSEffectPolicy == policy {
                activeSafetyOSEffectPolicy = nil
            }
        }
    }

    private func handleSafetyOSComposerAction(_ action: AmenDiscernmentAction, trigger: AmenTriggerResult) {
        switch action {
        case .editWithGrace, .cancel:
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isInputFocused = true
        case .rewriteGently, .addContext:
            if let replacement = AmenLocalTriggerEngine.shared.suggestedRewrite(for: trigger, originalText: commentText) {
                commentText = replacement
                spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: replacement)
                safetyOSTriggers = AmenLocalTriggerEngine.shared.analyze(
                    text: replacement,
                    surface: replyingTo == nil ? .comment : .reply
                )
            }
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isInputFocused = true
        case .pauseAndPray:
            commentText = "I want to pause and pray before I say more."
            spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: commentText)
            safetyOSTriggers = AmenLocalTriggerEngine.shared.analyze(
                text: commentText,
                surface: replyingTo == nil ? .comment : .reply
            )
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isInputFocused = true
        case .saveDraft:
            activeSafetyOSTrigger = nil
            bypassSpiritualDiscernmentGate = false
        case .openScripture, .joinPrayer, .keepAsText, .postAnyway:
            bypassSpiritualDiscernmentGate = true
            activeSafetyOSTrigger = nil
            submitComment()
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
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
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
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
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

        // Moderation filter (AGENT-2 FIX): General users must never see hidden or removed comments.
        // Only `.approved` and `.pending` states are visible. `.rejected`, `.removed`, `.hidden`,
        // `.escalated`, and `.flagged` are kept off the read path.
        let visibleComments = allComments.filter {
            $0.approvalStatus == nil || $0.approvalStatus == "approved" || $0.approvalStatus == "pending"
        }

        // Build commentsWithReplies from service data
        var newCommentsWithReplies: [CommentWithReplies] = []

        for comment in visibleComments {
            guard let commentId = comment.id else {
                continue
            }

            // Also filter replies from blocked users and by moderation state
            let rawReplies = commentService.commentReplies[commentId] ?? []
            let unblocked = blockedUsers.isEmpty ? rawReplies : rawReplies.filter { !blockedUsers.contains($0.authorId) }
            let replies = unblocked.filter {
                $0.approvalStatus == nil || $0.approvalStatus == "approved" || $0.approvalStatus == "pending"
            }

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

            // Phase 6: Analyze thread languages for multilingual bridge
            if AMENFeatureFlags.shared.conversationBridgeEnabled {
                let allComments = newCommentsWithReplies.flatMap { [$0.comment] + $0.replies }
                Task { await commentBridge.analyzeThread(comments: allComments) }
            }

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
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
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
                dlog("❌ [APPROVAL] Failed to update comment status: \(error)")
            }
        }
    }
}

// MARK: - Comment Row

private struct PostCommentRow: View {
    let post: Post
    let comment: Comment
    var isReply: Bool = false
    var isNew: Bool = false
    var isHighlighted: Bool = false
    let onReply: () -> Void
    let onReplyWithQuote: (String) -> Void
    let onDelete: () -> Void
    let onAmen: () -> Void
    let onProfileTap: () -> Void
    var onToggleThread: (() -> Void)? = nil
    var isThreadExpanded: Bool = true
    var replyCount: Int = 0
    var currentTime: Date = Date() // For timestamp auto-refresh

    // [AGENT-4] Reduce Motion support
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var followService = FollowService.shared

    @State private var showOptions = false
    @State private var hasAmened = false
    @State private var localAmenCount: Int = 0
    @State private var didJustFollow = false  // Optimistic follow state
    @State private var showReportSheet = false  // Report reason picker
    @State private var activeCommentSheet: CommentSheet?
    @State private var textSelection: PostTextSelection?
    @State private var isTextSelecting = false
    @State private var showSoftReactions = false
    // [AGENT-4] Reaction scale state for spec-compliant tap animation
    @State private var amenReactionScale: CGFloat = 1.0
    // reaction picker is handled by AMENReactionSystem (.reactionPicker modifier on MentionTextView)
    
    private enum CommentSheet: Identifiable {
        case quoteComposer(QuoteComposerContext)
        case share(String)
        case berean(String)

        var id: String {
            switch self {
            case .quoteComposer(let context):
                return "quoteComposer_\(context.id.uuidString)"
            case .share(let text):
                return "share_\(text.hashValue)"
            case .berean(let query):
                return "berean_\(query.hashValue)"
            }
        }
    }
    
    private var isOwnComment: Bool {
        comment.authorId == FirebaseManager.shared.currentUser?.uid
    }
    
    /// True when the current user should see the follow chip for this commenter.
    private var showFollowChip: Bool {
        guard !isOwnComment else { return false }
        guard !didJustFollow else { return false }
        return !followService.following.contains(comment.authorId)
    }

    @ViewBuilder
    private var commentSelectableText: some View {
        // [AGENT-4] Body font: spec 15pt top-level, 13pt reply
        let base = SelectablePostTextView(
            text: comment.content,
            mentions: nil,
            font: UIFont(name: "OpenSans-Regular", size: isReply ? 13 : 15) ?? .systemFont(ofSize: isReply ? 13 : 15),
            lineSpacing: 3,
            lineLimit: nil,
            onMentionTap: { _ in },
            onTextTap: {
                if textSelection != nil {
                    clearTextSelection()
                }
            },
            selection: $textSelection,
            isSelecting: $isTextSelecting
        )

        if isTextSelecting {
            base
        } else {
            base.reactionPicker(
                id: comment.id ?? UUID().uuidString,
                isFromCurrentUser: false,
                context: .comment,
                selectedEmoji: hasAmened ? "❤️" : nil,
                onSelect: { emoji in
                    if emoji == "❤️" || emoji == "🙏" {
                        // Map heart/amen reactions to the existing amen toggle
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.5))) {
                            hasAmened.toggle()
                        }
                        onAmen()
                    }
                    // Future: route other emoji reactions to their own handlers
                }
            )
        }
    }

    private var avatarButton: some View {
        Button {
            onProfileTap()

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
                    commentInitialsAvatar
                }
            } else {
                commentInitialsAvatar
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var commentInitialsAvatar: some View {
        Circle()
            .fill(.black)
            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
            .overlay(
                Text(comment.authorInitials)
                    .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                    .foregroundStyle(.white)
            )
    }

    private var authorHeaderRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                // [AGENT-4] Author name: spec 13pt semibold (both levels per spec)
                Text(comment.authorName)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)

                // Verified badge
                if VerifiedBadgeHelper.shared.isVerified(userId: comment.authorId) {
                    VerifiedBadge(
                        type: VerifiedBadgeHelper.shared.getVerificationType(userId: comment.authorId),
                        size: isReply ? 12 : 13
                    )
                }
            }

            // [AGENT-4] Username: .secondary (adaptive, dark-mode safe)
            Text(comment.authorUsername.hasPrefix("@") ? comment.authorUsername : "@\(comment.authorUsername)")
                .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                .foregroundStyle(.secondary)

            // Subtle follow chip — only shown when not yet following this commenter
            if showFollowChip {
                Button {
                    didJustFollow = true
                    HapticManager.impact(style: .light)
                    Task {
                        try? await FollowService.shared.followUser(userId: comment.authorId)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.systemScaled(isReply ? 8 : 9, weight: .semibold))
                        Text("Follow")
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: didJustFollow)
            }

            Text("•")
                .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                .foregroundStyle(.secondary)

            // [AGENT-4] Timestamp: spec 12pt regular, .secondary (adaptive)
            Text(timeAgoString(for: comment.createdAt, currentTime: currentTime))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var contentBlock: some View {
        ZStack(alignment: .topLeading) {
            commentSelectableText
                .frame(maxWidth: .infinity, alignment: .leading)

            if let selection = textSelection {
                GeometryReader { proxy in
                    HighlightActionCapsule(
                        onQuote: { handleQuoteSelection(selection) },
                        onReply: { handleReplyWithQuote(selection) },
                        onSave: { handleSaveSelection(selection) },
                        onShare: { handleShareSelection(selection) },
                        onBerean: { handleBereanSelection(selection) }
                    )
                    .position(actionCapsulePosition(for: selection.rect, in: proxy.size))
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsRow: some View {
        HStack(spacing: 20) {
            // [AGENT-4] Amen reaction: spec-compliant scale 1.0→1.3→1.0, spring(response:0.35, dampingFraction:0.7)
            // Reduce Motion: opacity-only fade, no scale
            Button {
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hasAmened.toggle()
                    }
                } else {
                    hasAmened.toggle()
                    // Bounce: scale up then back down
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        amenReactionScale = 1.3
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            amenReactionScale = 1.0
                        }
                    }
                }
                onAmen()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: hasAmened ? "heart.fill" : "heart")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(hasAmened ? Color.red : Color.secondary)
                        .scaleEffect(reduceMotion ? 1.0 : amenReactionScale)

                    if comment.amenCount > 0 {
                        Text("\(comment.amenCount)")
                            .font(.custom("OpenSans-Medium", size: 13))
                            .foregroundStyle(hasAmened ? Color.red : Color.secondary)
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
                            .font(.systemScaled(12))

                        if comment.replyCount > 0 {
                            MorphingBadgeView(count: comment.replyCount, useDot: isThreadExpanded)
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
                                .font(.systemScaled(10, weight: .semibold))

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
                        .font(.systemScaled(12))
                        .foregroundStyle(.black.opacity(0.6))
                }
                .accessibilityLabel("Comment options")
                .accessibilityHint("Double tap to delete this comment")
                .confirmationDialog("Comment Options", isPresented: $showOptions) {
                    Button("Delete Comment", role: .destructive) {
                        onDelete()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author and time
            authorHeaderRow

            // Content with highlight-to-quote support
            contentBlock

            // Phase 6: Language indicator for foreign-language comments
            CommentBridgeRow(comment: comment)

            // Translation affordance (lightweight, inline, non-blocking)
            CommentTranslationRow(
                text: comment.content,
                commentId: comment.id ?? "unknown",
                isPublicContent: true
            )

            // Actions
            actionsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarButton
            contentColumn
        }
        .padding(.horizontal, isReply ? 12 : 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.82).opacity(isHighlighted ? 0.55 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(isHighlighted ? 0.4 : 0), lineWidth: 0.8)
        )
        .onLongPressGesture(minimumDuration: 0.35) {
            guard LiquidGlassEffectsFlags.reactionSheet, !isTextSelecting else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showSoftReactions = true
            }
        }
        .overlay(alignment: .topLeading) {
            if showSoftReactions {
                VStack(alignment: .leading, spacing: 6) {
                    SoftReactionSheet(actions: ["❤️", "🙏", "👍"]) { action in
                        if action == "❤️" || action == "🙏" {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                                hasAmened.toggle()
                            }
                            onAmen()
                        }
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSoftReactions = false
                        }
                    }

                    // Spiritual silent reactions — no public counter shown to anyone
                    SilentReactionBar { reactionType in
                        guard let commentId = comment.id else { return }
                        Task {
                            await AmenSpiritualCloudService.shared.addSilentReaction(
                                sourceId: commentId,
                                sourceType: "comment",
                                reactionType: reactionType
                            )
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSoftReactions = false
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .offset(x: isReply ? 44 : 52, y: -8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onTapGesture {
            if showSoftReactions {
                withAnimation(.easeOut(duration: 0.2)) { showSoftReactions = false }
            }
        }
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
                            dlog("❌ Failed to block user: \(error)")
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
                            dlog("❌ Failed to mute user: \(error)")
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
        .sheet(item: $activeCommentSheet) { sheet in
            switch sheet {
            case .quoteComposer(let context):
                QuoteComposerView(context: context)
            case .share(let text):
                ShareSheet(items: [text])
            case .berean(let query):
                BereanAIAssistantView(initialQuery: query.isEmpty ? nil : query)
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

    private func clearTextSelection() {
        textSelection = nil
        isTextSelecting = false
    }

    private func actionCapsulePosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        guard !rect.isNull, !rect.isEmpty else {
            return CGPoint(x: size.width * 0.5, y: 24)
        }

        let clampedX = min(max(rect.midX, 90), size.width - 90)
        let capsuleY = max(rect.minY - 26, 22)
        return CGPoint(x: clampedX, y: capsuleY)
    }

    private func handleQuoteSelection(_ selection: PostTextSelection) {
        guard canQuote(post) else {
            HapticManager.notification(type: .warning)
            ToastManager.shared.info("Quoting is not allowed for this post")
            clearTextSelection()
            return
        }
        let context = QuoteComposerContext(
            sourcePost: post,
            sourceAuthorId: comment.authorId,
            sourceAuthorName: comment.authorName,
            sourceAuthorUsername: comment.authorUsername,
            selection: selection
        )
        activeCommentSheet = .quoteComposer(context)
        clearTextSelection()
    }

    private func handleReplyWithQuote(_ selection: PostTextSelection) {
        guard canQuote(post) else {
            HapticManager.notification(type: .warning)
            ToastManager.shared.info("Quoting is not allowed for this post")
            clearTextSelection()
            return
        }
        let excerpt = "“\(selection.text)” — \(comment.authorName)"
        onReplyWithQuote(excerpt + "\n\n")
        clearTextSelection()
    }

    private func handleSaveSelection(_ selection: PostTextSelection) {
        let excerpt = SavedExcerpt(
            postId: post.firestoreId,
            authorId: comment.authorId,
            authorName: comment.authorName,
            excerpt: selection.text
        )
        ExcerptStore.shared.save(excerpt)
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Saved excerpt")
        clearTextSelection()
    }

    private func handleShareSelection(_ selection: PostTextSelection) {
        let excerpt = "“\(selection.text)” — \(comment.authorName)"
        activeCommentSheet = .share(excerpt)
        clearTextSelection()
    }

    private func handleBereanSelection(_ selection: PostTextSelection) {
        let query = "Explain and reflect on: \"\(selection.text)\""
        activeCommentSheet = .berean(query)
        clearTextSelection()
    }

    private func canQuote(_ post: Post) -> Bool {
        let permission = post.quotesAllowed ?? .everyone
        switch permission {
        case .none:
            return false
        case .followers:
            let isUserPost = post.authorId == FirebaseManager.shared.currentUser?.uid
            return followService.following.contains(post.authorId) || isUserPost
        case .everyone:
            return true
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
                            .font(.systemScaled(52))
                            .foregroundStyle(.green)
                        Text("All caught up!")
                            .font(.systemScaled(18, weight: .semibold))
                        Text("No comments waiting for review.")
                            .font(.systemScaled(14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(pendingComments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(comment.authorName)
                                    .font(.systemScaled(14, weight: .semibold))
                                Spacer()
                                Text(comment.createdAt.timeAgoDisplay())
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.secondary)
                            }
                            SmartMessageText(
                                text: comment.content,
                                context: .local(messageId: comment.id ?? UUID().uuidString, surface: "comment_moderation"),
                                foregroundColor: .primary
                            )
                            .font(.systemScaled(14))
                            .lineLimit(4)
                            HStack(spacing: 12) {
                                Button {
                                    onApprove(comment)
                                } label: {
                                    Label("Approve", systemImage: "checkmark.circle.fill")
                                        .font(.systemScaled(13, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    onReject(comment)
                                } label: {
                                    Label("Reject", systemImage: "xmark.circle.fill")
                                        .font(.systemScaled(13, weight: .semibold))
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

extension Notification.Name {
    static let amenMediaCommentAnchorSelected = Notification.Name("amenMediaCommentAnchorSelected")
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
                            .font(.systemScaled(40))
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
                        .font(.systemScaled(15, weight: .semibold))
                }
            }
        }
    }

    private var reasonList: some View {
        List {
            Section {
                Text("Why are you reporting this comment?")
                    .font(.systemScaled(14))
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
                                .font(.systemScaled(16))
                                .foregroundStyle(.primary)
                                .frame(width: 22)
                            Text(reason.rawValue)
                                .font(.systemScaled(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSubmitting {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
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
                .font(.systemScaled(56))
                .foregroundStyle(.green)
            Text("Report Submitted")
                .font(.systemScaled(20, weight: .bold))
            Text("Thank you for helping keep AMEN safe. We review every report.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .font(.systemScaled(16, weight: .semibold))
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
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
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
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                        isPresented = false
                    }
                }

            HStack(spacing: 4) {
                ForEach(Array(reactions.enumerated()), id: \.offset) { index, reaction in
                    Button {
                        onReact(reaction.emoji)
                        // haptic
                        HapticManager.impact(style: .light)
                    } label: {
                        Text(reaction.emoji)
                            .font(.systemScaled(26))
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
            .onTapGesture { } // Intentional: absorbs tap on the capsule background so it does not dismiss the reaction tray overlay
        }
        .onAppear {
            withAnimation { appeared = true }
        }
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
