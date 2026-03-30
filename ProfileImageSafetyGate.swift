//
//  ProfileImageSafetyGate.swift
//  AMENAPP
//
//  Safety gate for profile photos and post images (public media).
//
//  Pipeline for every image being set as profile photo or attached to a post:
//    1. Image validity check (dimensions, format)
//    2. On-device pixel heuristic pre-screen (fast, no network)
//    3. Perceptual hash check against quarantined content (Firestore)
//    4. Server-side async deep scan (Cloud Vision via mediaScanQueue)
//
//  For post images, runs through the same MediaSafetyGateway pipeline
//  used for DMs but adapted for public-content context (no minor/mutual checks).
//
//  Hard rule: any CSAM signal → immediate account freeze.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Profile Image Safety Decision

enum ProfileImageSafetyDecision {
    /// Image is safe to upload.
    case allow

    /// Image passes pre-checks; upload proceeds but async scan will run.
    case allowWithAsyncScan(pHash: String)

    /// Image rejected — do not upload. Show user-facing reason.
    case reject(reason: String)

    /// Critical violation — freeze account immediately and do not upload.
    case freeze(reason: String)

    var blocksUpload: Bool {
        switch self {
        case .allow, .allowWithAsyncScan: return false
        default: return true
        }
    }
}

// MARK: - Profile Image Safety Gate

@MainActor
final class ProfileImageSafetyGate {
    static let shared = ProfileImageSafetyGate()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Primary Entry Point

    /// Evaluate a profile photo or post attachment before uploading to Firebase Storage.
    ///
    /// - Parameters:
    ///   - image: The image to evaluate.
    ///   - uploaderId: UID of the user uploading the image.
    ///   - context: Whether this is a profile photo or a post attachment.
    func evaluate(
        image: UIImage,
        uploaderId: String,
        context: ImageUploadContext
    ) async -> ProfileImageSafetyDecision {
        // 1. Basic validity
        guard let cgImage = image.cgImage,
              cgImage.width >= 50, cgImage.height >= 50 else {
            return .reject(reason: "Image format is not supported. Please choose a different photo.")
        }

        // 2. On-device pre-screen
        let prescreen = onDevicePreScreen(image: image, cgImage: cgImage)
        if prescreen.blocksUpload {
            if case .freeze(let reason) = prescreen {
                Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.freezeAccount(userId: uploaderId, reason: reason, context: context)
                }
            }
            return prescreen
        }

