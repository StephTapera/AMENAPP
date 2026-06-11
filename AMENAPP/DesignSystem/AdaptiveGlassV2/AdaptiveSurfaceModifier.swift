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
//    - Resolved GlassSurfaceState is published via \.glassSurfaceState
//      so custom surface implementations (e.g. AMENTabBar) can read it.
//    - The modifier also directly handles .hidden (opacity 0).
//    - For surfaces that use the modifier as their sole glass provider
//      (composerTray, actionStrip, card) it applies a native glass
//      background through the iOS 26 / iOS 17 compatibility shim.
//

import SwiftUI

// MARK: - Primary modifier

public struct AdaptiveSurfaceModifier: ViewModifier {
    let role: SurfaceRole

    @Environment(\.adaptiveSurfaceEngine) private var engine
    @Environment(\.colorScheme)           private var colorScheme

    public func body(content: Content) -> some View {
        // Flag OFF: zero-cost passthrough.
        guard AMENFeatureFlags.shared.adaptiveGlassV2Enabled, let engine else {
            return AnyView(content)
        }

        let state = SurfaceStateResolver.resolve(context: engine.context, role: role)
        let reduceMotion = engine.context.a11y.reduceMotion

        return AnyView(
            content
                // Publish state into environment for custom renderers.
                .environment(\.glassSurfaceState, state)
                // Handle hidden state universally — custom renderers don't need to.
                .opacity(state == .hidden ? 0 : 1)
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.15)
                        : .spring(response: 0.32, dampingFraction: 0.80),
                    value: state
                )
                // For roles that don't have their own glass renderer,
                // apply a background directly.
                .background(
                    standaloneBackground(state: state, role: role)
                )
        )
    }

    // MARK: - Standalone glass background

    /// Applied to roles that don't own their own glass renderer
    /// (composerTray, actionStrip, card). Top-bar / bottom-nav / status-zone
    /// have their own implementations that read glassSurfaceState; this
    /// background would stack on top of their existing glass and violate
    /// the no-glass-on-glass rule, so those roles are excluded.
    @ViewBuilder
    private func standaloneBackground(state: GlassSurfaceState, role: SurfaceRole) -> some View {
        switch role {
        case .topBar, .bottomNav, .statusZone:
            // These roles own their glass rendering — don't add a second layer.
            Color.clear

        case .composerTray, .actionStrip, .card:
            standaloneGlass(state: state, cornerRadius: cornerRadius(for: role))
        }
    }

    @ViewBuilder
    private func standaloneGlass(state: GlassSurfaceState, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch state {
        case .transparent:
            Color.clear

        case .frosted:
            if #available(iOS 26, *) {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }

        case .frostedStrong:
            if #available(iOS 26, *) {
                shape.fill(.clear).glassEffect(.prominent, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }

        case .solidLight:
            shape.fill(Color(uiColor: .systemBackground).opacity(0.97))

        case .collapsed:
            let capsule = Capsule()
            if #available(iOS 26, *) {
                capsule.fill(.clear).glassEffect(.regular, in: capsule)
            } else {
                capsule.fill(.ultraThinMaterial)
            }

        case .hidden:
            Color.clear
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
    /// \.glassSurfaceState — custom renderers can read it from there.
    ///
    /// This modifier is a no-op when adaptiveGlassV2Enabled is OFF.
    func adaptiveSurface(_ role: SurfaceRole) -> some View {
        modifier(AdaptiveSurfaceModifier(role: role))
    }
}

// MARK: - Convenience: ambient palette bridge

public extension View {
    /// Drive the scene engine from the current AmbientCoordinator palette.
    /// Attach to a view that already owns an AmbientCoordinator.
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
