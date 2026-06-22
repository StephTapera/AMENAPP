import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct HealthDimension: Identifiable {
    let id: String
    let name: String
    let score: Double
    let icon: String
    let description: String
    let trend: HealthTrend

    enum HealthTrend {
        case improving, stable, declining
        var label: String {
            switch self {
            case .improving: return "Improving"
            case .stable: return "Stable"
            case .declining: return "Declining"
            }
        }
        var color: Color {
            switch self {
            case .improving: return .green
            case .stable: return .secondary
            case .declining: return .orange
            }
        }
        var icon: String {
            switch self {
            case .improving: return "arrow.up.right.circle.fill"
            case .stable: return "minus.circle.fill"
            case .declining: return "arrow.down.right.circle.fill"
            }
        }
    }
}

struct PrayerActivityPulse: Identifiable {
    let id: String
    let dayLabel: String
    let requestCount: Int
    let responseCount: Int
    let maxValue: Int

    var requestRatio: Double { Double(requestCount) / Double(max(maxValue, 1)) }
    var responseRatio: Double { Double(responseCount) / Double(max(maxValue, 1)) }
}

struct EngagementAlert: Identifiable {
    let id: String
    let title: String
    let description: String
    let severity: AlertSeverity
    let suggestedAction: String
    var isDismissed: Bool = false

    enum AlertSeverity: String {
        case pastoral = "Pastoral"
        case operational = "Operational"
        case celebratory = "Celebratory"

        var color: Color {
            switch self {
            case .pastoral: return .accentColor
            case .operational: return .orange
            case .celebratory: return Color.accentColor
            }
        }

        var icon: String {
            switch self {
            case .pastoral: return "cross.fill"
            case .operational: return "exclamationmark.triangle.fill"
            case .celebratory: return "star.fill"
            }
        }
    }
}

struct CommunityDashboardSnapshot {
    let overallScore: Double
    let scoreDelta7d: Double
    let dimensions: [HealthDimension]
    let prayerPulse: [PrayerActivityPulse]
    let alerts: [EngagementAlert]
    let totalMembers: Int
    let weeklyActivePercent: Double
    let newConnections: Int
    let mentorshipPairs: Int

    static let preview = CommunityDashboardSnapshot(
        overallScore: 0.76,
        scoreDelta7d: 0.03,
        dimensions: [
            HealthDimension(id: "d1", name: "Prayer Life", score: 0.82, icon: "hands.sparkles.fill", description: "Active prayer requests and responses", trend: .improving),
            HealthDimension(id: "d2", name: "Scripture Engagement", score: 0.71, icon: "book.fill", description: "Bible study participation & notes", trend: .stable),
            HealthDimension(id: "d3", name: "Community Discussion", score: 0.68, icon: "bubble.left.and.bubble.right.fill", description: "Active conversations across spaces", trend: .improving),
            HealthDimension(id: "d4", name: "Member Retention", score: 0.79, icon: "person.2.fill", description: "30-day active member rate", trend: .stable),
            HealthDimension(id: "d5", name: "Volunteer Health", score: 0.55, icon: "person.badge.plus", description: "Volunteer slots filled vs. needed", trend: .declining),
            HealthDimension(id: "d6", name: "Event Participation", score: 0.73, icon: "calendar.badge.checkmark", description: "RSVP and attendance rates", trend: .stable)
        ],
        prayerPulse: [
            PrayerActivityPulse(id: "mon", dayLabel: "Mon", requestCount: 14, responseCount: 28, maxValue: 50),
            PrayerActivityPulse(id: "tue", dayLabel: "Tue", requestCount: 9, responseCount: 18, maxValue: 50),
            PrayerActivityPulse(id: "wed", dayLabel: "Wed", requestCount: 22, responseCount: 41, maxValue: 50),
            PrayerActivityPulse(id: "thu", dayLabel: "Thu", requestCount: 11, responseCount: 19, maxValue: 50),
            PrayerActivityPulse(id: "fri", dayLabel: "Fri", requestCount: 8, responseCount: 14, maxValue: 50),
            PrayerActivityPulse(id: "sat", dayLabel: "Sat", requestCount: 6, responseCount: 10, maxValue: 50),
            PrayerActivityPulse(id: "sun", dayLabel: "Sun", requestCount: 34, responseCount: 48, maxValue: 50)
        ],
        alerts: [
            EngagementAlert(id: "a1", title: "3 members inactive 30+ days", description: "These members previously engaged regularly. Consider a pastoral check-in.", severity: .pastoral, suggestedAction: "Schedule pastoral outreach (requires your approval)"),
            EngagementAlert(id: "a2", title: "Volunteer gap worsening", description: "Children's ministry remains understaffed for 3 consecutive weeks.", severity: .operational, suggestedAction: "Draft a volunteer recruitment post"),
            EngagementAlert(id: "a3", title: "8 members made their first contribution!", description: "New voices joined the community conversation this week.", severity: .celebratory, suggestedAction: "Send a welcome message to new contributors")
        ],
        totalMembers: 312,
        weeklyActivePercent: 0.74,
        newConnections: 23,
        mentorshipPairs: 11
    )
}

// MARK: - Main View

