//
//  PostCard.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Enhanced PostCard with edit/delete functionality and repost tracking
//

import SwiftUI
import UIKit
import Translation
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import Combine
import CoreLocation

@MainActor
struct PostCard: View {
    let post: Post?
    let authorName: String
    let timeAgo: String
    let content: String
    let category: PostCardCategory
    let topicTag: String?
    let isUserPost: Bool // Track if this is the current user's post
    
    // ⚡️ PERFORMANCE FIX: Minimize @ObservedObject to prevent render storms
    // Only observe services where we MUST react to external changes in the view body.
    // All other services are accessed directly for actions only (no observation).
    private let savedPostsService = RealtimeSavedPostsService.shared
    private let followService = FollowService.shared  // ⚡️ Changed from @ObservedObject - use computed property
    private let pinnedPostService = PinnedPostService.shared  // ⚡️ Changed from @ObservedObject
    private let interactionsService = PostInteractionsService.shared
    // Expansion state pulled from service via targeted onReceive — avoids full PostCard
    // body re-evaluation on every PostInteractionsService publish (render storm fix)
    @State private var isPostExpanded = false
    private let postsManager = PostsManager.shared
    private let moderationService = ModerationService.shared
    private let actionMenuCoordinator = AmenPostCardActionMenuCoordinator.shared
    // ⚡️ Local state driven by targeted .onReceive — avoids @ObservedObject render storm on ALL cards
    @State private var isActionMenuActive_state: Bool = false
    @State private var localIsFollowing: Bool = false
    // ✅ Consolidated sheet presentation state to prevent SwiftUI presentation conflicts
    @State private var activeSheet: PostCardSheet? = nil
    // ✅ Removed: Consolidated into PostCardAlert enum to prevent EXC_BAD_ACCESS from stacked alerts
    // @State private var showingDeleteAlert = false
    @State private var showingRepostConfirmation = false
    @State private var showRepostActionSheet = false
    @State private var showQuoteComposer = false
    @State private var hasLitLightbulb = false

    // Staggered entrance animation
    @State private var cardAppeared = false
    @State private var hasSaidAmen = false
    @State private var isLightbulbAnimating = false
    // ❌ REMOVED: @State private var isFollowing = false  // P0 FIX: Replaced with computed property
    @State private var lastProfileNavDate: Date = .distantPast
    @State private var isSaved = false
    @State private var hasReposted = false
    @State private var hasCommented = false  // illuminates comment button after user comments
    @State private var isSaveInFlight = false
    @State private var isDeletingPost = false
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
    @State private var actionMenuButtonFrame: CGRect = .zero
    
    // Testimony resonance micro-copy
    @State private var testimonyResonanceCopy: String = ""
    @State private var showTestimonyResonance: Bool = false
    @State private var testimonyResonanceDismissTask: Task<Void, Never>? = nil

    // Prayer activity
    @State private var isPraying = false
    @State private var prayingNowCount = 0
    @State private var isFasting = false
    
    // Animation timing constants
    private let fastAnimationDuration: Double = 0.15
    private let standardAnimationDuration: Double = 0.2
    private let springResponse: Double = 0.12
    private let springDamping: Double = 0.75
    
    // Moderation confirmations
    // ✅ Removed: Consolidated into PostCardAlert enum to prevent EXC_BAD_ACCESS from stacked alerts
    // @State private var showMuteConfirmation = false
    // @State private var showBlockConfirmation = false
    // @State private var showMuteSuccess = false
    // @State private var showBlockSuccess = false
    // @State private var showNotInterestedConfirmation = false
    // @State private var showNotInterestedSuccess = false
    
    // Scripture attachment detail
    @State private var postCardScriptureAttachment: ScriptureAttachment?
    @State private var showPostCardScriptureDetail = false
    
    // Error handling
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    // Local mirror of BereanLiveActivityService.showFallbackSheet — avoids Binding(get:set:)
    // polling the singleton on every body render which can destabilize the view update cycle.
    @State private var showBereanFallbackSheet = false
    
    // ✅ Consolidated alert state to prevent SwiftUI presentation conflicts
    enum PostCardAlert: Identifiable {
        case notInterested
        case feedbackReceived
        case error(String)
        case muteConfirmation(String)
        case blockConfirmation(String)
        case muteSuccess(String)
        case blockSuccess(String)
        case deleteConfirmation
        
        var id: String {
            switch self {
            case .notInterested: return "notInterested"
            case .feedbackReceived: return "feedbackReceived"
            case .error(let msg): return "error-\(msg.hashValue)"
            case .muteConfirmation(let name): return "muteConfirmation-\(name.hashValue)"
            case .blockConfirmation(let name): return "blockConfirmation-\(name.hashValue)"
            case .muteSuccess(let name): return "muteSuccess-\(name.hashValue)"
            case .blockSuccess(let name): return "blockSuccess-\(name.hashValue)"
            case .deleteConfirmation: return "deleteConfirmation"
            }
        }
    }
    @State private var activeAlert: PostCardAlert?
    
    // ✅ Single source of truth for sheet presentation
    fileprivate enum PostCardSheet: Identifiable {
        case options
        case whyThisPost(post: Post)
        case userProfile(userId: String)
        case mentionedProfile(userId: String)
        case edit(post: Post)
        case share(post: Post, churchNote: ChurchNote?)
        case postDetail(post: Post)
        case comments(post: Post)
        case report(post: Post)
        case churchNoteDetail(note: ChurchNote)
        case reasoningThread(postId: String, postText: String, authorName: String)
        case tip(creatorId: String, creatorName: String)
        case berean(initialQuery: String)
        case quoteComposer(context: QuoteComposerContext)
        case commentsWithQuote(post: Post, prefill: String)
        case shareExcerpt(text: String, attribution: String)
        
        var id: String {
            switch self {
            case .options:
                return "options"
            case .whyThisPost(let post):
                return "why-this-post-\(Self.stablePostId(post))"
            case .userProfile(let userId):
                return "profile-\(userId)"
            case .mentionedProfile(let userId):
                return "mention-profile-\(userId)"
            case .edit(let post):
                return "edit-\(Self.stablePostId(post))"
            case .share(let post, _):
                return "share-\(Self.stablePostId(post))"
            case .postDetail(let post):
                return "detail-\(Self.stablePostId(post))"
            case .comments(let post):
                return "comments-\(Self.stablePostId(post))"
            case .report(let post):
                return "report-\(Self.stablePostId(post))"
            case .churchNoteDetail(let note):
                return "church-note-\(note.id ?? "unknown")"
            case .reasoningThread(let postId, _, _):
                return "reasoning-\(postId)"
            case .tip(let creatorId, _):
                return "tip-\(creatorId)"
            case .berean(let initialQuery):
                return "berean-\(initialQuery.hashValue)"
            case .quoteComposer(let context):
                return "quote-\(context.id.uuidString)"
            case .commentsWithQuote(let post, _):
                return "comments-quote-\(Self.stablePostId(post))"
            case .shareExcerpt(let text, let attribution):
                return "share-excerpt-\(text.hashValue)-\(attribution.hashValue)"
            }
        }
        
        private static func stablePostId(_ post: Post) -> String {
            if !post.firestoreId.isEmpty { return post.firestoreId }
            if let firebaseId = post.firebaseId, !firebaseId.isEmpty { return firebaseId }
            return post.id.uuidString
        }
    }
    
    // Real-time interaction counts
    @State private var lightbulbCount = 0
    @State private var amenCount = 0
    @State private var commentCount = 0
    @State private var repostCount = 0

    // Church Note
    @State private var churchNote: ChurchNote?
    
    // ✅ Real-time profile image
    @State private var currentProfileImageURL: String?
    // ⚡️ PERFORMANCE FIX: Removed per-card Firestore listeners - rely on Post updates from PostsManager
    // Per-card listeners create 20+ active Firestore connections during scroll, causing network thrashing
    
    // Translation state — managed by TranslationService
    @State private var showTranslatedContent = false
    @State private var translatedContent: String?
    @State private var detectedLanguage: String?
    @State private var detectedLanguageConfidence: Double = 0
    @State private var translationUIState: TranslationUIState = .available
    @State private var showTranslationInfoSheet = false
    @State private var isTranslating = false
    @State private var currentTranslationMode: TranslationMode = .literal
    @State private var isRefinementLoading = false
    // Apple Translation framework: session-based config for language download prompts
    @State private var appleTranslationConfig: Translation.TranslationSession.Configuration?
    @State private var difficultyScore: ContentDifficultyScore?
    @State private var detectedContextTerms: [DetectedTerm] = []
    @State private var selectedContextTerm: DetectedTerm?

    // Highlight-to-quote selection state
    @State private var textSelection: PostTextSelection?
    @State private var isTextSelecting = false
    // PERF: Legacy translationService kept for backward compat; new service is action-only (not observed)
    // Use computed properties to defer access until actually needed (avoids initialization crash)
    @MainActor
    private var translationService: PostTranslationService {
        PostTranslationService.shared
    }
    @MainActor
    private var newTranslationService: TranslationService {
        TranslationService.shared
    }
    
    // P1-B FIX: Content expansion state now lives in PostInteractionsService
    // (keyed by stablePostId) so it survives SwiftUI view recycling during scroll.
    // Reading and writing goes through interactionsService.isExpanded / toggleExpanded.
    
    // P0 FIX: Stable post ID for reactions/interactions
    // Always use firebaseId if available, fallback to UUID
    // This prevents reactions from being tied to wrong IDs when firestoreId changes
    private var stablePostId: String {
        post?.firebaseId ?? post?.id.uuidString ?? ""
    }

    private var actionMenuCardID: String {
        if let post, !post.firestoreId.isEmpty {
            return post.firestoreId
        }
        if !stablePostId.isEmpty {
            return stablePostId
        }
        return "preview-\(authorName)-\(timeAgo)-\(content.prefix(24))"
    }

