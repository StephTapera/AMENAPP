//
//  PostTrustAnalysisService.swift
//  AMENAPP
//
//  Trust and authenticity signal pipeline for the AMEN post intelligence system.
//  Runs before and after publish. All scoring is internal only — never publicly
//  shames users or surfaces raw scores in the feed.
//
//  Companion to TrueSourceService.swift (which handles HMAC signing/verification).
//  This file handles pre-publish heuristic analysis: AI detection, media authenticity,
//  and composite trust profiling.
//
//  Design system: white background, black text (AmenColorScheme)
//  Dependencies: Foundation + Combine only. Network stubs marked with TODO(gate: HUMAN-MACHINE) comments.
//

import Foundation
import Combine

// MARK: - TrustSignal

/// A single internal trust/authenticity signal.
/// Raw signals are NEVER shown to end users. Only the derived `TrustPublicLabel`
/// from `TrustAnalysisProfile` may appear in UI, and only when positive.
struct TrustSignal: Codable {

    // MARK: Signal Types

    enum SignalType: String, Codable {
        /// Ratio of characters the user typed vs. pasted in the composer.
        case typedVsPastedRatio
        /// Suspiciously fast composition (large text, very short session).
        case burstTypingPattern
        /// Local heuristic estimate that text was AI-generated.
        case aiWrittenProbability
        /// Pattern of edits relative to final length (more edits = more human).
        case editHistoryPattern
        /// Composite original-composition signal.
        case originalCompositionScore
        /// Visual artifact score for images (compression / GAN artifacts).
        case imageArtifactScore
        /// Server-side AI synthetic-image probability.
        case imageSyntheticProbability
        /// Whether EXIF / metadata is present and consistent.
        case imageMetadataPresent
        /// Whether a visible logo matches the verified logo on the account.
        case logoAccountMatch
        /// Server-side video frame-consistency check.
        case videoFrameConsistency
        /// Safety / clarity score derived from the video transcript.
        case transcriptSafetyScore
        /// Bonus for media captured directly inside the AMEN app.
        case inAppCaptureBonus
        /// Cross-check that upload metadata is consistent with account identity.
        case sourceConsistency
    }

    /// Identifies which kind of signal this is.
    let type: SignalType
    /// 0.0 = low trust / bad signal — 1.0 = high trust / good signal.
    let score: Double
    /// `true` when the detection algorithm is confident in the score value.
    let confident: Bool
    /// Optional internal note for moderator review. Never shown publicly.
    let note: String?
}

// MARK: - TrustAnalysisProfile

/// Aggregated trust result for a single post.
///
/// `overallScore` is **internal only**. Only `publicLabel` may appear in UI,
/// and only when `shouldShowPublicLabel` is `true`.
struct TrustAnalysisProfile {

    // MARK: Public Label

    /// Positive-framing labels only — no negative labels ever surface publicly.
    enum TrustPublicLabel: String {
        case verifiedOriginal   = "Verified original"
        case officialSource     = "Official source matched"
        case inAppCaptured      = "Captured in app"
        case transcriptReady    = "Transcript ready"
        case contextReviewed    = "Context reviewed"
        case lowRiskLanguage    = "Low-risk language"
        case sourcePreserved    = "Source preserved"
        /// No positive label is surfaced for this post.
        case standard           = ""
    }

    let postId: String
    /// Aggregate score 0.0–1.0. **Internal use only** — never render in user-facing UI.
    let overallScore: Double
    let signals: [TrustSignal]
    let publicLabel: TrustPublicLabel
    /// Moderator-only flag strings. Never exposed to end users.
    let internalFlags: [String]

    /// Whether the public label badge should be displayed in feed / post-detail UI.
    var shouldShowPublicLabel: Bool {
        overallScore >= 0.78 && publicLabel != .standard
    }
}

// MARK: - PostTrustAnalysisService

