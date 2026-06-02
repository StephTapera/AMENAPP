// ContentObjectCardView.swift
// AMEN App — Community Around Content OS
//
// Rich card displayed whenever a user shares a link in a post or message.
// White-first design with Liquid Glass "Open" pill.
// Supports loading/placeholder state and full VoiceOver accessibility.

import SwiftUI

// MARK: - ContentObjectCardView

/// Renders a rich content card for a ContentObject.
/// Use `onTap` to handle the "Open" action (e.g., open URL in SFSafariViewController).
struct ContentObjectCardView: View {

    // MARK: - Inputs

    let contentObject: ContentObject
    let onTap: () -> Void

    // MARK: - State

    @State private var isLoaded: Bool = false

    // MARK: - Layout constants

    private enum Layout {
        static let thumbnailSize: CGFloat = 72
        static let thumbnailCornerRadius: CGFloat = 10
        static let cardCornerRadius: CGFloat = 16
        static let cardPadding: CGFloat = 14
        static let cardShadowRadius: CGFloat = 8
        static let cardShadowY: CGFloat = 2
        static let kindPillHPadding: CGFloat = 8
        static let kindPillVPadding: CGFloat = 4
        static let openPillHPadding: CGFloat = 16
        static let openPillVPadding: CGFloat = 8
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // — Top row: thumbnail + metadata
            HStack(alignment: .top, spacing: 12) {
                thumbnailView
                metadataColumn
            }

            // — Purity badge (hidden for .unreviewed)
            if contentObject.purityRating != .unreviewed {
                purityBadge(for: contentObject.purityRating)
            }

            // — Community stats row
            communityStatsRow

            Divider()
                .background(Color(.separator))

