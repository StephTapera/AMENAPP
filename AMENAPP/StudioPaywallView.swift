//
//  StudioPaywallView.swift
//  AMENAPP
//
//  Tier comparison + purchase flow for AMEN Studio.
//  Presented as a sheet from StudioHubView when free-tier limit is hit.
//

import SwiftUI
#if canImport(RevenueCat)
import RevenueCat
#endif

struct StudioPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = StudioSubscriptionService.shared

    @State private var selectedTier: StudioEntitlement = .creator

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 20)
                            .padding(.bottom, 28)

                        tierPicker
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        featureComparisonList
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        purchaseButton
                            .padding(.horizontal, 20)

                        restoreButton
                            .padding(.top, 10)

                        legalFooter
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.purple)
            }

            Text("Unlock AMEN Studio")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Text("Create freely. Your faith, your story, preserved forever.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Tier Picker

    private var tierPicker: some View {
        HStack(spacing: 8) {
            ForEach([StudioEntitlement.creator, .pro, .team], id: \.displayName) { tier in
                tierTab(tier)
            }
        }
    }

    private func tierTab(_ tier: StudioEntitlement) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTier = tier } } label: {
            VStack(spacing: 2) {
                Text(tier.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(tier.priceLabel)
                    .font(.system(size: 11))
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedTier == tier ? tier.accent.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selectedTier == tier ? tier.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .foregroundStyle(selectedTier == tier ? tier.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison

    private var featureComparisonList: some View {
        VStack(spacing: 0) {
            ForEach(featureRows, id: \.title) { row in
                HStack(spacing: 14) {
                    Image(systemName: row.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(row.available(selectedTier) ? selectedTier.accent : Color(.tertiaryLabel))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(row.available(selectedTier) ? .primary : .secondary)
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: row.available(selectedTier) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(row.available(selectedTier) ? selectedTier.accent : Color(.tertiaryLabel))
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.5)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selectedTier.accent.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private struct FeatureRow {
        let icon: String
        let title: String
        let detail: String?
        let available: (StudioEntitlement) -> Bool
    }

    private var featureRows: [FeatureRow] {
        [
            FeatureRow(icon: "pencil.and.scribble", title: "Unlimited Creates",
                       detail: "Write, compose, design without limits",
                       available: { $0 != .free }),
            FeatureRow(icon: "brain.head.profile", title: "AI Muse",
                       detail: "Guided prompts, scripture suggestions, style coaching",
                       available: { $0.canUseAIMuse }),
            FeatureRow(icon: "arrow.up.doc.fill", title: "Export & Share",
                       detail: "PDF, image, and social-ready exports",
                       available: { $0.canExport }),
            FeatureRow(icon: "person.2.fill", title: "Collaborative Workspaces",
                       detail: "Co-create with church teams",
                       available: { $0.canCollab }),
            FeatureRow(icon: "lock.shield.fill", title: "Legacy Vault",
                       detail: "Encrypted long-term preservation",
                       available: { $0.canUseVault }),
            FeatureRow(icon: "person.3.fill", title: "Team Workspace (10 members)",
                       detail: nil,
                       available: { $0 == .team })
        ]
    }

    // MARK: - Purchase Button

    @ViewBuilder
    private var purchaseButton: some View {
        #if canImport(RevenueCat)
        let product = matchingProduct(for: selectedTier)
        Button {
            guard let p = product else { return }
            Task { await service.purchase(p) }
        } label: {
            Group {
                if service.isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    VStack(spacing: 2) {
                        Text("Start 7-Day Free Trial")
                            .font(.system(size: 16, weight: .bold))
                        Text("then \(product?.storeProduct.localizedPriceString ?? selectedTier.priceLabel) / month")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [selectedTier.accent, selectedTier.accent.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(service.isPurchasing || product == nil)
        .opacity((service.isPurchasing || product == nil) ? 0.6 : 1)

        if let err = service.purchaseError {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        #else
        Text("Purchases unavailable — RevenueCat SDK not installed")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }

    private var restoreButton: some View {
        Button {
            #if canImport(RevenueCat)
            Task { await service.restore() }
            #endif
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var legalFooter: some View {
        Text("Subscription auto-renews. Cancel anytime in Settings. Payment charged to your Apple ID. See our Terms and Privacy Policy.")
            .font(.system(size: 11))
            .foregroundStyle(Color(.tertiaryLabel))
            .multilineTextAlignment(.center)
    }

    // MARK: - Helper

    #if canImport(RevenueCat)
    private func matchingProduct(for tier: StudioEntitlement) -> Package? {
        let monthlyIDs: [StudioEntitlement: String] = [
            .creator: "amenapp.studio.creator.monthly",
            .pro: "amenapp.studio.pro.monthly",
            .team: "amenapp.studio.team.monthly"
        ]
        guard let id = monthlyIDs[tier] else { return nil }
        return service.packages.first { $0.storeProduct.productIdentifier == id }
    }
    #endif
}
