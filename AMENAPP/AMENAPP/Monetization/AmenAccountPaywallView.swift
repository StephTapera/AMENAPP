// AmenAccountPaywallView.swift
// AMENAPP — Platform Monetization
//
// Platform-level paywall sheet presented when a user tries to access a
// feature that requires a higher account tier.
//
// Design rules:
//   - .ultraThinMaterial for all glass containers
//   - Color(hex: "D9A441") for gold accents (not Color.amenGold)
//   - No glass-on-glass stacking
//   - 4-space indentation
//   - Accessibility: reduceTransparency + reduceMotion respected
// Written: 2026-06-05

import SwiftUI
import UIKit

// MARK: - AmenAccountPaywallView

struct AmenAccountPaywallView: View {
    let requiredTier: AmenAccountTier
    let feature: String
    let onDismiss: () -> Void

    @StateObject private var storeKit = AmenPlatformStoreKitService.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String? = nil
    @State private var restoreMessage: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .task { await AmenPlatformStoreKitService.shared.loadProducts() }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        } else {
            Color(hex: "070607").ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Spacer().frame(height: 28)
                upgradeIcon
                Text("Upgrade to \(requiredTier.displayName)")
                    .font(.systemScaled(24, weight: .bold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlock \(feature) and more with \(requiredTier.displayName).")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.20)
                    }
            )

            dismissButton
        }
    }

    private var upgradeIcon: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
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
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Maybe later — dismiss paywall")
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
                    PaywallFeatureRow(text: item)
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
            Text(requiredTier.monthlyPrice)
                .font(.systemScaled(22, weight: .black))
                .foregroundStyle(Color(hex: "D9A441"))
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
        .accessibilityLabel("\(requiredTier.displayName) — \(requiredTier.monthlyPrice)")
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if requiredTier == .enterprise {
                // Enterprise subscriptions are handled manually — open contact URL.
                Button(action: openContactUs) {
                    Text("Contact Us")
                        .font(.systemScaled(16, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "D9A441"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(hex: "D9A441"), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Contact us to set up an Enterprise plan")
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(hex: "D9A441"), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isRestoring)
                .accessibilityLabel(
                    isPurchasing
                        ? "Processing purchase"
                        : "Upgrade to \(requiredTier.displayName), \(requiredTier.monthlyPrice)"
                )

                Button(action: onRestorePurchases) {
                    HStack(spacing: 8) {
                        if isRestoring {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "D9A441")))
                        }
                        Text(isRestoring ? "Restoring…" : "Restore Purchases")
                            .font(.systemScaled(14, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "D9A441"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isRestoring)
                .accessibilityLabel(isRestoring ? "Restoring purchases" : "Restore previous purchases")
            }

            if let purchaseError {
                Text(purchaseError)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Purchase error: \(purchaseError)")
            }

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .accessibilityLabel(restoreMessage)
            }

            // C-7: Apple App Store required auto-renewal disclosure (Guideline 3.1.2).
            iapDisclosureText

            Button(action: onDismiss) {
                Text("Maybe later")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss — maybe later")
        }
    }

    private var iapDisclosureText: some View {
        Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period. Manage or cancel subscriptions in your Apple ID Account Settings.")
            .font(.systemScaled(11))
            .foregroundStyle(Color.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Subscription auto-renewal and billing disclosure")
    }

    // MARK: - Actions

    private func onUpgrade() {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        restoreMessage = nil
        Task {
            do {
                try await storeKit.purchase(requiredTier)
                isPurchasing = false
                onDismiss()
            } catch {
                isPurchasing = false
                purchaseError = error.localizedDescription
            }
        }
    }

    private func onRestorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        purchaseError = nil
        restoreMessage = nil
        Task {
            do {
                try await storeKit.restorePurchases()
                isRestoring = false
                restoreMessage = "Purchases restored. If access does not update immediately, reopen AMEN."
            } catch {
                isRestoring = false
                purchaseError = error.localizedDescription
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
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .frame(width: 18, height: 18)
                .offset(y: 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - AmenLivePaywallModifier

/// Presents `AmenAccountPaywallView` as a `.sheet` when `isPresented` is true.
///
/// Usage:
///   ```swift
///   view.amenPaywall(isPresented: $showPaywall, requiredTier: .creatorPro, feature: "Live Streaming")
///   ```
struct AmenLivePaywallModifier: ViewModifier {
    @Binding var isPresented: Bool
    let requiredTier: AmenAccountTier
    let feature: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                AmenAccountPaywallView(
                    requiredTier: requiredTier,
                    feature: feature,
                    onDismiss: { isPresented = false }
                )
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches a platform-tier paywall sheet that presents when `isPresented` is true.
    ///
    /// - Parameters:
    ///   - isPresented: Binding that controls sheet presentation.
    ///   - requiredTier: Minimum tier needed to access the feature.
    ///   - feature: Human-readable feature name shown in the paywall headline.
    func amenPaywall(
        isPresented: Binding<Bool>,
        requiredTier: AmenAccountTier,
        feature: String
    ) -> some View {
        modifier(AmenLivePaywallModifier(
            isPresented: isPresented,
            requiredTier: requiredTier,
            feature: feature
        ))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("creatorPro paywall") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        Color.clear
    }
    .sheet(isPresented: .constant(true)) {
        AmenAccountPaywallView(
            requiredTier: .creatorPro,
            feature: "Live Streaming",
            onDismiss: {}
        )
    }
}

#Preview("churchPro paywall") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        Color.clear
    }
    .sheet(isPresented: .constant(true)) {
        AmenAccountPaywallView(
            requiredTier: .churchPro,
            feature: "Live Giving",
            onDismiss: {}
        )
    }
}

#Preview("amenPlus paywall") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        Color.clear
    }
    .sheet(isPresented: .constant(true)) {
        AmenAccountPaywallView(
            requiredTier: .amenPlus,
            feature: "AI Writing Coach",
            onDismiss: {}
        )
    }
}
#endif
