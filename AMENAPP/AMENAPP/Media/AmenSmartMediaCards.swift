// AmenSmartMediaCards.swift
// AMENAPP
//
// Universal typed media attachment card renderers.
// Each card kind matches the Liquid Glass design language:
//   - White/surfaceCard backgrounds — NO full-card glass fill
//   - .ultraThinMaterial only on controls, overlays, and glass pills
//   - AmenTheme.Colors for all color tokens
//
// Entry point: AmenSmartMediaCardRouter
// Loading skeleton: AmenLinkLoadingCard
// Multi-attachment: AmenAttachmentRail

import SwiftUI

// MARK: - AmenSmartMediaCardRouter

/// Routes to the correct card renderer based on `attachment.kind`.
struct AmenSmartMediaCardRouter: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil
    var onAskBerean: (() -> Void)? = nil

    var body: some View {
        switch attachment.kind {
        case .video:
            AmenVideoAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        case .podcast:
            AmenPodcastAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        case .music:
            AmenMusicAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        case .article:
            AmenArticleAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove,
                onAskBerean: onAskBerean
            )
        case .book:
            AmenBookAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        case .product:
            AmenProductAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        case .scripture:
            AmenScriptureAttachmentCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove,
                onAskBerean: onAskBerean
            )
        case .link:
            AmenGenericLinkCard(
                attachment: attachment,
                isCompact: isCompact,
                onRemove: onRemove
            )
        }
    }
}

// MARK: - Shared Card Shell

/// Base card shell: white surfaceCard background, subtle border and shadow.
/// All non-playable type cards embed this shell.
private struct AmenMediaCardShell<Content: View>: View {
    var onRemove: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(AmenTheme.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)

            if let onRemove {
                AmenCardRemoveButton(action: onRemove)
                    .padding(8)
            }
        }
    }
}

// MARK: - Remove Button

private struct AmenCardRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove attachment")
    }
}

// MARK: - Action Pill Button (local tappable variant)
// Named distinctly from the display-only AmenGlassPill in ReasoningThreadComponents.

private struct _MediaActionPill: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = AmenTheme.Colors.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration Formatter

