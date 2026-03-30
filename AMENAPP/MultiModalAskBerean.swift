// MultiModalAskBerean.swift
// AMENAPP
//
// Multi-Modal Ask Berean: Anywhere Intelligence
//
// User can interact with Berean from ANYTHING:
//   - Highlight text → ask
//   - Voice → ask
//   - Image → ask
//   - Sermon recording → ask
//   - Comment → ask
//   - Long-press → "Ask Berean"
//
// This is the unified entry point that routes to the right engine.
//
// Entry points:
//   MultiModalAskBerean.shared.ask(input:) async -> BereanResponse
//   AskBereanSheet (SwiftUI View — universal sheet)

import Foundation
import SwiftUI
import Combine
import Speech
import AVFoundation

// MARK: - Input Types

/// Unified input for any Ask Berean interaction
enum BereanInput {
    case text(String)
    case highlightedText(text: String, context: String)
    case voice                      // Will trigger voice recording
    case image(UIImage)
    case sermonTranscript(String)
    case comment(text: String, postContext: String)
    case verseReference(String)
    case situation(String)          // Life situation mapping
    case thought(String)            // "Test this thought"

    var displayLabel: String {
        switch self {
        case .text: return "Ask Berean"
        case .highlightedText: return "Study This"
        case .voice: return "Voice Ask"
        case .image: return "Scripture Vision"
        case .sermonTranscript: return "Sermon Intelligence"
        case .comment: return "Comment Insight"
        case .verseReference: return "Verse Study"
        case .situation: return "Life Wisdom"
        case .thought: return "Test This Thought"
        }
    }
}

/// Unified response from any engine
struct BereanMultiModalResponse: Identifiable {
    let id = UUID()
    let input: BereanInput
    let response: String
    let citations: [String]
    let suggestedActions: [String]
    let relatedFeature: RelatedFeature?
    let timestamp: Date

    enum RelatedFeature {
        case wordStudy(word: String)
        case contextExpansion(reference: String)
        case scriptureGraph(reference: String)
        case decisionAnalysis
        case growthLoop(content: String)
    }
}

// MARK: - MultiModalAskBerean

@MainActor
final class MultiModalAskBerean: ObservableObject {

    static let shared = MultiModalAskBerean()

    @Published var isProcessing = false
    @Published var lastResponse: BereanMultiModalResponse?
    @Published var isVoiceRecording = false
    @Published var voiceTranscript = ""

    private let aiService = ClaudeService.shared
    private let visionService = ScriptureVisionService.shared
    private let sermonEngine = SermonIntelligenceEngine.shared
    private let decisionEngine = BiblicalDecisionEngine.shared
    private let studyMode = IntentAwareStudyMode.shared
    private let knowledgeGraph = PersonalKnowledgeGraph.shared

    // Voice recording
    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private init() {}

    // MARK: - Unified Ask

    /// Process any input type and route to the right engine
    func ask(input: BereanInput) async -> BereanMultiModalResponse? {
        isProcessing = true
        defer { isProcessing = false }

        switch input {
        case .text(let text):
            return await handleTextQuery(text)

        case .highlightedText(let text, let context):
            return await handleHighlightedText(text, context: context)

        case .voice:
            // Voice is handled separately via startVoice/stopVoice
            return nil

        case .image(let image):
            return await handleImage(image)

        case .sermonTranscript(let transcript):
            return await handleSermon(transcript)

        case .comment(let text, let postContext):
            return await handleComment(text, postContext: postContext)

        case .verseReference(let ref):
            return await handleVerseReference(ref)

        case .situation(let description):
            return await handleSituation(description)

        case .thought(let thought):
            return await handleThought(thought)
        }
    }

    // MARK: - Voice Recording

