import SwiftUI
import AVKit
import FirebaseAuth

enum MediaSourceContext: String, Hashable {
    case feed
    case userProfile
    case profile
    case postDetail
    case notification
    case deepLink
}

struct AmenMediaDetailLoaderView: View {
    let postID: String
    let initialMediaIndex: Int
    let sourceContext: MediaSourceContext

    @Environment(\.dismiss) private var dismiss
    @State private var post: Post?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if let post {
                AmenMediaDetailView(
                    post: post,
                    initialMediaIndex: initialMediaIndex,
                    sourceContext: sourceContext
                )
            } else if isLoading {
                ProgressView()
                    .tint(.primary)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .semibold))
                    Text(errorMessage ?? "Unable to load this post.")
                        .font(AMENFont.semiBold(15))
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(14))
                }
                .foregroundStyle(.black.opacity(0.72))
                .padding(24)
            }
        }
        .task(id: postID) {
            await loadPost()
        }
    }

    @MainActor
    private func loadPost() async {
        isLoading = true
        errorMessage = nil
        do {
            post = try await FirebasePostService.shared.fetchPostById(postId: postID)
            if post == nil {
                errorMessage = "This post is no longer available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct AmenMediaDetailView: View {
    let post: Post
    let initialMediaIndex: Int
    let sourceContext: MediaSourceContext

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commentService = CommentService.shared
    @State private var selectedIndex: Int
    @State private var selectedTab: AmenMediaDetailTab = .comments
    @State private var composerText = ""
    @State private var isSending = false
    @State private var isCaptionExpanded = false
    @State private var showChrome = true
    @State private var showOverflowSheet = false
    @State private var activeContextSheet: AmenContextSheet?

    init(post: Post, initialMediaIndex: Int, sourceContext: MediaSourceContext) {
        self.post = post
        self.initialMediaIndex = initialMediaIndex
        self.sourceContext = sourceContext
        _selectedIndex = State(initialValue: initialMediaIndex)
    }

    private var postID: String { post.firestoreId }

    private var media: PostMediaContainer? {
        post.mediaContainer
    }

    private var mediaItems: [PostMediaItem] {
        media?.sortedItems ?? []
    }

    private var currentItem: PostMediaItem? {
        guard mediaItems.indices.contains(selectedIndex) else { return mediaItems.first }
        return mediaItems[selectedIndex]
    }

    private var commentsWithReplies: [CommentWithReplies] {
        let topLevel = commentService.comments[postID] ?? []
        return topLevel.map { comment in
            CommentWithReplies(
                comment: comment,
                replies: commentService.commentReplies[comment.id ?? ""] ?? []
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.972, green: 0.972, blue: 0.965)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 72)
                    heroSection
                    attachmentPills
                    tabBar
                    tabContent
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            header
            composerBar
        }
        .task(id: postID) {
            await startCommentTasks()
        }
        .onDisappear {
            commentService.stopListening(postId: postID)
        }
        .sheet(isPresented: $showOverflowSheet) {
            AmenMediaOverflowSheet(post: post)
                .presentationDetents([.medium])
        }
        .sheet(item: $activeContextSheet) { sheet in
            AmenContextSheetView(sheet: sheet)
                .presentationDetents([.medium, .large])
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.black)
                    Text("\(post.timeAgo) · \(sourceTitle)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.black.opacity(0.48))
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            if !mediaItems.isEmpty {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        AmenMediaSurface(
                            item: item,
                            contentMode: .fit,
                            cornerRadius: 28,
                            showsVideoBadge: true,
                            isHero: true
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: mediaItems.count > 1 ? .automatic : .never))
                .frame(height: heroHeight)
            }

            if let text = post.content.nilIfEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.black.opacity(0.78))
                        .lineSpacing(5)
                        .lineLimit(isCaptionExpanded ? nil : 3)

                    if text.count > 140 {
                        Button(isCaptionExpanded ? "Less" : "More") {
                            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.82))) {
                                isCaptionExpanded.toggle()
                            }
                        }
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .padding(14)
                .background(AmenGlassCard(cornerRadius: 22))
            }
        }
    }

    private var attachmentPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let verse = post.verseReference, !verse.isEmpty {
                    AmenContextPill(title: verse, systemImage: "sparkles") {
                        activeContextSheet = .verse(verse)
                    }
                }
                if post.churchNoteId != nil {
                    AmenContextPill(title: "Church Note", systemImage: "notebook") {
                        activeContextSheet = .churchNote(post.churchNoteId ?? "")
                    }
                }
                if post.isChurchShare, let churchName = post.sharedChurchName, !churchName.isEmpty {
                    AmenContextPill(title: "Find a Church", systemImage: "building.columns") {
                        activeContextSheet = .church(name: churchName, subtitle: post.sharedChurchAddress)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(AmenMediaDetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.82))) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title(commentCount: post.commentCount))
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(selectedTab == tab ? .black : .black.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .comments:
            AmenCommentThreadSection(comments: commentsWithReplies)
        case .context:
            VStack(spacing: 12) {
                AmenContextCard(
                    title: "Original post thread",
                    body: "Comments here read and write against the canonical post thread, so feed, profile, and detail stay in sync."
                )
                AmenContextCard(
                    title: "Source context",
                    body: "Opened from \(sourceTitle.lowercased()). Dismissal keeps the underlying profile or feed state intact because the detail is layered over the current surface."
                )
                AmenContextCard(
                    title: "Attached context",
                    body: contextSummary
                )
            }
        }
    }

    private var header: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label(sourceBackLabel, systemImage: "chevron.left")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AmenGlassCapsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                } label: {
                    Image(systemName: showChrome ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                        .frame(width: 40, height: 40)
                        .background(AmenGlassCapsule())
                }
                .buttonStyle(.plain)

                Button {
                    showOverflowSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                        .frame(width: 40, height: 40)
                        .background(AmenGlassCapsule())
                }
                .buttonStyle(.plain)
            }
            .opacity(showChrome ? 1 : 0.001)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()
        }
    }

    private var composerBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 0) {
                Divider()
                    .opacity(0.06)

                HStack(spacing: 10) {
                    TextField("Add a comment from the original post thread…", text: $composerText, axis: .vertical)
                        .font(AMENFont.regular(14))
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)

                    Button {
                        Task { await sendComment() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 42, height: 42)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(Color.black))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(.thinMaterial)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @MainActor
    private func startCommentTasks() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    _ = try await commentService.fetchCommentsWithReplies(for: postID)
                } catch {
                    dlog("❌ AmenMediaDetailView failed to fetch comments: \(error)")
                }
            }
            group.addTask {
                commentService.startListening(postId: postID)
            }
            group.addTask {
                await prefetchHeroMedia()
            }
        }
    }

    private func prefetchHeroMedia() async {
        guard let item = currentItem, let url = URL(string: item.thumbnailURL ?? item.url) else { return }
        _ = try? await URLSession.shared.data(from: url)
    }

    @MainActor
    private func sendComment() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        do {
            _ = try await commentService.addComment(
                postId: postID,
                content: trimmed,
                mentionedUserIds: nil,
                post: post
            )
            composerText = ""
        } catch {
            dlog("❌ AmenMediaDetailView failed to add comment: \(error)")
        }
    }

    private var heroHeight: CGFloat {
        let ratio = max(currentItem?.computedAspectRatio ?? 4.0 / 5.0, 0.65)
        let availableWidth = UIScreen.main.bounds.width - 32
        let calculated = availableWidth / ratio
        return min(max(calculated, 320), 520)
    }

    private var sourceBackLabel: String {
        switch sourceContext {
        case .feed: return "Feed"
        case .profile: return "Profile"
        case .userProfile: return "User Profile"
        case .postDetail: return "Post"
        case .notification: return "Notification"
        case .deepLink: return "Post"
        }
    }

    private var sourceTitle: String {
        switch sourceContext {
        case .feed: return "Feed"
        case .profile: return "Profile"
        case .userProfile: return "User Profile"
        case .postDetail: return "Post Detail"
        case .notification: return "Notification"
        case .deepLink: return "Deep Link"
        }
    }

    private var contextSummary: String {
        var parts: [String] = []
        if let verse = post.verseReference, !verse.isEmpty {
            parts.append("Verse \(verse)")
        }
        if post.churchNoteId != nil {
            parts.append("Church Note")
        }
        if post.isChurchShare, let churchName = post.sharedChurchName, !churchName.isEmpty {
            parts.append("Find a Church for \(churchName)")
        }
        return parts.isEmpty ? "No attached context." : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = post.authorProfileImageURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            CachedAsyncImage(url: url, size: CGSize(width: 44, height: 44)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.black.opacity(0.06))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.black)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(post.authorInitials)
                        .font(AMENFont.bold(14))
                        .foregroundStyle(.white)
                )
        }
    }
}

