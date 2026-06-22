// AmenPlanComparisonView.swift
// AMEN App — CommunityOS/Monetization
//
// Phase 6 — Agent M1 (Plans & Entitlements)
// Plan comparison screen: horizontal plan cards + feature grid.
// White card / gray background design (Liquid Glass — no glass-on-glass).
//
// HUMAN-GATED: "Select" button triggers createCovenantCheckoutSession CF via
// AmenEntitlementService.initiateUpgrade(). No Stripe SDK on iOS.
// Written: 2026-06-05

import SwiftUI
import SafariServices

// MARK: - AmenPlanComparisonView

struct AmenPlanComparisonView: View {

    let holderId: String
    let holderType: String

    @StateObject private var service = AmenEntitlementService()
    @State private var selectedTier: AmenPlanTier = .free
    @State private var checkoutURL: String?
    @State private var showSafari: Bool = false
    @State private var isSelectingTier: Bool = false
    @State private var selectError: String?

    var currentTier: AmenPlanTier {
        service.currentEntitlement?.planTier ?? .free
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose Your Plan")
                            .font(.largeTitle.weight(.bold))
                        Text("Upgrade anytime. Cancel anytime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Plan cards — horizontal scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AmenPlanTier.allCases, id: \.self) { tier in
                                AmenPlanCard(
                                    tier: tier,
                                    isCurrent: tier == currentTier,
                                    isSelected: tier == selectedTier
                                ) {
                                    selectedTier = tier
                                    if tier != currentTier && tier != .free {
                                        Task { await selectPlan(tier) }
                                    }
                                }
                                .frame(width: 200)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let errorMsg = selectError {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Feature comparison grid
                    featureGrid

                    // Legal footer
                    Text("Pricing subject to change. Cancel anytime. Subscriptions managed through your account settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            try? await service.loadEntitlement(for: holderId)
        }
        .sheet(isPresented: $showSafari, onDismiss: {
            Task {
                try? await service.refreshEntitlement(for: holderId)
            }
        }) {
            if let urlString = checkoutURL, let url = URL(string: urlString) {
                PlanCompareSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Feature grid

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Feature Comparison")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Header row
            HStack(spacing: 0) {
                Text("Feature")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)

                ForEach(AmenPlanTier.allCases, id: \.self) { tier in
                    Text(tier == .enterprise ? "Ent." : tier.displayName
                        .replacingOccurrences(of: " Pro", with: "")
                        .replacingOccurrences(of: "Community", with: "Comm."))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .center)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            .background(Color(uiColor: .systemGroupedBackground))

            // Feature rows
            ForEach(Array(AmenFeatureGate.allCases.enumerated()), id: \.element) { index, feature in
                HStack(spacing: 0) {
                    Text(feature.displayName)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)

                    ForEach(AmenPlanTier.allCases, id: \.self) { tier in
                        Image(systemName: tier.includes(feature) ? "checkmark" : "minus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tier.includes(feature) ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 48, alignment: .center)
                    }
                }
                .padding(.vertical, 10)
                .padding(.trailing, 8)
                .background(
                    index.isMultiple(of: 2)
                        ? Color(uiColor: .systemBackground)
                        : Color(uiColor: .secondarySystemGroupedBackground)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func selectPlan(_ tier: AmenPlanTier) async {
        guard tier != .enterprise else {
            // Enterprise = contact sales — open URL or sheet separately
            return
        }
        isSelectingTier = true
        selectError = nil
        defer { isSelectingTier = false }

        do {
            // HUMAN-GATED: calls createCovenantCheckoutSession CF
            let url = try await service.initiateUpgrade(to: tier, for: holderId)
            checkoutURL = url
            showSafari = true
        } catch {
            selectError = error.localizedDescription
        }
    }
}

// MARK: - AmenPlanCard

struct AmenPlanCard: View {

    let tier: AmenPlanTier
    let isCurrent: Bool
    let isSelected: Bool
    var onSelect: () -> Void

    /// Top 3 features shown in the card body (for free tier, list what's included).
    private var topFeatures: [String] {
        if tier == .free {
            return [
                "Core social feed",
                "Church discovery",
                "Prayer tools",
            ]
        }
        return tier.features.prefix(3).map { $0.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Tier name + current badge
            HStack(alignment: .top) {
                Text(tier.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if isCurrent {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            // Price
            if let priceUSD = tier.monthlyPriceUSD {
                if priceUSD == 0 {
                    Text("Free")
                        .font(.title2.weight(.bold))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$\(String(format: "%.0f", priceUSD))")
                            .font(.title2.weight(.bold))
                        Text("/mo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Contact us")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Top 3 features
            VStack(alignment: .leading, spacing: 6) {
                ForEach(topFeatures, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(feature)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Select button
            Button(action: onSelect) {
                Text(buttonLabel)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCurrent || tier == .free)
            .tint(isCurrent ? Color.secondary : Color.accentColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isCurrent ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
    }

    private var buttonLabel: String {
        if isCurrent          { return "Current Plan" }
        if tier == .free      { return "Free" }
        if tier == .enterprise { return "Contact Sales" }
        return "Select"
    }
}

// MARK: - PlanCompareSafariView (UIViewControllerRepresentable)

private struct PlanCompareSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview("Plan Comparison") {
    AmenPlanComparisonView(holderId: "preview-org", holderType: "organization")
}

#Preview("Plan Card — Current") {
    AmenPlanCard(tier: .churchPro, isCurrent: true, isSelected: false) {}
        .frame(width: 200)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Plan Card — Upgrade") {
    AmenPlanCard(tier: .organizationPro, isCurrent: false, isSelected: false) {}
        .frame(width: 200)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
#endif
