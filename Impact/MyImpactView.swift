import SwiftUI

struct MyImpactView: View {
    @StateObject private var service = ImpactDashboardService()
    @StateObject private var insightsService = ImpactInsightsService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    weeklyCard
                    highlightsSection
                    trendsSection
                    recommendationsSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle("My Impact")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                service.startListening()
                insightsService.loadLatest()
            }
        }
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(insightsService.weeklySummary)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(4)
            HStack(spacing: 12) {
                insightMetricPill(value: "$\(service.metrics.totalGiven / 100)", label: "Given", color: Color(red: 0.83, green: 0.69, blue: 0.22))
                insightMetricPill(value: String(format: "%.0f hr", service.metrics.wellnessEngagementHours), label: "Wellness", color: Color(red: 0.10, green: 0.60, blue: 0.56))
                insightMetricPill(value: "\(service.metrics.crisisCheckinsCount)", label: "Checkins", color: Color(red: 0.40, green: 0.70, blue: 0.95))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private func insightMetricPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(color)
            Text(label).font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var highlightsSection: some View {
        Group {
            if !insightsService.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Highlights")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(insightsService.highlights) { highlight in
                                highlightCard(highlight: highlight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func highlightCard(highlight: WeeklyInsight.InsightHighlight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlight.emoji).font(.title2)
            Text(highlight.title).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary).lineLimit(2)
            Text(highlight.metric).font(.custom("OpenSans-Bold", size: 20)).foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            Text(highlight.comparison).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(12)
        .frame(width: 150)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(12)
    }

    private var trendsSection: some View {
        Group {
            if let insight = insightsService.latestInsight {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trends")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    HStack(spacing: 10) {
                        trendPill(label: "Giving", trend: insight.givingTrend, color: Color(red: 0.83, green: 0.69, blue: 0.22))
                        trendPill(label: "Wellness", trend: insight.wellnessTrend, color: Color(red: 0.10, green: 0.60, blue: 0.56))
                    }
                }
            }
        }
    }

    private func trendPill(label: String, trend: String, color: Color) -> some View {
        HStack {
            Image(systemName: trend == "up" ? "arrow.up.circle.fill" : trend == "down" ? "arrow.down.circle.fill" : "minus.circle.fill")
                .foregroundStyle(trend == "up" ? .green : trend == "down" ? .red : .gray)
            Text(label).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(10)
        .accessibilityLabel("\(label) trend: \(trend)")
    }

    private var recommendationsSection: some View {
        Group {
            if !insightsService.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("For You")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    ForEach(insightsService.recommendations) { rec in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.title).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(rec.description).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AmenTheme.Colors.surfaceCard)
                        .cornerRadius(10)
                        .accessibilityLabel("\(rec.title): \(rec.description)")
                    }
                }
            }
        }
    }
}
