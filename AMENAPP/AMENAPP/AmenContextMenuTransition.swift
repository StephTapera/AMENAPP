// AmenContextMenuTransition.swift
// AMENAPP
//
// Bloom animation for the Liquid Glass context menu panel.
// Scale-up from 0.6 with spring; Reduce Motion falls back to opacity only.

import SwiftUI

struct AmenContextMenuBloomModifier: ViewModifier {
    let isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPresented ? 1.0 : (reduceMotion ? 1.0 : 0.6))
            .opacity(isPresented ? 1.0 : 0.0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.32, dampingFraction: 0.72),
                value: isPresented
            )
    }
}

extension View {
    func amenContextMenuBloom(isPresented: Bool) -> some View {
        modifier(AmenContextMenuBloomModifier(isPresented: isPresented))
    }
}
