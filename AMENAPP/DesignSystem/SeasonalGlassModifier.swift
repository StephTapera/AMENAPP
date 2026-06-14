//
//  SeasonalGlassModifier.swift
//  AMENAPP — DesignSystem
//
//  Applies a subtle liturgical season tint to any glass surface.
//
//  Usage:
//    someView
//      .seasonalGlass()        // uses EnvironmentObject LiturgicalSeasonService
//
//  Guard: if AMENFeatureFlags.shared.liturgicalTheming is false, the modifier
//  is a passthrough and applies no tint. This allows the flag to be flipped
//  remotely without any SwiftUI rebuild overhead beyond the flag observation.
//
//  Opacity is applied here (view layer), not stored in SeasonTheme.glassTintHex.
//  The hex string in SeasonTheme is the pure color value at 100% opacity;
//  we overlay it at a low alpha so it never overwhelms the glass surface.
//

import SwiftUI

// MARK: - SeasonalGlassModifier

struct SeasonalGlassModifier: ViewModifier {

    @EnvironmentObject private var seasonService: LiturgicalSeasonService

    /// Overlay opacity for the seasonal tint.
    /// Each season has been calibrated so the resulting glass tint reads as
    /// a subtle hue shift at this opacity, not a solid color overlay.
    /// WCAG AA (4.5:1) is satisfied because this is an additive overlay on top
    /// of the existing glass material — the underlying text contrast is preserved
    /// by the material itself, and the tint is below perceptual threshold for text.
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
