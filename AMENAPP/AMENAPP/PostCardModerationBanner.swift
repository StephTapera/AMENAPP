// PostCardModerationBanner.swift
// AMENAPP
//
// Standalone display-only banner shown on the author's own posts when
// flaggedForReview or removed. No state mutations — reads only.

import SwiftUI

// MARK: - PostCardModerationBanner

struct PostCardModerationBanner: View {
    let flaggedForReview: Bool
    let isRemoved: Bool

    var body: some View {
        if flaggedForReview {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Under review")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.08))
        } else if isRemoved {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.red)
                Text("Removed — violated community guidelines")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.08))
        }
    }
}
