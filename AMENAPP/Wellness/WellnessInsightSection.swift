import SwiftUI

// MARK: - Rhythm Card

struct WellnessRhythmCard: View {
    let rhythm: WellnessRhythmContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME & RHYTHM")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                    Text("Different surface, different smarts")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(rhythm.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.22, blue: 0.68), Color(red: 0.18, green: 0.12, blue: 0.48)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: rhythmIcon)
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(rhythm.contextNote)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                    .stroke(.white.opacity(0.26), lineWidth: 1)
            )
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }

    private var rhythmIcon: String {
        switch rhythm {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        case .sunday:    return "cross.fill"
        case .lent:      return "leaf.fill"
        }
    }
}

// MARK: - Insight Section

struct WellnessInsightSection: View {
    @ObservedObject var insightEngine: WellnessLocalInsightEngine

    var body: some View {
        VStack(spacing: 12) {
            WellnessLocalInsightCard(insightEngine: insightEngine)
            WellnessSafetyGuardrailsCard()
        }
    }
}

// MARK: - Local Insight Card

private struct WellnessLocalInsightCard: View {
    @ObservedObject var insightEngine: WellnessLocalInsightEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUIET LOCAL INSIGHT")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                    Text("Private by default")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        insightEngine.isEnabled.toggle()
                    }
                } label: {
                    Text(insightEngine.isEnabled ? "On-device on" : "Off")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(insightEngine.isEnabled ? Color(red: 0.06, green: 0.30, blue: 0.55) : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(insightEngine.isEnabled ? Color(red: 0.86, green: 0.93, blue: 0.99) : Color(.systemBackground))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
                .accessibilityLabel(insightEngine.isEnabled ? "On-device insight is on. Tap to turn off." : "On-device insight is off. Tap to turn on.")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: insightEngine.isEnabled ? "lock.fill" : "lock.slash.fill")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(insightEngine.isEnabled ? insightEngine.currentInsight : "Local insight is disabled. No pattern summaries will appear here.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                    .stroke(.white.opacity(0.26), lineWidth: 1)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: insightEngine.isEnabled)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }
}

// MARK: - Safety Guardrails Card

private struct WellnessSafetyGuardrailsCard: View {
    private let rules: [(icon: String, text: String)] = [
        ("nosign", "No streaks, badges, leaderboards, or shareable progress."),
        ("person.slash.fill", "No public feed of wellness activity."),
        ("chart.line.downtrend.xyaxis", "No daily clinical self-scoring loops."),
        ("fork.knife", "No fasting tools without disordered-eating safeguards."),
        ("cross.fill", "Berean supports professional care and never replaces it."),
        ("bell.slash.fill", "At most one gentle opt-in weekly nudge."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SAFETY GUARDRAILS")
                .font(.custom("OpenSans-SemiBold", size: 10))
                .tracking(2.2)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(rules, id: \.text) { rule in
                    HStack(spacing: 12) {
                        Image(systemName: rule.icon)
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(rule.text)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.26), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }
}
