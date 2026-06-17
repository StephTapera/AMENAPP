// LiquidGlassCard.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen. Body is a placeholder.
// W1: Implement glass card — white @60-80% opacity, hairline stroke, shadow,
//     cornerRadius 24-32. ReduceTransparency fallback = solid bereanIvory + stronger stroke.
//     Cluster inside GlassEffectContainer at the call site.

import SwiftUI

/// A reusable Liquid Glass card for the Berean reading surface.
/// Pass content via the ViewBuilder; caller controls data and actions.
/// Components in BereanGlass/ must NOT import any Features/ folder.
struct LiquidGlassCard<Content: View>: View {

    let header: String?
    let onTap: (() -> Void)?
    let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        header: String? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        // W1: Replace with full glass + ivory fallback implementation.
        content()
            .accessibilityElement(children: .contain)
    }
}

#Preview {
    LiquidGlassCard(header: "Preview") {
        Text("Card content")
            .padding()
    }
    .padding()
}
