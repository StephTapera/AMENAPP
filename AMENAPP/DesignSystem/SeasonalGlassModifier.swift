// SeasonalGlassModifier.swift
// AMENAPP — DesignSystem
//
// Applies a subtle liturgical season tint to any glass surface.
//
// Usage:
//   someView
//     .seasonalGlass()        // uses EnvironmentObject LiturgicalSeasonService
//
// Guard: if AMENFeatureFlags.shared.liturgicalTheming is false, the modifier
// is a passthrough and applies no tint. This allows the flag to be flipped
// remotely without any SwiftUI rebuild overhead beyond the flag observation.
//
// Opacity is applied here (view layer), not stored in SeasonTheme.glassTintHex.
// The hex string in SeasonTheme is the pure color value at 100% opacity;
// we overlay it at a low alpha so it never overwhelms the glass surface.
//

import SwiftUI

// MARK: - SeasonalGlassModifier

struct SeasonalGlassModifier: ViewModifier {

    @EnvironmentObject private var seasonService: LiturgicalSeasonService

    private let tintOpacity: Double = 0.12

    func body(content: Content) -> some View {
        let flagEnabled = AMENFeatureFlags.shared.liturgicalTheming

        if flagEnabled {
            let hexColor = seasonService.currentTheme.glassTintHex
            content
                .overlay(
                    Color(hex: hexColor)
                        .opacity(tintOpacity)
                        .allowsHitTesting(false)
                )
        } else {
            content
        }
    }
}

// MARK: - View extension

extension View {
    /// Applies the current liturgical season's glass tint overlay.
    /// Requires `LiturgicalSeasonService` in the SwiftUI environment.
    /// No-ops when `AMENFeatureFlags.shared.liturgicalTheming` is false.
    func seasonalGlass() -> some View {
        modifier(SeasonalGlassModifier())
    }
}

// Color(hex:) — canonical definition in Color+Hex.swift; local copy removed.
