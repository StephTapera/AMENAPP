// LiquidGlassToolbar.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen.
// W1: Implement as GlassEffectContainer wrapping ordered action buttons.
//     Overflow items beyond available width collapse into "More" (ellipsis).
//     All items require VoiceOver labels and 44pt targets.
//     ReduceTransparency = solid bereanIvory bar.

import SwiftUI

/// An ordered set of actions inside a single GlassEffectContainer.
/// Cluster all related toolbar actions here so glass blur batches correctly.
struct LiquidGlassToolbar: View {

    let items: [BereanToolbarItem]

    var body: some View {
        // W1: Replace with GlassEffectContainer implementation + overflow handling.
        HStack(spacing: 12) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Label(item.label, systemImage: item.icon)
                        .font(BereanType.label)
                }
                .frame(minWidth: BereanMetrics.minTapTarget, minHeight: BereanMetrics.minTapTarget)
                .accessibilityLabel(item.label)
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    LiquidGlassToolbar(items: [
        BereanToolbarItem(id: "save",  icon: "bookmark",        label: "Save",    action: {}),
        BereanToolbarItem(id: "share", icon: "square.and.arrow.up", label: "Share", action: {}),
        BereanToolbarItem(id: "pray",  icon: "hands.and.sparkles.fill", label: "Pray", action: {}),
    ])
    .padding()
}
