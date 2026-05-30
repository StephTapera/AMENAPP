//
//  CommentRateLimiter.swift
//  AMENAPP
//
//  Created by Agent-3 audit (2026-05-27).
//
//  CLIENT-SIDE rolling-window rate limiter for comment submissions.
//  All state is in-memory and resets on app restart.  This is defence-in-depth:
//  it prevents accidental flooding and gives good UX; it does NOT replace
//  server-side enforcement (see DEFERRED_FIXES.md — [AGENT-3] items).
//
//  Limits enforced:
//    General — 5 per rolling 60 s, 30 per rolling 60 min
//    Per-post — 5 per rolling 10 min (anti-flood a single thread)
//    New account (< 7 days) — 2 per rolling 60 s, 15 per rolling 60 min
//
//  Spam signals (soft-warn only — no hard block on the client):
//    • Duplicate text: same normalised text in the last 10 comments this session
//    • Cross-post spam: same normalised text on 3+ different posts within 5 min
//    • Mention bomb: > 5 @-mentions in a single comment
//    • Link spam: > 3 URLs in a single comment
//

import Foundation
import FirebaseAuth

// MARK: - Rate-limit Error

/// Typed errors returned by CommentRateLimiter.checkCanPost(…).
/// The UI should present these gracefully, NOT as hard crash errors.
enum CommentRateLimitError: LocalizedError {
    /// Hit the per-minute global window.
    case rateLimitedPerMinute(retryAfter: TimeInterval)
    /// Hit the per-hour global window.
    case rateLimitedPerHour(retryAfter: TimeInterval)
    /// Hit the per-post per-10-min window.
    case rateLimitedPerPost(postId: String, retryAfter: TimeInterval)
    /// Soft spam signal — caller should warn but MAY still allow the post.
    case suspectedSpam(reason: SpamReason)

    enum SpamReason: String {
        case duplicateText      = "You already posted that — try adding something new."
        case crossPostDuplicate = "That comment has been spotted across multiple posts recently."
        case mentionBomb        = "Too many @mentions in one comment."
        case linkSpam           = "Too many links in one comment."
    }

    var errorDescription: String? {
        switch self {
        case .rateLimitedPerMinute(let t):
            return "Slow down — give the conversation room to breathe. Try again in \(Int(ceil(t)))s."
        case .rateLimitedPerHour(let t):
            let min = Int(ceil(t / 60))
            return "Slow down — give the conversation room to breathe. Try again in ~\(min)min."
        case .rateLimitedPerPost(_, let t):
            return "You've commented a lot here — take a breath. Try again in \(Int(ceil(t)))s."
        case .suspectedSpam(let reason):
            return reason.rawValue
        }
    }

    /// True for hard rate-limit errors; false for soft spam warnings.
    var isHardLimit: Bool {
        switch self {
        case .rateLimitedPerMinute, .rateLimitedPerHour, .rateLimitedPerPost: return true
        case .suspectedSpam: return false
        }
    }

    /// Seconds until the user may retry (nil for soft spam warnings).
    var retryAfter: TimeInterval? {
        switch self {
        case .rateLimitedPerMinute(let t): return t
        case .rateLimitedPerHour(let t):   return t
        case .rateLimitedPerPost(_, let t): return t
        case .suspectedSpam: return nil
        }
    }
}

// MARK: - Internal record

private struct CommentRecord {
    let postId: String
    let normalizedText: String
    let timestamp: Date
}

// MARK: - CommentRateLimiter