    func startVoiceRecording() {
        guard !isVoiceRecording else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isVoiceRecording = true
                self.voiceTranscript = ""

                do {
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true

                    let inputNode = self.audioEngine.inputNode
                    let format = inputNode.outputFormat(forBus: 0)

                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.append(buffer)
                    }

                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.audioEngine.start()

                    self.recognitionTask = self.speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
                        guard let result else { return }
                        Task { @MainActor [weak self] in
                            self?.voiceTranscript = result.bestTranscription.formattedString
                        }
                    }
                } catch {
                    self.isVoiceRecording = false
                }
            }
        }
    }

    func stopVoiceRecording() async -> BereanMultiModalResponse? {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        isVoiceRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)

        guard !voiceTranscript.isEmpty else { return nil }
        return await ask(input: .text(voiceTranscript))
    }

    // MARK: - Route Handlers

    private func handleTextQuery(_ text: String) async -> BereanMultiModalResponse {
        let intent = studyMode.detectIntent(from: text)
        let modePrompt = studyMode.buildSystemPrompt(intent: intent)
        let memoryContext = await knowledgeGraph.getSystemPromptContext()
        let userContext = await BereanUserContext.shared.getContextBlock()

        let fullPrompt = """
        \(modePrompt)
        \(memoryContext)
        \(userContext)

        User: \(text)
        """

        do {
            let response = try await aiService.sendMessage(fullPrompt)

            // Extract memories from this interaction
            await knowledgeGraph.extractMemories(from: text, aiResponse: response)

            return BereanMultiModalResponse(
                input: .text(text),
                response: response,
                citations: [],
                suggestedActions: ["Save insight", "Start growth loop"],
                relatedFeature: nil,
                timestamp: Date()
            )
        } catch {
            return BereanMultiModalResponse(
                input: .text(text),
                response: "I'm sorry, I couldn't process that right now. Please try again.",
                citations: [],
                suggestedActions: [],
                relatedFeature: nil,
                timestamp: Date()
            )
        }
    }

    private func handleHighlightedText(_ text: String, context: String) async -> BereanMultiModalResponse {
        // Check if it's a verse reference
        let refs = BereanScriptureEngine.shared.detectReferences(in: text)

        if !refs.isEmpty {
            return await handleVerseReference(refs.first ?? text)
        }

        // Otherwise, do a word study
        let response: String
        do {
            response = try await aiService.sendMessage("""
            The user highlighted this text: "\(text)"
            Context: \(context)

            Provide a quick, insightful explanation. If it's a biblical term, include original language meaning.
            Keep it concise but rich.
            """)
        } catch {
            response = "Tap to study \"\(text)\" in more depth."
        }

        return BereanMultiModalResponse(
            input: .highlightedText(text: text, context: context),
            response: response,
            citations: [],
            suggestedActions: ["Deep word study", "Find in scripture"],
            relatedFeature: .wordStudy(word: text),
            timestamp: Date()
        )
    }

    private func handleImage(_ image: UIImage) async -> BereanMultiModalResponse {
        if let result = await visionService.processImage(image) {
            let verseSummary = result.detectedVerses.map { $0.reference }.joined(separator: ", ")
            return BereanMultiModalResponse(
                input: .image(image),
                response: result.detectedVerses.first?.interpretation?.simple ?? "Verses detected: \(verseSummary)",
                citations: result.detectedVerses.flatMap { $0.crossReferences },
                suggestedActions: ["View full analysis", "Apply to my life"],
                relatedFeature: result.detectedVerses.first.map { .contextExpansion(reference: $0.reference) },
                timestamp: Date()
            )
        }

        return BereanMultiModalResponse(
            input: .image(image),
            response: "No scripture detected in the image. Try a clearer photo of a Bible page.",
            citations: [],
            suggestedActions: ["Try again"],
            relatedFeature: nil,
            timestamp: Date()
        )
    }

    private func handleSermon(_ transcript: String) async -> BereanMultiModalResponse {
        if let analysis = await sermonEngine.analyze(transcript: transcript) {
            return BereanMultiModalResponse(
                input: .sermonTranscript(transcript),
                response: "**\(analysis.title)**\n\n\(analysis.summary)",
                citations: analysis.scripturesReferenced,
                suggestedActions: analysis.actionSteps.map { $0.action },
                relatedFeature: .growthLoop(content: analysis.summary),
                timestamp: Date()
            )
        }

        return BereanMultiModalResponse(
            input: .sermonTranscript(transcript),
            response: "Unable to analyze the sermon. Please try again with a longer recording.",
            citations: [],
            suggestedActions: [],
            relatedFeature: nil,
            timestamp: Date()
        )
    }

    private func handleComment(_ text: String, postContext: String) async -> BereanMultiModalResponse {
        let response: String
        do {
            response = try await aiService.sendMessage("""
            A user sees this comment: "\(text)"
            On a post about: \(postContext)

            Provide a brief, helpful insight about this comment from a biblical perspective.
            Keep it to 2-3 sentences.
            """)
        } catch {
            response = "Consider how this aligns with love, truth, and edification."
        }

        return BereanMultiModalResponse(
            input: .comment(text: text, postContext: postContext),
            response: response,
            citations: [],
            suggestedActions: [],
            relatedFeature: nil,
            timestamp: Date()
        )
    }

    private func handleVerseReference(_ ref: String) async -> BereanMultiModalResponse {
        let response: String
        do {
            let modePrompt = studyMode.buildSystemPrompt()
            response = try await aiService.sendMessage("""
            \(modePrompt)

            Explain \(ref) with context and application. Be rich but concise.
            """)
        } catch {
            response = "Open \(ref) to study it in depth."
        }

        return BereanMultiModalResponse(
            input: .verseReference(ref),
            response: response,
            citations: [ref],
            suggestedActions: ["Expand context", "Word study", "View connections"],
            relatedFeature: .scriptureGraph(reference: ref),
            timestamp: Date()
        )
    }

    private func handleSituation(_ description: String) async -> BereanMultiModalResponse {
        let scriptures = await decisionEngine.mapToScripture(situation: description)
        let scriptureText = scriptures.map { "\($0.reference): \($0.whyItApplies)" }.joined(separator: "\n")

        return BereanMultiModalResponse(
            input: .situation(description),
            response: scriptures.isEmpty ? "Let me help you find wisdom for this situation." : scriptureText,
            citations: scriptures.map { $0.reference },
            suggestedActions: ["Get full decision analysis", "Start prayer"],
            relatedFeature: .decisionAnalysis,
            timestamp: Date()
        )
    }

    private func handleThought(_ thought: String) async -> BereanMultiModalResponse {
        if let result = await decisionEngine.testThought(thought) {
            return BereanMultiModalResponse(
                input: .thought(thought),
                response: result.verdict + "\n\n" + result.balancedGuidance,
                citations: result.supportingScriptures + result.warningScriptures,
                suggestedActions: ["View full analysis"],
                relatedFeature: nil,
                timestamp: Date()
            )
        }

        return BereanMultiModalResponse(
            input: .thought(thought),
            response: "Let me help you think through this biblically.",
            citations: [],
            suggestedActions: [],
            relatedFeature: nil,
            timestamp: Date()
        )
    }
}

