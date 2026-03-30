// ScriptureVisionService.swift
// AMENAPP
//
// Scripture Vision: Camera → Understanding Layer
//
// Pipeline:
//   1. Camera capture / photo library → UIImage
//   2. VisionKit OCR → raw text extraction
//   3. Scripture reference detection (regex + AI fallback)
//   4. Bible version matching + verse fetch
//   5. Multi-layer interpretation:
//      - Simple (ELI5)
//      - Theological depth
//      - Life application
//      - Cross-references
//   6. Highlighted word detection → deep word study (Greek/Hebrew)
//   7. "Apply this to my life" personalized response
//
// Entry points:
//   ScriptureVisionService.shared.processImage(_ image: UIImage) async -> ScriptureVisionResult
//   ScriptureVisionService.shared.applyToMyLife(verse:) async -> String

import Foundation
import SwiftUI
import Vision
import Combine

// MARK: - Models

/// The complete result of processing a Bible photo
struct ScriptureVisionResult: Identifiable {
    let id = UUID()
    let extractedText: String
    let detectedVerses: [DetectedVerse]
    let highlightedWords: [HighlightedWord]
    let processedAt: Date

    var hasVerses: Bool { !detectedVerses.isEmpty }
}

/// A verse detected from the image with multi-layer interpretation
struct DetectedVerse: Identifiable {
    let id = UUID()
    let reference: String           // e.g. "John 3:16"
    let extractedText: String       // raw text from image
    let matchedVersion: String?     // ESV, NIV, KJV etc.
    let interpretation: VerseInterpretation?
    let crossReferences: [String]
}

/// Multi-layer explanation system
struct VerseInterpretation: Codable {
    let simple: String              // ELI5 explanation
    let theological: String         // Deep theological meaning
    let lifeApplication: String     // How to apply today
    let historicalContext: String    // Who, when, why
    let chapterContext: String       // What's happening in the chapter
    let audienceContext: String      // Original audience
}

/// A highlighted/emphasized word detected in the image
struct HighlightedWord: Identifiable {
    let id = UUID()
    let word: String
    let isHighlighted: Bool         // Detected as visually emphasized
    let wordStudy: DeepWordResult?
}

/// Deep word study result (Greek/Hebrew)
struct DeepWordResult: Codable {
    let english: String
    let greek: String?              // Greek term if NT
    let hebrew: String?             // Hebrew term if OT
    let transliteration: String?
    let definitionSpectrum: [String] // Multiple meanings
    let firstBiblicalUsage: String? // Where it first appears
    let usageAcrossContexts: [WordContextUsage]
}

struct WordContextUsage: Codable {
    let reference: String
    let context: String
    let meaningInContext: String
}

// MARK: - ScriptureVisionService

@MainActor
final class ScriptureVisionService: ObservableObject {

    static let shared = ScriptureVisionService()

    @Published var isProcessing = false
    @Published var currentResult: ScriptureVisionResult?
    @Published var processingStage: ProcessingStage = .idle
    @Published var error: String?

    enum ProcessingStage: String {
        case idle = "Ready"
        case extractingText = "Reading text..."
        case detectingVerses = "Finding verses..."
        case interpreting = "Understanding context..."
        case buildingWordStudy = "Studying words..."
        case complete = "Complete"
    }

    private let aiService = ClaudeService.shared
    private let scriptureEngine = BereanScriptureEngine.shared

    private init() {}

    // MARK: - Public API

    /// Process a camera/photo image to extract and interpret scripture
    func processImage(_ image: UIImage) async -> ScriptureVisionResult? {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        // Step 1: OCR text extraction
        processingStage = .extractingText
        let extractedText = await extractText(from: image)
        guard !extractedText.isEmpty else {
            error = "No text found in image"
            processingStage = .idle
            return nil
        }

        // Step 2: Detect scripture references
        processingStage = .detectingVerses
        let refs = scriptureEngine.detectReferences(in: extractedText)

        // Step 3: If no refs found via regex, try AI detection
        let finalRefs: [String]
        if refs.isEmpty {
            finalRefs = await detectVersesWithAI(text: extractedText)
        } else {
            finalRefs = refs
        }

        // Step 4: Build interpretations for each verse
        processingStage = .interpreting
        var detectedVerses: [DetectedVerse] = []
        for ref in finalRefs {
            let interpretation = await buildInterpretation(for: ref, fullContext: extractedText)
            let crossRefs = await scriptureEngine.crossRefs(for: ref)
            let version = detectBibleVersion(text: extractedText)

            detectedVerses.append(DetectedVerse(
                reference: ref,
                extractedText: extractedText,
                matchedVersion: version,
                interpretation: interpretation,
                crossReferences: crossRefs
            ))
        }

        // Step 5: Detect highlighted words
        processingStage = .buildingWordStudy
        let highlightedWords = await detectHighlightedWords(in: extractedText, refs: finalRefs)

        processingStage = .complete
        let result = ScriptureVisionResult(
            extractedText: extractedText,
            detectedVerses: detectedVerses,
            highlightedWords: highlightedWords,
            processedAt: Date()
        )
        currentResult = result
        return result
    }

