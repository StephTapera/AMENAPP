//
//  CreatorDashboardView.swift
//  AMENAPP
//
//  Creator Studio dashboard — revenue metrics, AI forecast, and monetization tools.
//

import SwiftUI
import Charts
import FirebaseAuth

// MARK: - CreatorDashboardView

struct CreatorDashboardView: View {

    var userId: String = ""

    @StateObject private var vm = CreatorViewModel()
    @State private var showMonetization = false

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenGold   = Color(red: 0.96, green: 0.62, blue: 0.04)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    private var isNewCreator: Bool {
        vm.profile.lifetimeEarnings == 0
            && vm.profile.subscriberCount == 0
            && vm.profile.monthlyRevenue == 0
    }

    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView()
                        .tint(amenPurple)
                        .scaleEffect(1.4)
                } else if isNewCreator {
                    onboardingCard
                } else {
                    dashboardContent
                }
            }
            .navigationTitle("Creator Studio")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if vm.profile.verificationStatus == .verified {
                        CreatorTrustBadgeView(
                            trustScore: vm.profile.trustScore,
                            verificationStatus: vm.profile.verificationStatus
                        )
                    }
                    Button {
                        // share profile
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .onAppear {
                Task { await vm.load(userId: userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "") : userId) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Onboarding Card

    private var onboardingCard: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Gradient banner
                ZStack {
                    LinearGradient(
                        colors: [amenPurple, Color(red: 0.94, green: 0.28, blue: 0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                        Text("Enable Creator Mode")
                            .font(AMENFont.bold(26))
                            .foregroundStyle(.white)
                        Text("Earn from your content, get tips,\nsell digital goods")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 36)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: CGRect(x: 0, y: 0, width: 1000, height: 1000)))

                VStack(spacing: 16) {
                    Button {
                        Task { await vm.enableCreator() }
                    } label: {
                        Text("Get Started")
                            .font(AMENFont.bold(17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [amenPurple, Color(red: 0.60, green: 0.28, blue: 0.90)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: amenPurple.opacity(0.4), radius: 14, y: 5)
                            )
                    }
                    .buttonStyle(CoCreationPressStyle())

                    Text("Free to enable · No hidden fees")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {

                // ── Hero Metric ───────────────────────────────────────
                heroMetricCard

                // ── 2×2 Metric Grid ───────────────────────────────────
                LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricCard(
                        icon: "person.2.fill",
                        label: "Subscribers",
                        value: "\(vm.profile.subscriberCount)",
                        color: Color(red: 0.20, green: 0.55, blue: 0.95)
                    )
                    MetricCard(
                        icon: "heart.circle.fill",
                        label: "Tips Received",
                        value: formattedTips,
                        color: Color(red: 0.94, green: 0.28, blue: 0.64)
                    )
                    MetricCard(
                        icon: "tag.fill",
                        label: "Goods Sold",
                        value: "\(totalSalesCount)",
                        color: Color(red: 0.20, green: 0.75, blue: 0.45)
                    )
                    MetricCard(
                        icon: "pencil.circle.fill",
                        label: "Posts This Month",
                        value: "—",
                        color: amenPurple
                    )
                }

                // ── Revenue Chart ─────────────────────────────────────
                if !vm.profile.revenueHistory.isEmpty {
                    revenueChartCard
                }

                // ── AI Forecast ───────────────────────────────────────
                aiForeastCard

                // ── Next Move ─────────────────────────────────────────
                if !vm.profile.aiNextMoveRecommendation.isEmpty {
                    nextMoveCard
                }

                // ── Monetization Link ─────────────────────────────────
                NavigationLink(destination: MonetizationToolsView(vm: vm)) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(amenGold.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(amenGold)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Monetization Tools")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.white)
                            Text("Subscriptions, tips, digital goods")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(amenGold.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(CoCreationPressStyle())

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Hero Metric Card

    private var heroMetricCard: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Month")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.55))
                Text(vm.formattedMonthlyRevenue)
                    .font(AMENFont.bold(44))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                    Text("Trending up")
                        .font(AMENFont.semiBold(13))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.80, blue: 0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(red: 0.20, green: 0.80, blue: 0.45).opacity(0.15)))

                Text("Lifetime: \(vm.formattedLifetime)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [amenPurple.opacity(0.5), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Revenue Chart

    private var revenueChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revenue History")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white.opacity(0.65))

            Chart(vm.profile.revenueHistory) { point in
                BarMark(
                    x: .value("Month", point.month),
                    y: .value("Revenue", point.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [amenPurple, Color(red: 0.94, green: 0.28, blue: 0.64)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.45))
                        .font(AMENFont.regular(10))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.45))
                        .font(AMENFont.regular(10))
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - AI Forecast Card

    private var aiForeastCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(amenPurple)
                    Text("AI Forecast")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    Task { await vm.refreshAIProjection() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(CoCreationPressStyle())
            }

            Text("Based on your growth…")
                .font(AMENFont.regular(13))
                .foregroundStyle(.white.opacity(0.45))

            Text(vm.formattedProjection)
                .font(AMENFont.bold(24))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(amenPurple.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Next Move Card

    private var nextMoveCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(amenGold)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("Your Next Move")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(amenGold.opacity(0.85))
                Text(vm.profile.aiNextMoveRecommendation)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(amenGold.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private var formattedTips: String {
        // Placeholder — sum would come from a tips sub-collection
        return "$0"
    }

    private var totalSalesCount: Int {
        vm.profile.digitalGoods.reduce(0) { $0 + $1.salesCount }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(AMENFont.bold(22))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(AMENFont.regular(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
