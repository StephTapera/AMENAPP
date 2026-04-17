// ThreadLanguageSummaryView.swift
// AMEN App — Accessibility Intelligence Layer (Phase 6)
//
// Collapsible glass card shown at the top of a multilingual comment thread.
// Displays detected languages and offers one-tap "Translate all" action.

import SwiftUI

struct ThreadLanguageSummaryView: View {

    let summary: ThreadLanguageSummary

    @State private var isExpanded = true

    var body: some View {
        if summary.foreignCommentCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Multilingual thread")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.displayText)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)

                        Text("\(summary.foreignCommentCount) comment\(summary.foreignCommentCount == 1 ? "" : "s") in other languages")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
