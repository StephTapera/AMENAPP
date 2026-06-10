//
//  AdaptiveGlassContainer.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  The only sanctioned glass primitive. Controls/nav layers ONLY — never reading planes.
//  Handles: tint × intensity, Reduce Transparency (opaque, C3), Increase Contrast (border +
//  alpha floor), thin border, inner highlight, soft ambient shadow.
//  `glassEffect` is iOS 26+ (Liquid Glass); guarded with an ultraThinMaterial fallback for iOS 17.
//

import SwiftUI

public struct AdaptiveGlassContainer<Content: View>: View {
    @Environment(\.ambientPalette) private var palette
    @Environment(\.ambientIntensity) private var intensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var shape: AnyShape
    var tintAlpha: Double            // pre-intensity ceiling
    var glow: Bool                   // gentle focus glow, opt-in only
    @ViewBuilder var content: () -> Content

    public init(shape: some Shape = Capsule(), tintAlpha: Double = 0.18,
                glow: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.shape = AnyShape(shape); self.tintAlpha = tintAlpha
        self.glow = glow; self.content = content
    }

    public var body: some View {
        let effectiveTint = palette.dominant.opacity(tintAlpha * intensity)
        content()
            .background {
                if reduceTransparency {                                    // C3
                    shape.fill(palette.background)
                } else if #available(iOS 26.0, *) {
                    shape.fill(.clear)
                        .glassEffect(.regular.tint(effectiveTint), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(effectiveTint))
                }
            }
            .overlay {
                shape.strokeBorder(
                    palette.textPrimary.opacity(contrast == .increased ? 0.35 : 0.12),
                    lineWidth: contrast == .increased ? 1.0 : 0.5
                )
            }
            .overlay(alignment: .top) {   // inner highlight
                shape.strokeBorder(Color.white.opacity(palette.isDarkContent ? 0.10 : 0.25), lineWidth: 0.5)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .shadow(color: palette.shadow.opacity(glow ? 0.6 : 0.3), radius: glow ? 14 : 8, y: 4)
    }
}