    // ⚡️ Use computed property that reads directly (no observation)
    private var isActionMenuPresented: Bool {
        isActionMenuActive
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
            case .testimonies: return "" // Remove Testimonies badge for cleaner design
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
                presentSheet(.userProfile(userId: post.authorId))
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

            // Score content difficulty for Understand pill (on-device, zero API cost)
            if AMENFeatureFlags.shared.readabilityLayerEnabled && AMENFeatureFlags.shared.contentDifficultyScoring {
                difficultyScore = ContentDifficultyScorer.shared.score(text: content)
            }

            // Detect faith context terms (on-device, zero API cost)
            if AMENFeatureFlags.shared.contextBridgeEnabled {
                let raw = ContextTermDetector.shared.detectTerms(in: content)
                detectedContextTerms = ContextAssistService.shared.filterDismissed(raw)
            }
        }
        .onChange(of: post?.authorProfileImageURL) { oldValue, newValue in
            // Sync currentProfileImageURL when Post updates from PostsManager
            if let newURL = newValue, !newURL.isEmpty, newURL != currentProfileImageURL {
                dlog("🔄 [POSTCARD] Profile image updated: \(newURL.prefix(50))...")
                currentProfileImageURL = newURL
            }
        }
        .sheet(item: $selectedContextTerm) { term in
            ContextCardView(
                term: term,
                onDismiss: {
                    ContextAssistService.shared.dismissTerm(term.term)
                    selectedContextTerm = nil
                },
                onSave: {
                    ContextAssistService.shared.saveTerm(term.term)
                    selectedContextTerm = nil
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .onAppear {
                AccessibilitySignalCollector.shared.recordSignal(.contextCardOpened)
                AccessibilitySuggestionEngine.shared.evaluate()
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
            
            Text(userInitials)
                .font(AMENFont.bold(16))
                .foregroundStyle(.primary)
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
        LinearGradient(
            colors: [Color(.secondarySystemBackground), Color(.systemFill)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func quoteSnippetView(_ quote: PostQuoteMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(quote.sourceAuthorName)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.primary)
                if let username = quote.sourceAuthorUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
            }

            Text(quote.sourceExcerpt)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )
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
        FollowBadgeView(
            isFollowed: Binding(
                get: { isFollowing },
                set: { _ in }
            ),
            onToggle: { toggleActionMenu() },
            openMenuMode: true
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: AmenPostCardActionMenuAnchorPreferenceKey.self,
                        value: proxy.frame(in: .named(actionMenuCardID))
                    )
            }
        )
        .offset(x: 3, y: 3)
    }
    
    // MARK: - Follow Actions
    
    // Follow state: local @State updated by .onReceive — only re-renders cards whose state actually changes
    private var isFollowing: Bool { localIsFollowing }
    
    // ⚡️ PERFORMANCE FIX: Computed property for pinned state (no observation)
    private var isPinned: Bool {
        guard let post = post else { return false }
        return PinnedPostService.shared.isPostPinned(post.firestoreId)
    }
    
    // Action menu state: read from local @State (updated by .onReceive in body)
    private var isActionMenuActive: Bool { isActionMenuActive_state }
    
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

    @MainActor
    private func toggleActionMenu() {
        HapticManager.impact(style: .light)
        withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.84))) {
            if isActionMenuPresented {
                actionMenuCoordinator.activePostId = nil
            } else {
                actionMenuCoordinator.activePostId = actionMenuCardID
            }
        }
    }

    @MainActor
    private func closeActionMenu(animated: Bool = true) {
        guard isActionMenuPresented else { return }
        if animated {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.9))) {
                actionMenuCoordinator.activePostId = nil
            }
        } else {
            actionMenuCoordinator.activePostId = nil
        }
    }

    @MainActor
    private func presentSheet(_ sheet: PostCardSheet) {
        guard activeSheet == nil else { return }
        activeSheet = sheet
    }

    @MainActor
    private func dismissSheet() {
        activeSheet = nil
    }

    private func clearTextSelection() {
        textSelection = nil
        isTextSelecting = false
    }

    private func actionCapsulePosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let isRectValid = !rect.isNull
            && !rect.isEmpty
            && rect.minX.isFinite
            && rect.minY.isFinite
            && rect.maxX.isFinite
            && rect.maxY.isFinite
        let isSizeValid = size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0

        guard isRectValid, isSizeValid else {
            return CGPoint(x: size.width * 0.5, y: 24)
        }
        let padding: CGFloat = 16
        let fallbackX = size.width * 0.5
        let fallbackY = min(max(CGFloat(24), padding), size.height - padding)
        let midX = rect.midX.isFinite
            ? min(max(rect.midX, padding), size.width - padding)
            : fallbackX
        var y = rect.minY - 26
        if y < padding {
            y = rect.maxY + 26
        }
        y = y.isFinite
            ? min(max(y, padding), size.height - padding)
            : fallbackY
        return CGPoint(x: midX, y: y)
    }

    private func handleQuoteSelection(_ selection: PostTextSelection) {
        guard let post = post else { return }
        guard canQuote(post) else {
            HapticManager.notification(type: .warning)
            ToastManager.shared.info("Quoting is not allowed for this post")
            clearTextSelection()
            return
        }
        let context = QuoteComposerContext(
            sourcePost: post,
            sourceAuthorId: post.authorId,
            sourceAuthorName: post.authorName,
            sourceAuthorUsername: post.authorUsername,
            selection: selection
        )
        presentSheet(.quoteComposer(context: context))
        clearTextSelection()
    }

    private func handleReplyWithQuote(_ selection: PostTextSelection) {
        guard let post = post else { return }
        guard canQuote(post) else {
            HapticManager.notification(type: .warning)
            ToastManager.shared.info("Quoting is not allowed for this post")
            clearTextSelection()
            return
        }
        let excerpt = "“\(selection.text)” — \(authorName)"
        presentSheet(.commentsWithQuote(post: post, prefill: excerpt))
        clearTextSelection()
    }

    private func handleSaveSelection(_ selection: PostTextSelection) {
        guard let post = post else { return }
        let excerpt = SavedExcerpt(postId: post.firestoreId, authorId: post.authorId, authorName: authorName, excerpt: selection.text)
        ExcerptStore.shared.save(excerpt)
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Excerpt saved")
        clearTextSelection()
    }

    private func handleShareSelection(_ selection: PostTextSelection) {
        let attribution = "— \(authorName)"
        presentSheet(.shareExcerpt(text: selection.text, attribution: attribution))
        clearTextSelection()
    }

    private func handleBereanSelection(_ selection: PostTextSelection) {
        let query = bereanQuery(for: selection)
        presentSheet(.berean(initialQuery: query))
        clearTextSelection()
    }

    private func bereanQuery(for selection: PostTextSelection) -> String {
        let excerpt = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.suggestedQuoteType == .verse {
            return "Reflect on this verse: \"\(excerpt)\"\n\nPlease ground your response in Scripture and provide cross-references."
        }
        return "Reflect on this highlighted excerpt: \"\(excerpt)\"\n\nWhat does Scripture say about this, and how should I respond?"
    }

    private func canQuote(_ post: Post) -> Bool {
        let permission = post.quotesAllowed ?? .everyone
        switch permission {
        case .none:
            return false
        case .followers:
            return isFollowing || isUserPost
        case .everyone:
            return true
        }
    }

    @MainActor
    private func handleActionMenuFollowTap() {
        guard !isUserPost else { return }
        closeActionMenu()
        handleFollowButtonTap()
    }

    @MainActor
    private func handleActionMenuProfileTap() {
        guard let post = post, !post.authorId.isEmpty else {
            closeActionMenu()
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastProfileNavDate) > 0.25 else {
            closeActionMenu()
            return
        }
        lastProfileNavDate = now
        closeActionMenu()
        HapticManager.impact(style: .light)
        presentSheet(.userProfile(userId: post.authorId))
        dlog("👤 Opening action menu profile for: \(authorName) (ID: \(post.authorId))")
    }

    @MainActor
    private func presentOptionsSheet() {
        guard activeSheet == nil else { return }
        closeActionMenu(animated: false)
        HapticManager.impact(style: .light)
        presentSheet(.options)
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

    private var optionsQuickActions: [AmenQuickAction] {
        let saveAction = AmenQuickAction(
            title: isSaved ? "Saved" : "Save",
            systemImage: isSaved ? "bookmark.fill" : "bookmark",
            isSelected: isSaved
        ) {
            performOption { toggleSave() }
        }

        let repostAction = AmenQuickAction(
            title: "Repost",
            systemImage: "repeat",
            isEnabled: !isUserPost
        ) {
            performOption { handleRemixAction() }
        }

        let sequenceAction = AmenQuickAction(
            title: "Thread",
            systemImage: "bubble.left.and.text.bubble.right"
        ) {
            performOption {
                guard let post = post else { return }
                presentSheet(.reasoningThread(postId: post.firestoreId, postText: post.content, authorName: authorName))
            }
        }

        return [saveAction, repostAction, sequenceAction]
    }

    private var optionsSections: [AmenOptionsSectionModel] {
        var sections: [AmenOptionsSectionModel] = []

        if isUserPost {
            var userActions: [AmenOptionAction] = []

            if let post = post {
                // ✅ Defensive: Ensure we have a valid firestoreId before accessing it
                let postId = post.firestoreId
                let isPinned = pinnedPostService.isPostPinned(postId)
                userActions.append(
                    AmenOptionAction(
                        title: isPinned ? "Unpin from profile" : "Pin to profile",
                        subtitle: "Choose what leads your profile",
                        systemImage: isPinned ? "pin.slash" : "pin"
                    ) {
                        performOption {
                            Task {
                                do {
                                    try await pinnedPostService.togglePin(postId: postId)
                                    HapticManager.notification(type: .success)
                                } catch {
                                    dlog("❌ Pin error: \(error)")
                                    HapticManager.notification(type: .error)
                                }
                            }
                        }
                    }
                )
            }

            if let post = post, canEditPost(post) {
                userActions.append(
                    AmenOptionAction(
                        title: "Edit Post",
                        subtitle: "Refine wording or details",
                        systemImage: "pencil",
                        showsChevron: true
                    ) {
                        performOption {
                            presentSheet(.edit(post: post))
                        }
                    }
                )
            }

            userActions.append(
                AmenOptionAction(
                    title: "Delete Post",
                    subtitle: "This cannot be undone",
                    systemImage: "trash",
                    isDestructive: true
                ) {
                    performOption { activeAlert = .deleteConfirmation }
                }
            )

            sections.append(AmenOptionsSectionModel(title: "Your Post", actions: userActions))
        }

        var primaryActions: [AmenOptionAction] = []

        if !isUserPost && category == .openTable {
            primaryActions.append(
                AmenOptionAction(
                    title: hasLitLightbulb ? "Remove Inspiration" : "Inspire",
                    subtitle: "Let the author know this helped",
                    systemImage: hasLitLightbulb ? "lightbulb.fill" : "lightbulb"
                ) {
                    performOption { toggleLightbulb() }
                }
            )
        }

        if category == .prayer, let post = post, post.topicTag == "Prayer Request" {
            primaryActions.append(
                AmenOptionAction(
                    title: isFasting ? "End Fast" : "Join Fast",
                    subtitle: "Commit to prayer for this request",
                    systemImage: isFasting ? "flame.fill" : "flame"
                ) {
                    performOption { toggleFasting() }
                }
            )
        }

        primaryActions.append(
            AmenOptionAction(
                title: "Share",
                subtitle: "Send in AMEN or outside",
                systemImage: "square.and.arrow.up"
            ) {
                performOption { sharePost() }
            }
        )

        primaryActions.append(
            AmenOptionAction(
                title: "Reasoning Thread",
                subtitle: "Open the discussion",
                systemImage: "bubble.left.and.text.bubble.right"
            ) {
                performOption {
                    guard let post = post else { return }
                    presentSheet(.reasoningThread(postId: post.firestoreId, postText: post.content, authorName: authorName))
                }
            }
        )

        if !isUserPost {
            primaryActions.append(
                AmenOptionAction(
                    title: "Support Creator",
                    subtitle: "Encourage the author",
                    systemImage: "gift.fill",
                    showsChevron: true
                ) {
                    performOption {
                        guard let post = post, !post.authorId.isEmpty else { return }
                        presentSheet(.tip(creatorId: post.authorId, creatorName: authorName))
                    }
                }
            )
        }

        primaryActions.append(
            AmenOptionAction(
                title: "Copy Link",
                subtitle: "Share this post anywhere",
                systemImage: "link"
            ) {
                performOption { copyLink() }
            }
        )

        primaryActions.append(
            AmenOptionAction(
                title: "Copy Text",
                subtitle: "Copy the post content",
                systemImage: "doc.on.doc"
            ) {
                performOption { copyPostText() }
            }
        )

        if !primaryActions.isEmpty {
            sections.append(AmenOptionsSectionModel(title: "Primary", actions: primaryActions))
        }

        let libraryActions: [AmenOptionAction] = [
            AmenOptionAction(
                title: isSaved ? "Remove from Library" : "Save to Library",
                subtitle: "Keep this for later",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            ) {
                performOption { toggleSave() }
            }
        ]
        sections.append(AmenOptionsSectionModel(title: "Library", actions: libraryActions))

        let folderActions: [AmenOptionAction] = SavedFolder.allCases
            .filter { $0 != .all }
            .map { folder in
                AmenOptionAction(
                    title: folder.rawValue,
                    subtitle: "Saved posts auto-sort by topic",
                    systemImage: folder.icon,
                    showsChevron: false
                ) {
                    performOption { saveToFolder(folder) }
                }
            }

        if !folderActions.isEmpty {
            sections.append(AmenOptionsSectionModel(title: "Folders", actions: folderActions))
        }

        if !isUserPost {
            var safetyActions: [AmenOptionAction] = []

            safetyActions.append(
                AmenOptionAction(
                    title: "Not Interested",
                    subtitle: "Help shape your feed",
                    systemImage: "eye.slash"
                ) {
                    performOption { activeAlert = .notInterested }
                }
            )

            safetyActions.append(
                AmenOptionAction(
                    title: "Report",
                    subtitle: "Help keep AMEN safe",
                    systemImage: "exclamationmark.triangle",
                    isDestructive: true
                ) {
                    performOption {
                        guard let post = post else { return }
                        presentSheet(.report(post: post))
                    }
                }
            )

            safetyActions.append(
                AmenOptionAction(
                    title: "Mute \(authorName)",
                    subtitle: "Quiet posts from this author",
                    systemImage: "speaker.slash",
                    isDestructive: true
                ) {
                    performOption { 
                        let safeName = authorName.isEmpty ? "this user" : authorName
                        activeAlert = .muteConfirmation(safeName)
                    }
                }
            )

            if let postAuthorId = post?.authorId {
                let isRestricted = RestrictService.shared.isRestricted(postAuthorId)
                safetyActions.append(
                    AmenOptionAction(
                        title: isRestricted ? "Unrestrict \(authorName)" : "Restrict \(authorName)",
                        subtitle: "Limit interactions quietly",
                        systemImage: isRestricted ? "checkmark.circle" : "hand.raised.slash"
                    ) {
                        performOption {
                            Task {
                                await RestrictService.shared.loadIfNeeded()
                                await RestrictService.shared.toggleRestrict(postAuthorId)
                                let isNowRestricted = RestrictService.shared.isRestricted(postAuthorId)
                                ToastManager.shared.success(isNowRestricted ? "\(authorName) restricted" : "\(authorName) unrestricted")
                            }
                        }
                    }
                )
            }

            safetyActions.append(
                AmenOptionAction(
                    title: "Block \(authorName)",
                    subtitle: "Stop all interactions",
                    systemImage: "hand.raised",
                    isDestructive: true
                ) {
                    performOption { 
                        let safeName = authorName.isEmpty ? "this user" : authorName
                        activeAlert = .blockConfirmation(safeName)
                    }
                }
            )

            sections.append(AmenOptionsSectionModel(title: "Transparency & Safety", actions: safetyActions))

            // HeyFeed quick-feedback section — lets the user tune their feed from the post itself
            if let post = post {
                let postId   = post.firestoreId
                let authorId = post.authorId
                let topicId: String = {
                    if let tag = post.topicTag, !tag.isEmpty { return tag }
                    switch post.category {
                    case .testimonies: return "testimonies"
                    case .prayer:      return "prayer_requests"
                    case .tip:         return "bible_teaching"
                    case .funFact:     return "bible_teaching"
                    case .openTable:   return "community"
                    }
                }()

                let heyFeedActions: [AmenOptionAction] = [
                    AmenOptionAction(
                        title: "More like this",
                        subtitle: "See more posts like this in your feed",
                        systemImage: "hand.thumbsup"
                    ) {
                        performOption {
                            Task {
                                await HeyFeedPreferencesService.shared.recordMoreLikeThis(postId: postId, authorId: authorId)
                                try? await HeyFeedNLPreferencesService.shared.applyIntent(
                                    HeyFeedParsedIntent(
                                        action: .increase,
                                        targets: [HeyFeedNLTarget(id: topicId, type: .topic, label: topicId.replacingOccurrences(of: "_", with: " ").capitalized, confidence: 1.0)],
                                        duration: .sevenDays,
                                        strength: 0.7,
                                        confidence: 1.0,
                                        originalText: "more like this",
                                        requiresConfirmation: false,
                                        parserVersion: 1
                                    ),
                                    source: "quick_chip"
                                )
                                HeyFeedContradictionService.shared.recordEngage(targetId: topicId)
                                ToastManager.shared.success("Got it — more like this")
                            }
                        }
                    },
                    AmenOptionAction(
                        title: "Less like this",
                        subtitle: "See fewer posts like this",
                        systemImage: "hand.thumbsdown"
                    ) {
                        performOption {
                            Task {
                                await HeyFeedPreferencesService.shared.recordLessLikeThis(postId: postId, authorId: authorId)
                                try? await HeyFeedNLPreferencesService.shared.applyIntent(
                                    HeyFeedParsedIntent(
                                        action: .decrease,
                                        targets: [HeyFeedNLTarget(id: topicId, type: .topic, label: topicId.replacingOccurrences(of: "_", with: " ").capitalized, confidence: 1.0)],
                                        duration: .sevenDays,
                                        strength: 0.7,
                                        confidence: 1.0,
                                        originalText: "less like this",
                                        requiresConfirmation: false,
                                        parserVersion: 1
                                    ),
                                    source: "quick_chip"
                                )
                                HeyFeedContradictionService.shared.recordSkip(targetId: topicId)
                                ToastManager.shared.success("Got it — fewer posts like this")
                            }
                        }
                    },
                    AmenOptionAction(
                        title: "Why this post?",
                        subtitle: "Understand why this appeared in your feed",
                        systemImage: "questionmark.circle"
                    ) {
                        performOption {
                            presentSheet(.whyThisPost(post: post))
                        }
                    }
                ]
                sections.append(AmenOptionsSectionModel(title: "Your Feed", actions: heyFeedActions))
            }
        }

        return sections
    }

    private func performOption(_ action: @escaping () -> Void) {
        dismissSheet()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            action()
        }
    }

    private func feedReasons(for post: Post) -> [FeedReason] {
        var reasons: [FeedReason] = []
        let preferences = HeyFeedPreferencesService.shared.preferences
        let algorithm = HomeFeedAlgorithm.shared
        let interests = algorithm.userInterests
        let followingIds = FollowService.shared.following

        if followingIds.contains(post.authorId) {
            reasons.append(
                FeedReason(
                    type: .followedAuthor,
                    description: "You follow \(post.authorName)"
                )
            )
        }

        if let topicTag = post.topicTag,
           let score = interests.engagedTopics[topicTag],
           score > 50 {
            reasons.append(
                FeedReason(
                    type: .topicMatch,
                    description: "You often engage with #\(topicTag) content"
                )
            )
        } else {
            let categoryKey = post.category.rawValue
            if let preference = interests.preferredCategories[categoryKey], preference > 50 {
                reasons.append(
                    FeedReason(
                        type: .topicMatch,
                        description: "You often engage with \(post.category.displayName) content"
                    )
                )
            }
        }

        let goalKeywords: [String: [String]] = [
            "Consistent Prayer": ["prayer", "pray"],
            "Daily Bible Reading": ["scripture", "bible", "verse"],
            "Build Community": ["community", "fellowship", "church"],
            "Grow in Faith": ["faith", "spiritual", "testimony"],
            "Share the Gospel": ["gospel", "witness", "testimony"],
            "Serve Others": ["serve", "service", "ministry"]
        ]

        for goal in interests.onboardingGoals {
            guard let keywords = goalKeywords[goal] else { continue }
            if keywords.contains(where: { post.content.lowercased().contains($0) }) {
                reasons.append(
                    FeedReason(
                        type: .topicMatch,
                        description: "Aligns with your goal: \(goal)"
                    )
                )
                break
            }
        }

        let engagementCount = post.amenCount + post.commentCount
        if engagementCount > 5 {
            reasons.append(
                FeedReason(
                    type: .engagement,
                    description: "Popular in your community (\(engagementCount) interactions)"
                )
            )
        }

        let hoursSince = Date().timeIntervalSince(post.createdAt) / 3600
        if hoursSince < 6 {
            let recencyLabel = hoursSince < 1 ? "just now" : "\(Int(hoursSince))h ago"
            reasons.append(
                FeedReason(
                    type: .recency,
                    description: "Posted \(recencyLabel)"
                )
            )
        }

        if preferences.boostedAuthors.contains(post.authorId) {
            reasons.append(
                FeedReason(
                    type: .boosted,
                    description: "You boosted content from \(post.authorName)"
                )
            )
        }

        if reasons.isEmpty {
            reasons.append(
                FeedReason(
                    type: .discovery,
                    description: "Suggested based on what's resonating in the AMEN community"
                )
            )
        }

        return reasons
    }

    private func handleRemixAction() {
        guard !isUserPost else { return }
        if hasReposted {
            toggleRepost()
        } else {
            showRepostActionSheet = true
        }
    }

    private func saveToFolder(_ folder: SavedFolder) {
        // Save the post if not already saved
        if !isSaved { toggleSave() }
        // Folders are keyword-based client-side filters. A post appears in a folder when
        // its topicTag matches the folder's keyword list — there is no server-side folder
        // assignment. We tell the user whether this specific post is likely to appear there.
        let postTopicTag = post?.topicTag?.lowercased() ?? ""
        let matchesFolder = folder.keywords.contains { postTopicTag.contains($0) }
        if matchesFolder {
            ToastManager.shared.success("Saved — will appear in \(folder.rawValue)")
        } else {
            ToastManager.shared.success("Saved to library")
        }
    }
    
    @ViewBuilder
    private var userPostMenuOptions: some View {
        // Pin/Unpin post (like Threads)
        if let post = post {
            // ✅ Defensive: Capture postId to avoid potential issues with closure capture
            let postId = post.firestoreId
            let isPinned = pinnedPostService.isPostPinned(postId)
            Button {
                Task {
                    do {
                        try await pinnedPostService.togglePin(postId: postId)
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
                presentSheet(.edit(post: post))
            } label: {
                Label("Edit Post", systemImage: "pencil")
            }
        }
        
        // Users can always delete their posts
        Button(role: .destructive) {
            activeAlert = .deleteConfirmation
        } label: {
            Label("Delete Post", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var commonMenuOptions: some View {
        // Inspire (lightbulb) - only show for non-user posts and OpenTable category
        if !isUserPost && category == .openTable {
            Button {
                toggleLightbulb()
            } label: {
                Label(hasLitLightbulb ? "Remove Inspiration" : "Inspire", systemImage: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
            }
        }
        
        // Join Fast - only show for prayer request posts
        if category == .prayer, let post = post, post.topicTag == "Prayer Request" {
            Button {
                toggleFasting()
            } label: {
                Label(isFasting ? "End Fast" : "Join Fast", systemImage: isFasting ? "flame.fill" : "flame")
            }
        }
        
        Button {
            sharePost()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        // Discuss — opens Reasoning Thread for this post
        Button {
            guard let post = post else { return }
            presentSheet(.reasoningThread(postId: post.firestoreId, postText: post.content, authorName: authorName))
        } label: {
            Label("Discuss", systemImage: "bubble.left.and.text.bubble.right.fill")
        }

        // Tip — only show for other people's posts
        if !isUserPost {
            Button {
                guard let post = post, !post.authorId.isEmpty else { return }
                presentSheet(.tip(creatorId: post.authorId, creatorName: authorName))
            } label: {
                Label("Send Tip", systemImage: "gift.fill")
            }
        }

        // Save to Library + folder shortcuts (Feature 3)
        Button {
            toggleSave()
        } label: {
            Label(isSaved ? "Remove from Library" : "Save to Library", systemImage: isSaved ? "bookmark.fill" : "bookmark")
        }

        // Quick-save to named folders (tag the post locally via topicTag matching)
        Menu {
            ForEach(SavedFolder.allCases.filter { $0 != .all }, id: \.id) { folder in
                Button {
                    // Save the post first, then navigate user to that folder
                    if !isSaved { toggleSave() }
                    NotificationCenter.default.post(
                        name: Notification.Name("openSavedFolder"),
                        object: nil,
                        userInfo: ["folder": folder.rawValue]
                    )
                } label: {
                    Label(folder.rawValue, systemImage: folder.icon)
                }
            }
        } label: {
            Label("Save to Folder", systemImage: "folder.badge.plus")
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
            activeAlert = .notInterested
        } label: {
            Label("Not Interested", systemImage: "eye.slash")
        }
        
        Button(role: .destructive) {
            guard let post = post else { return }
            presentSheet(.report(post: post))
        } label: {
            Label("Report Post", systemImage: "exclamationmark.triangle")
        }
        
        Button(role: .destructive) {
            let safeName = authorName.isEmpty ? "this user" : authorName
            activeAlert = .muteConfirmation(safeName)
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
            let safeName = authorName.isEmpty ? "this user" : authorName
            activeAlert = .blockConfirmation(safeName)
        } label: {
            Label("Block \(authorName)", systemImage: "hand.raised")
        }
    }
    
    // MARK: - Interaction Buttons
    
    // ⚡️ PERFORMANCE FIX: Static gradients computed once, not per render
    private static let lightbulbGradientActive = LinearGradient(
        colors: [.red, .red.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    private static let lightbulbGradientInactive = LinearGradient(
        colors: [Color.black.opacity(0.5), Color.black.opacity(0.5)],
        startPoint: .top,
        endPoint: .bottom
    )
    
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
    
    // ⚡️ PERFORMANCE FIX: Removed ZStack wrapper - direct icon rendering
    private var lightbulbIcon: some View {
        lightbulbMainIcon
    }
    
    // ⚡️ PERFORMANCE FIX: Removed glow effect entirely - too GPU intensive for feeds
    // Simple icon with minimal styling performs 10x better during scroll
    private var lightbulbMainIcon: some View {
        Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
            .font(.systemScaled(20, weight: .semibold))
            .foregroundStyle(hasLitLightbulb ? Self.lightbulbGradientActive : Self.lightbulbGradientInactive)
    }
    
    private var lightbulbBackground: some View {
        Capsule()
            .fill(hasLitLightbulb ? Color.red.opacity(0.15) : Color(.tertiarySystemFill))
            .shadow(color: hasLitLightbulb ? Color.red.opacity(0.2) : Color.clear, radius: 8, y: 2)
    }
    
    private var lightbulbOverlay: some View {
        Capsule()
            .stroke(hasLitLightbulb ? Color.red.opacity(0.3) : Color(.separator).opacity(0.25), lineWidth: hasLitLightbulb ? 1.5 : 1)
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
    
    // ⚡️ PERFORMANCE FIX: Removed ZStack and blur - simple icon only
    private var amenButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: hasSaidAmen ? "hands.clap.fill" : "hands.clap")
                .font(.systemScaled(20, weight: .semibold))
                .foregroundStyle(hasSaidAmen ? Color.blue : Color.secondary)
            
            // Amen count is private — not shown publicly.
            // Icon state (filled/outlined) reflects user's own amen only.
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
    
    private var amenBackground: some View {
        Capsule()
            .fill(hasSaidAmen ? Color(.secondarySystemFill) : Color(.tertiarySystemFill))
            .shadow(color: hasSaidAmen ? Color.black.opacity(0.10) : Color.clear, radius: 8, y: 2)
    }
    
    private var amenOverlay: some View {
        Capsule()
            .stroke(Color(.separator).opacity(hasSaidAmen ? 0.5 : 0.25), lineWidth: hasSaidAmen ? 1.5 : 1)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Avatar with Follow Button (TAPPABLE)
            avatarButton
            
            // Name and info (TAPPABLE)
            authorInfoButton
            
            Spacer()

            optionsButton
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
            presentSheet(.userProfile(userId: post.authorId))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var authorNameRow: some View {
        HStack(spacing: 8) {
            // Make author name tappable to view profile
            Button {
                openAuthorProfile()
            } label: {
                HStack(spacing: 4) {
                    Text(authorName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // ✅ Verified badge
                    if let post = post, VerifiedBadgeHelper.shared.isVerified(userId: post.authorId) {
                        VerifiedBadge(
                            type: VerifiedBadgeHelper.shared.getVerificationType(userId: post.authorId),
                            size: 14
                        )
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .layoutPriority(-1)
            
            // 📌 Pinned post indicator (like Threads)
            if let post = post, pinnedPostService.isPostPinned(post.firestoreId) {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.systemScaled(10, weight: .semibold))
                    Text("Pinned")
                        .font(AMENFont.bold(11))
                }
                .foregroundStyle(.gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
                .fixedSize()
            }

            // Category badge - only show if category allows it (not for Tip, Fun Fact)
            if let post = post, post.category.showCategoryBadge {
                categoryBadge
                    .fixedSize()
            } else if post == nil && category != .openTable {
                // Fallback for preview posts without full Post object
                categoryBadge
                    .fixedSize()
            }

            // AI-generated content label (shown when user chose to add a source label)
            if let post = post, let source = post.contentSource, !source.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(9, weight: .semibold))
                    Text("via \(source)")
                        .font(.systemScaled(10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.purple.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.8))
                .fixedSize()
            }
        }
        .lineLimit(1)
    }
    
    private var categoryBadge: some View {
        Group {
            if !category.displayName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.systemScaled(10, weight: .semibold))
                    Text(category.displayName)
                        .font(AMENFont.bold(11))
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
                        .font(.systemScaled(11, weight: .medium))
                    Text("Translating…")
                        .font(AMENFont.semiBold(12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .modifier(PulsingOpacityModifier())

            case .translated(let variant):
                VStack(alignment: .leading, spacing: 6) {
                    // Mode switcher (when meaning-aware translation is enabled) or simple source label
                    if AMENFeatureFlags.shared.meaningAwareTranslationEnabled {
                        TranslationModeSwitcher(
                            sourceLanguage: variant.sourceLanguage,
                            selectedMode: $currentTranslationMode,
                            isLoading: isRefinementLoading,
                            onModeChanged: { newMode in
                                Task { await retranslateWithMode(newMode) }
                            }
                        )
                    } else {
                        HStack(spacing: 8) {
                            // Source language label
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.systemScaled(10, weight: .medium))
                                Text("Translated from \(SupportedLanguage.displayName(for: variant.sourceLanguage))")
                                    .font(AMENFont.regular(11))
                            }
                            .foregroundStyle(.secondary)
                            .onTapGesture { showTranslationInfoSheet = true }

                            // Toggle original/translated
                            Button {
                                HapticManager.impact(style: .light)
                                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                                    showTranslatedContent.toggle()
                                }
                            } label: {
                                Text(showTranslatedContent ? "View original" : "View translation")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(.secondary)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                            .font(.systemScaled(11, weight: .medium))
                        Text("See translation")
                            .font(AMENFont.semiBold(12))
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
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await triggerTranslation() }
                    }
                    .font(AMENFont.semiBold(11))
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
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .fixedSize()

            // "Edited" badge — shown when updatedAt is set and at least 60s after createdAt
            if let post = post, let updatedAt = post.updatedAt,
               updatedAt.timeIntervalSince(post.createdAt) > 60 {
                Text("· Edited")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if let tag = topicTag, !tag.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
                // Topic tag as neutral pill
                Text(tag)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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
                        .font(.systemScaled(9, weight: .semibold))
                    Text("via \(source)")
                        .font(AMENFont.semiBold(10))
                        .lineLimit(1)
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
        .lineLimit(1)
    }
    
    /// Whether to show side-by-side (original + translated) view instead of toggle
    private var showSideBySideTranslation: Bool {
        guard TranslationSettingsManager.shared.preferences.sideBySideEnabled,
              AMENFeatureFlags.shared.sideBySideTranslationEnabled else { return false }
        guard showTranslatedContent, translatedContent != nil else { return false }
        return true
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
        AmenPostCardPlusButton(isExpanded: isActionMenuPresented) {
            toggleActionMenu()
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: AmenPostCardActionMenuAnchorPreferenceKey.self,
                        value: proxy.frame(in: .named(actionMenuCardID))
                )
            }
        )
    }

    private var optionsButton: some View {
        Button {
            presentOptionsSheet()
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post options")
    }

    @ViewBuilder
    private var actionMenuOverlay: some View {
        // ✅ P0 CRASH FIX: Validate frame is not just non-empty, but also has valid (non-NaN, finite) values
        // During view deallocation or rapid state updates, actionMenuButtonFrame can contain NaN/inf
        // which causes EXC_BAD_ACCESS when passed to .position() modifier
        let isFrameValid = !actionMenuButtonFrame.isEmpty 
            && actionMenuButtonFrame.maxX.isFinite 
            && actionMenuButtonFrame.maxY.isFinite
            && actionMenuButtonFrame.minX.isFinite
            && actionMenuButtonFrame.minY.isFinite
        
        if isActionMenuPresented, isFrameValid {
            GeometryReader { proxy in
                let menuWidth = AmenPostCardActionMenu.preferredWidth
                let menuHeight = AmenPostCardActionMenu.preferredHeight
                let inset: CGFloat = 18
                let targetCenterX = actionMenuButtonFrame.maxX - (menuWidth * 0.5) + 18
                let minCenterX = inset + (menuWidth * 0.5)
                let maxCenterX = max(minCenterX, proxy.size.width - inset - (menuWidth * 0.5))
                // ✅ Additional safety: ensure calculated values are finite before using in .position()
                let clampedCenterX = min(max(targetCenterX, minCenterX), maxCenterX).isFinite 
                    ? min(max(targetCenterX, minCenterX), maxCenterX) 
                    : proxy.size.width * 0.5
                let targetCenterY = (actionMenuButtonFrame.maxY + 18 + (menuHeight * 0.5)).isFinite
                    ? actionMenuButtonFrame.maxY + 18 + (menuHeight * 0.5)
                    : proxy.size.height * 0.5

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.035))
                        .frame(width: max(proxy.size.width * 6, 1600), height: max(proxy.size.height * 8, 2400))
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeActionMenu()
                        }

                    AmenPostCardActionMenu(
                        isFollowing: isFollowing,
                        canFollow: !isUserPost && post != nil,
                        onFollow: { handleActionMenuFollowTap() },
                        onVisitProfile: { handleActionMenuProfileTap() }
                    )
                    .frame(width: menuWidth, height: menuHeight)
                    .position(x: clampedCenterX, y: targetCenterY)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity),
                            removal: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity)
                        )
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
    
    // Break up the modifier chain into intermediate steps so the Swift type-checker
    // can resolve each piece independently (avoids "expression too complex" timeout).

    private var cardWithSheets: AnyView {
        AnyView(
            cardContent
                .onLongPressGesture(minimumDuration: 0.35) {
                    guard !isTextSelecting else { return }
                    closeActionMenu(animated: false)
                    HapticManager.impact(style: .light)
                    presentSheet(.options)
                }
                .modifier(PostCardSheetsModifier(
                    activeSheet: $activeSheet,
                    hasCommented: $hasCommented,
                    optionsQuickActionsBuilder: { optionsQuickActions },
                    optionsSectionsBuilder: { optionsSections },
                    feedReasonsBuilder: { post in feedReasons(for: post) },
                    authorName: authorName,
                    category: category
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
        )
    }
    
    private var cardWithAlerts: AnyView {
        AnyView(
            cardWithMuteBlockAlerts
                .alert(item: $activeAlert) { alert in
                    switch alert {
                    case .notInterested:
                        return Alert(
                            title: Text("Not Interested?"),
                            message: Text("You'll see fewer posts like this. This helps us personalize your feed."),
                            primaryButton: .cancel(),
                            secondaryButton: .default(Text("Confirm")) {
                                markNotInterested()
                            }
                        )
                    case .feedbackReceived:
                        return Alert(
                            title: Text("Feedback Received"),
                            message: Text("We'll show you fewer posts like this."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .error(let message):
                        return Alert(
                            title: Text("Error"),
                            message: Text(message),
                            dismissButton: .default(Text("OK")) {
                                errorMessage = ""
                            }
                        )
                    case .muteConfirmation(let name):
                        return Alert(
                            title: Text("Mute \(name)?"),
                            message: Text("You won't see posts from \(name) in your feed anymore. You can unmute them from your settings."),
                            primaryButton: .cancel(),
                            secondaryButton: .destructive(Text("Mute")) {
                                muteAuthor()
                            }
                        )
                    case .blockConfirmation(let name):
                        return Alert(
                            title: Text("Block \(name)?"),
                            message: Text("\(name) won't be able to see your posts or interact with you. You can unblock them from your settings."),
                            primaryButton: .cancel(),
                            secondaryButton: .destructive(Text("Block")) {
                                blockAuthor()
                            }
                        )
                    case .muteSuccess(let name):
                        return Alert(
                            title: Text("User Muted"),
                            message: Text("\(name) has been muted."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .blockSuccess(let name):
                        return Alert(
                            title: Text("User Blocked"),
                            message: Text("\(name) has been blocked."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .deleteConfirmation:
                        return Alert(
                            title: Text("Delete Post"),
                            message: Text("Are you sure you want to delete this post? This action cannot be undone."),
                            primaryButton: .cancel(),
                            secondaryButton: .destructive(Text("Delete")) {
                                deletePost()
                            }
                        )
                    }
                }
        )
    }
    
    private var cardWithMuteBlockAlerts: AnyView {
        AnyView(cardWithSheets)
    }

    var body: some View {
        cardWithAlerts
            .opacity(isDeletingPost ? 0 : 1)
            .scaleEffect(isDeletingPost ? 0.96 : 1)
            .zIndex(isActionMenuPresented ? 1000 : 0)
            .pressableCard(scale: 0.985)   // A) Subtle press-down on the whole card
            .coordinateSpace(name: actionMenuCardID)
            .onPreferenceChange(AmenPostCardActionMenuAnchorPreferenceKey.self) { newFrame in
                let isValid = !newFrame.isNull
                    && newFrame.minX.isFinite
                    && newFrame.minY.isFinite
                    && newFrame.maxX.isFinite
                    && newFrame.maxY.isFinite
                actionMenuButtonFrame = isValid ? newFrame : .zero
            }
            .overlay { actionMenuOverlay }
            .onAppear {
                // Set cardAppeared instantly (no animation) to avoid double-animation conflict
                // with the external .feedItemAppear() modifier already animating the whole card
                cardAppeared = true

                // Sync follow state on appear (covers cross-tab navigation)
                if let post = post {
                    localIsFollowing = FollowService.shared.following.contains(post.authorId)
                }

                // Sync expansion state (handles scroll recycle where onReceive doesn't fire)
                isPostExpanded = interactionsService.isExpanded(stablePostId)
            }
            .task(id: post?.authorId) {
                // Set initial follow state when post loads or author changes
                if let post = post {
                    localIsFollowing = FollowService.shared.following.contains(post.authorId)
                }
            }
            // Targeted re-render: only fires when THIS card's active state actually flips
            .onReceive(
                AmenPostCardActionMenuCoordinator.shared.$activePostId
                    .map { [actionMenuCardID] id in id == actionMenuCardID }
                    .removeDuplicates()
            ) { newState in
                if newState != isActionMenuActive_state {
                    isActionMenuActive_state = newState
                }
            }
            // Targeted re-render: only fires when THIS author's follow state actually changes
            .onReceive(
                FollowService.shared.$following
                    .map { [authorId = post?.authorId ?? ""] set in set.contains(authorId) }
                    .removeDuplicates()
            ) { newState in
                if newState != localIsFollowing {
                    localIsFollowing = newState
                }
            }
            // Targeted re-render: sync expansion state without full PostCard body re-evaluation
            .onReceive(interactionsService.$expandedPostIds.map { [stablePostId] ids in
                ids.contains(stablePostId)
            }.removeDuplicates()) { expanded in
                isPostExpanded = expanded
            }
            .onDisappear {
                closeActionMenu(animated: false)
                clearTextSelection()
            }
            .onChange(of: activeSheet?.id) { _, newValue in
                if newValue != nil {
                    closeActionMenu(animated: false)
                }
            }
            // Sync local state from BereanLiveActivityService via onReceive instead of wrapping
            // the singleton property in a Binding — the Binding(get:set:) pattern polls the
            // singleton on every body render which can destabilize the view update cycle.
            .onReceive(
                BereanLiveActivityService.shared.$showFallbackSheet.removeDuplicates()
            ) { show in
                if show { showBereanFallbackSheet = true }
            }
            .sheet(isPresented: $showBereanFallbackSheet, onDismiss: {
                BereanLiveActivityService.shared.showFallbackSheet = false
            }) {
                BereanFallbackSheet()
            }
            .task(id: content) {
                await detectAndTranslatePost()
            }
            .translationTask(appleTranslationConfig) { session in
                await handleAppleTranslationSession(session)
            }
    }

    // ⚡️ PERFORMANCE FIX: Removed startAuthorProfileListener()
    // Per-card Firestore listeners were causing 20+ simultaneous connections during scroll
    // Profile updates now come through PostsManager's centralized real-time listeners
    
    // MARK: - Translation Logic

    /// Called on appear to detect language and set initial translation UI state.
    private func detectAndTranslatePost() async {
        guard !content.isEmpty else { return }

        // Detect language on-device (instant, private)
        let detection = await newTranslationService.detectLanguage(content)
        guard detection.isReliable else { return }

        detectedLanguage = detection.languageCode
        detectedLanguageConfidence = detection.confidence

        let settings = TranslationSettingsManager.shared

        // Initialize default translation mode from user preferences
        currentTranslationMode = settings.preferences.defaultTranslationMode

        // Check if we should auto-translate or just offer a button
        if settings.shouldAutoTranslate(detectedLang: detection.languageCode, contentType: .post) {
            await triggerTranslation()
        } else if settings.shouldOfferTranslation(detectedLang: detection.languageCode, contentType: .post, confidence: detection.confidence) {
            translationUIState = .available
        } else {
            translationUIState = .notNeeded
        }
    }

    /// Manually or automatically trigger translation for this post.
    private func triggerTranslation() async {
        guard translationUIState != .loading else { return }

        // .original mode means show original — no translation needed
        guard currentTranslationMode.performsTranslation else {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                showTranslatedContent = false
                translationUIState = .available
            }
            return
        }

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

        // Route through MeaningAwareTranslationService for mode-aware translation
        let result: TranslationUIState
        if currentTranslationMode == .literal || !AMENFeatureFlags.shared.meaningAwareTranslationEnabled {
            result = await newTranslationService.translate(
                text: content,
                contentType: .post,
                contentId: postId,
                surface: .feed,
                isPublicContent: isPublic
            )
        } else {
            result = await MeaningAwareTranslationService.shared.translate(
                text: content,
                contentType: .post,
                contentId: postId,
                surface: .feed,
                mode: currentTranslationMode,
                isPublicContent: isPublic
            )
        }

        // If language models need downloading, fall back to .translationTask() modifier
        // which prompts the user to download and handles progress UI automatically.
        if case .error(.languageDownloadNeeded) = result {
            let sourceLang = detectedLanguage ?? "und"
            let targetLang = TranslationSettingsManager.shared.userLanguageCode
            if appleTranslationConfig == nil {
                appleTranslationConfig = .init(
                    source: Locale.Language(identifier: sourceLang),
                    target: Locale.Language(identifier: targetLang)
                )
            } else {
                appleTranslationConfig?.invalidate()
            }
            return
        }

        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
            translationUIState = result
            if let translated = result.translatedText {
                translatedContent = translated
                showTranslatedContent = true
                AccessibilitySignalCollector.shared.recordSignal(.translated)
                AccessibilitySuggestionEngine.shared.evaluate()

                // Phase 4: Re-detect glossary terms on translated text so context cards
                // appear in the user's language instead of the original language.
                if AMENFeatureFlags.shared.contextBridgeEnabled {
                    let raw = ContextTermDetector.shared.detectTerms(in: translated)
                    detectedContextTerms = ContextAssistService.shared.filterDismissed(raw)
                }
            }
        }
    }

    /// Handle a TranslationSession provided by the .translationTask() modifier.
    /// This session can download language models automatically (prompting the user),
    /// unlike TranslationSession(installedSource:) which only works with pre-installed models.
    private func handleAppleTranslationSession(_ session: Translation.TranslationSession) async {
        do {
            let response = try await session.translate(content)
            let targetLang = TranslationSettingsManager.shared.userLanguageCode
            let variant = TranslationVariant(
                translatedText: response.targetText.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceLanguage: detectedLanguage ?? "und",
                targetLanguage: targetLang,
                engineVersion: .appleOnDevice,
                translatedAt: Date(),
                characterCount: content.count,
                isUserRequested: true
            )
            await MainActor.run {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                    translationUIState = .translated(variant)
                    translatedContent = variant.translatedText
                    showTranslatedContent = true
                    AccessibilitySignalCollector.shared.recordSignal(.translated)
                    AccessibilitySuggestionEngine.shared.evaluate()
                    if AMENFeatureFlags.shared.contextBridgeEnabled {
                        let raw = ContextTermDetector.shared.detectTerms(in: variant.translatedText)
                        detectedContextTerms = ContextAssistService.shared.filterDismissed(raw)
                    }
                }
            }
        } catch {
            await MainActor.run {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                    translationUIState = .error(.serviceUnavailable)
                }
            }
        }
    }

    /// Listen pill button for audio narration
    private var listenPillButton: some View {
        Button {
            HapticManager.impact(style: .light)
            let postId = post?.firestoreId ?? UUID().uuidString
            let textToRead = showTranslatedContent ? (translatedContent ?? content) : content
            let lang = showTranslatedContent ? TranslationSettingsManager.shared.preferences.appLanguage : nil
            SpeechSynthesisService.shared.play(
                text: textToRead,
                id: postId,
                title: authorName,
                language: lang
            )
            AccessibilitySignalCollector.shared.recordSignal(.listenedToPost)
            AccessibilitySuggestionEngine.shared.evaluate()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: SpeechSynthesisService.shared.currentItemId == (post?.firestoreId ?? "")
                      ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 11, weight: .medium))
                Text("Listen")
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Listen to this post")
    }

    /// Re-translate current content with a different translation mode (original/literal/natural/contextual)
    private func retranslateWithMode(_ mode: TranslationMode) async {
        currentTranslationMode = mode

        // .original mode: revert to original text, no API call
        guard mode.performsTranslation else {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
                showTranslatedContent = false
            }
            return
        }

        let postId = post?.firestoreId ?? UUID().uuidString
        isRefinementLoading = true

        let result = await MeaningAwareTranslationService.shared.translate(
            text: content,
            contentType: .post,
            contentId: postId,
            surface: .feed,
            mode: mode,
            isPublicContent: true
        )

        isRefinementLoading = false

        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.85))) {
            translationUIState = result
            if let translated = result.translatedText {
                translatedContent = translated
                showTranslatedContent = true
                AccessibilitySignalCollector.shared.recordSignal(.translated)
                AccessibilitySignalCollector.shared.recordSignal(.modeChanged)
                AccessibilitySuggestionEngine.shared.evaluate()

                // Phase 4: Re-detect glossary terms on translated text
                if AMENFeatureFlags.shared.contextBridgeEnabled {
                    let raw = ContextTermDetector.shared.detectTerms(in: translated)
                    detectedContextTerms = ContextAssistService.shared.filterDismissed(raw)
                }
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
                                .font(.systemScaled(8, design: .monospaced))
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
    
    // MARK: - Header View
    private var postHeaderView: some View {
        headerView
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard NavigationGuard.shared.shouldNavigate() else { return }
                guard let post = post else { return }
                presentSheet(.postDetail(post: post))
            }
    }
    
    // MARK: - Post Content with Selection
    private var postContentWithSelection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Side-by-side translation view (when enabled and translated)
            if showSideBySideTranslation,
               let translated = translatedContent,
               let sourceLang = detectedLanguage {
                SideBySideTranslationView(
                    originalText: content,
                    translatedText: translated,
                    sourceLanguage: sourceLang,
                    targetLanguage: TranslationSettingsManager.shared.preferences.appLanguage
                )
                .padding(.horizontal, 12)
            }

            ZStack(alignment: .topLeading) {
                SelectablePostTextView(
                    text: showSideBySideTranslation ? content : (showTranslatedContent ? (translatedContent ?? content) : content),
                    mentions: post?.mentions,
                    font: UIFont(name: "OpenSans-Regular", size: 16) ?? .systemFont(ofSize: 16),
                    lineSpacing: 4,
                    lineLimit: isPostExpanded ? nil : 10,
                    onMentionTap: { mention in
                        guard NavigationGuard.shared.shouldNavigate() else { return }
                        presentSheet(.mentionedProfile(userId: mention.userId))
                        HapticManager.impact(style: .light)
                    },
                    onTextTap: {
                        guard NavigationGuard.shared.shouldNavigate() else { return }
                        guard let post = post else { return }
                        presentSheet(.postDetail(post: post))
                    },
                    selection: $textSelection,
                    isSelecting: $isTextSelecting
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: isPostExpanded ? nil : 400)
                // Hide the regular text view when side-by-side is showing
                .opacity(showSideBySideTranslation ? 0 : 1)
                .frame(height: showSideBySideTranslation ? 0 : nil)
                .clipped()

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

            if !isTextSelecting && content.count > 80 {
                Text("Select a thought to quote")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if !isPostExpanded && content.count > 300 {
                Button {
                    HapticManager.impact(style: .light)
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        interactionsService.toggleExpanded(stablePostId)
                    }
                } label: {
                    Text("Show more")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 0)
    }
    
    // MARK: - Post Interaction Section
    @ViewBuilder
    private var postInteractionSection: some View {
        interactionButtons
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, showTestimonyResonance ? 4 : 6)

        if showTestimonyResonance && !testimonyResonanceCopy.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color.indigo.opacity(0.7))
                Text(testimonyResonanceCopy)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .italic()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    // MARK: - Post Metadata
    @ViewBuilder
    private var postMetadata: some View {
        if let post = post, post.isRepost {
            let originalAuthor = post.originalAuthorName ?? post.authorName
            repostIndicator(originalAuthor: originalAuthor)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        
        if let post = post, post.category == .testimonies, post.linkedPrayerRequestId != nil {
            TestimonyArcView(testimony: post)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }

        if let post = post, (post.category == .prayer || post.category == .testimonies) {
            SermonConnectBanner(service: SermonConnectService.shared, onTapNote: { _ in }, paddingLeading: 16, paddingTop: 4)
                .onAppear { SermonConnectService.shared.findMatch(for: post.content) }
        }

        if let post = post, let replyPerm = post.replyPermission, replyPerm != .everyone {
            HStack(spacing: 4) {
                Image(systemName: replyPerm.icon)
                    .font(.systemScaled(10, weight: .semibold))
                Text("\(replyPerm.displayName) can reply")
                    .font(.systemScaled(12, weight: .regular))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }

        if let post = post, post.hasContext {
            Button {
                presentSheet(.postDetail(post: post))
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.systemScaled(11))
                    Text("Community context added")
                        .font(.systemScaled(12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }

        if let post = post, post.authorId == (Auth.auth().currentUser?.uid ?? "") {
            let hasCounts = post.savesCount > 0 || post.prayTapsCount > 0 || post.encouragedCount > 0
            if hasCounts {
                HStack(spacing: 12) {
                    if post.savesCount > 0 {
                        insightItem(icon: "bookmark.fill", count: post.savesCount, label: "saved")
                    }
                    if post.prayTapsCount > 0 {
                        insightItem(icon: "hands.sparkles.fill", count: post.prayTapsCount, label: "prayed")
                    }
                    if post.encouragedCount > 0 {
                        insightItem(icon: "heart.fill", count: post.encouragedCount, label: "encouraged")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Post Media Content
    @ViewBuilder
    private var postMediaContent: some View {
        if let quote = post?.quote {
            quoteSnippetView(quote)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }

        // Scripture attachment pill (published post)
        if let post = post, let verseRef = post.verseReference, !verseRef.isEmpty {
            PostCardScripturePill(
                reference: verseRef,
                translation: "NIV",
                onTap: {
                    // Open scripture detail
                    if let attachment = ScriptureAttachment.from(legacyReference: verseRef, legacyText: post.verseText) {
                        postCardScriptureAttachment = attachment
                        showPostCardScriptureDetail = true
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }

        if shouldShowTranslationAffordance {
            translationToggleButton
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }

        // Accessibility pills row (Understand + Listen)
        if AMENFeatureFlags.shared.accessibilityIntelligenceEnabled {
            HStack(spacing: 8) {
                // Understand pill — shown when content difficulty is high
                if AMENFeatureFlags.shared.readabilityLayerEnabled,
                   let score = difficultyScore,
                   score.score >= ContentDifficultyScore.displayThreshold {
                    UnderstandPillButton(
                        text: content,
                        contentId: post?.firestoreId ?? UUID().uuidString,
                        difficultyScore: score
                    )
                }

                // Listen pill — audio narration (only shown when user has opted in via Settings → Audio)
                if AMENFeatureFlags.shared.audioNarrationEnabled,
                   UserDefaults.standard.bool(forKey: "amen.audio.listenEnabled") {
                    listenPillButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        if let post = post, let imageURLs = post.imageURLs, !imageURLs.isEmpty {
            PostImagesView(imageURLs: imageURLs)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }

        if let post = post, let churchNoteId = post.churchNoteId {
            churchNotePreview(churchNoteId: churchNoteId)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }

        if let post = post, post.isChurchShare, let churchName = post.sharedChurchName {
            ChurchNameCapsulePill(churchName: churchName) {
                NotificationCenter.default.post(name: .navigateToFindChurch, object: nil)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if let eventName = post.sharedChurchEventName, !eventName.isEmpty {
                ChurchEventCapsulePill(eventName: eventName, eventTime: post.sharedChurchEventTime) {
                    NotificationCenter.default.post(name: .navigateToFindChurch, object: nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }

        if let post = post, let poll = post.poll {
            PostPollView(
                postId: post.firestoreId,
                poll: poll,
                currentUserId: Auth.auth().currentUser?.uid
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }

        if let post = post,
           let linkURLString = post.linkURL,
           !linkURLString.isEmpty,
           let linkURL = URL(string: linkURLString) {
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
            if AMENFeatureFlags.shared.inAppBrowserEnabled {
                EnhancedLinkPreviewCard(url: linkURL, metadata: meta)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            } else {
                FeedLinkPreviewCard(url: linkURL, metadata: meta)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
    }
    
    // MARK: - Moderation Banner
    @ViewBuilder
    private var moderationBanner: some View {
        if isUserPost, let post = post {
            if post.flaggedForReview {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Under review")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
            } else if post.removed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("Removed — violated community guidelines")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }
        }
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            moderationBanner

            postHeaderView
            postContentWithSelection

            postMediaContent
            
            postMetadata

            postInteractionSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onChange(of: hasSaidAmen) { _, newValue in
            if newValue && category == .testimonies {
                fetchTestimonyResonance(actionType: "amen")
            }
        }
        .onChange(of: isSaved) { _, newValue in
            if newValue && category == .testimonies {
                fetchTestimonyResonance(actionType: "saved")
            }
        }
        .onChange(of: hasLitLightbulb) { _, newValue in
            if newValue && category == .testimonies {
                fetchTestimonyResonance(actionType: "lightbulb")
            }
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
                
                // Threads-style: clean white background, no rounded corners
                Color(.systemBackground)
            }
        )
        .overlay(alignment: .bottom) {
            // Threads-style: subtle, inset divider between posts
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(height: 0.5)
        }
        .offset(x: swipeOffset)
        // P0 FIX: Use simultaneous gesture so ScrollView keeps priority for vertical scrolling
        // This gesture only activates when user clearly swipes horizontally (4x ratio + 50pt minimum distance)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50) // High threshold to avoid false triggers during vertical scroll
                .onChanged { value in
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)

                    // Require very strong horizontal bias (4x ratio) to activate swipe
                    // This ensures vertical scrolling always takes priority
                    guard horizontalAmount > verticalAmount * 4.0 else { 
                        // Reset any partial swipe state if gesture becomes too vertical
                        if swipeOffset != 0 {
                            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.9))) {
                                swipeOffset = 0
                                swipeDirection = .none
                            }
                        }
                        return 
                    }

                    // Strict vertical limit - abort if ANY vertical movement detected
                    // This ensures scrolling always works smoothly
                    guard verticalAmount < 10 else {
                        if swipeOffset != 0 {
                            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.9))) {
                                swipeOffset = 0
                                swipeDirection = .none
                            }
                        }
                        return
                    }

                    // Only update swipe state if horizontal movement is significant
                    if value.translation.width > 30 {
                        swipeDirection = .right
                        swipeOffset = min(value.translation.width, 100)
                    } else if value.translation.width < -30 {
                        swipeDirection = .left
                        swipeOffset = max(value.translation.width, -100)
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 70 // Increased threshold for more deliberate swipes
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)

                    // Very strict check: only trigger if it's an unmistakably horizontal swipe
                    // 4x ratio + minimal vertical movement ensures this never interferes with scrolling
                    guard horizontalAmount > verticalAmount * 4.0, verticalAmount < 15 else {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
                        return
                    }
                    
                    if swipeDirection == .right && swipeOffset > threshold {
                        // Trigger like/amen action
                        triggerSwipeLikeAction()
                        
                        // Reset with animation
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            swipeOffset = 0
                            swipeDirection = .none
                        }
                    } else if swipeDirection == .left && abs(swipeOffset) > threshold {
                        // Trigger comment action - delay reset to allow sheet to present
                        triggerSwipeCommentAction()
                        
                        // Small delay before reset to ensure sheet presents properly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                swipeOffset = 0
                                swipeDirection = .none
                            }
                        }
                    } else {
                        // Reset with animation if threshold not met
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
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
                .font(.systemScaled(28, weight: .medium))
                .foregroundColor(color)
            Text(text)
                .font(AMENFont.semiBold(12))
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
        guard let post = post else { return }
        presentSheet(.comments(post: post))
    }
    
    private func repostIndicator(originalAuthor: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.systemScaled(12, weight: .semibold))
            Text("Reposted from \(originalAuthor)")
                .font(AMENFont.semiBold(13))
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
                if let note = churchNote {
                    presentSheet(.churchNoteDetail(note: note))
                }
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
            lazy var db = Firestore.firestore()
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
            // 1. Lightbulb (OpenTable) / Amen (Prayer + other categories)
            if category == .openTable {
                circularInteractionButton(
                    icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                    count: nil,
                    isActive: hasLitLightbulb,
                    activeColor: .black,
                    disabled: isUserPost,
                    // HIGH FIX: Provide descriptive label so VoiceOver reads action, not SF Symbol name
                    accessibilityLabel: isUserPost
                        ? (hasLitLightbulb ? "Remove inspiration" : "Add inspiration — disabled for your own post")
                        : (hasLitLightbulb ? "Remove inspiration" : "Mark as inspiring")
                ) {
                    if !isUserPost { toggleLightbulb() }
                }
            } else {
                // Unified Amen button for Prayer, Testimonies, and other categories
                circularInteractionButton(
                    icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                    count: nil,
                    isActive: hasSaidAmen,
                    activeColor: .black,
                    disabled: isUserPost,
                    // HIGH FIX: Provide descriptive label so VoiceOver reads action, not SF Symbol name
                    accessibilityLabel: isUserPost
                        ? (hasSaidAmen ? "Remove Amen" : "Say Amen — disabled for your own post")
                        : (hasSaidAmen ? "Remove Amen" : "Say Amen")
                ) {
                    if !isUserPost { 
                        toggleAmen()
                        // For prayer posts, also toggle the praying status
                        if category == .prayer {
                            togglePraying()
                        }
                    }
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
                guard let post = post else { return }
                presentSheet(.comments(post: post))
            }

            // 3. Repost (repeat — illuminates when active; tap opens Repost/Quote sheet)
            circularInteractionButton(
                icon: "repeat",
                count: nil,
                isActive: hasReposted,
                activeColor: .black,
                disabled: isUserPost,
                accessibilityLabel: hasReposted ? "Remove repost" : "Repost"
            ) {
                if !isUserPost {
                    if hasReposted {
                        // Already reposted — undo directly
                        toggleRepost()
                    } else {
                        // Not yet reposted — show Repost / Quote choice
                        HapticManager.impact(style: .light)
                        showRepostActionSheet = true
                    }
                }
            }
            .shakeOnError(repostShakeError)
            .sheet(isPresented: $showRepostActionSheet) {
                if let post {
                    RepostActionSheet(
                        post: post,
                        onRepost: { toggleRepost() },
                        onQuote: { showQuoteComposer = true }
                    )
                    .presentationDetents([.height(160)])
                    .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(isPresented: $showQuoteComposer) {
                if let post {
                    QuotePostComposerView(originalPost: post) { quoteText, original in
                        Task {
                            await PostsManager.shared.publishQuotePost(text: quoteText, originalPost: original)
                        }
                        hasReposted = true
                        repostCount += 1
                    }
                }
            }
            .fullScreenCover(isPresented: $showPostCardScriptureDetail) {
                if let attachment = postCardScriptureAttachment {
                    ScriptureDetailRoute(
                        context: SelahLaunchContext(
                            attachment: attachment,
                            sourceContext: .postCard,
                            prefetchedPayload: nil,
                            translationPreference: attachment.translation,
                            openMode: .verseFocus
                        ),
                        onDismiss: { showPostCardScriptureDetail = false }
                    )
                }
            }
            
            // Prayer Echo button — shown only for prayer posts
            if category == .prayer, let post = post {
                EchoButton(post: post)
            }

            // 4. Berean AI sparkle (next to repost, testimonies + OpenTable + prayer)
            if category == .testimonies || category == .openTable || category == .prayer {
                AISparkleSearchButton {
                    HapticManager.impact(style: .light)
                    // Launch Berean Live Activity (Dynamic Island) or fallback sheet
                    if let post = post {
                        BereanLiveActivityService.shared.startActivity(for: post)
                    } else {
                        presentSheet(.berean(initialQuery: bereanInitialQuery))
                    }
                }
                // ✅ FIX: Removed .frame(width: 20, height: 20) - was too small to tap
                // Button has its own 28x28 frame which provides proper tap target
            }
            
            Spacer()
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
                .font(.systemScaled(17, weight: isActive ? .semibold : .thin))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
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

    // Feature 5 — Tiny insight counter (author-only)
    private func insightItem(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.systemScaled(10, weight: .semibold))
            Text("\(count) \(label)")
                .font(.systemScaled(11, weight: .regular))
        }
        .foregroundStyle(.secondary)
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
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(.blue)
                            .blur(radius: 3)
                            .opacity(0.6)
                    }
                    
                    Image(systemName: isPraying ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(isPraying ? 
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.secondary, Color.secondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                if prayingNowCount > 0 {
                    Text("\(prayingNowCount)")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isPraying ? Color.blue : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isPraying ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                    .shadow(color: isPraying ? Color.blue.opacity(0.2) : Color.clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isPraying ? Color.blue.opacity(0.3) : Color(.separator).opacity(0.25), lineWidth: isPraying ? 1.5 : 1)
            )
        }
        .buttonStyle(.instantFeedback)  // ✅ P0 FIX: INSTANT touch-down feedback
        .symbolEffect(.bounce, value: isPraying)
        // HIGH FIX: VoiceOver label so "hands.sparkles" icon is announced as an action
        .accessibilityLabel(isPraying ? "Stop praying for this post" : "Pray for this post")
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
        guard !post.authorId.isEmpty else { return }
        presentSheet(.userProfile(userId: post.authorId))
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
        HapticManager.impact(style: .light)
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                    // HeyFeed: amen = strong engagement signal
                    let amenTopicId: String = {
                        if let tag = post.topicTag, !tag.isEmpty { return tag }
                        switch post.category {
                        case .testimonies: return "testimonies"
                        case .prayer:      return "prayer_requests"
                        case .tip:         return "bible_teaching"
                        case .funFact:     return "bible_teaching"
                        case .openTable:   return "community"
                        }
                    }()
                    HeyFeedContradictionService.shared.recordEngage(targetId: amenTopicId)
                }

            } catch {
                logDebug("❌ Backend write FAILED: \(error.localizedDescription)", category: "AMEN")
                logDebug("  ROLLBACK: Reverting to hasSaidAmen=\(previousState)", category: "AMEN")

                // Revert optimistic update on error
                withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
        // Optimistic: collapse card immediately so it feels instant
        withAnimation(.easeOut(duration: 0.2)) {
            isDeletingPost = true
        }
        Task {
            postsManager.deletePost(postId: post.id)
            NotificationCenter.default.post(
                name: Notification.Name("postDeleted"),
                object: nil,
                userInfo: ["postId": post.id]
            )
            dlog("🗑️ Post deleted - notification sent")
        }
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
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                    withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                    withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
                        hasReposted = previousState
                    }
                    repostShakeError.toggle()
                    errorMessage = "Failed to toggle repost. Please try again."
                    activeAlert = .error(errorMessage)
                }
                HapticManager.notification(type: .error)

                logDebug("  AFTER ROLLBACK: hasReposted=\(hasReposted)", category: "REPOST")
            }
        }
    }
    

    private func sharePost() {
        HapticManager.impact(style: .light)
        if let post = post {
            presentSheet(.share(post: post, churchNote: churchNote))
        }
        
        // Record share engagement for ML training
        if let post = post, let userId = Auth.auth().currentUser?.uid {
            let postId = post.firebaseId ?? post.id.uuidString
            let shareTopicId: String = {
                if let tag = post.topicTag, !tag.isEmpty { return tag }
                switch post.category {
                case .testimonies: return "testimonies"
                case .prayer:      return "prayer_requests"
                case .tip:         return "bible_teaching"
                case .funFact:     return "bible_teaching"
                case .openTable:   return "community"
                }
            }()
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
                // HeyFeed: share = strong engagement signal
                HeyFeedContradictionService.shared.recordEngage(targetId: shareTopicId)
            }
        }
    }
    
    private func copyLink() {
        guard let post = post else { return }

        // Use firestoreId so the deep link is stable and matches the server-side route
        let deepLink = "amenapp://post/\(post.firestoreId)"

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
        let safeName = authorName.isEmpty ? "this user" : authorName  // ✅ Capture before async context
        
        Task {
            do {
                try await moderationService.muteUser(userId: authorId)
                dlog("🔇 Muted \(safeName)")
                
                await MainActor.run {
                    activeAlert = .muteSuccess(safeName)
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to mute: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to mute user. Please try again."
                    activeAlert = .error(errorMessage)
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
    
    private func blockAuthor() {
        guard let post = post else { return }
        let authorId = post.authorId
        let safeName = authorName.isEmpty ? "this user" : authorName  // ✅ Capture before async context
        
        Task {
            do {
                try await moderationService.blockUser(userId: authorId)
                dlog("🚫 Blocked \(safeName)")
                
                await MainActor.run {
                    activeAlert = .blockSuccess(safeName)
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to block: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to block user. Please try again."
                    activeAlert = .error(errorMessage)
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
                
                // Store "not interested" feedback in the TOP-LEVEL notInterested collection.
                // Firestore rule: /notInterested/{signalId} requires {userId, postId} fields
                // and checks userId == auth.uid. Document ID is userId_postId for idempotency.
                try await db.collection("notInterested")
                    .document("\(currentUserId)_\(post.firestoreId)")
                    .setData([
                        "userId": currentUserId,
                        "postId": post.firestoreId,
                        "postCategory": post.category.rawValue,
                        "postAuthorId": post.authorId,
                        "timestamp": FieldValue.serverTimestamp()
                    ], merge: true)
                
                dlog("👎 Marked post as not interested: \(post.firestoreId)")

                // HeyFeed: "not interested" = explicit skip signal
                let skipTopicId: String = {
                    if let tag = post.topicTag, !tag.isEmpty { return tag }
                    switch post.category {
                    case .testimonies: return "testimonies"
                    case .prayer:      return "prayer_requests"
                    case .tip:         return "bible_teaching"
                    case .funFact:     return "bible_teaching"
                    case .openTable:   return "community"
                    }
                }()
                await MainActor.run {
                    HeyFeedContradictionService.shared.recordSkip(targetId: skipTopicId)
                }

                await MainActor.run {
                    activeAlert = .feedbackReceived
                    HapticManager.notification(type: .success)
                }
            } catch {
                dlog("❌ Failed to mark not interested: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to save feedback. Please try again."
                    activeAlert = .error(errorMessage)
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
    
    // MARK: - Testimony Resonance

    private func fetchTestimonyResonance(actionType: String) {
        guard let post = post, !post.content.isEmpty else { return }
        let testimonyText = post.content
        Task {
            do {
                let functions = Functions.functions()
                let result = try await functions.httpsCallable("testimonyResonanceScore").call([
                    "testimonyText": testimonyText,
                    "actionType": actionType,
                ])
                if let data = result.data as? [String: Any],
                   let copy = data["copy"] as? String,
                   !copy.isEmpty {
                    await MainActor.run {
                        testimonyResonanceCopy = copy
                        withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                            showTestimonyResonance = true
                        }
                        testimonyResonanceDismissTask?.cancel()
                        testimonyResonanceDismissTask = Task {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showTestimonyResonance = false
                                }
                            }
                        }
                    }
                }
            } catch {
                // Silent fail — resonance copy is non-critical
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
            activeAlert = .error(errorMessage)
            
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
        HapticManager.impact(style: .light)
        logDebug("  📤 Performing OPTIMISTIC UI update...", category: "SAVE")
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                        // HeyFeed: save = strong engagement signal
                        let saveTopicId: String = {
                            if let tag = post.topicTag, !tag.isEmpty { return tag }
                            switch post.category {
                            case .testimonies: return "testimonies"
                            case .prayer:      return "prayer_requests"
                            case .tip:         return "bible_teaching"
                            case .funFact:     return "bible_teaching"
                            case .openTable:   return "community"
                            }
                        }()
                        HeyFeedContradictionService.shared.recordEngage(targetId: saveTopicId)
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
                    withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                    
                    activeAlert = .error(errorMessage)
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
        HapticManager.impact(style: .light)
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
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
                    withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
                        isPraying = previousState
                    }
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
    
    private func toggleFasting() {
        dlog("🔥 toggleFasting() called")
        
        guard let post = post else {
            dlog("❌ No post object available")
            return
        }
        
        guard category == .prayer, post.topicTag == "Prayer Request" else {
            dlog("⚠️ Not a prayer request post")
            return
        }
        
        dlog("   - Post ID: \(post.firestoreId)")
        dlog("   - Current state: \(isFasting ? "fasting" : "not fasting")")
        
        // Store previous state for rollback
        let previousState = isFasting
        
        // Haptic + optimistic update
        HapticManager.impact(style: .medium)
        withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
            isFasting.toggle()
        }
        
        let rtdb = RealtimeDatabaseManager.shared
        
        Task {
            let success: Bool
            
            if isFasting {
                success = await withCheckedContinuation { continuation in
                    rtdb.joinFast(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            } else {
                success = await withCheckedContinuation { continuation in
                    rtdb.leaveFast(postId: post.firestoreId) { result in
                        continuation.resume(returning: result)
                    }
                }
            }
            
            if success {
                dlog("✅ \(isFasting ? "Joined" : "Left") fast for post")
                await MainActor.run {
                    HapticManager.notification(type: .success)
                    ToastManager.shared.success(isFasting ? "Joined fast" : "Left fast")
                }
            } else {
                dlog("❌ Failed to \(isFasting ? "join" : "leave") fast")
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: springResponse, dampingFraction: springDamping))) {
                        isFasting = previousState
                    }
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
}

// MARK: - Liquid Glass Post Card Action Menu

@MainActor
final class AmenPostCardActionMenuCoordinator: ObservableObject {
    static let shared = AmenPostCardActionMenuCoordinator()
    @Published var activePostId: String?

    private init() {}
}

private struct AmenPostCardActionMenuAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct AmenPostCardPlusButton: View {
    let isExpanded: Bool
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.08 : 0.92),
                                Color.white.opacity(isDark ? 0.04 : 0.78),
                                Color.white.opacity(isDark ? 0.02 : 0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(isDark ? 0.16 : 0.72), lineWidth: 0.9)
                    )

                Image(systemName: "plus")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
            }
            .frame(width: 40, height: 40)
            .shadow(color: Color.black.opacity(isExpanded ? 0.12 : 0.08), radius: isExpanded ? 20 : 14, y: isExpanded ? 12 : 7)
            .scaleEffect(isPressed ? 0.94 : (isExpanded ? 1.02 : 1.0))
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}

private struct AmenPostCardOverflowButton: View {
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.08 : 0.94),
                                Color.white.opacity(isDark ? 0.04 : 0.80),
                                Color.white.opacity(isDark ? 0.02 : 0.72)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(isDark ? 0.16 : 0.74), lineWidth: 0.9)
                    )

                Image(systemName: "ellipsis")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 7)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }
}

private struct AmenPostCardActionMenu: View {
    static let preferredWidth: CGFloat = 296
    static let preferredHeight: CGFloat = 196

    let isFollowing: Bool
    let canFollow: Bool
    let onFollow: () -> Void
    let onVisitProfile: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        AmenGlassContainer(cornerRadius: 32) {
            VStack(spacing: 0) {
                AmenGlassRow(
                    icon: isFollowing ? "person.crop.circle.badge.checkmark" : "person.badge.plus",
                    title: isFollowing ? "Following" : "Follow",
                    isDisabled: !canFollow,
                    action: onFollow
                )

                Rectangle()
                    .fill(AmenTheme.Colors.separatorSubtle)
                    .frame(height: 0.8)
                    .padding(.horizontal, 18)

                AmenGlassRow(
                    icon: "person.circle",
                    title: "Visit Profile",
                    action: onVisitProfile
                )
            }
            .padding(8)
        }
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
        .scaleEffect(hasAppeared ? 1.0 : 0.88, anchor: .topLeading)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -10)
        .shadow(color: AmenTheme.Colors.glassHighlightTop.opacity(hasAppeared ? 0.35 : 0), radius: 18, y: -4)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.84))) {
                hasAppeared = true
            }
        }
        .onDisappear {
            hasAppeared = false
        }
    }
}

private struct AmenGlassContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    @State private var shinePhase: CGFloat = -0.9
    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat = 32, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.glassHighlightTop.opacity(isDark ? 0.8 : 1.0),
                            AmenTheme.Colors.glassFill.opacity(isDark ? 0.9 : 1.0),
                            AmenTheme.Colors.glassHighlightBottom.opacity(isDark ? 1.0 : 0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AmenTheme.Colors.glassStroke.opacity(isDark ? 1.0 : 0.95),
                                    AmenTheme.Colors.glassStroke.opacity(isDark ? 0.5 : 0.6)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceGlassDark.opacity(isDark ? 0.85 : 0.38))
                        .blur(radius: 14)
                )

            content
        }
        .compositingGroup()
        .shadow(color: AmenTheme.Colors.shadowFloating.opacity(0.82), radius: 34, y: 20)
        .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.55), radius: 12, y: 4)
        .overlay {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                AmenTheme.Colors.glassHighlightTop.opacity(isDark ? 0.8 : 1.0),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: proxy.size.width * 0.52)
                    .blur(radius: 11)
                    .rotationEffect(.degrees(16))
                    .offset(x: proxy.size.width * shinePhase)
                    .blendMode(.plusLighter)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AmenTheme.Colors.glassHighlightBottom.opacity(isDark ? 1.0 : 0.75))
                .blur(radius: 20)
                .padding(10)
                .opacity(0.7)
                .allowsHitTesting(false)
        }
        .onAppear {
            shinePhase = -0.9
            withAnimation(.easeInOut(duration: 0.95).delay(0.06)) {
                shinePhase = 1.05
            }
        }
    }
}

private struct AmenGlassRow: View {
    let icon: String
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Button {
            guard !isDisabled else { return }
            HapticManager.impact(style: .light)
            action()
        } label: {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isDark ? AmenTheme.Colors.surfaceElevated.opacity(0.92) : AmenTheme.Colors.glassFill.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AmenTheme.Colors.glassStroke.opacity(isDark ? 0.9 : 0.75), lineWidth: 0.8)
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: icon)
                            .font(.systemScaled(24, weight: .medium))
                            .foregroundStyle(.primary)
                    )

                Text(title)
                    .font(.systemScaled(25, weight: .medium, design: .rounded))
                    .foregroundStyle(isDisabled ? AmenTheme.Colors.textSecondary : AmenTheme.Colors.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        isDark
                        ? AmenTheme.Colors.pressedOverlay.opacity(isPressed ? 1.0 : 0.6)
                        : AmenTheme.Colors.selectedFill.opacity(isPressed ? 0.9 : 0.55)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isDisabled ? 0.72 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
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
                            .font(AMENFont.bold(28))
                        
                        Text("Help us keep AMEN safe. Why are you reporting this post?")
                            .font(AMENFont.regular(15))
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
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            
                            ZStack(alignment: .topLeading) {
                                if additionalDetails.isEmpty {
                                    Text("Provide any additional context that might help us review this report...")
                                        .font(AMENFont.regular(15))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                }
                                
                                TextEditor(text: $additionalDetails)
                                    .font(AMENFont.regular(15))
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
                                .font(AMENFont.regular(12))
                                .foregroundStyle(additionalDetails.count > 500 ? .red : .secondary)
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.2)))
                    }
                    
                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.checkered")
                                .font(.systemScaled(14))
                                .foregroundStyle(.blue)
                            
                            Text("Your report is confidential")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.primary)
                        }
                        
                        Text("We'll review this report and take appropriate action. The person who posted this won't know you reported it.")
                            .font(AMENFont.regular(13))
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
                            .font(.systemScaled(18))
                        Text("Submit Report")
                            .font(AMENFont.bold(16))
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
                        .fill(isSelected ? AmenTheme.Colors.statusError.opacity(0.16) : AmenTheme.Colors.surfaceElevated)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: reason.icon)
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(isSelected ? AmenTheme.Colors.statusError : AmenTheme.Colors.iconSecondary)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.rawValue)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Text(reason.description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }
                
                Spacer()
                
                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(24))
                    .foregroundStyle(isSelected ? AmenTheme.Colors.statusError : AmenTheme.Colors.textPlaceholder)
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? AmenTheme.Colors.statusError.opacity(0.3) : AmenTheme.Colors.borderSoft, lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? AmenTheme.Colors.statusError.opacity(0.12) : AmenTheme.Colors.shadowCard.opacity(0.55), radius: isSelected ? 12 : 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - View Modifiers

