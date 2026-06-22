// RhythmInsightCard.swift — Features/Intelligence/RhythmEngine
// Compact SwiftUI card displaying the user's formation rhythm.
// Free tier. Shown only when ctx_rhythm_engine_enabled and consent.activityToRhythm.

import SwiftUI

struct RhythmInsightCard: View {
    @ObservedObject private var engine = RhythmEngineService.shared
    @ObservedObject private var consent = ConsentStore.shared

    var body: some View {
        Group {
            if ContextIntelligenceFlags.rhythmEngine,
               consent.isEnabled(.activityToRhythm),
               let rhythm = engine.rhythm {
                cardContent(rhythm: rhythm)
            }
        }
    }

    @ViewBuilder
    private func cardContent(rhythm: FormationRhythm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Formation Rhythm", systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 20) {
                // streak count hidden per constitution — vanityMetricsAlwaysHidden
                stat(value: "Consistent", label: "this week")
                stat(value: "\(rhythm.weeklyCount)", label: "sessions")
                if let hour = rhythm.preferredHour {
                    stat(value: hourLabel(hour), label: "best time")
                }
            }

            if let days = rhythm.daysSinceLastSignal, days > 2 {
                Text("Last activity \(Int(days)) days ago — you've got this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let ampm = hour < 12 ? "am" : "pm"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour)\(ampm)"
    }
}
