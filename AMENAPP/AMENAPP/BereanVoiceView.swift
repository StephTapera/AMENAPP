// BereanVoiceView.swift
// AMENAPP
//
// Full Berean AI voice surface.
// Three glass implementations: .lensed (default), .contextual, .compressed.
// Modes: listen, prayer, study, capture.
// States: idle, listening, processing, speaking.

import SwiftUI
import Combine

// MARK: - Voice Models

enum BereanVoiceViewState: Equatable {
    case idle
    case listening
    case processing
    case speaking(text: String)
}

enum BereanVoiceOrbMode: String, CaseIterable {
    case listen  = "Listen"
    case prayer  = "Prayer"
    case study   = "Study"
    case capture = "Capture"

    var icon: String {
        switch self {
        case .listen:  "waveform"
        case .prayer:  "hands.sparkles"
        case .study:   "book.pages"
        case .capture: "doc.text"
        }
    }

    var contextLabel: String {
        switch self {
        case .listen:  "Listening for your thought"
        case .prayer:  "Praying with you"
        case .study:   "Scripture study mode"
        case .capture: "Capturing your reflection"
        }
    }

    var orbColor: Color {
        switch self {
        case .listen:  Color.black.opacity(0.80)
        case .prayer:  Color.black.opacity(0.65)
        case .study:   Color.black.opacity(0.72)
        case .capture: Color.black.opacity(0.60)
        }
    }
}

// MARK: - BereanVoiceView

struct BereanVoiceView: View {
    // Required callbacks
    var onDismiss: (() -> Void)? = nil
    var onTranscriptReady: ((String) -> Void)? = nil

    // Glass impl — default to .lensed for voice (most premium)
    var glassImpl: BereanGlass.Impl = .lensed

    @State private var voiceState: BereanVoiceViewState = .idle
    @State private var voiceMode: BereanVoiceOrbMode = .listen
    @State private var transcript: String = ""
    @State private var isMuted = false
    @State private var showTranscript = false
    @State private var orbPulse = false
    @State private var orbBreath = false
    @State private var appeared = false
    @State private var waveHeights: [CGFloat] = Array(repeating: 4, count: 24)
    @State private var followUpChips: [String] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Waveform timer
    private let waveTimer = Timer.publish(every: 0.07, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background — warm near-white
            Color(red: 0.975, green: 0.972, blue: 0.968)
                .ignoresSafeArea()

            // Ambient glow behind orb
            if !reduceMotion {
                ambientGlow
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                contextStrip
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                Spacer()

                // Central orb
                orbSection

                Spacer()

                // Mode selector
                modePicker
                    .padding(.horizontal, 16)

                // Controls
                controlRow
                    .padding(.top, 20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
            }

            // Transcript overlay
            if showTranscript {
                transcriptPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .bereanGlass(glassImpl)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.55, dampingFraction: 0.80)) {
                appeared = true
            }
            startBreathing()
        }
        .onReceive(waveTimer) { _ in
            guard voiceState == .listening && !isMuted else { return }
            waveHeights = waveHeights.map { _ in CGFloat.random(in: 4...32) }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        BereanTopBar(
            title: "Voice Mode",
            subtitle: "Speak, listen, pause freely",
            leadingContent: AnyView(
                BereanGlassUtilButton(icon: "chevron.down") { onDismiss?() }
                    .bereanGlass(glassImpl)
            ),
            trailingContent: AnyView(
                BereanGlassUtilButton(icon: "text.bubble") { showTranscript.toggle() }
                    .bereanGlass(glassImpl)
            )
        )
        .bereanGlass(glassImpl)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
    }

    // MARK: - Context Strip

    private var contextStrip: some View {
        HStack {
            BereanContextStrip(
                label: voiceMode.contextLabel,
                icon: voiceMode.icon
            )
            .bereanGlass(glassImpl)
            Spacer()

            // State indicator pill
            stateIndicatorPill
        }
        .opacity(appeared ? 1 : 0)
    }

