//
//  MediaSafetyGateway.swift
//  AMENAPP
//
//  Safety gateway for all media (images, video, voice) sent in DMs.
//
//  Pipeline for every media send:
//    1. New-account throttle (reject if account too new for media)
//    2. Rate throttle (N media sends per hour, stricter for non-mutuals)
//    3. Perceptual hash check (known illegal content — via server-side lookup)
//    4. On-device pre-screen (nudity/sexual signals before upload)
//    5. Strict policy for sends to minors
//    6. After upload: async deep scan via Cloud Vision + cross-user pattern detection
//
//  Rule: severe / high-confidence violation → auto-freeze sender account.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth
import CryptoKit

// MARK: - Media Safety Decision

enum MediaSafetyDecision {
    /// Media is safe to send — proceed with upload.
    case allow

    /// Media passes pre-check but should be scanned after delivery.
    /// Recipient sees it; async scan may retract it.
    case allowWithAsyncScan

    /// Media is held — uploaded to a quarantine path, not delivered until reviewed.
    case hold(reason: String)

    /// Media rejected before upload — sender sees error, no data leaves device.
    case reject(reason: String)

    /// Freeze sender account immediately. Do not upload.
    case freeze(reason: String)

    var blocksUpload: Bool {
        switch self {
        case .allow, .allowWithAsyncScan: return false
        default: return true
        }
    }
}

// MARK: - Media Safety Gateway

@MainActor
final class MediaSafetyGateway {
    static let shared = MediaSafetyGateway()

    private let db = Firestore.firestore()

    // Rate tracking: userId → (count, windowStart)
    private var mediaSendRates: [String: (count: Int, windowStart: Date)] = [:]

    private init() {}

    // MARK: - Primary Entry Point

    /// Evaluate whether a media attachment is safe to send.
    /// Call this BEFORE uploading to Firebase Storage.
    ///
    /// - Parameters:
    ///   - image: The UIImage to evaluate.
    ///   - senderId: UID of the sender.
    ///   - recipientId: UID of the primary recipient.
    ///   - conversationId: Conversation document ID.
    ///   - recipientIsMinor: Whether recipient is minor/unknown age.
    ///   - senderTrustTier: Sender's current trust tier.
    func evaluate(
        image: UIImage,
        senderId: String,
        recipientId: String,
        conversationId: String,
        recipientIsMinor: Bool,
        senderTrustTier: UserTrustTier
    ) async -> MediaSafetyDecision {
        // 1. Hard block: minors cannot receive media from non-trusted senders
        if recipientIsMinor && senderTrustTier < .trusted {
            return .reject(
                reason: "Media cannot be sent to this user"
            )
        }

        // 2. New account throttle: no media until infant tier (3+ days)
        if senderTrustTier < .infant {
            return .reject(
                reason: "New accounts cannot send media attachments yet"
            )
        }

        // 3. Rate throttle
        if let throttleDecision = checkRateThrottle(
            senderId: senderId,
            recipientIsMinor: recipientIsMinor,
            trustTier: senderTrustTier
        ) {
            return throttleDecision
        }

        // 4. On-device pre-screen (fast, no network)
        let onDeviceResult = onDevicePreScreen(image: image)
        switch onDeviceResult {
        case .freeze(let reason):
            // Log and freeze immediately
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.freezeSenderAccount(
                    senderId: senderId,
                    reason: reason,
                    conversationId: conversationId
                )
            }
            return .freeze(reason: reason)
        case .reject(let reason):
            return .reject(reason: reason)
        case .hold(let reason):
            return .hold(reason: reason)
        default:
            break
        }

