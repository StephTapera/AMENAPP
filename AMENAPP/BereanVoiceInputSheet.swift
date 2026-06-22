//
//  BereanVoiceInputSheet.swift
//  AMENAPP
//
//  Phase 5 / P0-2: real Berean voice input.
//
//  This replaces the dlog-only `handleVoiceAction` stub in BereanChatView.
//  It reuses the existing WhisperVoiceViewModel (AVAudioRecorder + Whisper
//  via the secured `whisperProxy` callable) for recording and transcription,
//  and presents a three-state UI:
//
//    1. Consent banner (first use only)
//    2. Recording state — elapsed timer, Stop / Cancel
//    3. Transcript preview — editable text + Send / Re-record / Discard
//
//  Privacy invariants:
//    - The raw audio file lives in a temp location managed by
//      WhisperVoiceService and is deleted immediately after transcription.
//    - No analytics event in this file logs the transcript text or audio
//      file URL — only durations, character counts, and error classes.
//    - The transcript is NEVER auto-sent. The user must explicitly tap
//      "Send to Berean" after reviewing.
//
//  Backend contract used:
//    - whisperProxy onCall  (Auth + App Check, see Backend/functions/src/
//      whisperProxy.ts and functions/openAIFunctions.js:30 — both now
//      require enforceAppCheck: true).
//

import SwiftUI

struct BereanVoiceInputSheet: View {
    /// Called when the user accepts a transcript and wants to send it to
    /// Berean. The host should set `vm.inputText = transcript` and call
    /// the normal send path.
    let onAccept: (_ transcript: String) -> Void
    /// Called when the user dismisses without sending.
    let onCancel: () -> Void

    @StateObject private var voiceVM = WhisperVoiceViewModel()
    @State private var editedTranscript: String = ""
    @State private var recordingStartedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let elapsedTimer = Timer.publish(every: 0.2, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if voiceVM.showConsentBanner {
                    consentBanner
                } else if voiceVM.isRecording {
                    recordingState
                } else if voiceVM.isTranscribing {
                    transcribingState
                } else if !editedTranscript.isEmpty || !voiceVM.transcript.isEmpty {
                    transcriptPreview
                } else if let error = voiceVM.error {
                    errorState(error)
                } else {
                    idleState
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Voice input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task {
                            if voiceVM.isRecording {
                                await voiceVM.cancelRecording()
                            }
                            onCancel()
                            dismiss()
                        }
                    }
                }
            }
            .onReceive(elapsedTimer) { _ in
                guard voiceVM.isRecording, let started = recordingStartedAt else {
                    elapsed = 0
                    return
                }
                elapsed = Date().timeIntervalSince(started)
            }
            .onChange(of: voiceVM.transcript) { _, newValue in
                if !newValue.isEmpty, editedTranscript.isEmpty {
                    editedTranscript = newValue
                }
            }
            .onAppear {
                // Auto-start: present sheet → immediately begin recording
                // (or surface consent on first use).
                Task { await voiceVM.startRecording() }
            }
        }
    }

    // MARK: - States

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.systemScaled(56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Tap to start recording")
                .font(.headline)
            Button {
                Task { await voiceVM.startRecording() }
            } label: {
                Label("Start recording", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Start recording")
        }
    }

    private var recordingState: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.systemScaled(56, weight: .regular))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: voiceVM.isRecording)
            Text(formattedElapsed)
                .font(.systemScaled(32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Recording, \(Int(elapsed)) seconds")
            Text("Listening…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await voiceVM.stopAndTranscribe() }
            } label: {
                Label("Stop and transcribe", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Stop recording and transcribe")
        }
        .onAppear { recordingStartedAt = Date() }
    }

    private var transcribingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Transcribing…")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review and edit")
                .font(.headline)
            Text("Berean will receive exactly what you send. Edit if needed.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedTranscript)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .accessibilityLabel("Transcript editor")

            if voiceVM.needsReRecord {
                Label("Audio was hard to hear. Consider re-recording.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    Task {
                        await voiceVM.cancelRecording()
                        editedTranscript = ""
                        voiceVM.transcript = ""
                        onCancel()
                        dismiss()
                    }
                } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        editedTranscript = ""
                        voiceVM.transcript = ""
                        voiceVM.needsReRecord = false
                        await voiceVM.startRecording()
                    }
                } label: {
                    Text("Re-record")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                let final = editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }
                onAccept(final)
                dismiss()
            } label: {
                Label("Send to Berean", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send transcript to Berean")
        }
    }

    private var consentBanner: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.systemScaled(44))
                .foregroundStyle(Color.accentColor)
            Text("Voice input uses your microphone")
                .font(.headline)
            Text("Your audio is sent to a transcription service to produce text, then deleted. You'll be able to review and edit the transcript before it goes to Berean.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Not now") {
                    voiceVM.declineConsent()
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Allow") {
                    Task { await voiceVM.acceptConsent() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func errorState(_ error: WhisperError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(44))
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Voice input failed.")
                .font(.headline)
                .multilineTextAlignment(.center)
            if case .micPermissionDenied = error {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Try again") {
                    Task {
                        voiceVM.error = nil
                        await voiceVM.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
