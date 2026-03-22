// SermonRecorder.swift
// AMENAPP
//
// Live sermon audio recorder:
//   AVAudioEngine + SFSpeechRecognizer → 30s rolling chunks
//   → ClaudeService (text) for incremental note structuring
//   → ChurchNote saved via ChurchNotesService on stop

import Foundation
import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - SermonRecorder

@MainActor
final class SermonRecorder: ObservableObject {

    // MARK: Published state

    @Published var isRecording = false
    @Published var liveNote    = SermonDraft()
    @Published var elapsed: TimeInterval = 0
    @Published var transcriptBuffer = ""    // full rolling transcript
    @Published var chunkCount = 0          // how many chunks processed
    @Published var stage: RecorderStage = .idle

    enum RecorderStage: String {
        case idle       = "Ready"
        case recording  = "Recording"
        case processing = "Structuring…"
        case finalizing = "Finalizing…"
        case done       = "Done"
    }

    // MARK: Private

    private let audioEngine  = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    private var chunkTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private let chunkInterval: TimeInterval = 30   // seconds between chunk sends
    private let overlapTokens = 200                // ~200 chars kept for continuity
    private var startedAt: Date?
    private var lastChunkEnd = ""                  // tail of last processed chunk

    // MARK: - Start

    func start() throws {
        guard !isRecording else { return }

        // Request permissions
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }

        try setupAudioSession()
        try setupRecognition()
        try audioEngine.start()

        isRecording = true
        stage       = .recording
        startedAt   = Date()
        elapsed     = 0

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startedAt else { return }
            Task { @MainActor in self.elapsed = Date().timeIntervalSince(start) }
        }

        scheduleNextChunk()
    }

    // MARK: - Stop

    func stop() async -> SermonDraft {
        guard isRecording else { return liveNote }

        isRecording = false
        stage       = .finalizing
        chunkTask?.cancel()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Final structuring pass on the full transcript
        await finalizeNote()
        stage = .done
        return liveNote
    }

    // MARK: - Audio + Speech setup

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func setupRecognition() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in self.transcriptBuffer = text }
            }
        }

        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            request.append(buf)
        }
        audioEngine.prepare()
    }

    // MARK: - Chunk scheduling

    private func scheduleNextChunk() {
        chunkTask?.cancel()
        chunkTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(chunkInterval) * 1_000_000_000)
            guard !Task.isCancelled, isRecording else { return }
            await processChunk()
            scheduleNextChunk()
        }
    }

    private func processChunk() async {
        let fullBuffer = transcriptBuffer
        guard !fullBuffer.isEmpty else { return }

        // Build the incremental chunk: new text since last chunk + overlap from previous
        let overlap  = String(lastChunkEnd.suffix(overlapTokens))
        let newText  = overlap + "\n" + fullBuffer

        stage = .processing
        if let structured = await structureChunk(newText) {
            liveNote.merge(structured)
            chunkCount += 1
            // Keep the tail of this chunk for next overlap
            lastChunkEnd = String(fullBuffer.suffix(overlapTokens))
        }
        if isRecording { stage = .recording }
    }

    private func finalizeNote() async {
        let fullTranscript = transcriptBuffer
        guard !fullTranscript.isEmpty else { return }

        let prompt = """
        Full sermon transcript:
        \(fullTranscript)

        Structure this into a sermon note. Return JSON only:
        {
          "title": "sermon title (derive from content)",
          "keyPoints": ["main point 1", "main point 2", ...],
          "scriptures": ["Book Chapter:Verse", ...],
          "summary": "2–3 sentence summary",
          "applicationPoints": ["practical takeaway 1", ...],
          "rawTranscript": "\(fullTranscript.prefix(4000))"
        }
        Deduplicate. Max 6 key points, 4 scriptures, 3 application points.
        JSON only, no markdown.
        """

        if let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar),
           let data = result.data(using: .utf8),
           let json = try? JSONDecoder().decode(SermonDraftJSON.self, from: cleanJSON(result)) {
            liveNote.merge(SermonDraft(from: json, transcript: fullTranscript))
        }
        liveNote.rawTranscript  = fullTranscript
        liveNote.durationSeconds = Int(elapsed)
    }

    // MARK: - Claude chunk structuring

    private func structureChunk(_ chunk: String) async -> SermonDraft? {
        let prompt = """
        New sermon transcript chunk (30 seconds):
        \(chunk)

        Extract incremental updates. Return JSON only:
        {
          "title": "if detected, else empty string",
          "keyPoints": ["new points only"],
          "scriptures": ["new refs only"],
          "summary": "",
          "applicationPoints": []
        }
        JSON only.
        """

        guard let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar) else {
            return nil
        }

        guard let data = cleanJSON(result).data(using: .utf8),
              let json = try? JSONDecoder().decode(SermonDraftJSON.self, from: data) else {
            return nil
        }
        return SermonDraft(from: json, transcript: chunk)
    }

    private func cleanJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - SermonDraft