struct AmenMediaSurface: View {
    let item: PostMediaItem
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 22
    var showsVideoBadge: Bool = false
    var isHero: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            AmenMediaRenderableView(item: item, contentMode: contentMode)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                )

            if showsVideoBadge, item.type == .video {
                Label("Video", systemImage: "play.fill")
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.black.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AmenGlassCapsule())
                    .padding(12)
            }
        }
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(isHero ? 0.08 : 0.04), radius: isHero ? 18 : 8, y: isHero ? 8 : 4)
    }
}

private struct AmenMediaRenderableView: View {
    let item: PostMediaItem
    let contentMode: ContentMode

    var body: some View {
        Group {
            switch item.type {
            case .image:
                CachedAsyncImage(url: URL(string: item.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(item.computedAspectRatio, contentMode: contentMode)
                } placeholder: {
                    placeholder
                }
            case .video:
                AmenVideoPlayerSurface(item: item, contentMode: contentMode)
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.black.opacity(0.05))
            .overlay(ProgressView().tint(.black.opacity(0.45)))
    }
}

private struct AmenVideoPlayerSurface: View {
    let item: PostMediaItem
    let contentMode: ContentMode

    @StateObject private var model = AmenVideoPlayerModel()

    var body: some View {
        ZStack {
            if let player = model.player {
                VideoPlayer(player: player)
                    .aspectRatio(item.computedAspectRatio, contentMode: contentMode)
                    .overlay(alignment: .center) {
                        if !model.isPlaying {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 58)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .aspectRatio(item.computedAspectRatio, contentMode: contentMode)
                    .overlay(ProgressView().tint(.black.opacity(0.45)))
            }
        }
        .onTapGesture {
            model.toggle()
        }
        .task(id: item.id) {
            model.configure(urlString: item.url)
        }
        .onDisappear {
            model.pause()
        }
    }
}

private final class AmenVideoPlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false

    func configure(urlString: String) {
        guard player == nil, let url = URL(string: urlString) else { return }
        player = AVPlayer(url: url)
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }
}

private enum AmenMediaDetailTab: CaseIterable {
    case comments
    case context

    func title(commentCount: Int) -> String {
        switch self {
        case .comments: return "Comments (\(commentCount))"
        case .context: return "Context"
        }
    }
}

struct AmenCommentThreadSection: View {
    let comments: [CommentWithReplies]

    var body: some View {
        VStack(spacing: 12) {
            if comments.isEmpty {
                AmenContextCard(
                    title: "No comments yet",
                    body: "Start the conversation from the original post thread."
                )
            } else {
                ForEach(comments, id: \.comment.stableId) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        AmenCommentRow(comment: item.comment)
                        if !item.replies.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(item.replies, id: \.stableId) { reply in
                                    AmenCommentRow(comment: reply, isReply: true)
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
            }
        }
    }
}

struct AmenCommentRow: View {
    let comment: Comment
    var isReply = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(comment.authorUsername.isEmpty ? comment.authorName : comment.authorUsername)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.black)
                    Text(comment.timeAgo)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.black.opacity(0.45))
                }

