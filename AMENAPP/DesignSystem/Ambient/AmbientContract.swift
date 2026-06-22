//
//  AmbientContract.swift
//  AMEN — Adaptive Ambient UI System
//
//  PHASE 1 — FROZEN CONTRACT. Additive-only. Do not modify these types without a
//  contract revision. Every Ambient agent reads this verbatim. Invariants C1–C8
//  (see system spec) are enforced against the types defined here.
//
//  Target: iOS 17+ (Liquid Glass `glassEffect` is guarded behind #available(iOS 26)
//  in the components layer). This file is SDK-safe on iOS 17.
//
//  Isolation note: this module compiles with MainActor-default actor isolation. The
//  palette currency must cross actor boundaries into the off-main `AdaptiveColorEngine`
//  (invariant C7 — extraction never runs on the main actor), so the value types and
//  their members are explicitly `nonisolated`. This is an isolation annotation only;
//  it does not change the public shape of the frozen types.
//

import SwiftUI

// MARK: - User setting (frozen enum — do not add cases without contract rev)

public enum AdaptiveColorsMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, subtle, balanced, immersive
    public var id: String { rawValue }

    /// Global intensity multiplier applied to every tint, bleed, and glow.
    public var intensity: Double {
        switch self {
        case .off: 0.0
        case .subtle: 0.35
        case .balanced: 0.65
        case .immersive: 1.0
        }
    }

    public var label: String {
        switch self {
        case .off: "Off"
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .immersive: "Immersive"
        }
    }
}

public enum AmbientStorageKeys {
    public static let mode = "amen.ambient.mode"   // @AppStorage, default .balanced
}

// MARK: - Palette (the single currency of the system)

public struct AmbientPalette: Equatable, Sendable {
    public var dominant: Color        // strongest perceptual color of the content
    public var background: Color      // muted, luminance-clamped page wash
    public var accent: Color          // most saturated viable color (controls, sliders, reactions)
    public var textPrimary: Color     // guaranteed ≥ 4.5:1 vs background (7:1 if Increase Contrast)
    public var textSecondary: Color   // guaranteed ≥ 3:1 vs background
    public var glassTint: Color       // low-alpha tint fed into glassEffect / materials
    public var shadow: Color          // ambient shadow color (darkened dominant)
    public var isDarkContent: Bool    // drives glass style + status bar style

    nonisolated public init(dominant: Color, background: Color, accent: Color,
                            textPrimary: Color, textSecondary: Color,
                            glassTint: Color, shadow: Color, isDarkContent: Bool) {
        self.dominant = dominant; self.background = background; self.accent = accent
        self.textPrimary = textPrimary; self.textSecondary = textSecondary
        self.glassTint = glassTint; self.shadow = shadow; self.isDarkContent = isDarkContent
    }

    /// Canonical AMEN neutrals — the fail-closed fallback and the .off rendering.
    /// Matches the white/light Liquid Glass system: neutral gray page, white cards, black SF text.
    nonisolated public static var neutralLight: AmbientPalette {
        AmbientPalette(
            dominant: Color(white: 0.45),
            background: Color(uiColor: .systemGroupedBackground),
            accent: Color.accentColor,
            textPrimary: .primary,
            textSecondary: .secondary,
            glassTint: Color.white.opacity(0.0),
            shadow: Color.black.opacity(0.12),
            isDarkContent: false
        )
    }

    nonisolated public static var neutralDark: AmbientPalette {
        AmbientPalette(
            dominant: Color(white: 0.6),
            background: Color(uiColor: .systemBackground),
            accent: Color.accentColor,
            textPrimary: .primary,
            textSecondary: .secondary,
            glassTint: Color.black.opacity(0.0),
            shadow: Color.black.opacity(0.35),
            isDarkContent: true
        )
    }

    nonisolated public static func neutral(for scheme: ColorScheme) -> AmbientPalette {
        scheme == .dark ? .neutralDark : .neutralLight
    }
}

// MARK: - Source identity (cache key discipline)

/// Every piece of media that can drive Ambient must provide a stable identity.
/// Firestore doc ID + media revision is the canonical pattern.
public struct AmbientSourceKey: Hashable, Sendable {
    public let id: String          // e.g. "post/abc123" or "user/uid/avatar"
    public let revision: String    // media version hash or updatedAt millis
    nonisolated public init(id: String, revision: String) { self.id = id; self.revision = revision }
    nonisolated public var cacheKey: String { "\(id)#\(revision)" }
}

// MARK: - Environment plumbing (frozen keys)

public struct AmbientPaletteKey: EnvironmentKey {
    public static let defaultValue: AmbientPalette = .neutralLight
}
public struct AmbientIntensityKey: EnvironmentKey {
    public static let defaultValue: Double = 0.65   // balanced
}

public extension EnvironmentValues {
    var ambientPalette: AmbientPalette {
        get { self[AmbientPaletteKey.self] } set { self[AmbientPaletteKey.self] = newValue }
    }
    var ambientIntensity: Double {
        get { self[AmbientIntensityKey.self] } set { self[AmbientIntensityKey.self] = newValue }
    }
}
