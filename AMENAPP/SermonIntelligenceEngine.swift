//
//  SermonIntelligenceEngine.swift
//  AMENAPP
//
//  Audio → Structured Growth.
//  Turns a sermon recording (or live transcript) into actionable Church Notes.
//
//  Pipeline:
//    1. Speech-to-text via WhisperVoiceService (already in project)
//    2. Topic segmentation  – main points, themes, scripture refs
//    3. AI structuring      – summary, takeaways, reflection prompts, action steps
//    4. Auto-scheduling     – reflection nudges at +24h / +3d / +7d
//    5. Church Notes export – writes directly into ChurchNotesService
//
//  Architecture:
//    SermonIntelligenceEngine (@MainActor singleton)
//    ├── SermonRecording      (model)
//    ├── SermonAnalysis       (model)
//    ├── transcribeAndAnalyze(_:)
//    ├── analyzeTranscript(_:)
//    └── exportToChurchNotes(_:)
//
//  SwiftUI: SermonIntelligenceSheet
//

import Foundation
import SwiftUI
import AVFoundation
import Speech
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct SermonRecording: Identifiable {
    let id = UUID()
    var audioURL: URL?
    var transcript: String = ""
    var churchName: String = ""
    var speakerName: String = ""
    var sermonDate: Date = Date()
    var analysis: SermonAnalysis?
    var isProcessing: Bool = false
}

struct SermonAnalysis: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String                 // 2-3 sentences
    let mainPoints: [SermonPoint]
    let scriptureRefs: [String]
    let themes: [String]                // e.g. "obedience", "grace"
    let keyTakeaways: [String]          // bullet list (3-5)
    let reflectionPrompts: [String]     // journaling questions (2-3)
    let actionSteps: [String]           // concrete actions (2-3)
    let moodTone: String                // "encouraging", "convicting", "teaching"
    let createdAt: Date

    struct SermonPoint: Codable, Identifiable {
        let id: String
        let heading: String
        let detail: String
        let supportingVerses: [String]
    }
}

// MARK: - Service

@MainActor
final class SermonIntelligenceEngine: ObservableObject {
    static let shared = SermonIntelligenceEngine()

    @Published var currentRecording: SermonRecording?
    @Published var recentSermons: [SermonAnalysis] = []
    @Published var isTranscribing: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var transcriptionProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?

    private let claude = ClaudeService.shared
    private lazy var db = Firestore.firestore()

    private init() {
        Task { await loadRecentSermons() }
    }

    // MARK: - Main Pipeline

    /// Full pipeline: audio file → Church Notes.
    func processAudio(url: URL, churchName: String = "", speakerName: String = "") async {
        var recording = SermonRecording(audioURL: url, churchName: churchName, speakerName: speakerName)
        currentRecording = recording
        isTranscribing = true
        statusMessage = "Transcribing sermon…"

        // Step 1: Transcribe via WhisperVoiceService
        let transcript = await transcribeAudio(url: url)
        recording.transcript = transcript
        isTranscribing = false

        guard !transcript.isEmpty else {
            errorMessage = "Could not transcribe audio. Please try again."
            return
        }

        // Step 2: Analyze
        isAnalyzing = true
        statusMessage = "Understanding the message…"
        if let analysis = await analyzeTranscript(recording: recording) {
            recording.analysis = analysis
            currentRecording = recording
            saveToFirestore(analysis)
            scheduleReflectionNudges(for: analysis)
        }
        isAnalyzing = false
        statusMessage = "Done"
    }

    /// Analyze a pre-existing transcript (e.g. typed or pasted).
    func analyzeTranscript(recording: SermonRecording) async -> SermonAnalysis? {
        let userContext = await BereanUserContextProvider.shared.getContextBlock()
        let prompt = buildAnalysisPrompt(recording: recording, userContext: userContext)

        let fullResponse = (try? await claude.sendMessageSync(prompt, mode: .scholar)) ?? ""

        return parseAnalysis(from: fullResponse)
    }

    /// Export the analysis into ChurchNotesService as a new note.
    func exportToChurchNotes(_ analysis: SermonAnalysis, sermonMeta: SermonRecording) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Build rich text content from the analysis
        var content = "# \(analysis.title)\n\n"
        content += "**Summary:** \(analysis.summary)\n\n"
        content += "## Main Points\n"
        for (i, point) in analysis.mainPoints.enumerated() {
            content += "\(i + 1). **\(point.heading)** — \(point.detail)\n"
            if !point.supportingVerses.isEmpty {
                content += "   📖 " + point.supportingVerses.joined(separator: ", ") + "\n"
            }
        }
        content += "\n## Key Takeaways\n"
        for t in analysis.keyTakeaways { content += "• \(t)\n" }
        content += "\n## Reflect On This\n"
        for q in analysis.reflectionPrompts { content += "• \(q)\n" }
        content += "\n## Action Steps\n"
        for a in analysis.actionSteps { content += "• \(a)\n" }

