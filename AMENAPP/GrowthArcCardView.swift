//
//  GrowthArcCardView.swift
//  AMENAPP
//
//  Glass card displaying a single AI-detected growth arc.
//  Width: 200pt fixed. Slots into a horizontal ScrollView in LongitudinalSelfView.
//

import SwiftUI

struct GrowthArcCardView: View {

    let arc: GrowthArc

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Glass card background ────────────────────────────────────
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.purple.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )

            // ── Content ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                // SF Symbol icon
                Image(systemName: arc.sfSymbol)
                    .font(.systemScaled(28, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.purple)
                    .padding(.bottom, 14)

                // From → To
                VStack(alignment: .leading, spacing: 4) {
                    Text(arc.fromState)
                        .font(AMENFont.regular(14))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "arrow.right")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color.purple)

                    Text(arc.toState)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.bottom, 10)

                // Date range
                if let start = arc.startDate {
                    let end = arc.endDate
                    Text(dateRangeString(start: start, end: end))
                        .font(AMENFont.regular(11))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.bottom, 8)
                }

                // Summary
                Text(arc.summary)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(width: 200)
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    // MARK: - Helpers

    private func dateRangeString(start: Date, end: Date?) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        let startStr = fmt.string(from: start)
        if let end {
            return "\(startStr) – \(fmt.string(from: end))"
        }
        return "\(startStr) – Present"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Growth Arc Card") {
    HStack(spacing: 12) {
        ForEach(GrowthArc.samples) { arc in
            GrowthArcCardView(arc: arc)
        }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
#endif
