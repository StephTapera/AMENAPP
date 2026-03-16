// VoiceSphereView.swift
// AMEN App — Voice Orb UI
// Mirrors three states: idle, listening (user speaking), responding (AI speaking)
// Used in Berean AI when voice input is active.

import SwiftUI

// MARK: - State

enum VoiceOrbState {
    case idle
    case listening   // user is speaking
    case responding  // AI is speaking back

    var statusLabel: String {
        switch self {
        case .idle:       return "idle"
        case .listening:  return "listening"
        case .responding: return "responding"
        }
    }

    var hintLabel: String {
        switch self {
        case .idle:       return "tap & hold to speak"
        case .listening:  return "speak freely\u{2026}"
        case .responding: return ""
        }
    }

    var ringColor: Color {
        switch self {
        case .idle:       return .clear
        case .listening:  return Color(red: 1.0, green: 0.73, blue: 0.24) // warm gold
        case .responding: return Color(red: 0.58, green: 0.43, blue: 1.0) // soft purple
        }
    }

    var sphereTint: Color {
        switch self {
        case .idle:       return Color(white: 0.94)
        case .listening:  return Color(red: 0.98, green: 0.93, blue: 0.82) // warm cream
        case .responding: return Color(red: 0.92, green: 0.88, blue: 1.0) // cool lavender
        }
    }

    var pulseScale: CGFloat {
        switch self {
        case .idle:       return 1.022
        case .listening:  return 1.06
        case .responding: return 1.045
        }
    }

    var pulseDuration: Double {
        switch self {
        case .idle:       return 4.0
        case .listening:  return 1.6
        case .responding: return 2.2
        }
    }
}

// MARK: - Main View

struct VoiceSphereView: View {

    @Binding var state: VoiceOrbState
    var onTapHold: (() -> Void)? = nil
    var onRelease: (() -> Void)? = nil

    @State private var pulsing = false
    @State private var foldOffset: CGFloat = 0
    @State private var ringScale1: CGFloat = 1
    @State private var ringScale2: CGFloat = 1
    @State private var ringScale3: CGFloat = 1
    @State private var ringOpacity1: Double = 0
    @State private var ringOpacity2: Double = 0
    @State private var ringOpacity3: Double = 0

    private let sphereSize: CGFloat = 200

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.027, blue: 0.051)
                .ignoresSafeArea()

            RadialGradient(
                colors: [state.ringColor.opacity(0.06), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 220
            )
            .frame(width: 440, height: 440)
            .animation(.easeInOut(duration: 0.8), value: state.ringColor)

            VStack(spacing: 0) {
                Text("AMEN")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.18))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 48)

                Spacer()

                ZStack {
                    ringView(scale: ringScale1, opacity: ringOpacity1)
                    ringView(scale: ringScale2, opacity: ringOpacity2)
                    ringView(scale: ringScale3, opacity: ringOpacity3)

                    OrbSphere(
                        size: sphereSize,
                        tint: state.sphereTint,
                        foldOffset: foldOffset,
                        pulsing: pulsing,
                        pulseScale: state.pulseScale
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in onTapHold?() }
                            .onEnded { _ in onRelease?() }
                    )
                    .accessibilityLabel(state == .listening ? "Recording voice" : "Tap and hold to speak")
                    .accessibilityHint("Hold to record your voice message")
                }
                .frame(width: sphereSize + 160, height: sphereSize + 160)

                Spacer()

                Text(state.statusLabel.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(3)
                    .foregroundStyle(statusColor)
                    .animation(.easeInOut(duration: 0.5), value: state)
                    .padding(.bottom, 6)

                Text(state.hintLabel)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.14))
                    .frame(height: 20)
                    .animation(.easeInOut(duration: 0.4), value: state)
                    .padding(.bottom, 48)
            }
            .padding(.vertical, 40)
        }
        .onChange(of: state) { _, newState in
            restartAnimations(for: newState)
        }
        .onAppear {
            restartAnimations(for: state)
        }
    }

    @ViewBuilder
    private func ringView(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(state.ringColor.opacity(opacity), lineWidth: 1)
            .frame(width: sphereSize, height: sphereSize)
            .scaleEffect(scale)
    }

    private var statusColor: Color {
        switch state {
        case .idle:       return .white.opacity(0.25)
        case .listening:  return Color(red: 1.0, green: 0.74, blue: 0.25).opacity(0.7)
        case .responding: return Color(red: 0.61, green: 0.45, blue: 1.0).opacity(0.7)
        }
    }

    private func restartAnimations(for newState: VoiceOrbState) {
        pulsing = false
        ringOpacity1 = 0; ringOpacity2 = 0; ringOpacity3 = 0
        ringScale1 = 1; ringScale2 = 1; ringScale3 = 1
        foldOffset = 0

        withAnimation(.easeInOut(duration: newState.pulseDuration).repeatForever(autoreverses: true)) {
            pulsing = true
        }

        if newState != .idle {
            startRings(for: newState)
            withAnimation(.easeInOut(duration: newState.pulseDuration).repeatForever(autoreverses: true)) {
                foldOffset = newState == .listening ? 6 : 5
            }
        }
    }

    private func startRings(for newState: VoiceOrbState) {
        let dur = newState == .listening ? 2.0 : 2.6
        fireRing(scale: $ringScale1, opacity: $ringOpacity1, duration: dur, delay: 0)
        fireRing(scale: $ringScale2, opacity: $ringOpacity2, duration: dur, delay: dur / 3)
        fireRing(scale: $ringScale3, opacity: $ringOpacity3, duration: dur, delay: (dur / 3) * 2)
    }

    private func fireRing(
        scale: Binding<CGFloat>,
        opacity: Binding<Double>,
        duration: Double,
        delay: Double
    ) {
        func pulse() {
            scale.wrappedValue = 1
            opacity.wrappedValue = 0.65
            withAnimation(.easeOut(duration: duration).delay(delay)) {
                scale.wrappedValue = 1.75
                opacity.wrappedValue = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + delay + 0.05) {
                guard self.state != .idle else { return }
                pulse()
            }
        }
        pulse()
    }
}

