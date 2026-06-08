import SwiftUI
import FirebaseAuth

// MARK: - Emoji Picker View

struct EmojiPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var commentText: String
    
    private let emojis = [
        "😊", "😂", "❤️", "🙏", "🔥", "✨", "🎉", "👏",
        "🙌", "💪", "⭐️", "💯", "✅", "🎯", "💡", "📖",
        "🕊️", "✝️", "🌟", "💖", "🌈", "☀️", "🌸", "🦋",
        "🎵", "📿", "⛪️", "🙇", "💫", "🌺", "🌻", "🌷"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8), spacing: 12) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            commentText += emoji
                            HapticManager.impact(style: .light)
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.systemScaled(32))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                        .accessibilityLabel(emoji)
                    }
                }
                .padding()
            }
            .navigationTitle("Add Emoji")
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

// MARK: - Comment Card

struct CommentCard: View {
    let comment: TestimonyComment
    let postId: String
    var onReply: ((TestimonyComment) -> Void)?
    @State private var hasAmened = false
    @State private var localAmenCount: Int
    @State private var isSubmittingAmen = false

    init(comment: TestimonyComment, postId: String, onReply: ((TestimonyComment) -> Void)? = nil) {
        self.comment = comment
        self.postId = postId
        self.onReply = onReply
        _localAmenCount = State(initialValue: comment.amenCount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(comment.avatarColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(comment.authorInitials)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(comment.avatarColor)
                )

            VStack(alignment: .leading, spacing: 6) {
                // Author and time
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)

                    Text("•")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)

                    Text(comment.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                // Comment content
                Text(comment.content)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Comment actions
                HStack(spacing: 16) {
                    Button {
                        guard !isSubmittingAmen else { return }
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                            hasAmened.toggle()
                            localAmenCount += hasAmened ? 1 : -1
                            HapticManager.impact(style: .light)
                        }
                        // Persist amen to RTDB — comment-level if commentId is available
                        isSubmittingAmen = true
                        Task {
                            defer { isSubmittingAmen = false }
                            guard !postId.isEmpty else { return }
                            // comment-level amen not yet supported server-side
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.systemScaled(11))
                            if localAmenCount > 0 {
                                Text("\(localAmenCount)")
                                    .font(AMENFont.semiBold(12))
                            }
                        }
                        .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                    }
                    .accessibilityLabel(hasAmened ? "Remove amen" : "Amen")

                    Button {
                        HapticManager.impact(style: .light)
                        onReply?(comment)
                    } label: {
                        Text("Reply")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Testimony Comment Model

struct TestimonyComment: Identifiable {
    let id = UUID()
    /// RTDB comment key — used to persist comment-level amen to the correct path.
    var commentId: String?
    let authorName: String
    let authorInitials: String
    let timeAgo: String
    let content: String
    let amenCount: Int
    let avatarColor: Color
    var replies: [TestimonyComment] = []
    var gifURL: String?
    /// Legacy combined flag — kept for compatibility. Prefer isBold/isItalic.
    var isFormatted: Bool = false
    var isBold: Bool = false
    var isItalic: Bool = false
}

// MARK: - Full Comments View

struct FullCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    let postId: String
    let comments: [TestimonyComment]
    /// Thread category written to the `user_comments` index and comment body.
    /// Pass "prayer", "verse_discussion", "church_note", or "berean" as appropriate.
    let threadCategory: String

    @State private var allComments: [TestimonyComment]
    @State private var commentText = ""
    @State private var replyingTo: TestimonyComment?
    @State private var showGIFPicker = false
    @State private var showEmojiPicker = false
    @State private var selectedGIF: String?
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isSubmittingComment = false
    /// True while waiting for the first RTDB snapshot; hides empty state flicker.
    @State private var isLoadingComments = false
    @FocusState private var isCommentFocused: Bool

    init(postId: String, comments: [TestimonyComment], threadCategory: String = "post") {
        self.postId = postId
        self.comments = comments
        self.threadCategory = threadCategory
        _allComments = State(initialValue: comments)
        // Only show loading skeleton when caller passed no seed comments.
        _isLoadingComments = State(initialValue: comments.isEmpty)
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Comments List
                Group {
                    if isLoadingComments {
                        VStack {
                            Spacer()
                            ProgressView()
                                .frame(maxWidth: .infinity)
                            Spacer()
                        }
                    } else if allComments.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.systemScaled(36))
                                .foregroundStyle(.secondary)
                            Text("No comments yet")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.secondary)
                            Text("Be the first to share your thoughts.")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(allComments) { comment in
                                    CommentThreadCard(
                                        comment: comment,
                                        postId: postId,
                                        onReply: { replyTo in
                                            replyingTo = replyTo
                                            isCommentFocused = true
                                        },
                                        onAddReply: { parent, reply in
                                            addReply(to: parent, reply: reply)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composerView
                }
            }
        }
        // Start RTDB comment listener when the sheet opens so live comments from
        // other users appear without a pull-to-refresh. The observer is LRU-capped
        // inside PostInteractionsService so opening this sheet is safe.
        .task {
            PostInteractionsService.shared.observePostInteractions(postId: postId)
            // Safety timeout: clear the loading spinner after 4 s even if RTDB is slow,
            // so the empty state (or seed comments) is shown rather than a stuck spinner.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if isLoadingComments {
                isLoadingComments = false
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .accessibilityLabel("Close comments")
                
                Spacer()
                
                Text("Comments")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Placeholder for symmetry
                Circle()
                    .fill(Color.clear)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Composer (Liquid Glass Style)
    
    private var composerView: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            
            VStack(spacing: 12) {
                // Reply indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.authorName)")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                self.replyingTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Liquid Glass Input Container
                HStack(alignment: .center, spacing: 12) {
                    // Avatar
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text("ME")
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.white)
                        )
                    
                    // Glass-style text field
                    HStack(spacing: 8) {
                        TextField("Add a comment...", text: $commentText, axis: .vertical)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.primary)
                            .lineLimit(1...4)
                            .focused($isCommentFocused)
                            .padding(.leading, 16)
                            .padding(.trailing, 8)
                            .padding(.vertical, 12)
                        
                        // Photo/GIF button inside text field
                        if isCommentFocused && commentText.isEmpty {
                            Button {
                                showGIFPicker.toggle()
                                isCommentFocused = false
                            } label: {
                                Image(systemName: "photo")
                                    .font(.systemScaled(18))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            // Glass effect background
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                            
                            // Subtle border
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
                    
                    // Animated Liquid Glass Post Button
                    if !commentText.isEmpty {
                        LiquidGlassPostButton(
                            isEnabled: !commentText.isEmpty,
                            isPublishing: false,
                            isScheduled: false
                        ) {
                            submitComment()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Minimal formatting toolbar (only when focused and typing)
                if isCommentFocused && !commentText.isEmpty {
                    minimalToolbarView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(
            ZStack {
                Color(.systemBackground)
                
                // Subtle top shadow for depth
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        )
        .sheet(isPresented: $showGIFPicker) {
            GIFPickerView(selectedGIF: $selectedGIF)
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(commentText: $commentText)
        }
        // Live RTDB updates: when PostInteractionsService fires new comments for this
        // post, replace allComments from the authoritative backend data so new
        // comments from other users appear while the sheet is open.
        .onReceive(PostInteractionsService.shared.$postCommentsData) { commentMap in
            // Always clear loading once the first RTDB snapshot arrives (even if empty)
            if isLoadingComments, commentMap[postId] != nil {
                isLoadingComments = false
            }
            guard let rtdbComments = commentMap[postId], !rtdbComments.isEmpty else { return }
            let updated: [TestimonyComment] = rtdbComments.compactMap { rc in
                let elapsed = Date().timeIntervalSince(rc.timestamp)
                let timeAgo: String
                switch elapsed {
                case ..<60:          timeAgo = "Just now"
                case ..<3600:        timeAgo = "\(Int(elapsed / 60))m"
                case ..<86400:       timeAgo = "\(Int(elapsed / 3600))h"
                default:             timeAgo = "\(Int(elapsed / 86400))d"
                }
                var tc = TestimonyComment(
                    authorName: rc.authorName,
                    authorInitials: rc.authorInitials,
                    timeAgo: timeAgo,
                    content: rc.content,
                    amenCount: rc.likes,
                    avatarColor: .blue,
                    replies: []
                )
                tc.commentId = rc.id
                return tc
            }
            allComments = updated
        }
    }
    
    // MARK: - Minimal Toolbar
    
    private var minimalToolbarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Bold
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                        isBold.toggle()
                    }
                } label: {
                    Text("B")
                        .font(AMENFont.bold(14))
                        .foregroundStyle(isBold ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                        )
                }
                
                // Italic
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                        isItalic.toggle()
                    }
                } label: {
                    Text("I")
                        .font(.custom("OpenSans-Italic", size: 14))
                        .foregroundStyle(isItalic ? .white : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isItalic ? Color.black : Color.gray.opacity(0.1))
                        )
                }
                
                Divider()
                    .frame(height: 24)
                
                // Emoji
                Button {
                    isCommentFocused = false
                    showEmojiPicker = true
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Style Toolbar (Kept for compatibility but simplified)
    
    private var styleToolbarView: some View {
        HStack(spacing: 8) {
            // Bold
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                    isBold.toggle()
                }
            } label: {
                Text("B")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(isBold ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isBold ? Color.black : Color.gray.opacity(0.1))
                    )
            }
            
            // Italic
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                    isItalic.toggle()
                }
            } label: {
                Text("I")
                    .font(.custom("OpenSans-Italic", size: 14))
                    .foregroundStyle(isItalic ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isItalic ? Color.black : Color.gray.opacity(0.1))
                    )
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Actions

    private func submitComment() {
        guard !commentText.isEmpty, !isSubmittingComment else { return }
        isSubmittingComment = true

        let capturedText = commentText
        let capturedGIF = selectedGIF
        let capturedReplyingTo = replyingTo
        let capturedBold = isBold
        let capturedItalic = isItalic

        // Optimistic UI update
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
            var newComment = TestimonyComment(
                authorName: "You",
                authorInitials: Auth.auth().currentUser?.displayName.map {
                    String($0.prefix(1).uppercased())
                } ?? "ME",
                timeAgo: "Just now",
                content: capturedText,
                amenCount: 0,
                avatarColor: .blue,
                replies: [],
                gifURL: capturedGIF,
                isFormatted: capturedBold || capturedItalic
            )
            newComment.isBold = capturedBold
            newComment.isItalic = capturedItalic

            if let replyingTo = capturedReplyingTo {
                addReply(to: replyingTo, reply: newComment)
            } else {
                allComments.insert(newComment, at: 0)
            }

            commentText = ""
            selectedGIF = nil
            self.replyingTo = nil
            isCommentFocused = false
            HapticManager.notification(type: .success)
        }

        // Backend persistence
        Task {
            defer { isSubmittingComment = false }
            guard !postId.isEmpty else { return }
            let username = Auth.auth().currentUser?.displayName ?? "User"
            let initials = String(username.prefix(1).uppercased())
            _ = try? await PostInteractionsService.shared.addComment(
                postId: postId,
                content: capturedText,
                authorInitials: initials,
                authorUsername: username
            )
        }
    }
    
