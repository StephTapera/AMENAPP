import SwiftUI
import AVKit

struct PinnedProfileHeroSection: View {
    let post: Post
    let metadata: PinnedProfilePostMetadata
    let collapseProgress: CGFloat
    let namespace: Namespace.ID
    let onUnpin: () -> Void
    let onShare: () -> Void
    let onViewDetails: () -> Void
    let onReplace: () -> Void

    @State private var hasAnimatedIn = false
    @State private var showSheen = false
    @State private var sheenOffset: CGFloat = -260
    @State private var showFocusedMedia = false
    @State private var focusedMedia: PostMediaItem?
    @State private var showActionBloom = false
    @State private var labelTransitionKey = UUID()

    private var mediaItems: [PostMediaItem] {
        (post.imageURLs ?? []).enumerated().map { index, url in
            PostMediaItem(type: .image, url: url, order: index)
        }
    }

    private var previewItems: [PostMediaItem] {
        Array(mediaItems.prefix(2))
    }

    private var semanticTags: [String] {
        Array(metadata.semanticTags.prefix(2))
    }

    private var detailOpacity: Double {
        1 - (collapseProgress * 0.78)
    }

    private var edgeMeltProgress: CGFloat {
        min(max((collapseProgress - 0.32) / 0.68, 0), 1)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                headerSurface
                    .opacity(1 - (collapseProgress * 0.48))
                    .offset(y: collapseProgress * -10)

                heroSurface
                    .scaleEffect(hasAnimatedIn ? 1 : 0.985, anchor: .top)
                    .offset(y: hasAnimatedIn ? 0 : 8)
                    .shadow(
                        color: .black.opacity(0.08 + (collapseProgress * 0.08)),
                        radius: 16 + (collapseProgress * 10),
                        x: 0,
                        y: 8 + (collapseProgress * 5)
                    )
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .topTrailing) {
                if showActionBloom {
                    actionBloom
                        .padding(.top, 24)
                        .padding(.trailing, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
                }
            }
            .overlay {
                if let focusedMedia, showFocusedMedia {
                    PinnedProfileFocusedMediaOverlay(
                        item: focusedMedia,
                        namespace: namespace,
                        onDismiss: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                showFocusedMedia = false
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onAppear {
            guard !hasAnimatedIn else { return }
            labelTransitionKey = UUID()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                hasAnimatedIn = true
            }
            runSheenSweep()
        }
        .onChange(of: metadata.label) { _, _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                labelTransitionKey = UUID()
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42)
                .onEnded { _ in
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        showActionBloom.toggle()
                    }
                }
        )
    }

    private var headerSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                pill

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        showActionBloom.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .amenGlassEffect(.white.opacity(0.12), in: Circle())
                        .glassEffectID("pinned-overflow-\(post.firestoreId)", in: namespace)
                }
                .buttonStyle(.plain)
            }

            if let rationale = metadata.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.black.opacity(0.5))
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .opacity(detailOpacity)
            }

            if !semanticTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(semanticTags.enumerated()), id: \.element) { index, tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.18)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.26), lineWidth: 0.8))
                            .offset(y: hasAnimatedIn ? 0 : 8)
                            .opacity(hasAnimatedIn ? detailOpacity : 0)
                            .animation(
                                .spring(response: 0.34, dampingFraction: 0.84).delay(Double(index) * 0.05),
                                value: hasAnimatedIn
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .adaptiveLiquidGlassHeaderSurface(progress: collapseProgress, cornerRadius: 24)
    }

    private var pill: some View {
        HStack(spacing: 7) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))

            PinnedProfileAnimatedLabelText(text: metadata.label, transitionKey: labelTransitionKey)
                .lineLimit(1)
        }
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .amenGlassEffect(.white.opacity(0.12), in: Capsule())
        .glassEffectID("pinned-pill-\(post.firestoreId)", in: namespace)
    }

    private var heroSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.black.opacity(0.88))

                    HStack(spacing: 6) {
                        Text(post.timeAgo)
                        if let verseReference = post.verseReference, !verseReference.isEmpty {
                            Text("•")
                            Text(verseReference)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                }

                Spacer(minLength: 0)

                if mediaItems.contains(where: { $0.type == .video }) {
                    Label("Video", systemImage: "play.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.32)))
                }
            }

            if !post.content.isEmpty {
                Text(post.content)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineSpacing(4)
                    .lineLimit(previewItems.isEmpty ? 8 : 6)
            }

            if !previewItems.isEmpty {
                PinnedProfileMediaPreviewGrid(
                    items: previewItems,
                    namespace: namespace,
                    onSelect: { item in
                        focusedMedia = item
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                            showFocusedMedia = true
                        }
                    }
                )
                .offset(y: collapseProgress * -4)
            }

            HStack(spacing: 16) {
                labelMetric(systemName: "hands.sparkles", text: "\(post.amenCount)")
                labelMetric(systemName: "bubble.left", text: "\(post.commentCount)")
                labelMetric(systemName: "arrow.2.squarepath", text: "\(post.repostCount)")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    .white.opacity(0.08),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.45 - (edgeMeltProgress * 0.3)))
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                        .blur(radius: 2 + (edgeMeltProgress * 6))
                        .opacity(1 - edgeMeltProgress)
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.12 + (edgeMeltProgress * 0.2)),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 42)
                    .blur(radius: 10)
                    .opacity(edgeMeltProgress)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.48 - (edgeMeltProgress * 0.28)), lineWidth: 1)
                }
                .overlay {
                    if showSheen {
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.26),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 120)
                        .rotationEffect(.degrees(18))
                        .offset(x: sheenOffset)
                        .blendMode(.screen)
                        .mask {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                        }
                    }
                }
        }
        .compositingGroup()
    }

    private var avatar: some View {
        Group {
            if let urlString = post.authorProfileImageURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, size: CGSize(width: 96, height: 96)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.22)
                }
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0.7), .black.opacity(0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Text(initials(from: post.authorName))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
    }

    private var actionBloom: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton(title: "Unpin", systemImage: "pin.slash", action: onUnpin)
            actionButton(title: "Replace pin", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
            actionButton(title: "Share", systemImage: "square.and.arrow.up", action: onShare)
            actionButton(title: "View insights", systemImage: "info.circle", action: onViewDetails)
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                showActionBloom = false
            }
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .amenGlassEffect(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func labelMetric(systemName: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.black.opacity(0.62))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let value = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "A" : value.uppercased()
    }

    private func runSheenSweep() {
        guard !showSheen else { return }
        showSheen = true
        sheenOffset = -260

        withAnimation(.easeInOut(duration: 0.82)) {
            sheenOffset = 340
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            showSheen = false
            sheenOffset = -260
        }
    }
}

