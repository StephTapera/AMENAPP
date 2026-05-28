import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum PinnedMediaMode: String, Codable, CaseIterable {
    case auto
    case photo
    case video
    case testimony
    case verse
}

struct PinnedPostMetadata: Codable, Equatable {
    var postID: String
    var isPinned: Bool
    var pinnedAt: Date?
    var pinnedReason: String?
    var pinnedLabelOverride: String?
    var pinnedMediaMode: PinnedMediaMode?
    var semanticTags: [String]

    init(
        postID: String,
        isPinned: Bool = true,
        pinnedAt: Date? = nil,
        pinnedReason: String? = nil,
        pinnedLabelOverride: String? = nil,
        pinnedMediaMode: PinnedMediaMode? = nil,
        semanticTags: [String] = []
    ) {
        self.postID = postID
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.pinnedReason = pinnedReason
        self.pinnedLabelOverride = pinnedLabelOverride
        self.pinnedMediaMode = pinnedMediaMode
        self.semanticTags = semanticTags
    }

    var label: String {
        pinnedLabelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Featured post"
    }

    var rationale: String? {
        pinnedReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var firestoreValue: [String: Any] {
        var value: [String: Any] = [
            "postId": postID,
            "isPinned": isPinned,
            "semanticTags": semanticTags
        ]

        if let pinnedAt {
            value["pinnedAt"] = Timestamp(date: pinnedAt)
        }
        if let pinnedReason = rationale {
            value["pinnedReason"] = pinnedReason
        }
        if let pinnedLabelOverride = pinnedLabelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            value["pinnedLabelOverride"] = pinnedLabelOverride
        }
        if let pinnedMediaMode {
            value["pinnedMediaMode"] = pinnedMediaMode.rawValue
        }

        return value
    }

    var postDocumentValue: [String: Any] {
        var value = firestoreValue
        value["postId"] = postID
        return value
    }

    static func decode(from data: [String: Any]) -> PinnedPostMetadata? {
        guard let raw = data["profilePinnedPost"] as? [String: Any] else { return nil }
        return decode(rawValue: raw)
    }

    static func decode(rawValue raw: [String: Any]) -> PinnedPostMetadata? {
        guard let postID = raw["postId"] as? String, !postID.isEmpty else { return nil }

        let isPinned = raw["isPinned"] as? Bool ?? true
        let pinnedAt = (raw["pinnedAt"] as? Timestamp)?.dateValue()
        let pinnedReason = (raw["pinnedReason"] as? String) ?? (raw["rationale"] as? String)
        let pinnedLabelOverride = (raw["pinnedLabelOverride"] as? String) ?? (raw["label"] as? String)
        let pinnedMediaMode = (raw["pinnedMediaMode"] as? String).flatMap(PinnedMediaMode.init(rawValue:))
        let semanticTags = raw["semanticTags"] as? [String] ?? []

        return PinnedPostMetadata(
            postID: postID,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            pinnedReason: pinnedReason,
            pinnedLabelOverride: pinnedLabelOverride,
            pinnedMediaMode: pinnedMediaMode,
            semanticTags: semanticTags
        )
    }
}

typealias PinnedProfilePostMetadata = PinnedPostMetadata

struct PinnedPostLabel: Equatable {
    let title: String
    let subtitle: String?
}

enum PinnedPostVisualState {
    case idle
    case anchoring
    case compressed
    case focused
    case actionMenu
}

enum PinnedPostLabelResolver {
    static func smartPinnedLabel(for post: Post, metadata: PinnedPostMetadata? = nil) -> PinnedPostLabel {
        let override = metadata?.pinnedLabelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let subtitle = metadata?.rationale

        if let override {
            return PinnedPostLabel(title: override, subtitle: subtitle)
        }

        if post.verseReference?.isEmpty == false {
            return PinnedPostLabel(title: "Pinned verse", subtitle: subtitle)
        }

        let sortedMedia = (post.mediaItems ?? []).sorted { $0.order < $1.order }
        if let firstVideo = sortedMedia.first(where: { $0.type == .video }) {
            let videoTitle = post.category == .testimonies ? "Pinned testimony" : "Pinned video"
            let videoSubtitle = subtitle ?? (firstVideo.duration != nil ? "Video testimony" : nil)
            return PinnedPostLabel(title: videoTitle, subtitle: videoSubtitle)
        }

        switch post.category {
        case .testimonies:
            return PinnedPostLabel(title: "Pinned testimony", subtitle: subtitle)
        case .openTable:
            return PinnedPostLabel(title: "Pinned reflection", subtitle: subtitle)
        case .prayer:
            return PinnedPostLabel(title: "Featured post", subtitle: subtitle)
        default:
            break
        }

        if post.hasMedia {
            return PinnedPostLabel(title: "Featured post", subtitle: subtitle)
        }

        return PinnedPostLabel(title: "Featured post", subtitle: subtitle)
    }