    private func addReply(to parent: TestimonyComment, reply: TestimonyComment) {
        if let index = allComments.firstIndex(where: { $0.id == parent.id }) {
            allComments[index].replies.append(reply)
        }
    }
}

// MARK: - Comment Thread Card

struct CommentThreadCard: View {
    let comment: TestimonyComment
    let postId: String
    let onReply: (TestimonyComment) -> Void
    let onAddReply: (TestimonyComment, TestimonyComment) -> Void

    @State private var hasAmened = false
    @State private var localAmenCount: Int
    @State private var showReplies = true
    @State private var isSubmittingAmen = false

    init(comment: TestimonyComment, postId: String, onReply: @escaping (TestimonyComment) -> Void, onAddReply: @escaping (TestimonyComment, TestimonyComment) -> Void) {
        self.comment = comment
        self.postId = postId
        self.onReply = onReply
        self.onAddReply = onAddReply
        _localAmenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main comment
            commentContentView(for: comment, isReply: false)
            
            // Replies
            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                            showReplies.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showReplies ? "chevron.down" : "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                            Text("\(comment.replies.count) \(comment.replies.count == 1 ? "reply" : "replies")")
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 48)
                        .padding(.vertical, 8)
                    }
                    
                    if showReplies {
                        ForEach(comment.replies) { reply in
                            commentContentView(for: reply, isReply: true)
                                .padding(.leading, 48)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func commentContentView(for comment: TestimonyComment, isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                Circle()
                    .fill(comment.avatarColor.opacity(0.2))
                    .frame(width: isReply ? 32 : 40, height: isReply ? 32 : 40)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 11 : 13))
                            .foregroundStyle(comment.avatarColor)
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 6) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                            .foregroundStyle(.primary)
                        
                        Text("•")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                        
                        Text(comment.timeAgo)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Content — font reflects the bold/italic flags set at compose time
                    let fontSize: CGFloat = isReply ? 13 : 14
                    let contentFont: Font = {
                        switch (comment.isBold, comment.isItalic) {
                        case (true, true):
                            return .custom("OpenSans-BoldItalic", size: fontSize)
                        case (true, false):
                            return .custom("OpenSans-Bold", size: fontSize)
                        case (false, true):
                            return .custom("OpenSans-Italic", size: fontSize)
                        default:
                            return .custom("OpenSans-Regular", size: fontSize)
                        }
                    }()
                    Text(comment.content)
                        .font(contentFont)
                        .foregroundStyle(.primary)
                    
                    // GIF if present
                    if let gifURL = comment.gifURL {
                        CachedAsyncImage(url: URL(string: gifURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 150)
                        }
                    }
                    
                    // Actions
                    HStack(spacing: 20) {
                        Button {
                            guard !isSubmittingAmen else { return }
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                                hasAmened.toggle()
                                localAmenCount += hasAmened ? 1 : -1
                                HapticManager.impact(style: .light)
                            }
                            isSubmittingAmen = true
                            Task {
                                defer { isSubmittingAmen = false }
                                guard !postId.isEmpty else { return }
                                // comment-level amen not yet supported server-side
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hands.sparkles.fill")
                                    .font(.systemScaled(13))
                                if localAmenCount > 0 {
                                    Text("\(localAmenCount)")
                                        .font(AMENFont.semiBold(13))
                                }
                            }
                            .foregroundStyle(hasAmened ? Color(red: 1.0, green: 0.84, blue: 0.0) : .secondary)
                        }

                        Button {
                            onReply(comment)
                            HapticManager.impact(style: .light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.systemScaled(12))
                                Text("Reply")
                                    .font(AMENFont.semiBold(13))
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        Menu {
                            Button(role: .destructive) {
                                // Report action
                            } label: {
                                Label("Report", systemImage: "exclamationmark.triangle")
                            }
                            
                            ShareLink(item: comment.content) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
        }
        .padding(isReply ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - GIF Picker View

struct GIFPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedGIF: String?
    
    @State private var searchText = ""
    
    // Sample GIF URLs (in production, you'd use a GIF API like Giphy or Tenor)
    private let sampleGIFs = [
        "https://media.giphy.com/media/26u4cqiYI30juCOGY/giphy.gif",
        "https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif",
        "https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif",
        "https://media.giphy.com/media/26FLgGTPUDH6UGAbm/giphy.gif",
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search GIFs", text: $searchText)
                        .font(AMENFont.regular(16))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // GIF Grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        ForEach(sampleGIFs, id: \.self) { gifURL in
                            Button {
                                selectedGIF = gifURL
                                dismiss()
                                
                                HapticManager.impact(style: .light)
                            } label: {
                                CachedAsyncImage(url: URL(string: gifURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 150)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Choose GIF")
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
}
