import SwiftUI

struct WeeklyAlignmentSummaryView: View {
    @State private var summary: WeeklyAlignmentSummary?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let summary {
                    statRow(title: "Aligned Interactions", value: "\(summary.stats.alignedPercent)%")
                    statRow(title: "Corrections Made", value: "\(summary.stats.correctionsMade)")
                    statRow(title: "Discernment Moments", value: "\(summary.stats.discernmentMoments)")
                    statRow(title: "Blocked / Held", value: "\(summary.stats.blockedOrHeldItems)")
                    statRow(title: "Protection Moments", value: "\(summary.stats.spiritualProtectionMoments ?? 0)")

                    section(title: "Themes", items: summary.topScriptureThemes)
                    section(title: "Suggested Practices", items: summary.suggestedPractices)
                    section(title: "Insights", items: summary.insights)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("No summary is available yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Weekly Alignment")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            summary = try? await BiblicalAlignmentService.shared.getWeeklyAlignmentSummary()
            isLoading = false
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func section(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.76))
            }
        }
    }
}
