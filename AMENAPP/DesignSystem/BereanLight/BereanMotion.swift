// BereanMotion.swift
// AMEN — Berean Reading Surface: spring constants + ReduceMotion helpers (W0)
//
// FROZEN after BRS-W0-GATE.
//
// All animations gate on accessibilityReduceMotion.
// Use Animation.berean(_:reduceMotion:) — never raw spring values in views.
// For global Motion.adaptive pattern, see Motion.swift.

import SwiftUI

// MARK: - Named Springs

enum BereanSpring {
    // Card entrance — gentle rise from below.
    static let cardRise: Animation    = .spring(response: 0.45, dampingFraction: 0.82)

    // Pill / chip press feedback (scale ~0.96).
    static let pillPress: Animation   = .spring(response: 0.25, dampingFraction: 0.72)

    // Orb pulse during active mode.
    static let orbPulse: Animation   = .spring(response: 0.60, dampingFraction: 0.65)

    // Toolbar animate-up from keyboard anchor.
    static let toolbarRise: Animation = .spring(response: 0.35, dampingFraction: 0.78)

    // Scripture action row scroll-aware collapse/expand.
    static let actionRowCollapse: Animation = .spring(response: 0.30, dampingFraction: 0.85)

    // Word glow letter transition.
    static let wordGlow: Animation   = .spring(response: 0.50, dampingFraction: 0.75)
}

// MARK: - ReduceMotion Helper

extension Animation {
    // Returns the given spring when ReduceMotion is off.
    // Falls back to a short ease-in-out so transitions still feel responsive.
    static func berean(_ spring: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : spring
    }
}

// MARK: - Press Scale Modifier

// Applies the Berean pill-press scale (0.96) with ReduceMotion guard.
// Used by LiquidGlassPill and FloatingPrimaryCTA.
struct BereanPressScale: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(.berean(BereanSpring.pillPress, reduceMotion: reduceMotion), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}

extension View {
    func bereanPressScale() -> some View {
        modifier(BereanPressScale())
    }
}
