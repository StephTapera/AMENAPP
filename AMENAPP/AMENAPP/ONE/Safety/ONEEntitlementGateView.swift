// ONEEntitlementGateView.swift
// ONE P5-F — Subscription paywall sheet for subscriber-gated features.
//
// Rules:
//   • Always dismissible — never traps the user.
//   • No dark patterns: no guilt language on dismiss, no countdown timers.
//   • Privacy note: Apple IAP, no payment details visible to ONE.
//   • Subscription management always in iOS Settings (per App Store guidelines).

import SwiftUI
import StoreKit

struct ONEEntitlementGateView: View {
    let featureName: String
    var onDismiss: () -> Void

    @StateObject private var service = ONEEntitlementService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ONE.Spacing.xl) {
                    heroHeader
                    tierComparison
                    pricingCards
                    privacyNote
                }
                .padding(ONE.Spacing.lg)
            }
            .navigationTitle("ONE Subscriber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { onDismiss(); dismiss() }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Dismiss subscription offer")
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await service.loadProducts()
            await service.verifyWithServer()
        }
        .alert("Purchase error", isPresented: Binding(
            get: { service.purchaseError != nil },
            set: { if !$0 { service.purchaseError = nil } }
        )) {
            Button("OK") { service.purchaseError = nil }
        } message: {
            Text(service.purchaseError ?? "")
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: ONE.Spacing.sm) {
            Text("✦")
                .font(.system(size: 40))
                .accessibilityHidden(true)
            Text("ONE Subscriber")
                .font(.system(size: 24, weight: .bold))
            Text("\(featureName) is a subscriber feature.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("No ads. No engagement scoring. Your subscription funds the service.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ONE.Spacing.md)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tier comparison

    private var tierComparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tierHeader("Free", accent: .secondary)
                Divider()
                tierHeader("Subscriber ✦", accent: Color.accentColor)
            }
            .frame(height: 40)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                tierColumn(items: freeFeatures, accent: .secondary)
                Divider()
                tierColumn(items: subscriberFeatures, accent: Color.accentColor)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feature comparison table")
    }

    private func tierHeader(_ title: String, accent: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ONE.Spacing.sm)
    }

    private func tierColumn(items: [(String, Bool)], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            ForEach(items, id: \.0) { (label, included) in
                HStack(spacing: ONE.Spacing.xs) {
                    Image(systemName: included ? "checkmark" : "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(included ? accent : Color.secondary.opacity(0.4))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(included ? .primary : .secondary)
                }
                .accessibilityLabel("\(label): \(included ? "included" : "not included")")
            }
        }
        .padding(ONE.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var freeFeatures: [(String, Bool)] {
        [
            ("E2E threads", true),
            ("Moments (50/mo)", true),
            ("Witness model", true),
            ("Privacy mirror", true),
            ("Emotional safety", false),
            ("Living Threads AI", false),
            ("Encrypted vault", false),
            ("Legacy directive", false),
        ]
    }

    private var subscriberFeatures: [(String, Bool)] {
        [
            ("Everything free", true),
            ("Emotional safety", true),
            ("Living Threads AI", true),
            ("Encrypted vault", true),
            ("Legacy directive", true),
            ("Unlimited moments", true),
            ("Extended reach budget", true),
            ("Priority repair flow", true),
        ]
    }

    // MARK: - Pricing cards

    private var pricingCards: some View {
        VStack(spacing: ONE.Spacing.sm) {
            if service.products.isEmpty {
                // Static fallback while products load
                staticPricingCard(title: "Monthly", price: "$5.99/mo", note: nil, isLoading: true)
                staticPricingCard(title: "Annual", price: "$49.99/yr", note: "Save 30%", isLoading: true)
            } else {
                ForEach(service.products, id: \.id) { product in
                    productCard(product)
                }
            }
            restoreButton
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isAnnual = product.id.contains("annual")
        return Button {
            Task { await service.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAnnual ? "Annual" : "Monthly")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if isAnnual {
                        Text("Save ~30% vs monthly")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if service.isPurchasing {
                    ProgressView().controlSize(.small)
                } else {
                    Text(product.displayPrice)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isAnnual ? Color.accentColor : .primary)
                }
            }
            .padding(ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(isAnnual
                          ? Color.accentColor.opacity(0.10)
                          : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(service.isPurchasing)
        .accessibilityLabel("Subscribe \(isAnnual ? "annually" : "monthly") for \(product.displayPrice)")
    }

    private func staticPricingCard(title: String, price: String, note: String?, isLoading: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let n = note { Text(n).font(.system(size: 12)).foregroundStyle(Color.accentColor) }
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(price).font(.system(size: 16, weight: .bold))
            }
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var restoreButton: some View {
        Button {
            Task { await service.restorePurchases() }
        } label: {
            HStack(spacing: ONE.Spacing.xs) {
                if service.isVerifying {
                    ProgressView().controlSize(.mini)
                }
                Text("Restore purchases")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(service.isVerifying)
        .accessibilityLabel("Restore previous subscription purchases")
    }

    // MARK: - Privacy note

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: ONE.Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(ONE.Colors.privateIndigo)
                .font(.system(size: 13))
            Text("Payments are handled by Apple IAP. We never see your payment details. Subscription status is verified on-device. Cancel anytime from iOS Settings → Subscriptions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(ONE.Colors.privateIndigo.opacity(0.07))
        )
        .accessibilityElement(children: .combine)
    }
}
