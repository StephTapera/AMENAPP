// AmenCreatorEarningsDashboard.swift
// AMEN Spaces — Monetization: Host-only earnings and payout dashboard.
//
// Glass rule: section cards use .thinMaterial chrome; body text and
//             numbers stay matte. No glass-on-glass stacking.
// Host-only: caller must verify host identity before presenting this view.
// Written: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Inline Model Types

struct EarningsSummary: Codable {
    var totalLifetimeCents: Int
    var thisMonthCents: Int
    var lastMonthCents: Int
    var pendingPayoutCents: Int
    var nextPayoutDate: Date?
}

struct TierRevenue: Identifiable, Codable {
    var id: String
    var tierName: String
    var memberCount: Int
    var monthlyRevenueCents: Int
}

struct RevenueSplit: Identifiable, Codable {
    var id: String
    var userId: String
    var displayName: String
    var percentage: Double
}

// MARK: - View Model

@MainActor
private final class EarningsDashboardViewModel: ObservableObject {

    @Published var summary: EarningsSummary? = nil
    @Published var tierRevenues: [TierRevenue] = []
    @Published var giftRevenueCents: Int = 0
    @Published var oneTimePurchaseCents: Int = 0
    @Published var splits: [RevenueSplit] = []
    @Published var ytdEarningsCents: Int = 0

    @Published var isLoadingSummary: Bool = false
    @Published var summaryError: String? = nil

    @Published var isSavingSplits: Bool = false
    @Published var splitsError: String? = nil
    @Published var splitsSaved: Bool = false

    @Published var isGeneratingReport: Bool = false
    @Published var reportCSV: String? = nil

    @Published var showPayoutSheet: Bool = false
    @Published var showShareSheet: Bool = false

    private let functions = Functions.functions()

    // MARK: - Load

    func load(spaceId: String, hostUserId: String) async {
        isLoadingSummary = true
        summaryError = nil
        defer { isLoadingSummary = false }

        do {
            let callable = functions.httpsCallable("getCreatorEarningsSummary")
            let result = try await callable.call([
                "spaceId": spaceId,
                "hostUserId": hostUserId,
            ])

            guard let data = result.data as? [String: Any] else {
                summaryError = "Unexpected response from server."
                return
            }

            summary = parseSummary(from: data)
            tierRevenues = parseTierRevenues(from: data["tierRevenues"] as? [[String: Any]] ?? [])
            giftRevenueCents = data["giftRevenueCents"] as? Int ?? 0
            oneTimePurchaseCents = data["oneTimePurchaseCents"] as? Int ?? 0
            splits = parseSplits(from: data["splits"] as? [[String: Any]] ?? [])
            ytdEarningsCents = data["ytdEarningsCents"] as? Int ?? 0
        } catch {
            summaryError = "Could not load earnings data. Please check your connection."
        }
    }

    // MARK: - Splits

    func saveSplits(spaceId: String) async {
        guard !splits.isEmpty else { return }

        isSavingSplits = true
        splitsError = nil
        splitsSaved = false
        defer { isSavingSplits = false }

        let payload: [String: Any] = [
            "spaceId": spaceId,
            "splits": splits.map { ["userId": $0.userId, "percentage": $0.percentage] },
        ]

        do {
            let callable = functions.httpsCallable("updateRevenueSplits")
            _ = try await callable.call(payload)
            splitsSaved = true
        } catch {
            splitsError = "Could not save splits. Please try again."
        }
    }

    func addSplit() {
        // Appends a placeholder split; host fills in details
        let placeholder = RevenueSplit(
            id: UUID().uuidString,
            userId: "",
            displayName: "Co-host",
            percentage: 0.0
        )
        splits.append(placeholder)
    }

    func removeSplit(at offsets: IndexSet) {
        splits.remove(atOffsets: offsets)
        splitsSaved = false
    }

    var splitsTotal: Double {
        splits.reduce(0) { $0 + $1.percentage }
    }

    var splitsExceed100: Bool {
        splitsTotal > 100.0
    }

    // MARK: - Report

    func generateReport(spaceId: String) async {
        isGeneratingReport = true
        defer { isGeneratingReport = false }

        do {
            let callable = functions.httpsCallable("generateEarningsReport")
            let result = try await callable.call(["spaceId": spaceId])
            if let data = result.data as? [String: Any],
               let csv = data["csv"] as? String {
                reportCSV = csv
                showShareSheet = true
            }
        } catch {
            // Report generation is best-effort; silently degrade
        }
    }

    // MARK: - Parsing Helpers

