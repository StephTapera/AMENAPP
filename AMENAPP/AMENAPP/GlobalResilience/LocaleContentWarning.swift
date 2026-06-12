// LocaleContentWarning.swift
// AMEN — Global Resilience System
// Compact non-dismissable badge shown when a post is under moderation review.
// Displayed when post.moderationStatus == "escalated" or "quarantined".

import SwiftUI

// MARK: - LocaleContentWarning

/// Compact orange glass-pill badge indicating that content is awaiting
/// human moderation review. Non-dismissable — the caller controls visibility
/// by passing the post's `moderationStatus` string.
///
/// - Parameter status: The post's `moderationStatus` field.
///   Renders only when `status` is `"escalated"` or `"quarantined"`.
struct LocaleContentWarning: View {

    // MARK: Input

    let status: String

    // MARK: Constants

    private static let visibleStatuses: Set<String> = ["escalated", "quarantined"]

    // MARK: Body

    var body: some View {
        if Self.visibleStatuses.contains(status) {
            badgeContent
        }
    }

    // MARK: Badge Layout

    private var badgeContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)

            Text("Content under review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
                .glassEffect()
        )
        .overlay(
            Capsule()
                .stroke(Color.orange.opacity(0.40), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Content under review")
        .accessibilityHint("This post is being reviewed by a human moderator")
    }
}

// MARK: - Preview

#Preview("LocaleContentWarning — escalated") {
    VStack(spacing: 16) {
        LocaleContentWarning(status: "escalated")
        LocaleContentWarning(status: "quarantined")
        // Approved status → renders nothing
        LocaleContentWarning(status: "approved")
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
}
