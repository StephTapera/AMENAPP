//
//  ScriptureVisionService.swift
//  AMENAPP
//
//  Camera → Understanding Layer.
//  User photographs a Bible page (or any text containing scripture) and Berean:
//    1. Extracts text via Vision (on-device OCR, zero network cost)
//    2. Detects verses + Bible version
//    3. Generates a multi-layer interpretation via ClaudeService
//    4. Offers "Apply to My Life" with personalized guidance
//
//  Architecture:
//    ScriptureVisionService (@MainActor singleton)
//    ├── extractText(from:)           – Vision OCR pipeline
//    ├── detectVerses(in:)            – regex + heuristic verse detection
//    ├── analyzeVerse(_:userContext:) – Claude multi-layer analysis
//    └── applyToLife(_:)             – personalized application prompt
//
//  SwiftUI entry: ScriptureVisionSheet (bottom sheet camera capture)
//

import Foundation
import SwiftUI
import Vision
import PhotosUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct VisionVerseResult: Identifiable {
    let id = UUID()
    let rawText: String
    let detectedReference: String?      // e.g. "John 3:16"
    let detectedTranslation: String?    // e.g. "NIV", "ESV"
    var analysis: VerseAnalysis?
    var isAnalyzing: Bool = false
}

struct VerseAnalysis: Codable {
    let reference: String
    let simpleExplanation: String       // ELI5 level
    let theologicalDepth: String        // Doctrine + context
    let historicalContext: String       // Who, when, why written
    let lifeApplication: String         // Practical today
    let crossReferences: [String]       // Related verses
    let highlightedWords: [WordHighlight]
    let prayerPrompt: String
}

struct WordHighlight: Codable, Identifiable {
    let id: String
    let word: String
    let originalLanguage: String?       // Greek / Hebrew
    let briefMeaning: String
}

// MARK: - Service

@MainActor
final class ScriptureVisionService: ObservableObject {
    static let shared = ScriptureVisionService()

    @Published var capturedImage: UIImage?
    @Published var extractedText: String = ""
    @Published var detectedVerses: [VisionVerseResult] = []
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    private let claude = ClaudeService.shared
    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - OCR Pipeline

    /// Run Vision OCR on `image` and store raw extracted text.
    func processImage(_ image: UIImage) async {
        capturedImage = image
        extractedText = ""
        detectedVerses = []
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        guard let cgImage = image.cgImage else {
            errorMessage = "Could not read image."
            return
        }

        let text = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil,
                      let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }

        extractedText = text
        detectedVerses = detectVerses(in: text)

        // Auto-analyze the first detected verse immediately
        if let first = detectedVerses.first {
            await analyzeVerse(id: first.id)
        }
    }

    // MARK: - Verse Detection

    private func detectVerses(in text: String) -> [VisionVerseResult] {
        // Regex for standard Bible reference patterns: "John 3:16", "Genesis 1:1-3", etc.
        let pattern = #"([1-3]?\s?[A-Za-z]+)\s+(\d+):(\d+)(?:[–\-](\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // No reference found — treat full OCR text as a verse fragment
            if text.count > 10 {
                return [VisionVerseResult(rawText: text, detectedReference: nil, detectedTranslation: detectTranslation(in: text))]
            }
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var results: [VisionVerseResult] = []
        for match in matches {
            if let r = Range(match.range, in: text) {
                let ref = String(text[r])
                let translation = detectTranslation(in: text)
                results.append(VisionVerseResult(rawText: text, detectedReference: ref, detectedTranslation: translation))
            }
        }

        // Deduplicate by reference
        var seen = Set<String>()
        return results.filter { seen.insert($0.detectedReference ?? $0.rawText).inserted }
    }

    private func detectTranslation(in text: String) -> String? {
        let markers = ["NIV", "ESV", "KJV", "NKJV", "NLT", "NASB", "CSB", "MSG", "AMP", "NRSV"]
        return markers.first { text.uppercased().contains($0) }
    }

    // MARK: - Analysis

    /// Ask Claude to produce a full multi-layer analysis of the detected verse.
    func analyzeVerse(id: UUID) async {
        guard let idx = detectedVerses.firstIndex(where: { $0.id == id }) else { return }
        detectedVerses[idx].isAnalyzing = true
        defer { detectedVerses[idx].isAnalyzing = false }

        let verse = detectedVerses[idx]
        let userContext = await BereanUserContextProvider.shared.getContextBlock()

        let prompt = buildAnalysisPrompt(verse: verse, userContext: userContext)

        let fullResponse = (try? await claude.sendMessageSync(prompt, mode: .scholar)) ?? ""

        if let analysis = parseAnalysis(from: fullResponse, reference: verse.detectedReference ?? "Unknown Verse") {
            detectedVerses[idx].analysis = analysis
            saveToFirestore(analysis: analysis)
        }
    }

    /// Generates a personalized life-application response.
    func applyToLife(verse: VisionVerseResult) async -> String {
        let userContext = await BereanUserContextProvider.shared.getContextBlock()
        let ref = verse.detectedReference ?? "this verse"
        let prompt = """
        \(userContext)

        The user photographed \(ref) and wants to know how to apply it personally today.
        Given what you know about them, write 3-4 sentences of warm, practical application.
        Be specific, not generic. Speak directly to them.
        """

        let result = (try? await claude.sendMessageSync(prompt, mode: .shepherd)) ?? ""
        return result
    }

    // MARK: - Prompt + Parse

    private func buildAnalysisPrompt(verse: VisionVerseResult, userContext: String) -> String {
        let ref = verse.detectedReference ?? "an extracted scripture passage"
        let translation = verse.detectedTranslation.map { " (\($0))" } ?? ""
        return """
        \(userContext)

        The user photographed a Bible page. Extracted text:
        \"\(verse.rawText.prefix(600))\"
        Detected reference: \(ref)\(translation)

        Return a JSON object with EXACTLY these keys:
        {
          "reference": "<book chapter:verse>",
          "simpleExplanation": "<ELI5 — 2 sentences max>",
          "theologicalDepth": "<doctrine + authorial intent — 3-4 sentences>",
          "historicalContext": "<who, when, why — 2-3 sentences>",
          "lifeApplication": "<practical application for today — 3-4 sentences>",
          "crossReferences": ["<verse1>", "<verse2>", "<verse3>"],
          "highlightedWords": [
            {"id":"1","word":"<word>","originalLanguage":"<Greek/Hebrew or null>","briefMeaning":"<1 sentence>"}
          ],
          "prayerPrompt": "<short prayer starter sentence>"
        }

        Return ONLY valid JSON. No markdown, no extra text.
        """
    }

    private func parseAnalysis(from json: String, reference: String) -> VerseAnalysis? {
        // Strip markdown code fences if present
        var clean = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = clean.data(using: .utf8),
              let obj = try? JSONDecoder().decode(VerseAnalysis.self, from: data) else {
            return nil
        }
        return obj
    }

    // MARK: - Persistence

    private func saveToFirestore(analysis: VerseAnalysis) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc: [String: Any] = [
            "reference": analysis.reference,
            "simpleExplanation": analysis.simpleExplanation,
            "historicalContext": analysis.historicalContext,
            "lifeApplication": analysis.lifeApplication,
            "crossReferences": analysis.crossReferences,
            "savedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("scriptureVisionHistory")
            .addDocument(data: doc)
    }
}