    private func parseSummary(from data: [String: Any]) -> EarningsSummary {
        let nextPayoutDate: Date? = {
            if let ts = data["nextPayoutDate"] as? TimeInterval {
                return Date(timeIntervalSince1970: ts)
            }
            return nil
        }()
        return EarningsSummary(
            totalLifetimeCents: data["totalLifetimeCents"] as? Int ?? 0,
            thisMonthCents: data["thisMonthCents"] as? Int ?? 0,
            lastMonthCents: data["lastMonthCents"] as? Int ?? 0,
            pendingPayoutCents: data["pendingPayoutCents"] as? Int ?? 0,
            nextPayoutDate: nextPayoutDate
        )
    }

    private func parseTierRevenues(from array: [[String: Any]]) -> [TierRevenue] {
        array.compactMap { dict -> TierRevenue? in
            guard let id = dict["id"] as? String,
                  let tierName = dict["tierName"] as? String else { return nil }
            return TierRevenue(
                id: id,
                tierName: tierName,
                memberCount: dict["memberCount"] as? Int ?? 0,
                monthlyRevenueCents: dict["monthlyRevenueCents"] as? Int ?? 0
            )
        }
    }

    private func parseSplits(from array: [[String: Any]]) -> [RevenueSplit] {
        array.compactMap { dict -> RevenueSplit? in
            guard let id = dict["id"] as? String,
                  let userId = dict["userId"] as? String else { return nil }
            return RevenueSplit(
                id: id,
                userId: userId,
                displayName: dict["displayName"] as? String ?? userId,
                percentage: dict["percentage"] as? Double ?? 0.0
            )
        }
    }
}

// MARK: - Dashboard View

struct AmenCreatorEarningsDashboard: View {
    let spaceId: String
    let hostUserId: String

