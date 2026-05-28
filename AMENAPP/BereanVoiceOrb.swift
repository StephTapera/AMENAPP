// BereanVoiceOrb.swift
// AMENAPP
//
// Berean Live Voice — Liquid Glass animated voice orb
//
// A self-contained SwiftUI component. No existing files are modified.

import SwiftUI

// MARK: - BereanVoiceOrb

struct BereanVoiceOrb: View {

    // -------------------------------------------------------------------------
    // MARK: Inputs
    // -------------------------------------------------------------------------

    let state:    BereanVoiceState
    let micLevel: Float
    let mode:     BereanVoiceMode

    // -------------------------------------------------------------------------
    // MARK: Environment
    // -------------------------------------------------------------------------

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // -------------------------------------------------------------------------
    // MARK: Animation State
    // -------------------------------------------------------------------------

    @State private var pulseScale:   CGFloat = 1.0
    @State private var glowOpacity:  Double  = 0.0
    @State private var wavePhase:    Double  = 0.0
    @State private var outerScale:   CGFloat = 1.0
    @State private var outerOpacity: Double  = 0.0
    @State private var snapScale:    CGFloat = 1.0

    // -------------------------------------------------------------------------
    // MARK: Constants
    // -------------------------------------------------------------------------

    private let orbSize: CGFloat = 80

    // MARK: Mode Accent Colour

    private var accentColour: Color {
        switch mode {
        case .prayer:       return .teal
        case .discovery:    return .indigo
        case .wellness:     return Color(red: 0.5, green: 0.2, blue: 0.8)
        case .churchNotes:  return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .conversation: return .black
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Body
    // -------------------------------------------------------------------------

    var body: some View {
        ZStack {
            // 1. Outer glow ring
            outerGlowRing

            // 2. Glass sphere (Liquid Glass)
            glassSphere

            // 3. Waveform bars (listening / speaking)
            if state == .listening || state == .speaking {
                waveformBars
            }

            // 4. State icon overlay
            stateIcon

            // 5. Outer pulse ring (speaking only)
            if state == .speaking {
                outerPulseRing
            }
        }
        .frame(width: orbSize, height: orbSize)
        .onChange(of: state) { _, newState in
            updateAnimations(for: newState)
        }
        .onAppear {
            updateAnimations(for: state)
            if !reduceMotion {
                withAnimation(
                    .linear(duration: 2.0).repeatForever(autoreverses: false)
                ) {
                    wavePhase = .pi * 2
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Sub-views
    // -------------------------------------------------------------------------

    private var outerGlowRing: some View {
        Circle()
            .strokeBorder(accentColour, lineWidth: 1.5)
            .frame(width: orbSize + 16, height: orbSize + 16)
            .opacity(glowOpacity)
    }

    private var glassSphere: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: orbSize, height: orbSize)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(pulseScale * snapScale)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6),
                value: snapScale
            )
    }

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(accentColour.opacity(0.7))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.15),
                        value: micLevel
                    )
            }
        }
        .frame(width: 30, height: 28)
    }

    private var stateIcon: some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
            case .thinking:
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(.primary)
            case .interrupted:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
            case .listening, .speaking:
                EmptyView()
            }
        }
    }

    private var outerPulseRing: some View {
        Circle()
            .strokeBorder(accentColour.opacity(0.3), lineWidth: 2)
            .frame(width: orbSize, height: orbSize)
            .scaleEffect(outerScale)
            .opacity(outerOpacity)
    }

    // -------------------------------------------------------------------------
    // MARK: Animation Logic
    // -------------------------------------------------------------------------

    private func updateAnimations(for newState: BereanVoiceState) {
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
            switch newState {

            case .idle:
                pulseScale  = 1.0
                glowOpacity = 0.0
                outerScale  = 1.0
                outerOpacity = 0.0

            case .listening:
                glowOpacity = 0.2
                if !reduceMotion {
                    withAnimation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.05
                    }
                }

            case .thinking:
                pulseScale  = 1.0
                glowOpacity = 0.3

            case .speaking:
                glowOpacity = 0.5
                if !reduceMotion {
                    withAnimation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.15
                    }
                    withAnimation(
                        .easeOut(duration: 1.2)
                        .repeatForever(autoreverses: false)
                    ) {
                        outerScale   = 1.4
                        outerOpacity = 0.0
                    }
                }

            case .interrupted:
                pulseScale  = 1.0
                glowOpacity = 0.0
                if !reduceMotion {
                    // Snap to 0.95 then bounce back
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                        snapScale = 0.95
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            snapScale = 1.0
                        }
                    }
                }

            case .error:
                pulseScale  = 1.0
                glowOpacity = 0.0
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Waveform Helpers
    // -------------------------------------------------------------------------

    /// Height of each waveform bar — driven by micLevel + animated sine wave.
    private func barHeight(for index: Int) -> CGFloat {
        let base:      CGFloat = 6
        let maxHeight: CGFloat = 22
        let phase = wavePhase + Double(index) * .pi / 2.5
        let sineComponent = CGFloat((sin(phase) + 1) / 2) * maxHeight * 0.5
        let levelComponent = CGFloat(max(0, min(1, (micLevel + 60) / 60))) * maxHeight * 0.5
        return base + sineComponent + (state == .listening ? levelComponent : 0)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Orb States") {
    VStack(spacing: 24) {
        ForEach([
            BereanVoiceState.idle,
            .listening,
            .thinking,
            .speaking,
            .interrupted,
            .error
        ], id: \.rawValue) { s in
            VStack(spacing: 6) {
                BereanVoiceOrb(state: s, micLevel: -20, mode: BereanVoiceMode.conversation)
                Text(s.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(32)
    .background(Color(.systemBackground))
}
#endif
