// VoiceNoteService.swift — AMEN IntegrationOS
// Actor that calls the `transcribeVoiceNote` Cloud Function.
// Storage path must start with voiceNotes/{uid}/

import Foundation
import FirebaseFunctions
import FirebaseAuth
import FirebaseStorage
import FirebaseRemoteConfig

actor VoiceNoteService {
    static let shared = VoiceNoteService()
    private init() {}

    private let functions = Functions.functions()
    private let storage = Storage.storage()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_messaging_enabled").booleanValue }

    struct TranscriptionResult {
        let storagePath: String
        let transcript: String
        let durationSeconds: Double
        let language: String
        let confidence: Double
    }

    // MARK: - Upload + Transcribe

    func uploadAndTranscribe(localFileURL: URL, fileName: String) async throws -> TranscriptionResult {
        guard isEnabled else { throw IntegrationOSError.providerUnavailable("transcribeVoiceNote") }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        // Enforce storage path security
        let storagePath = "voiceNotes/\(uid)/\(fileName)"
        guard storagePath.hasPrefix("voiceNotes/\(uid)/") else {
            throw IntegrationOSError.invalidStoragePath
        }

        // Upload to Firebase Storage
        let ref = storage.reference(withPath: storagePath)
        let data = try Data(contentsOf: localFileURL)
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"
        _ = try await ref.putDataAsync(data, metadata: metadata)

        // Call CF with storage path only — never raw audio data
        let result = try await functions.httpsCallable("transcribeVoiceNote").call([
            "storagePath": storagePath,
            "uid": uid
        ])

        guard let responseData = result.data as? [String: Any],
              let transcript = responseData["transcript"] as? String else {
            throw IntegrationOSError.providerUnavailable("transcribeVoiceNote")
        }

        return TranscriptionResult(
            storagePath: storagePath,
            transcript: transcript,
            durationSeconds: responseData["durationSeconds"] as? Double ?? 0,
            language: responseData["language"] as? String ?? "en",
            confidence: responseData["confidence"] as? Double ?? 0
        )
    }

    // MARK: - Transcribe Existing

    func transcribeExisting(storagePath: String) async throws -> TranscriptionResult {
        guard isEnabled else { throw IntegrationOSError.providerUnavailable("transcribeVoiceNote") }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        // Validate path ownership
        guard storagePath.hasPrefix("voiceNotes/\(uid)/") else {
            throw IntegrationOSError.invalidStoragePath
        }

        let result = try await functions.httpsCallable("transcribeVoiceNote").call([
            "storagePath": storagePath,
            "uid": uid
        ])

        guard let responseData = result.data as? [String: Any],
              let transcript = responseData["transcript"] as? String else {
            throw IntegrationOSError.providerUnavailable("transcribeVoiceNote")
        }

        return TranscriptionResult(
            storagePath: storagePath,
            transcript: transcript,
            durationSeconds: responseData["durationSeconds"] as? Double ?? 0,
            language: responseData["language"] as? String ?? "en",
            confidence: responseData["confidence"] as? Double ?? 0
        )
    }
}
