//
//  AdaptiveGlass.swift
//  AMENAPP
//
//  Accessibility-safe glass surface primitives.
//  When the user enables Reduce Transparency, all Liquid Glass materials
//  fall back to opaque system background colors — no illegible frosted blur.
//
//  Usage:
//    .background { AdaptiveGlass.regular }
//    .background { AdaptiveGlass.thin }
//    .amenGlassBackground()                  // rectangle, .regularMaterial
//    .amenGlassBackground(shape: Capsule(), weight: .ultraThin)
//

import SwiftUI

// MARK: - Material weight

enum GlassWeight {
    case regular, thin, ultraThin
}

// MARK: - Adaptive Glass Views

/// Ready-made glass fill primitives that respect Reduce Transparency.
enum AdaptiveGlass {

    /// Equivalent to `.regularMaterial` — use for cards, sheets, panels.
    static var regular: some View {
        _AdaptiveGlassFill(weight: .regular, fallback: Color(.systemBackground))
    }

    /// Equivalent to `.ultraThinMaterial` — use for pills, toolbars, overlays.
    static var thin: some View {
        _AdaptiveGlassFill(weight: .ultraThin, fallback: Color(.systemBackground).opacity(0.92))
    }

    /// Equivalent to `.thinMaterial` — use for light-weight chrome.
    static var chrome: some View {
        _AdaptiveGlassFill(weight: .thin, fallback: Color(.secondarySystemBackground))
    }
}

// MARK: - Internal fill view

struct _AdaptiveGlassFill: View {
    let weight: GlassWeight
    let fallback: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            fallback
        } else {
            switch weight {
            case .regular:   Rectangle().fill(.regularMaterial)
            case .thin:      Rectangle().fill(.thinMaterial)
            case .ultraThin: Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - ViewModifier

private struct AdaptiveGlassBackgroundModifier<S: Shape>: ViewModifier {
    let shape: S
    let weight: GlassWeight

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                shape.fill(Color(.systemBackground))
            } else {
                switch weight {
                case .regular:   shape.fill(.regularMaterial)
                case .thin:      shape.fill(.thinMaterial)
                case .ultraThin: shape.fill(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - Convenience extension

extension View {
    /// Applies a Reduce-Transparency-safe glass background.
    /// - Parameters:
    ///   - shape: Shape used for clipping (default: `Rectangle()`).
    ///   - weight: Glass weight (default: `.regular`).
    func amenGlassBackground<S: Shape>(
        shape: S = Rectangle(),
        weight: GlassWeight = .regular
    ) -> some View {
        self.modifier(AdaptiveGlassBackgroundModifier(shape: shape, weight: weight))
    }
}
