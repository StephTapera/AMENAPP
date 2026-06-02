// SmartThreadContextBar.swift
// AMENAPP
//
// Collapsible context bar that floats above the composer in UnifiedChatView.
// Shows Summary / Decisions / Questions / Actions / Media chips gated by feature flags.
// Collapses on scroll-down, reveals on scroll-up/pause.

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

    private var isVisible: Bool {
        !isScrollingDown && availableChips.count > 0
    }

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
            chipRow
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 8)
                .animation(
                    reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8),
                    value: isVisible
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Thread intelligence options")
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if false {
                    loadingChip
                }
                ForEach(availableChips) { chip in
                    contextChip(chip)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(barBackground)
    }

    private var loadingChip: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Analyzing…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

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
            .background(chipBackground(chip), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(chipColor(chip).opacity(0.2), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.rawValue): \(chipAccessibilityHint(chip))")
    }

    private func chipLabel(_ chip: SmartContextChip) -> String {
        switch chip {
        case .decisions:
            return "Decisions"
        case .questions:
            return "Questions"
        case .actions:
            return "Actions"
        default:
            return chip.rawValue
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

    private func chipBackground(_ chip: SmartContextChip) -> some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(chipColor(chip).opacity(0.15))
        }
        return AnyShapeStyle(.ultraThinMaterial)
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

    private var barBackground: some View {
        Group {
            if reduceTransparency {
                Color(.systemBackground).opacity(0.98)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}
