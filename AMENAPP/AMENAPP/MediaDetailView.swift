//
//  MediaDetailView.swift
//  AMENAPP
//
//  Media-first post detail view.
//  Opens focused on the selected image/video with swipe navigation.
//  Provides access to author, caption, verse, engagement, and
//  a "View full post" action to jump to the original post detail.
//  Liquid Glass design system.
//

import SwiftUI

struct MediaDetailView: View {
    let item: EnrichedMediaGridItem
    var onViewFullPost: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int
    @State private var showChrome = true
    @State private var dragDismissOffset: CGFloat = 0
    @State private var showFullCaption = false

    // MARK: - Engagement Rail State
    @ObservedObject private var interactions = PostInteractionsService.shared
    @State private var isLiked = false
    @State private var amenCount = 0
    @State private var commentCount = 0
    @State private var shareCount = 0
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var fetchedPost: Post? = nil

    init(item: EnrichedMediaGridItem, onViewFullPost: ((String) -> Void)? = nil) {
        self.item = item
        self.onViewFullPost = onViewFullPost
        _currentIndex = State(initialValue: item.indexInPost)
    }

    private var dismissOpacity: Double {
        let progress = abs(dragDismissOffset) / 220.0
        return Double(max(0, 1.0 - progress))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(dismissOpacity)
                .ignoresSafeArea()

            mediaPager
                .offset(y: dragDismissOffset)
                .gesture(dismissDragGesture)
                .onTapGesture { toggleChrome() }

            if showChrome {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomPanel
                }
                .transition(.opacity)

                engagementRail
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear { seedEngagementCounts() }
        .onChange(of: interactions.postAmens[item.postId]) { newVal in
            amenCount = newVal ?? amenCount
        }
        .onChange(of: interactions.postComments[item.postId]) { newVal in
            commentCount = newVal ?? commentCount
        }
        .onChange(of: interactions.postReposts[item.postId]) { newVal in
            shareCount = newVal ?? shareCount
        }
        .onChange(of: interactions.userAmenedPosts) { newSet in
            isLiked = newSet.contains(item.postId)
        }
        .sheet(isPresented: $showComments) {
            if let post = fetchedPost {
                CommentsView(post: post)
            } else {
                // Navigate to full post while we don't have the Post object yet
                ProgressView("Loading...")
                    .onAppear { fetchPost() }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [buildShareText()])
        }
    }

    // MARK: - Engagement Rail

    private var engagementRail: some View {
        VStack(spacing: 20) {
            Spacer()

            // Amen / Like
            VStack(spacing: 4) {
                Button {
                    Task { await toggleAmen() }
                } label: {
                    Image(systemName: isLiked ? "hands.clap.fill" : "hands.clap")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isLiked ? Color(red: 0.85, green: 0.65, blue: 0.13) : Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .accessibilityLabel(isLiked ? "Remove Amen" : "Amen")
                Text(formatCount(amenCount))
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }

            // Comments
            VStack(spacing: 4) {
                Button { showComments = true } label: {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .accessibilityLabel("Comments")
                Text(formatCount(commentCount))
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }

            // Share
            VStack(spacing: 4) {
                Button { showShareSheet = true } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .accessibilityLabel("Share")
                Text(formatCount(shareCount))
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .padding(.bottom, 80) // clear the bottom panel
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .colorScheme(.dark)
    }

    // MARK: - Engagement Helpers

    private func seedEngagementCounts() {
        let svc = PostInteractionsService.shared
        amenCount = svc.postAmens[item.postId] ?? 0
        commentCount = svc.postComments[item.postId] ?? 0
        shareCount = svc.postReposts[item.postId] ?? 0
        isLiked = svc.userAmenedPosts.contains(item.postId)
        svc.observePostInteractions(postId: item.postId)
        fetchPost()
    }

    private func fetchPost() {
        guard fetchedPost == nil else { return }
        Task {
            let post = try? await FirebasePostService.shared.fetchPostById(postId: item.postId)
            await MainActor.run { self.fetchedPost = post }
        }
    }

    private func toggleAmen() async {
        // Optimistic update
        isLiked.toggle()
        if isLiked {
            amenCount += 1
        } else {
            amenCount = max(0, amenCount - 1)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await PostInteractionsService.shared.toggleAmen(postId: item.postId)
        } catch {
            // Revert on failure
            isLiked.toggle()
            if isLiked {
                amenCount += 1
            } else {
                amenCount = max(0, amenCount - 1)
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000.0)
        case 1_000...: return String(format: "%.1fK", Double(n) / 1_000.0)
        default: return n > 0 ? "\(n)" : ""
        }
    }

    private func buildShareText() -> String {
        var text = item.postContent
        if let verse = item.verseReference, !verse.isEmpty {
            text += "\n\n\(verse)"
        }
        if let author = item.authorName {
            text += "\n\n— \(author)"
        }
        text += "\n\nShared from AMEN App"
        return text
    }

    // MARK: - Media Pager

    @ViewBuilder
    private var mediaPager: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(item.allImageURLs.enumerated()), id: \.offset) { index, url in
                mediaPage(url: url)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: item.isCarousel ? .automatic : .never))
    }

    @ViewBuilder
    private func mediaPage(url: String) -> some View {
        CachedAsyncImage(
            url: URL(string: url),
            size: CGSize(width: 800, height: 800)
        ) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            ProgressView()
                .tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                authorAvatar
                VStack(alignment: .leading, spacing: 1) {
                    if let name = item.authorName {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(item.postTimestamp)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let urlString = item.authorProfileImageURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, size: CGSize(width: 64, height: 64)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle().fill(Color.white.opacity(0.2))
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String((item.authorName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            captionSection

            if let verse = item.verseReference, !verse.isEmpty {
                versePill(verse)
            }

            HStack {
                if item.isCarousel {
                    Text("\(currentIndex + 1) of \(item.carouselCount)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                if onViewFullPost != nil {
                    Button {
                        onViewFullPost?(item.postId)
                    } label: {
                        HStack(spacing: 4) {
                            Text("View post")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                    }
                    .accessibilityLabel("View full post")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var captionSection: some View {
        if !item.postContent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.postContent)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(showFullCaption ? nil : 2)
                    .onTapGesture { showFullCaption.toggle() }

                if item.postContent.count > 100 && !showFullCaption {
                    Text("more")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .onTapGesture { showFullCaption = true }
                }
            }
        }
    }

    private func versePill(_ verse: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10, weight: .medium))
            Text(verse)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.white.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("Verse: \(verse)")
    }

    // MARK: - Gestures

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    dragDismissOffset = value.translation.height
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > 120 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                        dragDismissOffset = 0
                    }
                }
            }
    }

    private func toggleChrome() {
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }
}