// MARK: - Sphere Shape

struct OrbSphere: View {
    let size: CGFloat
    let tint: Color
    let foldOffset: CGFloat
    let pulsing: Bool
    let pulseScale: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, tint, tint.opacity(0.7)],
                        center: UnitPoint(x: 0.37, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)

            ZStack {
                FoldLayer(index: 0, size: size, offset: foldOffset)
                FoldLayer(index: 1, size: size, offset: foldOffset)
                FoldLayer(index: 2, size: size, offset: foldOffset)
                FoldLayer(index: 3, size: size, offset: foldOffset)
                FoldLayer(index: 4, size: size, offset: foldOffset)
            }
            .clipShape(Circle())
            .frame(width: size, height: size)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.4, green: 0.4, blue: 0.68).opacity(0.2), .clear],
                        center: UnitPoint(x: 0.72, y: 0.78),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.7), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 35
                    )
                )
                .frame(width: 68, height: 48)
                .offset(x: -size * 0.27, y: -size * 0.27)
                .rotationEffect(.degrees(-18))
        }
        .scaleEffect(pulsing ? pulseScale : 1.0)
        .animation(
            .easeInOut(duration: 4).repeatForever(autoreverses: true),
            value: pulsing
        )
    }
}

// MARK: - Fold Layer

struct FoldLayer: View {
    let index: Int
    let size: CGFloat
    let offset: CGFloat

    private var widthFraction: CGFloat { 0.76 - CGFloat(index) * 0.09 }
    private var heightFraction: CGFloat { 0.96 - CGFloat(index) * 0.07 }
    private var rightInset: CGFloat { (-0.09 + CGFloat(index) * 0.045) * size }
    private var topInset: CGFloat { (0.01 + CGFloat(index) * 0.04) * size }
    private var layerOpacity: Double { 0.52 - Double(index) * 0.08 }
    private var animDelay: Double { Double(index) * 0.08 }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.35)
            .fill(.white.opacity(layerOpacity))
            .frame(width: size * widthFraction, height: size * heightFraction)
            .offset(
                x: (size / 2) - (size * widthFraction / 2) + rightInset + offset,
                y: -(size / 2) + (size * heightFraction / 2) + topInset
            )
            .animation(
                .easeInOut(duration: 1.6)
                .repeatForever(autoreverses: true)
                .delay(animDelay),
                value: offset
            )
    }
}
