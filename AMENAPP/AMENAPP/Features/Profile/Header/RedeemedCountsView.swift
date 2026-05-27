import SwiftUI

public struct RedeemedCountsView: View {
    public let metrics: ProfileMetrics
    public let onTapMetric: (RedeemedMetricType) -> Void

    public enum RedeemedMetricType {
        case peopleDiscipled, versesShared, prayersOffered
    }

    public var body: some View {
        HStack(spacing: 0) {
            metricButton(value: metrics.peopleDiscipled, label: "Discipled", type: .peopleDiscipled)
            divider
            metricButton(value: metrics.versesShared, label: "Verses", type: .versesShared)
            divider
            metricButton(value: metrics.prayersOffered, label: "Prayers", type: .prayersOffered)
        }
        .accessibilityElement(children: .contain)
    }

    private func metricButton(value: Int, label: String, type: RedeemedMetricType) -> some View {
        Button { onTapMetric(type) } label: {
            VStack(spacing: 2) {
                Text(formattedCount(value))
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint("Double-tap to view details")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 0.5, height: 32)
    }

    private func formattedCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
