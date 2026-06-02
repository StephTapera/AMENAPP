// AmenAssistantBarCoordinator.swift
// Spiritual OS — Agent G: Berean Assistant Bar
//
// Owns all state for the global assistant bar overlay.
// Injected at ContentView level; tab bar remains fully accessible beneath it.
//
// Feature gate: AppStorage key "spiritualOS_assistant_bar_enabled" (default OFF).
// All @Published mutations happen on @MainActor.

import SwiftUI
import Firebase
import FirebaseFunctions
import Foundation
import PhotosUI
import Vision
import Speech
import AVFoundation

// MARK: - AssistantResponse

/// Structured response returned by the `getAssistantResponse` callable.
struct AssistantResponse: Equatable {
    /// The main answer text to display to the user.
    let answer: String
    /// Scripture or community sources supporting the answer.
    let sources: [AssistantSource]
    /// Suggested follow-up prompts shown beneath the response card.
    let suggestedFollowUps: [String]
    /// Short AI disclosure label, e.g. "Berean AI · powered by Anthropic".
    let aiDisclosureLabel: String
}

// MARK: - AssistantSource

/// A single sourced reference within an AssistantResponse.
struct AssistantSource: Equatable {
    /// Category of source: "scripture", "commentary", "community", etc.
    let type: String
    /// Machine-readable reference, e.g. "Romans 8:28".
    let ref: String
    /// Human-readable title.
    let title: String
    /// Optional short excerpt surfaced as a chip tooltip.
    let snippet: String?
}

// MARK: - AmenAssistantBarCoordinator

@MainActor
final class AmenAssistantBarCoordinator: ObservableObject {

    // MARK: Published state

    @Published var isExpanded: Bool = false
    @Published var currentSurface: SOSurface = .assistantBar
    /// Set when a deep link arrives carrying a pre-populated query string.
    @Published var pendingQuery: String? = nil
    /// True when the Context Engine reports the user is in drive/hands-free mode.
    @Published var isVoiceMode: Bool = false
    @Published var showingCamera: Bool = false
    @Published var showingVoice: Bool = false
    @Published var lastResponse: AssistantResponse? = nil
    /// Surfaced to the UI so a spinner or error badge can be shown.
    @Published var isLoading: Bool = false
    @Published var lastError: String? = nil

    // MARK: Identity

    let userId: String

    // MARK: Private

    private let functions = Functions.functions()

    // MARK: Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Actions

    /// Submits a free-text or quick-prompt query to the `getAssistantResponse` callable.
    func submit(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        lastError = nil

        let payload: [String: Any] = [
            "userId": userId,
            "query": trimmed,
            "queryType": "text",
            "surfaceContext": currentSurface.rawValue
        ]

        do {
            let callable = functions.httpsCallable("getAssistantResponse")
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any] else {
                lastError = "Unexpected response format."
                isLoading = false
                return
            }

            let answer = data["answer"] as? String ?? ""
            let disclosureLabel = data["aiDisclosureLabel"] as? String ?? "Berean AI"
            let followUps = data["suggestedFollowUps"] as? [String] ?? []

            var sources: [AssistantSource] = []
            if let rawSources = data["sources"] as? [[String: Any]] {
                sources = rawSources.compactMap { raw in
                    guard
                        let type = raw["type"] as? String,
                        let ref  = raw["ref"]  as? String,
                        let title = raw["title"] as? String
                    else { return nil }
                    return AssistantSource(
                        type: type,
                        ref: ref,
                        title: title,
                        snippet: raw["snippet"] as? String
                    )
                }
            }

            lastResponse = AssistantResponse(
                answer: answer,
                sources: sources,
                suggestedFollowUps: followUps,
                aiDisclosureLabel: disclosureLabel
            )
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Opens the camera OCR sheet for verse / scripture detection.
    func openCamera() {
        showingCamera = true
    }

    /// Opens the voice input sheet (drive mode / hands-free).
    func openVoice() {
        showingVoice = true
    }

    /// Called by camera OCR or voice input sheets with recognized text to submit.
    func receiveDetectedText(_ text: String) async {
        showingCamera = false
        showingVoice = false
        await submit(query: text)
    }

    /// Updates the active surface so quick prompts and context stay in sync.
    func setSurface(_ surface: SOSurface) {
        currentSurface = surface
    }

    /// Dismisses the last response card.
    func dismissResponse() {
        lastResponse = nil
    }

    // MARK: - Quick Prompts

    /// Returns 3 surface-appropriate quick prompt strings shown above the bar.
    func quickPromptsForSurface(_ surface: SOSurface) -> [String] {
        switch surface {
        case .dailyDigest:
            return [
                "What does today's verse mean?",
                "Show me a prayer for today",
                "What's on my schedule?"
            ]
        case .unifiedHub:
            return [
                "Summarize my messages",
                "Who needs prayer today?",
                "Help me respond"
            ]
        case .lifePlanner:
            return [
                "What should I prioritize today?",
                "Suggest a scripture for tonight",
                "Help me plan tomorrow"
            ]
        case .spaceDashboard:
            return [
                "What's happening in this space?",
                "Suggest a devotional for our group",
                "Help us pray together"
            ]
        case .commandCenter:
            return [
                "How am I growing in faith?",
                "Suggest my next step",
                "What should I focus on this week?"
            ]
        default:
            return [
                "Ask about scripture",
                "Help me pray",
                "Find a community"
            ]
        }
    }
}

// MARK: - AmenAssistantBarOverlay

/// Drop-in overlay injected at ContentView level.
/// Renders above all content; the tab bar beneath remains tappable.
struct AmenAssistantBarOverlay: View {

