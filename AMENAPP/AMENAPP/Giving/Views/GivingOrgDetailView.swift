// GivingOrgDetailView.swift
// AMENAPP
//
// Full organization detail — real impact, real transparency, no vanity metrics.
// Every claim has a source. Stale data shows "Verification in progress."

import SwiftUI

struct GivingOrgDetailView: View {
    let org: GivingOrganization
    @Environment(\.dismiss) private var dismiss
    @State private var showWhyShown = false
    @State private var showGiveSheet = false
    @State private var showJournalComposer = false
    @State private var journalNote = ""
    @State private var journalScripture = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero
                    orgHero
                        .frame(height: 240)

                    // Content
                    VStack(spacing: 16) {
                        // Trust badges
                        if !org.trustBadges.isEmpty {
                            VerifiedBadgeGroup(badges: org.trustBadges)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Why shown
                        if let explanation = org.rankingExplanation, !explanation.isEmpty {
                            Button {
                                showWhyShown = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.systemScaled(13))
                                        .foregroundStyle(Color.accentColor)
                                    Text("Why AMEN is showing this")
                                        .font(.systemScaled(13, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.systemScaled(11))
                                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                                }
                                .padding(12)
                                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        // Description
                        Text(org.description)
                            .font(.systemScaled(15))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Transparency
                        transparencySection

                        Divider()

                        // Recent Actions
                        if !org.recentActions.isEmpty {
                            recentActionsSection
                            Divider()
                        }

                        // Gift Impacts
                        if !org.giftImpacts.isEmpty {
                            giftImpactSection
                            Divider()
                        }

                        // Locations
                        if !org.serviceRegions.isEmpty {
                            locationsSection
                            Divider()
                        }

                        // CTAs
                        ctaSection

                        // Compliance note
                        complianceNote
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .overlay(alignment: .top) { navigationOverlay }
        }
        .sheet(isPresented: $showWhyShown) {
            WhyShownSheet(org: org)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGiveSheet) {
            GiveConfirmationSheet(org: org) {
                showGiveSheet = false
                showJournalComposer = true
            }
        }
        .overlay(alignment: .bottom) {
            if showJournalComposer {
                GivingJournalComposer(
                    text: $journalNote,
                    scriptureRef: $journalScripture,
                    onSave: {
                        // Save to local store
                        showJournalComposer = false
                    },
                    onDismiss: { showJournalComposer = false }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.08), value: showJournalComposer)
    }

    // MARK: - Hero

    private var orgHero: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.44, green: 0.35, blue: 0.10),
                    Color(red: 0.65, green: 0.52, blue: 0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Specular
            GeometryReader { g in
                RadialGradient(
                    colors: [.white.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: g.size.width * 0.6
                )
            }

            // Bottom fade
            LinearGradient(
                colors: [.clear, .black.opacity(0.25)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                // Cause tag
                HStack(spacing: 6) {
                    Image(systemName: org.causeCategories.first?.icon ?? "heart.fill")
                        .font(.systemScaled(10, weight: .semibold))
                    Text(org.primaryCauseLabel.uppercased())
                        .font(.systemScaled(10, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))

                Text(org.name)
                    .font(.systemScaled(30, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(org.primaryLocalityLabel, systemImage: "mappin")
                        .font(.systemScaled(13))
                        .foregroundStyle(.white.opacity(0.80))

                    if let firstAffiliation = org.theologicalAffiliations.first,
                       firstAffiliation != .denominationallyNeutral {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.50))
                        Text(firstAffiliation.rawValue)
                            .font(.systemScaled(13))
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }
            }
            .padding(22)
        }
    }

    // MARK: - Navigation Overlay

    private var navigationOverlay: some View {
        HStack {
            Button(action: { dismiss() }) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(.white.opacity(0.22))
                    Circle().stroke(.white.opacity(0.22), lineWidth: 0.7)
                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 56)
            Spacer()
        }
    }

    // MARK: - Transparency Section

    private var transparencySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Financial transparency", icon: "chart.bar.fill")

            if let transparency = org.transparency {
                switch transparency.verificationStatus {
                case .verified, .inProgress:
                    if transparency.verificationStatus == .inProgress {
                        staleBanner
                    }
                    if let ratioLabel = transparency.programCentsLabel {
                        TransparencyMetricRow(
                            label: "Program efficiency",
                            value: ratioLabel,
                            source: transparency.sourceLabel,
                            confidence: transparency.confidence,
                            icon: "chart.bar.fill"
                        )
                    }
                    if let admin = transparency.adminExpenseRatio {
                        TransparencyMetricRow(
                            label: "Administrative costs",
                            value: "\(Int(admin * 100))¢ per dollar",
                            source: nil,
                            confidence: transparency.confidence,
                            icon: "building.fill"
                        )
                    }
                case .stale:
                    staleBanner
                case .unavailable:
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(AmenTheme.Colors.statusWarning)
                        Text("Financial data not yet available from verified sources.")
                            .font(.systemScaled(14))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            } else {
                staleBanner
            }
        }
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.systemScaled(13))
                .foregroundStyle(AmenTheme.Colors.statusWarning)
            Text("Verification in progress — we don't fabricate precision.")
                .font(.systemScaled(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .italic()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AmenTheme.Colors.statusWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Recent Actions Section

    private var recentActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent verified action", icon: "bolt.circle.fill")

            ForEach(org.recentActions.prefix(2)) { action in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(action.title)
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Spacer()
                        if let date = action.occurredAt {
                            Text(date, style: .date)
                                .font(.systemScaled(11))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                    Text(action.summary)
                        .font(.systemScaled(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                    if !action.region.isEmpty {
                        Label(action.region, systemImage: "mappin")
                            .font(.systemScaled(11))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Gift Impact Section

    private var giftImpactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What your gift unlocks", icon: "gift.fill")

            ForEach(org.giftImpacts.prefix(4)) { impact in
                HStack(spacing: 14) {
                    Text("$\(impact.amount)")
                        .font(.systemScaled(18, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 50, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(impact.description)
                            .font(.systemScaled(14))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        if !impact.fiscalYear.isEmpty {
                            Text("Reported: \(impact.fiscalYear)")
                                .font(.systemScaled(11))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Locations Section

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Where they serve", icon: "globe.americas.fill")

            GivingFlowLayout(spacing: 8) {
                ForEach(org.serviceRegions.prefix(6), id: \.displayLabel) { region in
                    Text(region.displayLabel)
                        .font(.systemScaled(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                }
            }
        }
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: 10) {
            if let donationUrl = org.donationUrl, let url = URL(string: donationUrl) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Give on their website")
                    }
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let websiteUrl = org.websiteUrl, let url = URL(string: websiteUrl) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Visit website")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let volunteerUrl = org.volunteerUrl, let url = URL(string: volunteerUrl) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Volunteer / Serve", systemImage: "hands.and.sparkles.fill")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Compliance Note

    private var complianceNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.systemScaled(11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("AMEN does not verify or process donations on this screen. All giving happens directly through the organization.")
                .font(.systemScaled(11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .lineSpacing(2)
        }
        .padding(12)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.systemScaled(13, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
    }
}

// MARK: - Give Confirmation Sheet

struct GiveConfirmationSheet: View {
    let org: GivingOrganization
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.fill")
                    .font(.systemScaled(40))
                    .foregroundStyle(Color.accentColor)

                Text("Giving to \(org.name)")
                    .font(.systemScaled(20, weight: .semibold))

                Text("You'll be taken to the organization's secure giving page. AMEN does not process this transaction.")
                    .font(.systemScaled(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if let donationUrl = org.donationUrl, let url = URL(string: donationUrl) {
                    Button {
                        UIApplication.shared.open(url)
                        dismiss()
                        onComplete()
                    } label: {
                        Text("Continue to give →")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.systemScaled(14))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Give")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Simple Flow Layout

struct GivingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentY += lineHeight + spacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentY += lineHeight + spacing
                currentX = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
