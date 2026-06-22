//
//  GlassContentCard.swift
//  AMENAPP
//
//  Generic Liquid Glass card for the collapsible-header feed (spec §6.3 / §8).
//
//  Wraps existing card *content* in authentic glass — it does not replace card
//  internals. Built on `liquidGlassSurface` (from LiquidGlassNative.swift), so it
//  inherits the native lens + the fail-closed solid fallback under Reduce Transparency.
//
//  A single `onScrollVisibilityChange` observer drives BOTH the entrance (opacity +
//  gentle scale) and the "brighten when visible/active" highlight, keeping one scroll
//  observer per card (spec §10). Reduce Motion → no scale; pre-iOS 18 → appear at final
//  state on appear.
//

import SwiftUI

struct GlassContentCard<Content: View>: View {
    var cornerRadius: CGFloat
    var emphasis: LiquidGlassEmphasis
    @ViewBuilder var content: () -> Content

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = 28,
        emphasis: LiquidGlassEmphasis = .none,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.emphasis = emphasis
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let card = content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(.medium, emphasis: emphasis, in: shape)
            .overlay {
                // Single hairline; brightens slightly once the card is visible/active.
                shape.stroke(Color.white.opacity(shown ? 0.32 : 0.16), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .compositingGroup()
            .opacity(shown ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.98))

        applyVisibility(to: card)
    }

    @ViewBuilder
    private func applyVisibility<V: View>(to view: V) -> some View {
        if #available(iOS 18.0, *) {
            view.onScrollVisibilityChange(threshold: 0.05) { isVisible in
                guard isVisible, !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.easeOut(duration: 0.35)) { shown = true }
                }
            }
        } else {
            view.onAppear { shown = true }
        }
    }
}
