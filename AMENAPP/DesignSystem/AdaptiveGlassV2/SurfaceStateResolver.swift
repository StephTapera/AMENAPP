//
//  SurfaceStateResolver.swift
//  AMEN — Adaptive Glass V2
//
//  Pure function: (SurfaceContext, SurfaceRole) -> GlassSurfaceState
//
//  Rules execute in strict priority order. Higher rules always short-circuit
//  lower rules. A11y overrides run first and can never be overridden.
//
//  Unit-test this file exhaustively — it is the heart of the system.
//  No imports from UIKit or SwiftUI; pure Swift, trivially testable.
//

import Foundation

public enum SurfaceStateResolver {

    // MARK: - Entry point

    /// Resolves the glass surface state for a given context and role.
    /// This function is pure: same inputs always produce the same output.
    /// Call on the main actor only (context is @MainActor-owned).
    public static func resolve(context: SurfaceContext, role: SurfaceRole) -> GlassSurfaceState {

        // ── Priority 0: A11y overrides — these ALWAYS win. ──────────────────
        // Legibility wins over aesthetics. Increase Contrast and Reduce
        // Transparency both collapse every surface to solid rendering.
        if context.a11y.increaseContrast   { return .solidLight }
        if context.a11y.reduceTransparency { return .solidLight }
        if context.contrastRisk            { return .solidLight }

        // ── Priority 1: Full-screen video rules. ─────────────────────────────
        // In a video context the content IS the background. Bottom nav hides
        // completely; the top bar goes transparent to let video breathe.
        if context.mediaType == .video {
            switch role {
            case .bottomNav:  return .hidden
            case .topBar:     return .transparent
            case .statusZone: return .transparent
            default:          break  // other roles fall through to scroll rules
            }
        }

        // ── Priority 2: Keyboard / input transforms. ─────────────────────────
        // When the keyboard is up, the DockedCreationRail replaces the bottom nav.
        // Hide the floating tab bar so it doesn't overlap the composer tray.
        if context.keyboardVisible {
            switch role {
            case .bottomNav:    return .hidden   // slides off; DockedCreationRail is the keyboard chrome
            case .composerTray: return .frosted
            default:            break
            }
        }

        // ── Priority 3: Scroll-state × role matrix. ──────────────────────────
        switch context.scrollState {

        // At top — initial resting state.
        case .atTop:
            switch role {
            case .topBar:
                // Over media/hero: transparent — content owns the top edge.
                // Over plain text feed: solidLight — clean white at rest (Home Feed spec).
                return context.mediaType != .none ? .transparent : .solidLight

            case .statusZone:
                return context.mediaType != .none ? .transparent : .frosted

            case .bottomNav:
                // Always frosted at rest — the pill is always glass.
                return .frosted

            case .composerTray, .actionStrip, .card:
                return .frosted
            }

        // Actively scrolling.
        case .scrolling:
            let isBusy = context.backgroundBrightness == .busy
            switch role {
            case .topBar:
                return isBusy ? .frostedStrong : .frosted

            case .statusZone:
                return isBusy ? .frostedStrong : .frosted

            case .bottomNav:
                // System .tabBarMinimizeBehavior handles the compress/expand animation.
                // The glass state itself stays frosted; visibility is a layout concern.
                return .frosted

            case .composerTray, .actionStrip:
                return isBusy ? .frostedStrong : .frosted

            case .card:
                return .frosted
            }

        // Deep in content — past the fold.
        case .deep:
            switch role {
            case .topBar:
                // Collapse to a floating glass pill with title + primary action.
                return .collapsed

            case .statusZone:
                return .frosted

            case .bottomNav:
                // Compressed, not hidden — system handles the minimize animation.
                return .frosted

            case .composerTray, .actionStrip:
                return .frosted

            case .card:
                return .frosted
            }
        }
    }
}
