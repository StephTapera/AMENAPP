// AmenSpacePaywallView.swift
// AMEN Spaces — Monetization: Tier selection paywall sheet
//
// Glass rule: overlay chrome uses .ultraThinMaterial; tier cards are matte.
// Presented as a .sheet — consumer wraps in sheet(isPresented:).
// Written: 2026-06-02

import SwiftUI
import FirebaseAnalytics

// MARK: - Paywall View

struct AmenSpacePaywallView: View {
    let space: AmenConnectSpacesSpace
    let tiers: [AmenSpaceSubscriptionTier]
    let onSelectTier: (AmenSpaceSubscriptionTier) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sortedTiers: [AmenSpaceSubscriptionTier] {
        tiers.filter { $0.isActive }.sorted { $0.order < $1.order }
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                paywallHeader
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(sortedTiers) { tier in
                            TierCard(
                                tier: tier,
                                onSelect: { onSelectTier(tier) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .onAppear {
            Analytics.logEvent("space_paywall_viewed", parameters: nil)
        }
    }

    // MARK: - Header

    private var paywallHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Spacer().frame(height: 24)
                lockIcon
                Text("Join \(space.name) to unlock")
                    .font(.systemScaled(22, weight: .bold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Choose a membership tier to access content and community features.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.25)
                    }
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(9)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    )
            }
            .accessibilityLabel("Dismiss paywall")
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }

    private var lockIcon: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color(hex: "D9A441").opacity(0.40), lineWidth: 1))
                .frame(width: 56, height: 56)
            Image(systemName: "lock.fill")
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tier Card (matte)

private struct TierCard: View {
    let tier: AmenSpaceSubscriptionTier
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.name)
                        .font(.systemScaled(17, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(tier.description)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                priceStack
            }

            badgeRow

            if !tier.features.isEmpty {
                FeatureBulletList(features: tier.features)
            }

            ctaButton
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            tier.isFreeTier
                                ? Color.white.opacity(0.12)
                                : Color(hex: "D9A441").opacity(0.30),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Price Stack

    @ViewBuilder
    private var priceStack: some View {
        if tier.isFreeTier {
            Text("Free")
                .font(.systemScaled(24, weight: .black))
                .foregroundStyle(Color.white)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(monthlyPriceString)
                        .font(.systemScaled(24, weight: .black))
                        .foregroundStyle(Color.white)
                    Text("/mo")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                if let annualCents = tier.annualPriceCents {
                    let annualEquivMonthly = annualCents / 12
                    let savingsPct = savingsPercent(annualEquivMonthly: annualEquivMonthly)
                    if savingsPct > 0 {
                        Text("Save \(savingsPct)% annually")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                    }
                }
            }
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var badgeRow: some View {
        let hasBadges = tier.introMonths != nil || tier.annualPriceCents != nil && !tier.isFreeTier
        if hasBadges {
            HStack(spacing: 8) {
                if let introMonths = tier.introMonths, let introCents = tier.introPriceCents {
                    IntroBadge(months: introMonths, priceCents: introCents)
                }
                if let annualCents = tier.annualPriceCents, !tier.isFreeTier {
                    let equiv = annualCents / 12
                    let pct = savingsPercent(annualEquivMonthly: equiv)
                    if pct > 0 {
                        AnnualBadge(savingsPercent: pct)
                    }
                }
            }
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button(action: onSelect) {
            Text(tier.isFreeTier ? "Join for free" : "Join — \(monthlyPriceString)/mo")
                .font(.systemScaled(15, weight: .bold))
                .foregroundStyle(Color(hex: "070607"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "D9A441"))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tier.isFreeTier ? "Join \(tier.name) for free" : "Join \(tier.name) for \(monthlyPriceString) per month")
    }

    // MARK: - Helpers

    private var monthlyPriceString: String {
        guard tier.monthlyPriceCents > 0 else { return "Free" }
        let dollars = Double(tier.monthlyPriceCents) / 100.0
        if dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))"
        }
        return String(format: "$%.2f", dollars)
    }

    private func savingsPercent(annualEquivMonthly: Int) -> Int {
        guard tier.monthlyPriceCents > 0 else { return 0 }
        let saving = tier.monthlyPriceCents - annualEquivMonthly
        guard saving > 0 else { return 0 }
        return Int((Double(saving) / Double(tier.monthlyPriceCents)) * 100)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [tier.name]
        if tier.isFreeTier {
            parts.append("Free")
        } else {
            parts.append("\(monthlyPriceString) per month")
        }
        parts.append(contentsOf: tier.features)
        return parts.joined(separator: ". ")
    }
}

