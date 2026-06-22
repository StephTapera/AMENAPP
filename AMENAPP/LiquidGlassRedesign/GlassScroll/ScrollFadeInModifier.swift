//
//  ScrollFadeInModifier.swift
//  AMENAPP
//
//  Per-view scroll-entrance motion (spec §6.7 / §8) plus a reduce-motion-aware parallax.
//
//  Fade-in drives opacity 0→1 and a gentle scale 0.98→1.0 as a view crosses the scroll
//  visibility threshold (`onScrollVisibilityChange`, iOS 18+). Reduce Motion → opacity
//  only (no scale). Pre-iOS 18 → the view simply appears at its final state on appear,
//  which is also the calm degradation. Fades are always allowed (spec §9).
//

import SwiftUI

// MARK: - Fade + scale on visibility

struct ScrollFadeInModifier: ViewModifier {
    var threshold: Double = 0.05
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let styled = content
            .opacity(shown ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.98))

        if #available(iOS 18.0, *) {
            styled.onScrollVisibilityChange(threshold: threshold) { isVisible in
                guard isVisible, !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.easeOut(duration: 0.35)) { shown = true }
                }
            }
        } else {
            styled.onAppear { shown = true }
        }
    }
}

// MARK: - Parallax (slower-than-scroll inner drift)

/// Drifts inner content slower than the scroll by a fractional counter-offset (spec §8).
/// Disabled entirely under Reduce Motion. `rawScroll` is the same "distance scrolled"
/// value the header consumes; `offset` only — never per-frame layout.
struct ScrollParallaxModifier: ViewModifier {
    var rawScroll: CGFloat
    var factor: CGFloat = 0.12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.offset(y: reduceMotion ? 0 : rawScroll * factor)
    }
}

// MARK: - Sugar

extension View {
    /// Fade + gentle scale-in as the view enters the viewport.
    func scrollFadeIn(threshold: Double = 0.05) -> some View {
        modifier(ScrollFadeInModifier(threshold: threshold))
    }

    /// Slower-than-scroll parallax drift (off under Reduce Motion).
    func scrollParallax(rawScroll: CGFloat, factor: CGFloat = 0.12) -> some View {
        modifier(ScrollParallaxModifier(rawScroll: rawScroll, factor: factor))
    }
}
