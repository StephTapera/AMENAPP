import SwiftUI

struct ChurchNotesReviewSummaryView: View {
    let summary: ChurchNoteReviewSummary

    var body: some View {
        HStack(spacing: 0) {
            item(summary.highlightCount, "Highlights")
            item(summary.prayerCount, "Prayers")
            item(summary.actionCount, "Actions")
            item(summary.scriptureCount, "Scripture")
            item(summary.quoteCount, "Quotes")
        }
        .padding(.vertical, 10)
        .churchNotesGlassCard()
    }

    private func item(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.systemScaled(16, weight: .semibold, design: .rounded))
            Text(label)
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
