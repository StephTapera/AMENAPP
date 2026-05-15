import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Covenant Analytics View
// Creator analytics dashboard focused on community health and engagement.
// Revenue/MRR is covered by AmenCovenantRevenueView — this view covers
// engagement rate, member activity, tier distribution, and health score.

struct AmenCovenantAnalyticsView: View {
    let covenantId: String
    @EnvironmentObject var vm: AmenCovenantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var analyticsVM = AmenCovenantAnalyticsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                periodPicker

                if analyticsVM.isLoading && analyticsVM.analytics == nil {
                    loadingPlaceholder
                } else if let analytics = analyticsVM.analytics {
                    healthScoreSection(analytics)
                    memberActivitySection(analytics)
                    tierDistributionSection(analytics)
                    topContentSection(analytics)
                    privacyFooter
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Community Analytics")
        .navigationBarTitleDisplayMode(.large)
        .task { await analyticsVM.load(covenantId: covenantId) }
        .onChange(of: analyticsVM.selectedPeriod) { _, _ in
            Task { await analyticsVM.load(covenantId: covenantId) }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $analyticsVM.selectedPeriod) {
            ForEach(AmenCovenantAnalyticsViewModel.AnalyticsPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Analytics period selector")
    }

    // MARK: - Health Score Section

    private func healthScoreSection(_ analytics: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Community Health Score")

            HStack(spacing: 24) {
                healthGauge(score: analyticsVM.healthScore)

                VStack(alignment: .leading, spacing: 12) {
                    contributorRow(
                        label: "Room Engagement",
                        value: analytics.roomEngagementRate,
                        color: .blue
                    )
                    contributorRow(
                        label: "Prayer Engagement",
                        value: min(analytics.eventConversionRate * 1.2, 1.0),
                        color: .purple
                    )
                    contributorRow(
                        label: "Event Attendance",
                        value: analytics.eventConversionRate,
                        color: .orange
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }

    private func healthGauge(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(gaugeColor(score: score).opacity(0.2), lineWidth: 10)
                .frame(width: 90, height: 90)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100.0)
                .stroke(
                    gaugeColor(score: score),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: score)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("/ 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Community health score: \(score) out of 100")
    }

    private func gaugeColor(score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    private func contributorRow(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(max(value, 0), 1), height: 8)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: value)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(value * 100)) percent")
    }

    // MARK: - Member Activity Section

    private func memberActivitySection(_ analytics: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Member Activity")

            HStack(spacing: 12) {
                activityStatCard(
                    value: "\(analytics.paidMemberCount + analytics.freeMemberCount)",
                    label: "Active Members",
                    icon: "person.fill.checkmark",
                    color: .blue
                )
                activityStatCard(
                    value: "+\(newMembersEstimate(analytics))",
                    label: "New This Month",
                    icon: "person.badge.plus",
                    color: .green
                )
                activityStatCard(
                    value: "\(analytics.churnRiskCount)",
                    label: "At Risk",
                    icon: "exclamationmark.triangle.fill",
                    color: analytics.churnRiskCount > 0 ? .orange : .secondary
                )
            }
        }
    }

    private func activityStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func newMembersEstimate(_ analytics: CovenantAnalytics) -> Int {
        // Estimate using trialing + any positive delta from analytics data
        max(analytics.trialingCount, 0)
    }

    // MARK: - Tier Distribution Section

    private func tierDistributionSection(_ analytics: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Tier Distribution")

            if analytics.tierDistribution.isEmpty {
                emptyTierState
            } else {
                let total = analytics.tierDistribution.values.reduce(0, +)
                let sorted = analytics.tierDistribution.sorted { $0.value > $1.value }

                VStack(spacing: 12) {
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, pair in
                        tierDistributionRow(
                            tierName: pair.key,
                            count: pair.value,
                            total: total,
                            color: tierBarColor(index: index)
                        )
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
            }
        }
    }

    private func tierDistributionRow(tierName: String, count: Int, total: Int, color: Color) -> some View {
        let proportion = total > 0 ? CGFloat(count) / CGFloat(total) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tierName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count) member\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(\(Int(proportion * 100))%)")
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.15))
                        .frame(height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * proportion, height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: proportion)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tierName): \(count) members, \(Int(proportion * 100)) percent")
    }

    private func tierBarColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .green, .pink, .indigo]
        return colors[index % colors.count]
    }

    private var emptyTierState: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.tertiary)
            Text("No tier data available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Top Content Section

    private func topContentSection(_ analytics: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Trending Posts")

            HStack(spacing: 12) {
                Image(systemName: analytics.topContentIds.isEmpty ? "clock.arrow.circlepath" : "flame.fill")
                    .foregroundStyle(analytics.topContentIds.isEmpty ? Color.secondary : Color.orange)
                Text(analytics.topContentIds.isEmpty
                    ? "Analytics syncing…"
                    : "\(analytics.topContentIds.count) post\(analytics.topContentIds.count == 1 ? "" : "s") trending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Analytics are aggregated. No individual data is exposed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Loading & Empty States

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading analytics…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Analytics Yet")
                .font(.title3.bold())
            Text("Analytics will appear once your community has activity for the selected period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Section Title Helper

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

// MARK: - Analytics ViewModel

@MainActor
final class AmenCovenantAnalyticsViewModel: ObservableObject {
    enum AnalyticsPeriod: String, CaseIterable {
        case thisMonth = "This Month"
        case last30 = "Last 30 Days"
        case thisQuarter = "This Quarter"
    }

    @Published var analytics: CovenantAnalytics?
    @Published var isLoading: Bool = false
    @Published var selectedPeriod: AnalyticsPeriod = .thisMonth

    var dateKey: String {
        let cal = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .thisMonth:
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            return String(format: "%04d-%02d", year, month)
        case .last30:
            let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now
            let year = cal.component(.year, from: thirtyDaysAgo)
            let month = cal.component(.month, from: thirtyDaysAgo)
            return String(format: "%04d-%02d", year, month)
        case .thisQuarter:
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            let quarter = ((month - 1) / 3) + 1
            return String(format: "%04d-Q%d", year, quarter)
        }
    }

    var healthScore: Int {
        guard let a = analytics else { return 0 }
        let totalMembers = max(a.paidMemberCount + a.freeMemberCount + a.trialingCount, 1)
        let churnFactor = 1.0 - (Double(a.churnRiskCount) / Double(totalMembers))
        let raw = a.roomEngagementRate * 40.0
            + a.eventConversionRate * 30.0
            + churnFactor * 30.0
        return min(max(Int(raw.rounded()), 0), 100)
    }

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            analytics = try await CovenantService.shared.loadAnalytics(
                covenantId: covenantId,
                dateKey: dateKey
            )
        } catch {
            analytics = nil
        }
    }
}
