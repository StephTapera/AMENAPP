//
//  BereanToolbarExtras.swift
//  AMENAPP
//
//  Extra toolbar buttons for the Berean AI input bar:
//  1. Camera / Photo picker — OCR a Bible verse image
//  2. Microphone — speech-to-verse (standalone, distinct from the main voice button)
//
//  Permissions used:
//   - NSPhotoLibraryUsageDescription (already in Info.plist)
//   - NSMicrophoneUsageDescription   (already in Info.plist)
//   - NSSpeechRecognitionUsageDescription (already in Info.plist)
//

import SwiftUI
import PhotosUI
import Speech
import AVFoundation

// MARK: - BereanCameraChipButton

/// Photo-picker button. When an image is selected, `onImageSelected` is called
/// with the UIImage so the parent can forward it to the AI with the OCR prompt.
struct BereanCameraChipButton: View {

    var onImageSelected: (UIImage) -> Void

    @State private var photosItem: PhotosPickerItem? = nil
    @State private var isLoading = false

    var body: some View {
        PhotosPicker(
            selection: $photosItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            iconPill(
                symbol: "camera.fill",
                accessibilityLabel: "Pick an image to scan for Bible verses",
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        .onChange(of: photosItem) { _, newItem in
            guard let newItem else { return }
            isLoading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        isLoading = false
                        onImageSelected(uiImage)
                    }
                } else {
                    await MainActor.run { isLoading = false }
                }
            }
        }
    }
}

// MARK: - BereanVoiceChipButton

/// Standalone voice-to-verse button that lives in the quick-action chip row area
/// (distinct from the main voice button in the composer). When transcription
/// completes, `onTranscribed` is called with the raw text so the parent can
/// send it with the verse-matching system prompt.
struct BereanVoiceChipButton: View {

    var onTranscribed: (String) -> Void

    @State private var isListening = false
    @State private var permissionDenied = false
    @State private var recognizer: BereanSpeechChipRecognizer? = nil
    @State private var showDeniedAlert = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggleListening()
        } label: {
            iconPill(
                symbol: isListening ? "waveform" : "mic.fill",
                accessibilityLabel: isListening ? "Stop voice input" : "Speak to find a verse",
                isLoading: false,
                isActive: isListening
            )
        }
        .buttonStyle(.plain)
        .alert("Microphone Access Required",
               isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow microphone access in Settings to use voice input.")
        }
    }

    // MARK: - Private

    private func toggleListening() {
        if isListening {
            recognizer?.stop()
            isListening = false
        } else {
            let rec = BereanSpeechChipRecognizer()
            recognizer = rec
            rec.requestAuth { granted in
                if granted {
                    do {
                        try rec.start { transcribed in
                            DispatchQueue.main.async {
                                isListening = false
                                recognizer = nil
                                if !transcribed.isEmpty {
                                    onTranscribed(transcribed)
                                }
                            }
                        }
                        DispatchQueue.main.async { isListening = true }
                    } catch {
                        DispatchQueue.main.async { isListening = false }
                    }
                } else {
                    DispatchQueue.main.async {
                        permissionDenied = true
                        showDeniedAlert = true
                    }
                }
            }
        }
    }
}

// MARK: - Shared Icon Pill

private func iconPill(
    symbol: String,
    accessibilityLabel: String,
    isLoading: Bool,
    isActive: Bool = false
) -> some View {
    ZStack {
        Capsule()
            .fill(isActive
                ? Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.12)
                : Color.white)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive
                            ? Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.35)
                            : Color.black.opacity(0.09),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
            .frame(width: 42, height: 32)

        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.65)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    isActive
                        ? Color(red: 0.88, green: 0.38, blue: 0.28)
                        : Color(white: 0.35)
                )
                .symbolEffect(.variableColor, options: .repeating, isActive: isActive)
        }
    }
    .accessibilityLabel(accessibilityLabel)
}

// MARK: - BereanSpeechChipRecognizer

/// Lightweight, self-contained speech recognizer used only by BereanVoiceChipButton.
/// Uses SFSpeechRecognizer with a 6-second auto-stop timer.
final class BereanSpeechChipRecognizer: NSObject {

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var onComplete: ((String) -> Void)?
    private var lastPartialTranscription: String = ""

    func requestAuth(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start(onComplete: @escaping (String) -> Void) throws {
        self.onComplete = onComplete
        speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw NSError(domain: "BereanSpeech", code: 1) }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                self?.lastPartialTranscription = result.bestTranscription.formattedString
                if result.isFinal {
                    self?.finish(text: result.bestTranscription.formattedString)
                }
            }
            if error != nil {
                self?.finish(text: self?.lastPartialTranscription ?? "")
            }
        }

        // Auto-stop after 8 seconds
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        let partial = lastPartialTranscription
        finish(text: partial)
    }

    private func finish(text: String) {
        silenceTimer?.invalidate()
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        let callback = onComplete
        onComplete = nil
        DispatchQueue.main.async { callback?(text) }
    }
}

// MARK: - OCR System Prompt Constant

enum BereanToolbarPrompts {
    static let imageOCR = """
    Extract any Bible verse text from this image. \
    Return the full verse text, its reference (book, chapter, and verse), \
    cross-references if visible, and a brief commentary on its meaning. \
    If no Bible verse is found, respond graciously and describe what you see.
    """

    static func voiceVerseMatch(_ spokenText: String) -> String {
        """
        A user spoke the following text aloud: "\(spokenText)"

        Find the closest matching Bible verse to this spoken text. \
        Provide the full verse text, its reference (book chapter:verse), \
        a brief note on why this verse matches, \
        and offer a short devotional commentary.
        """
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Toolbar Extras") {
    HStack(spacing: 12) {
        BereanCameraChipButton { image in
            print("Image selected: \(image.size)")
        }
        BereanVoiceChipButton { text in
            print("Transcribed: \(text)")
        }
    }
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
#endif
