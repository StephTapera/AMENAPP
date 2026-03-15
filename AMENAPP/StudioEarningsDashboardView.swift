// StudioEarningsDashboardView.swift
// AMEN Studio — Creator Earnings Dashboard
// Meaningful business intelligence, not vanity metrics

import SwiftUI
import Charts

struct StudioEarningsDashboardView: View {
    @StateObject private var service = StudioDataService.shared
    @State private var summary: StudioEarningsSummary?
    @State private var transactions: [StudioTransaction] = []
    @State private var isLoading = true
    @State private var selectedPeriod: EarningsPeriod = .thisMonth
    @Environment(\.dismiss) private var dismiss

    enum EarningsPeriod: String, CaseIterable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case allTime = "All Time"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        loadingState
                    } else {
                        periodPicker
                        if let summary = summary {
                            earningsOverview(summary)
                            revenueBreakdown(summary)
                            activityMetrics(summary)
                        }
                        transactionsList
                        payoutInfoSection
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .task {
                // P0-C FIX: Use withTaskGroup instead of async let tuple so child tasks
                // are properly cancelled/awaited when the parent .task scope is cancelled
                // (e.g. view disappears). The async let + tuple pattern can trigger
                // swift_task_dealloc / asyncLet_finish_after_task_completion crashes.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { @MainActor in
                        summary = await service.fetchEarningsSummary()
                    }
                    group.addTask { @MainActor in
                        transactions = await service.fetchTransactions()
                    }
                }
                isLoading = false
            }
        }
    }

    // MARK: - Period Picker

    @ViewBuilder
    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(EarningsPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Earnings Overview

    @ViewBuilder
    private func earningsOverview(_ summary: StudioEarningsSummary) -> some View {
        VStack(spacing: 16) {
            // Net earnings hero
            VStack(spacing: 4) {
                Text("Net Earnings")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                Text(summary.netRevenue.formatted(.currency(code: "USD")))
                    .font(.custom("OpenSans-Bold", size: 38))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("After \(Int(AMENFeeConfig.productSaleFeePercent * 100))% AMEN fee")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)

            // Quick stats row
            HStack(spacing: 1) {
                earningsStat(
                    value: summary.grossRevenue.formatted(.currency(code: "USD")),
                    label: "Gross",
                    color: .primary
                )
                Divider().frame(height: 40)
                earningsStat(
                    value: summary.platformFees.formatted(.currency(code: "USD")),
                    label: "Platform Fee",
                    color: .secondary
                )
                Divider().frame(height: 40)
                earningsStat(
                    value: summary.pendingPayout.formatted(.currency(code: "USD")),
                    label: "Pending Payout",
                    color: Color(red: 0.18, green: 0.62, blue: 0.36)
                )
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    // MARK: - Revenue Breakdown

    @ViewBuilder
    private func revenueBreakdown(_ summary: StudioEarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Revenue Sources")

            VStack(spacing: 8) {
                if summary.serviceRevenue > 0 {
                    revenueRow(
                        icon: "briefcase.fill",
                        label: "Services",
                        amount: summary.serviceRevenue,
                        total: summary.grossRevenue,
                        color: Color(red: 0.15, green: 0.45, blue: 0.90)
                    )
                }
                if summary.productRevenue > 0 {
                    revenueRow(
                        icon: "bag.fill",
                        label: "Products",
                        amount: summary.productRevenue,
                        total: summary.grossRevenue,
                        color: Color(red: 0.55, green: 0.25, blue: 0.88)
                    )
                }
                if summary.commissionRevenue > 0 {
                    revenueRow(
                        icon: "pencil.line",
                        label: "Commissions",
                        amount: summary.commissionRevenue,
                        total: summary.grossRevenue,
                        color: Color(red: 0.88, green: 0.55, blue: 0.15)
                    )
                }
                if summary.bookingRevenue > 0 {
                    revenueRow(
                        icon: "calendar.fill",
                        label: "Bookings",
                        amount: summary.bookingRevenue,
                        total: summary.grossRevenue,
                        color: Color(red: 0.18, green: 0.62, blue: 0.55)
                    )
                }
                if summary.supportRevenue > 0 {
                    revenueRow(
                        icon: "heart.fill",
                        label: "Support",
                        amount: summary.supportRevenue,
                        total: summary.grossRevenue,
                        color: Color(red: 0.88, green: 0.25, blue: 0.35)
                    )
                }
                if summary.grossRevenue == 0 {
                    Text("No revenue yet — start by listing a service or product.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Activity Metrics

    @ViewBuilder
    private func activityMetrics(_ summary: StudioEarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Activity")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCell(
                    icon: "envelope.fill",
                    label: "Inquiries",
                    value: "\(summary.inquiryCount)",
                    color: Color(red: 0.15, green: 0.45, blue: 0.90)
                )
                metricCell(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Conversion Rate",
                    value: "\(Int(summary.inquiryConversionRate * 100))%",
                    color: Color(red: 0.18, green: 0.62, blue: 0.36)
                )
                metricCell(
                    icon: "bag.fill",
                    label: "Transactions",
                    value: "\(summary.totalTransactions)",
                    color: Color(red: 0.55, green: 0.25, blue: 0.88)
                )
                metricCell(
                    icon: "person.2.fill",
                    label: "New Collaborators",
                    value: "\(summary.newCollaborators)",
                    color: Color(red: 0.88, green: 0.55, blue: 0.15)
                )
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Transactions List

    @ViewBuilder
    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recent Transactions")

            if transactions.isEmpty {
                Text("No transactions yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(transactions.prefix(10)) { tx in
                    transactionRow(tx)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func transactionRow(_ tx: StudioTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tx.transactionType == .productSale ? "bag.fill" : "briefcase.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.relatedItemTitle)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .lineLimit(1)
                Text(tx.transactionType.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.netAmount.formatted(.currency(code: tx.currency)))
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                Text(tx.status.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tx.status.color)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Payout Info

    @ViewBuilder
    private var payoutInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Payout Settings")

            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your bank account")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    Text("Set up payouts to receive your earnings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))

            Text("AMEN pays out on a weekly schedule. Minimum payout is $10.00. Identity verification required.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Loading State

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 20) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 100)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 20)
        .redacted(reason: .placeholder)
    }

    // MARK: - Reusable Subviews

    @ViewBuilder
    private func earningsStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func revenueRow(icon: String, label: String, amount: Double, total: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)

            Spacer()

            // Progress bar
            let fraction = total > 0 ? min(amount / total, 1.0) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray4))
                    .frame(width: 60, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 60 * fraction, height: 6)
            }

            Text(amount.formatted(.currency(code: "USD")))
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func metricCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 16))
            .foregroundStyle(.primary)
    }
}
