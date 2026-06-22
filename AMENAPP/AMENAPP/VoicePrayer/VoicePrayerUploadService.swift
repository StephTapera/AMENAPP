// VoicePrayerUploadService.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Client service wrapping all six backend callables for voice comments.
// Backend owns all publish decisions. Client never sets moderation,
// intent, status, transcript, or summary.
//
// All callables require Firebase Auth + App Check (enforced server-side).

import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseStorage
import FirebaseFirestore

// MARK: - Error types

enum VoicePrayerError: Error, Equatable {
    case notAuthenticated
    case sessionCreationFailed(String)
    case uploadFailed(String)
    case finalizeFailed(String)
    case sensitiveContent
    case offTopicContent
    case moderationBlocked
    case fileTooLarge
    case unknown(String)
}

extension VoicePrayerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:         return "You must be signed in to share a voice prayer."
        case .sessionCreationFailed(let m): return "Could not start upload: \(m)"
        case .uploadFailed(let m):      return "Upload failed: \(m)"
        case .finalizeFailed(let m):    return "Could not finalize: \(m)"
        case .sensitiveContent:         return "Your recording may contain sensitive personal details."
        case .offTopicContent:          return "Voice comments must be prayers or testimonies."
        case .moderationBlocked:        return "Your recording could not be published at this time."
        case .fileTooLarge:             return "Recording exceeds the 25 MB size limit."
        case .unknown(let m):           return m
        }
    }
}

// MARK: - VoicePrayerUploadService

@MainActor
final class VoicePrayerUploadService: ObservableObject {
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var transcript: String = ""
    @Published private(set) var containsSensitiveDetails: Bool = false

    private static let functions = Functions.functions()
    private static let storage = Storage.storage()
    private static let db = Firestore.firestore()

    // MARK: - Full upload pipeline

    func upload(
        fileURL: URL,
        postId: String,
        type: VoiceCommentType,
        durationMs: Int,
        waveform: [Double],
        visibility: VoiceCommentVisibility
    ) async throws -> VoiceComment {
        guard Auth.auth().currentUser != nil else { throw VoicePrayerError.notAuthenticated }

        // 1. Validate file size
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        guard fileSize <= 25 * 1024 * 1024 else { throw VoicePrayerError.fileTooLarge }

        isUploading = true
        defer { isUploading = false }

        // 2. Create upload session
        let session = try await Self.createUploadSession(
            postId: postId,
            type: type,
            durationMs: durationMs
        )

        // 3. Upload audio to Firebase Storage
        uploadProgress = 0
        try await uploadAudio(fileURL: fileURL, storagePath: session.uploadPath)
        uploadProgress = 1.0

        // 4. Finalize — triggers backend transcription + moderation pipeline
        let comment = try await Self.finalize(
            voiceCommentId: session.voiceCommentId,
            postId: postId,
            type: type,
            durationMs: durationMs,
            waveform: waveform,
            visibility: visibility
        )

        return comment
    }

    // MARK: - Create upload session

