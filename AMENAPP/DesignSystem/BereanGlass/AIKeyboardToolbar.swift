// AIKeyboardToolbar.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen.
// W1: Implement as a keyboard-anchored action row (toolbarRise spring).
//     Actions shown: context-appropriate subset of BereanAIAction for the notes editor.
//     Animates up with the keyboard, dismisses with it.
//     All items 44pt targets + VoiceOver labels.
//     ReduceTransparency = solid bereanIvory bar.

import SwiftUI

/// AI action toolbar anchored above the software keyboard in the Notes editor.
struct AIKeyboardToolbar: View {

    let onAction: (BereanAIAction) -> Void

    // Actions relevant to the notes editing context.
    private let notesActions: [BereanAIAction] = [
        .summarize, .outline, .studyPlan, .turnIntoPrayer,
        .crossReference, .checkContext, .clarifyTerm
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // W1: Replace with animated glass bar anchored to keyboard (toolbarRise spring).
        // Keyboard-rise animation is gated on reduceMotion:
        //   .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: ...)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(notesActions, id: \.self) { action in
                    Button(action.displayName) {
                        onAction(action)
                    }
                    .font(BereanType.subheadline())
                    .frame(minHeight: BereanMetrics.minTapTarget)
                    .accessibilityLabel(action.displayName)
                    .accessibilityHint("Routes to \(action.routesTo.rawValue) mode")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: BereanMetrics.minTapTarget + 8)
    }
}

#Preview {
    AIKeyboardToolbar { action in
        print("Action: \(action.displayName)")
    }
    .padding(.vertical, 4)
}