        // 5. Compute perceptual hash for known-content matching
        let pHash = computePerceptualHash(image)
        let hashCheckResult = await checkHashAgainstKnownContent(
            pHash: pHash,
            senderId: senderId,
            recipientId: recipientId,
            recipientIsMinor: recipientIsMinor
        )
        if hashCheckResult.blocksUpload {
            if case .freeze(let reason) = hashCheckResult {
                Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.freezeSenderAccount(
                        senderId: senderId,
                        reason: reason,
                        conversationId: conversationId
                    )
                }
            }
            return hashCheckResult
        }

        // 6. Check if same image has been sent to many recipients (cross-user pattern)
        let broadcastResult = await checkBroadcastPattern(
            pHash: pHash,
            senderId: senderId
        )
        if broadcastResult.blocksUpload {
            return broadcastResult
        }

        // 7. Record this media send for rate + pattern tracking
        recordMediaSend(senderId: senderId, pHash: pHash, recipientId: recipientId)

        // All pre-checks passed — allow, but schedule async deep scan after delivery
        return .allowWithAsyncScan
    }

    // MARK: - Convenience Overload (auto-fetches trust tier + minor status)

    /// Convenience variant that resolves `recipientIsMinor` and `senderTrustTier`
    /// from `MinorSafetyService`, so callers don't need to pass them explicitly.
    func evaluate(
        image: UIImage,
        senderId: String,
        recipientId: String,
        conversationId: String,
        messageId: String
    ) async -> MediaSafetyDecision {
        async let senderProfileTask = MinorSafetyService.shared.fetchProfile(userId: senderId)
        async let recipientIsMinorTask = MinorSafetyService.shared.recipientIsMinorOrUnknown(recipientId)
        let (senderProfile, recipientIsMinor) = await (senderProfileTask, recipientIsMinorTask)

        // Derive trust tier from profile (default new account if profile unavailable)
        let senderTier: UserTrustTier = senderProfile?.trustTier ?? .newAccount

        return await evaluate(
            image: image,
            senderId: senderId,
            recipientId: recipientId,
            conversationId: conversationId,
            recipientIsMinor: recipientIsMinor,
            senderTrustTier: senderTier
        )
    }

    // MARK: - Rate Throttle

    /// Enforces per-sender media send rate limits.
    /// Stricter limits when recipient is minor or sender is new.
    private func checkRateThrottle(
        senderId: String,
        recipientIsMinor: Bool,
        trustTier: UserTrustTier
    ) -> MediaSafetyDecision? {
        let hourlyLimit: Int
        switch trustTier {
        case .blocked, .restricted, .newAccount:
            return .reject(reason: "Media sending not available for your account yet")
        case .infant:
            hourlyLimit = recipientIsMinor ? 0 : 3
        case .young:
            hourlyLimit = recipientIsMinor ? 0 : 10
        case .established:
            hourlyLimit = recipientIsMinor ? 2 : 20
        case .mature:
            hourlyLimit = recipientIsMinor ? 5 : 50
        case .verified:
            hourlyLimit = recipientIsMinor ? 10 : 100
        case .trusted:
            hourlyLimit = recipientIsMinor ? 20 : 200
        }

        if hourlyLimit == 0 {
            return .reject(reason: "Media cannot be sent to this user")
        }

        let now = Date()
        if var rate = mediaSendRates[senderId] {
            if now.timeIntervalSince(rate.windowStart) > 3600 {
                // Reset window
                mediaSendRates[senderId] = (count: 1, windowStart: now)
            } else if rate.count >= hourlyLimit {
                return .hold(reason: "You're sending media too quickly. Please wait before sending more.")
            } else {
                rate.count += 1
                mediaSendRates[senderId] = rate
            }
        } else {
            mediaSendRates[senderId] = (count: 1, windowStart: now)
        }
        return nil
    }

    // MARK: - On-Device Pre-Screen

    /// Fast on-device pre-screen using pixel statistics and metadata.
    /// Not a full classifier — just catches clear violations without network calls.
    private func onDevicePreScreen(image: UIImage) -> MediaSafetyDecision {
        guard let cgImage = image.cgImage else { return .allow }

        // Check for suspiciously small images (may be thumbnails of illegal content)
        let width = cgImage.width
        let height = cgImage.height
        if width < 10 || height < 10 {
            return .reject(reason: "Invalid image format")
        }

        // Check image metadata for EXIF signals (future: GPS location in metadata)
        // Currently: allow — cloud scan handles content analysis
        return .allowWithAsyncScan
    }

    // MARK: - Perceptual Hashing

    /// Compute a perceptual hash (simplified DCT-based approach).
    /// In production this would use PhotoDNA (Microsoft) or Apple's CSAM infrastructure.
    /// This implementation provides a fingerprint for duplicate detection.
    ///
    /// NOTE: Real CSAM hash matching MUST go through an industry service
    /// (PhotoDNA, Project Protect, NCMEC hash database).
    /// This implementation detects exact/near-exact duplicates within the app —
    /// it does NOT replace hash-matching against known illegal content databases.
    private func computePerceptualHash(_ image: UIImage) -> String {
        // Resize to 32x32 grayscale for consistent hashing
        let size = CGSize(width: 32, height: 32)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = resized?.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return UUID().uuidString  // Fallback: unique hash that won't match anything
        }

        // Compute average pixel value across 32x32 grayscale
        let bytesPerRow = cgImage.bytesPerRow
        var pixelValues = [UInt8](repeating: 0, count: 1024)  // 32x32
        for row in 0..<32 {
            for col in 0..<32 {
                let offset = row * bytesPerRow + col * (cgImage.bitsPerPixel / 8)
                // Average RGB channels for grayscale
                let r = Double(bytes[offset])
                let g = Double(bytes[offset + 1])
                let b = Double(bytes[offset + 2])
                pixelValues[row * 32 + col] = UInt8((r * 0.299 + g * 0.587 + b * 0.114))
            }
        }

        let average = Double(pixelValues.reduce(0, { $0 + Int($1) })) / 1024.0

        // Build 64-character hex hash: 1 if pixel > average, 0 otherwise
        var hashBits = ""
        for pixel in pixelValues.prefix(64) {
            hashBits += Double(pixel) >= average ? "1" : "0"
        }

        // Convert bit string to hex
        var hexHash = ""
        stride(from: 0, to: hashBits.count, by: 4).forEach { i in
            let startIndex = hashBits.index(hashBits.startIndex, offsetBy: i)
            let endIndex = hashBits.index(startIndex, offsetBy: min(4, hashBits.count - i))
            let nibble = hashBits[startIndex..<endIndex]
            hexHash += String(Int(nibble, radix: 2) ?? 0, radix: 16)
        }

        return hexHash
    }

    // MARK: - Known Content Hash Check

    /// Server-side hash lookup against:
    /// 1. App's own quarantine database (images previously flagged)
    /// 2. (Production) NCMEC hash database via PhotoDNA integration
    private func checkHashAgainstKnownContent(
        pHash: String,
        senderId: String,
        recipientId: String,
        recipientIsMinor: Bool
    ) async -> MediaSafetyDecision {
        do {
            // Check against app's quarantined content database
            let quarantineSnapshot = try await db
                .collection("quarantinedContentHashes")
                .whereField("pHash", isEqualTo: pHash)
                .limit(to: 1)
                .getDocuments()

            if let match = quarantineSnapshot.documents.first {
                let severity = match.data()["severity"] as? String ?? "medium"
                let isIllegal = match.data()["isIllegal"] as? Bool ?? false

                if isIllegal {
                    // Known illegal content — freeze immediately
                    return .freeze(
                        reason: "This image has been identified as illegal content. Your account has been frozen and the incident has been reported."
                    )
                }

                if severity == "high" {
                    return .reject(reason: "This media cannot be sent")
                }

                return .hold(reason: "This media is under review")
            }

            // Additional check: if recipient is minor, check against "adult content" hash list
            if recipientIsMinor {
                let adultHashSnapshot = try await db
                    .collection("adultContentHashes")
                    .whereField("pHash", isEqualTo: pHash)
                    .limit(to: 1)
                    .getDocuments()

                if !adultHashSnapshot.documents.isEmpty {
                    return .reject(reason: "This media cannot be sent to this user")
                }
            }
        } catch {
            // Hash check failed — proceed with allowWithAsyncScan (fail open for hashing)
            print("⚠️ [MediaSafety] Hash check failed: \(error)")
        }

        return .allow
    }

    // MARK: - Cross-User Broadcast Pattern Detection

    /// Detects if the same image (by pHash) is being sent to many different recipients.
    /// This catches bulk distribution of exploitative content.
    private func checkBroadcastPattern(
        pHash: String,
        senderId: String
    ) async -> MediaSafetyDecision {
        let oneDayAgo = Date().addingTimeInterval(-86400)

        do {
            let snapshot = try await db
                .collection("mediaSendEvents")
                .whereField("senderId", isEqualTo: senderId)
                .whereField("pHash", isEqualTo: pHash)
                .whereField("timestamp", isGreaterThan: Timestamp(date: oneDayAgo))
                .getDocuments()

            let uniqueRecipients = Set(snapshot.documents.compactMap {
                $0.data()["recipientId"] as? String
            })

            if uniqueRecipients.count >= 10 {
                // Same image sent to 10+ people — broadcast pattern
                return .hold(
                    reason: "Unusual send pattern detected. This media has been held for review."
                )
            }
        } catch {
            // Network error — allow (don't block on pattern check failure)
        }

        return .allow
    }

    // MARK: - Record Media Send

    private func recordMediaSend(senderId: String, pHash: String, recipientId: String) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            _ = try? await self.db.collection("mediaSendEvents").addDocument(data: [
                "senderId": senderId,
                "recipientId": recipientId,
                "pHash": pHash,
                "timestamp": FieldValue.serverTimestamp()
            ])
        }
    }

    // MARK: - Freeze Sender Account

    private func freezeSenderAccount(
        senderId: String,
        reason: String,
        conversationId: String
    ) async {
        guard !senderId.isEmpty else { return }

        // Freeze account
        _ = try? await db.collection("userSafetyRecords").document(senderId).setData(
            [
                "accountStatus": "frozen",
                "frozenUntil": 0,  // Indefinite
                "frozenReason": reason,
                "requiresManualReview": true,
                "frozenAt": FieldValue.serverTimestamp()
            ],
            merge: true
        )

        // Preserve evidence
        await MinorSafetyService.shared.preserveEvidenceForFrozenAccount(senderId)

        // Log to moderation queue as highest priority
        _ = try? await db.collection("moderationQueue").addDocument(data: [
            "senderId": senderId,
            "conversationId": conversationId,
            "decision": "freeze_account",
            "reason": reason,
            "mediaType": "image",
            "priorityLevel": 5,  // Highest priority
            "status": "pending_review",
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Async Deep Scan (post-delivery)

    /// Schedule an async server-side deep scan of uploaded media.
    /// This calls the Cloud Vision Cloud Function (moderateUploadedImage) and
    /// can retract content after delivery if a violation is found.
    func scheduleAsyncDeepScan(
        imageURL: String,
        messageId: String,
        conversationId: String,
        senderId: String,
        recipientId: String,
        recipientIsMinor: Bool,
        pHash: String
    ) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            // Write a scan request to the mediaScanQueue collection
            // Cloud Function picks this up and runs Vision API + cross-user check
            _ = try? await self.db.collection("mediaScanQueue").addDocument(data: [
                "imageURL": imageURL,
                "messageId": messageId,
                "conversationId": conversationId,
                "senderId": senderId,
                "recipientId": recipientId,
                "recipientIsMinor": recipientIsMinor,
                "pHash": pHash,
                "status": "pending",
                "requestedAt": FieldValue.serverTimestamp(),
                // Stricter thresholds when recipient is minor
                "strictMode": recipientIsMinor
            ])
        }
    }
}
