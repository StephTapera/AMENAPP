//
//  StudioVoiceRecorderView.swift
//  AMENAPP
//
//  AVAudioRecorder → Firebase Storage → transcribeAudio Cloud Function.
//  Usage: embed StudioVoiceButton in any compose view.
//  The button cycles through idle → recording → uploading → transcribing,
//  then fires onTranscript(_ text: String) and resets.
//

import AVFoundation
import Combine
import FirebaseFunctions
import FirebaseStorage
import SwiftUI

// MARK: - View Model

@MainActor
final class StudioVoiceRecorderViewModel: ObservableObject {
    enum RecorderState { case idle, recording, uploading, transcribing }

    @Published var state: RecorderState = .idle
    @Published var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var tempURL: URL?
    private let functions = Functions.functions(region: "us-central1")

    // MARK: - Public API

    func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in
                    self.errorMessage = "Microphone access is required to record audio."
                }
                return
            }
            Task { @MainActor in self.beginRecording() }
        }
    }

    func stopAndTranscribe(uid: String, onTranscript: @escaping (String) -> Void) {
        audioRecorder?.stop()
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = tempURL else { return }
        state = .uploading
        Task { await upload(localURL: url, uid: uid, onTranscript: onTranscript) }
    }

    func reset() {
        audioRecorder?.stop()
        audioRecorder = nil
        state = .idle
        errorMessage = nil
    }

    // MARK: - Private

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        tempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            state = .recording
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    private func upload(localURL: URL, uid: String, onTranscript: @escaping (String) -> Void) async {
        do {
            let storagePath = "studioVoice/\(uid)/\(Int(Date().timeIntervalSince1970)).m4a"
            let ref = Storage.storage().reference().child(storagePath)
            let audioData = try Data(contentsOf: localURL)
            let meta = StorageMetadata()
            meta.contentType = "audio/m4a"
            _ = try await ref.putDataAsync(audioData, metadata: meta)
            try? FileManager.default.removeItem(at: localURL)

            state = .transcribing
            let result = try await functions
                .httpsCallable("transcribeAudio")
                .safeCall(["storagePath": storagePath])

            if let data = result.data as? [String: Any],
               let text = data["text"] as? String, !text.isEmpty {
                onTranscript(text)
            } else {
                errorMessage = "Could not read the transcript. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        state = .idle
    }
}

// MARK: - Voice Button

struct StudioVoiceButton: View {
    let uid: String
    let accentColor: Color
    let onTranscript: (String) -> Void

    @StateObject private var vm = StudioVoiceRecorderViewModel()

    var body: some View {
        Button {
            switch vm.state {
            case .idle:
                vm.startRecording()
            case .recording:
                vm.stopAndTranscribe(uid: uid, onTranscript: onTranscript)
            default:
                break
            }
        } label: {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 36, height: 36)

                if vm.state == .uploading || vm.state == .transcribing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: vm.state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(vm.state == .uploading || vm.state == .transcribing)
        .overlay(alignment: .bottom) {
            if vm.state == .recording {
                Text("Stop")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(y: 18)
            }
        }
        .alert("Transcription Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var buttonFill: Color {
        switch vm.state {
        case .idle: return accentColor
        case .recording: return .red
        case .uploading, .transcribing: return Color(.secondaryLabel)
        }
    }
}