// MARK: - Feature Bullet List (matte)

private struct FeatureBulletList: View {
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .frame(width: 14, height: 14)
                        .offset(y: 2)
                    Text(feature)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Intro Pricing Badge

private struct IntroBadge: View {
    let months: Int
    let priceCents: Int

    private var label: String {
        let dollars = Double(priceCents) / 100.0
        let priceStr = dollars.truncatingRemainder(dividingBy: 1) == 0
            ? "$\(Int(dollars))"
            : String(format: "$%.2f", dollars)
        return "First \(months) mo. at \(priceStr)/mo"
    }

    var body: some View {
        Text(label)
            .font(.systemScaled(10, weight: .semibold))
            .foregroundStyle(Color(hex: "070607"))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(hex: "D9A441"))
            )
            .accessibilityLabel("Intro pricing: \(label)")
    }
}

// MARK: - Annual Savings Badge

private struct AnnualBadge: View {
    let savingsPercent: Int

    var body: some View {
        Text("Save \(savingsPercent)% yearly")
            .font(.systemScaled(10, weight: .semibold))
            .foregroundStyle(Color(hex: "D9A441"))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(hex: "D9A441").opacity(0.15))
                    .overlay(Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.40), lineWidth: 1))
            )
            .accessibilityLabel("Save \(savingsPercent) percent with annual plan")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenSpacePaywallView(
        space: AmenConnectSpacesSpace(
            id: "s1",
            name: "Reformation Church",
            type: .worship,
            memberIds: [],
            careSensitivity: false,
            createdBy: "host1",
            createdAt: Date(),
            updatedAt: Date()
        ),
        tiers: [
            AmenSpaceSubscriptionTier(
                id: "t0",
                spaceId: "s1",
                name: "Community",
                description: "Join the community feed and see what God is doing.",
                monthlyPriceCents: 0,
                annualPriceCents: nil,
                features: ["Space feed access", "Public announcements"],
                order: 0,
                isActive: true,
                isFreeTier: true,
                storeKitProductId: nil,
                introMonths: nil,
                introPriceCents: nil,
                createdAt: Date()
            ),
            AmenSpaceSubscriptionTier(
                id: "t1",
                spaceId: "s1",
                name: "Member",
                description: "Full access to live services, replays, and chat.",
                monthlyPriceCents: 999,
                annualPriceCents: 9588,
                features: ["Live room access", "Replay library", "Chat channels", "AI recap"],
                order: 1,
                isActive: true,
                isFreeTier: false,
                storeKitProductId: "com.amen.spaces.member.monthly",
                introMonths: 2,
                introPriceCents: 499,
                createdAt: Date()
            ),
            AmenSpaceSubscriptionTier(
                id: "t2",
                spaceId: "s1",
                name: "Founding Member",
                description: "All Member benefits plus direct access to the pastor and AI study tools.",
                monthlyPriceCents: 2499,
                annualPriceCents: 23988,
                features: ["Everything in Member", "Study companion", "AI transcript search", "AI clips", "Direct messaging"],
                order: 3,
                isActive: true,
                isFreeTier: false,
                storeKitProductId: "com.amen.spaces.founding.monthly",
                introMonths: nil,
                introPriceCents: nil,
                createdAt: Date()
            ),
        ],
        onSelectTier: { _ in },
        onDismiss: {}
    )
}
#endif
