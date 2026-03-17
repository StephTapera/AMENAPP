
//
//  ModerationIngestService.swift
//  AMENAPP
//
//  Client-side Stage 1 of the moderation pipeline (pre-submit guardrail).
//
//  The pipeline runs synchronously before any content is committed to Firestore.
//  Stages:
//    1. LocalContentGuard  — instant hard block (no network)
//    2. DoxxingScanner      — on-device PII detector
//    3. GroomingScanner     — on-device signal classifier (mirrors MessageSafetyGateway)
//    4. ThinkFirstGuardrails— existing service (hate, threats, spam)
//    5. Server callout      — ContentModerationService.moderateContent (async, after allow)
//
//  If any stage fires, the content is NOT submitted. The UI receives a
//  `PreSubmitResult` indicating what to show the user (prompt, block, etc.).
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Pre-Submit Result

enum PreSubmitResult {
    /// Content is clean — proceed with Firestore write.
    case allow
    /// Soft prompt: show a modal/toast but allow user to post anyway.
    case softPrompt(message: String, canOverride: Bool)
    /// User must edit before posting.
    case requireEdit(message: String, redactedText: String?)
    /// Hard block: content will not be posted.
    case block(reason: String, appealable: Bool)
}

// MARK: - ModerationIngestService

@MainActor
final class ModerationIngestService {

    static let shared = ModerationIngestService()
    private init() {}

    // MARK: - Primary Entry Point

    /// Run all pre-submit checks on `text` before it is committed.
    ///
    /// - Parameters:
    ///   - text: The raw text the user intends to post.
    ///   - contentType: Post, comment, dm, etc.
    ///   - authorId: Current user uid.
    ///   - typingDurationMs: Milliseconds the user spent typing (integrity signal).
    ///   - editCount: Number of edits made to the draft.
    ///
    /// - Returns: `PreSubmitResult` indicating whether to allow, prompt, or block.
    func check(
        text: String,
        contentType: ModerationContentType,
        authorId: String,
        typingDurationMs: Int = 0,
        editCount: Int = 0
    ) async -> PreSubmitResult {

        // ── Stage 1: Local hard-block (synchronous, no network) ──────────────
        // LocalContentGuard is a static enum — no shared instance needed.
        let localResult = LocalContentGuard.check(text)
        if localResult.isBlocked {
            return .block(reason: localResult.userMessage, appealable: false)
        }

        // ── Stage 2: Doxxing scanner ─────────────────────────────────────────
        let doxxResult = DoxxingScanner.shared.scan(text)
        if doxxResult.detected {
            let categories = doxxResult.detectedCategories
                .map { $0.rawValue.replacingOccurrences(of: "_", with: " ") }
                .joined(separator: ", ")
            // PII in posts is a hard block; PII in DMs is a soft prompt
            switch contentType {
            case .dm:
                return .softPrompt(
                    message: "Your message may contain personal information (\(categories)). Sharing private info can put you or others at risk.",
                    canOverride: true
                )
            default:
                return .requireEdit(
                    message: "Your post contains personal information that could identify someone (\(categories)). Please remove it before posting.",
                    redactedText: doxxResult.redactedText
                )
            }
        }

        // ── Stage 3: Grooming signal scanner ─────────────────────────────────
        let groomResult = GroomingScanner.shared.scan(text)
        if groomResult.detected {
            switch groomResult.riskScore {
            case 0.7...:
                // High confidence grooming pattern → hard block
                return .block(
                    reason: "This message pattern isn't allowed in our community. Please review the community guidelines.",
                    appealable: true
                )
            case 0.4..<0.7:
                return .softPrompt(
                    message: "This message contains language our safety system flagged. Make sure your conversation is appropriate and respectful.",
                    canOverride: false
                )
            default:
                break
            }
        }

        // ── Stage 4: ThinkFirstGuardrails ─────────────────────────────────────
        let guardrailResult = await ThinkFirstGuardrailsService.shared.checkAsync(text, contentType: contentType.rawValue)
        let guardrailMessage = guardrailResult.violations.first?.message
            ?? "Your content may not meet community guidelines."
        let guardrailRedacted = guardrailResult.redactions.first?.replacement

        switch guardrailResult.action {
        case .block:
            return .block(reason: guardrailMessage, appealable: true)
        case .requireEdit:
            return .requireEdit(message: guardrailMessage, redactedText: guardrailRedacted)
        case .softPrompt:
            // Let fall through to server callout; the UI layer will show the soft prompt after allow
            break
        case .allow:
            break
        }

        // ── Stage 5: Fire-and-forget server callout ───────────────────────────
        // We allow the post immediately but trigger the server pipeline async.
        // If the server rejects it, the post will be flagged server-side and
        // removed/held without blocking the user experience.
        Task.detached(priority: .background) {
            await self.submitIngestEvent(
                text: text,
                contentType: contentType,
                authorId: authorId,
                typingDurationMs: typingDurationMs,
                editCount: editCount
            )
        }

        // Return soft prompt if guardrails triggered one, otherwise allow
        if case .softPrompt = guardrailResult.action {
            return .softPrompt(message: guardrailMessage, canOverride: true)
        }

        return .allow
    }

