// CreatorAppropriatenessSignalView.swift
// AMENAPP — Creator Spotlight / Wave 3
//
// Compact appropriateness signal chip aligned to COPPA/KOSA minor-safety invariants.
// Fail-closed: EmptyView when creatorAppropriatenessSignalEnabled is false.

import SwiftUI

struct CreatorAppropriatenessSignalView: View {

    let signal: AppropriatenessSignal

    var body: some View {
        if !AMENFeatureFlags.shared.creatorAppropriatenessSignalEnabled {
            EmptyView()
        } else {
            chip
        }
    }

    // MARK: - Chip

    private var chip: some View {
        HStack(spacing: 5) {
            Image(systemName: signal.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(signal.chipColor)
            Text(signal.displayLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(signal.chipColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(signal.chipColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(signal.chipColor.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(signal.accessibilityLabel)
    }
}

// MARK: - AppropriatenessSignal display

private extension AppropriatenessSignal {
    var displayLabel: String {
        switch self {
        case .allAges:           return "All Ages"
        case .teenAndUp:         return "Teen & Up (13+)"
        case .matureThemes:      return "Mature Themes"
        case .guidanceSuggested: return "Guidance Suggested"
        }
    }

    var iconName: String {
        switch self {
        case .allAges:           return "checkmark.circle.fill"
        case .teenAndUp:         return "person.fill.checkmark"
        case .matureThemes:      return "exclamationmark.triangle"
        case .guidanceSuggested: return "person.2.fill"
        }
    }

    var chipColor: Color {
        switch self {
        case .allAges:           return .green
        case .teenAndUp:         return .blue
        case .matureThemes:      return .orange
        case .guidanceSuggested: return .orange
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .allAges:           return "Appropriate for all ages"
        case .teenAndUp:         return "Teen and up, 13 plus"
        case .matureThemes:      return "Contains mature themes"
        case .guidanceSuggested: return "Parental guidance suggested"
        }
    }
}
