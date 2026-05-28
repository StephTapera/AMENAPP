import SwiftUI

// MARK: - ReactorReel
// Horizontal reel of avatar+emoji pairs showing the first 12 reactors.
// Backed by a glass capsule strip. Shows "+N more" overflow pill.

@MainActor
struct ReactorReel: View {
    var reactions: [MediaReaction]

    private let maxVisible = 12

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var visibleReactions: [MediaReaction] {
        Array(reactions.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, reactions.count - maxVisible)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(visibleReactions) { reaction in
                    ReactorAvatarCell(reaction: reaction)
                }

                if overflowCount > 0 {
                    overflowPill
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background { reelBackground }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            overflowCount > 0
                ? "\(reactions.count) reactions"
                : "\(reactions.count) reaction\(reactions.count == 1 ? "" : "s")"
        )
    }

    private var overflowPill: some View {
        Text("+\(overflowCount) more")
            .font(.caption.weight(.medium))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.75)
                    }
            }
            .accessibilityLabel("\(overflowCount) more reactors")
    }

    @ViewBuilder
    private var reelBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
            Capsule(style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.36), lineWidth: 0.75)
                }
        }
    }
}

// MARK: - ReactorAvatarCell

@MainActor
private struct ReactorAvatarCell: View {
    let reaction: MediaReaction

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar
            AsyncImage(url: nil) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Color(.systemFill))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure:
                    Circle()
                        .fill(Color(.systemFill))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                @unknown default:
                    Circle().fill(Color(.systemFill))
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())

            // Emoji overlay at bottom-trailing
            Text(emojiChar(for: reaction.type))
                .font(.system(size: 10))
                .offset(x: 2, y: 2)
        }
        .frame(width: 28, height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityLabel(for: reaction.type)) reaction")
    }

    private func emojiChar(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "❤️"
        case .laugh:   return "😂"
        case .prayer:  return "🙏"
        case .fire:    return "🔥"
        case .cross:   return "✝️"
        case .custom:  return reaction.emoji ?? "😊"
        }
    }

    private func accessibilityLabel(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "heart"
        case .laugh:   return "laugh"
        case .prayer:  return "prayer"
        case .fire:    return "fire"
        case .cross:   return "cross"
        case .custom:  return "custom"
        }
    }
}
