// BereanListeningView.swift
// AMEN — Berean Reading Surface: Listening / Voice Mode (W3)
// Flag: bereanListening (default false)
//
// SAFETY INVARIANTS:
// - Mic consent gate is MANDATORY before any capture. No orb until consent granted.
// - Transcript is UGC → routes through Guard before any save or share (TODO marked).
// - This is an in-app study assistant only. No external telephony.
// - COPPA: inherits existing age-gate posture from GUARDIAN/Aegis.

import SwiftUI
import AVFoundation

struct BereanListeningView: View {

    @State private var hasMicConsent: Bool = false
    @State private var isCheckingPermission: Bool = true
    @State private var isRecording: Bool = false
    @State private var isPaused: Bool = false
    @State private var orbState: BereanOrbState = .idle
    @State private var transcript: [BereanTranscriptTurn] = []
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showConvertMenu: Bool = false

    var body: some View {
        ZStack {
            Color.bereanIvory.ignoresSafeArea()

            if isCheckingPermission {
                WordGlowLoader()
            } else if !hasMicConsent {
                consentView
            } else if let err = errorMessage {
                errorView(err)
            } else {
                sessionView
            }
        }
        .task { await checkPermission() }
    }

    // MARK: - Consent Gate

    private var consentView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "mic.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.bereanInk.opacity(0.45))

            VStack(spacing: 10) {
                Text("Listening Mode")
                    .font(BereanReaderType.displayTitle)
                    .foregroundStyle(Color.bereanInk)
                Text("Berean can listen to a sermon or discussion and help you study it — answering questions, citing scripture, and building study materials.")
                    .font(BereanType.body())
                    .foregroundStyle(Color.bereanInk.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await requestPermission() }
            } label: {
                Label("Allow Microphone", systemImage: "mic.fill")
                    .font(BereanType.subheadline())
                    .foregroundStyle(Color.bereanIvory)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.bereanInk)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Allow microphone access for Berean listening")

            Text("Your audio is processed on-device and is never stored without your explicit confirmation.")
                .font(BereanType.caption())
                .foregroundStyle(Color.bereanInk.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Session View

    private var sessionView: some View {
        VStack(spacing: 0) {
            // Orb
            VStack(spacing: 16) {
                Spacer()
                VoiceOrb(state: orbState)
                    .onTapGesture { toggleRecording() }

                Text(sessionStatusText)
                    .font(BereanType.body())
                    .foregroundStyle(Color.bereanInk.opacity(0.55))
                    .animation(.easeInOut(duration: 0.2), value: orbState)
                Spacer()
            }
            .frame(maxHeight: 260)

            // Transcript
            if !transcript.isEmpty {
                transcriptList
            } else if isRecording {
                Text("Listening…")
                    .font(BereanType.body())
                    .foregroundStyle(Color.bereanInk.opacity(0.4))
                    .padding(.top, 8)
            }

            Spacer()

            // Controls
            sessionControls
        }
        .padding(.bottom, 24)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript) { turn in
                        transcriptBubble(turn)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: transcript.count) { _, _ in
                if let last = transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: 300)
    }

    @ViewBuilder
    private func transcriptBubble(_ turn: BereanTranscriptTurn) -> some View {
        VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                if turn.speaker == .berean {
                    Circle()
                        .fill(Color.bereanWine.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
                Text(turn.text)
                    .font(turn.speaker == .berean ? BereanReaderType.body : BereanType.body())
                    .foregroundStyle(Color.bereanInk)
                    .multilineTextAlignment(turn.speaker == .user ? .trailing : .leading)
            }
            if let ref = turn.scriptureReference {
                Text(ref)
                    .font(BereanType.caption())
                    .foregroundStyle(Color.bereanWine.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.speaker == .user ? .trailing : .leading)
        .padding(.horizontal, 4)
        .accessibilityLabel("\(turn.speaker == .berean ? "Berean" : "You"): \(turn.text)")
    }

    private var sessionControls: some View {
        BereanActionToolbar(items: [
            BereanToolbarItem(id: "toggle", icon: isRecording ? "pause.fill" : "mic.fill",
                              label: isRecording ? "Pause" : "Start", action: toggleRecording),
            BereanToolbarItem(id: "save", icon: "note.text.badge.plus",
                              label: "Save", action: saveToNotes),
            BereanToolbarItem(id: "convert", icon: "arrow.triangle.2.circlepath",
                              label: "Convert", action: { showConvertMenu = true }),
            BereanToolbarItem(id: "end", icon: "stop.circle",
                              label: "End", action: endSession),
        ])
        .padding(.horizontal, 16)
        .confirmationDialog("Convert transcript to…", isPresented: $showConvertMenu) {
            Button("Prayer") { convertTranscript(to: .turnIntoPrayer) }
            Button("Study Plan") { convertTranscript(to: .studyPlan) }
            Button("Summary") { convertTranscript(to: .summarize) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sessionStatusText: String {
        switch orbState {
        case .idle:        return isRecording ? "Paused" : "Tap to start listening"
        case .listening:   return "Listening…"
        case .discerning:  return "Berean is checking context…"
        case .praying:     return "Berean is entering prayer mode…"
        case .summarizing: return "Building study materials…"
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.bereanWine.opacity(0.7))
            Text(message)
                .font(BereanType.body())
                .foregroundStyle(Color.bereanInk.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { errorMessage = nil }
                .font(BereanType.subheadline())
                .foregroundStyle(Color.bereanInk)
            Spacer()
        }
    }

    // MARK: - Actions

    private func checkPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        await MainActor.run {
            hasMicConsent = status == AVAudioApplication.recordPermission.granted
            isCheckingPermission = false
        }
    }

    private func requestPermission() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        await MainActor.run { hasMicConsent = granted }
    }

    private func toggleRecording() {
        if isRecording {
            isRecording = false
            orbState = .idle
        } else {
            isRecording = true
            orbState = .listening
            // TODO: Start AVAudioEngine capture
        }
    }

    private func saveToNotes() {
        // TODO: UGC SAFETY — transcript must route through GUARDIAN/Aegis Guard mode
        //       before any save. Do not save raw transcript without Guard clearance.
        print("Save transcript to notes — Guard routing required")
    }

    private func convertTranscript(to action: BereanAIAction) {
        orbState = .summarizing
        // TODO: Route through BereanContextActionEngine.perform(action: action, payload: transcript data)
        //       UGC: transcript passes through Guard before Build/Reflect mode call
        print("Convert transcript via \(action.routesTo.rawValue) mode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            orbState = .idle
        }
    }

    private func endSession() {
        isRecording = false
        orbState = .idle
        // TODO: Finalize session, offer save/convert options
    }
}

#Preview {
    BereanListeningView()
}
