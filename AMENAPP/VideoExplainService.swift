// VideoExplainService.swift
// Client-side service for the Video Explain AI feature.
//
// RESPONSIBILITIES
// ─────────────────
// - Calls the `explainVideoContent` Cloud Function.
// - Enforces debounce: ignores repeated requests for the same mediaId within 2 s.
// - Caches the last successful result per mediaId for the app session.
// - Cancels the in-flight request when the caller explicitly cancels (e.g., sheet dismiss).
// - Fires analytics events at each lifecycle stage.
// - Checks feature flag + rollout gate before any network call.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Models

struct VideoExplanation: Equatable {
    let explanation: String
    let themes: [String]
    let scriptureRefs: [String]
    let cachedAt: Date
}

// MARK: - Service

@MainActor
final class VideoExplainService: ObservableObject {

    // MARK: State

    enum State: Equatable {
        case idle
        case flagDisabled          // flag off or not in rollout bucket
        case transcriptMissing     // captionsGenerationState != "ready"
        case loading
        case success(VideoExplanation)
        case failure(String)       // user-facing error message

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.flagDisabled, .flagDisabled),
                 (.transcriptMissing, .transcriptMissing), (.loading, .loading):
                return true
            case (.success(let a), .success(let b)):
                return a == b
            case (.failure(let a), .failure(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle

    // MARK: Private

    private let functions = Functions.functions()
    private let flags = AMENFeatureFlags.shared
    private let analytics = AMENAnalyticsService.shared

    private var inFlightTask: Task<Void, Never>?
    private var sessionCache: [String: VideoExplanation] = [:]      // keyed by mediaId
    private var lastRequestTime: [String: Date] = [:]

    private static let debounceInterval: TimeInterval = 2.0

    // MARK: Init

    init() {}

    // MARK: - Public API

    /// Request an explanation for the given media item.
    ///
    /// - Respects the feature flag and rollout gate.
    /// - Returns immediately with `.flagDisabled` if the gate is off.
    /// - Debounces repeated calls within 2 s for the same mediaId.
    /// - Hits the session cache before making a network call.
    func requestExplanation(postId: String, mediaId: String, surface: String = "media_detail") async {
        // ── Gate check ────────────────────────────────────────────────────────
        guard let uid = Auth.auth().currentUser?.uid else {
            state = .failure("Sign in to use this feature.")
            return
        }

        guard flags.isExplainVideoActive(uid: uid) else {
            state = .flagDisabled
            return
        }

        // ── Debounce ──────────────────────────────────────────────────────────
        let now = Date()
        if let lastTime = lastRequestTime[mediaId],
           now.timeIntervalSince(lastTime) < Self.debounceInterval {
            return
        }
        lastRequestTime[mediaId] = now

        // ── Cache hit ─────────────────────────────────────────────────────────
        if let cached = sessionCache[mediaId] {
            state = .success(cached)
            return
        }

        // ── Cancel any prior in-flight task ───────────────────────────────────
        inFlightTask?.cancel()

        state = .loading
        analytics.track(.custom(
            name: "video_explain_tapped",
            parameters: ["post_id": postId, "media_id": mediaId, "surface": surface]
        ))

        let startTime = Date()
        analytics.track(.custom(
            name: "ai_generation_started",
            parameters: ["feature": "video_explain", "post_id": postId]
        ))

        inFlightTask = Task {
            await performRequest(postId: postId, mediaId: mediaId, surface: surface, startedAt: startTime)
        }
    }

    /// Cancel any in-flight explanation request (call when the sheet dismisses).
    func cancel() {
        inFlightTask?.cancel()
        inFlightTask = nil
        if case .loading = state {
            state = .idle
        }
    }

    /// Retry after a failure. Clears the debounce lock so the request can proceed.
    func retry(postId: String, mediaId: String, surface: String = "media_detail") async {
        lastRequestTime.removeValue(forKey: mediaId)
        await requestExplanation(postId: postId, mediaId: mediaId, surface: surface)
    }

    // MARK: - Private

    private func performRequest(
        postId: String,
        mediaId: String,
        surface: String,
        startedAt: Date
    ) async {
        guard !Task.isCancelled else { return }

        do {
            let result = try await callExplainFunction(postId: postId, mediaId: mediaId)
            guard !Task.isCancelled else { return }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            analytics.track(.custom(
                name: "ai_generation_completed",
                parameters: [
                    "feature": "video_explain",
                    "post_id": postId,
                    "duration_ms": "\(durationMs)"
                ]
            ))

            sessionCache[mediaId] = result
            state = .success(result)

        } catch let error as NSError {
            guard !Task.isCancelled else { return }

            let reason = functionsErrorReason(error)
            let userMessage = userFacingMessage(for: error)

            analytics.track(.custom(
                name: "ai_generation_failed",
                parameters: [
                    "feature": "video_explain",
                    "post_id": postId,
                    "reason": reason
                ]
            ))

            // Transcript-missing is a distinct state so the UI can show a different message.
            if reason == "failed-precondition" {
                state = .transcriptMissing
            } else {
                state = .failure(userMessage)
            }
        }
    }

    private func callExplainFunction(postId: String, mediaId: String) async throws -> VideoExplanation {
        let callable = functions.httpsCallable("explainVideoContent")
        let data: [String: Any] = ["postId": postId, "mediaId": mediaId]
        let result = try await callable.call(data)

        guard let dict = result.data as? [String: Any] else {
            throw NSError(domain: "VideoExplainService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response format."])
        }

        let explanation = dict["explanation"] as? String ?? ""
        let themes = dict["themes"] as? [String] ?? []
        let scriptureRefs = dict["scriptureRefs"] as? [String] ?? []
        let cachedAtStr = dict["cachedAt"] as? String ?? ""

        let cachedAt = ISO8601DateFormatter().date(from: cachedAtStr) ?? Date()

        guard !explanation.isEmpty else {
            throw NSError(domain: "VideoExplainService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty explanation returned."])
        }

        return VideoExplanation(
            explanation: explanation,
            themes: themes,
            scriptureRefs: scriptureRefs,
            cachedAt: cachedAt
        )
    }

    // MARK: - Error helpers

    private func functionsErrorReason(_ error: NSError) -> String {
        // Firebase Functions errors carry the code as the userInfo "FIRFunctionsErrorDetailsKey"
        // or as the domain+code combination. The code string is most reliable.
        guard error.domain == FunctionsErrorDomain else { return "unknown" }
        switch FunctionsErrorCode(rawValue: error.code) {
        case .unauthenticated:       return "unauthenticated"
        case .permissionDenied:      return "permission-denied"
        case .notFound:              return "not-found"
        case .invalidArgument:       return "invalid-argument"
        case .failedPrecondition:    return "failed-precondition"
        case .internal:              return "internal"
        case .unavailable:           return "unavailable"
        case .deadlineExceeded:      return "deadline-exceeded"
        default:                     return "unknown"
        }
    }

    private func userFacingMessage(for error: NSError) -> String {
        guard error.domain == FunctionsErrorDomain else {
            return "Something went wrong. Please try again."
        }
        switch FunctionsErrorCode(rawValue: error.code) {
        case .unauthenticated:
            return "Sign in to use this feature."
        case .permissionDenied:
            return "This content isn't available for explanation."
        case .notFound:
            return "This video could not be found."
        case .failedPrecondition:
            return "Transcript not available yet."
        case .deadlineExceeded:
            return "Request timed out. Please try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