struct SermonDraft {
    var title = ""
    var keyPoints: [String]         = []
    var scriptures: [String]        = []
    var summary = ""
    var applicationPoints: [String] = []
    var rawTranscript = ""
    var durationSeconds = 0

    init() {}

    init(from json: SermonDraftJSON, transcript: String) {
        title              = json.title ?? ""
        keyPoints          = json.keyPoints ?? []
        scriptures         = json.scriptures ?? []
        summary            = json.summary ?? ""
        applicationPoints  = json.applicationPoints ?? []
        rawTranscript      = transcript
    }

    mutating func merge(_ other: SermonDraft) {
        if title.isEmpty && !other.title.isEmpty { title = other.title }
        let existingKP  = Set(keyPoints)
        let existingSC  = Set(scriptures)
        let existingAP  = Set(applicationPoints)
        keyPoints        += other.keyPoints.filter  { !existingKP.contains($0) }
        scriptures       += other.scriptures.filter { !existingSC.contains($0) }
        applicationPoints += other.applicationPoints.filter { !existingAP.contains($0) }
        if summary.isEmpty && !other.summary.isEmpty { summary = other.summary }
    }

    /// Convert to ChurchNote for saving
    func toChurchNote(userId: String) -> ChurchNote {
        ChurchNote(
            userId:              userId,
            title:               title.isEmpty ? "Sermon Recording" : title,
            date:                Date(),
            content:             summary.isEmpty ? rawTranscript : summary,
            keyPoints:           keyPoints,
            tags:                ["recorded"],
            scriptureReferences: scriptures
        )
    }
}

// MARK: - SermonDraftJSON (decoding only)

struct SermonDraftJSON: Codable {
    var title:              String?
    var keyPoints:          [String]?
    var scriptures:         [String]?
    var summary:            String?
    var applicationPoints:  [String]?
}

// MARK: - RecordingControlView (inserted into Berean as sheet)

struct SermonRecordingSheet: View {
    @StateObject private var recorder = SermonRecorder()
    let onSave: (SermonDraft) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // Stage + elapsed
            HStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color(.tertiaryLabel))
                    .frame(width: 8, height: 8)
                    .opacity(recorder.isRecording ? 1 : 0.4)
                Text(recorder.isRecording ? elapsedString : recorder.stage.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
                if recorder.chunkCount > 0 {
                    Text("\(recorder.chunkCount) chunks")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Live note preview
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !recorder.liveNote.title.isEmpty {
                        Text(recorder.liveNote.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(.label))
                    }
                    if !recorder.liveNote.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Key Points")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .textCase(.uppercase)
                            ForEach(recorder.liveNote.keyPoints, id: \.self) { pt in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(Color(.secondaryLabel))
                                    Text(pt).font(.system(size: 14)).foregroundStyle(Color(.label))
                                }
                            }
                        }
                    }
                    if !recorder.liveNote.scriptures.isEmpty {
                        FlowLayout(items: recorder.liveNote.scriptures) { ref in
                            Text(ref)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.purple.opacity(0.08), in: Capsule())
                        }
                    }
                    if !recorder.transcriptBuffer.isEmpty {
                        Text(recorder.transcriptBuffer.suffix(300))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .lineLimit(4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)

            Divider()

            // Controls
            HStack(spacing: 16) {
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if recorder.isRecording {
                    Button {
                        Task {
                            let draft = await recorder.stop()
                            onSave(draft)
                        }
                    } label: {
                        Label("Stop & Save", systemImage: "stop.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        try? recorder.start()
                    } label: {
                        Label("Start Recording", systemImage: "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.label), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var elapsedString: String {
        let mins = Int(recorder.elapsed) / 60
        let secs = Int(recorder.elapsed) % 60
        return String(format: "%d:%02d  Recording", mins, secs)
    }
}

// MARK: - FlowLayout (simple horizontal-wrapping layout for scripture chips)

private struct FlowLayout<T: Hashable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content

    var body: some View {
        // Simplified: horizontal scroll for chips
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