/// In-memory, rolling-window rate limiter for comment submissions.
/// Isolated as a Swift actor so all state access is data-race–safe.
actor CommentRateLimiter {

    // MARK: Singleton
    static let shared = CommentRateLimiter()
    private init() {}

    // MARK: Constants

    /// General limits (applied to all accounts).
    private let generalMinuteLimit = 5      // per 60 s
    private let generalHourLimit   = 30     // per 60 min

    /// New-account limits (account age < 7 days).
    private let newAccountMinuteLimit = 2   // per 60 s
    private let newAccountHourLimit   = 15  // per 60 min

    /// Per-post limit: 5 per rolling 10 min.
    private let perPostLimit         = 5
    private let perPostWindowSeconds = 10 * 60.0

    /// Window sizes.
    private let minuteWindow = 60.0
    private let hourWindow   = 60.0 * 60.0

    /// Number of recent comments to keep in the normalised-text ring buffer
    /// for duplicate detection.
    private let duplicateCheckWindow = 10

    /// Cross-post spam: same text on N+ different posts within this window.
    private let crossPostDuplicateThreshold = 3
    private let crossPostWindowSeconds      = 5 * 60.0

    // MARK: State

    /// All comment submissions by the current session (ring-buffer pruned to 60 min).
    private var records: [CommentRecord] = []

    // MARK: - Public API

    /// Check whether the user may post a comment right now.
    ///
    /// - Returns: `.success(())` if allowed, or `.failure(CommentRateLimitError)` if blocked or warned.
    ///
    /// For `.suspectedSpam`, the caller SHOULD warn the user but MAY still allow the post.
    /// For all other errors the caller MUST block the post and surface the message.
    ///
    /// This method does NOT record the submission — call `recordSubmission(postId:text:)` after
    /// the write succeeds to keep counts accurate.
    func checkCanPost(
        postId: String,
        text: String,
        isNewAccount: Bool
    ) -> Result<Void, CommentRateLimitError> {
        let now = Date()
        prune(before: now)

        let minuteLimit = isNewAccount ? newAccountMinuteLimit : generalMinuteLimit
        let hourLimit   = isNewAccount ? newAccountHourLimit   : generalHourLimit

        // ── 1. Per-minute check ──────────────────────────────────────────────
        let inLastMinute = records.filter { now.timeIntervalSince($0.timestamp) < minuteWindow }
        if inLastMinute.count >= minuteLimit {
            guard let oldest1 = inLastMinute.min(by: { $0.timestamp < $1.timestamp }) else { return .success(()) }
            let retryAfter = minuteWindow - now.timeIntervalSince(oldest1.timestamp)
            return .failure(.rateLimitedPerMinute(retryAfter: max(0, retryAfter)))
        }

        // ── 2. Per-hour check ────────────────────────────────────────────────
        let inLastHour = records.filter { now.timeIntervalSince($0.timestamp) < hourWindow }
        if inLastHour.count >= hourLimit {
            guard let oldest2 = inLastHour.min(by: { $0.timestamp < $1.timestamp }) else { return .success(()) }
            let retryAfter = hourWindow - now.timeIntervalSince(oldest2.timestamp)
            return .failure(.rateLimitedPerHour(retryAfter: max(0, retryAfter)))
        }

        // ── 3. Per-post per-10-min check ─────────────────────────────────────
        let inPostWindow = records.filter {
            $0.postId == postId && now.timeIntervalSince($0.timestamp) < perPostWindowSeconds
        }
        if inPostWindow.count >= perPostLimit {
            guard let oldest3 = inPostWindow.min(by: { $0.timestamp < $1.timestamp }) else { return .success(()) }
            let retryAfter = perPostWindowSeconds - now.timeIntervalSince(oldest3.timestamp)
            return .failure(.rateLimitedPerPost(postId: postId, retryAfter: max(0, retryAfter)))
        }

        // ── 4. Spam signals (soft-warn only) ─────────────────────────────────
        let normalised = normalise(text)

        // 4a. Duplicate text: same normalised text in last 10 submissions
        let recentTexts = records.suffix(duplicateCheckWindow).map(\.normalizedText)
        if recentTexts.contains(normalised) {
            return .failure(.suspectedSpam(reason: .duplicateText))
        }

        // 4b. Cross-post duplicate: same text on 3+ different posts within 5 min
        let crossPostRecords = records.filter {
            $0.normalizedText == normalised &&
            now.timeIntervalSince($0.timestamp) < crossPostWindowSeconds
        }
        let uniquePosts = Set(crossPostRecords.map(\.postId))
        if uniquePosts.count >= crossPostDuplicateThreshold {
            return .failure(.suspectedSpam(reason: .crossPostDuplicate))
        }

        // 4c. Mention bomb: > 5 @-mentions
        if mentionCount(in: text) > 5 {
            return .failure(.suspectedSpam(reason: .mentionBomb))
        }

        // 4d. Link spam: > 3 URLs
        if urlCount(in: text) > 3 {
            return .failure(.suspectedSpam(reason: .linkSpam))
        }

        return .success(())
    }

    /// Record a successful comment submission.
    /// Call this ONLY after the RTDB/Firestore write succeeds.
    func recordSubmission(postId: String, text: String) {
        records.append(CommentRecord(
            postId: postId,
            normalizedText: normalise(text),
            timestamp: Date()
        ))
    }

    /// Returns the number of seconds remaining before the per-minute bucket frees up,
    /// or 0 if the user is not currently rate-limited.
    /// Used by the UI to drive the "Post in Xs" countdown label.
    func secondsUntilNextAllowed(isNewAccount: Bool) -> TimeInterval {
        let now = Date()
        prune(before: now)
        let minuteLimit = isNewAccount ? newAccountMinuteLimit : generalMinuteLimit
        let inLastMinute = records.filter { now.timeIntervalSince($0.timestamp) < minuteWindow }
        guard inLastMinute.count >= minuteLimit,
              let oldest = inLastMinute.min(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return 0
        }
        return max(0, minuteWindow - now.timeIntervalSince(oldest))
    }

    // MARK: - Helpers

    /// Remove records older than 1 hour (they can never contribute to any window).
    private func prune(before now: Date) {
        records = records.filter { now.timeIntervalSince($0.timestamp) < hourWindow }
    }

    /// Lowercase + strip punctuation + collapse whitespace.
    /// Used for dedup keys — never for display.
    private func normalise(_ text: String) -> String {
        let lower = text.lowercased()
        // Remove punctuation
        let noPunct = lower.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
        // Collapse whitespace
        return noPunct
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Count @-mention tokens in a string.
    private func mentionCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "@[a-zA-Z0-9_]+") else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    /// Count URL-like tokens in a string (http:// or https://).
    private func urlCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+") else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}

// MARK: - Account Age Helper (nonisolated, uses Auth directly)

extension CommentRateLimiter {
    /// Returns true if the current Firebase Auth user's account is less than 7 days old.
    /// Safe to call from any context — reads metadata synchronously.
    nonisolated static func currentUserIsNewAccount() -> Bool {
        guard let creationDate = Auth.auth().currentUser?.metadata.creationDate else {
            return false // can't determine — treat as established
        }
        return Date().timeIntervalSince(creationDate) < 7 * 24 * 3600
    }
}
