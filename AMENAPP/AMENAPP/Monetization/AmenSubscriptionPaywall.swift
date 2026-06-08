// AmenSubscriptionPaywall.swift
// AMENAPP — Platform Monetization
//
// Reusable paywall sheet for platform subscription tiers.
// Wraps AmenAccountPaywallView and AmenStoreKitManager into a single
// drop-in sheet that any view can present via the `.amenSubscriptionPaywall`
// view modifier or by instantiating directly.
//
// Design rules:
//   - .regularMaterial / .ultraThinMaterial for glass containers — no hardcoded colors.
//   - Color(hex: "D9A441") for gold accents.
//   - Accessibility: reduceMotion + reduceTransparency respected.
//   - Apple IAP auto-renewal disclosure required (Guideline 3.1.2).
// Written: 2026-06-08

import SwiftUI
import StoreKit

// MARK: - AmenSubscriptionPaywall

/// Reusable subscription paywall sheet.
///
/// Usage — present as a sheet with the required tier and feature context:
/// ```swift
/// .amenSubscriptionPaywall(
///     isPresented: $showPaywall,
///     requiredTier: .amenPlus,
///     feature: "AI Writing Coach"
/// )
/// ```
///
/// Or use directly in a `.sheet`:
/// ```swift
/// .sheet(isPresented: $showPaywall) {
///     AmenSubscriptionPaywall(
///         requiredTier: .creatorPro,
///         feature: "Live Streaming",
///         onDismiss: { showPaywall = false }
///     )
/// }
/// ```
struct AmenSubscriptionPaywall: View {

    // MARK: - Parameters

    /// The minimum tier the user must have to access the feature.
    let requiredTier: AmenAccountTier

    /// Human-readable name of the locked feature, shown in the headline.
    let feature: String

    /// Called when the sheet should close (user tapped "Maybe later" or upgrade succeeded).
    let onDismiss: () -> Void

    // MARK: - State

