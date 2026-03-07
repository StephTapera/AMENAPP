//
//  PostDetailView.swift
//  AMENAPP
//
//  Post detail: hero image/content fills ~half the screen, floating liquid-glass X
//  to dismiss, comments below, glassmorphic comment input bar at bottom.
//

import SwiftUI
import FirebaseAuth

struct PostDetailView: View {
    let post: Post

    @Environment(\.dismiss) var dismiss
    @ObservedObject private var commentService = CommentService.shared
    @ObservedObject private var userService = UserService.shared
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared

    @State private var isLoading = false
    @State private var commentText = ""
    @State private var isFollowInFlight = false
    @FocusState private var isCommentFocused: Bool

    // CommentService uses the short (8-char prefix) ID format in Realtime Database
    private var postId: String { String(post.firestoreId.prefix(8)) }

    // Derived from @Published CommentService state — no local copy, no concurrent mutation.
    // SwiftUI re-renders automatically whenever commentService.comments or commentReplies changes.
    private var commentsWithReplies: [CommentWithReplies] {
        let topLevel = commentService.comments[postId] ?? []
        return topLevel.map { comment in
            let replies = commentService.commentReplies[comment.id ?? ""] ?? []
            return CommentWithReplies(comment: comment, replies: replies)
        }
    }

    @State private var isListening = false
    @State private var pollingTask: Task<Void, Never>?
    @State private var isGuardrailBlocked = false
    @State private var isSubmittingComment = false  // debounce: prevent double-submit
    @State private var isPostExpanded = true         // Default expanded in detail view
    @State private var replyingToUsername: String? = nil  // Set when Reply is tapped
    @State private var rateLimitMessage: String? = nil   // Auto-dismissing rate limit notice
    @State private var rateLimitDismissTask: Task<Void, Never>? = nil

    // Scroll-driven sheet expansion (0 = compact hero visible, 1 = full-screen sheet)


    // Single sheet enum — avoids "only presenting a single sheet" SwiftUI warning
    private enum DetailSheet: Identifiable {
        case berean(String), share, profile
        var id: String {
            switch self {
            case .berean:   return "berean"
            case .share:    return "share"
            case .profile:  return "profile"
            }
        }
    }
    @State private var activeDetailSheet: DetailSheet?

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Hero — image posts taller, text-only posts compact ───
                    GeometryReader { geo in
                        heroSection
                            .frame(width: geo.size.width,
                                   height: hasMedia ? geo.size.width * 0.72 : 160)
                            .clipped()
                    }
                    .frame(height: hasMedia ? 300 : 160)
                    .overlay(alignment: .topLeading) {
                        // ── Floating dismiss button — sits just below status bar
                        Button { dismiss() } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .padding(.leading, 16)
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    Divider()

                    // ── Comments ────────────────────────────────────────────
                    if isLoading {
                        loadingView
                    } else if commentsWithReplies.isEmpty {
                        emptyCommentsView
                    } else {
                        commentsSection
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                commentInputBar
            }
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
            }
        }
        .task {
            await loadComments()
            if !isListening {
                commentService.startListening(to: postId)
                isListening = true
            }
        }
        .onDisappear {
            if isListening {
                commentService.stopListening(to: postId)
                pollingTask?.cancel()
                pollingTask = nil
                isListening = false
            }
        }
        // commentsWithReplies is now a computed property derived from @Published
        // CommentService state, so no notification handlers are needed here.
        // SwiftUI automatically re-renders when commentService.comments changes.
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Background — image if available, else category-tinted gradient
            if let url = heroImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .empty:
                        postGradientBackground
                            .overlay(ProgressView().tint(.white))
                    case .failure:
                        // Image URL exists but failed to load — show gradient + icon
                        postGradientBackground
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.white.opacity(0.4))
                            )
                    @unknown default:
                        postGradientBackground
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                // Text-only post: category-tinted gradient with subtle pattern
                postGradientBackground
            }

            // Scrim gradient so text is readable over any background
            LinearGradient(
                colors: [.clear, .black.opacity(hasMedia ? 0.72 : 0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Post metadata pinned to bottom of hero
            heroMetadata
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    private var heroMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row
            HStack(spacing: 10) {
                Button {
                    activeDetailSheet = .profile
                } label: {
                    authorAvatar
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Button {
                    activeDetailSheet = .profile
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorUsername ?? post.authorName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(timeAgo(from: post.createdAt))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Follow button (if not own post)
                if !isUserPost {
                    followButton
                }
            }

            // Topic tag only — post text shown once in the main content area below
            if let topicTag = post.topicTag, !topicTag.isEmpty {
                Text("#\(topicTag)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(.ultraThinMaterial.opacity(0.6))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
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

    private var followButton: some View {
        Button {
            handleFollowTap()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isFollowing ? .white.opacity(0.8) : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isFollowing ? Color.white.opacity(0.2) : Color.white)
            )
            .opacity(isFollowInFlight ? 0.6 : 1.0)
        }
        .disabled(isFollowInFlight)
        .buttonStyle(.plain)
    }

    // MARK: - Expanding Comments Sheet

    /// Scroll- and drag-driven sheet that expands from ~52% to full screen.
    @ViewBuilder


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

            Spacer()

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

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading comments…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Comment Input Bar

    private var commentInputBar: some View {
        VStack(spacing: 0) {
            // "Replying to @username" banner
            if let replyUsername = replyingToUsername {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Replying to **@\(replyUsername)**")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        replyingToUsername = nil
                        // Strip the @mention prefix if user hasn't typed anything extra
                        if commentText == "@\(replyUsername) " { commentText = "" }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }

            // Rate limit notice — slides in above input, auto-dismisses after 4s
            if let msg = rateLimitMessage {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Top hairline separator
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                // User avatar
                Group {
                    if let imageURL = userService.currentUser?.profileImageURL,
                       !imageURL.isEmpty,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Text(userService.currentUser?.initials ?? "U")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            )
                    }
                }
                .frame(width: 32, height: 32)

                // Text field pill background
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $commentText, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...4)
                        .focused($isCommentFocused)
                        .submitLabel(.send)
                        .onSubmit { submitComment() }
                        .contentGuardrail(text: $commentText, context: .comment) { _ in
                            isGuardrailBlocked = true
                        }
                        .onChange(of: commentText) { _, _ in
                            isGuardrailBlocked = false
                        }

                    // Send button — visible only when there is text
                    if !commentText.isEmpty {
                        Button { submitComment() } label: {
                            if isSubmittingComment {
                                ProgressView()
                                    .frame(width: 26, height: 26)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(isGuardrailBlocked ? Color.secondary : Color.blue)
                            }
                        }
                        .disabled(isGuardrailBlocked || isSubmittingComment)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
    }



    // MARK: - Helpers

    private func loadComments() async {
        isLoading = true
        do {
            // fetchCommentsWithReplies populates commentService.comments[postId]
            // and commentService.commentReplies — commentsWithReplies (computed) updates automatically.
            _ = try await commentService.fetchCommentsWithReplies(for: postId)
        } catch {
            print("❌ Failed to load comments: \(error)")
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
            } catch {
                print("❌ Failed to post comment: \(error)")
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
                print("❌ Follow error: \(error.localizedDescription)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isFollowInFlight = false
        }
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
                print("❌ Failed to delete comment: \(error)")
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
                print("❌ Failed to delete reply: \(error)")
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
                print("❌ Report failed: \(error)")
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
                print("❌ Report failed: \(error)")
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
