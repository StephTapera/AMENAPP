import SwiftUI

struct ImpactDashboardCard: View {
    @StateObject private var service = ImpactDashboardService()
    @State private var selectedBadge: ImpactBadge? = nil
    @State private var animateScore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            scoreAndMetricsRow
            if !service.badges.isEmpty { badgeCarousel }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onAppear {
            service.startListening()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.80).delay(0.2)) { animateScore = true }
        }
        .sheet(item: $selectedBadge) { badge in BadgeDetailSheet(badge: badge, allBadges: service.badges) }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Impact")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                if let lastUpdate = service.metrics.lastAggregationAt?.dateValue() {
                    Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            Spacer()
            impactScoreCircle
        }
    }

    private var impactScoreCircle: some View {
        ZStack {
            Circle()
                .stroke(AmenTheme.Colors.surfaceChip, lineWidth: 6)
                .frame(width: 60, height: 60)
            Circle()
                .trim(from: 0, to: animateScore ? CGFloat(service.metrics.impactScore) / 100.0 : 0)
                .stroke(
                    AngularGradient(colors: [Color(red: 0.83, green: 0.69, blue: 0.22), Color(red: 0.10, green: 0.60, blue: 0.56)], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animateScore)
            Text("\(service.metrics.impactScore)")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .accessibilityLabel("Impact score: \(service.metrics.impactScore) out of 100")
    }

    private var scoreAndMetricsRow: some View {
        HStack(spacing: 0) {
            metricColumn(
                value: "$\(service.metrics.totalGiven / 100)",
                label: "Total Given",
                color: Color(red: 0.83, green: 0.69, blue: 0.22)
            )
            Divider().frame(height: 40)
            metricColumn(
                value: String(format: "%.0f hr", service.metrics.wellnessEngagementHours),
                label: "Wellness",
                color: Color(red: 0.10, green: 0.60, blue: 0.56)
            )
            Divider().frame(height: 40)
            metricColumn(
                value: "\(service.metrics.crisisCheckinsCount)",
                label: "Crisis Support",
                color: Color(red: 0.40, green: 0.70, blue: 0.95)
            )
        }
        .padding(.vertical, 8)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(12)
    }

    private func metricColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(color)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var badgeCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges")
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(service.badges.prefix(6)) { badge in
                        badgeView(badge: badge)
                            .onTapGesture { selectedBadge = badge }
                    }
                }
            }
        }
    }

    private func badgeView(badge: ImpactBadge) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.badgeColorValue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: badge.icon)
                    .font(.title3)
                    .foregroundStyle(badge.badgeColorValue)
            }
            Text(badge.name)
                .font(.custom("OpenSans-Regular", size: 10))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 56)
        .accessibilityLabel("\(badge.name) badge")
    }
}
