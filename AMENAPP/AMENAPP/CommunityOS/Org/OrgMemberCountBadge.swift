// OrgMemberCountBadge.swift
// AMEN Community OS — Org OS (A9)
//
// Private count badge for internal/admin surfaces ONLY.
// This badge must NEVER appear on any public-facing profile screen.
// It is strictly for org admins in the admin/settings context.
//
// Privacy contract (C1):
//   - memberCount is never shown comparatively on any public UI
//   - No leaderboard, no "top orgs by members" ranking ever surfaces this value
//   - This component is gated behind an adminContext flag as a compile-time safety mechanism
//
// Design rules (C3): system colors only, no amenGold/hex.

import SwiftUI

// MARK: - OrgMemberCountBadge

/// Internal-only member count badge.
/// - IMPORTANT: Only render this view inside admin/settings surfaces.
///   Never embed in a public-facing profile or discovery feed.
struct OrgMemberCountBadge: View {

    /// The member count value. Pass nil to show a loading state.
    let count: Int?

    /// Must be `true` — this acts as a guard to prevent accidental
    /// use in public surfaces. Set to `isOrgAdmin` from your view model.
    let isAdminContext: Bool

    // MARK: Body

    var body: some View {
        if isAdminContext {
            badgeContent
        }
        // Renders nothing when isAdminContext is false — safe default
    }

    @ViewBuilder
    private var badgeContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            if let count {
                Text(formattedCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text("members")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\(formattedCount($0)) members (admin view)" } ?? "Member count loading")
        .accessibilityHint("This count is only visible to org admins")
    }

    private func formattedCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Preview

#Preview("Org Member Count Badge — Admin Only") {
    VStack(spacing: 16) {
        Text("Shown only in admin contexts:")
            .font(.subheadline)
            .foregroundStyle(Color(uiColor: .secondaryLabel))

        OrgMemberCountBadge(count: 1_234, isAdminContext: true)
        OrgMemberCountBadge(count: 98_000, isAdminContext: true)
        OrgMemberCountBadge(count: nil, isAdminContext: true)

        Divider()

        Text("Renders nothing in public context:")
            .font(.subheadline)
            .foregroundStyle(Color(uiColor: .secondaryLabel))

        OrgMemberCountBadge(count: 1_234, isAdminContext: false)
            .border(Color.red.opacity(0.3)) // shows empty space in preview
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
