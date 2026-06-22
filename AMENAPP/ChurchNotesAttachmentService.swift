//
//  ChurchNotesAttachmentService.swift
//  AMENAPP
//
//  Feature 7: Attachments + Document Scanning
//  Handles photo, PDF, bulletin, and scanned-document attachments.
//  Uploads to Firebase Storage, persists metadata to Firestore.
//  OCR via Vision framework on scanned pages.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Vision
import VisionKit
import Combine

// MARK: - Attachment Type

enum AttachmentType: String, Codable, CaseIterable, Identifiable {
    case photo    = "photo"
    case scan     = "scan"
    case pdf      = "pdf"
    case bulletin = "bulletin"
    case setlist  = "setlist"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo:    return "Photo"
        case .scan:     return "Scanned Document"
        case .pdf:      return "PDF"
        case .bulletin: return "Church Bulletin"
        case .setlist:  return "Worship Set List"
        }
    }

    var systemImage: String {
        switch self {
        case .photo:    return "photo"
        case .scan:     return "doc.viewfinder"
        case .pdf:      return "doc.fill"
        case .bulletin: return "newspaper"
        case .setlist:  return "music.note.list"
        }
    }

    var mimeType: String {
        switch self {
        case .photo, .scan:  return "image/jpeg"
        case .pdf, .bulletin, .setlist: return "application/pdf"
        }
    }
}

// MARK: - Note Attachment

