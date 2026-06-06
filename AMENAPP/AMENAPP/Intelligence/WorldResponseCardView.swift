// WorldResponseCardView.swift
// AMENAPP — World Events as Christian Response: Card UI
//
// Renders a GLOBAL-tier IntelligenceCard with Christian-response framing.
//
// Design invariants:
//   - "World Event" / "Responding in Faith" tag uses subdued warm tone — not alarming red
//   - Lament header shown for disaster/conflict events; opt-in reveal overlay
//   - Source attribution ALWAYS visible for GLOBAL cards
//   - Summary bullets: known facts + how to respond
//   - "What's contested or uncertain" disclosure is expandable, hidden by default
//   - DEVELOPING badge is a subdued capsule — never top-ranked
//   - Actions restricted to PRAY / GIVE / SHOW_UP / DISCUSS only
//   - NO count-based UI (no "N affected", no share counts)
//   - NO political framing, commentary, or editorial takes

import SwiftUI

// MARK: - WorldResponseCardView

struct WorldResponseCardView: View {
    let card: IntelligenceCard
    let onAction: (CardAction) -> Void

    @State private var isContentRevealed: Bool = false
    @State private var showWhySheet: Bool = false
    @State private var contestedExpanded: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Computed helpers

    private var isLamentContext: Bool {
        card.formation.lamentFrame == true
    }

    private var isDeveloping: Bool {
        card.truthLevel == .developing
    }

    /// Contested bullets are stored in matchReasons by the CF.
    private var contestedBullets: [String] {
        card.matchReasons?.filter { !$0.isEmpty } ?? []
    }

    /// Actions restricted to PRAY / GIVE / SHOW_UP / DISCUSS for GLOBAL cards.
    private var allowedActions: [CardAction] {
        let permitted: Set<ActionRung> = [.pray, .give, .showUp, .discuss]
        return card.actions.filter { permitted.contains($0.rung) }
    }