private func formatDuration(ms: Int) -> String {
    let totalSeconds = ms / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - AmenVideoAttachmentCard

struct AmenVideoAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isThumbnailPressed = false

    private var videoDetails: AmenVideoDetails? { attachment.videoDetails }
    private var playable: AmenPlayableInfo? { attachment.playable }
    private var hasTimestamp: Bool { (playable?.startMs ?? 0) > 0 }
    private var durationMs: Int? { playable?.durationMs }
    private var youtubeID: String? { videoDetails?.youtubeVideoID }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            // Thumbnail
            ZStack(alignment: .center) {
                thumbnailImage

                // Play overlay
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)

                // Chips row (bottom-leading)
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        if hasTimestamp, let ms = playable?.startMs {
                            timestampChip(ms: ms)
                        }
                        if videoDetails?.hasChapters == true {
                            chaptersChip
                        }
                        Spacer()
                        if let dur = durationMs {
                            durationChip(ms: dur)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(height: 160)
            .clipped()
            .scaleEffect(isThumbnailPressed && !reduceMotion ? 1.02 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.75),
                value: isThumbnailPressed
            )
            .onTapGesture {
                guard !reduceMotion else { return }
                isThumbnailPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    isThumbnailPressed = false
                }
                openURL()
            }
            .accessibilityLabel("Video thumbnail: \(attachment.title)")
            .accessibilityHint("Tap to open video")

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let channel = videoDetails?.channelName {
                        Text(channel)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    if videoDetails?.channelName != nil, durationMs != nil {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    if let dur = durationMs {
                        Text(formatDuration(ms: dur))
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }

                if let ytID = youtubeID {
                    _MediaActionPill(
                        title: "Watch on YouTube",
                        systemImage: "play.rectangle.fill",
                        tint: AmenTheme.Colors.textSecondary
                    ) {
                        if let url = URL(string: "https://www.youtube.com/watch?v=\(ytID)") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let urlString = attachment.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    videoThumbnailPlaceholder
                }
            }
        } else {
            videoThumbnailPlaceholder
        }
    }

    private var videoThumbnailPlaceholder: some View {
        Rectangle()
            .fill(AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }

    private func timestampChip(ms: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9))
            Text("Starts at \(formatDuration(ms: ms))")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AmenTheme.Colors.amenGold.opacity(0.85))
        .clipShape(Capsule())
    }

    private var chaptersChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "list.number")
                .font(.system(size: 9))
            Text("Chapters")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func durationChip(ms: Int) -> some View {
        Text(formatDuration(ms: ms))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
    }

    private func openURL() {
        guard let urlString = playable?.mediaURL,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - AmenPodcastAttachmentCard

struct AmenPodcastAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    @State private var selectedSpeed: Double = 1.0

    private var podcastDetails: AmenPodcastDetails? { attachment.podcastDetails }
    private var speeds: [Double] { podcastDetails?.speedOptions ?? [0.75, 1.0, 1.25, 1.5, 2.0] }
    private var durationMs: Int? { attachment.playable?.durationMs }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                podcastArtwork
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Metadata
                VStack(alignment: .leading, spacing: 3) {
                    if let show = podcastDetails?.showName {
                        Text(show)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Text(attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)
                    if let dur = durationMs {
                        Text(formatDuration(ms: dur))
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }

                    // Controls row
                    HStack(spacing: 8) {
                        // Play button (no autoplay)
                        Button {
                            // Deferred to AmenMediaPlaybackCoordinator.shared in production
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Play")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play episode")
                        .accessibilityHint("Opens podcast playback")
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            // Speed chips
            speedSelector
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var podcastArtwork: some View {
        if let urlString = attachment.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    podcastArtworkPlaceholder
                }
            }
        } else {
            podcastArtworkPlaceholder
        }
    }

    private var podcastArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }

    private var speedSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        selectedSpeed = speed
                    } label: {
                        Text("\(speed, specifier: speed == 1.0 ? "%.0f" : "%.2g")×")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(
                                selectedSpeed == speed
                                    ? AmenTheme.Colors.textInverse
                                    : AmenTheme.Colors.textSecondary
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                selectedSpeed == speed
                                    ? AmenTheme.Colors.textPrimary
                                    : AmenTheme.Colors.surfaceChip
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Playback speed \(speed)×")
                    .accessibilityAddTraits(selectedSpeed == speed ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - AmenMusicAttachmentCard

struct AmenMusicAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    private var musicDetails: AmenMusicDetails? { attachment.musicDetails }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            HStack(spacing: 12) {
                // Artwork
                musicArtwork
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)
                    if let artists = musicDetails?.artists, !artists.isEmpty {
                        Text(artists.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    if let sub = attachment.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                Spacer(minLength: 0)

                if let urlString = attachment.playable?.mediaURL,
                   let url = URL(string: urlString) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open in music app")
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var musicArtwork: some View {
        if let urlString = musicDetails?.albumArtURL ?? attachment.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    musicArtworkPlaceholder
                }
            }
        } else {
            musicArtworkPlaceholder
        }
    }

    private var musicArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }
}

// MARK: - AmenArticleAttachmentCard

struct AmenArticleAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil
    var onAskBerean: (() -> Void)? = nil

    private var articleDetails: AmenArticleDetails? { attachment.articleDetails }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            // Hero image
            if let urlString = attachment.thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipped()
                    }
                }
                .frame(height: 120)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 6) {
                // Source row
                HStack(spacing: 5) {
                    if let faviconURL = articleDetails?.faviconURL,
                       let url = URL(string: faviconURL) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .frame(width: 14, height: 14)
                    }
                    Text(articleDetails?.sourceName ?? (attachment.subtitle ?? ""))
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    Spacer()

                    if let readTime = articleDetails?.readingTimeMinutes {
                        Text("\(readTime) min read")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                            )
                    }
                }

                Text(attachment.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                if let excerpt = articleDetails?.excerpt {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(3)
                }

                if let onAskBerean {
                    HStack {
                        Spacer()
                        _MediaActionPill(
                            title: "Ask Berean",
                            systemImage: "book.fill",
                            tint: AmenTheme.Colors.amenGoldText,
                            action: onAskBerean
                        )
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - AmenBookAttachmentCard

struct AmenBookAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    private var bookDetails: AmenBookDetails? { attachment.bookDetails }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            HStack(alignment: .top, spacing: 12) {
                // Book cover
                bookCover
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)

                    Text(bookDetails?.authorName ?? (attachment.subtitle ?? ""))
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    if let rating = bookDetails?.rating {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: starName(for: i, rating: rating))
                                    .font(.system(size: 10))
                                    .foregroundStyle(AmenTheme.Colors.amenGold)
                            }
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }

                    if let blurb = bookDetails?.blurb {
                        Text(blurb)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    _MediaActionPill(
                        title: "Add to Reading Plan",
                        systemImage: "book.closed.fill",
                        tint: AmenTheme.Colors.amenGoldText
                    ) {
                        // Integrate with reading plan in production
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var bookCover: some View {
        if let urlString = bookDetails?.coverURL ?? attachment.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    bookCoverPlaceholder
                }
            }
        } else {
            bookCoverPlaceholder
        }
    }

    private var bookCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AmenTheme.Colors.amenBronze.opacity(0.20))
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AmenTheme.Colors.amenBronze)
            )
    }

    private func starName(for index: Int, rating: Double) -> String {
        let filled = Int(rating)
        let hasHalf = rating - Double(filled) >= 0.5
        if index < filled { return "star.fill" }
        if index == filled && hasHalf { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - AmenProductAttachmentCard

struct AmenProductAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    private var productDetails: AmenProductDetails? { attachment.productDetails }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            HStack(alignment: .top, spacing: 12) {
                // Product image
                productImage
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)

                    Text(productDetails?.merchantName ?? (attachment.subtitle ?? ""))
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    if let label = productDetails?.safetyLabel {
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AmenTheme.Colors.statusWarning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AmenTheme.Colors.statusWarning.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        _MediaActionPill(
                            title: "View Product",
                            systemImage: "arrow.up.right",
                            tint: AmenTheme.Colors.textPrimary
                        ) {
                            // Open product URL in production
                        }

                        if productDetails?.isAffiliate == true {
                            Text("Affiliate link")
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if let urlString = productDetails?.imageURL ?? attachment.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    productImagePlaceholder
                }
            }
        } else {
            productImagePlaceholder
        }
    }

    private var productImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "bag.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }
}

