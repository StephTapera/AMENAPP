// ActionBadge.swift
// AMENAPP — Notifications/Views
//
// Small 28×28 circular badge showing the action icon on a gold gradient.
// Used overlapping the bottom-right corner of an avatar in AmenNotificationCard.
//
// AmenAction is the canonical type from Notifications/Engine/NotifContext.swift.
// The local stub below must be removed once the merge with NotifContext.swift
// is confirmed. At that point delete the `#if AMENACTION_STUB` block.

import SwiftUI

// MARK: - ActionBadge

struct ActionBadge: View {

    let action: AmenAction

    var body: some View {
        ZStack {
            Circle()
                .fill(NotifGlassTokens.goldGradient)
                .frame(width: 28, height: 28)

            // Inner specular highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.30), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 28, height: 28)
                .allowsHitTesting(false)

            Image(systemName: action.systemImageName)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.40), lineWidth: 1.5)
        }
        .shadow(color: Color.accentColor.opacity(0.45), radius: 6, x: 0, y: 3)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHidden(true) // decorative — parent supplies the label
    }
}

// MARK: - AmenAction helpers

extension AmenAction {

    /// SF Symbol name for badge icon.
    var systemImageName: String {
        switch self {
        case .amen:   return "hands.sparkles.fill"
        case .repost: return "arrow.2.squarepath"
        case .save:   return "bookmark.fill"
        case .join:   return "person.crop.circle.badge.plus"
        case .give:   return "heart.fill"
        }
    }

    /// Human-readable accessibility label.
    var accessibilityLabel: String {
        switch self {
        case .amen:   return "Amen"
        case .repost: return "Repost"
        case .save:   return "Save"
        case .join:   return "Join"
        case .give:   return "Give"
        }
    }

    /// Primary CTA copy used on the card button.
    var primaryButtonTitle: String {
        switch self {
        case .amen:   return "Amen"
        case .repost: return "Got it"
        case .save:   return "Got it"
        case .join:   return "Join now"
        case .give:   return "Got it"
        }
    }
}

// MARK: - Preview

#Preview("ActionBadge — all actions") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()

        HStack(spacing: 20) {
            ForEach(AmenAction.allCases, id: \.rawValue) { action in
                VStack(spacing: 8) {
                    ActionBadge(action: action)
                    Text(action.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding()
    }
}