/// Main orchestrator for the pre-publish trust/authenticity heuristic pipeline.
///
/// Typical usage:
/// ```swift
/// let service = PostTrustAnalysisService()
///
/// // Before publish — collect signals
/// let textSignals  = await service.analyzeText(text:typedRatio:editCount:sessionDurationSeconds:)
/// let imageSignals = await service.analyzeImage(imageData:isInAppCapture:accountType:accountId:)
///
/// // Build profile
/// let profile = service.buildProfile(postId: newPostId, signals: textSignals + imageSignals)
///
/// // Optionally attach profile label to post metadata (server-side)
/// ```
///
/// - Important: No part of this service surfaces raw scores to users.
@MainActor
final class PostTrustAnalysisService: ObservableObject {

    // MARK: Published State

    @Published private(set) var lastProfile: TrustAnalysisProfile?
    @Published private(set) var isAnalyzing: Bool = false

    // MARK: - Text Analysis

    /// Analyzes typed text before publish. Returns internal signals — never shown raw.
    ///
    /// - Parameters:
    ///   - text: The composed post body text.
    ///   - typedRatio: 0.0 = fully pasted, 1.0 = fully hand-typed.
    ///   - editCount: Number of distinct edit events recorded by the composer.
    ///   - sessionDurationSeconds: Wall-clock seconds from composer open to publish tap.
    /// - Returns: `[TrustSignal]` for aggregation into a profile.
    func analyzeText(
        text: String,
        typedRatio: Double,
        editCount: Int,
        sessionDurationSeconds: Double
    ) async -> [TrustSignal] {

        var signals: [TrustSignal] = []

        // ── Signal 1: typedVsPastedRatio ────────────────────────────────────
        // A fully pasted body is not inherently bad, but lowers confidence in
        // original composition. Penalise gently below 0.3 typed ratio.
        let pasteScore: Double
        switch typedRatio {
        case 0.85...:        pasteScore = 1.0
        case 0.60..<0.85:    pasteScore = 0.85
        case 0.30..<0.60:    pasteScore = 0.65
        case 0.10..<0.30:    pasteScore = 0.40
        default:             pasteScore = 0.25
        }
        signals.append(TrustSignal(
            type: .typedVsPastedRatio,
            score: pasteScore,
            confident: true,
            note: "typedRatio=\(String(format: "%.2f", typedRatio))"
        ))

        // ── Signal 2: burstTypingPattern ────────────────────────────────────
        // Large body in under 2 seconds is almost certainly pasted or auto-filled.
        let isBurst = sessionDurationSeconds < 2.0 && text.count > 200
        signals.append(TrustSignal(
            type: .burstTypingPattern,
            score: isBurst ? 0.15 : 1.0,
            confident: isBurst,
            note: isBurst
                ? "Large body (\(text.count) chars) in <2 s session"
                : nil
        ))

        // ── Signal 3: aiWrittenProbability ──────────────────────────────────
        // Local heuristic. High AI probability → low trust score (inverted).
        let aiProb = estimateAIProbability(text: text)
        signals.append(TrustSignal(
            type: .aiWrittenProbability,
            score: 1.0 - aiProb,
            confident: aiProb > 0.55 || aiProb < 0.2,
            note: "estimated_ai_prob=\(String(format: "%.2f", aiProb))"
        ))

        // ── Signal 4: editHistoryPattern ────────────────────────────────────
        // More edits relative to text length suggests genuine composition.
        // Heuristic: expect at least 1 edit per 80 characters.
        let expectedEdits = max(1, text.count / 80)
        let editScore = min(Double(editCount) / Double(expectedEdits), 1.0)
        signals.append(TrustSignal(
            type: .editHistoryPattern,
            score: editScore,
            confident: editCount > 0,
            note: "editCount=\(editCount) expectedMin=\(expectedEdits)"
        ))

        // ── Signal 5: originalCompositionScore ──────────────────────────────
        // Summary signal — composite of typed ratio and edit pattern.
        let compositionScore = (pasteScore * 0.5) + (editScore * 0.5)
        signals.append(TrustSignal(
            type: .originalCompositionScore,
            score: compositionScore,
            confident: true,
            note: nil
        ))

        return signals
    }