// MARK: - AmenScriptureAttachmentCard

struct AmenScriptureAttachmentCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil
    var onAskBerean: (() -> Void)? = nil

    @State private var isExpanded = false

    private var scriptureDetails: AmenScriptureDetails? { attachment.scriptureDetails }
    private let maxCollapsedLines = 4

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Gold left accent border
                Rectangle()
                    .fill(AmenTheme.Colors.amenGold)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 8) {
                    // Reference header
                    HStack {
                        Text(scriptureDetails?.reference ?? attachment.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AmenTheme.Colors.amenGoldText)

                        Spacer()

                        // Translation badge
                        Text(scriptureDetails?.translation ?? "NIV")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                            )
                    }

                    // Verse text
                    if let verseText = scriptureDetails?.verseText {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verseText)
                                .font(.body)
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .lineLimit(isExpanded ? nil : maxCollapsedLines)

                            if !isExpanded && verseTextIsLong(verseText) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        isExpanded = true
                                    }
                                } label: {
                                    Text("…Read more")
                                        .font(.body)
                                        .foregroundStyle(AmenTheme.Colors.amenGoldText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        if let deepLink = scriptureDetails?.youVersionDeepLink,
                           let url = URL(string: deepLink) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 12))
                                    Text("Open in AMEN")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open in AMEN Bible reader")
                        }

                        if let onAskBerean {
                            _MediaActionPill(
                                title: "Reflect with Berean",
                                systemImage: "sparkles",
                                tint: AmenTheme.Colors.amenGoldText,
                                action: onAskBerean
                            )
                            .accessibilityHint("Opens Berean AI reflection for this verse")
                        }
                    }
                }
                .padding(12)
            }
            .background(AmenTheme.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AmenTheme.Colors.amenGold.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)

            if let onRemove {
                AmenCardRemoveButton(action: onRemove)
                    .padding(8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scripture: \(scriptureDetails?.reference ?? attachment.title)")
    }

    private func verseTextIsLong(_ text: String) -> Bool {
        // Approximate: more than ~200 characters likely overflows 4 lines
        text.count > 200
    }
}

// MARK: - AmenGenericLinkCard

struct AmenGenericLinkCard: View {
    let attachment: AmenMediaAttachment
    var isCompact: Bool = true
    var onRemove: (() -> Void)? = nil

    private var linkDetails: AmenLinkDetails? { attachment.linkDetails }

    var body: some View {
        AmenMediaCardShell(onRemove: onRemove) {
            HStack(alignment: .top, spacing: 10) {
                // Thumbnail or domain favicon placeholder
                linkThumbnail
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(linkDetails?.domain ?? (attachment.subtitle ?? ""))
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }

                    Text(linkDetails?.ogTitle ?? attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)

                    if let description = linkDetails?.ogDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var linkThumbnail: some View {
        if let urlString = linkDetails?.ogImageURL ?? attachment.thumbnailURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    linkPlaceholder
                }
            }
        } else {
            linkPlaceholder
        }
    }

    private var linkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AmenTheme.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }
}