    private var stateIndicatorPill: some View {
        Group {
            switch voiceState {
            case .idle:
                Text("Ready")
            case .listening:
                HStack(spacing: 5) {
                    Circle().fill(Color.black).frame(width: 6, height: 6)
                        .scaleEffect(orbPulse ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: orbPulse)
                    Text("Listening")
                }
            case .processing:
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 5, height: 5)
                            .offset(y: orbPulse ? -3 : 0)
                            .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.12), value: orbPulse)
                    }
                    Text("Thinking")
                }
            case .speaking:
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text("Speaking")
                }
            }
        }
        .font(AMENFont.regular(12))
        .foregroundStyle(.primary.opacity(0.65))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.30)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.40), lineWidth: 0.6))
        )
        .onAppear { orbPulse = true }
    }

    // MARK: - Ambient Glow

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .scaleEffect(orbBreath ? 1.15 : 0.90)
                .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: orbBreath)
                .onAppear { orbBreath = true }

            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: -30, y: -40)
                .scaleEffect(orbBreath ? 0.95 : 1.08)
                .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: orbBreath)
        }
    }

    // MARK: - Orb Section

    private var orbSection: some View {
        VStack(spacing: 28) {
            // Main orb
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 196, height: 196)
                    .scaleEffect(voiceState == .listening ? (orbBreath ? 1.18 : 1.02) : 1.0)
                    .animation(
                        reduceMotion ? .none :
                        voiceState == .listening
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .spring(response: 0.5, dampingFraction: 0.7),
                        value: orbBreath
                    )

                // Glass orb
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.40)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1.0))
                    .frame(width: 160, height: 160)
                    .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                    .scaleEffect(voiceState == .processing ? (orbPulse ? 1.04 : 0.97) : 1.0)
                    .animation(
                        reduceMotion ? .none :
                        voiceState == .processing
                            ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                            : .spring(response: 0.4, dampingFraction: 0.7),
                        value: orbPulse
                    )

                // Inner content
                orbContent
            }
            .scaleEffect(appeared ? 1.0 : 0.82)
            .opacity(appeared ? 1.0 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.72), value: appeared)

            // Waveform strip — only when listening
            if voiceState == .listening {
                waveformStrip
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // State label
            stateLabel
        }
    }

    private var orbContent: some View {
        Group {
            switch voiceState {
            case .idle:
                Image(systemName: voiceMode.icon)
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(voiceMode.orbColor)
            case .listening:
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.primary.opacity(0.82))
                    .symbolEffect(.variableColor.iterative, isActive: true)
            case .processing:
                Image(systemName: "ellipsis")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.primary.opacity(0.65))
            case .speaking:
                Image(systemName: "speaker.wave.3")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(.primary.opacity(0.75))
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: voiceState)
    }

    private var stateLabel: some View {
        VStack(spacing: 6) {
            switch voiceState {
            case .idle:
                Text("Hold to speak or tap mic")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary.opacity(0.70))
            case .listening:
                Text("Listening...")
                    .font(AMENFont.semiBold(18))
                    .foregroundStyle(.primary)
            case .processing:
                Text("Thinking through scripture...")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary.opacity(0.65))
            case .speaking(let text):
                Text(text)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.primary.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: voiceState)
    }

    // MARK: - Waveform Strip

    private var waveformStrip: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.black.opacity(isMuted ? 0.18 : 0.72))
                    .frame(width: 3, height: isMuted ? 4 : waveHeights[i])
                    .animation(.easeInOut(duration: 0.07), value: waveHeights[i])
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.38)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 0.6))
        )
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanVoiceOrbMode.allCases, id: \.self) { mode in
                    BereanModeChip(
                        label: mode.rawValue,
                        icon: mode.icon,
                        isActive: voiceMode == mode
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.78))) {
                            voiceMode = mode
                        }
                        HapticManager.impact(style: .light)
                    }
                    .bereanGlass(glassImpl)
                }
            }
            .padding(.horizontal, 2)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.80).delay(0.12), value: appeared)
    }

    // MARK: - Control Row

    private var controlRow: some View {
        HStack(spacing: 16) {
            // Mute
            voiceControlButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                label: isMuted ? "Muted" : "Mute",
                style: .secondary
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                    isMuted.toggle()
                }
                HapticManager.impact(style: .light)
            }

            // Primary: hold to speak / tap to stop
            voicePrimaryButton

            // Transcript
            voiceControlButton(
                icon: "text.bubble",
                label: "Transcript",
                style: .secondary
            ) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    showTranscript.toggle()
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.80).delay(0.18), value: appeared)
    }

    private var voicePrimaryButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(voiceState == .listening ? Color.black : Color.black.opacity(0.88))
                        .frame(width: 100, height: 52)
                        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)

                    Text(primaryButtonLabel)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)
                }
                Text("speak")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(voiceState == .listening ? 1.04 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.72), value: voiceState)
    }

    private var primaryButtonLabel: String {
        switch voiceState {
        case .idle:       "Hold"
        case .listening:  "Stop"
        case .processing: "Wait"
        case .speaking:   "Pause"
        }
    }

    private func voiceControlButton(
        icon: String,
        label: String,
        style: ControlStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(style == .secondary ? Color.primary.opacity(0.65) : Color.primary)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.42)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75))
                    )
                Text(label)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private enum ControlStyle { case primary, secondary }

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Transcript")
                        .font(AMENFont.semiBold(16))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            showTranscript = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.white.opacity(0.50))))
                    }
                    .buttonStyle(.plain)
                }

                if transcript.isEmpty {
                    Text("Transcript will appear here as you speak.")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                } else {
                    Text(transcript)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }

                // Smart follow-up chips after listening
                if !transcript.isEmpty {
                    BereanSmartFollowUpChips(
                        chips: ["Continue conversation", "Save to notes", "Turn into prayer"],
                        onSelect: { chip in
                            onTranscriptReady?(transcript + "\n" + chip)
                        }
                    )
                    .bereanGlass(glassImpl)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.72), Color.white.opacity(0.44)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.68), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 28, y: -6)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        HapticManager.impact(style: .medium)
        switch voiceState {
        case .idle:
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                voiceState = .listening
            }
        case .listening:
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                voiceState = .processing
            }
            // Simulate processing → speaking
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                    voiceState = .speaking(text: "In Romans 8, Paul grounds assurance not in feelings but in the Spirit's witness and God's unbreakable purpose.")
                }
                followUpChips = ["What does covenant mean?", "Turn this into prayer", "Show cross-references"]
            }
        case .processing:
            break
        case .speaking:
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                voiceState = .idle
            }
        }
    }

    private func startBreathing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
            orbBreath = true
        }
    }
}

// MARK: - BereanWaveformBar (preserved for backward compatibility)

/// Legacy inline waveform bar — shown inside composer during voice recording.
struct BereanWaveformBar: View {
    let isActive: Bool
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 20)
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.65))
                    .frame(width: 3, height: heights[i])
                    .animation(.easeInOut(duration: 0.08), value: heights[i])
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.42)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5))
        )
        .opacity(isActive ? 1 : 0)
        .scaleEffect(isActive ? 1 : 0.92, anchor: .bottom)
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7)), value: isActive)
        .onReceive(timer) { _ in
            guard isActive else { return }
            heights = heights.map { _ in CGFloat.random(in: 4...26) }
        }
    }
}