    /// Local heuristic estimate of AI-generated text probability (0.0–1.0).
    ///
    /// - Returns: Value where **low** (< 0.3) = likely human, **high** (> 0.6) = likely AI.
    ///   Runs entirely on-device — no network calls.
    func estimateAIProbability(text: String) -> Double {
        guard text.count > 40 else { return 0.1 }  // too short to score

        var flags = 0
        var totalChecks = 0
        let lower = text.lowercased()

        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Check 1: Hedged AI opener phrases
        let hedgedOpeners = [
            "certainly", "of course", "absolutely", "great question",
            "i'd be happy to", "i'd be glad to", "as an ai", "as a language model",
            "let me help you", "let's explore", "let's dive into"
        ]
        totalChecks += 1
        if hedgedOpeners.contains(where: { lower.hasPrefix($0) }) { flags += 1 }

        // Check 2: Structured enumeration with uniform leading phrases
        let enumPhrases = [
            "firstly,", "secondly,", "thirdly,", "in conclusion,",
            "furthermore,", "moreover,", "additionally,",
            "it is worth noting", "it is important to"
        ]
        totalChecks += 1
        if enumPhrases.filter({ lower.contains($0) }).count >= 2 { flags += 1 }

        // Check 3: Overly uniform sentence length (low std dev = AI pattern)
        if sentences.count >= 4 {
            let lengths = sentences.map { $0.count }
            let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
            let variance = lengths.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(lengths.count)
            totalChecks += 1
            if mean > 30 && sqrt(variance) < 12 { flags += 1 }
        }

        // Check 4: Absence of natural contractions/fillers in long text
        if text.count > 200 {
            let humanFillers = [
                "i'm", "i've", "i'd", "it's", "that's", "don't", "can't",
                "won't", "isn't", "you're", "we're", "honestly", "tbh", "like,"
            ]
            totalChecks += 1
            if !humanFillers.contains(where: { lower.contains($0) }) { flags += 1 }
        }

        // Check 5: Absence of any typo-adjacent patterns in long text
        if text.count > 300 {
            let hasTypoPatterns = text.contains("  ") || text.contains(" ,") || text.contains(" .")
            totalChecks += 1
            if !hasTypoPatterns { flags += 1 }
        }

        // Check 6: Overly formal vocabulary density
        let formalWords = [
            "utilize", "endeavour", "facilitate", "leverage", "paradigm",
            "synergy", "implement", "comprehensively", "demonstrate",
            "subsequently", "aforementioned"
        ]
        totalChecks += 1
        if formalWords.filter({ lower.contains($0) }).count >= 2 { flags += 1 }

        guard totalChecks > 0 else { return 0.2 }
        // Bias slightly toward false-negative to avoid flagging real humans
        return (Double(flags) / Double(totalChecks)) * 0.85
    }

    // MARK: - Image Analysis

