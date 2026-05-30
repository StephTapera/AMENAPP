//
//  CreatePostAudienceHintRow.swift
//  AMENAPP
//
//  Optional audience hint selector inside CreatePostView.
//  Helps HeyFeed route posts to the most receptive readers.
//

import SwiftUI

// MARK: - Audience Hint

struct AudienceHint: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
}

extension AudienceHint {
    static let allHints: [AudienceHint] = [
        AudienceHint(id: "encouragement_seekers", label: "Seeking encouragement", icon: "heart"),
        AudienceHint(id: "prayer_community",       label: "Prayer community",      icon: "hands.sparkles"),
        AudienceHint(id: "local_community",        label: "Local community",       icon: "mappin.circle"),
        AudienceHint(id: "scripture_readers",      label: "Scripture readers",     icon: "book.closed"),
        AudienceHint(id: "open_discussion",        label: "Open discussion",       icon: "bubble.left.and.bubble.right"),
    ]
}

// MARK: - Row View

struct CreatePostAudienceHintRow: View {
    @Binding var selectedHint: AudienceHint?

    var body: some View {
        Group {
            if let hint = selectedHint {
                selectedStateRow(hint)
            } else {
                pickerRow
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78)), value: selectedHint?.id)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Picker

    private var pickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who is this for?")
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AudienceHint.allHints) { hint in
                        AudienceHintPill(hint: hint) {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                                selectedHint = hint
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Selected State

    private func selectedStateRow(_ hint: AudienceHint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: hint.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Text(hint.label)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                    selectedHint = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color(.systemGray5)))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove audience hint")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Removes the selected audience hint")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Audience Hint Pill

private struct AudienceHintPill: View {
    let hint: AudienceHint
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: hint.icon)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
                Text(hint.label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Selects \(hint.label) as the audience for your post")
    }
}
