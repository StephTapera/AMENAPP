//
//  CollapsibleGlassHeader.swift
//  AMENAPP
//
//  The pinned, scroll-driven Liquid Glass header (spec §6.2 / §2).
//
//  Apple-Weather behaviour: a large hero title compresses and pins to a compact glass
//  capsule as the user scrolls up. Every value is interpolated from `progress` via
//  `GlassHeaderInterpolation` — there is no `withAnimation` here, so the motion tracks
//  the finger and reverses instantly.
//
//  Native glass: "blurAmount 12 → 28" has no numeric analogue in Liquid Glass, so the
//  *intent* is translated into a crossfade of glass presence — near-invisible (read-
//  through) when expanded, a prominent readable capsule when collapsed. Reduce
//  Transparency crossfades a solid translucent fill the same way (spec §9).
//

import SwiftUI

struct CollapsibleGlassHeader<Artwork: View>: View {
    let progress: CGFloat
    let title: String
    var subtitle: String?
    var metrics: GlassScrollMetrics
    /// Top safe-area inset the header reserves (supplied by the host scaffold).
    var topInset: CGFloat
    @ViewBuilder var artwork: () -> Artwork

    init(
        progress: CGFloat,
        title: String,
        subtitle: String? = nil,
        metrics: GlassScrollMetrics = .init(),
        topInset: CGFloat,
        @ViewBuilder artwork: @escaping () -> Artwork = { EmptyView() }
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.topInset = topInset
        self.artwork = artwork
    }

    var body: some View {
        let i = GlassHeaderInterpolation(progress: progress, metrics: metrics)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous
        )

        ZStack(alignment: .bottomLeading) {
            // Optional hero artwork fades out as the header pins (decorative —
            // hidden from VoiceOver so it never becomes a stray swipe stop).
            artwork()
                .opacity(1 - i.eased)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .scaleEffect(i.titleScale, anchor: .leading)
                    .offset(y: i.titleOffsetY)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(i.subtitleOpacity)
                        .offset(y: i.titleOffsetY)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            // One header element regardless of scroll-driven scale/opacity: VoiceOver
            // reads "Title, subtitle" as a single navigable header, not two drifting nodes.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: topInset + i.contentHeight, alignment: .bottom)
        .background(
            ContinuousGlassBackground(
                shape: AnyShape(shape),
                presence: i.glassPresenceOpacity,
                tintAlpha: i.glassTintAlpha,
                tint: LGAccent.interactive
            )
        )
        .overlay(alignment: .bottom) {
            // Single hairline highlight; depth comes from glass, not stacked shadows.
            Rectangle()
                .fill(Color.white.opacity(i.strokeOpacity))
                .frame(height: 0.75)
        }
        .shadow(color: .black.opacity(i.shadowOpacity), radius: 10, y: 4)
    }
}

// MARK: - Continuous-tint glass background

/// A header background whose glass *presence* and accent tint track scroll progress
/// continuously — the crossfade that stands in for a numeric blur ramp (spec §2).
///
/// Uses the same typed-`Glass` disambiguation documented in `LiquidGlassNative.swift`:
/// passing an explicitly-typed `Glass` binds Apple's `glassEffect(_:in:)` rather than the
/// legacy `GlassEffectStyle` shim in `GlassEffectModifiers.swift`. Reduce Transparency or
/// a pre-26 OS renders a solid translucent fill crossfaded the same way (fail-closed).
private struct ContinuousGlassBackground: View {
    let shape: AnyShape
    /// Overall glass-layer opacity, 0.15 (expanded) → 0.75 (collapsed).
    let presence: CGFloat
    /// Accent tint alpha on the native glass, 0.0 → 0.18.
    let tintAlpha: CGFloat
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            // Solid translucent fill, crossfaded by the same presence curve.
            shape.fill(AmenTheme.Colors.surfaceElevated.opacity(min(presence + 0.20, 1)))
        } else if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(tintedGlass, in: shape)
                .opacity(presence)
        } else {
            shape.fill(AmenTheme.Colors.surfaceElevated.opacity(min(presence + 0.20, 1)))
        }
    }

    @available(iOS 26.0, *)
    private var tintedGlass: Glass {
        // `g` is explicitly typed `Glass` → native lens, never the app's shim overload.
        let g: Glass = .regular
        return g.tint(tint.opacity(tintAlpha))
    }
}
