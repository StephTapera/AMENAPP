//
//  LiquidGlassActionCapsule.swift
//  AMENAPP
//
//  Created by Gemini CLI on 2026-06-09.
//  Copyright © 2026 AMEN. All rights reserved.
//
//  The LiquidGlassActionCapsule renders contextual actions surfaced by the AI Engine.
//  It conforms to the Liquid Glass design system and animates state transitions.
//
//  SECURITY FIX (MEDIUM 2026-06-11):
//  1. Added @Environment(\.accessibilityReduceMotion) and reduce-motion–aware animations.
//     The previous bare .spring() calls ignored accessibilityReduceMotion.
//  2. Replaced the undefined .amenLiquidGlassCapsuleSurface() modifier with
//     .amenInteractiveGlassEffect(in: Capsule()) which is defined in LiquidGlassModifiers.swift.
//     The undefined extension would have caused a compile error if the file was compiled.

import SwiftUI

struct LiquidGlassActionCapsule: View {
    let actions: [ActionOption]
    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expandAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.75)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Collapsed state: Primary action only
            if !isExpanded && !actions.isEmpty {
                Button(action: { withAnimation(expandAnimation) { isExpanded = true } }) {
                    HStack {
                        Image(systemName: actions.first!.systemImage)
                        Text(actions.first!.title)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .amenInteractiveGlassEffect(in: Capsule())
            } else if isExpanded {
                // Expanded state: Surface up to 3 primary actions
                HStack(spacing: 8) {
                    ForEach(actions.prefix(3), id: \.title) { action in
                        Button(action: action.action) {
                            Text(action.title)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .amenInteractiveGlassEffect(in: Capsule())
                    }
                    Button(action: { withAnimation(expandAnimation) { isExpanded = false } }) {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                            .padding(8)
                    }
                    .amenInteractiveGlassEffect(in: Capsule())
                }
            }
        }
    }
}

struct ActionOption {
    let title: String
    let systemImage: String
    let action: () -> Void
}
