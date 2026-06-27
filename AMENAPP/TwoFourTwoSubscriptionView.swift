import SwiftUI
import StoreKit

// MARK: - Product ID Constants for 242 Hub Tiers

private extension AMENSubscriptionTier {
    /// App Store Connect product identifier for this tier.
    /// Returns `nil` for `.free` and `.enterprise` (not purchasable via StoreKit).
    /// Replace these with real IDs before App Store submission.
    var storeKitProductID: String? {
        switch self {
        case .free:       return nil
        case .grow:       return "com.amen.twofourtwohub.grow.monthly"
        case .lead:       return "com.amen.twofourtwohub.lead.monthly"
        case .enterprise: return nil   // Contact sales — handled via email
        }
    }
}

// MARK: - TwoFourTwoSubscriptionView

struct TwoFourTwoSubscriptionView: View {
    @Binding var currentTier: AMENSubscriptionTier
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    // StoreKit state
    @State private var products: [Product] = []
    @State private var isPurchasing: AMENSubscriptionTier? = nil
    @State private var isRestoring = false
    @State private var purchaseError: String?
    @State private var restoreMessage: String?
    @State private var showPurchaseError = false

    private let tiers: [(AMENSubscriptionTier, String, [String])] = [
        (.grow,       "For personal growth",
         ["Sermon Library search", "Mentorship matching", "Intercessors Network", "Covenant Academy", "Living Memory (full access)"]),
        (.lead,       "For church & ministry leaders",
         ["Everything in Grow", "Flock Intelligence briefings", "Covenant Metrics", "Prayer Wall elder tools", "Pastoral care dashboard"]),
        (.enterprise, "For organizations",
         ["Everything in Lead", "Multi-campus support", "API access", "Dedicated onboarding", "Custom integrations"]),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 12).padding(.bottom, 20)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 8) {
                            Text("242 Resources").font(.systemScaled(28, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Text("Unlock the full depth of Acts 2:42")
                                .font(.systemScaled(14, design: .rounded)).foregroundColor(.white.opacity(0.45)).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28).padding(.bottom, 28)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 12)

                        // Free tier note
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Color(red: 0.20, green: 0.72, blue: 0.44))
                            Text("Core features are always free").font(.systemScaled(13, design: .rounded)).foregroundColor(.white.opacity(0.55))
                        }
                        .padding(.bottom, 24)
                        .opacity(appeared ? 1 : 0)

                        // Tier cards
                        VStack(spacing: 12) {
                            ForEach(Array(tiers.enumerated()), id: \.offset) { index, item in
                                let (tier, subtitle, features) = item
                                TierCard(
                                    tier: tier,
                                    subtitle: subtitle,
                                    features: features,
                                    isCurrent: currentTier == tier,
                                    isPurchasing: isPurchasing == tier,
                                    livePrice: livePrice(for: tier)
                                ) {
                                    handleSelect(tier: tier)
                                }
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.08 + 0.15), value: appeared)
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 16)

                        restoreSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) { appeared = true }
        }
        .task { await loadProducts() }
        .alert("Purchase Error", isPresented: $showPurchaseError, presenting: purchaseError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Live Price Helper

    private func livePrice(for tier: AMENSubscriptionTier) -> String? {
        guard let productID = tier.storeKitProductID else { return nil }
        return products.first(where: { $0.id == productID })?.displayPrice
    }

    private var restoreSection: some View {
        VStack(spacing: 8) {
            Button(action: restorePurchases) {
                HStack(spacing: 8) {
                    if isRestoring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.91, green: 0.69, blue: 0.26)))
                    }
                    Text(isRestoring ? "Restoring…" : "Restore Purchases")
                        .font(.systemScaled(14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(red: 0.91, green: 0.69, blue: 0.26))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing != nil)
            .accessibilityLabel(isRestoring ? "Restoring purchases" : "Restore previous purchases")

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.systemScaled(12, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(restoreMessage)
            }
        }
    }

    // MARK: - Actions

    private func handleSelect(tier: AMENSubscriptionTier) {
        switch tier {
        case .enterprise:
            if let url = URL(string: "mailto:amenappmarketing@gmail.com?subject=Enterprise%20Inquiry") {
                UIApplication.shared.open(url)
            }
        case .free:
            currentTier = tier
            dismiss()
        case .grow, .lead:
            guard let productID = tier.storeKitProductID else {
                currentTier = tier
                dismiss()
                return
            }
            guard let product = products.first(where: { $0.id == productID }) else {
                purchaseError = "Purchases are still loading. Please try again in a moment."
                showPurchaseError = true
                return
            }
            purchase(product, for: tier)
        }
    }

    private func purchase(_ product: Product, for tier: AMENSubscriptionTier) {
        isPurchasing = tier
        purchaseError = nil
        Task {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await transaction.finish()
                        await MainActor.run {
                            isPurchasing = nil
                            currentTier = tier
                            dismiss()
                        }
                    case .unverified:
                        await MainActor.run {
                            isPurchasing = nil
                            purchaseError = "Purchase verification failed. Please contact support."
                            showPurchaseError = true
                        }
                    }
                case .pending:
                    // Ask-to-Buy — dismiss sheet; entitlement granted when approved.
                    await MainActor.run { isPurchasing = nil }
                case .userCancelled:
                    await MainActor.run { isPurchasing = nil }
                @unknown default:
                    await MainActor.run { isPurchasing = nil }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = nil
                    purchaseError = error.localizedDescription
                    showPurchaseError = true
                }
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        purchaseError = nil
        restoreMessage = nil
        Task {
            do {
                try await AppStore.sync()
                var restoredTier: AMENSubscriptionTier?
                for await result in Transaction.currentEntitlements {
                    guard case .verified(let transaction) = result,
                          transaction.revocationDate == nil,
                          let tier = AMENSubscriptionTier.allCases.first(where: { $0.storeKitProductID == transaction.productID }) else {
                        continue
                    }
                    restoredTier = tier
                    break
                }
                await MainActor.run {
                    isRestoring = false
                    if let restoredTier {
                        currentTier = restoredTier
                        restoreMessage = "Restored \(restoredTier.displayName)."
                    } else {
                        restoreMessage = "No active purchases were found for this Apple ID."
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    purchaseError = "Could not restore purchases. \(error.localizedDescription)"
                    showPurchaseError = true
                }
            }
        }
    }

    private func loadProducts() async {
        let ids = AMENSubscriptionTier.allCases.compactMap(\.storeKitProductID)
        guard !ids.isEmpty else { return }
        do {
            let fetched = try await Product.products(for: ids)
            await MainActor.run {
                products = fetched.sorted { $0.price < $1.price }
            }
        } catch {
            // Non-fatal — fall back to static price strings already on the tier model.
        }
    }
}

