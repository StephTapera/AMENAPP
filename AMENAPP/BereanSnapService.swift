// BereanSnapService.swift
// AMENAPP
//
// Sermon Snap pipeline:
//   UIImage → Firebase Storage (berean/ocr_queue/{uid}/{ts}.jpg, 15-min TTL tag)
//           → sermonSnapProxy Cloud Function (Claude multimodal vision)
//           → JSON parse → SermonNote → ChurchNote saved via ChurchNotesService

import Foundation
import UIKit
import Combine
import FirebaseAuth
import FirebaseStorage
import FirebaseFunctions

// MARK: - Models

struct SermonNoteJSON: Codable {
    var title: String
    var scriptures: [String]
    var keyPoints: [String]
    var rawText: String

    private enum CodingKeys: String, CodingKey {
        case title, scriptures, keyPoints, rawText
    }

    // Tolerant decode: missing fields fall back to empty defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title      = (try? c.decode(String.self,   forKey: .title))      ?? ""
        scriptures = (try? c.decode([String].self, forKey: .scriptures)) ?? []
        keyPoints  = (try? c.decode([String].self, forKey: .keyPoints))  ?? []
        rawText    = (try? c.decode(String.self,   forKey: .rawText))    ?? ""
    }

    init(title: String = "", scriptures: [String] = [], keyPoints: [String] = [], rawText: String = "") {
        self.title = title; self.scriptures = scriptures
        self.keyPoints = keyPoints; self.rawText = rawText
    }
}

// MARK: - BereanSnapService

@MainActor
final class BereanSnapService: ObservableObject {
    static let shared = BereanSnapService()

    @Published var isProcessing = false
    @Published var processingStage: ProcessingStage = .idle

    enum ProcessingStage: String {
        case idle        = ""
        case uploading   = "Uploading image…"
        case analyzing   = "Analyzing with Claude…"
        case saving      = "Saving note…"
        case done        = "Done"
    }

    private let functions = Functions.functions()
    private let storage   = Storage.storage()

    // MARK: - Main entry point

    /// Full pipeline: upload image → call Claude vision → return parsed ChurchNote draft.
    /// The caller is responsible for showing the preview sheet and calling
    /// ChurchNotesService.createNote() after user approval.
    func processSermonImage(_ image: UIImage) async throws -> ChurchNote {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SnapError.unauthenticated
        }

        // 1. Upload to Storage with TTL metadata tag
        processingStage = .uploading
        let imageURL = try await uploadImage(image, uid: uid)

        // 2. Call Claude vision via sermonSnapProxy Cloud Function
        processingStage = .analyzing
        let json = try await callVisionProxy(image: image)

        // 3. Map to ChurchNote draft (unsaved — caller saves after approval)
        processingStage = .saving
        let note = ChurchNote(
            userId:             uid,
            title:              json.title.isEmpty ? "Sermon Notes" : json.title,
            date:               Date(),
            content:            json.rawText,
            keyPoints:          json.keyPoints,
            tags:               [],
            scriptureReferences: json.scriptures,
            sourceImageURL:     imageURL
        )
        processingStage = .done
        return note
    }

    // MARK: - Firebase Storage upload

    private func uploadImage(_ image: UIImage, uid: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw SnapError.imageEncodingFailed
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "berean/ocr_queue/\(uid)/\(timestamp).jpg"
        let ref  = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        // Tag for 15-min auto-delete lifecycle rule set in Firebase console
        metadata.customMetadata = ["ttl": "900", "purpose": "sermon_ocr"]

        return try await withCheckedThrowingContinuation { continuation in
            let task = ref.putData(data, metadata: metadata)
            task.observe(.success) { _ in
                ref.downloadURL { url, error in
                    if let url { continuation.resume(returning: url.absoluteString) }
                    else { continuation.resume(throwing: error ?? SnapError.uploadFailed) }
                }
            }
            task.observe(.failure) { snap in
                continuation.resume(throwing: snap.error ?? SnapError.uploadFailed)
            }
        }
    }

    // MARK: - Claude vision via Cloud Function

    private func callVisionProxy(image: UIImage) async throws -> SermonNoteJSON {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw SnapError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()

        let prompt = """
        This is a photo of a church sermon slide or screen.
        Extract ALL visible text. Then return JSON with these exact keys:
        {
          "title": "sermon title if visible, else empty string",
          "scriptures": ["John 3:16", ...],
          "keyPoints": ["point 1", ...],
          "rawText": "all extracted text verbatim"
        }
        Return ONLY valid JSON. No markdown, no explanation, no code fences.
        """

        let callable = functions.httpsCallable("sermonSnapProxy")
        let params: [String: Any] = [
            "base64Image": base64,
            "prompt":      prompt
        ]

        let result = try await callable.call(params)
        guard let data = result.data as? [String: Any],
              let text = data["text"] as? String else {
            throw SnapError.invalidResponse
        }

        // Strip any accidental markdown code fences
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw SnapError.jsonParseFailed
        }

        // Best-effort decode — missing fields fall back to empty defaults
        let decoded = (try? JSONDecoder().decode(SermonNoteJSON.self, from: jsonData))
            ?? SermonNoteJSON(rawText: text)

        return decoded
    }

    // MARK: - Errors

    enum SnapError: LocalizedError {
        case unauthenticated, imageEncodingFailed, uploadFailed, invalidResponse, jsonParseFailed

        var errorDescription: String? {
            switch self {
            case .unauthenticated:    return "Sign in to use Sermon Snap."
            case .imageEncodingFailed: return "Could not process this image."
            case .uploadFailed:       return "Image upload failed. Check your connection."
            case .invalidResponse:    return "Unexpected response from server."
            case .jsonParseFailed:    return "Could not parse sermon data."
            }
        }
    }
}

// MARK: - ChurchNote extension for sourceImageURL

// ChurchNote already has scriptureReferences, keyPoints, content, title.
// We extend with a computed helper to carry the source image URL in the
// note's `content` metadata line (avoids schema change for this field).
private extension ChurchNote {
    init(userId: String, title: String, date: Date, content: String,
         keyPoints: [String], tags: [String], scriptureReferences: [String],
         sourceImageURL: String?) {
        self.init(
            userId:              userId,
            title:               title,
            date:                date,
            content:             content,
            keyPoints:           keyPoints,
            tags:                tags,
            scriptureReferences: scriptureReferences
        )
        // Store sourceImageURL in claudeTags as a tagged value until schema adds the field
        if let url = sourceImageURL {
            self.claudeTags = ["sourceImage:\(url)"]
        }
    }
}