    static func pinnedMediaMode(for post: Post, metadata: PinnedPostMetadata? = nil) -> PinnedMediaMode {
        if let metadataMode = metadata?.pinnedMediaMode {
            return metadataMode
        }
        if post.verseReference?.isEmpty == false {
            return .verse
        }
        if post.category == .testimonies {
            return .testimony
        }
        if post.mediaItems?.contains(where: { $0.type == .video }) == true {
            return .video
        }
        if post.hasMedia {
            return .photo
        }
        return .auto
    }

    static func semanticTags(for post: Post) -> [String] {
        var tags: [String] = []

        if post.verseReference?.isEmpty == false {
            tags.append("Verse attached")
        }

        switch post.category {
        case .testimonies:
            tags.append("Testimony")
        case .prayer:
            tags.append("Prayer")
        case .openTable:
            tags.append("Reflection")
        default:
            break
        }

        if let firstMedia = post.mediaItems?.sorted(by: { $0.order < $1.order }).first {
            tags.append(firstMedia.type == .video ? "Video" : "Photo")
        } else if let firstImage = post.imageURLs?.first, !firstImage.isEmpty {
            tags.append("Photo")
        }

        return Array(NSOrderedSet(array: tags).array as? [String] ?? tags).prefix(2).map { $0 }
    }
}

enum PinnedProfileError: LocalizedError {
    case notAuthenticated
    case notOwner
    case postNotFound
    case pinUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to pin a post."
        case .notOwner:
            return "Only the profile owner can pin this post."
        case .postNotFound:
            return "Pinned post unavailable."
        case .pinUnavailable:
            return "This pinned post is unavailable."
        }
    }
}

@MainActor
final class PinnedGlassPostService: ObservableObject {
    static let shared = PinnedGlassPostService()

    private let db = Firestore.firestore()

    private init() {}

    func pinPostToProfile(postId: String, userId: String, reason: String?) async throws -> PinnedPostMetadata {
        let currentPinned = try await currentPinnedMetadata(userId: userId)
        if let currentPinned, currentPinned.postID != postId {
            return try await replacePinnedPost(
                oldPostId: currentPinned.postID,
                newPostId: postId,
                userId: userId,
                reason: reason
            )
        }

        let post = try await fetchOwnedPost(postId: postId, userId: userId)
        let label = PinnedPostLabelResolver.smartPinnedLabel(for: post)
        let metadata = PinnedPostMetadata(
            postID: resolvedPostID(for: post),
            isPinned: true,
            pinnedAt: Date(),
            pinnedReason: reason?.nilIfEmpty ?? label.subtitle,
            pinnedLabelOverride: label.title,
            pinnedMediaMode: PinnedPostLabelResolver.pinnedMediaMode(for: post),
            semanticTags: PinnedPostLabelResolver.semanticTags(for: post)
        )

        let batch = db.batch()
        let userRef = db.collection("users").document(userId)
        let postRef = db.collection("posts").document(postId)

        batch.setData(["profilePinnedPost": metadata.firestoreValue], forDocument: userRef, merge: true)
        batch.setData([
            "isPinned": true,
            "pinnedAt": FieldValue.serverTimestamp(),
            "pinnedMetadata": metadata.postDocumentValue
        ], forDocument: postRef, merge: true)

        try await batch.commit()
        return metadata
    }

