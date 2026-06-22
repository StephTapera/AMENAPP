// AccentColorPalette.swift
// AMEN — Settings/Safety system · Design System
//
// Single source of truth mapping the AccentColor contract enum to brand color tokens.
// Call sites use `accent.color` / `accent.displayName` — never a raw hex literal at the
// call site. The hex mapping lives here, paired with AmenTheme brand tokens.

import SwiftUI

extension AccentColor {

    /// Resolved brand-mapped color token for this accent.
    var color: Color {
        switch self {
        case .default: return AmenTheme.Colors.amenGold
        case .blue:    return AmenTheme.Colors.statusInfo
        case .green:   return AmenTheme.Colors.statusSuccess
        case .yellow:  return Color(hex: "F2C94C")
        case .pink:    return Color(hex: "EB5FA6")
        case .orange:  return AmenTheme.Colors.amenBronze
        case .purple:  return Color(hex: "8E6BD6")
        // "Black" maps to the adaptive primary label (AMEN's monochrome CTA convention):
        // black on light, white on dark — a high-contrast neutral accent.
        case .black:   return AmenTheme.Colors.textPrimary
        case .tan:     return Color(hex: "C8A97E")
        case .wineRed: return Color(hex: "7B2D3B")
        }
    }

    /// Human-readable label for pickers and accessibility.
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .blue:    return "Blue"
        case .green:   return "Green"
        case .yellow:  return "Yellow"
        case .pink:    return "Pink"
        case .orange:  return "Orange"
        case .purple:  return "Purple"
        case .black:   return "Black"
        case .tan:     return "Tan"
        case .wineRed: return "Wine Red"
        }
    }
}