/// Handles all sheet presentations and alerts
@MainActor
private struct PostCardSheetsModifier: ViewModifier {
    @Binding var activeSheet: PostCard.PostCardSheet?
    @Binding var hasCommented: Bool

    // Closures instead of pre-built arrays — evaluated lazily only when the sheet opens,
    // not on every body render. This prevents the re-render feedback loop (stack overflow)
    // caused by non-Equatable closure arrays forcing SwiftUI to re-diff the modifier every pass.
    let optionsQuickActionsBuilder: () -> [AmenQuickAction]
    let optionsSectionsBuilder: () -> [AmenOptionsSectionModel]
    let feedReasonsBuilder: (Post) -> [FeedReason]
    let authorName: String
    let category: PostCard.PostCardCategory

    @State private var commentsRefreshTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .sheet(item: $activeSheet) { sheet in
                sheetView(for: sheet)
            }
    }

    @ViewBuilder
    private func sheetView(for sheet: PostCard.PostCardSheet) -> some View {
        switch sheet {
        case .options:
            AmenOptionsSheet(
                isPresented: optionsBinding(),
                title: "Post Options",
                subtitle: "Steward your feed with clarity",
                quickActions: optionsQuickActionsBuilder(),
                sections: optionsSectionsBuilder()
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(.regularMaterial)
        case .whyThisPost(let post):
            WhyAmISeeingThisSheet(post: post, reasons: feedReasonsBuilder(post))
        case .userProfile(let userId):
            UserProfileView(userId: userId, showsDismissButton: true)
        case .mentionedProfile(let userId):
            UserProfileView(userId: userId, showsDismissButton: true)
        case .edit(let post):
            EditPostSheet(post: post)
        case .share(let post, let note):
            if post.churchNoteId != nil, let note {
                ChurchNoteShareOptionsSheet(note: note)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            } else if post.isChurchShare, let churchName = post.sharedChurchName {
                FindChurchShareOptionsSheet(church: Church(
                    name: churchName,
                    denomination: post.sharedChurchDenomination ?? "",
                    address: "",
                    distance: "",
                    serviceTime: post.sharedChurchServiceTime ?? "",
                    phone: "",
                    coordinate: .init()
                ))
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            } else {
                PostShareOptionsSheet(post: post)
            }
        case .postDetail(let post):
            PostDetailView(post: post)
        case .comments(let post):
            CommentsView(post: post)
                .onDisappear { refreshCommentedState(for: post) }
        case .commentsWithQuote(let post, let prefill):
            CommentsView(post: post, prefillText: prefill)
                .onDisappear { refreshCommentedState(for: post) }
        case .report(let post):
            ReportPostSheet(
                post: post,
                postAuthor: authorName,
                category: category
            )
        case .churchNoteDetail(let note):
            ChurchNoteDetailModal(note: note)
        case .reasoningThread(let postId, let postText, let authorName):
            NavigationStack {
                ReasoningThreadView(postId: postId, postText: postText, postAuthorName: authorName)
            }
        case .tip(let creatorId, let creatorName):
            TipView(creatorId: creatorId, creatorName: creatorName, onSuccess: {})
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .berean(let initialQuery):
            BereanAIAssistantView(initialQuery: initialQuery)
        case .quoteComposer(let context):
            QuoteComposerView(context: context)
        case .shareExcerpt(let text, let attribution):
            ShareSheet(items: ["\(text)\n\n\(attribution)"])
        }
    }

    private func optionsBinding() -> Binding<Bool> {
        Binding(
            get: {
                if case .options = activeSheet { return true }
                return false
            },
            set: { newValue in
                if !newValue { activeSheet = nil }
            }
        )
    }

    private func refreshCommentedState(for post: Post) {
        commentsRefreshTask?.cancel()
        commentsRefreshTask = Task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            let postId = post.firestoreId
            let ref = Database.database().reference().child("user_comments").child(userId)
            let snapshot = try? await ref.getData()
            guard !Task.isCancelled else { return }
            if let children = snapshot?.children.allObjects as? [DataSnapshot] {
                let didComment = children.contains {
                    ($0.childSnapshot(forPath: "postId").value as? String) == postId
                }
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.12, dampingFraction: 0.75))) {
                        hasCommented = didComment
                    }
                }
            }
        }
    }
}

