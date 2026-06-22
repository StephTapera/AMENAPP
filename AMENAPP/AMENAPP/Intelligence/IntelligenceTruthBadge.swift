// IntelligenceTruthBadge.swift — AMEN Living Intelligence
// Compact badge that communicates the truth/verification level of an intelligence card.
// Low emphasis for .developing so it never reads as authoritative.

import SwiftUI

struct IntelligenceTruthBadge: View {
    let level: TruthLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(badgeColor)

            Text(level.displayLabel)
                .font(.caption2)
                .fontWeight(level == .developing ? .regular : .medium)
                .foregroundStyle(badgeColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Truth level: \(level.displayLabel)")
    }

    // MARK: - Icon

    private var iconName: String {
        switch level {
        case .verified:           return "checkmark.seal.fill"
        case .churchConfirmed:    return "building.columns.fill"
        case .communityConfirmed: return "person.2.fill"
        case .developing:         return "clock.fill"
        }
    }

    // MARK: - Color

    /// Colors map to trust levels.
    /// .developing uses .secondary to communicate low confidence — never alarming.
    private var badgeColor: Color {
        switch level {
        case .verified:           return Color.green
        case .churchConfirmed:    return Color(red: 0.28, green: 0.44, blue: 0.88)
        case .communityConfirmed: return Color.orange
        case .developing:         return Color.secondary
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        IntelligenceTruthBadge(level: .verified)
        IntelligenceTruthBadge(level: .churchConfirmed)
        IntelligenceTruthBadge(level: .communityConfirmed)
        IntelligenceTruthBadge(level: .developing)
    }
    .padding()
}
#endif
