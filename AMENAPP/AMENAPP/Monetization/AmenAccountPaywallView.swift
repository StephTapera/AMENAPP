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

// MARK: - AmenAccountPaywallView

struct AmenAccountPaywallView: View {
    let requiredTier: AmenAccountTier
    let feature: String
    let onDismiss: () -> Void

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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlock \(feature) and more with \(requiredTier.displayName).")
                    .font(.system(size: 14))
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
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
        }
        .accessibilityHidden(true)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Billed monthly. Cancel anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            Spacer(minLength: 12)
            Text(requiredTier.monthlyPrice)
                .font(.system(size: 22, weight: .black))
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
            Button(action: onUpgrade) {
                Text("Upgrade to \(requiredTier.displayName)")
                    .font(.system(size: 16, weight: .bold))
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
            .accessibilityLabel("Upgrade to \(requiredTier.displayName), \(requiredTier.monthlyPrice)")

            Button(action: onDismiss) {
                Text("Maybe later")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss — maybe later")
        }
    }

    // MARK: - Actions

    private func onUpgrade() {
        // TODO: Wire to AmenAccountEntitlementService upgrade flow / StoreKit sheet
        onDismiss()
    }
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .frame(width: 18, height: 18)
                .offset(y: 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14))
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
