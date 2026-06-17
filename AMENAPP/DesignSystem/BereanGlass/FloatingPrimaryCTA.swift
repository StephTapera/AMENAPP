// FloatingPrimaryCTA.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen.
// W1: Implement as a soft circular arrow button (arrow.forward.circle.fill or
//     context-appropriate variant). bereanPressScale on tap.
//     Floats above the bottom safe area — does NOT overlap keyboard.
//     44pt minimum target.
//     ReduceTransparency = solid bereanIvory button background.

import SwiftUI

/// A floating circular primary call-to-action button for the Berean surface.
/// Used to advance the primary flow: Continue Study / Open Passage / Start Prayer / Next Reflection.
struct FloatingPrimaryCTA: View {

    let label: BereanCTALabel
    let action: () -> Void

    private var iconName: String {
        switch label {
        case .continueStudy:    return "arrow.forward.circle.fill"
        case .openPassage:      return "book.circle.fill"
        case .startPrayer:      return "hands.and.sparkles.fill"
        case .nextReflection:   return "chevron.down.circle.fill"
        }
    }

    var body: some View {
        // W1: Replace with full glass floating button + press scale.
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(Color.bereanInk.opacity(0.8))
        }
        .frame(width: BereanMetrics.minTapTarget + 12, height: BereanMetrics.minTapTarget + 12)
        .contentShape(Circle())
        .bereanPressScale()
        .accessibilityLabel(label.rawValue)
    }
}

#Preview {
    VStack(spacing: 24) {
        FloatingPrimaryCTA(label: .continueStudy,  action: {})
        FloatingPrimaryCTA(label: .openPassage,    action: {})
        FloatingPrimaryCTA(label: .startPrayer,    action: {})
        FloatingPrimaryCTA(label: .nextReflection, action: {})
    }
    .padding()
    .background(Color.bereanIvory)
}