struct NoteAttachment: Identifiable, Codable, Hashable {
    var id: String
    var noteId: String
    var type: AttachmentType
    var url: String
    var thumbnailURL: String?
    var fileName: String
    var fileSize: Int          // bytes
    var ocrText: String?       // extracted text from scan
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        noteId: String,
        type: AttachmentType,
        url: String,
        thumbnailURL: String? = nil,
        fileName: String,
        fileSize: Int,
        ocrText: String? = nil
    ) {
        self.id           = id
        self.noteId       = noteId
        self.type         = type
        self.url          = url
        self.thumbnailURL = thumbnailURL
        self.fileName     = fileName
        self.fileSize     = fileSize
        self.ocrText      = ocrText
        self.createdAt    = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, noteId, type, url, thumbnailURL, fileName, fileSize, ocrText, createdAt
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        noteId        = try c.decodeIfPresent(String.self, forKey: .noteId) ?? ""
        type          = try c.decodeIfPresent(AttachmentType.self, forKey: .type) ?? .photo
        url           = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        thumbnailURL  = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        fileName      = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileSize      = try c.decodeIfPresent(Int.self, forKey: .fileSize) ?? 0
        ocrText       = try c.decodeIfPresent(String.self, forKey: .ocrText)
        createdAt     = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - Attachment Service

@MainActor
final class ChurchNotesAttachmentService: ObservableObject {
    static let shared = ChurchNotesAttachmentService()

    @Published var attachmentsByNote: [String: [NoteAttachment]] = [:]
    @Published var isUploading  = false
    @Published var uploadProgress: Double = 0
    @Published var lastError: Error?

    private let db      = Firestore.firestore()
    private lazy var storage = Storage.storage()

    private init() {}

    // MARK: - Firestore Path

    private func attachmentsRef(noteId: String, userId: String) -> CollectionReference {
        db.collection("users")
          .document(userId)
          .collection("churchNotes")
          .document(noteId)
          .collection("attachments")
    }

    // MARK: - Upload

    /// Uploads image/PDF data to Firebase Storage and records metadata in Firestore.
    func uploadAttachment(
        data: Data,
        type: AttachmentType,
        noteId: String,
        fileName: String? = nil
    ) async throws -> NoteAttachment {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AttachmentError.notAuthenticated
        }

        isUploading    = true
        uploadProgress = 0
        defer { isUploading = false; uploadProgress = 0 }

        let attachmentId = UUID().uuidString
        let resolvedName = fileName ?? "\(attachmentId).\(type == .pdf ? "pdf" : "jpg")"

        // Storage path: churchNotes/{noteId}/attachments/{attachmentId}/{fileName}
        let storagePath  = "churchNotes/\(noteId)/attachments/\(attachmentId)/\(resolvedName)"
        let ref          = storage.reference().child(storagePath)

        let metadata          = StorageMetadata()
        metadata.contentType  = type.mimeType

        // Use resumable upload and track progress
        let downloadURL: URL = try await withCheckedThrowingContinuation { cont in
            let task = ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                ref.downloadURL { url, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let url else { cont.resume(throwing: AttachmentError.uploadFailed); return }
                    cont.resume(returning: url)
                }
            }
            task.observe(.progress) { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self, let progress = snapshot.progress else { return }
                    self.uploadProgress = progress.fractionCompleted
                }
            }
        }

        // Generate thumbnail for images
        var thumbnailURL: String? = nil
        if type == .photo || type == .scan, let image = UIImage(data: data) {
            if let thumbData = thumbnail(for: image)?.jpegData(compressionQuality: 0.6) {
                let thumbPath = "churchNotes/\(noteId)/attachments/\(attachmentId)/thumb_\(resolvedName)"
                let thumbRef  = storage.reference().child(thumbPath)
                if let thumbURL = try? await uploadDataReturningURL(thumbData, to: thumbRef, contentType: "image/jpeg") {
                    thumbnailURL = thumbURL.absoluteString
                }
            }
        }

        // OCR for scans
        var ocrText: String? = nil
        if type == .scan, let image = UIImage(data: data), let cg = image.cgImage {
            ocrText = await extractText(from: cg)
        }

        let attachment = NoteAttachment(
            id:           attachmentId,
            noteId:       noteId,
            type:         type,
            url:          downloadURL.absoluteString,
            thumbnailURL: thumbnailURL,
            fileName:     resolvedName,
            fileSize:     data.count,
            ocrText:      ocrText
        )

        // Persist metadata to Firestore
        let docRef   = attachmentsRef(noteId: noteId, userId: uid).document(attachmentId)
        let encoded  = try Firestore.Encoder().encode(attachment)
        try await docRef.setData(encoded)

        // Update note's attachmentCount
        try await incrementAttachmentCount(noteId: noteId, userId: uid)

        var current = attachmentsByNote[noteId] ?? []
        current.append(attachment)
        attachmentsByNote[noteId] = current

        return attachment
    }

    // MARK: - Delete

    func deleteAttachment(_ attachment: NoteAttachment) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AttachmentError.notAuthenticated
        }

        // Delete from Storage
        let storagePath = "churchNotes/\(attachment.noteId)/attachments/\(attachment.id)"
        let folderRef   = storage.reference().child(storagePath)
        // Best effort — ignore errors if file already gone
        try? await folderRef.child(attachment.fileName).delete()
        if let thumb = attachment.thumbnailURL,
           let thumbName = URL(string: thumb)?.lastPathComponent {
            try? await folderRef.child(thumbName).delete()
        }

        // Delete Firestore metadata
        let docRef = attachmentsRef(noteId: attachment.noteId, userId: uid).document(attachment.id)
        try await docRef.delete()

        // Decrement attachment count
        let noteRef = db.collection("users").document(uid)
            .collection("churchNotes").document(attachment.noteId)
        try await noteRef.updateData(["attachmentCount": FieldValue.increment(Int64(-1))])

        attachmentsByNote[attachment.noteId]?.removeAll { $0.id == attachment.id }
    }

    // MARK: - Get Attachments

    func getAttachments(for noteId: String) -> [NoteAttachment] {
        attachmentsByNote[noteId] ?? []
    }

    func loadAttachments(for noteId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await attachmentsRef(noteId: noteId, userId: uid)
                .order(by: "createdAt")
                .getDocuments()
            let items = snapshot.documents.compactMap { try? $0.data(as: NoteAttachment.self) }
            attachmentsByNote[noteId] = items
        } catch {
            lastError = error
        }
    }

    // MARK: - Vision OCR

    /// Extracts text from a CGImage using Vision's VNRecognizeTextRequest.
    func extractText(from cgImage: CGImage) async -> String {
        await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                cont.resume(returning: text)
            }
            request.recognitionLevel   = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Helpers

    private func thumbnail(for image: UIImage) -> UIImage? {
        let targetSize = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func uploadDataReturningURL(_ data: Data, to ref: StorageReference, contentType: String) async throws -> URL {
        let meta = StorageMetadata()
        meta.contentType = contentType
        return try await withCheckedThrowingContinuation { cont in
            ref.putData(data, metadata: meta) { _, error in
                if let error { cont.resume(throwing: error); return }
                ref.downloadURL { url, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let url else { cont.resume(throwing: AttachmentError.uploadFailed); return }
                    cont.resume(returning: url)
                }
            }
        }
    }

    private func incrementAttachmentCount(noteId: String, userId: String) async throws {
        let ref = db.collection("users").document(userId)
            .collection("churchNotes").document(noteId)
        try await ref.updateData(["attachmentCount": FieldValue.increment(Int64(1))])
    }
}

// MARK: - Document Scanner Coordinator

/// Bridges VNDocumentCameraViewController into SwiftUI.
/// Provides OCR on each scanned page and returns extracted text to the caller.
final class DocumentScannerCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {

    var onCompletion: ((String, [UIImage]) -> Void)?
    var onCancellation: (() -> Void)?

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard self != nil else { return }
            var accumulatedText = ""
            var collectedPages: [UIImage] = []

            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                collectedPages.append(image)

                if let cg = image.cgImage {
                    let service = await ChurchNotesAttachmentService.shared
                    let text    = await service.extractText(from: cg)
                    if !text.isEmpty {
                        accumulatedText += (accumulatedText.isEmpty ? "" : "\n\n") + text
                    }
                }
            }
            let finalText = accumulatedText
            let finalPages = collectedPages
            await MainActor.run { [weak self] in
                self?.onCompletion?(finalText, finalPages)
            }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        onCancellation?()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
        onCancellation?()
    }
}

// MARK: - Errors

enum AttachmentError: LocalizedError {
    case notAuthenticated
    case uploadFailed
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to upload attachments."
        case .uploadFailed:     return "Attachment upload failed. Please try again."
        case .fileTooLarge:     return "File is too large. Maximum size is 25 MB."
        }
    }
}