        let note: [String: Any] = [
            "title": analysis.title,
            "content": content,
            "sermonDate": sermonMeta.sermonDate,
            "churchName": sermonMeta.churchName,
            "speakerName": sermonMeta.speakerName,
            "tags": analysis.themes,
            "scriptureRefs": analysis.scriptureRefs,
            "source": "SermonIntelligence",
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("users").document(uid).collection("churchNotes").addDocument(data: note)
        } catch {
            print("SermonIntelligenceEngine: failed to save church note — \(error.localizedDescription)")
        }
        statusMessage = "Saved to Church Notes"
    }

    // MARK: - Transcription (delegates to WhisperVoiceService)

    private func transcribeAudio(url: URL) async -> String {
        // Use SFSpeechRecognizer for file-based transcription.
        return await withCheckedContinuation { continuation in
            let recognizer = SFSpeechRecognizer()
            guard recognizer?.isAvailable == true else {
                continuation.resume(returning: "")
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            recognizer?.recognitionTask(with: request) { result, error in
                if let r = result, r.isFinal {
                    continuation.resume(returning: r.bestTranscription.formattedString)
                } else if error != nil {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: - Prompt Building

    private func buildAnalysisPrompt(recording: SermonRecording, userContext: String) -> String {
        let meta = recording.churchName.isEmpty ? "" : "Church: \(recording.churchName). Speaker: \(recording.speakerName)."
        let truncated = String(recording.transcript.prefix(6000))

        return """
        \(userContext)
        \(meta)

        Sermon transcript (may be truncated):
        \"\"\"\(truncated)\"\"\"

        Analyze this sermon and return a JSON object with EXACTLY these keys:
        {
          "id": "<uuid string>",
          "title": "<concise sermon title>",
          "summary": "<2-3 sentence summary>",
          "mainPoints": [
            {"id":"1","heading":"<point heading>","detail":"<1-2 sentences>","supportingVerses":["<verse>"]}
          ],
          "scriptureRefs": ["<verse reference>"],
          "themes": ["<theme tag>"],
          "keyTakeaways": ["<takeaway>"],
          "reflectionPrompts": ["<question>"],
          "actionSteps": ["<action>"],
          "moodTone": "<encouraging|convicting|teaching|prophetic|comforting>",
          "createdAt": "<ISO 8601 date string>"
        }

        Return ONLY valid JSON. No markdown fences.
        """
    }

    private func parseAnalysis(from json: String) -> SermonAnalysis? {
        var clean = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            let lines = clean.components(separatedBy: "\n")
            clean = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = clean.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SermonAnalysis.self, from: data)
    }

    // MARK: - Growth Loop Scheduling

    private func scheduleReflectionNudges(for analysis: SermonAnalysis) {
        let center = UNUserNotificationCenter.current()

        let nudges: [(TimeInterval, String)] = [
            (86_400,    "Reflect: \(analysis.reflectionPrompts.first ?? "How is God speaking to you through Sunday's sermon?")"),
            (259_200,   "Day 3 check-in: Have you applied one action step from the sermon?"),
            (604_800,   "One week later — how has the sermon changed your thinking or actions?")
        ]

        for (offset, body) in nudges {
            let content = UNMutableNotificationContent()
            content.title = "Sermon Reflection — \(analysis.title)"
            content.body = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: offset, repeats: false)
            let req = UNNotificationRequest(
                identifier: "sermon_\(analysis.id)_\(Int(offset))",
                content: content,
                trigger: trigger
            )
            center.add(req)
        }
    }

    // MARK: - Persistence

    private func saveToFirestore(_ analysis: SermonAnalysis) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc: [String: Any] = [
            "id": analysis.id,
            "title": analysis.title,
            "summary": analysis.summary,
            "themes": analysis.themes,
            "scriptureRefs": analysis.scriptureRefs,
            "keyTakeaways": analysis.keyTakeaways,
            "moodTone": analysis.moodTone,
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("sermonAnalyses")
            .document(analysis.id)
            .setData(doc)
    }

    private func loadRecentSermons() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await db.collection("users").document(uid)
            .collection("sermonAnalyses")
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments()

        // We only have summary data in Firestore for the list view.
        // Full analysis lives in currentRecording.
        _ = snap?.documents
    }
}

// MARK: - SwiftUI View

struct SermonIntelligenceSheet: View {
    @StateObject private var engine = SermonIntelligenceEngine.shared
    @State private var showingFilePicker = false
    @State private var pastedTranscript = ""
    @State private var mode: InputMode = .record
    @State private var churchName = ""
    @State private var speakerName = ""
    @State private var showingExportConfirm = false
    @Environment(\.dismiss) private var dismiss

    enum InputMode { case record, paste }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Mode picker
                    Picker("Input Mode", selection: $mode) {
                        Text("Audio File").tag(InputMode.record)
                        Text("Paste Transcript").tag(InputMode.paste)
                    }
                    .pickerStyle(.segmented)

                    // Meta fields
                    VStack(spacing: 10) {
                        TextField("Church name (optional)", text: $churchName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Speaker name (optional)", text: $speakerName)
                            .textFieldStyle(.roundedBorder)
                    }

                    if mode == .record {
                        audioInputSection
                    } else {
                        pasteInputSection
                    }

                    // Status
                    if engine.isTranscribing || engine.isAnalyzing {
                        ProgressView(engine.statusMessage)
                            .padding()
                    }

                    // Results
                    if let analysis = engine.currentRecording?.analysis {
                        SermonAnalysisResultView(analysis: analysis, onExport: {
                            showingExportConfirm = true
                        })
                    }
                }
                .padding()
            }
            .navigationTitle("Sermon Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save to Church Notes?", isPresented: $showingExportConfirm) {
                Button("Save") {
                    Task {
                        if let analysis = engine.currentRecording?.analysis,
                           let rec = engine.currentRecording {
                            await engine.exportToChurchNotes(analysis, sermonMeta: rec)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var audioInputSection: some View {
        VStack(spacing: 12) {
            Button {
                showingFilePicker = true
            } label: {
                Label("Choose Audio File", systemImage: "waveform.and.mic")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio],
                allowsMultipleSelection: false
            ) { result in
                if let url = try? result.get().first {
                    Task { await engine.processAudio(url: url, churchName: churchName, speakerName: speakerName) }
                }
            }

            Text("Supports .mp3, .m4a, .wav")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pasteInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste your sermon transcript:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $pastedTranscript)
                .frame(minHeight: 140)
                .padding(8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

            Button {
                guard !pastedTranscript.isEmpty else { return }
                Task {
                    var rec = SermonRecording(churchName: churchName, speakerName: speakerName)
                    rec.transcript = pastedTranscript
                    engine.currentRecording = rec
                    engine.isAnalyzing = true
                    let analysis = await engine.analyzeTranscript(recording: rec)
                    var updated = rec
                    updated.analysis = analysis
                    engine.currentRecording = updated
                    engine.isAnalyzing = false
                }
            } label: {
                Label("Analyze Transcript", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pastedTranscript.isEmpty || engine.isAnalyzing)
        }
    }
}

// MARK: - Analysis Result View

struct SermonAnalysisResultView: View {
    let analysis: SermonAnalysis
    let onExport: () -> Void
    @State private var expanded: String? = "summary"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.title).font(.headline)
                HStack {
                    Text(analysis.moodTone.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(moodColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(moodColor)
                    Spacer()
                }
            }
            .padding()

            Divider()

            // Section tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["summary", "points", "takeaways", "reflect", "actions", "verses"], id: \.self) { key in
                        Button(tabLabel(key)) {
                            withAnimation(.spring(response: 0.3)) { expanded = key }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(expanded == key ? Color.accentColor : Color(.systemGray5), in: Capsule())
                        .foregroundStyle(expanded == key ? .white : .primary)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }

            Group {
                switch expanded {
                case "summary":
                    Text(analysis.summary).font(.subheadline).padding()
                case "points":
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(analysis.mainPoints) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.heading).font(.subheadline.weight(.semibold))
                                Text(p.detail).font(.caption).foregroundStyle(.secondary)
                                if !p.supportingVerses.isEmpty {
                                    Text(p.supportingVerses.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(.indigo)
                                }
                            }
                        }
                    }.padding()
                case "takeaways":
                    bulletList(analysis.keyTakeaways)
                case "reflect":
                    bulletList(analysis.reflectionPrompts)
                case "actions":
                    bulletList(analysis.actionSteps)
                case "verses":
                    bulletList(analysis.scriptureRefs)
                default: EmptyView()
                }
            }

            Divider()

            // Themes + export
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(analysis.themes, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.1), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    onExport()
                } label: {
                    Label("Save to Church Notes", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var moodColor: Color {
        switch analysis.moodTone {
        case "encouraging": return .green
        case "convicting":  return .orange
        case "prophetic":   return .purple
        case "comforting":  return .blue
        default:            return .indigo
        }
    }

    private func tabLabel(_ key: String) -> String {
        switch key {
        case "summary":   return "Summary"
        case "points":    return "Points"
        case "takeaways": return "Takeaways"
        case "reflect":   return "Reflect"
        case "actions":   return "Actions"
        case "verses":    return "Verses"
        default:          return key.capitalized
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.subheadline)
                    .labelStyle(BulletLabelStyle())
            }
        }.padding()
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 6) {
            configuration.icon
                .font(.systemScaled(5))
                .padding(.top, 6)
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
