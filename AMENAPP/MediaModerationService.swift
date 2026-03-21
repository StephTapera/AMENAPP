//
//  MediaModerationService.swift
//  AMENAPP
//
//  AI-powered media moderation for PostDetailView.
//
//  Trigger: PostDetailView load when post has imageURLs and is not cached.
//  Flow:    iOS calls `moderateMediaContent` Cloud Function → receives JSON →
//           returns MediaModerationResult → PostDetailView renders accordingly.
//
//  Cache:   NSCache keyed by postId, TTL 30 minutes. Prevents repeat calls
//           when user opens/closes the same post.
//
//  Cloud Function contract: see system prompt in functions/moderateMediaContent
//  (deploy separately — this client assumes the function exists)
//

import Combine
import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Result Model

struct MediaModerationResult: Codable {
    let approved: Bool
    let confidence: Double
    let mediaType: String
    let flags: [String]
    let flagCategories: [String]
    let severity: ModerationSeverity
    let action: ModerationResultAction
    let autoRejectReason: String?
    let reviewerNotes: String
    let safeToDisplay: Bool
    let displayWithWarning: Bool
    let warningMessage: String?
    let postContextMatch: Bool
    let postContextNotes: String

    enum CodingKeys: String, CodingKey {
        case approved, confidence, flags, severity, action
        case mediaType = "media_type"
        case flagCategories = "flag_categories"
        case autoRejectReason = "auto_reject_reason"
        case reviewerNotes = "reviewer_notes"
        case safeToDisplay = "safe_to_display"
        case displayWithWarning = "display_with_warning"
        case warningMessage = "warning_message"
        case postContextMatch = "post_context_match"
        case postContextNotes = "post_context_notes"
    }
}

enum ModerationSeverity: String, Codable {
    case none, low, medium, high, critical
}

enum ModerationResultAction: String, Codable {
    case approve
    case flagForReview    = "flag_for_review"
    case blurPendingReview = "blur_pending_review"
    case autoReject       = "auto_reject"
}

// MARK: - Cache Entry

private final class ModerationCacheEntry: NSObject {
    let result: MediaModerationResult
    let fetchedAt: Date
    init(_ result: MediaModerationResult) {
        self.result = result
        self.fetchedAt = Date()
    }
    var isExpired: Bool { Date().timeIntervalSince(fetchedAt) > 1800 } // 30 min TTL
}

// MARK: - Service

@MainActor
final class MediaModerationService: ObservableObject {
    static let shared = MediaModerationService()

    @Published private(set) var moderationStates: [String: MediaModerationState] = [:]

    private let functions = Functions.functions(region: "us-central1")
    private let cache = NSCache<NSString, ModerationCacheEntry>()

    // In-flight dedup: prevents double-call when PostDetailView re-renders mid-check
    private var inFlight = Set<String>()

    private init() {
        cache.countLimit = 300
    }

    // MARK: - Public API

    /// Returns the current moderation state for a post.
    /// Call `check(post:)` first to trigger evaluation; this is a read-only accessor.
    func state(for postId: String) -> MediaModerationState {
        moderationStates[postId] ?? .unchecked
    }

    /// Evaluate a post's media. Safe to call multiple times — deduplicates automatically.
    /// Only evaluates posts with imageURLs. Skips if cached result is still valid.
    func check(post: Post) {
        let postId = post.firestoreId
        guard !postId.isEmpty,
              let imageURLs = post.imageURLs, !imageURLs.isEmpty,
              !inFlight.contains(postId) else { return }

        // Hit: return cached state immediately
        if let entry = cache.object(forKey: postId as NSString), !entry.isExpired {
            moderationStates[postId] = stateFromResult(entry.result)
            return
        }

        // Already evaluated and safe — skip re-check unless flagged
        if case .approved = moderationStates[postId] { return }

        inFlight.insert(postId)
        moderationStates[postId] = .checking

        Task {
            defer { inFlight.remove(postId) }
            do {
                let result = try await callModerationFunction(post: post, imageURLs: imageURLs)
                cache.setObject(ModerationCacheEntry(result), forKey: postId as NSString)
                moderationStates[postId] = stateFromResult(result)
                // Critical severity: alert admin via a separate function call (fire-and-forget)
                if result.severity == .critical {
                    escalateCritical(postId: postId, reason: result.autoRejectReason ?? "critical_severity")
                }
            } catch {
                // Network failure or function error → fail open (show media, don't block user)
                dlog("⚠️ MediaModeration check failed for \(postId): \(error.localizedDescription)")
                moderationStates[postId] = .failedOpen
            }
        }
    }