    /// Analyzes an image for authenticity signals before publish.
    ///
    /// Steps performed locally:
    /// - In-app capture bonus
    /// - Image header / metadata consistency
    ///
    /// Steps stubbed for server implementation:
    /// - Logo/account match (church & business accounts)
    /// - Synthetic probability (GAN/artifact detection)
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes for header inspection.
    ///   - isInAppCapture: `true` if captured using the AMEN in-app camera.
    ///   - accountType: `"personal"`, `"church"`, or `"business"`.
    ///   - accountId: The poster's account identifier.
    func analyzeImage(
        imageData: Data?,
        isInAppCapture: Bool,
        accountType: String,
        accountId: String
    ) async -> [TrustSignal] {

        var signals: [TrustSignal] = []

        // ── Signal 1: inAppCaptureBonus ─────────────────────────────────────
        signals.append(TrustSignal(
            type: .inAppCaptureBonus,
            score: isInAppCapture ? 1.0 : 0.5,
            confident: true,
            note: isInAppCapture ? "AMEN in-app capture confirmed" : "External source"
        ))

        // ── Signal 2: imageMetadataPresent ──────────────────────────────────
        // Local: verify data is non-empty and begins with a known image header.
        let metadataScore: Double
        if let data = imageData, data.count > 512 {
            let header = data.prefix(4)
            let isJPEG = header[header.startIndex] == 0xFF && header[header.index(after: header.startIndex)] == 0xD8
            let isPNG  = header[header.startIndex] == 0x89 && header[header.index(after: header.startIndex)] == 0x50
            metadataScore = (isJPEG || isPNG) ? 0.9 : 0.5
        } else {
            metadataScore = 0.3
        }
        signals.append(TrustSignal(
            type: .imageMetadataPresent,
            score: metadataScore,
            confident: imageData != nil,
            note: imageData == nil ? "No image data provided" : nil
        ))

        // ── Signal 3: logoAccountMatch (church / business only) ─────────────
        // Server-side logo-match endpoint not yet deployed; using neutral stub score.
        if accountType == "church" || accountType == "business" {
            signals.append(TrustSignal(
                type: .logoAccountMatch,
                score: 0.7,   // neutral stub pending server implementation
                confident: false,
                note: "Stub: server logo-match endpoint not yet implemented"
            ))
        }

        // ── Signal 4: imageSyntheticProbability ─────────────────────────────
        // Server-side GAN/artifact detection not yet deployed; using neutral stub score.
        signals.append(TrustSignal(
            type: .imageSyntheticProbability,
            score: 0.75,   // neutral stub: assume mostly authentic
            confident: false,
            note: "Stub: awaiting server image-check endpoint"
        ))

        return signals
    }

    // MARK: - Video Analysis

    /// Analyzes a video for authenticity and content safety signals.
    ///
    /// Steps performed locally:
    /// - In-app capture bonus
    /// - Transcript safety heuristic
    /// - Upload source consistency check
    ///
    /// Steps stubbed for server implementation:
    /// - Frame consistency (deepfake / splice detection)
    ///
    /// - Parameters:
    ///   - videoURL: Local or remote URL of the video asset.
    ///   - transcriptText: Auto-generated or user-provided transcript, if available.
    ///   - isInAppCapture: `true` if recorded inside the AMEN app.
    func analyzeVideo(
        videoURL: URL?,
        transcriptText: String?,
        isInAppCapture: Bool
    ) async -> [TrustSignal] {

        var signals: [TrustSignal] = []

        // ── Signal 1: inAppCaptureBonus ─────────────────────────────────────
        signals.append(TrustSignal(
            type: .inAppCaptureBonus,
            score: isInAppCapture ? 1.0 : 0.5,
            confident: true,
            note: isInAppCapture ? "AMEN in-app capture confirmed" : "External source"
        ))

        // ── Signal 2: transcriptSafetyScore ─────────────────────────────────
        if let transcript = transcriptText, !transcript.isEmpty {
            let safetyScore = evaluateTranscriptSafety(transcript)
            signals.append(TrustSignal(
                type: .transcriptSafetyScore,
                score: safetyScore,
                confident: transcript.count > 50,
                note: "Local heuristic on \(transcript.count) chars"
            ))
        }

        // ── Signal 3: sourceConsistency ─────────────────────────────────────
        // Verify URL scheme/host is consistent with expected AMEN upload domains.
        let sourceScore: Double
        if let url = videoURL {
            let isLocal  = url.scheme == "file"
            let isKnownHost = ["amenapp", "firebase", "akamai", "googleapis"]
                .contains(where: { url.host?.contains($0) == true })
            sourceScore = (isLocal || isKnownHost) ? 0.95 : 0.55
        } else {
            sourceScore = 0.4
        }
        signals.append(TrustSignal(
            type: .sourceConsistency,
            score: sourceScore,
            confident: videoURL != nil,
            note: videoURL == nil ? "No video URL provided" : nil
        ))

        // ── Signal 4: videoFrameConsistency ─────────────────────────────────
        // Server-side deepfake/frame-consistency endpoint not yet deployed; using neutral stub.
        signals.append(TrustSignal(
            type: .videoFrameConsistency,
            score: 0.7,
            confident: false,
            note: "Stub: awaiting server video-check endpoint"
        ))

        return signals
    }

