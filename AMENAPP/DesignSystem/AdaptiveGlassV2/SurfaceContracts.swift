//
//  SurfaceContracts.swift
//  AMEN — Adaptive Glass V2
//
//  FROZEN CONTRACT — Wave 0.
//  All shared types used by the Adaptive Glass V2 system.
//  Additive-only. No consumer may compute GlassSurfaceState directly —
//  declare a SurfaceRole and let AdaptiveSurfaceEngine + SurfaceStateResolver
//  produce the state.
//
//  Target: iOS 17+ (all types are SDK-safe on iOS 17).
//

import SwiftUI

// MARK: - Brightness (precomputed per asset — never sampled per-frame)

/// Background brightness classification derived from the per-asset
/// AdaptiveColorEngine extraction. Stored alongside asset metadata;
/// never computed live on the main thread.
public enum Brightness: Equatable, Sendable {
    /// Predominantly dark content — controls should use light rendering.
    case dark
    /// Predominantly light content — controls should use dark rendering.
    case light
    /// High-saturation / high-contrast content where neither dark nor light
    /// applies cleanly. Triggers .frostedStrong surface tier.
    case busy
}

// MARK: - MediaKind

/// The media category of the content currently driving chrome adaptation.
public enum MediaKind: Equatable, Sendable {
    case none
    case image
    case video
    case heroBanner
}

// MARK: - ScrollState

public enum ScrollDirection: Equatable, Sendable {
    case up
    case down
}

/// Coarse scroll position classification. Drive from onScrollGeometryChange,
/// throttled (50 ms min interval) — never from a geometry reader per frame.
public enum ScrollState: Equatable, Sendable {
    /// Content offset near zero — bars are at rest at the top.
    case atTop
    /// User is actively scrolling.
    case scrolling(direction: ScrollDirection)
    /// Content has scrolled well past the fold — header bars should collapse.
    case deep
}

// MARK: - A11y snapshot (environment values frozen once per scene activation)

/// Snapshot of accessibility settings relevant to glass rendering.
/// Captured by the engine via a SwiftUI .task — never per-frame.
public struct A11ySnapshot: Equatable, Sendable {
    public var reduceTransparency: Bool
    public var reduceMotion: Bool
    public var increaseContrast: Bool
    public var dynamicTypeSize: DynamicTypeSize

    public init(reduceTransparency: Bool, reduceMotion: Bool,
                increaseContrast: Bool, dynamicTypeSize: DynamicTypeSize) {
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.dynamicTypeSize = dynamicTypeSize
    }

    /// Safe neutral defaults — fails open (does not force glass off).
    public static let `default` = A11ySnapshot(
        reduceTransparency: false,
        reduceMotion: false,
        increaseContrast: false,
        dynamicTypeSize: .large
    )
}

// MARK: - SurfaceContext (engine output — single source of truth)

/// The complete description of the visual environment at any given moment.
/// Published by AdaptiveSurfaceEngine and consumed by SurfaceStateResolver.
/// All fields are precomputed — no live sampling.
public struct SurfaceContext: Equatable, Sendable {
    /// Precomputed per asset. Never live-sampled.
    public var backgroundBrightness: Brightness
    /// Precomputed dominant hue from AdaptiveColorEngine. nil = plain/neutral.
    public var dominantColor: Color?
    /// The media type currently driving chrome adaptation.
    public var mediaType: MediaKind
    /// Coarse scroll position, throttled to 50 ms updates.
    public var scrollState: ScrollState
    /// True while the system keyboard is on-screen.
    public var keyboardVisible: Bool
    /// True while a text input field has first-responder focus.
    public var activeInput: Bool
    /// True when brightness == .busy or readability is at risk.
    /// A11y override wins if this is true.
    public var contrastRisk: Bool
    /// A11y settings snapshot — updated once per scene activation.
    public var a11y: A11ySnapshot

    /// Neutral context — the engine's initial state before any media loads.
    public static let neutral = SurfaceContext(
        backgroundBrightness: .light,
        dominantColor: nil,
        mediaType: .none,
        scrollState: .atTop,
        keyboardVisible: false,
        activeInput: false,
        contrastRisk: false,
        a11y: .default
    )
}

// MARK: - GlassSurfaceState

/// The visual state that the adaptive surface system assigns to a chrome surface.
/// Produced exclusively by SurfaceStateResolver — never computed by feature views.
public enum GlassSurfaceState: Equatable, Sendable {
    /// Clear — no background. Resting over full-bleed visual content.
    case transparent
    /// Standard Liquid Glass frost. Scrolling or light content underneath.
    case frosted
    /// Stronger frost for busy, high-contrast backgrounds.
    case frostedStrong
    /// Opaque system background for readability or a11y override.
    case solidLight
    /// Collapsed into a compact floating pill (top bar deep-scroll state).
    case collapsed
    /// Fully hidden — full-screen media mode.
    case hidden
}

// MARK: - SurfaceRole

/// The role of the chrome surface. Determines which resolver rules apply.
/// Declare at call site; never derive this from scroll offset or media state.
public enum SurfaceRole: Equatable, Sendable {
    /// System status bar zone — top safe area inset.
    case statusZone
    /// Primary navigation bar / top chrome.
    case topBar
    /// Bottom navigation pill.
    case bottomNav
    /// Text composer tray above the keyboard.
    case composerTray
    /// Inline action strip (post action row, media controls).
    case actionStrip
    /// Feed or inline card surface.
    case card
}

// MARK: - Environment keys

private struct GlassSurfaceStateKey: EnvironmentKey {
    static let defaultValue: GlassSurfaceState = .frosted
}

public extension EnvironmentValues {
    /// The resolved glass state for the nearest .adaptiveSurface() ancestor.
    /// Read this in custom surface implementations instead of computing state.
    var glassSurfaceState: GlassSurfaceState {
        get { self[GlassSurfaceStateKey.self] }
        set { self[GlassSurfaceStateKey.self] = newValue }
    }
}