            // — Open pill button
            HStack {
                Spacer()
                openPillButton
                Spacer()
            }
        }
        .padding(Layout.cardPadding)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
        .shadow(
            color: Color(.label).opacity(0.08),
            radius: Layout.cardShadowRadius,
            x: 0,
            y: Layout.cardShadowY
        )
        .redacted(reason: isLoaded ? [] : .placeholder)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .onAppear {
            withAnimation(AppAnimation.fade) {
                isLoaded = true
            }
        }
    }

    // MARK: - Subviews

    private var thumbnailView: some View {
        Group {
            if let thumbnailURLString = contentObject.thumbnailURL,
               let url = URL(string: thumbnailURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        thumbnailPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        thumbnailPlaceholder
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: Layout.thumbnailCornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: contentObject.kind.systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Kind pill
            kindPill

            // Title
            Text(contentObject.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Subtitle
            if let subtitle = contentObject.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindPill: some View {
        HStack(spacing: 4) {
            Image(systemName: contentObject.kind.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(contentObject.kind.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(kindPillColor(for: contentObject.kind))
        .padding(.horizontal, Layout.kindPillHPadding)
        .padding(.vertical, Layout.kindPillVPadding)
        .background(
            kindPillColor(for: contentObject.kind).opacity(0.12)
        )
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func purityBadge(for rating: PurityRating) -> some View {
        let color = purityColor(for: rating)
        HStack(spacing: 5) {
            Image(systemName: rating.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(rating.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(rating == .notRecommended ? .white : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            rating == .notRecommended
                ? AnyShapeStyle(color)
                : AnyShapeStyle(color.opacity(0.15))
        )
        .clipShape(Capsule())
        .accessibilityLabel("\(rating.label) content")
        .withAnimation(AppAnimation.stateChange)
    }

    private var communityStatsRow: some View {
        HStack(spacing: 16) {
            statLabel(
                systemImage: "bubble.left.fill",
                count: contentObject.discussionCount,
                label: "discussions"
            )
            statLabel(
                systemImage: "hands.sparkles.fill",
                count: contentObject.prayerCount,
                label: "prayers"
            )
            statLabel(
                systemImage: "star.bubble.fill",
                count: contentObject.testimonyCount,
                label: "testimonies"
            )
            Spacer()
        }
    }

    private func statLabel(systemImage: String, count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
            Text(formattedCount(count))
                .font(.system(size: 12))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .accessibilityLabel("\(count) \(label)")
    }

    private var openPillButton: some View {
        Button(action: {
            withAnimation(AppAnimation.stateChange) {
                onTap()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Open")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color(.label))
            .padding(.horizontal, Layout.openPillHPadding)
            .padding(.vertical, Layout.openPillVPadding)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(contentObject.title)")
        .accessibilityHint("Opens this \(contentObject.kind.displayName.lowercased()) in your browser")
    }

    // MARK: - Accessibility

    private var voiceOverLabel: String {
        var parts: [String] = [contentObject.title, contentObject.kind.displayName]
        if let subtitle = contentObject.subtitle {
            parts.append(subtitle)
        }
        if contentObject.purityRating != .unreviewed {
            parts.append(contentObject.purityRating.label)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func kindPillColor(for kind: ContentObjectKind) -> Color {
        switch kind {
        case .song:          return Color(hex: "#8B5CF6") // violet
        case .podcast:       return Color(hex: "#F59E0B") // amber
        case .book:          return Color(hex: "#3B82F6") // blue
        case .bibleVerse:    return Color(hex: "#10B981") // emerald
        case .sermon:        return Color(hex: "#6366F1") // indigo
        case .video:         return Color(hex: "#EF4444") // red
        case .course:        return Color(hex: "#0EA5E9") // sky
        case .event:         return Color(hex: "#F97316") // orange
        case .prayerRequest: return Color(hex: "#EC4899") // pink
        case .article:       return Color(.secondaryLabel)
        case .testimony:     return Color(hex: "#14B8A6") // teal
        case .userPost:      return Color(hex: "#64748B") // slate
        }
    }

    private func purityColor(for rating: PurityRating) -> Color {
        switch rating {
        case .familySafe:     return Color(hex: "#10B981") // green
        case .someConcerns:   return Color(hex: "#F59E0B") // yellow
        case .notRecommended: return Color(hex: "#EF4444") // red
        case .unreviewed:     return Color(.secondaryLabel)
        }
    }

    private func formattedCount(_ count: Int) -> String {
        switch count {
        case 0 ..< 1_000:
            return "\(count)"
        case 1_000 ..< 1_000_000:
            let k = Double(count) / 1_000
            return String(format: k >= 10 ? "%.0fK" : "%.1fK", k)
        default:
            let m = Double(count) / 1_000_000
            return String(format: "%.1fM", m)
        }
    }
}

// MARK: - View + animation helper

private extension View {
    /// Applies a named AppAnimation via `withAnimation` for state-driven transitions.
    @discardableResult
    func withAnimation(_ animation: Animation) -> some View {
        self.transaction { $0.animation = animation }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Loaded — Song") {
    let song = ContentObject(
        kind: .song,
        source: .spotify,
        title: "Way Maker",
        subtitle: "Sinach · Spotify",
        thumbnailURL: nil,
        rawURL: "https://open.spotify.com/track/abc123",
        discussionCount: 1_247,
        prayerCount: 834,
        testimonyCount: 312,
        purityRating: .familySafe
    )
    ContentObjectCardView(contentObject: song, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Not Recommended — Article") {
    let article = ContentObject(
        kind: .article,
        source: .unknown,
        title: "Controversial Opinion Piece on Faith",
        subtitle: "example.com",
        rawURL: "https://example.com/article",
        discussionCount: 42,
        prayerCount: 5,
        testimonyCount: 1,
        purityRating: .notRecommended
    )
    ContentObjectCardView(contentObject: article, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Bible Verse") {
    let verse = ContentObject(
        kind: .bibleVerse,
        source: .bibleRef,
        title: "John 3:16",
        subtitle: "For God so loved the world...",
        rawURL: "John 3:16",
        discussionCount: 8_920,
        prayerCount: 4_100,
        testimonyCount: 2_300,
        purityRating: .familySafe
    )
    ContentObjectCardView(contentObject: verse, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Loading / Placeholder") {
    let placeholder = ContentObject(
        kind: .podcast,
        source: .podcast,
        title: "Loading…",
        rawURL: "https://podcasts.apple.com/episode/123"
    )
    ContentObjectCardView(contentObject: placeholder, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .redacted(reason: .placeholder)
}
#endif