    // MARK: - Private

    private func callModerationFunction(post: Post, imageURLs: [String]) async throws -> MediaModerationResult {
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"
        let accountAgeDays = accountAge()
        let payload: [String: Any] = [
            "post_type":        post.category.rawValue,
            "post_caption":     post.content,
            "user_display_name": post.authorName,
            "account_age_days":  accountAgeDays,
            "prior_reports":     0,      // extend: fetch from Firestore if needed
            "media_type":       "image",
            "media_url":        imageURLs.first ?? "",
            "media_urls":       imageURLs,
            "video_duration_seconds": 0,
            "has_audio":        false,
            "user_report_count": post.flaggedForReview ? 1 : 0,
            "post_author_id":   post.authorId,
            "requesting_uid":   uid
        ]
        let result = try await functions
            .httpsCallable("moderateMediaContent")
            .safeCall(payload)
        guard let data = result.data as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            throw ModerationError.invalidResponse
        }
        return try JSONDecoder().decode(MediaModerationResult.self, from: jsonData)
    }

    private func stateFromResult(_ result: MediaModerationResult) -> MediaModerationState {
        switch result.action {
        case .approve:
            return result.displayWithWarning
                ? .warningRequired(message: result.warningMessage ?? "Content flagged for sensitivity.",
                                   result: result)
                : .approved
        case .flagForReview:
            if result.severity == .high {
                return .hidden(result: result)
            }
            return result.displayWithWarning
                ? .warningRequired(message: result.warningMessage ?? "This content has been flagged.", result: result)
                : .approved
        case .blurPendingReview:
            return .blurred(result: result)
        case .autoReject:
            return .rejected(reason: result.autoRejectReason ?? "Content violates community standards.")
        }
    }

    private func escalateCritical(postId: String, reason: String) {
        Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.functions
                .httpsCallable("escalateModerationAlert")
                .safeCall(["postId": postId, "reason": reason, "severity": "critical"])
        }
    }

    private func accountAge() -> Int {
        guard let creationDate = Auth.auth().currentUser?.metadata.creationDate else { return 0 }
        return Int(Date().timeIntervalSince(creationDate) / 86400)
    }

    enum ModerationError: Error {
        case invalidResponse
    }
}

// MARK: - State Machine

enum MediaModerationState: Equatable {
    case unchecked           // Not yet evaluated (default)
    case checking            // Cloud Function call in progress
    case approved            // Safe to display
    case warningRequired(message: String, result: MediaModerationResult)  // Show with banner
    case blurred(result: MediaModerationResult)    // Blurred pending human review
    case hidden(result: MediaModerationResult)     // Hidden until reviewed
    case rejected(reason: String)                  // Auto-rejected, never display
    case failedOpen          // Network error — fail open, show media

    static func == (lhs: MediaModerationState, rhs: MediaModerationState) -> Bool {
        switch (lhs, rhs) {
        case (.unchecked, .unchecked), (.checking, .checking),
             (.approved, .approved), (.failedOpen, .failedOpen): return true
        case (.rejected(let a), .rejected(let b)): return a == b
        case (.blurred, .blurred), (.hidden, .hidden),
             (.warningRequired, .warningRequired): return true
        default: return false
        }
    }
}


