// CreatorPrivateMetricsDashboard.swift
// AMENAPP — CreatorOS
// Private-only metrics dashboard for creators and hosts.
// RULE: No public vanity metrics. Only private engagement + spiritual health signals.

import SwiftUI

// MARK: - Private Metrics Model

struct CreatorPrivateMetrics {
    var retentionRate: Double          // 0–1, % who return each week
    var participationRate: Double      // 0–1, % who post/comment
    var prayerEngagement: Int          // prayer hands tapped this period
    var studyCompletionRate: Double    // 0–1
    var newMemberWelcomedCount: Int
    var followUpsSent: Int
    var prayerRequestsAnswered: Int
    var communityHealthScore: Double   // 0–1, composite signal
    var period: String                 // "This Week", "This Month" etc.

    static let preview = CreatorPrivateMetrics(
        retentionRate: 0.74,
        participationRate: 0.51,
        prayerEngagement: 138,
        studyCompletionRate: 0.68,
        newMemberWelcomedCount: 7,
        followUpsSent: 12,
        prayerRequestsAnswered: 9,
        communityHealthScore: 0.81,
        period: "This Month"
    )
}

// MARK: - Dashboard View

struct CreatorPrivateMetricsDashboard: View {
    let metrics: CreatorPrivateMetrics
    let spaceName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Privacy notice
                privacyNotice

                // Community health score
                healthScoreCard

                // Metric grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(
                        title: "Weekly Return Rate",
                        value: "\(Int(metrics.retentionRate * 100))%",
                        icon: "arrow.clockwise",
                        trend: metrics.retentionRate > 0.65 ? .positive : .neutral,
                        description: "Members returning each week"
                    )
                    MetricCard(
                        title: "Participation",
                        value: "\(Int(metrics.participationRate * 100))%",
                        icon: "bubble.left.and.bubble.right.fill",
                        trend: metrics.participationRate > 0.4 ? .positive : .neutral,
                        description: "Members actively posting or replying"
                    )
                    MetricCard(
                        title: "Prayer Engagements",
                        value: "\(metrics.prayerEngagement)",
                        icon: "hands.sparkles.fill",
                        trend: .positive,
                        description: "Prayer reactions this period"
                    )
                    MetricCard(
                        title: "Study Completion",
                        value: "\(Int(metrics.studyCompletionRate * 100))%",
                        icon: "book.closed.fill",
                        trend: metrics.studyCompletionRate > 0.5 ? .positive : .neutral,
                        description: "Studies finished by members"
                    )
                    MetricCard(
                        title: "New Members Welcomed",
                        value: "\(metrics.newMemberWelcomedCount)",
                        icon: "person.badge.plus.fill",
                        trend: .positive,
                        description: "New members greeted this period"
                    )
                    MetricCard(
                        title: "Prayers Answered",
                        value: "\(metrics.prayerRequestsAnswered)",
                        icon: "checkmark.circle.fill",
                        trend: .positive,
                        description: "Marked as answered"
                    )
                }

                // No vanity metrics notice
                VStack(alignment: .leading, spacing: 6) {
                    Label("Why no follower counts?", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("AMEN intentionally hides public follower and view counts. These metrics stay private to help you care for your community without comparison or performance pressure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .navigationTitle("\(spaceName) — Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sub-views

    private var privacyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.amenGold)
            Text("Only you can see these metrics — they are never public.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.amenGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var healthScoreCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.secondarySystemBackground), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: metrics.communityHealthScore)
                    .stroke(Color.amenGold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(metrics.communityHealthScore * 100))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.amenGold)
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text("Community Health")
                    .font(.headline)
                Text(healthLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(metrics.period)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var healthLabel: String {
        switch metrics.communityHealthScore {
        case 0.8...: return "Thriving — your community is flourishing"
        case 0.6..<0.8: return "Growing — strong engagement across the board"
        case 0.4..<0.6: return "Developing — room for intentional growth"
        default: return "Needs attention — consider reaching out"
        }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let trend: Trend
    let description: String

    enum Trend { case positive, neutral, negative }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenGold)
                Spacer()
                Image(systemName: trendIcon)
                    .font(.caption)
                    .foregroundStyle(trendColor)
            }
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(description)")
    }

    private var trendIcon: String {
        switch trend {
        case .positive: return "arrow.up.right"
        case .neutral:  return "minus"
        case .negative: return "arrow.down.right"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .positive: return .green
        case .neutral:  return .secondary
        case .negative: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreatorPrivateMetricsDashboard(
            metrics: .preview,
            spaceName: "Sunday Morning Group"
        )
    }
}