    func unpinPostFromProfile(postId: String, userId: String) async throws {
        let post = try await fetchOwnedPost(postId: postId, userId: userId)
        let postKey = resolvedPostID(for: post)
        let userRef = db.collection("users").document(userId)
        let postRef = db.collection("posts").document(postId)

        let batch = db.batch()
        batch.updateData(["profilePinnedPost": FieldValue.delete()], forDocument: userRef)
        batch.setData([
            "isPinned": false,
            "pinnedAt": FieldValue.delete(),
            "pinnedMetadata": FieldValue.delete()
        ], forDocument: postRef, merge: true)

        if let userPinned = try await currentPinnedMetadata(userId: userId),
           userPinned.postID != postKey,
           userPinned.postID != postId {
            throw PinnedProfileError.pinUnavailable
        }

        try await batch.commit()
    }

    func replacePinnedPost(oldPostId: String, newPostId: String, userId: String, reason: String?) async throws -> PinnedPostMetadata {
        let oldPost = try await fetchOwnedPost(postId: oldPostId, userId: userId)
        let newPost = try await fetchOwnedPost(postId: newPostId, userId: userId)

        let label = PinnedPostLabelResolver.smartPinnedLabel(for: newPost)
        let metadata = PinnedPostMetadata(
            postID: resolvedPostID(for: newPost),
            isPinned: true,
            pinnedAt: Date(),
            pinnedReason: reason?.nilIfEmpty ?? label.subtitle,
            pinnedLabelOverride: label.title,
            pinnedMediaMode: PinnedPostLabelResolver.pinnedMediaMode(for: newPost),
            semanticTags: PinnedPostLabelResolver.semanticTags(for: newPost)
        )

        let batch = db.batch()
        let userRef = db.collection("users").document(userId)
        let oldPostRef = db.collection("posts").document(oldPostId)
        let newPostRef = db.collection("posts").document(newPostId)

        batch.setData(["profilePinnedPost": metadata.firestoreValue], forDocument: userRef, merge: true)
        batch.setData([
            "isPinned": false,
            "pinnedAt": FieldValue.delete(),
            "pinnedMetadata": FieldValue.delete()
        ], forDocument: oldPostRef, merge: true)
        batch.setData([
            "isPinned": true,
            "pinnedAt": FieldValue.serverTimestamp(),
            "pinnedMetadata": metadata.postDocumentValue
        ], forDocument: newPostRef, merge: true)

        if resolvedPostID(for: oldPost) == resolvedPostID(for: newPost) {
            throw PinnedProfileError.pinUnavailable
        }

        try await batch.commit()
        return metadata
    }

    func currentPinnedMetadata(userId: String) async throws -> PinnedPostMetadata? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        return PinnedPostMetadata.decode(from: snapshot.data() ?? [:])
    }

    private func fetchOwnedPost(postId: String, userId: String) async throws -> Post {
        guard Auth.auth().currentUser?.uid == userId else {
            throw PinnedProfileError.notOwner
        }

        let snapshot = try await db.collection("posts").document(postId).getDocument()
        guard snapshot.exists else {
            throw PinnedProfileError.postNotFound
        }

        guard let data = snapshot.data(), (data["authorId"] as? String) == userId else {
            throw PinnedProfileError.notOwner
        }

        guard let post = try? snapshot.data(as: Post.self) else {
            throw PinnedProfileError.postNotFound
        }

        return post
    }

    private func resolvedPostID(for post: Post) -> String {
        post.firestoreId.isEmpty ? post.id.uuidString : post.firestoreId
    }
}

struct PinnedPostHeaderConfiguration {
    let label: PinnedPostLabel
    let semanticTags: [String]
    let collapseProgress: CGFloat
    let glowAmount: CGFloat
    let showText: Bool
}

struct PinnedPostGlassContainer<Content: View>: View {
    let post: Post
    let metadata: PinnedPostMetadata
    let isOwner: Bool
    let collapseProgress: CGFloat
    let scrollVelocity: CGFloat
    let namespace: Namespace.ID
    let onOpenDetails: () -> Void
    let onUnpin: (() -> Void)?
    let onReplace: (() -> Void)?
    let onShare: (() -> Void)?
    let onInsights: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAnchored = false
    @State private var showActionMenu = false
    @State private var isMediaFocused = false
    @State private var selectedMediaIndex = 0