    @StateObject private var storeKit = AmenStoreKitManager.shared
    @State private var isPurchasing: Bool = false
    @State private var purchaseError: String?
    @State private var appeared: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                headerSection
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        featuresSection
                        pricingSection
                        ctaSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .task {
            await storeKit.loadProducts()
            if !reduceMotion {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        } else {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()
                // Subtle radial highlight — reduced transparency keeps it accessible
                RadialGradient(
                    colors: [
                        Color(hex: "D9A441").opacity(0.07),
                        Color.clear,
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 320
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Spacer().frame(height: 28)
                upgradeIconView
                Text("Upgrade to \(requiredTier.displayName)")
                    .font(.systemScaled(24, weight: .bold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlock \(feature) and more.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.20)
                    }
            )

            dismissButton
        }
    }

    private var upgradeIconView: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle().strokeBorder(Color(hex: "D9A441").opacity(0.45), lineWidth: 1.5)
                )
                .frame(width: 60, height: 60)
            Image(systemName: "arrow.up.circle.fill")
                .font(.systemScaled(26, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
        }
        .accessibilityHidden(true)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .padding(9)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss — maybe later")
        .padding(.top, 16)
        .padding(.trailing, 20)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.50))
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(requiredTier.featureList, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                            .frame(width: 18, height: 18)
                            .offset(y: 1)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(requiredTier.displayName)
                    .font(.systemScaled(16, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Billed monthly. Cancel anytime.")
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if let product = storeKit.products.first(
                    where: { $0.id == productIDForTier(requiredTier) }
                ) {
                    Text(product.displayPrice)
                        .font(.systemScaled(22, weight: .black))
                        .foregroundStyle(Color(hex: "D9A441"))
                    Text("/mo")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.white.opacity(0.45))
                } else {
                    Text(storeKit.isLoading ? "Loading…" : requiredTier.monthlyPrice)
                        .font(.systemScaled(22, weight: .black))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.30), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let price = storeKit.products
                .first(where: { $0.id == productIDForTier(requiredTier) })
                .map(\.displayPrice) ?? requiredTier.monthlyPrice
            return "\(requiredTier.displayName) — \(price) per month"
        }())
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if requiredTier == .enterprise {
                Button(action: openContactUs) {
                    Text("Contact Us")
                        .font(.systemScaled(16, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "D9A441"))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Contact us for Enterprise plan")
            } else {
                Button(action: onUpgrade) {
                    Group {
                        if isPurchasing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "070607")))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            Text("Upgrade to \(requiredTier.displayName)")
                                .font(.systemScaled(16, weight: .bold))
                                .foregroundStyle(Color(hex: "070607"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
                .accessibilityLabel({
                    if isPurchasing { return "Processing purchase…" }
                    let price = storeKit.products
                        .first(where: { $0.id == productIDForTier(requiredTier) })
                        .map(\.displayPrice) ?? requiredTier.monthlyPrice
                    return "Upgrade to \(requiredTier.displayName) for \(price) per month"
                }())
            }

            if let err = purchaseError {
                Text(err)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Purchase error: \(err)")
            }

            Button(action: onRestore) {
                Text("Restore Purchases")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityLabel("Restore previous purchases")

            // Apple Guideline 3.1.2 auto-renewal disclosure
            Text("Payment will be charged to your Apple ID at confirmation. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Apple ID Account Settings.")
                .font(.systemScaled(11))
                .foregroundStyle(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Subscription auto-renewal and billing disclosure")

            Button(action: onDismiss) {
                Text("Maybe later")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss paywall — maybe later")
            .accessibilityHint("Returns you to the previous screen without upgrading")
        }
    }

    // MARK: - Actions

    private func onUpgrade() {
        guard !isPurchasing else { return }
        let targetID = productIDForTier(requiredTier)
        guard let product = storeKit.products.first(where: { $0.id == targetID }) else {
            // Fallback: products not yet loaded. Try loading then retry.
            Task {
                isPurchasing = true
                purchaseError = nil
                await storeKit.loadProducts()
                guard let p = storeKit.products.first(where: { $0.id == targetID }) else {
                    purchaseError = "Could not load this subscription. Please try again."
                    isPurchasing = false
                    return
                }
                await performPurchase(p)
            }
            return
        }
        Task { await performPurchase(product) }
    }

    private func performPurchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        do {
            let success = try await storeKit.purchase(product)
            isPurchasing = false
            if success { onDismiss() }
        } catch {
            isPurchasing = false
            purchaseError = error.localizedDescription
        }
    }

    private func onRestore() {
        Task {
            isPurchasing = true
            purchaseError = nil
            await storeKit.restorePurchases()
            isPurchasing = false
            if storeKit.purchasedSubscriptions.contains(productIDForTier(requiredTier)) {
                onDismiss()
            }
        }
    }

    private func openContactUs() {
        let mailto = URL(string: "mailto:enterprise@amenapp.com?subject=Enterprise%20Plan%20Inquiry")
        let fallback = URL(string: "https://amenapp.com/enterprise")
        if let url = mailto, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = fallback {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func productIDForTier(_ tier: AmenAccountTier) -> String {
        AmenStoreKitManager.monthlyProductID(for: tier) ?? ""
    }
}

// MARK: - AmenSubscriptionPaywallModifier

/// `.amenSubscriptionPaywall(isPresented:requiredTier:feature:)` view modifier.
struct AmenSubscriptionPaywallModifier: ViewModifier {
    @Binding var isPresented: Bool
    let requiredTier: AmenAccountTier
    let feature: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                AmenSubscriptionPaywall(
                    requiredTier: requiredTier,
                    feature: feature,
                    onDismiss: { isPresented = false }
                )
            }
    }
}

// MARK: - View Extension

extension View {
    /// Presents a platform subscription paywall sheet.
    ///
    /// - Parameters:
    ///   - isPresented: Binding that controls sheet visibility.
    ///   - requiredTier: The tier the user must upgrade to.
    ///   - feature: Human-readable locked-feature name shown in the paywall.
    func amenSubscriptionPaywall(
        isPresented: Binding<Bool>,
        requiredTier: AmenAccountTier,
        feature: String
    ) -> some View {
        modifier(AmenSubscriptionPaywallModifier(
            isPresented: isPresented,
            requiredTier: requiredTier,
            feature: feature
        ))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AMEN Plus paywall") {
    Color(hex: "070607")
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenSubscriptionPaywall(
                requiredTier: .amenPlus,
                feature: "AI Writing Coach",
                onDismiss: {}
            )
        }
}

#Preview("Creator Pro paywall") {
    Color(hex: "070607")
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenSubscriptionPaywall(
                requiredTier: .creatorPro,
                feature: "Live Streaming",
                onDismiss: {}
            )
        }
}

#Preview("Church Pro paywall") {
    Color(hex: "070607")
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenSubscriptionPaywall(
                requiredTier: .churchPro,
                feature: "Live Giving",
                onDismiss: {}
            )
        }
}
#endif
