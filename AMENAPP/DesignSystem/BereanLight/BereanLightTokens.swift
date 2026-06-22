// BereanLightTokens.swift
// AMEN — Berean Reading Surface: color, typography, and metric tokens (W0)
//
// FROZEN after BRS-W0-GATE. Additions require Class C blocker + human approval.
//
// Color strategy: berean* tokens are thin aliases to the existing BAS tokens
// defined in BereanAgentContracts.swift. Do NOT redefine the hex values here —
// always call through to the BAS canonical definitions so the two surfaces
// remain visually coherent if BAS color values are ever revised.

import SwiftUI

// MARK: - Color Tokens

extension Color {

    // Primary reading surface — warm off-white parchment.
    // Alias of Color.basWarmPaper (hex F7F0E3).
    static var bereanIvory: Color { .basWarmPaper }

    // High-contrast reading areas — near-pure white.
    static var bereanWhite: Color { Color(hex: "FAFAFA") }

    // Primary text — warm near-black.
    // Alias of Color.basInk (hex 1C1008).
    static var bereanInk: Color { .basInk }

    // Low-emphasis: chips, dividers, glass strokes.
    // Alias of Color.basTan (hex E8D9C0).
    static var bereanTan: Color { .basTan }

    // Sacred emphasis only: warnings, Discern flags, sacred moments.
    // Alias of Color.basWineRed (hex 6B2137).
    // Use at most once per screen.
    static var bereanWine: Color { .basWineRed }
}

// MARK: - Reading Typography (serif — scripture body text, reading surfaces)
//
// UI chrome fonts live in `BereanType` (BereanDesignSystem.swift). This adds the
// serif reading scale for reading surfaces only. Values use SwiftUI text-style
// descriptors so they scale correctly with Dynamic Type.

enum BereanReaderType {
    static let displayTitle: Font  = .system(.largeTitle, design: .serif, weight: .medium)
    static let sectionHeader: Font = .system(.title2,     design: .serif, weight: .semibold)
    static let body: Font          = .system(.body,        design: .serif)
}

// MARK: - Surface Metrics

enum BereanMetrics {
    // Corner radii
    static let cardRadius: CGFloat      = 24
    static let pillRadius: CGFloat      = 32
    static let inputBarRadius: CGFloat  = 20
    static let orbSize: CGFloat         = 80

    // Glass card material
    static let cardOpacity: Double      = 0.78
    static let strokeWidth: CGFloat     = 0.5

    // Shadow
    static let shadowRadius: CGFloat    = 12
    static let shadowOpacity: Double    = 0.08

    // Accessibility
    static let minTapTarget: CGFloat    = 44
}