struct PinnedProfileMiniTokenView: View {
    let metadata: PinnedProfilePostMetadata
    let postID: String
    let namespace: Namespace.ID
    let collapseProgress: CGFloat
    let fadeProgress: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))

            Text(metadata.label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .amenGlassEffect(.white.opacity(0.12), in: Capsule())
        .glassEffectID("pinned-pill-\(postID)", in: namespace)
        .scaleEffect(0.97 + (collapseProgress * 0.03))
        .opacity(1 - fadeProgress)
    }
}

struct PinnedReadOnlyProfileHeader: View {
    let metadata: PinnedProfilePostMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(metadata.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .amenGlassEffect(.white.opacity(0.12), in: Capsule())

            if let rationale = metadata.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ProfileDesignTokens.horizontalPadding)
        .padding(.top, 12)
    }
}

private struct PinnedProfileAnimatedLabelText: View {
    let text: String
    let transitionKey: UUID

    var body: some View {
        ZStack {
            Text(text)
                .id(transitionKey)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: transitionKey)
    }
}

private struct PinnedProfileMediaPreviewGrid: View {
    let items: [PostMediaItem]
    let namespace: Namespace.ID
    let onSelect: (PostMediaItem) -> Void

    var body: some View {
        Group {
            if items.count == 1, let item = items.first {
                PinnedProfileMediaTile(item: item, namespace: namespace)
                    .onTapGesture {
                        onSelect(item)
                    }
            } else {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        PinnedProfileMediaTile(item: item, namespace: namespace)
                            .onTapGesture {
                                onSelect(item)
                            }
                    }
                }
            }
        }
    }
}

private struct PinnedProfileMediaTile: View {
    let item: PostMediaItem
    let namespace: Namespace.ID

    private var mediaURL: URL? {
        let string = item.thumbnailURL ?? item.url
        return URL(string: string)
    }

    private var aspectRatio: CGFloat {
        min(max(item.computedAspectRatio, 0.72), 1.5)
    }

    var body: some View {
        ZStack {
            if let mediaURL {
                CachedAsyncImage(url: mediaURL, size: CGSize(width: 900, height: 900)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    LinearGradient(
                        colors: [.black.opacity(0.12), .black.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if item.type == .video {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.leading, 3)
                    }

                if let duration = item.formattedDuration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(duration)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.94))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.black.opacity(0.35)))
                                .padding(10)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.26), lineWidth: 1)
        )
        .matchedGeometryEffect(id: "pinned-media-\(item.id)", in: namespace)
    }
}

private struct PinnedProfileFocusedMediaOverlay: View {
    let item: PostMediaItem
    let namespace: Namespace.ID
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.12))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button("Close") {
                        onDismiss()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .amenGlassEffect(.white.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer(minLength: 0)

                Group {
                    if item.type == .video, let url = URL(string: item.url) {
                        VideoPlayer(player: AVPlayer(url: url))
                    } else {
                        PinnedProfileMediaTile(item: item, namespace: namespace)
                    }
                }
                .matchedGeometryEffect(id: "pinned-media-\(item.id)", in: namespace)
                .frame(maxWidth: 380)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 18)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
        }
    }
}
