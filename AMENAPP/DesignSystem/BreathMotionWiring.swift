// BreathMotionWiring.swift
// AMEN — Breath Motion System wiring
//
// Wires the frozen BreathMotion.swift contracts into ViewModifiers and View
// extensions that can be applied to surfaces throughout the app.
//
// All modifiers respect AMENFeatureFlags.shared.breathMotion.
// When the flag is OFF every modifier is a zero-cost passthrough.
//
// Do NOT add .ultraThinMaterial anywhere in this file.
// All animations MUST pass through Motion.adaptive(animation:reduceMotion:isAmbient:).
//
// TARGET MEMBERSHIP NOTE:
// This file depends on BreathMotion.swift (frozen Wave 0 contract).
// BreathMotion.swift declares `enum Motion` with the 3-arg adaptive overload;
// Motion.swift declares the same `enum Motion` with the 1-arg overload.
// When both are added to the Xcode target, convert BreathMotion.swift's
// `enum Motion { }` block to `extension Motion { }` to resolve the conflict.

import SwiftUI
import UIKit

// MARK: - BreathAnimationModifier

/// Applies a `Breath.inhale` transition animation to view appearances.
/// Respects reduce-motion via `Motion.adaptive`.
/// Flag-gated: no-op when `AMENFeatureFlags.shared.breathMotion` is false.
struct BreathAnimationModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if AMENFeatureFlags.shared.breathMotion {
            content
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .animation(
                                Motion.adaptive(
                                    animation: Breath.inhale,
                                    reduceMotion: reduceMotion
                                )
                            ),
                        removal: .opacity
                            .animation(
                                Motion.adaptive(
                                    animation: Breath.exhale,
                                    reduceMotion: reduceMotion
                                )
                            )
                    )
                )
        } else {
            content
        }
    }
}

// MARK: - GlassBreathModifier

/// Applies a subtle 1.0 → 0.97 → 1.0 scale on button press using `Breath.inhale`.
/// Intended for glass pill buttons. Flag-gated on `breathMotion`.
struct GlassBreathModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed: Bool = false

    func body(content: Content) -> some View {
        if AMENFeatureFlags.shared.breathMotion {
            content
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(
                    Motion.adaptive(
                        animation: Breath.inhale,
                        reduceMotion: reduceMotion
                    ),
                    value: isPressed
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in
                            state = true
                        }
                )
        } else {
            content
        }
    }
}

// MARK: - BereanThinkingBreath

/// A repeating ambient opacity pulse (0.7 → 1.0 → 0.7) at `Breath.ambient` cadence.
/// Used for Berean loading / thinking states.
/// Collapses to a single opacity flash when Reduce Motion is enabled.
/// Flag-gated: stops pulsing when `breathMotion` is false (opacity stays at 1.0).
struct BereanThinkingBreath: ViewModifier {

    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed: Bool = false

    func body(content: Content) -> some View {
        if AMENFeatureFlags.shared.breathMotion && active {
            content
                .opacity(reduceMotion ? (pulsed ? 1.0 : 0.7) : (pulsed ? 1.0 : 0.7))
                .onAppear { startPulse() }
                .onDisappear { pulsed = false }
        } else {
            content
        }
    }

    private func startPulse() {
        if reduceMotion {
            // Single flash, no loop — respects reduce-motion preference.
            withAnimation(
                Motion.adaptive(
                    animation: .easeInOut(duration: 0.15),
                    reduceMotion: true,
                    isAmbient: false
                )
            ) {
                pulsed = true
            }
            return
        }
        // Looping ambient pulse at Breath.ambient cadence.
        withAnimation(
            Motion.adaptive(
                animation: .easeInOut(duration: Breath.ambient / 2.0).repeatForever(autoreverses: true),
                reduceMotion: false,
                isAmbient: true
            )
        ) {
            pulsed = true
        }
    }
}

// MARK: - SheetBreathPresentation

/// Applies `Breath.exhale` to the appear transition of sheet presentations.
/// Flag-gated on `breathMotion`.
struct SheetBreathPresentation: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if AMENFeatureFlags.shared.breathMotion {
            content
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .animation(
                                Motion.adaptive(
                                    animation: Breath.exhale,
                                    reduceMotion: reduceMotion
                                )
                            ),
                        removal: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .animation(
                                Motion.adaptive(
                                    animation: .easeIn(duration: Breath.enter),
                                    reduceMotion: reduceMotion
                                )
                            )
                    )
                )
        } else {
            content
        }
    }
}

// MARK: - View extensions

public extension View {

    /// Applies `Breath.inhale`/`exhale` transitions to view appearances.
    /// No-op when the `breathMotion` flag is OFF.
    func breathAppear() -> some View {
        modifier(BreathAnimationModifier())
    }

    /// Applies the glass-pill press scale (1.0 → 0.97 → 1.0) on touch-down.
    /// No-op when the `breathMotion` flag is OFF.
    func breathButton() -> some View {
        modifier(GlassBreathModifier())
    }

    /// Adds a looping ambient opacity pulse for Berean loading/thinking states.
    /// Collapses to a single flash for Reduce Motion users.
    /// No-op when `breathMotion` is OFF or `active` is false.
    func bereanThinking(active: Bool) -> some View {
        modifier(BereanThinkingBreath(active: active))
    }

    /// Applies `Breath.settle` to a sheet appear/dismiss transition.
    /// No-op when the `breathMotion` flag is OFF.
    func breathSheet() -> some View {
        modifier(SheetBreathPresentation())
    }
}
