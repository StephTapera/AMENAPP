//
//  Feature06_VoiceDevotional.swift
//  AMENAPP
//
//  Voice → Devotional — record a voice note, transcribe it with SFSpeechRecognizer,
//  then generate a 3-sentence devotional + verse via Anthropic.
//  Stores audio + devotional as fields on the message Firestore doc.
//

import SwiftUI
import AVFoundation
import Speech
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import FirebaseFunctions
import Combine

// MARK: - Model

struct VoiceDevotional: Codable {
    let title: String
    let text: String
    let verse: String
    let verseRef: String
}

// MARK: - Manager

final class VoiceDevotionalManager: NSObject, ObservableObject {
    static let shared = VoiceDevotionalManager()

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let db        = Firestore.firestore()
    private let storage   = Storage.storage()
    private let functions = Functions.functions()

    private var audioEngine   = AVAudioEngine()
    private var audioFile:     AVAudioFile?
    private var tempURL:       URL?

    private var recognizer:    SFSpeechRecognizer?
    private var recognitionReq: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private override init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()
    }

    // MARK: - Recording

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")

        guard let url = tempURL else { return }

        let format = inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async { self.isRecording = true }
        dlog("🎙️ [VoiceDevotional] Recording started")
    }

    func stopRecordingAndProcess(
        conversationId: String,
        messageId: String
    ) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        DispatchQueue.main.async {
            self.isRecording   = false
            self.isProcessing  = true
        }

        guard let url = tempURL else { return }

        Task {
            do {
                let transcript = try await transcribe(url: url)
                guard !transcript.isEmpty else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.errorMessage = "Could not transcribe audio."
                    }
                    return
                }

                let devotional = try await generateDevotional(from: transcript)
                let audioStorageURL = try await uploadAudio(url: url)

                try await saveToMessage(
                    conversationId: conversationId,
                    messageId: messageId,
                    devotional: devotional,
                    audioUrl: audioStorageURL,
                    transcript: transcript
                )

                await MainActor.run { self.isProcessing = false }
                dlog("✅ [VoiceDevotional] Saved to message \(messageId)")
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Private

    private func transcribe(_ url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            guard let recognizer, recognizer.isAvailable else {
                cont.resume(returning: "")
                return
            }
            let req = SFSpeechURLRecognitionRequest(url: url)
            req.shouldReportPartialResults = false
            recognizer.recognitionTask(with: req) { result, error in
                if let error { cont.resume(throwing: error); return }
                if let result, result.isFinal {
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private func generateDevotional(from transcript: String) async throws -> VoiceDevotional {
        let payload: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": "Based on this spoken voice note, write a short devotional (3 sentences max). Then suggest one Bible verse. Return only JSON: {\"title\": string, \"devotional\": string, \"verse\": string, \"verseRef\": string}. Voice note: '\(transcript.prefix(500))'"
            ]],
        ]

        let result = try await functions.httpsCallable("bereanGenericProxy").call(payload)
        guard let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONDecoder().decode(VoiceDevotional.self, from: data)
        else { throw NSError(domain: "VoiceDevotional", code: -1) }

        return json
    }

    private func uploadAudio(_ url: URL) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "Auth", code: -1) }
        let ref = storage.reference().child("voiceDevotionals/\(uid)/\(Int(Date().timeIntervalSince1970)).m4a")
        _ = try await ref.putFileAsync(from: url)
        return try await ref.downloadURL().absoluteString
    }

    private func saveToMessage(
        conversationId: String,
        messageId: String,
        devotional: VoiceDevotional,
        audioUrl: String,
        transcript: String
    ) async throws {
        let devotionalData: [String: Any] = [
            "title":    devotional.title,
            "text":     devotional.text,
            "verse":    devotional.verse,
            "verseRef": devotional.verseRef,
        ]

        try await db
            .collection("conversations").document(conversationId)
            .collection("messages").document(messageId)
            .updateData([
                "hasDevotional": true,
                "devotional":    devotionalData,
                "audioUrl":      audioUrl,
                "transcript":    transcript,
            ])
    }
}
