// CatchMeUpBanner.swift
// AMENAPP — MessagingOS
// Collapsible glass banner for thread catch-up summaries.

import SwiftUI

struct CatchMeUpBanner: View {
    let unreadCount: Int
    let onSummarize: () async -> String
    @State private var state: BannerState = .collapsed
    @State private var summary: String = ""
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum BannerState { case collapsed, loading, expanded }

    var body: some View {
        VStack(spacing: 0) {
            // Banner row
            Button {
                guard state == .collapsed else { return }
                Task { await loadSummary() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.amenGold)
                        .symbolEffect(.pulse, isActive: state == .loading && !reduceMotion)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Catch Me Up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(unreadCount) messages since you were last here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if state == .loading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if state == .expanded {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                state = .collapsed
                                summary = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss summary")
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .disabled(state != .collapsed)
            .accessibilityLabel("Catch me up on \(unreadCount) messages")
            .accessibilityHint("Double tap to generate a summary")

            // Expanded summary card
            if state == .expanded, !summary.isEmpty {
                Divider().opacity(0.3)
                ScrollView {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .background {
            if reduceTransparency {
                Color(.secondarySystemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.amenGold.opacity(0.3), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: state)
    }

    private func loadSummary() async {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { state = .loading }
        let result = await onSummarize()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35)) {
            summary = result
            state = .expanded
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CatchMeUpBanner(unreadCount: 42) {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "The group discussed Sunday's sermon on Psalm 23. Three members shared prayer requests about health challenges. Pastor James announced a new Bible study series starting next week on the book of James. There was enthusiastic discussion about the upcoming community service day on the 15th."
        }
        Spacer()
    }
    .padding()
}