    // Lament palette: muted blue-gray; standard: subdued warm green
    private var accentColor: Color {
        isLamentContext ? Color(hex: "5E7291") : Color(hex: "2C6E49")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            if isLamentContext && !isContentRevealed {
                lamentOverlay
            } else {
                cardBody
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(accentColor.opacity(0.22), lineWidth: 0.75)
        )
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityCardLabel)
        .sheet(isPresented: $showWhySheet) {
            WorldResponseWhySheet(rankReasons: card.rankReasons)
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isLamentContext {
                    Label("Responding in Faith", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                } else {
                    Label("World Events", systemImage: "globe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if isDeveloping {
                    DevelopingBadge()
                }

                Button {
                    showWhySheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Why you're seeing this")
            }

            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Lament Overlay

    /// Pastoral opt-in gate for difficult events — language is calm and invitational.
    private var lamentOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(accentColor)

            Text("This calls for lament and prayer.")
                .font(.subheadline)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Tap to read and respond in faith.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                withAnimation(.easeInOut(duration: LiquidGlassTokens.motionFast)) {
                    isContentRevealed = true
                }
            } label: {
                Text("Read and Respond")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read this world event and respond in faith")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary bullets — known facts + how to respond (max 3)
            if !card.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(card.summary.prefix(3), id: \.self) { bullet in
                        WorldResponseSummaryRow(text: bullet)
                    }
                }
            }

            // Contested / uncertain disclosure — hidden by default
            if !contestedBullets.isEmpty {
                contestedDisclosure
            }

            Divider()
                .padding(.vertical, 2)

            // Source provenance — ALWAYS shown for GLOBAL cards
            if let source = card.source, !source.isEmpty {
                Label("Source: \(source)", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Source: \(source)")
            }

            // Actions — PRAY, GIVE, SHOW_UP, DISCUSS only
            if !allowedActions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(allowedActions) { action in
                        GlobalActionButton(action: action, accentColor: accentColor) {
                            onAction(action)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Contested disclosure

    private var contestedDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: LiquidGlassTokens.motionFast)) {
                    contestedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: contestedExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("What's contested or uncertain")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                contestedExpanded
                    ? "Collapse: what is contested or uncertain"
                    : "Expand: what is contested or uncertain"
            )

            if contestedExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(contestedBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("?")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text(bullet)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                if isLamentContext {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(Color(hex: "5E7291").opacity(colorScheme == .dark ? 0.10 : 0.06))
                }
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                                Color.white.opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.screen)
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityCardLabel: String {
        var parts: [String] = ["World event card: \(card.title)"]
        if isLamentContext { parts.append("calls for lament and prayer") }
        if isDeveloping    { parts.append("still developing — limited information") }
        if let source = card.source, !source.isEmpty {
            parts.append("Source: \(source)")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - WorldResponseSummaryRow

private struct WorldResponseSummaryRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(text)
    }
}

// MARK: - GlobalActionButton

private struct GlobalActionButton: View {
    let action: CardAction
    let accentColor: Color
    let onTap: () -> Void

    private var actionIcon: String {
        switch action.rung {
        case .pray:    return "hands.pray.fill"
        case .give:    return "heart.circle.fill"
        case .showUp:  return "figure.walk.circle.fill"
        case .discuss: return "bubble.left.and.bubble.right.fill"
        default:       return "circle.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            Label(action.label, systemImage: actionIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint("Tap to \(action.label.lowercased())")
    }
}

// MARK: - DevelopingBadge

private struct DevelopingBadge: View {
    var body: some View {
        Text("Still developing")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("Still developing — information is limited")
    }
}

// MARK: - WorldResponseWhySheet

private struct WorldResponseWhySheet: View {
    let rankReasons: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rankReasons, id: \.self) { reason in
                        Label(reason, systemImage: "info.circle")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Why you're seeing this")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("World event cards are sourced from trusted Christian news organisations and curated by admins. Content is generated to summarise known facts and suggest faithful responses — no editorial opinion is added.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About world response cards")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Why you're seeing this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Lament — Disaster (Developing)") {
    let lamentCard = IntelligenceCard(
        id: "preview-lament",
        tier: .global,
        title: "Earthquake Affects Communities in Southeast Asia",
        summary: [
            "Search and rescue efforts are underway across the affected region.",
            "Aid organisations have begun distributing food and water.",
            "Pray for those affected and for the safety of rescue workers.",
        ],
        backingEntity: BackingEntity(kind: .event, id: "preview_earthquake", verified: false),
        truthLevel: .developing,
        matchScore: nil,
        matchReasons: [
            "Exact casualty figures have not yet been confirmed.",
            "Access to some areas is still restricted, limiting information.",
        ],
        actions: [
            CardAction(rung: .pray,    label: "Pray for those affected",    handler: "openPrayer",   target: "world_event:earthquake"),
            CardAction(rung: .give,    label: "Give to relief efforts",      handler: "openDonation", target: "world_event:earthquake"),
            CardAction(rung: .discuss, label: "Discuss with your community", handler: "discuss",      target: "world_event:earthquake"),
        ],
        rankScore: 40,
        rankReasons: [
            "World event from trusted source",
            "Source: WORLD Magazine",
        ],
        geo: nil,
        formation: IntelligenceFormation(
            finite: true,
            spectacleCounters: false,
            lamentFrame: true,
            loopParentId: nil
        ),
        source: "WORLD Magazine",
        createdAt: Date().timeIntervalSince1970,
        expiresAt: Date().addingTimeInterval(86400).timeIntervalSince1970
    )
    ScrollView {
        WorldResponseCardView(card: lamentCard) { action in
            print("Action tapped: \(action.label)")
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Justice Event — Verified") {
    let justiceCard = IntelligenceCard(
        id: "preview-justice",
        tier: .global,
        title: "Christians Partner in Regional Service Day",
        summary: [
            "Multiple churches joining local organisations for a day of community service.",
            "Volunteer sign-ups are open through participating churches.",
            "Prayer gatherings are scheduled across participating congregations.",
        ],
        backingEntity: BackingEntity(kind: .event, id: "preview_justice", verified: true),
        truthLevel: .verified,
        matchScore: nil,
        matchReasons: [
            "Long-term outcomes of the initiative are still being evaluated.",
        ],
        actions: [
            CardAction(rung: .pray,    label: "Pray",               handler: "openPrayer",   target: "world_event:service"),
            CardAction(rung: .showUp,  label: "Get involved",       handler: "volunteer",    target: "world_event:service"),
            CardAction(rung: .discuss, label: "Discuss",            handler: "discuss",      target: "world_event:service"),
        ],
        rankScore: 65,
        rankReasons: [
            "World event from trusted source",
            "Source: Christianity Today",
        ],
        geo: nil,
        formation: IntelligenceFormation(
            finite: true,
            spectacleCounters: false,
            lamentFrame: false,
            loopParentId: nil
        ),
        source: "Christianity Today",
        createdAt: Date().timeIntervalSince1970,
        expiresAt: Date().addingTimeInterval(86400).timeIntervalSince1970
    )
    ScrollView {
        WorldResponseCardView(card: justiceCard) { action in
            print("Action tapped: \(action.label)")
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
#endif
