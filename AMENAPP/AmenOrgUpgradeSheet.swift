// AmenOrgUpgradeSheet.swift
// AMENAPP
//
// Liquid Glass upgrade / tier comparison sheet for org subscriptions.
// Presented from the adminTools module card when the org owner taps
// "Upgrade Plan" (Free → Plus/Pro) or "Manage Plan" (Plus/Pro → portal).
//
// Three glass tier cards stacked vertically with spring-animated detail reveal.
// Uses AMEN brand tokens: amenGold (Plus), amenPurple (Pro), never system blue.

import SwiftUI

// MARK: - AmenOrgUpgradeSheet

struct AmenOrgUpgradeSheet: View {

    let organization: AmenOrganizationProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @StateObject private var subscriptionService = AmenOrgSubscriptionService.shared

    @State private var expandedCard: AmenOrganizationBillingPlan? = nil

    private var currentTier: AmenOrganizationBillingPlan {
        organization.billing?.tier ?? .free
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sheetHeader
                    currentPlanPill
                    tierCards
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(24)
        .presentationDragIndicator(.visible)
        .alert("Error", isPresented: checkoutErrorBinding, actions: {
            Button("OK") { subscriptionService.reset() }
        }, message: {
            if case .error(let msg) = subscriptionService.checkoutState {
                Text(msg)
            } else if case .error(let msg) = subscriptionService.portalState {
                Text(msg)
            }
        })
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(spacing: 6) {
            Text("Grow your community")
                .font(AMENFont.semiBold(24))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)

            Text("Choose a plan for \(organization.name)")
                .font(AMENFont.regular(15))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Current Plan Pill

    private var currentPlanPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(currentTier == .free ? Color.secondary : AmenTheme.Colors.amenGold)
                .frame(width: 7, height: 7)
            Text("You're on \(currentTier.displayName)")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.systemGroupedBackground))
                .overlay(Capsule(style: .continuous).strokeBorder(Color(UIColor.separator).opacity(0.4), lineWidth: 0.5))
        )
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        VStack(spacing: 14) {
            tierCard(for: .free)
            tierCard(for: .plus)
            tierCard(for: .pro)
        }
    }

    @ViewBuilder
    private func tierCard(for plan: AmenOrganizationBillingPlan) -> some View {
        let isExpanded = expandedCard == plan
        let isCurrent = currentTier == plan

        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(cardAnimation) {
                    expandedCard = isExpanded ? nil : plan
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plan.displayName)
                                .font(AMENFont.semiBold(17))
                                .foregroundStyle(Color.primary)
                            if let badge = planBadge(plan) {
                                Text(badge)
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(Color(.systemBackground))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(planAccentColor(plan))
                                    )
                            }
                            if isCurrent {
                                Text("Current")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(.systemGroupedBackground))
                                    )
                            }
                        }
                        Text(plan.monthlyPrice)
                            .font(AMENFont.bold(20))
                            .foregroundStyle(plan == .free ? Color.primary : planAccentColor(plan))
                        if let tagline = planTagline(plan) {
                            Text(tagline)
                                .font(AMENFont.regular(12))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Feature list — spring-animated reveal
            if isExpanded {
                Divider().padding(.horizontal, 16)
                featureList(for: plan)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top)))
            }

            // CTA
            ctaButton(for: plan, isCurrent: isCurrent)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, isExpanded ? 0 : 8)
        }
        .background { tierCardBackground(plan: plan, isCurrent: isCurrent) }
        .animation(cardAnimation, value: isExpanded)
    }

    // MARK: - Feature List

    @ViewBuilder
    private func featureList(for plan: AmenOrganizationBillingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(planFeatures(plan), id: \.self) { feature in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(plan == .free ? Color.secondary : planAccentColor(plan))
                        .frame(width: 18, height: 18)
                    Text(feature)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - CTA Button

    @ViewBuilder
    private func ctaButton(for plan: AmenOrganizationBillingPlan, isCurrent: Bool) -> some View {
        let isLoading = subscriptionService.checkoutState == .loading
            || subscriptionService.portalState == .loading

        if isCurrent && plan != .free {
            // Manage Plan → open billing portal
            Button {
                Task { await subscriptionService.openBillingPortal(orgId: organization.id) }
            } label: {
                ctaLabel(title: "Manage Plan", plan: plan, isLoading: isLoading)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        } else if plan == .free {
            // Nothing to do for free tier
            EmptyView()
        } else if currentTier == plan {
            EmptyView()
        } else {
            // Upgrade to this tier
            Button {
                Task { await subscriptionService.startCheckout(orgId: organization.id, plan: plan) }
            } label: {
                ctaLabel(
                    title: "Upgrade to \(plan.displayName)",
                    plan: plan,
                    isLoading: isLoading && subscriptionService.checkoutState == .loading
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || !organization.claimStatus.allowsOfficialControls)
        }
    }

    private func ctaLabel(title: String, plan: AmenOrganizationBillingPlan, isLoading: Bool) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(.systemBackground))
            } else {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(planAccentColor(plan))
                .opacity(isLoading ? 0.6 : 1)
        )
    }

    // MARK: - Card Background

    @ViewBuilder
    private func tierCardBackground(plan: AmenOrganizationBillingPlan, isCurrent: Bool) -> some View {
        let accent = planAccentColor(plan)
        if plan == .free {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    }
            }
        } else {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(accent, lineWidth: isCurrent ? 2 : 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(accent.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(accent, lineWidth: isCurrent ? 2 : 1)
                    }
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Cancel anytime · billed monthly")
            .font(AMENFont.regular(12))
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Helpers

    private var cardAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.36, dampingFraction: 0.80)
    }

    private func planAccentColor(_ plan: AmenOrganizationBillingPlan) -> Color {
        switch plan {
        case .free:  return Color.secondary
        case .plus:  return AmenTheme.Colors.amenGold
        case .pro:   return AmenTheme.Colors.amenPurple
        }
    }

    private func planBadge(_ plan: AmenOrganizationBillingPlan) -> String? {
        switch plan {
        case .free:  return nil
        case .plus:  return "Most Popular"
        case .pro:   return nil
        }
    }

    private func planTagline(_ plan: AmenOrganizationBillingPlan) -> String? {
        switch plan {
        case .free:  return "Core profile features, always free"
        case .plus:  return "Spaces, Events, Notes & Giving"
        case .pro:   return "For growing churches & schools"
        }
    }

    private func planFeatures(_ plan: AmenOrganizationBillingPlan) -> [String] {
        switch plan {
        case .free:
            return [
                "Organization profile page",
                "Hero banner & identity header",
                "Safety transparency module",
                "Admin tools (owner only)"
            ]
        case .plus:
            return [
                "Everything in Free",
                "Spaces — host groups & communities",
                "Events — RSVP & scheduling",
                "School Notes & Smart Notes",
                "Giving — receive tithes & offerings"
            ]
        case .pro:
            return [
                "Everything in Plus",
                "Media library — sermons & clips",
                "Analytics — member growth & insights",
                "Priority support"
            ]
        }
    }

    private var checkoutErrorBinding: Binding<Bool> {
        Binding {
            if case .error = self.subscriptionService.checkoutState { return true }
            if case .error = self.subscriptionService.portalState { return true }
            return false
        } set: { _ in }
    }
}

// MARK: - Preview

#if DEBUG
private extension AmenOrganizationProfile {
    static var previewChurch: AmenOrganizationProfile {
        AmenOrganizationProfile(
            id: "preview-church",
            type: .church,
            name: "Cornerstone Church",
            normalizedName: "cornerstone church",
            description: "A community of faith in downtown Atlanta.",
            address: AmenOrganizationAddress(city: "Atlanta", state: "GA"),
            website: "https://cornerstoneatl.com",
            phone: nil,
            verifiedStatus: "verified",
            claimStatus: .claimed,
            source: .userCreated,
            sourceId: "preview",
            visibility: "public",
            bannerConfig: [:],
            spaceDefaults: [:],
            billing: AmenOrganizationBilling(
                stripeCustomerId: nil,
                subscriptionId: nil,
                tier: .free,
                status: "active"
            ),
            safetyStatus: "clear",
            modules: [],
            schemaVersion: 1
        )
    }
}

#Preview {
    AmenOrgUpgradeSheet(organization: .previewChurch)
}
#endif
