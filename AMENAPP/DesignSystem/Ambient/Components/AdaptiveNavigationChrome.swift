//
//  AdaptiveNavigationChrome.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  Top bar + bottom tab tinting. Collapses hero bleed into a compact glass bar on scroll.
//  Tab bar reflects at most 0.10 × intensity (Rules / tint ceiling).
//

import SwiftUI

public struct AdaptiveNavigationChrome: ViewModifier {
    @Environment(\.ambientPalette) private var palette
    @Environment(\.ambientIntensity) private var intensity

    /// 0 = expanded over hero, 1 = fully collapsed glass bar. Drive from scroll offset.
    var collapseProgress: Double

    public func body(content: Content) -> some View {
        content
            .toolbarBackground(
                intensity > 0 && collapseProgress > 0.3 ? .visible : .hidden,
                for: .navigationBar
            )
            .toolbarBackground(
                palette.background.opacity(0.85 * collapseProgress), for: .navigationBar
            )
            .toolbarColorScheme(palette.isDarkContent ? .dark : .light, for: .navigationBar)
            .toolbarBackground(palette.background.opacity(0.10 * intensity), for: .tabBar) // subtle tab reflect
    }
}

public extension View {
    func adaptiveNavigationChrome(collapseProgress: Double) -> some View {
        modifier(AdaptiveNavigationChrome(collapseProgress: collapseProgress))
    }
}