    private var visualState: PinnedPostVisualState {
        if showActionMenu {
            return .actionMenu
        }
        if isMediaFocused {
            return .focused
        }
        if collapseProgress > 0.58 {
            return .compressed
        }
        if !hasAnchored {
            return .anchoring
        }
        return .idle
    }

    private var label: PinnedPostLabel {
        PinnedPostLabelResolver.smartPinnedLabel(for: post, metadata: metadata)
    }

    private var sortedMediaItems: [PostMediaItem] {
        if let mediaItems = post.mediaItems, !mediaItems.isEmpty {
            return mediaItems.sorted { $0.order < $1.order }
        }
        return (post.imageURLs ?? []).enumerated().map { index, url in
            PostMediaItem(type: .image, url: url, order: index)
        }
    }

    private var mediaPreviewItems: [PostMediaItem] {
        Array(sortedMediaItems.prefix(2))
    }

    private var velocityResponse: CGFloat {
        min(max(abs(scrollVelocity) / 1200, 0), 1)
    }

    private var cardScale: CGFloat {
        switch visualState {
        case .anchoring:
            return hasAnchored ? 1 : 0.985
        case .compressed:
            return 1 - (collapseProgress * 0.03)
        case .focused:
            return 0.992
        case .actionMenu:
            return 0.986
        case .idle:
            return 1
        }
    }

    private var cardBlur: CGFloat {
        reduceMotion ? 0 : velocityResponse * 1.1
    }

    private var cardShadowOpacity: Double {
        0.08 + (velocityResponse * 0.05)
    }

    private var mediaParallax: CGFloat {
        reduceMotion ? 0 : collapseProgress * -10
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                PinnedPostHeader(
                    configuration: .init(
                        label: label,
                        semanticTags: metadata.semanticTags.isEmpty ? PinnedPostLabelResolver.semanticTags(for: post) : metadata.semanticTags,
                        collapseProgress: collapseProgress,
                        glowAmount: velocityResponse,
                        showText: hasAnchored || reduceMotion
                    ),
                    namespace: namespace,
                    postID: resolvedPostID
                )

                if !mediaPreviewItems.isEmpty {
                    PinnedPostMediaPreview(
                        post: post,
                        items: mediaPreviewItems,
                        namespace: namespace,
                        glowAmount: velocityResponse,
                        parallaxOffset: mediaParallax
                    ) { index in
                        selectedMediaIndex = index
                        if reduceMotion {
                            isMediaFocused = true
                        } else {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                isMediaFocused = true
                            }
                        }
                    }
                }

                content()
            }
            .padding(14)
            .background(shellBackground)
            .scaleEffect(cardScale, anchor: .top)
            .blur(radius: cardBlur)
            .opacity(visualState == .compressed ? 1 - (collapseProgress * 0.12) : 1)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.24 + (velocityResponse * 0.08)))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
                    .blur(radius: 2.4)
                    .opacity(0.9)
            }
            .overlay(alignment: .topTrailing) {
                if isOwner {
                    Button {
                        toggleActionMenu()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.68))
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.tint(.white.opacity(0.16)), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .accessibilityLabel("Pinned post actions")
                    .accessibilityHint("Shows actions for the pinned post.")
                }
            }
            .shadow(color: .black.opacity(cardShadowOpacity), radius: 18 + (velocityResponse * 8), x: 0, y: 8 + (velocityResponse * 4))
            .offset(y: hasAnchored || reduceMotion ? 0 : 8)
            .onAppear {
                guard !hasAnchored else { return }
                guard !reduceMotion else {
                    hasAnchored = true
                    return
                }
                withAnimation(.interactiveSpring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.14)) {
                    hasAnchored = true
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.42)
                    .onEnded { _ in
                        guard isOwner else { return }
                        HapticManager.impact(style: .light)
                        toggleActionMenu()
                    }
            )

            if showActionMenu, isOwner {
                PinnedPostActionBloomMenu(
                    onUnpin: onUnpin,
                    onReplace: onReplace,
                    onShare: onShare,
                    onInsights: onInsights
                )
                .padding(.top, 30)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
            }
        }
        .overlay {
            if isMediaFocused {
                pinnedMediaOverlay
            }
        }
    }

    private var resolvedPostID: String {
        post.firestoreId.isEmpty ? post.id.uuidString : post.firestoreId
    }

    private var shellBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.68 + (velocityResponse * 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private var pinnedMediaOverlay: some View {
        let transitionID = "pinned-media-\(resolvedPostID)-\(selectedMediaIndex)"

        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(.white.opacity(0.36))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissMediaOverlay()
                }

            AmenMediaDetailView(
                post: post,
                initialMediaIndex: selectedMediaIndex,
                sourceContext: .profile
            )
            .background(Color.clear)

            Button {
                dismissMediaOverlay()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.tint(.white.opacity(0.16)), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 16)
            .accessibilityLabel("Close pinned media")
        }
        .transition(.opacity)
    }

    private func toggleActionMenu() {
        if reduceMotion {
            showActionMenu.toggle()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                showActionMenu.toggle()
            }
        }
    }

    private func dismissMediaOverlay() {
        if reduceMotion {
            isMediaFocused = false
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                isMediaFocused = false
            }
        }
    }
}

