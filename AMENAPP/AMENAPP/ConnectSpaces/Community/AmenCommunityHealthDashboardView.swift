// AmenCommunityHealthDashboardView.swift
// AMEN ConnectSpaces — Private Host-Only Health Dashboard
// Built 2026-06-03
//
// Engagement QUALITY metrics only. No public vanity numbers.
// Calls CF `getSpaceHealthMetrics` via AmenRelationshipIntelligenceService.
// Vitality gauge drawn with SwiftUI Canvas arc (no external dependencies).

import SwiftUI

// MARK: - ViewModel

@MainActor
final class AmenCommunityHealthDashboardViewModel: ObservableObject {
    @Published var metrics: SpaceHealthMetrics?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let spaceId: String
    private let service = AmenRelationshipIntelligenceService.shared

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            metrics = try await service.fetchHealthMetrics(spaceId: spaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Vitality arc gauge

private struct VitalityGauge: View {
    let score: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var arcColor: Color {
        switch score {
        case 70...: return Color(red: 0.22, green: 0.75, blue: 0.45)  // green
        case 40..<70: return Color(hex: "D9A441")                       // gold
        default: return Color(red: 0.80, green: 0.28, blue: 0.28)      // red
        }
    }

    private var scoreLabel: String {
        switch score {
        case 80...: return "Thriving"
        case 60..<80: return "Growing"
        default: return "Needs Attention"
        }
    }

    private var trimEnd: Double {
        Double(max(0, min(100, score))) / 100.0
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Track
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: 140, height: 140)

                // Fill
                Circle()
                    .trim(from: 0.1, to: 0.1 + 0.8 * trimEnd)
                    .stroke(
                        arcColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 140, height: 140)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.01)
                            : .spring(response: 0.85, dampingFraction: 0.72),
                        value: score
                    )

