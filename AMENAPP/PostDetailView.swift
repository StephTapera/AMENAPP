//
//  PostDetailView.swift
//  AMENAPP
//
//  Post detail: hero image/content fills ~half the screen, floating liquid-glass X
//  to dismiss, comments below, glassmorphic comment input bar at bottom.
//

import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

struct PostDetailView: View {
    let post: Post

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var commentService = CommentService.shared
    @ObservedObject private var commentFocusCoordinator = CommentFocusCoordinator.shared
    @ObservedObject private var userService = UserService.shared
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared

    @State private var isLoading = false
    @State private var commentText = ""
    @State private var isFollowInFlight = false
    @State private var expandedCommentClusters: Set<String> = []
    @State private var highlightedCommentIDs: Set<String> = []
    @State private var highlightResetTask: Task<Void, Never>?
    @FocusState private var isCommentFocused: Bool

    // CommentService uses the full firestoreId as the Realtime Database key.
    // Truncating to prefix(8) produces a path that doesn't exist, resulting in empty comments.
    private var postId: String { post.firestoreId }

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
    @State private var replyingToUsername: String? = nil  // Set when Reply is tapped
    @State private var rateLimitMessage: String? = nil   // Auto-dismissing rate limit notice
    @State private var rateLimitDismissTask: Task<Void, Never>? = nil
    @State private var showCommentsLoadError = false      // P2 FIX: surface loadComments failure
    @State private var scrollOffset: CGFloat = 0
    @State private var carouselPage: Int = 0               // Active slide in media carousel

    // Testimony features — only active when post.category == .testimonies
    @StateObject private var witnessService = TestimonyWitnessService()
    @StateObject private var strengthService = TestimonyStrengthService()
    @State private var showRipple = false
    @State private var showAnsweredComposer = false
    @State private var linkedTestimonyPost: Post? = nil
    
    // Prayer features — fasting chain
    @State private var isFasting = false

    // Scroll-driven sheet expansion (0 = compact hero visible, 1 = full-screen sheet)


    // Single sheet enum — avoids "only presenting a single sheet" SwiftUI warning
    private enum DetailSheet: Identifiable {
        case berean(String), share, profile, report, editPost
        var id: String {
            switch self {
            case .berean:    return "berean"
            case .share:     return "share"
            case .profile:   return "profile"
            case .report:    return "report"
            case .editPost:  return "editPost"
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
        VStack(spacing: 0) {
            // ── Top nav bar ─────────────────────────────────────────
            topNavBar

            ScrollView(.vertical, showsIndicators: false) {

                VStack(spacing: 0) {
                    // ── Media carousel or compact category banner ────────
                    if !allImageURLs.isEmpty {
                        mediaCarousel
                    } else {
                        textOnlyBanner
                    }

                    // ── Full post text (expanded by default in detail view) ──
                    VStack(alignment: .leading, spacing: 10) {
                        Text(post.content)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                            .lineLimit(isPostExpanded ? nil : 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPostExpanded)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Show collapse option only for long posts
                        if !isPostExpanded {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isPostExpanded = true
                                }
                            } label: {
                                Text("Read more")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        // Topic tag
                        if let topicTag = post.topicTag, !topicTag.isEmpty {
                            Text("#\(topicTag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                    Divider()

                    // ── Engagement bar ──────────────────────────────────────
                    engagementBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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
        }
        .background(Color(.systemBackground).ignoresSafeArea())
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
            }
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
        }
        .onDisappear {
            highlightResetTask?.cancel()
            highlightResetTask = nil
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
        }
        // commentsWithReplies is now a computed property derived from @Published
        // CommentService state, so no notification handlers are needed here.
        // SwiftUI automatically re-renders when commentService.comments changes.
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
                    .overlay(Text(post.authorInitials).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        } else {
            Circle()
                .fill(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(post.authorInitials).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
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
                        .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let tag = post.topicTag, !tag.isEmpty {
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timeAgo(from: post.createdAt))
                                .font(.system(size: 11))
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
                                            .font(.system(size: 32, weight: .light))
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
                .font(.system(size: 26, weight: .light))
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
                        .font(.system(size: 17))
                        .foregroundStyle(interactionsService.userAmenedPosts.contains(post.firestoreId) ? Color.orange : .secondary)
                    if post.amenCount > 0 {
                        Text("\(post.amenCount)")
                            .font(.system(size: 14, weight: .medium))
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
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    if !commentsWithReplies.isEmpty {
                        Text("\(commentsWithReplies.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Join Fast button - only for prayer request posts
            if post.category == .prayer, post.topicTag == "Prayer Request" {
                Button {
                    toggleFasting()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isFasting ? "flame.fill" : "flame")
                            .font(.system(size: 17))
                            .foregroundStyle(isFasting ? Color.orange : .secondary)
                        if isFasting {
                            Text("Fasting")
                                .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 17))
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
                        postsManager.deletePost(postId: post.id)
                        dismiss()
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
                        Task {
                            try? await BlockService.shared.blockUser(userId: post.authorId)
                            dismiss()
                        }
                    } label: {
                        Label("Block \(post.authorName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17))
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
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var commentsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(commentsWithReplies.count)")
                    .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("0")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("No comments yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    isCommentFocused = true
                } label: {
                    Text("Be the first to comment")
                        .font(.system(size: 14))
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
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Could not load comments")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                Task { await loadComments() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 14))
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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Comment Input Bar (ThreadComposerView)

    private var commentInputBar: some View {
        ThreadComposerView(
            text: $commentText,
            replyingToUsername: $replyingToUsername,
            isFocused: $isCommentFocused,
            onSubmit: { submitComment() },
            onBerean: { query in activeDetailSheet = .berean(query) }
        )
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
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
        let db = Firestore.firestore()
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                if hasFollowedReactor {
                    Text("Including your followers")
                        .font(.system(size: 10))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(timeAgo(from: comment.createdAt))
                        .font(.system(size: 13))
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if replyCount > 0 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showReplies.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showReplies ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(showReplies ? "Hide replies" : "\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                                    .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(timeAgo(from: reply.createdAt))
                            .font(.system(size: 12))
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
                            .font(.system(size: 12, weight: .medium))
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
                    .overlay(Text(initials).font(.system(size: size * 0.33, weight: .semibold)).foregroundStyle(.white))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(initials).font(.system(size: size * 0.33, weight: .semibold)).foregroundStyle(.white))
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