// MARK: - SwiftUI View

struct ScriptureVisionSheet: View {
    @StateObject private var service = ScriptureVisionService.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var applyText: String = ""
    @State private var showingApply = false
    @State private var activeVerseId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    captureSection
                    if !service.extractedText.isEmpty {
                        extractedTextCard
                    }
                    ForEach(service.detectedVerses) { verse in
                        VerseAnalysisCard(verse: verse, onApplyToLife: {
                            activeVerseId = verse.id
                            Task {
                                applyText = await service.applyToLife(verse: verse)
                                showingApply = true
                            }
                        }, onReanalyze: {
                            Task { await service.analyzeVerse(id: verse.id) }
                        })
                    }
                    if service.isProcessing {
                        ProgressView("Analyzing scripture…")
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Scripture Vision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingApply) {
                ApplyToLifeSheet(text: applyText)
            }
        }
    }

    private var captureSection: some View {
        VStack(spacing: 12) {
            if let img = service.capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 160)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Photo a Bible verse")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            await service.processImage(img)
                        }
                    }
                }

                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var extractedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Extracted Text", systemImage: "text.viewfinder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(service.extractedText.prefix(300) + (service.extractedText.count > 300 ? "…" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Verse Analysis Card

private struct VerseAnalysisCard: View {
    let verse: VisionVerseResult
    let onApplyToLife: () -> Void
    let onReanalyze: () -> Void

    @State private var expandedSection: String? = "simple"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse.detectedReference ?? "Scripture")
                        .font(.headline)
                    if let t = verse.detectedTranslation {
                        Text(t).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if verse.isAnalyzing {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding()

            if let a = verse.analysis {
                Divider()

                // Layer tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["simple", "depth", "history", "apply", "cross", "words"], id: \.self) { key in
                            Button(labelFor(key)) {
                                withAnimation(.spring(response: 0.3)) { expandedSection = key }
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(expandedSection == key ? Color.accentColor : Color(.systemGray5),
                                        in: Capsule())
                            .foregroundStyle(expandedSection == key ? .white : .primary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Content
                Group {
                    switch expandedSection {
                    case "simple":  sectionText(a.simpleExplanation)
                    case "depth":   sectionText(a.theologicalDepth)
                    case "history": sectionText(a.historicalContext)
                    case "apply":   sectionText(a.lifeApplication)
                    case "cross":
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(a.crossReferences, id: \.self) { ref in
                                Label(ref, systemImage: "book.closed")
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                    case "words":
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(a.highlightedWords) { w in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(w.word).font(.subheadline.weight(.semibold))
                                        if let lang = w.originalLanguage {
                                            Text("(\(lang))").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(w.briefMeaning).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                    default: EmptyView()
                    }
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button {
                        onApplyToLife()
                    } label: {
                        Label("Apply to My Life", systemImage: "heart.text.square.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    Button {
                        onReanalyze()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                // Prayer prompt
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hands.sparkles.fill")
                        .foregroundStyle(.purple)
                    Text(a.prayerPrompt)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)

            } else if !verse.isAnalyzing {
                Button("Analyze This Verse") { onReanalyze() }
                    .buttonStyle(.bordered)
                    .padding()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func labelFor(_ key: String) -> String {
        switch key {
        case "simple":  return "Simple"
        case "depth":   return "Deep"
        case "history": return "History"
        case "apply":   return "Apply"
        case "cross":   return "Cross-refs"
        case "words":   return "Words"
        default:        return key.capitalized
        }
    }

    private func sectionText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding()
    }
}

// MARK: - Apply to Life Sheet

private struct ApplyToLifeSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Apply to Your Life", systemImage: "heart.text.square.fill")
                        .font(.headline)
                    Text(text.isEmpty ? "Generating personalized guidance…" : text)
                        .font(.body)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
