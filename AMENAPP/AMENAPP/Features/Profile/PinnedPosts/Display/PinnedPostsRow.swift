// PinnedPostsRow.swift
// AMENAPP — Profile Header v2
//
// Horizontal scroll row of up to 3 glassmorphic pinned post cards.
// Renders nothing when `previews` is empty — callers own the empty state
// (see PinEmptyStateCard for the own-profile empty treatment).

import SwiftUI

// MARK: - PinnedPostsRow

public struct PinnedPostsRow: View {

    public let previews: [PinnedPostPreview]
    public let onTap: (PinnedPostPreview) -> Void

    public init(previews: [PinnedPostPreview], onTap: @escaping (PinnedPostPreview) -> Void) {
        self.previews = previews
        self.onTap = onTap
    }

    public var body: some View {
        if previews.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(previews) { preview in
                        PinnedPostRowCard(preview: preview)
                            .onTapGesture { onTap(preview) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pinned posts")
        }
    }
}

// MARK: - PinnedPostRowCard (private card cell)

private struct PinnedPostRowCard: View {

    let preview: PinnedPostPreview

    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)
    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image (when available)
            if let urlString = preview.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        imagePlaceholder
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
            } else {
                imagePlaceholder
            }

            // Gradient scrim for legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content snippet + type badge
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)

                // Type badge
                Text(typeBadgeLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(amenGold.opacity(0.82))
                    )
                    .accessibilityHidden(true)

                // Content snippet
                Text(preview.content)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            PinBadge()
        }
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Helpers

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.14))
            )
    }

    @ViewBuilder
    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.06), Color.black.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: cardWidth, height: cardHeight)
    }

    private var typeBadgeLabel: String {
        switch preview.type.lowercased() {
        case "prayer":        return "Prayer"
        case "testimonies",
             "testimony":     return "Testimony"
        case "verse":         return "Verse"
        case "opentable":     return "Reflection"
        default:              return "Post"
        }
    }

    private var accessibilityLabel: String {
        "Pinned \(typeBadgeLabel.lowercased()): \(preview.content.prefix(60))"
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let samples: [PinnedPostPreview] = [
        PinnedPostPreview(
            id: "1",
            content: "God has been faithful through every storm. I am a living testimony.",
            type: "testimonies",
            imageURL: nil,
            pinnedAt: Date(),
            authorId: "uid-1"
        ),
        PinnedPostPreview(
            id: "2",
            content: "\"For I know the plans I have for you...\" — Jeremiah 29:11",
            type: "verse",
            imageURL: nil,
            pinnedAt: Date().addingTimeInterval(-86400 * 30),
            authorId: "uid-1"
        ),
        PinnedPostPreview(
            id: "3",
            content: "Lord, heal our land. We need your presence now more than ever.",
            type: "prayer",
            imageURL: nil,
            pinnedAt: Date().addingTimeInterval(-86400 * 90),
            authorId: "uid-1"
        )
    ]

    VStack {
        PinnedPostsRow(previews: samples) { _ in }
        PinnedPostsRow(previews: []) { _ in }
    }
    .padding(.vertical)
    .background(Color(.systemGroupedBackground))
}
#endif
