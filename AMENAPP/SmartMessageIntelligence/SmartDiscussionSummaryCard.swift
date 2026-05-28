import SwiftUI

struct SmartDiscussionSummaryCard: View {
    let insight: SmartDiscussionInsight?
    let isLoading: Bool
    var onSummarize: () -> Void
    var onRefresh: () -> Void
    var onSaveToStudy: () -> Void
    var onShare: () -> Void
    var onAskBerean: () -> Void

    var body: some View {
        if AMENFeatureFlags.shared.discussionSummariesEnabled {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Summary", systemImage: "text.quote")
                        .font(.headline)
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                }
                if let insight {
                    Text(insight.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    sections(insight)
                    controls(hasSummary: true)
                } else {
                    Text("No summary has been created for this discussion yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    controls(hasSummary: false)
                }
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
        }
    }

    private func sections(_ insight: SmartDiscussionInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summarySection("Key Takeaways", items: insight.keyTakeaways)
            summarySection("Scriptures Mentioned", items: insight.scriptures)
            summarySection("Prayer Requests", items: insight.prayerRequests)
            summarySection("Action Items", items: insight.actionItems)
            summarySection("Unresolved Questions", items: insight.unresolvedQuestions)
            summarySection("Suggested Next Steps", items: insight.suggestedNextActions.map(\.title))
        }
    }

    private func summarySection(_ title: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(items.prefix(5), id: \.self) { item in
                        Text(item).font(.caption).foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private func controls(hasSummary: Bool) -> some View {
        HStack(spacing: 10) {
            Button(hasSummary ? "Refresh" : "Summarize", systemImage: hasSummary ? "arrow.clockwise" : "sparkles") {
                hasSummary ? onRefresh() : onSummarize()
            }
            if hasSummary {
                Button("Study", systemImage: "book.closed", action: onSaveToStudy)
                Button("Share", systemImage: "square.and.arrow.up", action: onShare)
                Button("Berean", systemImage: "sparkles", action: onAskBerean)
            }
        }
        .buttonStyle(.bordered)
    }
}
