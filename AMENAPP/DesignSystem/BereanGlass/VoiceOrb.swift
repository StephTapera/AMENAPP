// VoiceOrb.swift
// AMEN — Berean Reading Surface component (W0 shell → W1 implementation)
//
// W0: Public signature frozen.
// W1: Implement animated waveform + outer halo ring.
//     idle = orb is hidden (EmptyView).
//     listening / discerning / praying / summarizing = orb visible with
//     mode-tinted halo pulse (orbPulse spring, gated on ReduceMotion).
//     ReduceMotion = static glow, no pulse.
//     VoiceOver: "Berean is [state description], double tap to stop."

import SwiftUI

/// A significant mode indicator — appears only when a Berean AI mode is active.
/// The orb maps 1:1 to BereanOrbState; idle = no orb rendered.
struct VoiceOrb: View {

    let state: BereanOrbState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // W1: Replace with animated waveform + halo.
        if state != .idle {
            Circle()
                .fill(orbColor.opacity(0.18))
                .overlay(
                    Circle().strokeBorder(orbColor.opacity(0.35), lineWidth: 1.5)
                )
                .frame(width: BereanMetrics.orbSize, height: BereanMetrics.orbSize)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Double tap to stop")
        }
    }

    private var orbColor: Color {
        switch state {
        case .idle:        return .clear
        case .listening:   return Color.bereanInk
        case .discerning:  return Color.bereanWine
        case .praying:     return Color.bereanTan
        case .summarizing: return Color.bereanInk
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:        return ""
        case .listening:   return "Berean is listening"
        case .discerning:  return "Berean is discerning"
        case .praying:     return "Berean is reflecting"
        case .summarizing: return "Berean is summarizing"
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        VoiceOrb(state: .listening)
        VoiceOrb(state: .discerning)
        VoiceOrb(state: .praying)
        VoiceOrb(state: .summarizing)
    }
    .padding()
}
