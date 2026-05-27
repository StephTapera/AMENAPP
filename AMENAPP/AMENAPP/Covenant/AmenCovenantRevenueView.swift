import SwiftUI

// MARK: - Creator Revenue + Member Insights View
// Creator/admin only. Shows MRR, member health, tier distribution, content performance.
// No raw Stripe financial data exposed to unauthorized users.
// Privacy-first: aggregate by default, no invasive member surveillance.

struct AmenCovenantRevenueView: View {
    let covenantId: String
    @State private var analytics: CovenantAnalytics?
    @State private var churnSignals: [CovenantMemberSignal] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var selectedPeriod = Period.thisMonth

    enum Period: String, CaseIterable {
        case thisMonth = "This Month"
        case last3Months = "3 Months"
        case allTime = "All Time"
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let a = analytics {
                    contentView(a)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Revenue & Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(Period.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .task { await loadData() }
            .alert("Couldn't Load Revenue Data", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("Retry") { Task { await loadData() } }
                Button("Dismiss", role: .cancel) { loadError = nil }
            } message: {
                Text(loadError ?? "An error occurred. Please try again.")
            }
        }
    }

    // MARK: - Content

    private func contentView(_ a: CovenantAnalytics) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                mrrCard(a)
                memberHealthGrid(a)
                tierDistributionSection(a)
                if !churnSignals.isEmpty { churnRiskSection }
                privacyNotice
            }
            .padding(20)
        }
    }

    // MARK: - MRR Card

    private func mrrCard(_ a: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monthly Recurring Revenue", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(formatCurrency(a.monthlyRecurringRevenue))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Divider()

            HStack(spacing: 20) {
                metricSmall(label: "Paid", value: "\(a.paidMemberCount)")
                metricSmall(label: "Free", value: "\(a.freeMemberCount)")
                metricSmall(label: "Trialing", value: "\(a.trialingCount)")
                metricSmall(label: "Past Due", value: "\(a.pastDueCount)")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Member Health Grid

    private func memberHealthGrid(_ a: CovenantAnalytics) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
            metricCard(label: "Event Conversion", value: "\(Int(a.eventConversionRate * 100))%", icon: "calendar.badge.plus", color: .orange)
            metricCard(label: "Room Engagement", value: "\(Int(a.roomEngagementRate * 100))%", icon: "bubble.left.and.bubble.right.fill", color: .teal)
            metricCard(label: "Churn Risk", value: "\(a.churnRiskCount) members", icon: "exclamationmark.triangle.fill", color: a.churnRiskCount > 5 ? .red : .yellow)
            metricCard(label: "Canceled", value: "\(a.canceledCount)", icon: "xmark.circle.fill", color: .secondary)
        }
    }

    private func metricCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Tier Distribution

    private func tierDistributionSection(_ a: CovenantAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tier Distribution")
                .font(.headline)

            if a.tierDistribution.isEmpty {
                Text("Data appears after activity begins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let total = Double(a.tierDistribution.values.reduce(0, +))
                VStack(spacing: 10) {
                    ForEach(Array(a.tierDistribution.sorted { $0.value > $1.value }), id: \.key) { tier, count in
                        tierBar(name: tier, count: count, total: total)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func tierBar(name: String, count: Int, total: Double) -> some View {
        let pct = total > 0 ? Double(count) / total : 0
        return HStack(spacing: 10) {
            Text(name)
                .font(.caption.weight(.medium))
                .frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.purple.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.purple)
                        .frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Churn Risk Section

    private var churnRiskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Churn Risk (Aggregated)", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
            }

            Text("These trends suggest some members may leave soon. Consider increasing engagement.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                let highCount   = churnSignals.filter { $0.churnRisk == .high }.count
                let mediumCount = churnSignals.filter { $0.churnRisk == .medium }.count

                if highCount > 0 {
                    churnBand(label: "High Risk", count: highCount, color: .red)
                }
                if mediumCount > 0 {
                    churnBand(label: "Medium Risk", count: mediumCount, color: .orange)
                }
            }

            Text("Individual member data is not shown here to protect member privacy.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func churnBand(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.subheadline)
            Spacer()
            Text("\(count) members")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Privacy Notice

    private var privacyNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(.secondary)
            Text("Analytics are aggregated. Individual prayer details, vulnerability signals, and sensitive personal data are never surfaced here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Data Appears After Activity Begins")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Come back after your community has been active for a few days.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func metricSmall(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func formatCurrency(_ value: Double) -> String {
        Self.usdFormatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func loadData() async {
        loading = true
        loadError = nil
        let key = DateFormatter.yearMonthKey.string(from: Date())
        do {
            analytics    = try await CovenantService.shared.loadAnalytics(covenantId: covenantId, dateKey: key)
            churnSignals = (try? await CovenantService.shared.loadChurnSignals(covenantId: covenantId)) ?? []
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let yearMonthKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()
}
