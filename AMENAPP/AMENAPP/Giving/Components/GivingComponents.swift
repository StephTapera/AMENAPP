// GivingComponents.swift
// AMENAPP
//
// Reusable Liquid Glass components for the Giving surface.
// Premium, calm, native-iOS. No manipulation, no fake urgency, no vanity.
// All touch targets >= 44pt. Full Dynamic Type and Reduce Motion support.

import SwiftUI

// MARK: - Glass Selectable Pill

struct GlassSelectablePill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(pillBackground)
                .animation(reduceMotion ? .none : .spring(duration: 0.22, bounce: 0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var pillBackground: some View {
        Group {
            if isSelected {
                Capsule()
                    .fill(AmenTheme.Colors.textPrimary)
                    .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
            } else {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Glass Selectable Pill Scroll Row

struct GlassSelectablePillRow<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let options: [T]
    let selected: T?
    let onSelect: (T) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    GlassSelectablePill(
                        label: option.rawValue,
                        isSelected: selected == option,
                        onTap: { onSelect(option) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Multi-Select Pill Row

struct GlassMultiSelectPillRow<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let options: [T]
    let selected: Set<T>
    let onToggle: (T) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    GlassSelectablePill(
                        label: option.rawValue,
                        isSelected: selected.contains(option),
                        onTap: { onToggle(option) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Trust Badge Chip

struct VerifiedBadgeChip: View {
    let badge: TrustBadge

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: badge.icon)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(badge.color)
                .accessibilityHidden(true)
            Text(badge.rawValue)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(badge.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badge.color.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(badge.color.opacity(0.15), lineWidth: 0.5))
        .accessibilityLabel(badge.rawValue)
    }
}

// MARK: - Verified Badge Group

struct VerifiedBadgeGroup: View {
    let badges: [TrustBadge]
    let maxVisible: Int

    init(badges: [TrustBadge], maxVisible: Int = 4) {
        self.badges = badges
        self.maxVisible = maxVisible
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges.prefix(maxVisible), id: \.self) { badge in
                    VerifiedBadgeChip(badge: badge)
                }
                if badges.count > maxVisible {
                    Text("+\(badges.count - maxVisible)")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Transparency Metric Row

struct TransparencyMetricRow: View {
    let label: String
    let value: String
    let source: String?
    let confidence: DataConfidence
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
                Text(label.uppercased())
                    .font(.systemScaled(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }

            switch confidence {
            case .high, .medium:
                Text(value)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                if let source {
                    Text(source)
                        .font(.systemScaled(11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            case .low:
                Text(value)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text("Limited source data")
                    .font(.systemScaled(11))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            case .unverified:
                Text("Verification in progress")
                    .font(.systemScaled(14))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .italic()
            }
        }
    }
}

// MARK: - Why Shown Sheet

struct WhyShownSheet: View {
    let org: GivingOrganization
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Why AMEN is showing this")
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .padding(.top, 4)

                    if let explanation = org.rankingExplanation, !explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(explanation.tokens, id: \.key) { token in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.systemScaled(15))
                                        .foregroundStyle(AmenTheme.Colors.statusSuccess)
                                        .accessibilityHidden(true)
                                    Text(token.label)
                                        .font(.systemScaled(15))
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        Text("This organization meets AMEN's baseline trust requirements and has verified transparency data.")
                            .font(.systemScaled(15))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineSpacing(3)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What AMEN never does")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)

                        ForEach(neverDoes, id: \.self) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "xmark.circle")
                                    .font(.systemScaled(13))
                                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(.systemScaled(13))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private let neverDoes = [
        "Paid placement or sponsored rankings",
        "Opaque engagement-only ranking",
        "Social proof pressure (friends gave this)",
        "Giving streaks or generosity badges",
        "Prosperity-gospel language",
    ]
}

// MARK: - AMEN Transparency Card

struct AMENTransparencyCard: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AmenTheme.Colors.backgroundSecondary)
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("How AMEN's giving surface works")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Transparency about our role")
                            .font(.systemScaled(12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(transparencyPoints, id: \.question) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.question)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(point.answer)
                                .font(.systemScaled(13))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 10, y: 3)
        .accessibilityElement(children: .combine)
    }

    private struct TransparencyPoint {
        let question: String
        let answer: String
    }

    private let transparencyPoints = [
        TransparencyPoint(
            question: "Does AMEN take a platform fee?",
            answer: "AMEN passes 100% of your gift to the organization. We do not take a cut of donations."
        ),
        TransparencyPoint(
            question: "Who covers processor fees?",
            answer: "Processor fees are covered separately by AMEN or disclosed clearly before you give."
        ),
        TransparencyPoint(
            question: "Is placement paid?",
            answer: "No. Organizations cannot pay for ranking or placement. Rankings are based on trust data, cause match, and transparency completeness."
        ),
        TransparencyPoint(
            question: "How does AMEN sustain this feature?",
            answer: "AMEN's giving surface is part of the core product. If this changes, this card will say so plainly."
        ),
    ]
}

// MARK: - Active Response Card

struct ActiveResponseCard: View {
    let event: DisasterEvent
    let orgs: [GivingOrganization]
    let onGive: (GivingOrganization) -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: event.eventType.icon)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.80))
                    Text("ACTIVE RESPONSE")
                        .font(.systemScaled(10, weight: .bold))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if let updated = event.updatedAt {
                        Text(updated, style: .relative)
                            .font(.systemScaled(11))
                            .foregroundStyle(.white.opacity(0.60))
                        + Text(" ago")
                            .font(.systemScaled(11))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }

                Text(event.title)
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(.white)

                Text(event.summary)
                    .font(.systemScaled(14))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)

            // Responding orgs
            if !orgs.isEmpty {
                Divider()
                    .background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Organizations currently responding")
                        .font(.systemScaled(11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    ForEach(orgs.prefix(3)) { org in
                        Button {
                            onGive(org)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(org.name)
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if let action = org.recentActions.first {
                                        Text(action.summary)
                                            .font(.systemScaled(12))
                                            .foregroundStyle(.white.opacity(0.68))
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text("Give")
                                    .font(.systemScaled(12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(.white.opacity(0.18)))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.5))
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.22, blue: 0.10),
                            Color(red: 0.55, green: 0.38, blue: 0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        // Note: no autoplay, no red panic UI, no fake urgency
    }
}

// MARK: - Cause Brief Card

struct CauseBriefCard: View {
    let brief: CauseBrief
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(brief.causeCategory.rawValue, systemImage: brief.causeCategory.icon)
                        .font(.systemScaled(11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Spacer()
                    if let updatedAt = brief.updatedAt {
                        Text(updatedAt, style: .date)
                            .font(.systemScaled(11))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }

                Text(brief.title)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)

                Text(brief.summary)
                    .font(.systemScaled(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)

                if let scripture = brief.scriptureRefs.first {
                    Text(scripture)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .italic()
                }

                HStack(spacing: 8) {
                    ForEach(["Give", "Serve", "Pray"], id: \.self) { action in
                        Text(action)
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                    }
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .amenCard(cornerRadius: 22)
    }
}

// MARK: - Berean Counsel Card (inline teaser)

struct BereanCounselCard: View {
    @Binding var budgetDollars: Int
    let onTap: () -> Void

    let budgetOptions = [25, 50, 100, 200]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: "sparkles")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BEREAN COUNSEL")
                        .font(.systemScaled(10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("I have $\(budgetDollars) to give this month.")
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Text("Berean shows 2–3 matched organizations with reasons, scripture context, and financial transparency. No pressure, no reward promises.")
                .font(.systemScaled(13))
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(budgetOptions, id: \.self) { amount in
                        Button {
                            budgetDollars = amount
                        } label: {
                            Text("$\(amount)")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(budgetDollars == amount ? Color(uiColor: .label) : .white.opacity(0.75))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(budgetDollars == amount
                                    ? Color(uiColor: .systemBackground)
                                    : Color.white.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: onTap) {
                Text("Ask Berean →")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.10, blue: 0.08),
                                Color(red: 0.28, green: 0.22, blue: 0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.05))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
        )
        .shadow(color: .black.opacity(0.20), radius: 20, y: 8)
    }
}

// MARK: - Stewardship Dashboard Card (Summary)

struct StewardshipDashboardCard: View {
    let review: GivingAnnualReview?
    let snapshot: StewardshipSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Stewardship", systemImage: "chart.pie.fill")
                        .font(.systemScaled(11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Spacer()
                    Text("Private")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                }

                if let review {
                    HStack(spacing: 16) {
                        statCell(value: "\(review.destinationCount)", label: "Orgs supported")
                        Divider().frame(height: 32)
                        statCell(value: "\(review.churchPercent)%", label: "Church")
                        Divider().frame(height: 32)
                        statCell(value: "\(review.nonprofitPercent)%", label: "Nonprofits")
                    }
                } else {
                    Text("Track your giving across church and nonprofit giving — privately, on-device.")
                        .font(.systemScaled(14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                }

                if let target = snapshot.tithingTargetFormatted {
                    Label("Tithe target: \(target)", systemImage: "target")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .amenCard(cornerRadius: 22)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.systemScaled(20, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(label)
                .font(.systemScaled(11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Request Card

struct RequestCard: View {
    let request: BenevolenceRequest
    let onGive: () -> Void
    let onPray: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.category.label.uppercased())
                        .font(.systemScaled(10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text(request.title)
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                }
                Spacer()
                if let cap = request.approvedCapFormatted {
                    Text(cap)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.20, green: 0.45, blue: 0.85).opacity(0.08), in: Capsule())
                }
            }

            Text(request.verificationType.label)
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            Text(request.summary)
                .font(.systemScaled(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(2)
                .lineLimit(3)

            // Trust signals — no donor amounts, no social proof
            HStack(spacing: 6) {
                ForEach(requestTrustSignals, id: \.self) { signal in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(AmenTheme.Colors.statusSuccess)
                        Text(signal)
                            .font(.systemScaled(11))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Button(action: onGive) {
                    Text("Give anonymously")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onPray) {
                    Text("Pray")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .amenCard(cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    private var requestTrustSignals: [String] {
        var signals = ["Anonymous giving", "Guardian cleared"]
        if request.guardianStatus == .cleared { signals.append("Verified") }
        return signals
    }
}

// MARK: - Tax Receipt Row

struct TaxReceiptRow: View {
    let receipt: GivingReceipt
    let onView: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundSecondary)
                Image(systemName: "doc.text.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.destinationName)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                if let issued = receipt.issuedAt {
                    Text(issued, style: .date)
                        .font(.systemScaled(12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(receipt.amountFormatted)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                if receipt.receiptUrl != nil {
                    Button("View", action: onView)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("View receipt for \(receipt.destinationName)")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Giving Journal Composer

struct GivingJournalComposer: View {
    @Binding var text: String
    @Binding var scriptureRef: String
    let onSave: () -> Void
    let onDismiss: () -> Void
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A note to yourself")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text("Private. Not visible to anyone. Why did you give today?")
                .font(.systemScaled(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(2)

            TextEditor(text: $text)
                .font(.systemScaled(15))
                .focused($textFocused)
                .frame(minHeight: 80)
                .padding(10)
                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField("Scripture (optional)", text: $scriptureRef)
                .font(.systemScaled(14))
                .padding(10)
                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Skip")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    Text("Save note")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .onAppear { textFocused = true }
    }
}

// MARK: - Organization Card (Feed)

struct OrgCard: View {
    let org: GivingOrganization
    let onTap: () -> Void
    let onWhyShown: () -> Void
    let onGive: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    orgIconView

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(org.name)
                                .font(.systemScaled(18, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .lineLimit(2)
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            Text(org.primaryCauseLabel)
                                .font(.systemScaled(12))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                            Text("·")
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                            Label(org.primaryLocalityLabel, systemImage: "mappin")
                                .font(.systemScaled(12))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(16)

            // Badges
            if !org.trustBadges.isEmpty {
                VerifiedBadgeGroup(badges: org.trustBadges, maxVisible: 3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider().padding(.horizontal, 16)

            // Key metrics
            VStack(alignment: .leading, spacing: 10) {
                if let transparency = org.transparency {
                    if let label = transparency.programCentsLabel {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.fill")
                                .font(.systemScaled(12))
                                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                                .accessibilityHidden(true)
                            Text(label)
                                .font(.systemScaled(15, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Spacer()
                            if let sourceLabel = transparency.sourceLabel {
                                Text(sourceLabel)
                                    .font(.systemScaled(11))
                                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                            }
                        }
                    } else if transparency.verificationStatus == .inProgress {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.systemScaled(12))
                                .foregroundStyle(AmenTheme.Colors.statusWarning)
                            Text("Verification in progress")
                                .font(.systemScaled(13))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                                .italic()
                        }
                    }
                }

                if let action = org.recentActions.first {
                    Text(action.summary)
                        .font(.systemScaled(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                if !org.giftImpacts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(org.giftImpacts.prefix(3)) { impact in
                                Text("$\(impact.amount) = \(impact.description)")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            // CTA row
            HStack(spacing: 10) {
                // Why shown
                Button(action: onWhyShown) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.systemScaled(12, weight: .medium))
                        Text("Why shown")
                            .font(.systemScaled(12, weight: .medium))
                    }
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                if let _ = org.websiteUrl {
                    Button {
                        // handled in OrgDetail
                        onTap()
                    } label: {
                        Text("Learn more")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onGive) {
                    Text("Give")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textInverse)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .amenCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }

    private var orgIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.backgroundSecondary)
            if let logoUrl = org.logoUrl, let url = URL(string: logoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: org.causeCategories.first?.icon ?? "heart.fill")
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
            } else {
                Image(systemName: org.causeCategories.first?.icon ?? "heart.fill")
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
