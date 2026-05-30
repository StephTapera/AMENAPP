// BereanSelahModeView.swift
// AMEN App — Context-Aware Voice Bible Companion (Agent 5)
//
// Selah / Quiet Mode — Berean listens, transcribes, and holds space.
// It does NOT respond. This is a witness-only mode for prayer
// that isn't a conversation.
// Transcript is held on-device; user can save or discard at the end.

import SwiftUI

// MARK: - Selah Session State

private enum SelahPhase {
    case ready
    case listening
    case finished(transcript: String)
}

// MARK: - Main View

struct BereanSelahModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onSaveToJournal: ((String) -> Void)?

    @StateObject private var engine = VoicePrayerAudioEngine()
    @StateObject private var transcription = BereanTranscriptionService.shared

    @State private var phase: SelahPhase = .ready
    @State private var transcript = ""
    @State private var showSaveConfirm = false
    @State private var pulseAnimation = false

    var body: some View {
        guard AMENFeatureFlags.shared.bereanSelahModeEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(NavigationStack {
            ZStack {
                // Deep navy background for contemplative feel
                Color(red: 0.05, green: 0.07, blue: 0.18).ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()

                    switch phase {
                    case .ready:
                        readyView
                    case .listening:
                        listeningView
                    case .finished(let t):
                        finishedView(transcript: t)
                    }

                    Spacer()
                }
            }
        }
        .onDisappear {
            engine.cancelRecording()
        })
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                engine.cancelRecording()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .accessibilityLabel("Close Selah mode")

            Spacer()

            // Selah label
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 13))
                Text("Selah")
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundStyle(.white.opacity(0.85))

            Spacer()
            Spacer().frame(width: 36)  // balance
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Ready Phase

    private var readyView: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text("Selah")
                    .font(.custom("OpenSans-Bold", size: 36))
                    .foregroundStyle(.white)

                Text("A space for prayer that doesn't need a reply.\nBerean listens and holds space with you.")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            // Begin button
            Button {
                Task { await beginListening() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                    Text("Begin")
                }
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(Color(red: 0.05, green: 0.07, blue: 0.18))
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Listening Phase

    private var listeningView: some View {
        VStack(spacing: 40) {
            // Breathing pulse indicator
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(.white.opacity(0.15 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: 80 + CGFloat(i * 36), height: 80 + CGFloat(i * 36))
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(
                            reduceMotion ? nil
                                : Animation.easeInOut(duration: 2.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.4),
                            value: pulseAnimation
                        )
                }

                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 160, height: 160)
            .onAppear { pulseAnimation = true }
            .onDisappear { pulseAnimation = false }

            VStack(spacing: 8) {
                Text("Listening…")
                    .font(.custom("OpenSans-Regular", size: 18))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Berean will not respond. This is your space.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Stop button
            Button {
                Task { await stopListening() }
            } label: {
                Text("Finish")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(.white.opacity(reduceTransparency ? 0.2 : 0.12))
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Finished Phase

    private func finishedView(transcript: String) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Your prayer was heard.")
                    .font(.custom("OpenSans-Regular", size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if !transcript.isEmpty {
                // Show transcript in a quiet card
                ScrollView {
                    Text(transcript)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )
                        .padding(.horizontal, 20)
                }
                .frame(maxHeight: 200)
            }

            // Actions
            VStack(spacing: 12) {
                if let onSave = onSaveToJournal, !transcript.isEmpty {
                    Button {
                        showSaveConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed.fill")
                            Text("Save to Journal")
                        }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(Color(red: 0.05, green: 0.07, blue: 0.18))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 13)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Save to Journal?", isPresented: $showSaveConfirm) {
                        Button("Save") {
                            onSave(transcript)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Your prayer transcript will be saved privately to your journal.")
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func beginListening() async {
        phase = .listening
        await engine.requestPermissionAndStart()
    }

    private func stopListening() async {
        engine.stopRecording()

        // Transcribe locally for the user — Selah transcripts stay on-device
        // unless the user explicitly saves to journal
        if let url = engine.recordedFileURL {
            do {
                let t = try await BereanTranscriptionService.shared.transcribe(audioURL: url)
                transcript = t.text
            } catch {
                transcript = ""
            }
        }

        phase = .finished(transcript: transcript)
    }
}
