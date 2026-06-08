// SmartThreadContextBar.swift
// AMENAPP
//
// Collapsible context bar that floats above the composer in UnifiedChatView.
// Shows Summary / Decisions / Questions / Actions / Media chips gated by feature flags.
// Collapses on scroll-down, reveals on scroll-up/pause.
//
// Liquid Glass: collapsed pill and expanded chip row share the "context-bar" glass
// identity so they morph between states via matchedGeometryEffect.
// Shadow applied before .amenGlassEffect() per kit rules.
// Solid opaque fallback used when accessibilityReduceTransparency is on.
// No glass applied to message thread content below this bar.

import SwiftUI

enum SmartContextChip: String, CaseIterable, Identifiable {
    case summary   = "Summary"
    case decisions = "Decisions"
    case questions = "Questions"
    case actions   = "Actions"
    case media     = "Media"
    case catchUp   = "Catch Up"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary:   return "text.quote"
        case .decisions: return "checkmark.seal"
        case .questions: return "questionmark.bubble"
        case .actions:   return "bolt.fill"
        case .media:     return "photo.stack"
        case .catchUp:   return "arrow.up.doc"
        }
    }
}

struct SmartThreadContextBar: View {
    @ObservedObject var coordinator: AmenMessagingIntelligenceCoordinator
    let isScrollingDown: Bool

    var onChipTap: (SmartContextChip) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Namespace shared between collapsed pill and expanded chip row for glass morphing.
    @Namespace private var barNamespace

    private var availableChips: [SmartContextChip] {
        guard AMENFeatureFlags.shared.messagesSmartContextEnabled else { return [] }
        var chips: [SmartContextChip] = []
        if AMENFeatureFlags.shared.threadSummaryEnabled { chips.append(.summary) }
        if AMENFeatureFlags.shared.threadDecisionExtractionEnabled { chips.append(.decisions) }
        if AMENFeatureFlags.shared.threadQuestionDetectionEnabled { chips.append(.questions) }
        if AMENFeatureFlags.shared.threadActionExtractionEnabled { chips.append(.actions) }
        if AMENFeatureFlags.shared.mediaIntelligenceEnabled { chips.append(.media) }
        if AMENFeatureFlags.shared.catchUpDigestEnabled { chips.append(.catchUp) }
        return chips
    }

    var body: some View {
        if !availableChips.isEmpty {
            Group {
                if isScrollingDown {
                    collapsedPill
                } else {
                    expandedChipRow
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .amenSpringEntry,
                value: isScrollingDown
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Thread intelligence options")
        }
    }

    // MARK: - Collapsed pill

    /// Shown while the user is scrolling down. Morphs into the chip row when scrolling stops.
    @ViewBuilder
    private var collapsedPill: some View {
        let pillContent = HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
            Text("\(availableChips.count) insights")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)

        if reduceTransparency {
            // Solid fallback — no glass when transparency is reduced.
            pillContent
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 16)
                .accessibilityHint("Scroll up to expand thread insights")
        } else {
            // Shadow before .amenGlassEffect() — required by kit rules.
            pillContent
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                .amenGlassEffect(in: Capsule(style: .continuous))
                .glassEffectID("context-bar", in: barNamespace)
                .padding(.horizontal, 16)
                .accessibilityHint("Scroll up to expand thread insights")
        }
    }

    // MARK: - Expanded chip row

    /// Shown when the user is not scrolling down. Morphs from the collapsed pill.
    @ViewBuilder
    private var expandedChipRow: some View {
        if reduceTransparency {
            // Solid fallback — no glass when transparency is reduced.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if false { loadingChip }
                    ForEach(availableChips) { chip in contextChip(chip) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))
            .padding(.horizontal, 16)
        } else {
            // Shadow before .amenGlassEffect() — required by kit rules.
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        if false { loadingChip }
                        ForEach(availableChips) { chip in contextChip(chip) }
                    }
                }
                .padding(.horizontal, 10)
            }
            .shadow(
                color: .black.opacity(LiquidGlassTokens.shadowSoftOpacity),
                radius: LiquidGlassTokens.shadowSoftRadius,
                y: LiquidGlassTokens.shadowSoftY
            )
            // .amenGlassEffect() is the absolute last modifier on the shell.
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
            )
            .glassEffectID("context-bar", in: barNamespace)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Loading chip

    private var loadingChip: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Analyzing…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .amenGlassEffect(in: Capsule(style: .continuous))
    }

    // MARK: - Individual chip button

    private func contextChip(_ chip: SmartContextChip) -> some View {
        Button {
            AmenMessagingAnalytics.track(.smartContextBarOpened, parameters: ["chip": chip.rawValue])
            onChipTap(chip)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chip.icon)
                    .font(.caption2.weight(.semibold))
                Text(chipLabel(chip))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(chipColor(chip))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // Shadow before .amenGlassEffect() — required by kit rules.
            .shadow(color: chipColor(chip).opacity(0.12), radius: 8, y: 3)
            .amenGlassEffect(in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.rawValue): \(chipAccessibilityHint(chip))")
    }

    // MARK: - Helpers

    private func chipLabel(_ chip: SmartContextChip) -> String {
        switch chip {
        case .decisions: return "Decisions"
        case .questions: return "Questions"
        case .actions:   return "Actions"
        default:         return chip.rawValue
        }
    }

    private func chipColor(_ chip: SmartContextChip) -> Color {
        switch chip {
        case .summary:   return .blue
        case .decisions: return .green
        case .questions: return .orange
        case .actions:   return .purple
        case .media:     return .teal
        case .catchUp:   return .indigo
        }
    }

    private func chipAccessibilityHint(_ chip: SmartContextChip) -> String {
        switch chip {
        case .summary:   return "Generate a thread summary"
        case .decisions: return "View extracted decisions"
        case .questions: return "View open questions"
        case .actions:   return "View suggested actions"
        case .media:     return "Open media intelligence"
        case .catchUp:   return "Catch up on missed messages"
        }
    }
}

// MARK: - LiquidGlassTokens shadow bridge

/// Private computed helpers so call sites read `.shadowSoftRadius` etc. rather than
/// digging into the `Shadow` struct directly.
private extension LiquidGlassTokens {
    static var shadowSoftRadius: CGFloat { shadowSoft.radius }
    static var shadowSoftY: CGFloat      { shadowSoft.y }
    static var shadowSoftOpacity: Double { 0.08 }  // matches shadowSoft.color opacity
}
