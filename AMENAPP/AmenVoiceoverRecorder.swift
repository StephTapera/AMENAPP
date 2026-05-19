// AmenVoiceoverRecorder.swift
// AMENAPP
// Simple voiceover recorder for media attachments.

import SwiftUI
import AVFoundation

struct AmenVoiceoverRecorder: View {
    let onSave: (URL?) -> Void

    @State private var isRecording = false
    @State private var recorder: AVAudioRecorder? = nil
    @State private var lastRecordingURL: URL? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text("Voiceover")
                .font(.systemScaled(18, weight: .bold))

            Button(isRecording ? "Stop Recording" : "Start Recording") {
                isRecording ? stopRecording() : startRecording()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            if let url = lastRecordingURL {
                Text(url.lastPathComponent)
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Button("Use Voiceover") {
                onSave(lastRecordingURL)
            }
            .disabled(lastRecordingURL == nil)
            .accessibilityLabel("Use voiceover")
        }
        .padding(24)
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("amen_voiceover_\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            isRecording = true
            lastRecordingURL = url
        } catch {
            dlog("[AmenVoiceoverRecorder] Failed to start recording: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }
}
