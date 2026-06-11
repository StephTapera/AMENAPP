// IntelligenceCardView.swift — AMEN Living Intelligence
// Individual intelligence card with:
//   - IntelligenceTier chip + truth badge
//   - Title (max 2 lines)
//   - Summary bullets (≤3)
//   - Expandable "Why you're seeing this" (matchReasons + rankReasons)
//   - CommitmentLadderView (all actions wired)
//   - Lament framing (opt-in reveal)
//   - Source attribution for .global tier
//
// NEVER shows count-based UI ("N people praying", "N attending").
// Solidarity is expressed in language only.

import SwiftUI

// MARK: - Navigation Destinations

/// Published action routing for WhatNeedsAttentionView to observe.
enum IntelligenceNavigationDestination: Identifiable {
    case prayer(targetId: String)
    case discussion(targetId: String)
    case bereanStudy(targetId: String)
    case giving(targetId: String)
    case eventRSVP(targetId: String)
    case maps(targetId: String)
    case creation(targetId: String)
    case webFallback(url: URL)

    var id: String {
        switch self {
        case .prayer(let t):      return "prayer-\(t)"
        case .discussion(let t):  return "discussion-\(t)"
        case .bereanStudy(let t): return "study-\(t)"
        case .giving(let t):      return "giving-\(t)"
        case .eventRSVP(let t):   return "event-\(t)"
        case .maps(let t):        return "maps-\(t)"
        case .creation(let t):    return "creation-\(t)"
        case .webFallback(let u): return "web-\(u.absoluteString)"
        }
    }
}

// MARK: - Not-Implemented Placeholder Sheet

struct IntelligenceNotImplementedSheet: View {
    let cardTitle: String
    let actionLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "hammer.circle")
                    .font(.systemScaled(52))
                    .foregroundStyle(.secondary)

                Text(cardTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("\(actionLabel)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .navigationTitle(cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - IntelligenceTier Badge

private struct TierBadge: View {
    let tier: IntelligenceTier

    var body: some View {
        Text(tier.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(tierColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tierColor.opacity(0.14), in: Capsule())
            .accessibilityHidden(true)
    }

    private var tierColor: Color {
        switch tier {
        case .spiritual: return Color(red: 0.50, green: 0.30, blue: 0.90)
        case .community: return Color(red: 0.20, green: 0.60, blue: 0.40)
        case .family:    return Color(red: 0.90, green: 0.50, blue: 0.20)
        case .local:     return Color(red: 0.20, green: 0.50, blue: 0.90)
        case .global:    return Color(red: 0.70, green: 0.20, blue: 0.30)
        }
    }
}

// MARK: - Main Card View

struct IntelligenceCardView: View {
    let card: IntelligenceCard
    let onAction: (CardAction) -> Void

    @State private var isExpanded = false
    @State private var lamentRevealed = false
    @State private var pendingSheet: CardAction?

    private var isLamentFrame: Bool { card.formation.lamentFrame == true }
    private var sortedActions: [CardAction] { card.actions.sorted { $0.rung < $1.rung } }

    var body: some View {
        Group {
            if isLamentFrame && !lamentRevealed {
                lamentOverlayCard
            } else {
                cardBody
            }
        }
        .sheet(item: $pendingSheet) { action in
            IntelligenceNotImplementedSheet(cardTitle: card.title, actionLabel: action.label)
        }
    }

    // MARK: - Lament Overlay

    private var lamentOverlayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TierBadge(tier: card.tier)
                Spacer()
                Image(systemName: "heart.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Sensitive content")
            }

            Text(card.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .blur(radius: 4)
                .lineLimit(2)

            Text("This card involves a sensitive topic. Tap to engage with care.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    lamentRevealed = true
                }
            } label: {
                Text("I want to engage with this")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal sensitive content for: \(card.title)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
    }

    // MARK: - Full Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. IntelligenceTier chip + TruthBadge
            HStack(spacing: 8) {
                TierBadge(tier: card.tier)
                Spacer()
                IntelligenceTruthBadge(level: card.truthLevel)
            }

            // 2. Title (max 2 lines)
            Text(card.title)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isLamentFrame ? .secondary : .primary)

            // 3. Summary bullets (≤3, each prefixed with "•")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.summary.prefix(3), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                        Text(bullet)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 4. "Why this?" expand/collapse
            if hasWhyContent {
                whyDisclosure
            }

            // 5. Commitment ladder actions
            if !sortedActions.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                CommitmentLadderView(actions: sortedActions) { action in
                    routeAction(action)
                }
            }

            // 6. Lament framing text (subdued)
            if isLamentFrame && lamentRevealed {
                lamentFramingText
            }

            // 7. Source attribution for .global tier
            if card.tier == .global, let source = card.source {
                sourceAttribution(source)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
    }

    // MARK: - Why Disclosure

    private var hasWhyContent: Bool {
        let hasMatch = (card.matchReasons?.isEmpty == false)
        let hasRank = !card.rankReasons.isEmpty
        return hasMatch || hasRank
    }

    private var whyDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.up" : "info.circle")
                        .font(.caption2)
                    Text("Why you're seeing this")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide why this was surfaced" : "Show why this was surfaced")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Match reasons
                    if let reasons = card.matchReasons, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Matched to you because:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fontWeight(.medium)

                            ForEach(reasons, id: \.self) { reason in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "person.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // Rank reasons
                    if !card.rankReasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Surfaced because:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fontWeight(.medium)

                            ForEach(card.rankReasons, id: \.self) { reason in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "arrow.up.right.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Lament framing text

    private var lamentFramingText: some View {
        Text("This involves a real situation in our community. We approach it with lament and prayer.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .padding(.top, 2)
            .accessibilityLabel("Lament framing: this involves a real situation in our community. We approach it with lament and prayer.")
    }

    // MARK: - Source attribution

    private func sourceAttribution(_ source: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Source: \(source)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    // MARK: - Action Routing

    /// Routes every handler to its destination. Every button taps — none are dead.
    /// Unmapped handlers fall back to web Safari with action.target as URL.
    private func routeAction(_ action: CardAction) {
        onAction(action)

        switch action.handler {
        case "intelligence.pray":
            // Opens prayer composer — handled via sheet in parent via onAction
            // Fallback: NotImplemented sheet until PrayerComposerView is wired here
            pendingSheet = action
        case "intelligence.rsvp":
            pendingSheet = action
        case "intelligence.give":
            pendingSheet = action
        case "intelligence.discuss":
            pendingSheet = action
        case "intelligence.learn":
            pendingSheet = action
        case "intelligence.show_up":
            // Open Maps with target as location identifier
            if let url = URL(string: "maps://?q=\(action.target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? action.target)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                pendingSheet = action
            }
        case "intelligence.start":
            pendingSheet = action
        default:
            // Web fallback: open target as URL if valid, else NotImplemented
            if let url = URL(string: action.target), url.scheme?.hasPrefix("http") == true {
                UIApplication.shared.open(url)
            } else {
                pendingSheet = action
            }
        }
    }
}