struct PinnedPostHeader: View {
    let configuration: PinnedPostHeaderConfiguration
    let namespace: Namespace.ID
    let postID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                headerPill
                Spacer(minLength: 0)
            }

            if let subtitle = configuration.label.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.black.opacity(0.5))
                    .opacity(1 - (configuration.collapseProgress * 0.82))
            }

            if !configuration.semanticTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(configuration.semanticTags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.72))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.26)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.34), lineWidth: 0.8))
                    }
                }
                .opacity(1 - (configuration.collapseProgress * 0.92))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.62 + (configuration.glowAmount * 0.06)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    private var headerPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12)

            if configuration.showText {
                Text(configuration.label.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 6)))
            }
        }
        .foregroundStyle(.black.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.white.opacity(0.3))
                .overlay(Capsule().strokeBorder(.white.opacity(0.36), lineWidth: 0.8))
        )
        .glassEffectID("pinned-pill-\(postID)", in: namespace)
    }
}

struct PinnedPostMediaPreview: View {
    let post: Post
    let items: [PostMediaItem]
    let namespace: Namespace.ID
    let glowAmount: CGFloat
    let parallaxOffset: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let itemWidth = items.count > 1 ? max((width - 8) / 2, 0) : width

            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(index)
                    } label: {
                        previewSurface(for: item, index: index)
                            .frame(width: itemWidth, height: 168)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.type == .video ? "Open pinned video" : "Open pinned photo")
                }
            }
            .offset(y: parallaxOffset)
        }
        .frame(height: 168)
    }

    @ViewBuilder
    private func previewSurface(for item: PostMediaItem, index: Int) -> some View {
        let transitionID = "pinned-media-\(resolvedPostID)-\(index)"

        ZStack(alignment: .bottomLeading) {
            AmenMediaSurface(
                item: item,
                contentMode: .fill,
                cornerRadius: 22,
                showsVideoBadge: false
            )
            .matchedGeometryEffect(id: transitionID, in: namespace)

            LinearGradient(
                colors: [.clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 8) {
                if item.type == .video {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.8)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.64), lineWidth: 0.8))

                    if let duration = item.duration {
                        Text(durationText(duration))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.78))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.white.opacity(0.66)))
                    }
                } else if items.count > 1 && index == items.count - 1 {
                    Text("\(items.count) media")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.66)))
                }
            }
            .padding(12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.42 + (glowAmount * 0.08)), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.08 + (glowAmount * 0.04)), radius: 14, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var resolvedPostID: String {
        post.firestoreId.isEmpty ? post.id.uuidString : post.firestoreId
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}

struct PinnedPostActionBloomMenu: View {
    let onUnpin: (() -> Void)?
    let onReplace: (() -> Void)?
    let onShare: (() -> Void)?
    let onInsights: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton(title: "Unpin", systemImage: "pin.slash", action: onUnpin)
            actionButton(title: "Replace pin", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
            actionButton(title: "Share", systemImage: "square.and.arrow.up", action: onShare)
            actionButton(title: "View insights", systemImage: "chart.line.uptrend.xyaxis", action: onInsights)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .accessibilityLabel("Pinned post actions")
    }

    @ViewBuilder
    private func actionButton(title: String, systemImage: String, action: (() -> Void)?) -> some View {
        if let action {
            Button {
                HapticManager.selection()
                action()
            } label: {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(.white.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
