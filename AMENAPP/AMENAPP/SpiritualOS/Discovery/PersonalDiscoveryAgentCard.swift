// PersonalDiscoveryAgentCard.swift
// AMEN App — Spiritual OS / Community Discovery
//
// Promotional card for the Personal Discovery Agent feature.
// Shown inline in the discovery rails vertical stack.
// Free users see a lock + upgrade CTA; AMEN+ users see "Open Agent".
//
// Design rules (C3):
//   • Background: Color(.secondarySystemBackground) — NO glass, NO dark panel
//   • Accent: Color.accentColor — NO gold, NO purple
//   • Fonts: Dynamic Type only

import SwiftUI

// MARK: - PersonalDiscoveryAgentCard

struct PersonalDiscoveryAgentCard: View {

    let hasAccess: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon well
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: hasAccess ? "sparkles" : "lock.fill")
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityHidden(true)

                // Text block
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Personal Discovery Agent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if !hasAccess {
                            Text("AMEN+")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }

                    Text(
                        hasAccess
                            ? "Your AI-powered guide to the right communities, studies, and people."
                            : "Upgrade to AMEN+ to unlock AI-powered community discovery."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Personal Discovery Agent")
        .accessibilityHint(
            hasAccess
                ? "Opens your AI-powered discovery guide. Double-tap to open."
                : "Requires AMEN Plus subscription. Double-tap to upgrade."
        )
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview("Access granted") {
    PersonalDiscoveryAgentCard(hasAccess: true, onTap: {})
        .padding(20)
}

#Preview("Locked — free tier") {
    PersonalDiscoveryAgentCard(hasAccess: false, onTap: {})
        .padding(20)
}
