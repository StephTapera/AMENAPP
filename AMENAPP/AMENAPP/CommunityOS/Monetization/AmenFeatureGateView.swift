// AmenFeatureGateView.swift
// AMEN App — CommunityOS/Monetization
//
// Phase 6 — Agent M1 (Plans & Entitlements)
// Generic SwiftUI gate: wraps any content view with a plan-tier check.
// Shows AmenUpgradePromptView when the required plan is not met.
//
// Usage:
//   AmenFeatureGateView(feature: .broadcastMessaging, holderId: orgId) {
//       BroadcastView()
//   }
//
// HUMAN-GATED: payment flow triggered by upgrade button goes through
// createCovenantCheckoutSession CF — no Stripe SDK on iOS.
// Written: 2026-06-05

import SwiftUI
import SafariServices

// MARK: - AmenFeatureGateView

/// Generic feature gate wrapper.
/// `checkFeature()` returns false (deny) when entitlement is not loaded — fail closed.
struct AmenFeatureGateView<Content: View>: View {

    let feature: AmenFeatureGate
    let holderId: String
    @ViewBuilder let content: () -> Content

    @StateObject private var service = AmenEntitlementService()

    var body: some View {
        Group {
            if service.checkFeature(feature) {
                content()
            } else {
                AmenUpgradePromptView(
                    requiredTier: feature.minimumTier,
                    holderId: holderId,
                    featureName: feature.displayName
                )
            }
        }
        .task {
            try? await service.loadEntitlement(for: holderId)
        }
    }
}

// MARK: - AmenUpgradePromptView

/// Paywall prompt shown when a feature is not included in the current plan.
/// Upgrade button calls `createCovenantCheckoutSession` CF (HUMAN-GATED).
struct AmenUpgradePromptView: View {

    let requiredTier: AmenPlanTier
    let holderId: String
    var featureName: String = ""

    @StateObject private var service = AmenEntitlementService()
    @State private var checkoutURL: String?
    @State private var showSafari: Bool = false
    @State private var isUpgrading: Bool = false
    @State private var upgradeError: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(featureName.isEmpty
                     ? "\(requiredTier.displayName) feature"
                     : featureName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("\(requiredTier.displayName) plan required")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Text("Upgrade to unlock this feature and support your community.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let priceUSD = requiredTier.monthlyPriceUSD, priceUSD > 0 {
                Text("$\(String(format: "%.0f", priceUSD))/month")
                    .font(.headline)
            }

            if let errorMessage = upgradeError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // HUMAN-GATED: triggers createCovenantCheckoutSession CF
            Button {
                Task { await startUpgrade() }
            } label: {
                if isUpgrading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Upgrade to \(requiredTier.displayName)")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUpgrading || checkoutURL != nil)
            .frame(minWidth: 200)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .task {
            try? await service.loadEntitlement(for: holderId)
        }
        // Present Stripe checkout URL in SafariVC when available
        .sheet(isPresented: $showSafari, onDismiss: {
            // Refresh entitlement when user returns from Stripe checkout
            Task {
                try? await service.refreshEntitlement(for: holderId)
            }
        }) {
            if let urlString = checkoutURL, let url = URL(string: urlString) {
                AmenSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Private

    private func startUpgrade() async {
        isUpgrading = true
        upgradeError = nil
        defer { isUpgrading = false }

        do {
            // HUMAN-GATED: calls createCovenantCheckoutSession CF
            let url = try await service.initiateUpgrade(to: requiredTier, for: holderId)
            checkoutURL = url
            showSafari = true
        } catch {
            upgradeError = error.localizedDescription
        }
    }
}

// MARK: - AmenSafariView (UIViewControllerRepresentable)

/// Wraps SFAmenSafariViewController for presentation inside a SwiftUI sheet.
private struct AmenAmenSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFAmenSafariViewController {
        let config = SFAmenSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFAmenSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFAmenSafariViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview("Gate — locked") {
    AmenFeatureGateView(feature: .broadcastMessaging, holderId: "preview-org") {
        Text("Broadcast content here")
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Upgrade prompt") {
    AmenUpgradePromptView(
        requiredTier: .churchPro,
        holderId: "preview-org",
        featureName: "Broadcast Messaging"
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