        // 3. Perceptual hash + known-bad content check
        let pHash = computePerceptualHash(image)
        let hashResult = await checkHashAgainstKnownContent(
            pHash: pHash,
            uploaderId: uploaderId,
            context: context
        )
        if hashResult.blocksUpload {
            if case .freeze(let reason) = hashResult {
                Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.freezeAccount(userId: uploaderId, reason: reason, context: context)
                }
            }
            return hashResult
        }

        // 4. Schedule async deep scan — upload allowed, scan runs post-upload
        return .allowWithAsyncScan(pHash: pHash)
    }

    // MARK: - Schedule Post-Upload Deep Scan

    /// Call this AFTER the image has been uploaded to Firebase Storage.
    /// The Cloud Function picks this up and runs Vision API moderation.
    func scheduleDeepScan(
        imageURL: String,
        pHash: String,
        uploaderId: String,
        context: ImageUploadContext,
        contentId: String  // postId or userId
    ) {
        Task.detached(priority: .background) { [weak self] in
            _ = try? await self?.db.collection("mediaScanQueue").addDocument(data: [
                "imageURL": imageURL,
                "pHash": pHash,
                "uploaderId": uploaderId,
                "context": context.rawValue,
                "contentId": contentId,
                "surface": context == .profilePhoto ? "profile_photo" : "post_attachment",
                "strictMode": false,   // Public images use standard thresholds
                "status": "pending",
                "requestedAt": FieldValue.serverTimestamp()
            ])
        }
    }

    // MARK: - On-Device Pre-Screen

    /// Fast pixel-statistics-based pre-screen. Catches obvious violations
    /// without any network calls. Not a full classifier — complements server scan.
    private func onDevicePreScreen(image: UIImage, cgImage: CGImage) -> ProfileImageSafetyDecision {
        // Reject extremely tiny images (thumbnail of larger illegal content pattern)
        if cgImage.width < 50 || cgImage.height < 50 {
            return .reject(reason: "Image resolution is too low.")
        }

        // Reject images with suspicious aspect ratios (some CSAM patterns)
        let aspectRatio = Double(cgImage.width) / Double(cgImage.height)
        if aspectRatio < 0.1 || aspectRatio > 10.0 {
            return .reject(reason: "Image format is not supported.")
        }

        // Check image is not all-black / uniform (potential obfuscation attempt)
        if isUniformColor(cgImage: cgImage) {
            return .reject(reason: "Image appears to be invalid. Please choose a different photo.")
        }

        return .allowWithAsyncScan(pHash: "")
    }

    /// Checks if the image is essentially a single flat color (obfuscation heuristic).
    private func isUniformColor(cgImage: CGImage) -> Bool {
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContext(size)
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let tCGImage = thumbnail?.cgImage,
              let data = tCGImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }

        let bytesPerPixel = tCGImage.bitsPerPixel / 8
        var rSum = 0, gSum = 0, bSum = 0
        var minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0

        for i in 0..<64 {
            let offset = i * bytesPerPixel
            let r = Int(bytes[offset])
            let g = Int(bytes[offset + 1])
            let b = Int(bytes[offset + 2])
            rSum += r; gSum += g; bSum += b
            minR = min(minR, r); maxR = max(maxR, r)
            minG = min(minG, g); maxG = max(maxG, g)
            minB = min(minB, b); maxB = max(maxB, b)
        }

        // Uniform if all channel ranges are < 15 (very little variation)
        return (maxR - minR) < 15 && (maxG - minG) < 15 && (maxB - minB) < 15
    }

    // MARK: - Perceptual Hash

    private func computePerceptualHash(_ image: UIImage) -> String {
        let size = CGSize(width: 32, height: 32)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = resized?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return UUID().uuidString
        }

        let bytesPerRow = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8
        var pixelValues = [UInt8](repeating: 0, count: 1024)

        for row in 0..<32 {
            for col in 0..<32 {
                let offset = row * bytesPerRow + col * bpp
                let r = Double(bytes[offset])
                let g = Double(bytes[min(offset + 1, Int(CFDataGetLength(data)) - 1)])
                let b = Double(bytes[min(offset + 2, Int(CFDataGetLength(data)) - 1)])
                pixelValues[row * 32 + col] = UInt8((r * 0.299 + g * 0.587 + b * 0.114))
            }
        }

        let average = Double(pixelValues.reduce(0) { $0 + Int($1) }) / 1024.0
        var hashBits = ""
        for pixel in pixelValues.prefix(64) {
            hashBits += Double(pixel) >= average ? "1" : "0"
        }

        var hexHash = ""
        stride(from: 0, to: hashBits.count, by: 4).forEach { i in
            let start = hashBits.index(hashBits.startIndex, offsetBy: i)
            let end = hashBits.index(start, offsetBy: min(4, hashBits.count - i))
            hexHash += String(Int(hashBits[start..<end], radix: 2) ?? 0, radix: 16)
        }
        return hexHash
    }

    // MARK: - Hash Check Against Known Content

    private func checkHashAgainstKnownContent(
        pHash: String,
        uploaderId: String,
        context: ImageUploadContext
    ) async -> ProfileImageSafetyDecision {
        do {
            // Check quarantined content database
            let snapshot = try await db
                .collection("quarantinedContentHashes")
                .whereField("pHash", isEqualTo: pHash)
                .limit(to: 1)
                .getDocuments()

            if let match = snapshot.documents.first {
                let isIllegal = match.data()["isIllegal"] as? Bool ?? false
                let severity = match.data()["severity"] as? String ?? "medium"

                if isIllegal {
                    return .freeze(
                        reason: "Image identified as prohibited content. Account suspended pending review."
                    )
                }
                if severity == "high" {
                    return .reject(reason: "This image cannot be uploaded.")
                }
                return .reject(reason: "This image has been flagged by our safety system.")
            }
        } catch {
            // Hash check failed — proceed with async scan (fail open for hashing)
        }

        return .allow
    }

    // MARK: - Account Freeze

    private func freezeAccount(userId: String, reason: String, context: ImageUploadContext) async {
        guard !userId.isEmpty else { return }

        _ = try? await db.collection("userSafetyRecords").document(userId).setData([
            "accountStatus": "frozen",
            "frozenUntil": 0,
            "frozenReason": reason,
            "requiresManualReview": true,
            "frozenAt": FieldValue.serverTimestamp()
        ], merge: true)

        _ = try? await db.collection("moderationQueue").addDocument(data: [
            "uploaderId": userId,
            "decision": "freeze_account",
            "reason": reason,
            "mediaType": context.rawValue,
            "priorityLevel": 5,
            "status": "pending_review",
            "createdAt": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - Image Upload Context

enum ImageUploadContext: String {
    case profilePhoto   = "profile_photo"
    case postAttachment = "post_attachment"
    case commentAttachment = "comment_attachment"
    case churchNoteAttachment = "church_note_attachment"
}
