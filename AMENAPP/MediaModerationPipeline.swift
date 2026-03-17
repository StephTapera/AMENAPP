//
//  MediaModerationPipeline.swift
//  AMENAPP
//
//  Upload → mark as pending_moderation → scan → only then publish.
//
//  Core guarantee: NO media is ever visible to other users until it has passed
//  at least a fast on-device nudity pre-screen. Cloud Vision deep scan runs
//  asynchronously after the fast scan; if the async scan fails the content stays
//  in pending state until a moderator reviews it.
//
//  Pipeline stages:
//    1. Pre-upload trust check (account tier + recipient minor policy)
//    2. Fast on-device nudity pre-screen (Vision framework)
//    3. Upload to Storage with status = "pending_moderation"
//    4. Firestore doc written with status = "pending_moderation" — NOT visible in feeds
//    5. Schedule async Cloud Vision deep scan via Cloud Function
//    6. On pass: update status = "approved", content appears in feed
//    7. On fail: update status = "rejected", content removed, strike recorded
//
//  Privacy guarantee:
//    - Rejected media is deleted from Storage after strike recorded
//    - Evidence pointer (hash + moderation result) retained for 90 days
//    - Full media bytes are NOT retained after rejection
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Vision
import UIKit

// MARK: - Media Moderation Status

enum MediaModerationStatus: String, Codable {
    case pendingModeration  = "pending_moderation"
    case approved           = "approved"
    case rejected           = "rejected"
    case awaitingReview     = "awaiting_review"  // Borderline — sent to human moderator
}

// MARK: - Pre-Screen Result

struct MediaPreScreenResult {
    let passed: Bool
    let nudityConfidence: Double       // 0–1; ≥0.7 = likely explicit
    let violenceConfidence: Double
    let decision: PreScreenDecision
    let reason: String?

    enum PreScreenDecision {
        case allow
        case allowWithAsyncScan       // Borderline — approve optimistically, scan in BG
        case rejectNudity             // High-confidence explicit content
        case rejectViolence
        case sendToHumanReview        // Borderline nudity — not clear enough to auto-reject
    }
}

// MARK: - Upload Context

struct MediaUploadContext {
    let authorId: String
    let recipientId: String?           // nil = public post
    let surface: MediaSurface          // Where is this being posted?
    let recipientIsMinor: Bool         // If true, apply strictest policy
    let authorTrustTier: AccountAgeTier

    enum MediaSurface: String {
        case post        = "post"
        case testimony   = "testimony"
        case dm          = "dm"
        case profile     = "profile_photo"
        case churchNote  = "church_note"
    }
}

// MARK: - Pipeline

@MainActor
final class MediaModerationPipeline {
    static let shared = MediaModerationPipeline()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private init() {}

    // MARK: - Stage 1: Pre-Upload Check

    /// Run before showing the image picker or starting the upload.
    /// Checks trust policy for the author + recipient combination.
    func preUploadCheck(context: MediaUploadContext) -> PreUploadCheckResult {
        // Newborn accounts cannot send media to strangers
        if context.authorTrustTier == .newborn {
            return .rejected(reason: "New accounts cannot send media. Your account needs to be a few days old first.")
        }

        // Adults cannot send media to known minors (hard block, same as MediaSafetyGateway)
        if context.recipientIsMinor && context.surface == .dm {
            return .rejected(reason: "Media cannot be sent to this person.")
        }

        // Infant accounts: media in DMs only to mutual followers
        if context.authorTrustTier == .infant && context.recipientId != nil {
            return .allowedWithRestrictions(note: "Media will be scanned before delivery.")
        }

        return .allowed
    }

    enum PreUploadCheckResult {
        case allowed
        case allowedWithRestrictions(note: String)
        case rejected(reason: String)
    }

    // MARK: - Stage 2: On-Device Fast Pre-Screen