    @ObservedObject var coordinator: AmenAssistantBarCoordinator

    @AppStorage("spiritualOS_assistant_bar_enabled") private var isEnabled = false

    var body: some View {
        if !isEnabled {
            EmptyView()
        } else {
            overlayContent
        }
    }

    // MARK: - Overlay content

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Response card sits above the bar when a response is present.
            if let response = coordinator.lastResponse {
                responseCard(response)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if coordinator.isVoiceMode {
                // Drive / hands-free mode: only show the mic chip.
                voiceModeButton
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                // Normal mode: full assistant bar.
                VStack(spacing: 0) {
                    AssistantBar(
                        placeholder: "Ask Berean\u{2026}",
                        contextSurface: coordinator.currentSurface,
                        onSubmit: { query in
                            Task { await coordinator.submit(query: query) }
                        },
                        onCamera: { coordinator.openCamera() },
                        onVoice:  { coordinator.openVoice()  },
                        quickPrompts: coordinator.quickPromptsForSurface(coordinator.currentSurface)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: coordinator.lastResponse != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: coordinator.isVoiceMode)
        .sheet(isPresented: $coordinator.showingCamera) {
            CameraOCRSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.showingVoice) {
            VoiceInputSheet(coordinator: coordinator)
        }
    }

    // MARK: - Voice-mode mic button

    private var voiceModeButton: some View {
        HStack {
            Spacer()
            GlassChip(
                label: "Mic",
                icon: "mic.fill",
                tint: .amenPurple,
                size: .regular,
                isActive: true,
                action: { coordinator.openVoice() }
            )
            .accessibilityLabel("Voice input — tap to speak")
            Spacer()
        }
    }

    // MARK: - Response card

    @ViewBuilder
    private func responseCard(_ response: AssistantResponse) -> some View {
        GlassCard(tint: .amenPurple.opacity(0.08), elevated: true) {
            VStack(alignment: .leading, spacing: 10) {

                // Answer body on matte amenCream background
                Text(response.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.amenBlack)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Source chips (max 3)
                if !response.sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(response.sources.prefix(3).enumerated()), id: \.offset) { _, source in
                                GlassChip(
                                    label: source.title,
                                    icon: source.type == "scripture" ? "book.closed" : "person.2",
                                    tint: .amenGold,
                                    size: .compact,
                                    isActive: true
                                )
                                .accessibilityLabel(source.ref)
                            }
                        }
                    }
                }

                // Follow-up prompts
                if !response.suggestedFollowUps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(response.suggestedFollowUps.prefix(3), id: \.self) { followUp in
                            Button {
                                Task { await coordinator.submit(query: followUp) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.amenPurple)
                                    Text(followUp)
                                        .font(.caption.italic())
                                        .foregroundStyle(Color.amenSlate)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.amenSlate.opacity(0.45))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.amenPurple.opacity(0.06))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.amenPurple.opacity(0.14), lineWidth: 0.5)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Follow up: \(followUp)")
                        }
                    }
                }

                // Divider + disclosure + dismiss row
                Divider()
                    .overlay(Color.amenPurple.opacity(0.12))

                HStack(alignment: .center, spacing: 0) {
                    Text(response.aiDisclosureLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.amenSlate)

                    Spacer()

                    GlassChip(
                        label: "Dismiss",
                        icon: "xmark",
                        tint: .amenSlate,
                        size: .compact,
                        action: { coordinator.dismissResponse() }
                    )
                    .accessibilityLabel("Dismiss Berean response")
                }
            }
            .padding(14)
            .background(Color.amenCream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Camera OCR Sheet

/// Presents a photo picker and runs Vision text recognition to extract scripture text.
struct CameraOCRSheet: View {
    @ObservedObject var coordinator: AmenAssistantBarCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var detectedText = ""
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.amenPurple)
                    Text("Verse Lens")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.amenBlack)
                    Text("Select a photo containing a Bible verse. AMEN will read the text and help you explore it.")
                        .font(.subheadline)
                        .foregroundStyle(Color.amenSlate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 20)

                if !detectedText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Detected Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.amenSlate)
                        TextEditor(text: $detectedText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amenBlack)
                            .frame(minHeight: 80, maxHeight: 160)
                            .padding(10)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .scrollContentBackground(.hidden)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
                            Image(systemName: isProcessing ? "hourglass" : "photo.on.rectangle")
                            Text(isProcessing ? "Reading text…" : "Choose Photo")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isProcessing ? Color.amenPurple.opacity(0.5) : Color.amenPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isProcessing)
                    .padding(.horizontal, 16)

                    if !detectedText.isEmpty {
                        Button {
                            Task { await coordinator.receiveDetectedText(detectedText) }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Ask Berean about this")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.amenPurple)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.amenPurple.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16)
                        .accessibilityLabel("Submit detected text to Berean AI")
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Verse Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                isProcessing = true
                Task {
                    await processPhoto(newItem)
                    isProcessing = false
                }
            }
        }
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let uiImage = UIImage(data: data),
            let cgImage = uiImage.cgImage
        else { return }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else { return }

        let recognized = results
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")

        await MainActor.run { detectedText = recognized }
    }
}