// MARK: - TierCard

private struct TierCard: View {
    let tier: AMENSubscriptionTier
    let subtitle: String
    let features: [String]
    let isCurrent: Bool
    let isPurchasing: Bool
    var livePrice: String?
    let action: () -> Void

    private var displayPrice: String {
        if tier == .enterprise { return "Contact sales" }
        return livePrice ?? tier.price
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tier.displayName).font(.systemScaled(18, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        if isCurrent {
                            Text("current").font(.systemScaled(10, weight: .medium, design: .rounded)).foregroundColor(tier.badgeColor)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(tier.badgeColor.opacity(0.15)))
                        }
                    }
                    Text(subtitle).font(.systemScaled(12, design: .rounded)).foregroundColor(.white.opacity(0.40))
                }
                Spacer()
                Text(displayPrice).font(.systemScaled(13, weight: .medium, design: .rounded)).foregroundColor(tier.badgeColor)
            }
            Divider().background(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(features, id: \.self) { f in
                    HStack(spacing: 8) {
                        Circle().fill(tier.badgeColor).frame(width: 4, height: 4)
                        Text(f).font(.systemScaled(12, design: .rounded)).foregroundColor(.white.opacity(0.60))
                    }
                }
            }
            Button(action: action) {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(isCurrent ? Color.white.opacity(0.40) : Color.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(tier.isContactSales ? "Contact Sales" : isCurrent ? "Current Plan" : "Unlock \(tier.displayName)")
                            .font(.systemScaled(14, weight: .semibold, design: .rounded))
                            .foregroundColor(isCurrent ? .white.opacity(0.40) : .white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isCurrent ? Color.white.opacity(0.06) : tier.badgeColor.opacity(0.85)))
            }
            .disabled(isCurrent || isPurchasing)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 1, opacity: 0.04))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isCurrent ? tier.badgeColor.opacity(0.40) : Color.white.opacity(0.08), lineWidth: isCurrent ? 1 : 0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            tier.isContactSales
                ? "Enterprise plan — contact sales"
                : isCurrent
                    ? "\(tier.displayName) — current plan"
                    : "Unlock \(tier.displayName) — \(displayPrice)"
        )
    }
}