/// Handles all interaction observers and state updates
@MainActor
private struct PostCardInteractionsModifier: ViewModifier {
    let post: Post?
    // NOT @ObservedObject — observing the shared singleton caused every PostCard to re-render
    // on every interactionsService publish (constant Firebase traffic), creating a body
    // re-evaluation feedback loop that exhausted the call stack (EXC_BAD_ACCESS stack overflow).
    // State sync happens through targeted .onReceive(…removeDuplicates()) inside body instead.
    let interactionsService: PostInteractionsService
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

                // HeyFeed: Record impression for saturation detection
                let heyTopicId: String = {
                    if let tag = post.topicTag, !tag.isEmpty { return tag }
                    switch post.category {
                    case .testimonies: return "testimonies"
                    case .prayer:      return "prayer_requests"
                    case .tip:         return "bible_teaching"
                    case .funFact:     return "bible_teaching"
                    case .openTable:   return "community"
                    }
                }()
                await MainActor.run {
                    HeyFeedSaturationService.shared.recordImpression(topics: [heyTopicId])
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
            // PERF: Targeted .onReceive on narrow Equatable slices keyed to THIS post only.
            // Using .onReceive + removeDuplicates() instead of @ObservedObject prevents the
            // re-render feedback loop: @ObservedObject caused every Firebase publish to
            // re-evaluate this modifier's body, which cascaded back into PostCard.body.
            .onReceive(
                interactionsService.$postLightbulbs
                    .combineLatest(interactionsService.$postAmens,
                                   interactionsService.$postComments,
                                   interactionsService.$postReposts)
                    .map { [post] lbs, amens, comments, reposts -> PostCounts in
                        let id = post?.firebaseId ?? post?.id.uuidString ?? ""
                        return PostCounts(
                            lightbulbs: lbs[id] ?? 0,
                            amens:      amens[id] ?? 0,
                            comments:   comments[id] ?? 0,
                            reposts:    reposts[id] ?? 0
                        )
                    }
                    .removeDuplicates()
            ) { counts in
                lightbulbCount = counts.lightbulbs
                amenCount      = counts.amens
                commentCount   = counts.comments
                repostCount    = counts.reposts
            }
            // ✅ Update lightbulb state when userLightbulbedPosts changes
            .onReceive(
                interactionsService.$userLightbulbedPosts
                    .map { [post] set in set.contains(post?.firestoreId ?? "") }
                    .removeDuplicates()
            ) { newState in
                guard post != nil else { return }
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                if isLightbulbToggleInFlight {
                    if newState == expectedLightbulbState {
                        if hasLitLightbulb != newState {
                            withAnimation(animation) { hasLitLightbulb = newState }
                        }
                        isLightbulbToggleInFlight = false
                    }
                    return
                }
                if hasLitLightbulb != newState {
                    withAnimation(animation) { hasLitLightbulb = newState }
                }
            }
            // ✅ Update amen state when userAmenedPosts changes
            .onReceive(
                interactionsService.$userAmenedPosts
                    .map { [post] set in set.contains(post?.firestoreId ?? "") }
                    .removeDuplicates()
            ) { newState in
                guard post != nil else { return }
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                if hasSaidAmen != newState {
                    withAnimation(animation) { hasSaidAmen = newState }
                }
            }
            // ✅ Update repost state when userRepostedPosts changes
            .onReceive(
                interactionsService.$userRepostedPosts
                    .map { [post] set in set.contains(post?.firestoreId ?? "") }
                    .removeDuplicates()
            ) { newState in
                guard post != nil else { return }
                let animation: Animation? = hasCompletedInitialLoad ? .default : nil
                if isRepostToggleInFlight {
                    if newState == expectedRepostState {
                        if hasReposted != newState {
                            withAnimation(animation) { hasReposted = newState }
                        }
                        isRepostToggleInFlight = false
                    }
                    return
                }
                if hasReposted != newState {
                    withAnimation(animation) { hasReposted = newState }
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
                    .font(AMENFont.regular(16))
                    .padding(16)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                
                Spacer()
                
                // Character count
                HStack {
                    Text("\(editedContent.count) characters")
                        .font(AMENFont.regular(13))
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
                                .font(AMENFont.bold(16))
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
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                
                // URL text (shortened)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Link")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    
                    Text(displayURL)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // External link indicator
                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(14, weight: .semibold))
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

// MARK: - Poll Display Component

struct PostPollView: View {
    let postId: String
    let poll: PostPoll
    let currentUserId: String?
    
    @State private var userVote: String? = nil
    @State private var isVoting = false
    @State private var localPoll: PostPoll
    
    init(postId: String, poll: PostPoll, currentUserId: String?) {
        self.postId = postId
        self.poll = poll
        self.currentUserId = currentUserId
        self._localPoll = State(initialValue: poll)
    }
    
    var isPollExpired: Bool {
        guard let expiresAt = poll.expiresAt else { return false }
        return Date() > expiresAt
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Poll question (if provided)
            if !poll.question.isEmpty {
                Text(poll.question)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
            }
            
            // Poll options
            VStack(spacing: 8) {
                ForEach(localPoll.options) { option in
                    pollOptionButton(option)
                }
            }
            
            // Poll footer (total votes + expiry)
            HStack(spacing: 12) {
                Text("\(localPoll.totalVotes) \(localPoll.totalVotes == 1 ? "vote" : "votes")")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                
                if let expiresAt = poll.expiresAt {
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    if isPollExpired {
                        Text("Poll ended")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ends \(expiresAt, style: .relative)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onAppear {
            loadUserVote()
        }
    }
    
    @ViewBuilder
    private func pollOptionButton(_ option: PostPoll.PollOption) -> some View {
        let hasVoted = userVote != nil
        let isThisOption = userVote == option.id
        let percentage = localPoll.totalVotes > 0 ? Double(option.voteCount) / Double(localPoll.totalVotes) : 0.0
        
        Button {
            guard !hasVoted && !isPollExpired else { return }
            vote(for: option.id)
        } label: {
            HStack(spacing: 0) {
                // Background bar (shows percentage if voted)
                if hasVoted {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(isThisOption ? Color.blue.opacity(0.2) : Color(.tertiarySystemFill))
                            .frame(width: geometry.size.width * percentage)
                    }
                }
                
                HStack {
                    Text(option.text)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(isThisOption ? .blue : .primary)
                    
                    Spacer()
                    
                    if hasVoted {
                        Text("\(Int(percentage * 100))%")
                            .font(AMENFont.bold(14))
                            .foregroundStyle(isThisOption ? .blue : .secondary)
                        
                        if isThisOption {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isThisOption ? Color.blue : Color(.separator),
                    lineWidth: isThisOption ? 2 : 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hasVoted ? Color.clear : Color(.tertiarySystemFill))
                )
        )
        .disabled(hasVoted || isPollExpired || isVoting)
    }
    
    private func loadUserVote() {
        guard let uid = currentUserId else { return }
        
        // Check if user already voted by querying Firestore poll data
        Task {
            do {
                let doc = try await Firestore.firestore()
                    .collection("posts")
                    .document(postId)
                    .getDocument()
                
                if let pollData = doc.data()?["poll"] as? [String: Any],
                   let voters = pollData["voters"] as? [String: String],
                   let votedOptionId = voters[uid] {
                    await MainActor.run {
                        userVote = votedOptionId
                    }
                }
            } catch {
                dlog("❌ Error loading user vote: \(error)")
            }
        }
    }
    
    private func vote(for optionId: String) {
        guard currentUserId != nil, !isVoting else { return }
        
        isVoting = true
        HapticManager.impact(style: .light)
        
        // Optimistic update
        userVote = optionId
        var updatedOptions = localPoll.options
        if let index = updatedOptions.firstIndex(where: { $0.id == optionId }) {
            updatedOptions[index].voteCount += 1
        }
        localPoll = PostPoll(
            question: localPoll.question,
            options: updatedOptions,
            expiresAt: localPoll.expiresAt,
            totalVotes: localPoll.totalVotes + 1
        )
        
        Task {
            do {
                try await PollService.shared.vote(postId: postId, optionId: optionId)
                await MainActor.run {
                    isVoting = false
                    HapticManager.notification(type: .success)
                }
            } catch {
                // Revert optimistic update on error
                await MainActor.run {
                    userVote = nil
                    localPoll = poll
                    isVoting = false
                    HapticManager.notification(type: .error)
                    dlog("❌ Error voting: \(error)")
                }
            }
        }
    }
}