                // Score text
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.systemScaled(34, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            VStack(spacing: 3) {
                Text("Community Vitality")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                Text(scoreLabel)
                    .font(.systemScaled(13, weight: .bold))
                    .foregroundStyle(arcColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Community Vitality Score: \(score) out of 100. Status: \(scoreLabel).")
    }
}

// MARK: - Trend arrow

private enum MetricTrend {
    case up, flat, down

    var icon: String {
        switch self {
        case .up:   return "arrow.up.right"
        case .flat: return "minus"
        case .down: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .up:   return Color(red: 0.22, green: 0.75, blue: 0.45)
        case .flat: return Color.white.opacity(0.45)
        case .down: return Color(red: 0.80, green: 0.28, blue: 0.28)
        }
    }
}

// MARK: - Metric card (glass, horizontal scroll row)

private struct MetricCard: View {
    let value: String
    let label: String
    let trend: MetricTrend
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.systemScaled(24, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: trend.icon)
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(trend.color)
                    .accessibilityHidden(true)
            }

            Text(label)
                .font(.systemScaled(13))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            Text("This Month")
                .font(.systemScaled(11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(14)
        .frame(width: 150, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). Trend: \(trendAccessibilityLabel(trend)).")
    }

    private func trendAccessibilityLabel(_ t: MetricTrend) -> String {
        switch t {
        case .up:   return "trending up"
        case .flat: return "stable"
        case .down: return "trending down"
        }
    }
}

// MARK: - Main View

struct AmenCommunityHealthDashboardView: View {
    let spaceId: String
    let spaceName: String

    @StateObject private var vm: AmenCommunityHealthDashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    init(spaceId: String, spaceName: String) {
        self.spaceId = spaceId
        self.spaceName = spaceName
        _vm = StateObject(wrappedValue: AmenCommunityHealthDashboardViewModel(spaceId: spaceId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Community Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                    }
                    .accessibilityLabel("Refresh health metrics")
                }
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Content dispatch

    @ViewBuilder
    private var contentBody: some View {
        if vm.isLoading {
            loadingBody
        } else if let error = vm.errorMessage {
            errorBody(error)
        } else if let metrics = vm.metrics {
            dashboardBody(metrics)
        } else {
            emptyBody
        }
    }

    // MARK: - Loading skeleton

    private var loadingBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Gauge placeholder
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 160, height: 160)

                // Card row placeholder
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 150, height: 100)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
        }
        .accessibilityLabel("Loading health metrics")
    }

    // MARK: - Error state

    private func errorBody(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(36))
                .foregroundStyle(Color(hex: "D9A441"))
            Text("Couldn't load metrics")
                .font(.systemScaled(17, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await vm.load() }
            } label: {
                Text("Try Again")
                    .font(.systemScaled(15, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(hex: "D9A441"), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyBody: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.systemScaled(36))
                .foregroundStyle(Color.white.opacity(0.25))
            Text("No metrics yet")
                .font(.systemScaled(16))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dashboard

    private func dashboardBody(_ metrics: SpaceHealthMetrics) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {

                // Privacy disclaimer — always at top
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.white.opacity(0.40))
                    Text("These analytics are visible only to you.")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
                .accessibilityLabel("These analytics are private and visible only to you.")

                // Section 1: Vitality gauge
                vitalityGaugeSection(metrics)

                // Section 2: Metric cards (horizontal scroll)
                metricCardsSection(metrics)

                // Section 3: Source breakdown card (matte)
                sourceBreakdownCard(metrics)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Vitality gauge section

    private func vitalityGaugeSection(_ metrics: SpaceHealthMetrics) -> some View {
        VStack(spacing: 0) {
            VitalityGauge(score: metrics.vitalityScore)
                .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Metric cards

    private func metricCardsSection(_ metrics: SpaceHealthMetrics) -> some View {
        let trend = parseTrend(metrics.trend)

        return VStack(alignment: .leading, spacing: 10) {
            Text("ENGAGEMENT QUALITY")
                .font(.systemScaled(11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Color.white.opacity(0.40))
                .padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    MetricCard(
                        value: "\(Int(metrics.memberRetentionPct.rounded()))%",
                        label: "Member Retention",
                        trend: trend,
                        tint: Color(hex: "6E4BB5")
                    )
                    MetricCard(
                        value: String(format: "%.1f", metrics.avgEventAttendance),
                        label: "Event Attendance",
                        trend: trend,
                        tint: Color(hex: "D9A441")
                    )
                    MetricCard(
                        value: String(format: "%.1f", metrics.prayerEngagementRate),
                        label: "Prayer Engagement",
                        trend: trend,
                        tint: Color(hex: "6E4BB5")
                    )
                    MetricCard(
                        value: String(format: "%.1f", metrics.discussionHealthAvg),
                        label: "Discussion Health",
                        trend: trend,
                        tint: Color(hex: "D9A441")
                    )
                    MetricCard(
                        value: "\(metrics.mentorshipCompletionsThisMonth)",
                        label: "Mentorship Completions",
                        trend: trend,
                        tint: Color(hex: "6E4BB5")
                    )
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Source breakdown card (matte)

    private func sourceBreakdownCard(_ metrics: SpaceHealthMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCORE COMPOSITION")
                .font(.systemScaled(11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Color.white.opacity(0.40))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                breakdownRow(label: "Prayer Activity",           value: metrics.prayerEngagementRate / 5.0, tint: Color(hex: "6E4BB5"))
                breakdownRow(label: "Mentorship Completions",    value: Double(metrics.mentorshipCompletionsThisMonth) / 20.0, tint: Color(hex: "D9A441"))
                breakdownRow(label: "Event Attendance",          value: metrics.avgEventAttendance / 100.0, tint: Color(hex: "6E4BB5"))
                breakdownRow(label: "Discussion Health",         value: metrics.discussionHealthAvg / 10.0, tint: Color(hex: "D9A441"))
            }
        }
        .padding(16)
        .background {
            // Matte — not glass on glass
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "0E0C12"))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                }
        }
    }

    private func breakdownRow(label: String, value: Double, tint: Color) -> some View {
        let clamped = max(0, min(1, value))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.70))
                Spacer()
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: geo.size.width * clamped, height: 6)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.01)
                                : .spring(response: 0.6, dampingFraction: 0.78),
                            value: clamped
                        )
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int((clamped * 100).rounded())) percent")
    }

    // MARK: - Helpers

    private func parseTrend(_ raw: String) -> MetricTrend {
        switch raw {
        case "growing":  return .up
        case "declining": return .down
        default:         return .flat
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenCommunityHealthDashboardView(spaceId: "preview-space", spaceName: "Sunday Worship Team")
        .preferredColorScheme(.dark)
}
#endif
