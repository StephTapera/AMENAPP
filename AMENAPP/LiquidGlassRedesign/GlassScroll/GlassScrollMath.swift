//
//  GlassScrollMath.swift
//  AMENAPP
//
//  Collapsible Liquid Glass header — scroll motion math (the single source of truth).
//
//  Everything the header/cards render is *interpolated* from one live scroll value.
//  No `withAnimation` wraps these numbers: they track the finger frame-for-frame so a
//  reversed or interrupted gesture follows instantly (spec §3 / §5). Discrete events
//  (pill selection, alert toggle) still use springs at their own call sites.
//
//  Helpers are namespaced under `GlassScrollMath` to avoid colliding with any
//  free-function `lerp`/`smoothstep` elsewhere in the app.
//

import CoreGraphics

// MARK: - Pure math

enum GlassScrollMath {
    /// Linear interpolation. `t` is expected in 0...1 but is not clamped here.
    @inline(__always) static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    /// Hermite smoothstep — calmer easing for decorative values.
    @inline(__always) static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always) static func clamp01(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
}

// MARK: - Geometry contract (the "tuck", spec §4)

/// Defines how much the header loses as it collapses. `collapseDistance` equals the
/// height delta, which is *also* the distance the first card must travel to sit flush
/// beneath the collapsed capsule — that equality is what makes the tuck seamless.
struct GlassScrollMetrics: Equatable {
    /// Content height when expanded (excludes the top safe-area inset).
    var expandedHeaderHeight: CGFloat = 220
    /// Content height when fully collapsed and pinned (excludes the top safe-area inset).
    var collapsedHeaderHeight: CGFloat = 88

    /// The height the header loses == the scroll distance the collapse spans.
    var collapseDistance: CGFloat { max(expandedHeaderHeight - collapsedHeaderHeight, 1) }

    /// Raw progress: 0 at rest, →1 once `collapseDistance` has been scrolled.
    func progress(forScrolled rawScroll: CGFloat) -> CGFloat {
        GlassScrollMath.clamp01(rawScroll / collapseDistance)
    }

    /// Eased progress for calm decorative interpolation.
    func easedProgress(forScrolled rawScroll: CGFloat) -> CGFloat {
        GlassScrollMath.smoothstep(0, 1, progress(forScrolled: rawScroll))
    }

    /// Current content height (excludes top inset) for an already-eased progress.
    func headerContentHeight(progressEased eased: CGFloat) -> CGFloat {
        GlassScrollMath.lerp(expandedHeaderHeight, collapsedHeaderHeight, eased)
    }
}

// MARK: - Derived header state (spec §5 interpolation table)

/// One snapshot of every interpolated header value for a given progress. Built once
/// per scroll update and handed to the header view, so the curves live in exactly
/// one place and stay consistent across surfaces.
struct GlassHeaderInterpolation {
    /// Raw, clamped progress 0...1 (finger position).
    let progress: CGFloat
    /// Smoothstepped progress for decorative values.
    let eased: CGFloat
    /// Header content height (excludes the top safe-area inset).
    let contentHeight: CGFloat
    /// Title scale 1.00 → 0.72.
    let titleScale: CGFloat
    /// Title vertical offset 0 → −42 (rises as it pins).
    let titleOffsetY: CGFloat
    /// Subtitle opacity 1 → 0, gone by the halfway point.
    let subtitleOpacity: CGFloat
    /// Overall glass-layer presence 0.15 → 0.75 (near-invisible → prominent capsule).
    let glassPresenceOpacity: CGFloat
    /// Accent tint alpha on the native glass 0.0 → 0.18.
    let glassTintAlpha: CGFloat
    /// Hairline highlight stroke opacity ~0.10 → ~0.35.
    let strokeOpacity: CGFloat
    /// Light drop-shadow opacity 0 → 0.10 (depth only when pinned).
    let shadowOpacity: CGFloat

    init(progress p: CGFloat, metrics: GlassScrollMetrics) {
        let pc = GlassScrollMath.clamp01(p)
        let e = GlassScrollMath.smoothstep(0, 1, pc)
        progress = pc
        eased = e
        contentHeight = GlassScrollMath.lerp(metrics.expandedHeaderHeight, metrics.collapsedHeaderHeight, e)
        titleScale = GlassScrollMath.lerp(1.0, 0.72, e)
        titleOffsetY = GlassScrollMath.lerp(0, -42, e)
        subtitleOpacity = 1 - GlassScrollMath.smoothstep(0, 0.5, pc)
        glassPresenceOpacity = GlassScrollMath.lerp(0.15, 0.75, e)
        glassTintAlpha = GlassScrollMath.lerp(0.0, 0.18, e)
        strokeOpacity = GlassScrollMath.lerp(0.10, 0.35, e)
        shadowOpacity = GlassScrollMath.lerp(0.0, 0.10, e)
    }
}