    static func createUploadSession(
        postId: String,
        type: VoiceCommentType,
        durationMs: Int
    ) async throws -> VoicePrayerUploadSession {
        let callable = functions.httpsCallable("createVoicePrayerUploadSession")
        let result = try await callable.call([
            "postId":     postId,
            "type":       type.rawValue,
            "durationMs": durationMs
        ] as [String: Any])

        guard
            let data       = result.data as? [String: Any],
            let commentId  = data["voiceCommentId"] as? String,
            let path       = data["uploadPath"] as? String
        else {
            throw VoicePrayerError.sessionCreationFailed("Invalid server response")
        }
        return VoicePrayerUploadSession(
            voiceCommentId: commentId,
            uploadPath: path,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Upload audio

    private func uploadAudio(fileURL: URL, storagePath: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let ref = Self.storage.reference(withPath: storagePath)
            let metadata = StorageMetadata()
            metadata.contentType = "audio/m4a"

            let task = ref.putFile(from: fileURL, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: VoicePrayerError.uploadFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
            task.observe(.progress) { [weak self] snapshot in
                let pct = Double(snapshot.progress?.completedUnitCount ?? 0) /
                          Double(max(1, snapshot.progress?.totalUnitCount ?? 1))
                Task { @MainActor [weak self] in
                    self?.uploadProgress = pct
                }
            }
        }
    }

    // MARK: - Finalize

    static func finalize(
        voiceCommentId: String,
        postId: String,
        type: VoiceCommentType,
        durationMs: Int,
        waveform: [Double],
        visibility: VoiceCommentVisibility
    ) async throws -> VoiceComment {
        let callable = functions.httpsCallable("finalizeVoicePrayerComment")
        let result = try await callable.call([
            "voiceCommentId": voiceCommentId,
            "postId":         postId,
            "type":           type.rawValue,
            "durationMs":     durationMs,
            "waveform":       waveform,
            "visibility":     visibility.rawValue
        ] as [String: Any])

        guard let data = result.data as? [String: Any] else {
            throw VoicePrayerError.finalizeFailed("Invalid server response")
        }

        // Check backend decision
        let decision = data["decision"] as? String ?? ""
        if decision == "blocked" { throw VoicePrayerError.moderationBlocked }
        if decision == "off_topic" { throw VoicePrayerError.offTopicContent }

        // Build a minimal local VoiceComment from the response
        // (full doc arrives via Firestore listener; this is a receipt)
        return buildProcessingComment(
            id: voiceCommentId,
            postId: postId,
            type: type,
            durationMs: durationMs,
            waveform: waveform,
            visibility: visibility
        )
    }

    // MARK: - React

    static func react(
        voiceCommentId: String,
        postId: String,
        reaction: String,
        userId: String
    ) async throws {
        let callable = functions.httpsCallable("reactToVoicePrayerComment")
        _ = try await callable.call([
            "voiceCommentId": voiceCommentId,
            "postId":         postId,
            "reaction":       reaction
        ] as [String: Any])
    }

    // MARK: - Delete

    static func delete(voiceCommentId: String, postId: String) async throws {
        let callable = functions.httpsCallable("deleteVoicePrayerComment")
        _ = try await callable.call([
            "voiceCommentId": voiceCommentId,
            "postId":         postId
        ] as [String: Any])
    }

    // MARK: - Report

    static func report(voiceCommentId: String, postId: String, reason: String) async throws {
        let callable = functions.httpsCallable("reportVoicePrayerComment")
        _ = try await callable.call([
            "voiceCommentId": voiceCommentId,
            "postId":         postId,
            "reason":         reason
        ] as [String: Any])
    }

    // MARK: - Playback URL

    static func getPlaybackURL(storagePath: String) async throws -> URL {
        let callable = functions.httpsCallable("getVoicePrayerPlaybackURL")
        let result = try await callable.call(["storagePath": storagePath])
        guard
            let data = result.data as? [String: Any],
            let urlString = data["url"] as? String,
            let url = URL(string: urlString)
        else {
            throw VoicePrayerError.unknown("Could not obtain playback URL")
        }
        return url
    }

    // MARK: - Reset

    func reset() {
        isUploading = false
        uploadProgress = 0
        transcript = ""
        containsSensitiveDetails = false
    }

    // MARK: - Helpers

    private static func buildProcessingComment(
        id: String,
        postId: String,
        type: VoiceCommentType,
        durationMs: Int,
        waveform: [Double],
        visibility: VoiceCommentVisibility
    ) -> VoiceComment {
        let uid = Auth.auth().currentUser?.uid ?? ""
        // Construct a minimal struct; Firestore listener replaces it with the real doc.
        return VoiceComment(
            id_: id,
            postId_: postId,
            authorUid_: uid,
            type_: type,
            status_: .processing,
            audioStoragePath_: "",
            audioDurationMs_: durationMs,
            waveform_: waveform,
            visibility_: visibility
        )
    }
}

// MARK: - VoiceComment convenience init for local use

extension VoiceComment {
    init(
        id_: String,
        postId_: String,
        authorUid_: String,
        type_: VoiceCommentType,
        status_: VoiceCommentStatus,
        audioStoragePath_: String,
        audioDurationMs_: Int,
        waveform_: [Double],
        visibility_: VoiceCommentVisibility
    ) {
        self.id = id_
        self.postId = postId_
        self.parentCommentId = nil
        self.authorUid = authorUid_
        self.type = type_
        self.status = status_
        self.audioStoragePath = audioStoragePath_
        self.audioDurationMs = audioDurationMs_
        self.waveform = waveform_
        self.transcript = ""
        self.transcriptStatus = .pending
        self.summary = ""
        self.language = "en"
        self.moderation = nil
        self.intent = nil
        self.spiritualContext = nil
        self.visibility = visibility_
        self.counts = VoiceCommentCounts(prayed: 0, amen: 0, encourage: 0, replies: 0, reports: 0)
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