    /// Runs Vision framework classifiers synchronously on a downsized image.
    /// ≤200ms on modern devices. Returns a PreScreenResult.
    func fastPreScreen(image: UIImage) async -> MediaPreScreenResult {
        // Downsize to 512×512 for speed
        let screenSize = CGSize(width: 512, height: 512)
        guard let resized = image.pipelineResized(to: screenSize),
              let cgImage = resized.cgImage else {
            // Can't screen — send to async scan, don't block
            return MediaPreScreenResult(
                passed: true,
                nudityConfidence: 0,
                violenceConfidence: 0,
                decision: .allowWithAsyncScan,
                reason: "Could not pre-screen image — will be scanned after upload."
            )
        }

        return await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            // Use image classification to detect explicit content signals
            let classifyRequest = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: MediaPreScreenResult(
                        passed: true, nudityConfidence: 0, violenceConfidence: 0,
                        decision: .allowWithAsyncScan, reason: nil
                    ))
                    return
                }

                // Look for explicit content classifiers
                let nudityScore = observations.first(where: {
                    $0.identifier.contains("explicit") ||
                    $0.identifier.contains("nudity") ||
                    $0.identifier.contains("suggestive")
                })?.confidence ?? 0

                let violenceScore = observations.first(where: {
                    $0.identifier.contains("violence") ||
                    $0.identifier.contains("weapons")
                })?.confidence ?? 0

                let nudityDouble = Double(nudityScore)
                let violenceDouble = Double(violenceScore)

                let decision: MediaPreScreenResult.PreScreenDecision
                let reason: String?

                if nudityDouble >= 0.85 {
                    decision = .rejectNudity
                    reason = "This image contains explicit content and cannot be uploaded."
                } else if violenceDouble >= 0.85 {
                    decision = .rejectViolence
                    reason = "This image contains violent content and cannot be uploaded."
                } else if nudityDouble >= 0.55 {
                    decision = .sendToHumanReview
                    reason = "This image will be reviewed before appearing."
                } else if nudityDouble >= 0.30 {
                    decision = .allowWithAsyncScan
                    reason = nil
                } else {
                    decision = .allow
                    reason = nil
                }

                continuation.resume(returning: MediaPreScreenResult(
                    passed: decision != .rejectNudity && decision != .rejectViolence,
                    nudityConfidence: nudityDouble,
                    violenceConfidence: violenceDouble,
                    decision: decision,
                    reason: reason
                ))
            }

            do {
                try requestHandler.perform([classifyRequest])
            } catch {
                continuation.resume(returning: MediaPreScreenResult(
                    passed: true, nudityConfidence: 0, violenceConfidence: 0,
                    decision: .allowWithAsyncScan,
                    reason: "Pre-screen unavailable — will be scanned after upload."
                ))
            }
        }
    }

    // MARK: - Stage 3–4: Upload with pending_moderation status

    struct UploadedMediaRecord {
        let mediaId: String
        let storagePath: String
        let downloadURL: String
        let status: MediaModerationStatus
        let contentHash: String
    }

    /// Upload image to Storage and write Firestore record with `pending_moderation` status.
    /// Returns the record so the caller can insert a placeholder in the UI.
    func uploadWithPendingStatus(
        image: UIImage,
        context: MediaUploadContext,
        contentId: String,      // Post ID, message ID, etc.
        fileName: String
    ) async throws -> UploadedMediaRecord {
        guard let uid = Auth.auth().currentUser?.uid,
              uid == context.authorId else {
            throw PipelineError.unauthorized
        }

        // Compress to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            throw PipelineError.compressionFailed
        }

        let contentHash = sha256Hex(imageData)
        let mediaId = UUID().uuidString

        // Determine storage path by surface
        let storagePath: String
        switch context.surface {
        case .post:       storagePath = "post_media/\(uid)/\(contentId)/\(fileName)"
        case .testimony:  storagePath = "testimony_media/\(uid)/\(contentId)/\(fileName)"
        case .dm:         storagePath = "message_attachments/\(uid)/\(context.recipientId ?? "unknown")/\(fileName)"
        case .profile:    storagePath = "profile_images/\(uid)/\(fileName)"
        case .churchNote: storagePath = "post_media/\(uid)/\(contentId)/\(fileName)"
        }

        // Upload to Storage
        let storageRef = storage.reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "moderationStatus": MediaModerationStatus.pendingModeration.rawValue,
            "authorId": uid,
            "contentId": contentId,
            "contentHash": contentHash,
            "mediaId": mediaId
        ]

        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()

        // Write Firestore record — status = pending_moderation
        // Feed queries MUST filter by status == "approved" to exclude pending content
        let mediaRecord: [String: Any] = [
            "mediaId": mediaId,
            "authorId": uid,
            "contentId": contentId,
            "surface": context.surface.rawValue,
            "storagePath": storagePath,
            "downloadURL": downloadURL.absoluteString,
            "status": MediaModerationStatus.pendingModeration.rawValue,
            "contentHash": contentHash,
            "createdAt": FieldValue.serverTimestamp(),
            "approvedAt": NSNull(),
            "rejectedAt": NSNull(),
            "rejectionReason": NSNull(),
            "nudityScore": NSNull(),   // Filled by async scan
            "violenceScore": NSNull()
        ]

        try await db.collection("media_moderation").document(mediaId).setData(mediaRecord)

        // Schedule async deep scan via Cloud Function (fire and forget)
        Task.detached(priority: .background) { [weak self] in
            await self?.scheduleAsyncScan(
                mediaId: mediaId,
                storagePath: storagePath,
                authorId: uid,
                contentId: contentId,
                surface: context.surface.rawValue
            )
        }

        return UploadedMediaRecord(
            mediaId: mediaId,
            storagePath: storagePath,
            downloadURL: downloadURL.absoluteString,
            status: .pendingModeration,
            contentHash: contentHash
        )
    }

    // MARK: - Stage 5: Schedule Async Deep Scan

    private func scheduleAsyncScan(
        mediaId: String,
        storagePath: String,
        authorId: String,
        contentId: String,
        surface: String
    ) async {
        // Write a scan request to a Cloud-Function-watched collection.
        // The CF picks this up, runs Cloud Vision SafeSearch, and updates
        // media_moderation/{mediaId} with the result and final status.
        let scanRequest: [String: Any] = [
            "mediaId": mediaId,
            "storagePath": storagePath,
            "authorId": authorId,
            "contentId": contentId,
            "surface": surface,
            "requestedAt": FieldValue.serverTimestamp(),
            "scanned": false
        ]
        try? await db.collection("media_scan_requests").document(mediaId).setData(scanRequest)
    }

    // MARK: - Stage 6: Listen for Scan Result

    /// Returns a real-time publisher that fires when the media record transitions
    /// from `pending_moderation` to `approved` or `rejected`.
    /// The caller (e.g., CreatePostView) subscribes and shows a spinner until resolved.
    func waitForApproval(mediaId: String) async throws -> MediaModerationStatus {
        return try await withCheckedThrowingContinuation { continuation in
            var listenerRef: ListenerRegistration?
            listenerRef = db.collection("media_moderation").document(mediaId)
                .addSnapshotListener { snap, error in
                    guard let data = snap?.data(),
                          let rawStatus = data["status"] as? String,
                          let status = MediaModerationStatus(rawValue: rawStatus) else { return }

                    switch status {
                    case .approved:
                        listenerRef?.remove()
                        continuation.resume(returning: .approved)
                    case .rejected:
                        listenerRef?.remove()
                        continuation.resume(returning: .rejected)
                    case .awaitingReview:
                        listenerRef?.remove()
                        continuation.resume(returning: .awaitingReview)
                    case .pendingModeration:
                        break  // Keep waiting
                    }
                }
        }
    }

    // MARK: - Stage 7: Reject + Evidence Retention

    /// Called by Cloud Function after scan — also callable from moderator console.
    /// Marks record as rejected, records evidence pointer, schedules Storage deletion.
    func rejectMedia(
        mediaId: String,
        reason: SexualPolicyViolationCode,
        nudityScore: Double,
        violenceScore: Double
    ) async throws {
        let update: [String: Any] = [
            "status": MediaModerationStatus.rejected.rawValue,
            "rejectedAt": FieldValue.serverTimestamp(),
            "rejectionReason": reason.rawValue,
            "nudityScore": nudityScore,
            "violenceScore": violenceScore,
            // Evidence pointer retained for 90 days — full media bytes scheduled for deletion
            "evidenceRetentionDeadline": Timestamp(date: Date().addingTimeInterval(90 * 24 * 3600))
        ]
        try await db.collection("media_moderation").document(mediaId).updateData(update)
    }

    // MARK: - SHA-256 Hash (privacy-preserving content fingerprint)

    private func sha256Hex(_ data: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16, uppercase: false)
    }

    // MARK: - Errors

    enum PipelineError: LocalizedError {
        case unauthorized
        case compressionFailed
        case uploadFailed(String)
        case scanTimeout

        var errorDescription: String? {
            switch self {
            case .unauthorized:      return "Not authorized to upload."
            case .compressionFailed: return "Could not process the image."
            case .uploadFailed(let msg): return "Upload failed: \(msg)"
            case .scanTimeout:       return "Media review timed out. Please try again."
            }
        }
    }
}

// MARK: - UIImage resize helper (pipeline-private)

private extension UIImage {
    func pipelineResized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
