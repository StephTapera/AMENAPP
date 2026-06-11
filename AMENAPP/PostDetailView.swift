//
//  PostDetailView.swift
//  AMENAPP
//
//  Post detail: hero image/content fills ~half the screen, floating liquid-glass X
//  to dismiss, comments below, glassmorphic comment input bar at bottom.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

struct PostDetailView: View {
    let post: Post

    @Environment(\.dismiss) var dismiss
    // Adaptive Ambient: scheme + reduce-motion feed coordinator.drive()/reset().
    @Environment(\.colorScheme) private var ambientScheme
    @Environment(\.accessibilityReduceMotion) private var ambientReduceMotion
    @ObservedObject private var commentService = CommentService.shared
    @ObservedObject private var commentFocusCoordinator = CommentFocusCoordinator.shared
    @ObservedObject private var userService = UserService.shared
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared

    @State private var isLoading = false
    @State private var commentText = ""
    // AIL C10/C11 pre-send gate — proposal-only, no-op unless enabled in a11y prefs.
    @State private var commentSendGate = AILPreSendGate(messageKey: "comment-composer")
    @State private var isFollowInFlight = false
    @State private var expandedCommentClusters: Set<String> = []
    @State private var highlightedCommentIDs: Set<String> = []
    @State private var highlightResetTask: Task<Void, Never>?
    @FocusState private var isCommentFocused: Bool

    // CommentService uses the full firestoreId as the Realtime Database key.
    // Truncating to prefix(8) produces a path that doesn't exist, resulting in empty comments.
    private var postId: String { post.firestoreId }

    // Adaptive Ambient source identity: post doc id + media revision (falls back to "1").
    private var ambientSourceKey: AmbientSourceKey {
        let rev = post.imageURLs?.first(where: { !$0.isEmpty }).map { String($0.hashValue) } ?? "1"
        return AmbientSourceKey(id: "post/\(post.firestoreId)", revision: rev)
    }

    // Derived from @Published CommentService state — no local copy, no concurrent mutation.
    // SwiftUI re-renders automatically whenever commentService.comments or commentReplies changes.
    private var commentsWithReplies: [CommentWithReplies] {
        let topLevel = commentService.comments[postId] ?? []
        return topLevel.map { comment in
            let replies = commentService.commentReplies[comment.id ?? ""] ?? []
            return CommentWithReplies(comment: comment, replies: replies)
        }
    }

    // Engagement avatar strip
    @State private var recentReactors: [ReactorUser] = []
    @State private var reactorCount: Int = 0
    @State private var reactorFetchTask: Task<Void, Never>? = nil
    @State private var reactorsVisible: Bool = false

    @State private var isListening = false
    @State private var pollingTask: Task<Void, Never>?
    @State private var isGuardrailBlocked = false
    // Track 4 — BereanInsightCard tap press animation
    @State private var isInsightCardPressed = false
    @State private var isSubmittingComment = false  // debounce: prevent double-submit
    @State private var isPostExpanded = true         // Default expanded in detail view
    @State private var musicCardMode: MusicCardMode = .expanded
    @State private var replyingToUsername: String? = nil  // Set when Reply is tapped
    @State private var rateLimitMessage: String? = nil   // Auto-dismissing rate limit notice
    @State private var rateLimitDismissTask: Task<Void, Never>? = nil
    @State private var showCommentsLoadError = false      // P2 FIX: surface loadComments failure
    // Comment quality nudge sheet
    @State private var showNudgeSheet = false
    @State private var pendingNudge: CommentService.PendingCommentSubmission? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var carouselPage: Int = 0               // Active slide in media carousel
    /// Reactive scroll target — set by consumePendingCommentFocus() to trigger ScrollViewReader scrollTo.
    @State private var commentScrollTarget: String?
    @State private var textSelection: PostTextSelection?
    @State private var isTextSelecting = false

    // Testimony features — only active when post.category == .testimonies
    @StateObject private var witnessService = TestimonyWitnessService()
    @StateObject private var strengthService = TestimonyStrengthService()
    @State private var showRipple = false
    @State private var showAnsweredComposer = false
    @State private var linkedTestimonyPost: Post? = nil
    
    // Prayer features — fasting chain
    @State private var isFasting = false

    // Destructive action confirmation dialogs
    @State private var showDeletePostConfirm = false
    @State private var showBlockConfirm = false
    @State private var blockTargetId: String? = nil

    // Scroll-driven sheet expansion (0 = compact hero visible, 1 = full-screen sheet)


    // Single sheet enum — avoids "only presenting a single sheet" SwiftUI warning
    private enum DetailSheet: Identifiable {
        case berean(String), share, profile, report, editPost, discussion
        case quoteComposer(QuoteComposerContext)
        case commentsWithQuote(String)
        case shareExcerpt(String)
        var id: String {
            switch self {
            case .berean:    return "berean"
            case .share:     return "share"
            case .profile:   return "profile"
            case .report:    return "report"
            case .editPost:  return "editPost"
            case .discussion: return "discussion"
            case .quoteComposer(let context):
                return "quoteComposer_\(context.id.uuidString)"
            case .commentsWithQuote(let text):
                return "commentsWithQuote_\(text.hashValue)"
            case .shareExcerpt(let text):
                return "shareExcerpt_\(text.hashValue)"
            }
        }
    }
    @State private var activeDetailSheet: DetailSheet?
    @ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
    private var isSaved: Bool {
        guard let firebaseId = post.firebaseId else { return false }
        return savedPostsService.savedPostIds.contains(firebaseId)
    }

