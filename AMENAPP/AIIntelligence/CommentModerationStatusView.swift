// CommentModerationStatusView.swift
// AMENAPP — Smart Comments Wave 2
//
// Renders the moderation state indicator for a single comment.
// Opaque backgrounds only — these chips are inline with comment text; NO glass on text.
//
// .allowed    → no indicator (comment renders normally)
// .pendingReview → amber "Pending review" capsule
// .limited    → amber "Visible with limits" capsule
// .blocked    → calm non-punitive "This comment was not posted" text
// .removed    → "Removed" text + "Appeal" link
// .appealed   → "Under review" capsule
// .restored   → green "Restored" capsule

import SwiftUI
import Foundation

struct CommentModerationStatusView: View {

    let status: CommentModerationStatus

    /// Called when the user taps "Appeal" on a removed comment.
    var onAppealTapped: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch status {
        case .allowed:
            EmptyView()

        case .pendingReview:
            statusCapsule(
                label: "Pending review",
                color: .amber,
                accessibilityLabel: "This comment is pending safety review"
            )

        case .limited:
            statusCapsule(
                label: "Visible with limits",
                color: .amber,
                accessibilityLabel: "This comment is visible with certain limits applied"
            )

        case .blocked:
            Text("This comment was not posted")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("This comment was not posted")

        case .removed:
            HStack(spacing: 6) {
                Text("Removed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if onAppealTapped != nil {
                    Button(action: { onAppealTapped?() }) {
                        Text("Appeal")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Appeal this removal")
                    }
                    .buttonStyle(.plain)
                }
            }

        case .appealed:
            statusCapsule(
                label: "Under review",
                color: .amber,
                accessibilityLabel: "Your appeal is under review"
            )

        case .restored:
            statusCapsule(
                label: "Restored",
                color: .green,
                accessibilityLabel: "This comment has been restored"
            )
        }
    }

    // MARK: - Capsule Builder

    @ViewBuilder
    private func statusCapsule(
        label: String,
        color: StatusColor,
        accessibilityLabel: String
    ) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(color.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.background(reduceTransparency: reduceTransparency))
            )
            .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Status Color

private enum StatusColor {
    case amber
    case green

    var foreground: Color {
        switch self {
        case .amber: return Color(red: 0.60, green: 0.40, blue: 0.00)
        case .green: return Color(red: 0.10, green: 0.45, blue: 0.10)
        }
    }

    func background(reduceTransparency: Bool) -> Color {
        switch self {
        case .amber: return Color(red: 1.0, green: 0.85, blue: 0.40).opacity(reduceTransparency ? 1.0 : 0.22)
        case .green: return Color(red: 0.70, green: 1.0, blue: 0.70).opacity(reduceTransparency ? 1.0 : 0.22)
        }
    }
}
