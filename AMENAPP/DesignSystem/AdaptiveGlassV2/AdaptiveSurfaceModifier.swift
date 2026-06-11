//
//  AdaptiveSurfaceModifier.swift
//  AMEN — Adaptive Glass V2
//
//  The only sanctioned way to adopt the adaptive glass system.
//  Screens declare a role; the engine + resolver produce the state.
//
//  Behaviour when adaptiveGlassV2Enabled is OFF:
//    - The modifier is a complete passthrough — zero behaviour change.
//    - Feature views do not need to guard against the flag themselves.
//
//  Behaviour when adaptiveGlassV2Enabled is ON:
//    - Resolved GlassSurfaceState is published via \.glassSurfaceState so
//      custom surface implementations (e.g. AMENTabBar) can read it.
//    - The modifier also handles .hidden (opacity 0) universally.
//    - For roles that own their own glass renderer (topBar, bottomNav,
//      statusZone) the modifier only publishes state — it never adds a
//      second glass layer (no-glass-on-glass invariant).
//    - For standalone roles (composerTray, actionStrip, card) the modifier
//      applies a glass background directly via the existing project shims
//      (amenRegularGlassEffect / amenProminentGlassEffect).
//

import SwiftUI

// MARK: - Primary modifier

public struct AdaptiveSurfaceModifier: ViewModifier {
    let role: SurfaceRole

    @Environment(\.adaptiveSurfaceEngine) private var engine

    public func body(content: Content) -> some View {
        // Flag OFF: zero-cost passthrough.
        guard AMENFeatureFlags.shared.adaptiveGlassV2Enabled, let engine else {
            return AnyView(content)
        }

        let ctx   = engine.context
        let state = SurfaceStateResolver.resolve(context: ctx, role: role)
        let reduceMotion = ctx.a11y.reduceMotion

        return AnyView(
            content
                // Publish state for custom renderers (AMENTabBar, nav chrome, etc.).
                .environment(\.glassSurfaceState, state)
                // Hidden state: slide off-screen (caller drives layout).
                // Opacity to 0 gives instant visual hide; layout offset handled per-surface.
                .opacity(state == .hidden ? 0 : 1)
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.15)
                        : .spring(response: 0.32, dampingFraction: 0.80),
                    value: state
                )
                // Standalone glass background for roles that don't own their renderer.
                .background(standaloneBackground(state: state, role: role))
        )
    }

    // MARK: - Standalone glass background

    @ViewBuilder
    private func standaloneBackground(state: GlassSurfaceState, role: SurfaceRole) -> some View {
        switch role {
        case .topBar, .bottomNav, .statusZone:
            // These roles own their glass rendering. Adding a second background
            // would violate the no-glass-on-glass rule.
            Color.clear

        case .composerTray, .actionStrip, .card:
            standaloneGlass(state: state, cornerRadius: cornerRadius(for: role))
        }
    }

    @ViewBuilder
    private func standaloneGlass(state: GlassSurfaceState, cornerRadius cr: CGFloat) -> some View {
        // Use project shims — they handle availability + correct iOS 17 fallback.
        // We never call Glass.regular / Glass.prominent directly to avoid
        // type-inference ambiguity in @ViewBuilder switch contexts.
        let rect = RoundedRectangle(cornerRadius: cr, style: .continuous)
        switch state {
        case .transparent, .hidden:
            Color.clear

        case .frosted:
            Color.clear.amenRegularGlassEffect(in: rect)

        case .frostedStrong:
            Color.clear.amenProminentGlassEffect(in: rect)

        case .solidLight:
            rect.fill(Color(uiColor: .systemBackground).opacity(0.97))

        case .collapsed:
            // Collapsed pills use a capsule shape.
            Color.clear.amenRegularGlassEffect(in: Capsule())
        }
    }

    private func cornerRadius(for role: SurfaceRole) -> CGFloat {
        switch role {
        case .composerTray: return 20
        case .actionStrip:  return 14
        case .card:         return 16
        default:            return 20
        }
    }
}

// MARK: - View extension

public extension View {
    /// Declare a surface role to adopt the adaptive glass system.
    ///
    /// The engine (installed via .adaptiveSurfaceScene() at the scene root)
    /// resolves context + role into a GlassSurfaceState and publishes it via
    /// \.glassSurfaceState — custom renderers read the state from there.
    ///
    /// This modifier is a no-op when adaptiveGlassV2Enabled is OFF.
    func adaptiveSurface(_ role: SurfaceRole) -> some View {
        modifier(AdaptiveSurfaceModifier(role: role))
    }
}

// MARK: - Ambient palette bridge

public extension View {
    /// Drive the scene engine from an existing AmbientCoordinator palette.
    ///
    ///     feedContent
    ///         .adaptiveSurfaceMediaBridge(palette: coordinator.palette, kind: .image)
    ///
    func adaptiveSurfaceMediaBridge(palette: AmbientPalette,
                                    kind: MediaKind) -> some View {
        modifier(AmbientBridgeModifier(palette: palette, kind: kind))
    }
}

private struct AmbientBridgeModifier: ViewModifier {
    let palette: AmbientPalette
    let kind: MediaKind
    @Environment(\.adaptiveSurfaceEngine) private var engine

    func body(content: Content) -> some View {
        content
            .onChange(of: palette) { _, newPalette in
                engine?.updateFromAmbientPalette(newPalette, kind: kind)
            }
            .onAppear {
                engine?.updateFromAmbientPalette(palette, kind: kind)
            }
            .onDisappear {
                engine?.resetMedia()
            }
    }
}
