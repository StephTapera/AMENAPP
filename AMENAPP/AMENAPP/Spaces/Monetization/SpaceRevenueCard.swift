// SpaceRevenueCard.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Owner/admin-only revenue card shown in Space settings.
// Displays total revenue and active subscriber count for a paid Space.
//
// Data source: `getSpaceRevenue` Cloud Function
//   → queries the community's Stripe Connect account for this Space's product.
//
// Visibility: caller (Space settings) must verify current user is owner/admin
//   before presenting this card.
//
// Usage:
//   SpaceRevenueCard(space: space, communityId: communityId)

import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

// MARK: - Revenue Data

private struct SpaceRevenueData {
    let totalRevenueCents: Int
    let activeSubscriberCount: Int
    let oneTimePurchaseCount: Int
    let currency: String

    var formattedTotal: String {
        let dollars = Double(totalRevenueCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - SpaceRevenueCard

/// Owner/admin-only card displaying revenue from this Space.
/// Shows total revenue and active subscriber count.
struct SpaceRevenueCard: View {

    let space: AmenSpace
    let communityId: String

    // MARK: State

    @State private var revenueData: SpaceRevenueData? = nil
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil

    private let functions = Functions.functions()

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .opacity(0.15)

            cardContent
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        }
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundGroupedRow)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(AmenTheme.Colors.amenGold.opacity(0.04))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(AmenTheme.Colors.amenGold.opacity(0.20), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
        .task { await loadRevenue() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space revenue card")
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .accessibilityHidden(true)

            Text("Revenue from this Space")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.75)
            } else {
                Button {
                    Task { await loadRevenue() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .accessibilityLabel("Refresh revenue data")
            }
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        if let error = loadError {
            errorView(message: error)
        } else if let data = revenueData {
            revenueStats(data: data)
        } else if isLoading {
            loadingPlaceholder
        } else {
            emptyState
        }
    }

    private func revenueStats(data: SpaceRevenueData) -> some View {
        HStack(spacing: 0) {
            statItem(
                value: data.formattedTotal,
                label: "Total",
                icon: "dollarsign.circle.fill",
                color: AmenTheme.Colors.amenGold
            )

            statDivider

            statItem(
                value: "\(data.activeSubscriberCount)",
                label: "Active subscribers",
                icon: "person.2.fill",
                color: .blue
            )

            if data.oneTimePurchaseCount > 0 {
                statDivider

                statItem(
                    value: "\(data.oneTimePurchaseCount)",
                    label: "One-time",
                    icon: "bolt.fill",
                    color: .green
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 40)
            .opacity(0.15)
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 20) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AmenTheme.Colors.textSecondary.opacity(0.12))
                        .frame(width: 56, height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AmenTheme.Colors.textSecondary.opacity(0.08))
                        .frame(width: 44, height: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Loading revenue data")
    }

    private var emptyState: some View {
        Text("No revenue data yet.")
            .font(.subheadline)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityLabel("No revenue data yet")
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .accessibilityLabel("Error loading revenue: \(message)")
    }

    // MARK: - Load Revenue

    private func loadRevenue() async {
        guard let spaceId = space.id, !spaceId.isEmpty else { return }
        guard !isLoading else { return }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let payload: [String: Any] = [
                "spaceId": spaceId,
                "communityId": communityId
            ]
            let result = try await functions.httpsCallable("getSpaceRevenue").call(payload)

            guard let data = result.data as? [String: Any] else {
                loadError = "Invalid response from server."
                return
            }

            let totalRevenueCents = data["totalRevenueCents"] as? Int ?? 0
            let activeSubscriberCount = data["activeSubscriberCount"] as? Int ?? 0
            let oneTimePurchaseCount = data["oneTimePurchaseCount"] as? Int ?? 0
            let currency = data["currency"] as? String ?? "usd"

            revenueData = SpaceRevenueData(
                totalRevenueCents: totalRevenueCents,
                activeSubscriberCount: activeSubscriberCount,
                oneTimePurchaseCount: oneTimePurchaseCount,
                currency: currency
            )

        } catch {
            loadError = "Unable to load revenue data."
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SpaceRevenueCard — loaded") {
    VStack {
        SpaceRevenueCard(
            space: AmenSpace(
                communityId: "com1",
                type: .bibleStudy,
                title: "Deep Dive: Romans",
                description: nil,
                avatarURL: nil,
                createdBy: "user1",
                createdAt: Timestamp(date: Date()),
                accessPolicy: .recurring,
                priceConfig: SpacePriceConfig(amountCents: 999, currency: "usd", interval: "month"),
                sharedWith: []
            ),
            communityId: "com1"
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
#endif
