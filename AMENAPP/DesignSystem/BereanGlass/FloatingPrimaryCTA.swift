// FloatingPrimaryCTA.swift
// AMEN — Berean Reading Surface: FloatingPrimaryCTA component (W1)
//
// Soft 56pt circular button — floats above content, does NOT overlap keyboard.
// Press scale ~0.92 via bereanPressScale(). ReduceTransparency: solid bereanIvory.

import SwiftUI

/// Floating circular primary call-to-action for the Berean reading surface.
/// Caller positions via padding — button does not self-position.
struct FloatingPrimaryCTA: View {

    let label: BereanCTALabel
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var iconName: String {
        switch label {
        case .continueStudy:    return "arrow.forward.circle.fill"
        case .openPassage:      return "book.circle.fill"
        case .startPrayer:      return "hands.and.sparkles.fill"
        case .nextReflection:   return "chevron.down.circle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.bereanTan, lineWidth: BereanMetrics.strokeWidth)
                    )
                    .frame(width: 56, height: 56)
                    .shadow(
                        color: Color.bereanInk.opacity(BereanMetrics.shadowOpacity),
                        radius: BereanMetrics.shadowRadius, y: 4
                    )

                Image(systemName: iconName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.bereanInk.opacity(0.82))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .bereanPressScale()
        .accessibilityLabel(label.rawValue)
        .accessibilityAddTraits(.isButton)
    }

    private var buttonFill: Color {
        reduceTransparency ? Color.bereanIvory : Color.bereanIvory.opacity(0.92)
    }
}

#Preview {
    VStack(spacing: 20) {
        ForEach([BereanCTALabel.continueStudy, .openPassage, .startPrayer, .nextReflection], id: \.rawValue) { lbl in
            FloatingPrimaryCTA(label: lbl, action: {})
        }
    }
    .padding(40)
    .background(Color.bereanIvory)
}