// MARK: - AmenLinkLoadingCard

/// Skeleton placeholder shown while a URL is being resolved.
/// Respects `accessibilityReduceMotion`: shimmer when false, pulsing opacity when true.
struct AmenLinkLoadingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerPhase: CGFloat = -1.0
    @State private var pulseOpacity: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail placeholder
            skeletonRect(width: nil, height: 100, cornerRadius: 0)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                // Title line
                skeletonRect(width: nil, height: 14, cornerRadius: 7)
                // Subtitle line
                skeletonRect(width: 160, height: 11, cornerRadius: 5)
                // Short line
                skeletonRect(width: 90, height: 11, cornerRadius: 5)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(AmenTheme.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .onAppear { startAnimation() }
        .accessibilityLabel("Loading link preview")
        .accessibilityHint("Resolving link metadata")
    }

    @ViewBuilder
    private func skeletonRect(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat) -> some View {
        if reduceMotion {
            // Pulsing opacity
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: width, height: height)
                .opacity(pulseOpacity)
        } else {
            // Shimmer sweep
            GeometryReader { geo in
                let w = geo.size.width
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: AmenTheme.Colors.shimmerHighlight, location: 0.4),
                                .init(color: AmenTheme.Colors.shimmerHighlight, location: 0.6),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.6)
                        .offset(x: shimmerPhase * (w + w * 0.6) - w * 0.3)
                        .clipped()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(width: width, height: height)
        }
    }

    private func startAnimation() {
        if reduceMotion {
            withAnimation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
            ) {
                pulseOpacity = 1.0
            }
        } else {
            shimmerPhase = -1.0
            withAnimation(
                .linear(duration: 1.4).repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1.0
            }
        }
    }
}

// MARK: - AmenAttachmentRail

/// Horizontal scrolling rail for multiple attachments.
/// Shows up to 3 cards fully, hints at a 4th.
struct AmenAttachmentRail: View {
    let attachments: [AmenMediaAttachment]
    var onRemove: ((String) -> Void)? = nil

    private let cardWidth: CGFloat = 240

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    AmenSmartMediaCardRouter(
                        attachment: attachment,
                        isCompact: true,
                        onRemove: onRemove.map { handler in
                            { handler(attachment.id) }
                        }
                    )
                    .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Attached media, \(attachments.count) item\(attachments.count == 1 ? "" : "s")")
    }
}

// MARK: - Previews

#Preview("Video Card") {
    let attachment = AmenMediaAttachment(
        id: "v1",
        kind: .video,
        sourceURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90",
        title: "The Power of Faith — Sunday Sermon",
        subtitle: "Grace Community Church",
        thumbnailURL: "https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
        accentHex: "FF0000",
        playable: AmenPlayableInfo(
            transport: .youtubeEmbed,
            mediaURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90",
            durationMs: 3_720_000,
            startMs: 90_000
        ),
        videoDetails: AmenVideoDetails(
            channelName: "Grace Community Church",
            youtubeVideoID: "dQw4w9WgXcQ",
            hasChapters: true
        )
    )
    AmenSmartMediaCardRouter(attachment: attachment, onRemove: {})
        .padding()
}

#Preview("Podcast Card") {
    let attachment = AmenMediaAttachment(
        id: "p1",
        kind: .podcast,
        sourceURL: "https://podcasts.apple.com/episode/142",
        title: "Walking By Faith, Not By Sight — Ep. 142",
        subtitle: "The Daily Grace Podcast",
        thumbnailURL: nil,
        accentHex: nil,
        playable: AmenPlayableInfo(
            transport: .nativeAudio,
            mediaURL: "https://example.com/episode.mp3",
            durationMs: 2_820_000,
            startMs: 0
        ),
        podcastDetails: AmenPodcastDetails(
            showName: "The Daily Grace Podcast",
            episodeNumber: 142,
            speedOptions: [0.75, 1.0, 1.25, 1.5, 2.0]
        )
    )
    AmenSmartMediaCardRouter(attachment: attachment, onRemove: {})
        .padding()
}

#Preview("Scripture Card") {
    let attachment = AmenMediaAttachment(
        id: "s1",
        kind: .scripture,
        sourceURL: nil,
        title: "John 3:16",
        subtitle: "NIV",
        thumbnailURL: nil,
        accentHex: "D4AF37",
        scriptureDetails: AmenScriptureDetails(
            reference: "John 3:16",
            verseText: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
            translation: "NIV",
            youVersionDeepLink: "youversion://bible?reference=John+3:16"
        )
    )
    AmenSmartMediaCardRouter(
        attachment: attachment,
        onRemove: {},
        onAskBerean: {}
    )
    .padding()
}

