// CreatorStudioInsightCard.swift
// AMENAPP — Creator Studio / Wave 5
//
// One stewardship insight card.
// ANTI-VANITY GUARDRAIL:
// No chart. No sparkline. Numbers in narrative sentences only.
// The icon + narrative text are the hero, never a metric value.

import SwiftUI

struct CreatorStudioInsightCard: View {

    let insight: StudioInsight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconView
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.narrativeText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let metricValue = insight.supportingMetricValue,
                   let metricContext = insight.supportingMetricContext {
                    // Supporting metric shown ONLY as a contextual sentence, never as headline.
                    Text("(\(metricValue) \(metricContext))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.narrativeText). \(insight.periodLabel).")
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconBackground)
                .frame(width: 36, height: 36)

            Image(systemName: iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconForeground)
        }
    }

    private var iconName: String {
        switch insight.kind {
        case .formationTrend:    return "checkmark.circle.fill"
        case .searchDiscovery:   return "magnifyingglass"
        case .passageResonance:  return "book.fill"
        case .stewardshipSummary: return "person.2.fill"
        }
    }

    private var iconBackground: Color {
        switch insight.kind {
        case .formationTrend:    return Color.accentColor.opacity(0.12)
        case .searchDiscovery:   return Color.purple.opacity(0.10)
        case .passageResonance:  return Color.accentColor.opacity(0.12)
        case .stewardshipSummary: return Color.purple.opacity(0.10)
        }
    }

    private var iconForeground: Color {
        switch insight.kind {
        case .formationTrend:    return Color.accentColor
        case .searchDiscovery:   return Color.purple
        case .passageResonance:  return Color.accentColor
        case .stewardshipSummary: return Color.purple
        }
    }
}