                Text(comment.content)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.black.opacity(0.76))
                    .lineSpacing(4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AmenGlassCard(cornerRadius: 22))
        .padding(.leading, isReply ? 8 : 0)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = comment.authorProfileImageURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            CachedAsyncImage(url: url, size: CGSize(width: 34, height: 34)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.black.opacity(0.06))
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(comment.authorInitials)
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.black.opacity(0.7))
                )
        }
    }
}

private struct AmenContextCard: View {
    let title: String
    let body: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.black)
            Text(body)
                .font(AMENFont.regular(14))
                .foregroundStyle(.black.opacity(0.7))
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AmenGlassCard(cornerRadius: 24))
    }
}

private struct AmenContextPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AmenGlassCapsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AmenMediaOverflowSheet: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button("Share") {}
                Button("Save") {}
                Button("Copy Link") {}
                Button("Open Profile") {}
                Button("Report", role: .destructive) {}
            }
            .navigationTitle("Post Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum AmenContextSheet: Identifiable {
    case verse(String)
    case churchNote(String)
    case church(name: String, subtitle: String?)

    var id: String {
        switch self {
        case .verse(let value): return "verse-\(value)"
        case .churchNote(let id): return "note-\(id)"
        case .church(let name, _): return "church-\(name)"
        }
    }
}

private struct AmenContextSheetView: View {
    let sheet: AmenContextSheet

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.black)
                Text(message)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.black.opacity(0.72))
                    .lineSpacing(6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(Color(.systemBackground))
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch sheet {
        case .verse(let verse): return verse
        case .churchNote: return "Church Note"
        case .church(let name, _): return name
        }
    }

    private var message: String {
        switch sheet {
        case .verse(let verse):
            return "This post is carrying \(verse) as attached context."
        case .churchNote:
            return "This post includes a linked church note. The post thread stays canonical while the note remains a secondary surface."
        case .church(_, let subtitle):
            return subtitle ?? "This post includes a church discovery attachment."
        }
    }
}

private struct AmenGlassCapsule: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private struct AmenGlassCard: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