    // Check if this is the current user's post
    private var isUserPost: Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        return post.authorId == currentUserId
    }

    // Check if following the post author
    private var isFollowing: Bool {
        followService.following.contains(post.authorId)
    }

    // Whether the post has a media image to show as hero
    private var heroImageURL: URL? {
        guard let urls = post.imageURLs?.filter({ !$0.isEmpty }), let first = urls.first else { return nil }
        return URL(string: first)
    }

    // True if this post has at least one valid image URL
    private var hasMedia: Bool {
        heroImageURL != nil
    }

    // All valid image URLs (supports multi-image carousel)
    private var allImageURLs: [URL] {
        (post.imageURLs ?? [])
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
    }

    var body: some View {
        AmbientScope { coordinator in
        VStack(spacing: 0) {
            // ── Top nav bar ─────────────────────────────────────────
            topNavBar

            ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {

                VStack(spacing: 0) {
                    // ── Media carousel or compact category banner ────────
                    if !allImageURLs.isEmpty {
                        mediaCarousel
                    } else {
                        textOnlyBanner
                    }

                    // ── Full post text (expanded by default in detail view) ──
                    // Adaptive Ambient C6: post body is a reading plane — neutral card,
                    // tint hard-capped at 0.04 × intensity, never a chroma background.
                    AdaptiveContentCard(isReadingPlane: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let quote = post.quote {
                            quoteSnippetView(quote)
                        }

                        ZStack(alignment: .topLeading) {
                            SelectablePostTextView(
                                text: post.content,
                                mentions: post.mentions,
                                font: UIFont.systemFont(ofSize: 16),
                                lineSpacing: 4,
                                lineLimit: isPostExpanded ? nil : 5,
                                onMentionTap: { mention in
                                    if !mention.userId.isEmpty {
                                        NotificationCenter.default.post(
                                            name: Notification.Name("openUserProfile"),
                                            object: mention.userId
                                        )
                                    }
                                },
                                onTextTap: {
                                    if textSelection != nil {
                                        clearTextSelection()
                                    }
                                },
                                selection: $textSelection,
                                isSelecting: $isTextSelecting
                            )
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
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPostExpanded)

                        // Show collapse option only for long posts
                        if !isPostExpanded {
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
                                    isPostExpanded = true
                                }
                            } label: {
                                Text("Read more")
                                    .font(.systemScaled(14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if !isTextSelecting && post.content.count > 80 {
                            Text("Select a thought to quote")
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }

                        // Topic tag
                        if let topicTag = post.topicTag, !topicTag.isEmpty {
                            Text("#\(topicTag)")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }

                        // Accessibility Intelligence Layer — translate / culture notes (C1).
                        // Fails open to the original; "View original" always available.
                        if AMENFeatureFlags.shared.accessibilityIntelligenceEnabled,
                           !post.content.isEmpty {
                            AILTranslatePill(
                                originalText: post.content,
                                originalRef: post.firestoreId
                            )
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    } // end AdaptiveContentCard (post body reading plane)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                    // Accessibility Intelligence Layer — scripture explanation (C1, iron rule 2).
                    // Canonical verse rendered verbatim; explanation is labeled, never re-leveled.
                    if AMENFeatureFlags.shared.accessibilityIntelligenceEnabled,
                       let ref = post.verseReference, !ref.isEmpty,
                       let verse = post.verseText, !verse.isEmpty {
                        AILScriptureExplanationPanel(canonicalVerse: verse, reference: ref)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // ── Music attachment card ────────────────────────────────
                    if let music = post.music {
                        MusicCardContainer(track: music, displayMode: $musicCardMode)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    Divider()

                    // ── Engagement bar ──────────────────────────────────────
                    // Adaptive Ambient: reaction/controls bar on the only sanctioned glass
                    // primitive (tint × intensity, Reduce Transparency / iOS17 fallback handled).
                    AdaptiveGlassContainer(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) {
                        engagementBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)

                    // ── Prayer Status Track — prayer posts, author only ────────
                    if post.category == .prayer {
                        PrayerStatusTrackView(post: post) {
                            showAnsweredComposer = true
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        PrayerFulfillmentInsightView(postId: postId)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    Divider()

                    // ── Live Witness Banner — testimony posts only ────────────
                    if post.category == .testimonies {
                        WitnessBannerView(service: witnessService)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    // ── Prayer Arc — testimony ↔ prayer link ─────────────────
                    // Only shown on testimony posts with linkedPrayerRequestId set.
                    if post.category == .testimonies {
                        PrayerArcCard(testimonyPost: post)
                    }

                    // ── Answered prayer banner — prayer posts with linked testimony ──
                    if post.category == .prayer, post.linkedTestimonyId != nil {
                        PrayerAnsweredBannerView(post: post) { tp in
                            linkedTestimonyPost = tp
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    // ── Testimony origin link — on answered-prayer testimony posts ──
                    if post.category == .testimonies && post.isAnsweredPrayer {
                        TestimonyOriginLinkView(post: post)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        TestimonyRippleView(count: post.rippleCount ?? 0)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    Divider()

                    // ── Testimony Strength Meter — testimony posts only ───────
                    if post.category == .testimonies {
                        StrengthMeterView(service: strengthService)
                    }

                    // ── Conversation Thread (Threads-style wisdom UI) ────────
                    // TODO(ambient) C6: each comment card must be a reading plane
                    // (AdaptiveContentCard(isReadingPlane: true)). Comment row chrome is owned
                    // by ConversationThreadView (separate file), so wrap per-row there rather than
                    // wrapping the whole thread in one card here — wrapping the container would
                    // collapse all comments into a single card and break the threaded layout.
                    if showCommentsLoadError {
                        commentsErrorView
                    } else {
                        ConversationThreadView(
                            post: post,
                            postId: postId,
                            commentsWithReplies: commentsWithReplies,
                            isLoading: isLoading,
                            savedBookIds: [],
                            expandedClusters: $expandedCommentClusters,
                            highlightedCommentIDs: highlightedCommentIDs,
                            onReply: { parentComment in
                                if let parent = parentComment {
                                    commentText = "@\(parent.authorUsername) "
                                    replyingToUsername = parent.authorUsername
                                } else {
                                    replyingToUsername = nil
                                }
                                isCommentFocused = true
                            },
                            onReplyWithQuote: { comment, selection in
                                let excerpt = "“\(selection.text)” — \(comment.authorName)"
                                commentText = excerpt + "\n\n"
                                replyingToUsername = comment.authorUsername
                                isCommentFocused = true
                            },
                            onAmen: { comment in
                                let uid = Auth.auth().currentUser?.uid ?? ""
                                let alreadyAmened = !uid.isEmpty && comment.amenUserIds.contains(uid)
                                Task { try? await CommentService.shared.toggleAmen(commentId: comment.id ?? "", postId: postId, currentlyAmened: alreadyAmened) }
                            },
                            onDelete: { comment in
                                Task { try? await CommentService.shared.deleteComment(commentId: comment.id ?? "", postId: postId) }
                            },
                            onProfileTap: { userId in
                                activeDetailSheet = .profile
                            },
                            onBerean: { query in
                                activeDetailSheet = .berean(query)
                            }
                        )
                    }

                    // Ripple overlay for testimony post reply submit
                    if post.category == .testimonies && showRipple {
                        GeometryReader { geo in
                            Circle()
                                .fill(Color.accentColor.opacity(0.18))
                                .frame(width: showRipple ? geo.size.width * 2 : 0,
                                       height: showRipple ? geo.size.width * 2 : 0)
                                .position(x: geo.size.width / 2, y: geo.size.height)
                                .opacity(showRipple ? 0 : 0.3)
                        }
                        .frame(height: 60)
                        .allowsHitTesting(false)
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                commentInputBar
            }
            .onChange(of: commentScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.9))) {
                    scrollProxy.scrollTo(target, anchor: .center)
                }
                commentScrollTarget = nil
            }
            } // end ScrollViewReader
        }
        // Adaptive Ambient: page wash behind cards (light touch — cards stay dominant).
        // Renders byte-identical neutral when AdaptiveColorsMode == .off / Reduce Transparency.
        // TODO(ambient): pass the decoded hero UIImage as `bleedImage:` once the carousel
        // exposes a decoded thumbnail (currently media is AsyncImage-by-URL, no UIImage reachable).
        .background(AdaptiveAmbientBackground())
        .sheet(isPresented: $showAnsweredComposer) {
            AnsweredPrayerComposerView(originalPrayerPost: post)
        }
        .sheet(item: $linkedTestimonyPost) { tp in
            PostDetailView(post: tp)
        }
        .navigationBarHidden(true)
        .sheet(item: $activeDetailSheet) { sheet in
            switch sheet {
            case .berean(let query):
                BereanAIAssistantView(initialQuery: query.isEmpty ? nil : query)
            case .share:
                PostShareOptionsSheet(post: post)
            case .profile:
                UserProfileView(userId: post.authorId, showsDismissButton: true)
            case .report:
                ReportPostSheet(
                    post: post,
                    postAuthor: post.authorName,
                    category: post.category == .testimonies ? .testimonies : post.category == .prayer ? .prayer : .openTable
                )
            case .editPost:
                EditPostSheet(post: post)
            case .discussion:
                DiscussionThreadView(
                    postId: postId,
                    postTitle: post.content.isEmpty ? nil : String(post.content.prefix(80))
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            case .quoteComposer(let context):
                QuoteComposerView(context: context)
            case .commentsWithQuote(let text):
                CommentsView(post: post, prefillText: text)
            case .shareExcerpt(let text):
                ShareSheet(items: [text])
            }
        }
        // Comment quality nudge sheet — shown when checkCommentQuality returns "nudge"
        .sheet(isPresented: $showNudgeSheet, onDismiss: {
            // User swiped to dismiss (only possible for safety == .allow nudges)
            // Treat as "edit" — keep commentText in place, do nothing
            pendingNudge = nil
        }) {
            if let pending = pendingNudge {
                CommentNudgeSheet(
                    nudges: pending.nudges,
                    safetyDecision: pending.safetyDecision,
                    onEdit: {
                        showNudgeSheet = false
                        pendingNudge = nil
                        // Re-focus the comment composer so user can edit
                        isCommentFocused = true
                    },
                    onPostAnyway: {
                        postAfterNudgeDismissal()
                    }
                )
            }
        }
        // H1b — confirm before deleting own post
        .confirmationDialog("Delete this post?", isPresented: $showDeletePostConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                postsManager.deletePost(postId: post.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
        // H1a — confirm before blocking another user
        .confirmationDialog("Block this user?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    try? await BlockService.shared.blockUser(userId: blockTargetId ?? "")
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("They won't be able to see your content and you won't see theirs.")
        }
        .task {
            await loadComments()
            consumePendingCommentFocus()
            if !isListening {
                commentService.startListening(to: postId)
                isListening = true
            }
            reactorFetchTask = Task { await loadRecentReactors() }
            if post.category == .testimonies {
                witnessService.startWitnessing(postId: postId)
                strengthService.startListening(postId: postId)
            }
            // Adaptive Ambient: drive palette from the post media.
            // TODO(ambient): supply the decoded hero UIImage here (image arg currently nil ⇒
            // fails closed to neutral). Carousel uses AsyncImage-by-URL, so no UIImage is
            // reachable in this view yet. Key is stable; once a decoded thumbnail exists, pass it.
            coordinator.drive(with: nil, key: ambientSourceKey,
                              scheme: ambientScheme, reduceMotion: ambientReduceMotion)
        }
        .onDisappear {
            // Adaptive Ambient: clear tint so the next screen starts neutral.
            coordinator.reset(scheme: ambientScheme, reduceMotion: ambientReduceMotion)
            highlightResetTask?.cancel()
            highlightResetTask = nil
            clearTextSelection()
            if isListening {
                commentService.stopListening(to: postId)
                pollingTask?.cancel()
                pollingTask = nil
                isListening = false
            }
            reactorFetchTask?.cancel()
            reactorFetchTask = nil
            if post.category == .testimonies {
                witnessService.stopWitnessing()
                strengthService.stopListening()
            }
            if let music = post.music,
               AudioPlaybackManager.shared.currentTrackID == music.id {
                AudioPlaybackManager.shared.pause()
            }
        }
        // commentsWithReplies is now a computed property derived from @Published
        // CommentService state, so no notification handlers are needed here.
        // SwiftUI automatically re-renders when commentService.comments changes.
        } // end AmbientScope
    }

    // MARK: - Category gradient (used by textOnlyBanner)
    // Category-aware gradient for text-only posts
    private var postGradientBackground: some View {
        let colors: [Color] = {
            switch post.category {
            case .prayer:
                return [Color(red: 0.05, green: 0.08, blue: 0.25), Color(red: 0.10, green: 0.15, blue: 0.35)]
            case .testimonies:
                return [Color(red: 0.18, green: 0.06, blue: 0.02), Color(red: 0.30, green: 0.12, blue: 0.04)]
            case .openTable:
                return [Color(red: 0.02, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.18, blue: 0.28)]
            default:
                return [Color(white: 0.06), Color(white: 0.14)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let imageURL = post.authorProfileImageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.4))
                    .overlay(Text(post.authorInitials).font(.systemScaled(14, weight: .semibold)).foregroundStyle(.white))
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        } else {
            Circle()
                .fill(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(post.authorInitials).font(.systemScaled(14, weight: .semibold)).foregroundStyle(.white))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Top Nav Bar

    private var topNavBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // X / back button — left, alone
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Author info — right side
            Button { activeDetailSheet = .profile } label: {
                HStack(spacing: 9) {
                    authorAvatar
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.authorUsername ?? post.authorName)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let tag = post.topicTag, !tag.isEmpty {
                            Text("#\(tag)")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timeAgo(from: post.createdAt))
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Media Carousel (Threads-style, AMEN liquid glass)

    private var mediaCarousel: some View {
        GeometryReader { geo in
            let imageHeight = min(geo.size.width * 5 / 4, 420)
            ZStack(alignment: .bottom) {
                TabView(selection: $carouselPage) {
                    ForEach(Array(allImageURLs.enumerated()), id: \.offset) { index, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: imageHeight)
                                    .clipped()
                            case .empty:
                                Rectangle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: geo.size.width, height: imageHeight)
                                    .overlay(ProgressView().tint(.secondary))
                            case .failure:
                                Rectangle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: geo.size.width, height: imageHeight)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.systemScaled(32, weight: .light))
                                            .foregroundStyle(.secondary)
                                    )
                            @unknown default:
                                Rectangle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: geo.size.width, height: imageHeight)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: imageHeight)

                // Liquid glass pill indicators (multi-image only)
                if allImageURLs.count > 1 {
                    carouselIndicators
                        .padding(.bottom, 14)
                }
            }
            .frame(height: imageHeight)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 5, contentMode: .fit)
    }

    private var carouselIndicators: some View {
        HStack(spacing: 5) {
            ForEach(0..<allImageURLs.count, id: \.self) { i in
                Capsule()
                    .fill(i == carouselPage
                          ? Color.white.opacity(0.96)
                          : Color.white.opacity(0.40))
                    .frame(width: i == carouselPage ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: carouselPage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
        )
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }

    // MARK: - Text-only compact banner

    private var textOnlyBanner: some View {
        ZStack {
            postGradientBackground
            Image(systemName: categorySymbol)
                .font(.systemScaled(26, weight: .light))
                .foregroundStyle(.white.opacity(0.20))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
    }

    private var categorySymbol: String {
        switch post.category {
        case .prayer:       return "hands.sparkles"
        case .testimonies:  return "star.circle"
        case .openTable:    return "bubble.left.and.bubble.right"
        default:            return "text.bubble"
        }
    }

    // MARK: - Engagement Bar

    private var engagementBar: some View {
        HStack(spacing: 20) {
            // Amen button
            Button {
                Task { try? await interactionsService.toggleAmen(postId: post.firestoreId) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: interactionsService.userAmenedPosts.contains(post.firestoreId) ? "hands.clap.fill" : "hands.clap")
                        .font(.systemScaled(17))
                        .foregroundStyle(interactionsService.userAmenedPosts.contains(post.firestoreId) ? Color.orange : .secondary)
                    if post.amenCount > 0 {
                        Text("\(post.amenCount)")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Comment button
            Button {
                isCommentFocused = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "message")
                        .font(.systemScaled(17))
                        .foregroundStyle(.secondary)
                    if !commentsWithReplies.isEmpty {
                        Text("\(commentsWithReplies.count)")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Discussion thread button
            Button {
                activeDetailSheet = .discussion
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.systemScaled(17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open discussion")

            // Join Fast button - only for prayer request posts
            if post.category == .prayer, post.topicTag == "Prayer Request" {
                Button {
                    toggleFasting()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isFasting ? "flame.fill" : "flame")
                            .font(.systemScaled(17))
                            .foregroundStyle(isFasting ? Color.orange : .secondary)
                        if isFasting {
                            Text("Fasting")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Bookmark / Save button
            Button {
                HapticManager.impact(style: .light)
                if let firebaseId = post.firebaseId {
                    Task { try? await savedPostsService.toggleSavePost(postId: firebaseId) }
                }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.systemScaled(17))
                    .foregroundStyle(isSaved ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            // Ellipsis menu — report, edit (own posts), block/mute
            Menu {
                if isUserPost {
                    Button {
                        activeDetailSheet = .editPost
                    } label: {
                        Label("Edit Post", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeletePostConfirm = true
                    } label: {
                        Label("Delete Post", systemImage: "trash")
                    }
                } else {
                    Button {
                        activeDetailSheet = .report
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    Button {
                        blockTargetId = post.authorId
                        showBlockConfirm = true
                    } label: {
                        Label("Block \(post.authorName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.systemScaled(17))
                    .foregroundStyle(.secondary)
            }

            // Berean AI — AMEN logo button (same style as OpenTable top-right)
            Button {
                let q = "Help me reflect on this post: \(post.content.prefix(150))"
                activeDetailSheet = .berean(q)
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                    Image("amen-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .blendMode(.multiply)
                }
            }
            .buttonStyle(.plain)

            // Share button
            Button {
                activeDetailSheet = .share
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.systemScaled(17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func quoteSnippetView(_ quote: PostQuoteMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(quote.sourceAuthorName)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.primary)
                if let username = quote.sourceAuthorUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
            }

            Text(quote.sourceExcerpt)
                .font(.systemScaled(14))
                .foregroundStyle(.primary)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 1.0, green: 0.95, blue: 0.75))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
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
            sourceAuthorId: post.authorId,
            sourceAuthorName: post.authorName,
            sourceAuthorUsername: post.authorUsername,
            selection: selection
        )
        activeDetailSheet = .quoteComposer(context)
        clearTextSelection()
    }

    private func handleReplyWithQuote(_ selection: PostTextSelection) {
        guard canQuote(post) else {
            HapticManager.notification(type: .warning)
            ToastManager.shared.info("Quoting is not allowed for this post")
            clearTextSelection()
            return
        }
        let excerpt = "“\(selection.text)” — \(post.authorName)"
        commentText = excerpt + "\n\n"
        isCommentFocused = true
        clearTextSelection()
    }

    private func handleSaveSelection(_ selection: PostTextSelection) {
        let excerpt = SavedExcerpt(
            postId: post.firestoreId,
            authorId: post.authorId,
            authorName: post.authorName,
            excerpt: selection.text
        )
        ExcerptStore.shared.save(excerpt)
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Saved excerpt")
        clearTextSelection()
    }

    private func handleShareSelection(_ selection: PostTextSelection) {
        let excerpt = "“\(selection.text)” — \(post.authorName)"
        activeDetailSheet = .shareExcerpt(excerpt)
        clearTextSelection()
    }

    private func handleBereanSelection(_ selection: PostTextSelection) {
        let query = "Explain and reflect on: \"\(selection.text)\""
        activeDetailSheet = .berean(query)
        clearTextSelection()
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

    private var commentsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(commentsWithReplies.count)")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            LazyVStack(spacing: 0) {
                ForEach(commentsWithReplies) { commentWithReplies in
                    CommentRowView(
                        comment: commentWithReplies.comment,
                        replies: commentWithReplies.replies,
                        postId: postId,
                        onReply: { username in
                            commentText = "@\(username) "
                            replyingToUsername = username
                            isCommentFocused = true
                        }
                    )
                    .padding(.horizontal, 16)

                    Divider()
                        .padding(.leading, 64) // indent past avatar
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var emptyCommentsView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Comments")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("0")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.systemScaled(28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("No comments yet")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    isCommentFocused = true
                } label: {
                    Text("Be the first to comment")
                        .font(.systemScaled(14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var commentsErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.systemScaled(28))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Could not load comments")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                Task { await loadComments() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.systemScaled(14))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            AMENLoadingIndicator()
            Text("Loading comments…")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Comment Input Bar (ThreadComposerView)

    private var commentInputBar: some View {
        VStack(spacing: 8) {
            // Accessibility Intelligence Layer — comment intent picker (C8).
            // Tapping an intent focuses the composer ready to write in that spirit.
            if AMENFeatureFlags.shared.accessibilityIntelligenceEnabled {
                AILCommentIntentPicker { _ in
                    isCommentFocused = true
                }
            }

            ThreadComposerView(
                text: $commentText,
                replyingToUsername: $replyingToUsername,
                isFocused: $isCommentFocused,
                onSubmit: {
                    // Route through the AIL pre-send gate. When disabled (default),
                    // this forwards straight to submitComment — zero interference.
                    let draft = commentText
                    commentSendGate.submit(draft: draft) { finalText in
                        commentText = finalText
                        submitComment()
                    }
                },
                onBerean: { query in activeDetailSheet = .berean(query) }
            )
        }
        .ailPreSendGate(commentSendGate)
    }

    // MARK: - Helpers

    private func loadComments() async {
        isLoading = true
        showCommentsLoadError = false
        do {
            // fetchCommentsWithReplies populates commentService.comments[postId]
            // and commentService.commentReplies — commentsWithReplies (computed) updates automatically.
            _ = try await commentService.fetchCommentsWithReplies(for: postId)
        } catch {
            dlog("❌ Failed to load comments: \(error)")
            // Only show the error state when comments are empty — if we already have cached
            // comments from the real-time listener, keep showing them rather than replacing
            // them with an error banner.
            if commentsWithReplies.isEmpty {
                showCommentsLoadError = true
            }
        }
        isLoading = false
    }

    private func submitComment() {
        guard !commentText.isEmpty, !isGuardrailBlocked, !isSubmittingComment else { return }
        let text = commentText
        commentText = ""
        replyingToUsername = nil
        isCommentFocused = false
        isSubmittingComment = true
        Task { @MainActor in
            defer { isSubmittingComment = false }
            do {
                _ = try await commentService.addComment(postId: postId, content: text, post: post)
                // UI updates automatically via @Published commentService.comments
                if post.category == .testimonies {
                    withAnimation(.easeOut(duration: 0.8)) { showRipple = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        showRipple = false
                    }
                }
            } catch let nudgeErr as CommentService.CommentNudgeRequired {
                // Quality gate returned "nudge" — surface the prompt sheet.
                // Text is already cleared; we restore it so user can edit if they choose.
                commentText = text
                pendingNudge = nudgeErr.pending
                showNudgeSheet = true
            } catch {
                dlog("❌ Failed to post comment: \(error)")
                let nsError = error as NSError
                if nsError.domain == "CommentService" && nsError.code == -11 {
                    // Rate limit hit — show subtle auto-dismissing notice, don't restore text
                    showRateLimitMessage(nsError.localizedDescription)
                } else {
                    commentText = text  // restore on failure for other errors
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func postAfterNudgeDismissal() {
        guard let pending = pendingNudge else { return }
        showNudgeSheet = false
        pendingNudge = nil
        isSubmittingComment = true
        Task { @MainActor in
            defer { isSubmittingComment = false }
            do {
                _ = try await commentService.resumeAfterNudge(pending)
                if post.category == .testimonies {
                    withAnimation(.easeOut(duration: 0.8)) { showRipple = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        showRipple = false
                    }
                }
            } catch {
                dlog("❌ Failed to post comment after nudge: \(error)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func consumePendingCommentFocus() {
        let pendingFocus = commentFocusCoordinator.consume()

        if let expandId = pendingFocus.expand, !expandId.isEmpty {
            expandedCommentClusters.insert(expandId)
        }

        guard let highlightId = pendingFocus.highlight, !highlightId.isEmpty else { return }

        highlightedCommentIDs = [highlightId]
        highlightResetTask?.cancel()
        highlightResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if highlightedCommentIDs == [highlightId] {
                highlightedCommentIDs.removeAll()
            }
        }

        // Scroll to the comment after a brief settle delay so the view is fully rendered.
        if let scrollId = pendingFocus.scroll, !scrollId.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
                commentScrollTarget = scrollId
            }
        }
    }

    private func showRateLimitMessage(_ message: String) {
        rateLimitDismissTask?.cancel()
        rateLimitMessage = message
        rateLimitDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { rateLimitMessage = nil }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60       { return "just now" }
        if interval < 3600     { return "\(Int(interval / 60))m" }
        if interval < 86400    { return "\(Int(interval / 3600))h" }
        if interval < 604800   { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    private func handleFollowTap() {
        guard !isFollowInFlight else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid,
              post.authorId != currentUserId else { return }
        // Set in-flight immediately (synchronous) so button dims before the Task runs
        isFollowInFlight = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                try await followService.toggleFollow(userId: post.authorId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                dlog("❌ Follow error: \(error.localizedDescription)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isFollowInFlight = false
        }
    }
    
    // MARK: - Fasting Chain
    
    private func toggleFasting() {
        dlog("🔥 toggleFasting() called in PostDetailView")
        
        guard post.category == .prayer, post.topicTag == "Prayer Request" else {
            dlog("⚠️ Not a prayer request post")
            return
        }
        
        // Store previous state for rollback
        let previousState = isFasting
        
        // Haptic + optimistic update
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
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
            
            await MainActor.run {
                if success {
                    dlog("✅ \(isFasting ? "Joined" : "Left") fast for post")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastManager.shared.success(isFasting ? "Joined fast" : "Left fast")
                } else {
                    dlog("❌ Failed to \(isFasting ? "join" : "leave") fast")
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
                        isFasting = previousState
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - Reactor Fetch

    @MainActor
    private func loadRecentReactors() async {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }
        let stablePostId = post.firestoreId
        lazy var db = Firestore.firestore()
        let rtdb = Database.database().reference()

        // 1. Fetch top 8 reactor user IDs from RTDB amens node, ordered by timestamp desc
        guard !Task.isCancelled else { return }
        let amensSnap: DataSnapshot
        do {
            amensSnap = try await rtdb
                .child("postInteractions")
                .child(stablePostId)
                .child("amens")
                .getData()
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        guard amensSnap.exists(), let dict = amensSnap.value as? [String: Any] else { return }

        // Sort by timestamp descending, take top 8
        let sortedUids: [String] = dict
            .compactMap { key, value -> (String, Double)? in
                let ts = (value as? [String: Any])?["timestamp"] as? Double ?? 0
                return (key, ts)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map(\.0)

        guard !sortedUids.isEmpty else { return }

        let totalCount = dict.count

        // 2. Batch-fetch Firestore user docs
        guard !Task.isCancelled else { return }
        let userSnap: QuerySnapshot
        do {
            userSnap = try await db
                .collection("users")
                .whereField(FieldPath.documentID(), in: Array(sortedUids.prefix(10)))
                .getDocuments()
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        // 3. For each reactor, check if current user follows them
        var reactors: [ReactorUser] = []
        for doc in userSnap.documents {
            guard !Task.isCancelled else { return }
            let data = doc.data()
            let imageURL = (data["profileImageURL"] as? String) ?? (data["profilePhotoURL"] as? String)
            guard let imageURL, !imageURL.isEmpty else { continue }

            // Check following status: users/{currentUid}/following/{reactorUid}
            var isFollowed = false
            let followSnap = try? await db
                .collection("users")
                .document(currentUid)
                .collection("following")
                .document(doc.documentID)
                .getDocument()
            isFollowed = followSnap?.exists ?? false

            guard !Task.isCancelled else { return }
            reactors.append(ReactorUser(
                id: doc.documentID,
                profileImageURL: imageURL,
                isFollowedByCurrentUser: isFollowed
            ))
        }

        guard !Task.isCancelled else { return }

        // 4. Update state
        recentReactors = reactors
        reactorCount = totalCount
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            reactorsVisible = true
        }
    }
}

// MARK: - ReactorUser

private struct ReactorUser: Identifiable {
    let id: String
    let profileImageURL: String?
    let isFollowedByCurrentUser: Bool
}

// MARK: - PostEngagementAvatarStrip

private struct PostEngagementAvatarStrip: View {
    let reactors: [ReactorUser]
    let reactorCount: Int
    let isVisible: Bool

    private let avatarSize: CGFloat = 26
    private let overlap: CGFloat = 8
    private let borderColor = Color(red: 0.05, green: 0.05, blue: 0.07)
    private let maxVisible = 4

    private var photoReactors: [ReactorUser] {
        reactors
            .filter { $0.profileImageURL != nil && !($0.profileImageURL!.isEmpty) }
            .prefix(maxVisible)
            .map { $0 }
    }

    private var hasFollowedReactor: Bool {
        reactors.contains { $0.isFollowedByCurrentUser }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Left: stacked avatars
            avatarStack

            // Right: labels
            VStack(alignment: .leading, spacing: 2) {
                Text("\(reactorCount) people reacted")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                if hasFollowedReactor {
                    Text("Including your followers")
                        .font(.systemScaled(10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Spacer()
        }
    }

    private var avatarStack: some View {
        let count = photoReactors.count
        let totalWidth = avatarSize + CGFloat(max(count - 1, 0)) * (avatarSize - overlap)

        return ZStack(alignment: .leading) {
            ForEach(Array(photoReactors.enumerated().reversed()), id: \.element.id) { index, reactor in
                avatarCircle(for: reactor, index: index)
                    .offset(x: CGFloat(index) * (avatarSize - overlap))
            }
        }
        .frame(width: totalWidth, height: avatarSize)
    }

    @ViewBuilder
    private func avatarCircle(for reactor: ReactorUser, index: Int) -> some View {
        let url = reactor.profileImageURL.flatMap { URL(string: $0) }

        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        } placeholder: {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: avatarSize, height: avatarSize)
        }
        .overlay(
            Circle()
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .frame(width: avatarSize, height: avatarSize)
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -8)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.7)
                .delay(0.1 + Double(index) * 0.08),
            value: isVisible
        )
    }
}

// MARK: - Scroll offset preference key (PostDetailView)

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - CGFloat clamping (PostDetailView)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - Liquid Glass button press style

private struct LiquidGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Comment Row View

struct CommentRowView: View {
    let comment: Comment
    let replies: [Comment]
    let postId: String
    var onReply: ((String) -> Void)? = nil  // called with the username to pre-fill @mention

    @State private var showReplies = false
    @State private var isDeleting = false

    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var isOwnComment: Bool { comment.authorId == currentUserId }
    // Use live replies array count as source of truth; fall back to stored replyCount
    private var replyCount: Int { replies.isEmpty ? comment.replyCount : replies.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainCommentRow
                .contentShape(Rectangle())  // makes full row tappable for context menu
                .contextMenu {
                    // Reply is in the context menu too for discoverability
                    Button {
                        onReply?(comment.authorUsername)
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }

                    if isOwnComment {
                        Divider()
                        Button(role: .destructive) {
                            deleteOwnComment()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        Divider()
                        Button {
                            reportComment()
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                    }
                }

            // Threaded replies with indent line
            if showReplies && !replies.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(replies, id: \.stableId) { reply in
                        replyRow(reply)
                            .contextMenu {
                                if reply.authorId == currentUserId {
                                    Button(role: .destructive) {
                                        deleteReply(reply)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else {
                                    Button { reportReply(reply) } label: {
                                        Label("Report", systemImage: "flag")
                                    }
                                }
                            }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showReplies)
            }
        }
        .opacity(isDeleting ? 0.4 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isDeleting)
    }

    // MARK: - Main Comment Row

    private var mainCommentRow: some View {
        HStack(alignment: .top, spacing: 12) {
            commentAvatar(imageURL: comment.authorProfileImageURL, initials: comment.authorInitials, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorUsername)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(timeAgo(from: comment.createdAt))
                        .font(.systemScaled(13))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                // Render @mentions in bold blue
                mentionStyledText(comment.content, fontSize: 15)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Action row: Reply + expand replies
                HStack(spacing: 20) {
                    Button {
                        onReply?(comment.authorUsername)
                    } label: {
                        Text("Reply")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if replyCount > 0 {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                showReplies.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showReplies ? "chevron.up" : "chevron.down")
                                    .font(.systemScaled(10, weight: .semibold))
                                Text(showReplies ? "Hide replies" : "\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                                    .font(.systemScaled(13, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Reply Row

    private func replyRow(_ reply: Comment) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread indent connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1.5)
            }
            .padding(.leading, 17.5) // centers under avatar (36/2 - 0.75)
            .frame(width: 36)

            HStack(alignment: .top, spacing: 12) {
                commentAvatar(imageURL: reply.authorProfileImageURL, initials: reply.authorInitials, size: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(reply.authorUsername)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(timeAgo(from: reply.createdAt))
                            .font(.systemScaled(12))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    mentionStyledText(reply.content, fontSize: 14)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    // Reply-to-reply button
                    Button {
                        onReply?(reply.authorUsername)
                    } label: {
                        Text("Reply")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
    }

    // MARK: - Mention-styled text

    /// Renders text with @mentions highlighted in blue bold.
    private func mentionStyledText(_ text: String, fontSize: CGFloat) -> Text {
        let nsAttr = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.label
            ]
        )
        // Find all @word tokens and style them
        let pattern = "@[\\w.]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                nsAttr.addAttributes([
                    .foregroundColor: UIColor.systemBlue,
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                ], range: match.range)
            }
        }
        return Text(AttributedString(nsAttr))
    }

    // MARK: - Avatar

    @ViewBuilder
    private func commentAvatar(imageURL: String?, initials: String, size: CGFloat) -> some View {
        if let url = imageURL.flatMap({ URL(string: $0) }), !(imageURL?.isEmpty ?? true) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Text(initials).font(.systemScaled(size * 0.33, weight: .semibold)).foregroundStyle(.white))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(initials).font(.systemScaled(size * 0.33, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }

    // MARK: - Actions

    private func deleteOwnComment() {
        guard let commentId = comment.id, !isDeleting else { return }
        isDeleting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                try await CommentService.shared.deleteComment(commentId: commentId, postId: postId)
            } catch {
                await MainActor.run { isDeleting = false }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                dlog("❌ Failed to delete comment: \(error)")
            }
        }
    }

    private func deleteReply(_ reply: Comment) {
        guard let replyId = reply.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                try await CommentService.shared.deleteComment(commentId: replyId, postId: postId)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                dlog("❌ Failed to delete reply: \(error)")
            }
        }
    }

    private func reportComment() {
        guard let commentId = comment.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                try await ModerationService.shared.reportComment(
                    commentId: commentId,
                    commentAuthorId: comment.authorId,
                    postId: postId,
                    reason: .inappropriateContent,
                    additionalDetails: nil
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                dlog("❌ Report failed: \(error)")
            }
        }
    }

    private func reportReply(_ reply: Comment) {
        guard let replyId = reply.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                try await ModerationService.shared.reportComment(
                    commentId: replyId,
                    commentAuthorId: reply.authorId,
                    postId: postId,
                    reason: .inappropriateContent,
                    additionalDetails: nil
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                dlog("❌ Report failed: \(error)")
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60    { return "now" }
        if interval < 3600  { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