// MARK: - Voice Input Sheet

/// Records speech via SFSpeechRecognizer and submits the transcription to Berean.
struct VoiceInputSheet: View {
    @ObservedObject var coordinator: AmenAssistantBarCoordinator
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 44))
                        .foregroundStyle(recorder.isRecording ? Color.red : Color.amenPurple)
                    Text("Voice to Berean")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.amenBlack)
                    Text(recorder.isRecording ? "Listening…" : "Tap the mic to speak your question or verse")
                        .font(.subheadline)
                        .foregroundStyle(Color.amenSlate)
                }
                .padding(.top, 20)

                if !recorder.transcribedText.isEmpty {
                    Text(recorder.transcribedText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.amenBlack)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                }

                if let error = recorder.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        recorder.isRecording ? recorder.stop() : recorder.start()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(recorder.isRecording ? Color.red : Color.amenPurple)
                                .frame(width: 72, height: 72)
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

                    if !recorder.transcribedText.isEmpty && !recorder.isRecording {
                        Button {
                            Task { await coordinator.receiveDetectedText(recorder.transcribedText) }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Ask Berean")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.amenPurple)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16)
                        .accessibilityLabel("Submit transcription to Berean AI")
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color.amenCream.ignoresSafeArea())
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { recorder.stop() }
            .task { await recorder.requestPermission() }
        }
    }
}

// MARK: - VoiceRecorder

private final class VoiceRecorder: ObservableObject {
    @Published var transcribedText = ""
    @Published var isRecording = false
    @Published var errorMessage: String? = nil

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func requestPermission() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        await MainActor.run {
            if status != .authorized {
                errorMessage = "Speech recognition permission required. Enable in Settings."
            }
        }
    }

    func start() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not configure audio session."
            return
        }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest else { return }
        req.shouldReportPartialResults = true

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        guard (try? audioEngine.start()) != nil else {
            errorMessage = "Could not start audio engine."
            return
        }
        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async { self?.transcribedText = result.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true { self?.stop() }
        }
        DispatchQueue.main.async { self.isRecording = true }
        errorMessage = nil
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        DispatchQueue.main.async { self.isRecording = false }
    }
}
