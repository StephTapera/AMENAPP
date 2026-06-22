// TopChromeAnimator.swift
// Smart Header Orchestrator — Animation helpers

import SwiftUI

struct TopChromeAnimator {

    // MARK: - Standard Transitions

    static var expandTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .move(edge: .top).combined(with: .opacity)
        )
    }

    static var fadeSlide: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }

    // MARK: - Spring Presets

    static var expand: Animation {
        .spring(response: TopChromeMetrics.springResponse,
                dampingFraction: TopChromeMetrics.springDamping)
    }

    static var collapse: Animation {
        .easeInOut(duration: TopChromeMetrics.collapseDuration)
    }

    // MARK: - Scroll-driven opacity

    static func opacity(for scrollOffset: CGFloat) -> Double {
        let start = TopChromeMetrics.collapseThreshold
        let end   = TopChromeMetrics.hideThreshold
        guard scrollOffset > start else { return 1 }
        return max(0, 1 - (scrollOffset - start) / (end - start))
    }

    // MARK: - ReduceMotion-aware

    static func animation(reducedMotion: Bool) -> Animation {
        reducedMotion ? .easeInOut(duration: 0.15) : expand
    }
}