    @StateObject private var vm = EarningsDashboardViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                if vm.isLoadingSummary && vm.summary == nil {
                    loadingPlaceholder
                } else if let errorMsg = vm.summaryError, vm.summary == nil {
                    errorState(message: errorMsg)
                } else {
                    dashboardContent
                }
            }
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "070607"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { await vm.load(spaceId: spaceId, hostUserId: hostUserId) }
        .sheet(isPresented: $vm.showPayoutSheet) {
            // AmenStripeOnboardingService handles payout setup
            AmenStripeOnboardingSheet(spaceId: spaceId) {
                vm.showPayoutSheet = false
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let csv = vm.reportCSV {
                ShareSheet(activityItems: [csv])
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                earningsSummaryCard
                revenueBreakdownSection
                revenueSplitSection
                taxSummarySection
                payoutSetupRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - 1. Earnings Summary

    private var earningsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Total Earned
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Earned")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .textCase(.uppercase)
                    .kerning(0.6)
                Text(centsToString(vm.summary?.totalLifetimeCents ?? 0))
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityLabel("Total earned: \(centsToString(vm.summary?.totalLifetimeCents ?? 0))")
            }

            Divider().overlay(Color.white.opacity(0.10))

            // This Month / Last Month
            HStack(spacing: 0) {
                statCell(
                    label: "This Month",
                    value: centsToString(vm.summary?.thisMonthCents ?? 0)
                )
                Divider()
                    .frame(height: 40)
                    .overlay(Color.white.opacity(0.10))
                    .padding(.horizontal, 16)
                statCell(
                    label: "Last Month",
                    value: centsToString(vm.summary?.lastMonthCents ?? 0)
                )
                Spacer()
            }

            Divider().overlay(Color.white.opacity(0.10))

            // Pending Payout
            HStack(spacing: 10) {
                Image(systemName: "banknote")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending Payout")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Text(centsToString(vm.summary?.pendingPayoutCents ?? 0))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pending payout: \(centsToString(vm.summary?.pendingPayoutCents ?? 0))")
                Spacer()
            }

            if let nextDate = vm.summary?.nextPayoutDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .accessibilityHidden(true)
                    Text("Next payout: \(nextDate.formatted(.dateTime.month(.wide).day().year()))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .accessibilityLabel("Next payout date: \(nextDate.formatted(.dateTime.month(.wide).day().year()))")
                }
            }
        }
        .padding(20)
        .background(glassCard(tinted: true))
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .textCase(.uppercase)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - 2. Revenue Breakdown

    private var revenueBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Revenue Breakdown")

            VStack(spacing: 0) {
                ForEach(vm.tierRevenues) { row in
                    breakdownRow(
                        label: row.tierName,
                        detail: "\(row.memberCount) member\(row.memberCount == 1 ? "" : "s")",
                        value: centsToString(row.monthlyRevenueCents)
                    )
                    Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 16)
                }

                breakdownRow(
                    label: "Gift memberships",
                    detail: nil,
                    value: centsToString(vm.giftRevenueCents)
                )
                Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 16)

                breakdownRow(
                    label: "One-time purchases",
                    detail: nil,
                    value: centsToString(vm.oneTimePurchaseCents)
                )
                Divider().overlay(Color.white.opacity(0.12))

                // Total
                HStack {
                    Text("Total this month")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "D9A441"))
                    Spacer()
                    Text(centsToString(vm.summary?.thisMonthCents ?? 0))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total this month: \(centsToString(vm.summary?.thisMonthCents ?? 0))")
            }
            .background(glassCard(tinted: false))
        }
    }

    private func breakdownRow(label: String, detail: String?, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)\(detail.map { ", \($0)" } ?? ""): \(value)")
    }

    // MARK: - 3. Revenue Split Config

    private var revenueSplitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Revenue Split")

            VStack(alignment: .leading, spacing: 12) {
                if vm.splits.isEmpty {
                    Text("No co-host splits configured.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 4)
                } else {
                    ForEach($vm.splits) { $split in
                        SplitRow(split: $split)
                    }
                    .onDelete { vm.removeSplit(at: $0) }
                }

                if vm.splitsExceed100 {
                    Label("Splits exceed 100%. Please adjust percentages.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange.opacity(0.90))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Warning: splits exceed 100 percent. Please adjust percentages.")
                }

                // Add co-host split button (dashed gold border)
                Button(action: vm.addSplit) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Add Co-host Split")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "D9A441"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                Color(hex: "D9A441").opacity(0.70),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a co-host revenue split")

                if !vm.splits.isEmpty {
                    Button(action: {
                        Task { await vm.saveSplits(spaceId: spaceId) }
                    }) {
                        Group {
                            if vm.isSavingSplits {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color(hex: "070607"))
                            } else {
                                Text(vm.splitsSaved ? "Splits Saved" : "Save Splits")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(hex: "070607"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                vm.splitsExceed100
                                    ? Color(hex: "D9A441").opacity(0.30)
                                    : Color(hex: "D9A441")
                            )
                    )
                    .buttonStyle(.plain)
                    .disabled(vm.splitsExceed100 || vm.isSavingSplits)
                    .accessibilityLabel(vm.splitsSaved ? "Splits saved" : "Save revenue splits")
                }

                if let splitsErr = vm.splitsError {
                    Text(splitsErr)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .accessibilityLabel("Error: \(splitsErr)")
                }
            }
            .padding(16)
            .background(glassCard(tinted: false))
        }
    }

    // MARK: - 4. Tax Summary

    private var taxSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tax Summary")

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Estimated 1099 Earnings (YTD)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.70))
                        Text(centsToString(vm.ytdEarningsCents))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Estimated 1099 earnings year to date: \(centsToString(vm.ytdEarningsCents))")
                    Spacer()
                }

                Button(action: {
                    Task { await vm.generateReport(spaceId: spaceId) }
                }) {
                    Group {
                        if vm.isGeneratingReport {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(hex: "070607"))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text("Download Earnings Report (CSV)")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: "070607"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "D9A441"))
                )
                .buttonStyle(.plain)
                .disabled(vm.isGeneratingReport)
                .accessibilityLabel("Download earnings report as CSV")

                Text("AMEN provides earnings data for your records. Consult a tax professional for filing guidance.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(glassCard(tinted: false))
        }
    }

    // MARK: - 5. Payout Setup

    private var payoutSetupRow: some View {
        Button(action: { vm.showPayoutSheet = true }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "245B8F").opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color(hex: "245B8F").opacity(0.50), lineWidth: 1)
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "245B8F"))
                }
                .accessibilityHidden(true)

                Text("Manage Payout Account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(glassCard(tinted: false))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage payout account via Stripe")
        .accessibilityHint("Opens Stripe Connect onboarding")
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .accessibilityLabel("Loading earnings data")
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: {
                Task { await vm.load(spaceId: spaceId, hostUserId: hostUserId) }
            }) {
                Text("Try Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "070607"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading earnings data")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading earnings: \(message). Retry button available.")
    }

    // MARK: - Shared UI Helpers

    private func glassCard(tinted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        tinted
                            ? Color(hex: "D9A441").opacity(0.25)
                            : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.55))
            .textCase(.uppercase)
            .kerning(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    private func centsToString(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        if dollars.truncatingRemainder(dividingBy: 1) == 0 && dollars >= 1 {
            return String(format: "$%,.0f", dollars)
        }
        return String(format: "$%,.2f", dollars)
    }
}

// MARK: - Split Row

private struct SplitRow: View {
    @Binding var split: RevenueSplit

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(split.displayName.isEmpty ? "Co-host" : split.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                if !split.userId.isEmpty {
                    Text(split.userId)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("0", value: $split.percentage, format: .number)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .accessibilityLabel("Split percentage for \(split.displayName)")
                Text("%")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(split.displayName): \(Int(split.percentage)) percent")
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenCreatorEarningsDashboard(
        spaceId: "s1",
        hostUserId: "host1"
    )
    .preferredColorScheme(.dark)
}
#endif