    // MARK: - Ingest Event (Firestore)

    /// Writes a `moderation_ingest_events` document so the Cloud Function can
    /// create a full `ModerationJob` with deeper analysis.
    private func submitIngestEvent(
        text: String,
        contentType: ModerationContentType,
        authorId: String,
        typingDurationMs: Int,
        editCount: Int
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let contentId = "\(uid)_\(Int(Date().timeIntervalSince1970 * 1000))"

        let event: [String: Any] = [
            "content_id": contentId,
            "content_type": contentType.rawValue,
            "author_id": authorId,
            "content_snapshot": String(text.prefix(4000)),
            "media_urls": [] as [String],
            "client_signals": [
                "typing_duration_ms": typingDurationMs,
                "pasted_content": typingDurationMs < 500 && text.count > 100,
                "edit_count": editCount,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ] as [String: Any],
            "created_at": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("moderation_ingest_events").addDocument(data: event)
        } catch {
            // Non-fatal — server pipeline is best-effort for pre-submit
            dlog("⚠️ [ModerationIngestService] Failed to submit ingest event: \(error.localizedDescription)")
        }
    }
}

// MARK: - DoxxingScanner

/// On-device PII scanner that detects personal identifying information in text.
/// Uses regex patterns similar to ThinkFirstGuardrailsService but extended.
final class DoxxingScanner {
    static let shared = DoxxingScanner()
    private init() {}

    func scan(_ text: String) -> DoxxingCheckResult {
        var detectedCategories: [DoxxingCheckResult.PIICategory] = []
        var confidence = 0.0
        var redacted = text

        let checks: [(pattern: String, category: DoxxingCheckResult.PIICategory, weight: Double)] = [
            // Home address: "123 Main St" / "123 Elm Street, Chicago, IL 60601"
            (#"(?<![0-9])\d{1,5}\s+[A-Za-z0-9\s]{3,40}(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl)(?:\s+[A-Za-z]{2,20})?(?:,\s*\w{2})?(?:\s+\d{5}(?:-\d{4})?)?"#,
             .homeAddress, 0.7),

            // US phone numbers: (555) 123-4567 / 555-123-4567 / 5551234567
            (#"(?<![0-9])(?:\+1\s?)?(?:\(\d{3}\)|\d{3})[-.\s]?\d{3}[-.\s]?\d{4}(?![0-9])"#,
             .personalPhoneNumber, 0.6),

            // Email addresses
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
             .personalEmail, 0.5),

            // SSN: 123-45-6789 / 123456789
            (#"(?<![0-9])\d{3}[-\s]?\d{2}[-\s]?\d{4}(?![0-9])"#,
             .ssn, 0.9),

            // Credit card / bank account: 16-digit sequences
            (#"(?<![0-9])\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}(?![0-9])"#,
             .bankAccount, 0.8),

            // US licence plate: ABC-1234 / AB-12-CD
            (#"(?<![A-Z0-9])[A-Z]{2,3}[-\s]?\d{3,4}(?:-[A-Z]{0,3})?(?![A-Z0-9])"#,
             .licencePlate, 0.4),
        ]

        for check in checks {
            guard let regex = try? NSRegularExpression(pattern: check.pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if !matches.isEmpty {
                detectedCategories.append(check.category)
                confidence = max(confidence, check.weight)
                // Redact the matched ranges
                redacted = regex.stringByReplacingMatches(
                    in: redacted,
                    range: NSRange(redacted.startIndex..., in: redacted),
                    withTemplate: "[REDACTED]"
                )
            }
        }

        return DoxxingCheckResult(
            detected: !detectedCategories.isEmpty,
            detectedCategories: detectedCategories,
            confidence: confidence,
            redactedText: detectedCategories.isEmpty ? nil : redacted
        )
    }
}

