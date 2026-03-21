//
//  TrueSourceService.swift
//  AMENAPP
//
//  TrueSource — content authentication for AMEN.
//
//  When a user publishes a post, TrueSource:
//    1. Computes a SHA-256 fingerprint of (postId + authorId + content + timestamp).
//    2. Calls the `trueSourceSign` Cloud Function, which signs the fingerprint
//       server-side using an HMAC-SHA256 key stored in Secret Manager.
//    3. Stores the signature in Firestore posts/{postId}.trueSource.
//    4. Any client can call `trueSourceVerify` to confirm the signature is valid
//       and the content hasn't been altered.
//
//  Trust model:
//    • Trust root is AMEN's server — appropriate for a closed platform.
//    • Signature invalidates if post content is edited after signing (by design).
//    • AI-assisted content is tagged but not disqualified from verification.
//    • "Verified Original" badge shows for verified posts.
//    • "AI-Assisted" badge shows alongside Verified when AI was used.
//

import Combine
import Foundation
import CryptoKit
import FirebaseFunctions
import FirebaseFirestore

// MARK: - TrueSource Models

struct TrueSourceRecord: Codable {
    let postId: String
    let authorId: String
    let signature: String          // HMAC-SHA256 hex, server-signed
    let fingerprint: String        // SHA-256 hex of canonical payload
    let signedAt: Date
    let isAIAssisted: Bool
    let contentHash: String        // SHA-256 of post body at signing time

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case authorId = "author_id"
        case signature
        case fingerprint
        case signedAt = "signed_at"
        case isAIAssisted = "is_ai_assisted"
        case contentHash = "content_hash"
    }
}

enum TrueSourceState {
    case unsigned               // Post has no TrueSource record
    case pending                // Signing in progress
    case verified(TrueSourceRecord, Bool) // (record, isAIAssisted)
    case tampered               // Content changed after signing
    case failed(String)         // Cloud Function error
}

// MARK: - Service

@MainActor
final class TrueSourceService: ObservableObject {
    static let shared = TrueSourceService()

    @Published private(set) var states: [String: TrueSourceState] = [:]

    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()
    private var inFlight = Set<String>()

    private init() {}

    // MARK: - Sign a post after publish

    /// Call immediately after a post is successfully written to Firestore.
    func sign(postId: String, authorId: String, content: String, isAIAssisted: Bool = false) {
        guard !inFlight.contains(postId) else { return }
        inFlight.insert(postId)
        states[postId] = .pending

        Task {
            defer { inFlight.remove(postId) }
            do {
                let contentHash = sha256Hex(content)
                let payload: [String: Any] = [
                    "post_id": postId,
                    "author_id": authorId,
                    "content_hash": contentHash,
                    "is_ai_assisted": isAIAssisted
                ]
                let result = try await functions.httpsCallable("trueSourceSign").safeCall(payload)
                guard let data = result.data as? [String: Any],
                      let json = try? JSONSerialization.data(withJSONObject: data),
                      let record = try? JSONDecoder().decode(TrueSourceRecord.self, from: json) else {
                    states[postId] = .failed("Invalid response from signing service")
                    return
                }
                states[postId] = .verified(record, isAIAssisted)
            } catch {
                states[postId] = .failed(error.localizedDescription)
                dlog("⚠️ TrueSource sign failed for \(postId): \(error)")
            }
        }
    }

    // MARK: - Verify a post (check badge)

    /// Load and verify TrueSource record for a post. Safe to call multiple times.
    func verify(postId: String, currentContent: String) {
        guard !inFlight.contains(postId) else { return }
        if case .verified = states[postId] { return }

        inFlight.insert(postId)
        Task {
            defer { inFlight.remove(postId) }
            do {
                let doc = try await db.collection("posts").document(postId).getDocument()
                guard let tsData = doc.data()?["trueSource"] as? [String: Any],
                      let json = try? JSONSerialization.data(withJSONObject: tsData),
                      let record = try? JSONDecoder().decode(TrueSourceRecord.self, from: json) else {
                    states[postId] = .unsigned
                    return
                }

                // Local integrity check: does current content hash match what was signed?
                let currentHash = sha256Hex(currentContent)
                if currentHash != record.contentHash {
                    states[postId] = .tampered
                } else {
                    states[postId] = .verified(record, record.isAIAssisted)
                }
            } catch {
                states[postId] = .unsigned
            }
        }
    }

    // MARK: - Helpers

    func state(for postId: String) -> TrueSourceState {
        states[postId] ?? .unsigned
    }

    private func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - TrueSource Badge View

import SwiftUI

struct TrueSourceBadge: View {
    let state: TrueSourceState

    var body: some View {
        switch state {
        case .verified(_, let isAI):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.teal)
                Text("Verified Original")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.teal)
                if isAI {
                    Text("· AI-Assisted")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.teal.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.teal.opacity(0.2), lineWidth: 0.5))
            )

        case .tampered:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Content Modified")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5))
            )

        default:
            EmptyView()
        }
    }
}