#Preview("Article Card") {
    let attachment = AmenMediaAttachment(
        id: "a1",
        kind: .article,
        sourceURL: "https://thegospelcoalition.org/article/scripture",
        title: "Five Ways to Deepen Your Daily Scripture Reading",
        subtitle: "thegospelcoalition.org",
        thumbnailURL: nil,
        accentHex: nil,
        articleDetails: AmenArticleDetails(
            sourceName: "The Gospel Coalition",
            faviconURL: nil,
            readingTimeMinutes: 4,
            excerpt: "Consistency in Bible reading transforms not just what we know, but who we are becoming."
        )
    )
    AmenSmartMediaCardRouter(
        attachment: attachment,
        onRemove: {},
        onAskBerean: {}
    )
    .padding()
}

#Preview("Book Card") {
    let attachment = AmenMediaAttachment(
        id: "b1",
        kind: .book,
        sourceURL: "https://www.goodreads.com/book/show/11138",
        title: "Mere Christianity",
        subtitle: "C.S. Lewis",
        thumbnailURL: nil,
        accentHex: "8B4513",
        bookDetails: AmenBookDetails(
            authorName: "C.S. Lewis",
            coverURL: nil,
            isbn: "9780060652920",
            rating: 4.8,
            blurb: "A timeless defense of the Christian faith, originally delivered as radio broadcasts during World War II."
        )
    )
    AmenSmartMediaCardRouter(attachment: attachment, onRemove: {})
        .padding()
}

#Preview("Product Card") {
    let attachment = AmenMediaAttachment(
        id: "pr1",
        kind: .product,
        sourceURL: "https://www.amazon.com/dp/B09ABC",
        title: "ESV Study Bible, Large Print",
        subtitle: "Crossway",
        thumbnailURL: nil,
        accentHex: nil,
        productDetails: AmenProductDetails(
            merchantName: "Amazon",
            imageURL: nil,
            isAffiliate: true,
            safetyLabel: nil
        )
    )
    AmenSmartMediaCardRouter(attachment: attachment, onRemove: {})
        .padding()
}

#Preview("Generic Link Card") {
    let attachment = AmenMediaAttachment(
        id: "l1",
        kind: .link,
        sourceURL: "https://thegospelcoalition.org/article/resurrection",
        title: "Shared Link",
        subtitle: "thegospelcoalition.org",
        thumbnailURL: nil,
        accentHex: nil,
        linkDetails: AmenLinkDetails(
            domain: "thegospelcoalition.org",
            ogTitle: "Why the Resurrection Changes Everything",
            ogDescription: "The bodily resurrection of Jesus is the hinge on which all of Christian faith swings.",
            ogImageURL: nil
        )
    )
    AmenSmartMediaCardRouter(attachment: attachment, onRemove: {})
        .padding()
}

#Preview("Loading Skeleton") {
    AmenLinkLoadingCard()
        .padding()
}

#Preview("Attachment Rail") {
    let attachments: [AmenMediaAttachment] = [
        AmenMediaAttachment(
            id: "v1",
            kind: .video,
            sourceURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            title: "Sunday Sermon",
            subtitle: "Grace Church",
            thumbnailURL: nil,
            accentHex: nil,
            videoDetails: AmenVideoDetails(
                channelName: "Grace Church",
                youtubeVideoID: "dQw4w9WgXcQ",
                hasChapters: false
            )
        ),
        AmenMediaAttachment(
            id: "s1",
            kind: .scripture,
            sourceURL: nil,
            title: "Romans 8:28",
            subtitle: "ESV",
            thumbnailURL: nil,
            accentHex: nil,
            scriptureDetails: AmenScriptureDetails(
                reference: "Romans 8:28",
                verseText: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
                translation: "ESV",
                youVersionDeepLink: nil
            )
        ),
        AmenMediaAttachment(
            id: "a1",
            kind: .article,
            sourceURL: "https://thegospelcoalition.org/article/scripture",
            title: "Five Ways to Deepen Your Daily Scripture Reading",
            subtitle: "thegospelcoalition.org",
            thumbnailURL: nil,
            accentHex: nil,
            articleDetails: AmenArticleDetails(
                sourceName: "The Gospel Coalition",
                faviconURL: nil,
                readingTimeMinutes: 5,
                excerpt: "Consistency transforms not just what we know, but who we are."
            )
        ),
    ]
    AmenAttachmentRail(attachments: attachments, onRemove: { _ in })
        .background(Color(.systemGroupedBackground))
}