    // MARK: - Build Profile

    /// Aggregates all collected signals into a `TrustAnalysisProfile`.
    ///
    /// Uses a weighted average where unconfident signals contribute at half weight.
    ///
    /// - Parameters:
    ///   - postId: The post's unique identifier.
    ///   - signals: All signals collected across text, image, and video analyses.
    /// - Returns: A complete `TrustAnalysisProfile` including public label and moderator flags.
    func buildProfile(postId: String, signals: [TrustSignal]) -> TrustAnalysisProfile {

        // Weighted average — unconfident signals count at 50% weight
        let (weightedSum, totalWeight) = signals.reduce((0.0, 0.0)) { acc, signal in
            let w: Double = signal.confident ? 1.0 : 0.5
            return (acc.0 + signal.score * w, acc.1 + w)
        }
        let overall = totalWeight > 0 ? weightedSum / totalWeight : 0.5

        // Determine public label — priority order matters
        let hasCapture = signals.contains { $0.type == .inAppCaptureBonus && $0.score > 0.8 }
        let hasLogoMatch = signals.contains { $0.type == .logoAccountMatch && $0.score > 0.85 }
        let hasTranscript = signals.contains { $0.type == .transcriptSafetyScore && $0.score > 0.7 }
        let hasSourcePreserved = signals.contains { $0.type == .sourceConsistency && $0.score > 0.9 }

        let label: TrustAnalysisProfile.TrustPublicLabel
        if hasCapture                { label = .inAppCaptured }
        else if hasLogoMatch         { label = .officialSource }
        else if hasTranscript        { label = .transcriptReady }
        else if hasSourcePreserved   { label = .sourcePreserved }
        else if overall >= 0.85      { label = .verifiedOriginal }
        else if overall >= 0.78      { label = .lowRiskLanguage }
        else                         { label = .standard }

        // Internal moderation flags — low-confidence, certain-flagging signals
        let flags = signals
            .filter { $0.score < 0.4 && $0.confident }
            .map { "LOW_\($0.type.rawValue.uppercased())" }

        let profile = TrustAnalysisProfile(
            postId: postId,
            overallScore: overall,
            signals: signals,
            publicLabel: label,
            internalFlags: flags
        )

        lastProfile = profile
        return profile
    }

    // MARK: - Convenience Pipeline

    /// Runs the full text-only pipeline and updates `lastProfile`.
    /// Useful for single-call usage from the composer view model.
    @discardableResult
    func runTextPipeline(
        postId: String,
        text: String,
        typedRatio: Double,
        editCount: Int,
        sessionDurationSeconds: Double
    ) async -> TrustAnalysisProfile {
        isAnalyzing = true
        defer { isAnalyzing = false }
        let signals = await analyzeText(
            text: text,
            typedRatio: typedRatio,
            editCount: editCount,
            sessionDurationSeconds: sessionDurationSeconds
        )
        return buildProfile(postId: postId, signals: signals)
    }

    // MARK: - Private Helpers

    /// Local heuristic safety evaluation on transcript text.
    /// Returns 0.0–1.0 where 1.0 means no concerns detected.
    /// Not a replacement for a full moderation service — flag for server review.
    private func evaluateTranscriptSafety(_ text: String) -> Double {
        let lower = text.lowercased()

        let highRiskPhrases = [
            "kill yourself", "self harm", "end your life",
            "commit suicide", "i want to die", "hate yourself"
        ]
        let mediumRiskPhrases = [
            "attack", "destroy them", "violent", "weapon", "end it all"
        ]

        let highHits = highRiskPhrases.filter { lower.contains($0) }.count
        let mediumHits = mediumRiskPhrases.filter { lower.contains($0) }.count

        if highHits > 0    { return max(0.0, 0.1 - Double(highHits) * 0.05) }
        if mediumHits > 1  { return max(0.3, 0.7 - Double(mediumHits) * 0.1) }
        return 1.0
    }
}
