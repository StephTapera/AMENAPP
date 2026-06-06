// BereanVoiceSession.swift
// AMEN App — Berean voice input session.
//
// Design reference: ChatGPT voice mode (IMG_2394) — blue waveform orb, Liquid Glass overlay.
// Architecture:
//   - Full-screen sheet with frosted glass backdrop
//   - BereanVoiceEngine: @MainActor ObservableObject managing SFSpeechRecognizer + AVAudioEngine
//   - Auto-stops after 2.5 s of silence; Done / Cancel buttons
//   - Permission denied → friendly explanation state (never crashes)
//   - Calls back via onText(_ String) when transcript is confirmed

import SwiftUI
import Speech
import AVFoundation

// MARK: - BereanVoiceSession

struct BereanVoiceSessionView: View {

    @Binding var isPresented: Bool
    let onText: (String) -> Void

    @StateObject private var engine = BereanVoiceEngine()
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        ZStack {
            // Frosted backdrop — solid when reduceTransparency is on (a11y), material otherwise
            if reduceTransparency {
                Color.black.opacity(0.85).ignoresSafeArea()
            } else {
                Color.black.opacity(0.50).background(.ultraThinMaterial).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer()

                voiceOrb
                    .scaleEffect(appeared ? 1.0 : 0.72)
                    .opacity(appeared ? 1.0 : 0)

                transcriptArea
                    .padding(.top, 36)

                Spacer()

                bottomRow
                    .padding(.bottom, 52)
                    .opacity(appeared ? 1.0 : 0)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.44, dampingFraction: 0.74)) {
                appeared = true
            }
            engine.requestPermissionAndStart()
        }
        .onDisappear {
            engine.stop()
        }
        .onChange(of: engine.sessionFinished) { _, finished in
            guard finished else { return }
            let text = engine.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { onText(text) }
            isPresented = false
        }
    }

    // MARK: - Voice orb

    private var voiceOrb: some View {
        ZStack {
            // Outer pulse ring — only while listening
            if engine.state == .listening && !reduceMotion {
                Circle()
                    .fill(Color(red: 0.20, green: 0.48, blue: 1.00).opacity(0.18))
                    .frame(width: 148, height: 148)
                    .scaleEffect(engine.pulseScale)
                    .animation(
                        .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                        value: engine.pulseScale
                    )

                Circle()
                    .fill(Color(red: 0.20, green: 0.48, blue: 1.00).opacity(0.09))
                    .frame(width: 178, height: 178)
                    .scaleEffect(engine.pulseScale * 0.92)
                    .animation(
                        .easeInOut(duration: 1.55).repeatForever(autoreverses: true),
                        value: engine.pulseScale
                    )
            }

            // Core orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.58, blue: 1.00),
                            Color(red: 0.16, green: 0.36, blue: 0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .shadow(
                    color: Color(red: 0.20, green: 0.48, blue: 1.00).opacity(0.42),
                    radius: 28,
                    y: 8
                )
                .overlay(
                    // Specular glare
                    Ellipse()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 46, height: 20)
                        .blur(radius: 6)
                        .offset(x: -8, y: -26)
                )

            // Waveform / mic icon
            Group {
                switch engine.state {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .medium))
                case .listening:
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .medium))
                case .processing:
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.2), value: engine.state)
        }
    }

    // MARK: - Status + live transcript

    private var transcriptArea: some View {
        VStack(spacing: 14) {
            // Status label
            Text(engine.statusLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.70))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: engine.statusLabel)

            // Live transcript — appears as words come in
            if !engine.transcript.isEmpty {
                Text(engine.transcript)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            // Permission denied helper link
            if case .error(let msg) = engine.state, msg.contains("denied") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.48, green: 0.72, blue: 1.00))
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: engine.transcript)
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: 44) {
            // Cancel
            Button {
                engine.stop()
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.80))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel voice input")

            // Done — visible once transcript is non-empty
            if !engine.transcript.isEmpty {
                Button {
                    let text = engine.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    engine.stop()
                    if !text.isEmpty { onText(text) }
                    isPresented = false
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.20, green: 0.48, blue: 1.00))
                                .shadow(
                                    color: Color(red: 0.20, green: 0.48, blue: 1.00).opacity(0.40),
                                    radius: 12,
                                    y: 3
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use transcribed text")
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.76), value: engine.transcript.isEmpty)
    }
}

// MARK: - BereanVoiceEngine

@MainActor
final class BereanVoiceEngine: ObservableObject {

    // MARK: - State machine

    enum RecordingState: Equatable {
        case idle
        case listening
        case processing
        case error(String)

        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.listening, .listening), (.processing, .processing): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var pulseScale: CGFloat = 1.0
    @Published private(set) var sessionFinished = false

    var statusLabel: String {
        switch state {
        case .idle:           return "Tap the orb to start"
        case .listening:      return "Listening…"
        case .processing:     return "Processing…"
        case .error(let msg): return msg
        }
    }

    // MARK: - Private AVFoundation / Speech

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    // MARK: - Permission + start

    func requestPermissionAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.startListening()
                case .denied:
                    self.state = .error("Microphone access denied. Open Settings to enable.")
                case .restricted:
                    self.state = .error("Speech recognition is restricted on this device.")
                default:
                    self.state = .error("Speech recognition unavailable.")
                }
            }
        }
    }

    // MARK: - Start listening

    private func startListening() {
        let rec = SFSpeechRecognizer(locale: .current)
        guard rec?.isAvailable == true else {
            state = .error("Speech recognition unavailable on this device.")
            return
        }
        recognizer = rec

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        audioRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Could not activate audio session.")
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.audioRequest?.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            state = .error("Could not start audio engine.")
            return
        }

        state = .listening
        pulseScale = 1.14

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }
                if let error {
                    // Ignore cancellation errors (user-initiated stop)
                    let nsErr = error as NSError
                    let isCancelled = nsErr.code == 301 || nsErr.domain == "kAFAssistantErrorDomain"
                    if !isCancelled {
                        self.state = .error("Recognition error. Try again.")
                    }
                    self.cleanupAudio()
                } else if result?.isFinal == true {
                    self.finalize()
                }
            }
        }
    }

    // MARK: - Stop / finalize

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        audioRequest?.endAudio()
        cleanupAudio()
        state = .idle
    }

    private func finalize() {
        silenceTimer?.invalidate()
        state = .processing
        recognitionTask?.cancel()
        audioRequest?.endAudio()
        cleanupAudio()
        // Brief processing flash before dismissing
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            sessionFinished = true
        }
    }

    private func cleanupAudio() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finalize()
            }
        }
    }
}