struct CommunityHealthDashboardView: View {
    let snapshot: CommunityDashboardSnapshot
    @State private var localAlerts: [EngagementAlert]
    @State private var selectedDimension: HealthDimension? = nil
    @State private var showDimensionDetail = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: CommunityDashboardSnapshot) {
        self.snapshot = snapshot
        self._localAlerts = State(initialValue: snapshot.alerts)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                overallScoreCard
                alertsSection
                dimensionsGrid
                prayerPulseChart
                connectionStats
                privacyNotice
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showDimensionDetail) {
            if let dim = selectedDimension {
                DimensionDetailSheet(dimension: dim)
            }
        }
    }

    // MARK: - Overall Score

    private var overallScoreCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Community Health")
                        .font(.title2.weight(.semibold))
                    Text("Live — updated daily")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                deltaLabel
            }
            HStack(alignment: .bottom, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: snapshot.overallScore)
                        .stroke(
                            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? .none : .spring(response: 0.8), value: snapshot.overallScore)
                    VStack(spacing: 0) {
                        Text("\(Int(snapshot.overallScore * 100))")
                            .font(.systemScaled(36, weight: .bold))
                        Text("Health Score")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 10) {
                    statRow(label: "Total Members", value: "\(snapshot.totalMembers)")
                    statRow(label: "Weekly Active", value: "\(Int(snapshot.weeklyActivePercent * 100))%")
                    statRow(label: "New Connections", value: "+\(snapshot.newConnections)")
                    statRow(label: "Mentorship Pairs", value: "\(snapshot.mentorshipPairs)")
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var deltaLabel: some View {
        let isPositive = snapshot.scoreDelta7d >= 0
        return Label(
            "\(isPositive ? "+" : "")\(Int(snapshot.scoreDelta7d * 100)) pts",
            systemImage: isPositive ? "arrow.up.right" : "arrow.down.right"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(isPositive ? .green : .orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background((isPositive ? Color.green : Color.orange).opacity(0.12))
        .clipShape(Capsule())
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Community Alerts", systemImage: "bell.badge.fill")
                .font(.headline)

            ForEach($localAlerts) { $alert in
                if !alert.isDismissed {
                    AlertCard(alert: alert, onDismiss: {
                        withAnimation { alert.isDismissed = true }
                    })
                }
            }
        }
    }

    // MARK: - Dimensions Grid

    private var dimensionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Health Dimensions", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(snapshot.dimensions) { dim in
                    DimensionCard(dimension: dim) {
                        selectedDimension = dim
                        showDimensionDetail = true
                    }
                }
            }
        }
    }

    // MARK: - Prayer Pulse Chart

    private var prayerPulseChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prayer Activity (7 days)", systemImage: "waveform.path.ecg")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(snapshot.prayerPulse) { pulse in
                    VStack(spacing: 3) {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(height: CGFloat(pulse.responseRatio) * 80)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(height: CGFloat(pulse.requestRatio) * 40)
                        }
                        Text(pulse.dayLabel)
                            .font(.systemScaled(9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)

            HStack(spacing: 16) {
                legendDot(color: Color.accentColor, label: "Requests")
                legendDot(color: Color.accentColor.opacity(0.6), label: "Responses")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Connection Stats

    private var connectionStats: some View {
        HStack(spacing: 12) {
            connectionStatCard(value: "\(snapshot.newConnections)", label: "New Connections", icon: "link")
            connectionStatCard(value: "\(snapshot.mentorshipPairs)", label: "Mentorship Pairs", icon: "person.2.circle.fill")
        }
    }

    private func connectionStatCard(value: String, label: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.weight(.bold))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Privacy Notice

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Leader-Only View")
                    .font(.caption.weight(.semibold))
                Text("All health data is private and visible only to pastors and community admins. No individual-level data is surfaced. Trend analysis never exposes personal prayer requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Alert Card

private struct AlertCard: View {
    let alert: EngagementAlert
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: alert.severity.icon)
                    .foregroundStyle(alert.severity.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.subheadline.weight(.medium))
                    Text(alert.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(alert.suggestedAction)
                .font(.caption.italic())
                .foregroundStyle(alert.severity.color)
                .padding(.leading, 24)
        }
        .padding()
        .background(alert.severity.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(alert.severity.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Dimension Card

private struct DimensionCard: View {
    let dimension: HealthDimension
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: dimension.icon)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: dimension.trend.icon)
                        .foregroundStyle(dimension.trend.color)
                        .font(.caption)
                }
                Text(dimension.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemFill))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(scoreColor(dimension.score))
                                .frame(width: geo.size.width * dimension.score)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(dimension.score * 100))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return .green
        case 0.5..<0.75: return Color.accentColor
        default: return .orange
        }
    }
}

// MARK: - Dimension Detail Sheet

private struct DimensionDetailSheet: View {
    let dimension: HealthDimension
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: dimension.icon)
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(dimension.name)
                            .font(.title2.weight(.semibold))
                        Text(dimension.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current Score")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(dimension.score * 100)) / 100")
                            .font(.title.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Trend")
                            .font(.caption).foregroundStyle(.secondary)
                        Label(dimension.trend.label, systemImage: dimension.trend.icon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(dimension.trend.color)
                    }
                }
                Text("Detailed breakdown for this dimension will be available in a future update. This score reflects aggregate community activity — no individual data is exposed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle(dimension.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CommunityHealthDashboardView(snapshot: .preview)
            .navigationTitle("Community Health")
    }
}
