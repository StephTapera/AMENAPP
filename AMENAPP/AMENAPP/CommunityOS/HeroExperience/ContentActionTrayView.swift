// ContentActionTrayView.swift
// AMEN App — Community Around Content OS › Dynamic Hero Experience
//
// The floating action tray pinned at the bottom of MediaHeroView.
// One primary action gets .amenGlassEffect() — all others are standard icon buttons.

import SwiftUI
import Foundation

// MARK: - ContentActionTrayView

struct ContentActionTrayView: View {

    let contentObject: ContentObject
    let onPray: () -> Void
    let onDiscuss: () -> Void
    let onStudy: () -> Void
    let onTestify: () -> Void
    let onSaveToChurchNotes: () -> Void
    let onJoinCommunity: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TrayButton(
                icon: "hands.sparkles",
                label: "Pray",
                isPrimary: primaryAction == .prayer,
                action: {
                    hapticTap()
                    onPray()
                }
            )
            .accessibilityLabel("Pray")
            .accessibilityHint("Add your prayer for this content")

            TrayButton(
                icon: "bubble.left.and.bubble.right",
                label: "Discuss",
                isPrimary: primaryAction == .discussion,
                action: {
                    hapticTap()
                    onDiscuss()
                }
            )
            .accessibilityLabel("Discuss")
            .accessibilityHint("Join the discussion about this content")

            TrayButton(
                icon: "book",
                label: "Study",
                isPrimary: primaryAction == .study,
                action: {
                    hapticTap()
                    onStudy()
                }
            )
            .accessibilityLabel("Study")
            .accessibilityHint("Open a Bible study connected to this content")

            TrayButton(
                icon: "text.quote",
                label: "Testify",
                isPrimary: false,
                action: {
                    hapticTap()
                    onTestify()
                }
            )
            .accessibilityLabel("Testify")
            .accessibilityHint("Share how this content impacted your faith")

            TrayButton(
                icon: "note.text",
                label: "Save",
                isPrimary: false,
                action: {
                    hapticTap()
                    onSaveToChurchNotes()
                }
            )
            .accessibilityLabel("Save to Church Notes")
            .accessibilityHint("Save this content to your church notes")

            TrayButton(
                icon: "person.3",
                label: "Community",
                isPrimary: false,
                action: {
                    hapticTap()
                    onJoinCommunity()
                }
            )
            .accessibilityLabel("Community")
            .accessibilityHint("View and join the community around this content")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: Color(.label).opacity(0.12), radius: 16, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }

    // MARK: Primary action logic

    /// The most spiritually relevant action for this content kind.
    private var primaryAction: CommunityLayer {
        switch contentObject.kind {
        case .prayerRequest:    return .prayer
        case .bibleVerse:       return .study
        case .sermon, .course:  return .study
        case .song:             return .worship
        default:                return .discussion
        }
    }

    private func hapticTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - TrayButton

private struct TrayButton: View {
    let icon: String
    let label: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(20, weight: isPrimary ? .semibold : .regular))
                    .foregroundStyle(isPrimary ? Color.accentColor : Color(.secondaryLabel))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isPrimary ? Color.accentColor : Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            // Liquid Glass only on the single highlighted primary button.
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.08))
                        .amenGlassEffect()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Song — Discuss primary") {
    ZStack {
        Color(.secondarySystemBackground).ignoresSafeArea()
        ContentActionTrayView(
            contentObject: ContentObject(
                kind: .song,
                source: .spotify,
                title: "Goodness of God",
                rawURL: "https://open.spotify.com/track/example"
            ),
            onPray:             { },
            onDiscuss:          { },
            onStudy:            { },
            onTestify:          { },
            onSaveToChurchNotes:{ },
            onJoinCommunity:    { }
        )
    }
}

#Preview("Prayer Request — Pray primary") {
    ZStack {
        Color(.secondarySystemBackground).ignoresSafeArea()
        ContentActionTrayView(
            contentObject: ContentObject(
                kind: .prayerRequest,
                source: .amenPost,
                title: "Healing for my family",
                rawURL: "amen://post/123"
            ),
            onPray:             { },
            onDiscuss:          { },
            onStudy:            { },
            onTestify:          { },
            onSaveToChurchNotes:{ },
            onJoinCommunity:    { }
        )
    }
}
#endif