// MARK: - GroomingScanner

/// On-device grooming signal detector.
/// Mirrors `MessageSafetyGateway`'s signal classification but optimised for
/// post and comment content (lower weight thresholds; no conversation context).
final class GroomingScanner {
    static let shared = GroomingScanner()
    private init() {}

    private struct SignalPattern {
        let signal: GroomingCheckResult.GroomingSignal
        let patterns: [String]
        let weight: Double
    }

    private let signalPatterns: [SignalPattern] = [
        SignalPattern(
            signal: .ageMentionWithSexual,
            patterns: [
                #"(?:how old|your age|are you young|how young)\b.{0,30}\b(?:send|meet|chat|dm|private)"#,
                #"\b(?:14|15|16|underage|teen|minor)\b.{0,40}\b(?:hot|cute|sexy|body|meet)"#,
            ],
            weight: 1.0
        ),
        SignalPattern(
            signal: .isolationLanguage,
            patterns: [
                #"\b(?:don't tell|keep this between|our secret|just between us|no one else|delete this after)\b"#,
                #"\b(?:parents? don'?t|without your mom|behind their back)\b"#,
            ],
            weight: 0.70
        ),
        SignalPattern(
            signal: .secretKeeping,
            patterns: [
                #"\b(?:secret|secretly|hide this|don't show|keep quiet)\b.{0,20}\b(?:message|photo|video|pic)\b"#,
            ],
            weight: 0.65
        ),
        SignalPattern(
            signal: .offPlatformMigration,
            patterns: [
                #"\b(?:snapchat|snap|telegram|whatsapp|discord|signal|kik|wickr)\b.{0,30}\b(?:add me|find me|dm me|message me)\b"#,
                #"\bget off (?:here|this app|this platform)\b"#,
            ],
            weight: 0.60
        ),
        SignalPattern(
            signal: .locationRequest,
            patterns: [
                #"\b(?:where do you live|your address|what city|near you|come to my)\b"#,
                #"\b(?:location|address|zip code|neighborhood)\b.{0,30}\b(?:send|share|tell)\b"#,
            ],
            weight: 0.55
        ),
        SignalPattern(
            signal: .giftOffering,
            patterns: [
                #"\b(?:gift card|amazon card|itunes|google play|cash app|venmo|paypal).{0,30}\b(?:send you|give you|for you)\b"#,
            ],
            weight: 0.60
        ),
        SignalPattern(
            signal: .urgencyPressure,
            patterns: [
                #"\b(?:reply now|respond quickly|hurry|don't wait|limited time|before it's too late)\b"#,
            ],
            weight: 0.45
        ),
        SignalPattern(
            signal: .loveBombing,
            patterns: [
                #"\b(?:you're so special|no one understands|only you|you're perfect|i love you so much)\b.{0,40}\b(?:meet|dm|private|secret)\b"#,
            ],
            weight: 0.45
        ),
    ]

    func scan(_ text: String) -> GroomingCheckResult {
        let lower = text.lowercased()
        var detectedSignals: [GroomingCheckResult.GroomingSignal] = []
        var combinedScore = 0.0

        for sp in signalPatterns {
            for pattern in sp.patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    if !detectedSignals.contains(sp.signal) {
                        detectedSignals.append(sp.signal)
                    }
                    combinedScore = min(1.0, combinedScore + sp.weight * 0.6)
                    break
                }
            }
        }

        return GroomingCheckResult(
            detected: combinedScore >= 0.4,
            signals: detectedSignals,
            riskScore: combinedScore
        )
    }
}

// MARK: - ThinkFirstGuardrailsService Async Wrapper

private extension ThinkFirstGuardrailsService {
    /// Calls the async `checkContent(_:context:)` method with a mapped `ContentContext`.
    func checkAsync(_ text: String, contentType: String) async -> ThinkFirstGuardrailsService.ContentCheckResult {
        let context: ContentContext = {
            switch contentType {
            case "prayer", "church_note", "testimony":
                return .normalPost
            case "dm":
                return .normalPost
            default:
                return .normalPost
            }
        }()
        return await checkContent(text, context: context)
    }
}
