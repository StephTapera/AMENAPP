// VoiceOrb.swift
// AMEN — Berean Reading Surface: VoiceOrb component (W1)
//
// Appears only when a Berean AI mode is active. idle = nothing rendered.
// Animated: outer halo pulses, inner waveform bars move.
// ReduceMotion: static glow ring, no pulse, no bars.

import SwiftUI

/// Significant mode indicator — maps 1:1 to BereanOrbState.
/// idle renders nothing. All other states show an animated orb.
struct VoiceOrb: View {

    let state: BereanOrbState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Group {
            if state != .idle {
                orbBody
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.berean(BereanSpring.cardRise, reduceMotion: reduceMotion), value: state)
    }

    private var orbBody: some View {
        ZStack {
            // Outer halo
            Circle()
                .fill(orbColor.opacity(0.12))
                .frame(width: BereanMetrics.orbSize + 28, height: BereanMetrics.orbSize + 28)
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.14 : 1.0))
                .opacity(reduceMotion ? 1 : (isPulsing ? 0.7 : 1.0))

            // Inner ring
            Circle()
                .strokeBorder(orbColor.opacity(0.5), lineWidth: 1.5)
                .frame(width: BereanMetrics.orbSize, height: BereanMetrics.orbSize)

            // Fill
            Circle()
                .fill(orbColor.opacity(0.18))
                .frame(width: BereanMetrics.orbSize, height: BereanMetrics.orbSize)

            // Waveform bars (motion only)
            if !reduceMotion {
                waveformBars
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
        .onChange(of: state) { _, _ in
            isPulsing = false
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to stop")
        .accessibilityAddTraits(.isButton)
    }

    private var waveformBars: some View {
        let heights: [CGFloat] = [9, 18, 13, 22, 11]
        let pulseHeights: [CGFloat] = [14, 24, 18, 28, 16]

        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(orbColor.opacity(0.75))
                    .frame(width: 3, height: isPulsing ? pulseHeights[i] : heights[i])
                    .animation(
                        .easeInOut(duration: 0.6 + Double(i) * 0.08)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.07),
                        value: isPulsing
                    )
            }
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
        case .praying:     return "Berean is in prayer mode"
        case .summarizing: return "Berean is summarizing"
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        VoiceOrb(state: .listening)
        VoiceOrb(state: .discerning)
        VoiceOrb(state: .praying)
        VoiceOrb(state: .summarizing)
    }
    .padding(48)
    .background(Color.bereanIvory)
}
