// BereanConfidenceBadge.swift
// AMENAPP — BereanOS
// Reusable confidence-level pill badge for memory entries.

import SwiftUI

// MARK: - BereanConfidenceBadge

struct BereanConfidenceBadge: View {
    let level: BereanConfidenceLevel
    var compact: Bool = false

    @State private var showingPopover = false

    // MARK: Colour mapping

    private var badgeColor: Color {
        switch level {
        case .certain:     return Color.green
        case .probable:    return Color.blue
        case .uncertain:   return Color.orange
        case .speculative: return Color(red: 0.60, green: 0.50, blue: 0.10)
        case .unsupported: return Color.gray
        }
    }

    // MARK: Abbreviation (compact mode)

    private var abbreviation: String {
        switch level {
        case .certain:     return "CT"
        case .probable:    return "PR"
        case .uncertain:   return "UN"
        case .speculative: return "SP"
        case .unsupported: return "NS"
        }
    }

    // MARK: Body

    var body: some View {
        if compact {
            compactBadge
        } else {
            fullBadge
        }
    }

    // MARK: Compact — dot + 2-letter code

    private var compactBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(abbreviation)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(badgeColor)
        }
        .accessibilityLabel("Confidence: \(level.displayName). \(level.explanation)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Full pill — tappable with popover

    private var fullBadge: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Text(level.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(badgeColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Confidence: \(level.displayName). \(level.explanation)")
        .popover(isPresented: $showingPopover) {
            confidencePopover
        }
    }

    // MARK: Popover content

    private var confidencePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 12, height: 12)
                Text(level.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text(level.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(minWidth: 220, maxWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Full badges
        ForEach(BereanConfidenceLevel.allCases) { level in
            BereanConfidenceBadge(level: level, compact: false)
        }
        Divider()
        // Compact badges
        HStack(spacing: 12) {
            ForEach(BereanConfidenceLevel.allCases) { level in
                BereanConfidenceBadge(level: level, compact: true)
            }
        }
    }
    .padding()
}