    /// Personalized "Apply this to my life" response
    func applyToMyLife(verse: DetectedVerse) async -> String {
        let userContext = await BereanUserContext.shared.getContextBlock()
        let prompt = """
        The user photographed this Bible verse and wants to apply it to their life:

        Verse: \(verse.reference)
        Text: \(verse.extractedText)

        User context:
        \(userContext)

        Provide a deeply personal, practical application of this verse to their life.
        Be specific, warm, and actionable. Include:
        1. What this verse means for their specific situation
        2. One concrete thing they can do TODAY
        3. A short prayer they can pray

        Keep it under 200 words. Be pastoral, not preachy.
        """

        do {
            return try await aiService.sendMessage(prompt)
        } catch {
            return "Take a moment to reflect on \(verse.reference) and ask God how it applies to your life today."
        }
    }

    // MARK: - OCR Engine

    private func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - AI Verse Detection

    private func detectVersesWithAI(text: String) async -> [String] {
        let prompt = """
        Extract any Bible verse references from this text. Return ONLY the references, one per line.
        If no Bible verses are found, return "NONE".

        Text: \(text)
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            if response.contains("NONE") { return [] }
            return response.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    // MARK: - Multi-Layer Interpretation

    private func buildInterpretation(for ref: String, fullContext: String) async -> VerseInterpretation? {
        let prompt = """
        Provide a multi-layer interpretation of \(ref). Return as JSON:
        {
            "simple": "ELI5 explanation (2-3 sentences, anyone can understand)",
            "theological": "Deep theological meaning with doctrinal significance",
            "lifeApplication": "How to apply this verse in daily life today",
            "historicalContext": "Who wrote it, when, why, and to whom",
            "chapterContext": "What is happening in the surrounding chapter",
            "audienceContext": "Who was the original audience and their situation"
        }

        Be accurate, grounded in scripture, and warm in tone.
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(response.utf8)
            return try JSONDecoder().decode(VerseInterpretation.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Bible Version Detection

    private func detectBibleVersion(text: String) -> String? {
        let versions = [
            "ESV": ["ESV", "English Standard Version"],
            "NIV": ["NIV", "New International Version"],
            "KJV": ["KJV", "King James Version"],
            "NKJV": ["NKJV", "New King James Version"],
            "NLT": ["NLT", "New Living Translation"],
            "NASB": ["NASB", "New American Standard Bible"],
        ]

        for (code, markers) in versions {
            for marker in markers {
                if text.localizedCaseInsensitiveContains(marker) {
                    return code
                }
            }
        }
        return nil
    }

    // MARK: - Highlighted Word Detection

    private func detectHighlightedWords(in text: String, refs: [String]) async -> [HighlightedWord] {
        // Use AI to detect theologically significant words
        let prompt = """
        From this Bible text, identify the 3 most theologically significant words that would benefit from a deep word study.
        Return as JSON array: [{"word": "love", "significant": true}]

        Text: \(text)
        Return ONLY valid JSON array, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(response.utf8)

            struct WordCandidate: Codable {
                let word: String
                let significant: Bool
            }

            let candidates = try JSONDecoder().decode([WordCandidate].self, from: data)

            var results: [HighlightedWord] = []
            for candidate in candidates where candidate.significant {
                let study = await deepWordStudy(word: candidate.word, context: refs.first ?? "")
                results.append(HighlightedWord(
                    word: candidate.word,
                    isHighlighted: true,
                    wordStudy: study
                ))
            }
            return results
        } catch {
            return []
        }
    }

    // MARK: - Deep Word Study (used by ScriptureVision + standalone)

    func deepWordStudy(word: String, context: String) async -> DeepWordResult? {
        let prompt = """
        Perform a deep word study for "\(word)" in the context of \(context). Return as JSON:
        {
            "english": "\(word)",
            "greek": "Greek term if New Testament (null if OT)",
            "hebrew": "Hebrew term if Old Testament (null if NT)",
            "transliteration": "How to pronounce the original",
            "definitionSpectrum": ["meaning1", "meaning2", "meaning3"],
            "firstBiblicalUsage": "First appearance in the Bible with reference",
            "usageAcrossContexts": [
                {"reference": "Verse ref", "context": "Brief context", "meaningInContext": "What it means here"}
            ]
        }

        Be accurate. Include 3-5 usage examples across different biblical contexts.
        Return ONLY valid JSON, no markdown.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(response.utf8)
            return try JSONDecoder().decode(DeepWordResult.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Scripture Vision View

struct ScriptureVisionView: View {
    @StateObject private var visionService = ScriptureVisionService.shared
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedImage: UIImage?
    @State private var selectedVerse: DetectedVerse?
    @State private var applyToLifeText: String?
    @State private var isApplying = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if visionService.isProcessing {
                        processingView
                    } else if let result = visionService.currentResult {
                        resultView(result)
                    } else {
                        capturePromptView
                    }
                }
                .padding()
            }
            .navigationTitle("Scripture Vision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePickerView(image: $capturedImage, sourceType: .camera)
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePickerView(image: $capturedImage, sourceType: .photoLibrary)
            }
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    Task { await visionService.processImage(image) }
                }
            }
        }
    }

    // MARK: - Subviews

    private var capturePromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.and.wrench.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)

            Text("Photograph a Bible verse")
                .font(.title2.bold())

            Text("Point your camera at any Bible verse and Berean will extract, interpret, and contextualize it for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showPhotoLibrary = true
                } label: {
                    Label("Photos", systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(.top, 60)
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text(visionService.processingStage.rawValue)
                .font(.headline)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: visionService.processingStage.rawValue)
        }
        .padding(.top, 100)
    }

    private func resultView(_ result: ScriptureVisionResult) -> some View {
        VStack(spacing: 20) {
            // Detected verses
            ForEach(result.detectedVerses) { verse in
                verseCard(verse)
            }

            // Highlighted words
            if !result.highlightedWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Word Studies")
                        .font(.headline)

                    ForEach(result.highlightedWords) { word in
                        wordStudyCard(word)
                    }
                }
            }

            // Scan another
            Button {
                visionService.currentResult = nil
                capturedImage = nil
            } label: {
                Label("Scan Another Verse", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.blue.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func verseCard(_ verse: DetectedVerse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verse.reference)
                    .font(.headline)
                Spacer()
                if let version = verse.matchedVersion {
                    Text(version)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if let interp = verse.interpretation {
                // Simple explanation
                interpretationSection(title: "Simple", icon: "lightbulb.fill", text: interp.simple)

                // Theological depth
                interpretationSection(title: "Theological", icon: "book.fill", text: interp.theological)

                // Life application
                interpretationSection(title: "Life Application", icon: "heart.fill", text: interp.lifeApplication)

                // Historical context
                interpretationSection(title: "Historical Context", icon: "clock.fill", text: interp.historicalContext)

                // Cross-references
                if !verse.crossReferences.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cross-References")
                            .font(.subheadline.bold())
                        ForEach(verse.crossReferences, id: \.self) { ref in
                            Text("• \(ref)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Apply to my life button
            Button {
                Task {
                    isApplying = true
                    applyToLifeText = await visionService.applyToMyLife(verse: verse)
                    isApplying = false
                }
            } label: {
                HStack {
                    Image(systemName: "person.fill.questionmark")
                    Text(isApplying ? "Thinking..." : "Apply This to My Life")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isApplying)

            if let text = applyToLifeText {
                Text(text)
                    .font(.subheadline)
                    .padding()
                    .background(.green.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func interpretationSection(title: String, icon: String, text: String) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
        }
    }

    private func wordStudyCard(_ word: HighlightedWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.word.capitalized)
                .font(.subheadline.bold())

            if let study = word.wordStudy {
                if let greek = study.greek {
                    HStack {
                        Text("Greek:")
                            .font(.caption.bold())
                        Text(greek)
                            .font(.caption)
                            .italic()
                    }
                }
                if let hebrew = study.hebrew {
                    HStack {
                        Text("Hebrew:")
                            .font(.caption.bold())
                        Text(hebrew)
                            .font(.caption)
                            .italic()
                    }
                }

                Text(study.definitionSpectrum.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Image Picker (UIKit bridge)

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