// MARK: - Ask Berean Sheet (Universal Entry Point)

struct AskBereanSheet: View {
    var initialInput: BereanInput?
    @StateObject private var askBerean = MultiModalAskBerean.shared
    @State private var textInput = ""
    @State private var selectedMode: InputMode = .text
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    enum InputMode: String, CaseIterable {
        case text = "Text"
        case voice = "Voice"
        case camera = "Camera"

        var icon: String {
            switch self {
            case .text: return "text.bubble.fill"
            case .voice: return "mic.fill"
            case .camera: return "camera.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Response area
                if askBerean.isProcessing {
                    Spacer()
                    ProgressView("Berean is thinking...")
                    Spacer()
                } else if let response = askBerean.lastResponse {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(response.response)
                                .font(.body)

                            if !response.citations.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(response.citations, id: \.self) { ref in
                                            Text(ref)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.blue.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }

                            if !response.suggestedActions.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(response.suggestedActions.prefix(3), id: \.self) { action in
                                        Button(action) {}
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.secondary.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                    Text("Ask Berean Anything")
                        .font(.title3.bold())
                    Text("Text, voice, or camera")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Mode selector
                Picker("Input Mode", selection: $selectedMode) {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Input area
                switch selectedMode {
                case .text:
                    HStack {
                        TextField("Ask anything...", text: $textInput)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            guard !textInput.isEmpty else { return }
                            let query = textInput
                            textInput = ""
                            Task { await askBerean.ask(input: .text(query)) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .disabled(textInput.isEmpty || askBerean.isProcessing)
                    }
                    .padding(.horizontal)

                case .voice:
                    VStack(spacing: 8) {
                        if askBerean.isVoiceRecording {
                            Text(askBerean.voiceTranscript.isEmpty ? "Listening..." : askBerean.voiceTranscript)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        Button {
                            if askBerean.isVoiceRecording {
                                Task { await askBerean.stopVoiceRecording() }
                            } else {
                                askBerean.startVoiceRecording()
                            }
                        } label: {
                            Image(systemName: askBerean.isVoiceRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(askBerean.isVoiceRecording ? .red : .blue)
                        }
                    }
                    .padding()

                case .camera:
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.blue.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePickerView(image: $capturedImage, sourceType: .camera)
            }
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    Task { await askBerean.ask(input: .image(image)) }
                }
            }
            .task {
                if let initial = initialInput {
                    await askBerean.ask(input: initial)
                }
            }
        }
    }
}
