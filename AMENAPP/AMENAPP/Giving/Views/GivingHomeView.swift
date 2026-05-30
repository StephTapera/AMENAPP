// GivingHomeView.swift
// AMENAPP
//
// Main giving surface. Gold/olive hero banner, ranked org feed, Berean counsel,
// stewardship tools, benevolence requests, cause briefs.
// Premium, calm, non-coercive. No leaderboards, no streaks, no manipulation.

import SwiftUI

struct GivingHomeView: View {
    @StateObject private var vm = GivingHomeViewModel()
    @State private var budgetDollars = 100
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let heroHeight: CGFloat = 310
    private let sheetOverlap: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                // ── Hero banner (behind sheet) ────────────────────────────
                givingHero(safeAreaTop: safeTop)
                    .frame(height: heroHeight + safeTop)
                    .frame(maxWidth: .infinity, alignment: .top)

                // ── Scrollable sheet ──────────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: heroHeight + safeTop - sheetOverlap)

                        VStack(spacing: 16) {
                            // Tab bar
                            feedTabBar
                                .padding(.horizontal, 16)
                                .padding(.top, 20)

                            // Feed content
                            feedContent
                                .padding(.horizontal, 16)
                                .padding(.bottom, 120)
                        }
                        .frame(maxWidth: .infinity)
                        .background(sheetBackground)
                    }
                }
                .ignoresSafeArea(edges: .top)

                // ── Floating glass buttons (above hero, below status bar) ──
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            glassCircleButton(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        Spacer()
                        Button { vm.showIntentFlow = true } label: {
                            glassCircleButton(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Values preferences")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, safeTop + 14)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $vm.showIntentFlow) {
            GivingIntentFlowView(
                onComplete: { profile in
                    vm.onIntentFlowCompleted(profile)
                },
                onSkip: {
                    vm.showIntentFlow = false
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $vm.showOrgDetail) { org in
            GivingOrgDetailView(org: org)
        }
        .sheet(isPresented: $vm.showBereanCounsel) {
            BereanGivingCounselView(
                profile: vm.givingProfile,
                candidates: vm.rankedOrganizations,
                initialBudget: budgetDollars
            )
        }
        .sheet(isPresented: $vm.showStewardshipDashboard) {
            StewardshipDashboardView(store: vm.stewardshipStore)
        }
        .sheet(item: $vm.showWhyShownSheet) { org in
            WhyShownSheet(org: org)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $vm.showTaxCenter) {
            TaxCenterView(store: vm.stewardshipStore)
        }
        .onAppear { vm.onAppear() }
    }

    // MARK: - Hero Banner

    private func givingHero(safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Gold/olive gradient — consistent with AMEN giving identity
            LinearGradient(
                colors: [
                    Color(red: 0.44, green: 0.35, blue: 0.10),
                    Color(red: 0.61, green: 0.50, blue: 0.19),
                    Color(red: 0.73, green: 0.60, blue: 0.28),
                    Color(red: 0.49, green: 0.39, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Specular highlights
            GeometryReader { g in
                ZStack {
                    RadialGradient(
                        colors: [.white.opacity(0.22), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: g.size.width * 0.65
                    )
                    RadialGradient(
                        colors: [.white.opacity(0.08), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: g.size.width * 0.50
                    )
                }
            }

            // Bottom fade into sheet
            LinearGradient(
                colors: [.clear, .black.opacity(0.10)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: safeAreaTop + 68)

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GIVING & NONPROFITS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(3.0)
                            .foregroundStyle(.white.opacity(0.66))
                            .padding(.bottom, 6)
                        Text("Giving &")
                            .font(.custom("Georgia", size: 46))
                            .foregroundStyle(.white)
                            .lineSpacing(-4)
                        Text("Nonprofits")
                            .font(.custom("Georgia", size: 46))
                            .foregroundStyle(.white)
                        Text("Vetted. Transparent. Formative.")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.top, 4)
                    }

                    Spacer()

                    // Scripture quote
                    Text(vm.heroScriptureQuote)
                        .font(.custom("Georgia", size: 13))
                        .italic()
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(3)
                        .frame(maxWidth: 140)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, sheetOverlap + 16)
            }
        }
    }

    // MARK: - Feed Tab Bar

    private var feedTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GivingFeedTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(duration: 0.26, bounce: 0.08)) {
                            vm.selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(vm.selectedTab == tab ? .white : AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(vm.selectedTab == tab
                                          ? AmenTheme.Colors.amenGold
                                          : AmenTheme.Colors.backgroundSecondary.opacity(0.80))
                                    .shadow(color: vm.selectedTab == tab ? AmenTheme.Colors.amenGold.opacity(0.30) : .clear,
                                            radius: 10, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(vm.selectedTab == tab ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        switch vm.selectedTab {
        case .vetted:
            vettedFeed
        case .causes:
            causesFeed
        case .local:
            localFeed
        case .stewardship:
            stewardshipSection
        case .requests:
            requestsFeed
        }
    }

    // MARK: - Vetted Feed

    private var vettedFeed: some View {
        LazyVStack(spacing: 16) {
            // Active disaster — shown above feed if present
            if vm.hasActiveDisaster, let event = vm.primaryDisaster {
                activeDisasterSection(event)
            }

            // Berean counsel card
            BereanCounselCard(budgetDollars: $budgetDollars) {
                vm.showBereanCounsel = true
            }

            // Trust explainer
            trustExplainer

            // Org cards
            if vm.isLoading {
                ForEach(0..<3, id: \.self) { _ in
                    skeletonOrgCard
                }
            } else if vm.filteredOrgs.isEmpty {
                emptyFeedView
            } else {
                ForEach(vm.filteredOrgs) { org in
                    OrgCard(
                        org: org,
                        onTap: { vm.showOrgDetail = org },
                        onWhyShown: { vm.showWhyShownSheet = org },
                        onGive: { vm.showOrgDetail = org }
                    )
                }
            }

            // Stewardship nudge
            StewardshipDashboardCard(
                review: nil,
                snapshot: vm.stewardshipStore.snapshot,
                onTap: { vm.showStewardshipDashboard = true }
            )

            // AMEN transparency
            AMENTransparencyCard()
        }
    }

    private func activeDisasterSection(_ event: DisasterEvent) -> some View {
        let orgs = vm.rankedOrganizations.filter {
            event.linkedOrgIds.contains($0.id) || $0.isDisasterResponder
        }
        return ActiveResponseCard(
            event: event,
            orgs: Array(orgs.prefix(3)),
            onGive: { org in vm.showOrgDetail = org },
            onLearnMore: {}
        )
    }

    private var trustExplainer: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                .accessibilityHidden(true)
            Text("Impact cards show program efficiency, verified field action, and what a concrete gift unlocks — no vanity metrics, no paid placement.")
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .lineSpacing(2)
        }
        .padding(14)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Causes Feed

    private var causesFeed: some View {
        LazyVStack(spacing: 16) {
            if vm.hasActiveDisaster, let event = vm.primaryDisaster {
                activeDisasterSection(event)
            }

            ForEach(vm.causeBriefs) { brief in
                CauseBriefCard(brief: brief, onTap: {})
            }

            if vm.causeBriefs.isEmpty && !vm.isLoading {
                emptyStateView(
                    icon: "book.closed.fill",
                    title: "Cause briefs loading",
                    body: "Living editorial briefs on foster care, persecuted church, disaster recovery, and more are coming."
                )
            }
        }
    }

    // MARK: - Local Feed

    private var localFeed: some View {
        LazyVStack(spacing: 16) {
            // Location context note
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
                Text(localContextLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
            }

            let localOrgs = vm.filteredOrgs
            if localOrgs.isEmpty && !vm.isLoading {
                VStack(spacing: 16) {
                    emptyStateView(
                        icon: "mappin.slash.circle.fill",
                        title: "Limited local coverage here",
                        body: "We're expanding local partner verification. Here are trusted global organizations that fill the same causes."
                    )
                    ForEach(vm.rankedOrganizations.prefix(3)) { org in
                        OrgCard(
                            org: org,
                            onTap: { vm.showOrgDetail = org },
                            onWhyShown: { vm.showWhyShownSheet = org },
                            onGive: { vm.showOrgDetail = org }
                        )
                    }
                }
            } else {
                ForEach(localOrgs) { org in
                    OrgCard(
                        org: org,
                        onTap: { vm.showOrgDetail = org },
                        onWhyShown: { vm.showWhyShownSheet = org },
                        onGive: { vm.showOrgDetail = org }
                    )
                }
            }
        }
    }

    private var localContextLabel: String {
        if let region = vm.givingProfile.homeRegion?.metro {
            return "Near \(region)"
        } else if let state = vm.givingProfile.homeRegion?.state {
            return "Serving \(state)"
        }
        return "Near you"
    }

    // MARK: - Stewardship Section

    private var stewardshipSection: some View {
        StewardshipDashboardView(store: vm.stewardshipStore)
            .background(Color.clear)
    }

    // MARK: - Requests Feed

    private var requestsFeed: some View {
        GivingRequestsView(requests: vm.benevolenceRequests, isLoading: vm.isLoading)
    }

    // MARK: - Skeleton

    private var skeletonOrgCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(AmenTheme.Colors.shimmerBase).frame(height: 16)
                    Capsule().fill(AmenTheme.Colors.shimmerBase).frame(width: 120, height: 12)
                }
            }
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(height: 12)
            Capsule().fill(AmenTheme.Colors.shimmerBase).frame(width: 200, height: 12)
        }
        .padding(16)
        .amenCard(cornerRadius: 24, shadow: false)
        .amenSkeleton()
    }

    // MARK: - Empty States

    private var emptyFeedView: some View {
        emptyStateView(
            icon: "heart.circle",
            title: "No matches yet",
            body: "Complete your values intake to see personalized organizations."
        )
    }

    private func emptyStateView(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Glass Circle Button

    private func glassCircleButton(systemName: String) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(
                LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Circle().stroke(.white.opacity(0.22), lineWidth: 0.7)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    // MARK: - Sheet Background

    private var sheetBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 30,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 30,
            style: .continuous
        )
        .fill(Color(uiColor: .systemGroupedBackground))
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
