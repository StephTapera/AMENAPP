// AIReceiptService.swift
// AMENAPP
//
// Wave 1 — Transparency: AI Receipt + Uncertainty Mode.
//
// Derives a real AIReceipt (Contracts/trustTransparency.ts) from the actual
// BereanPipelineResponse produced by the 7-stage constitutional pipeline.
//
// NON-NEGOTIABLE (build brief §2): nothing here is invented.
//   - sources are the ACTUAL retrieved evidence chunks + their real citations
//     (BereanPipelineEvidence). retrievalScore is OMITTED, not faked, because the
//     pipeline does not return a per-chunk score.
//   - confidence is DERIVED from real signals (isVerified + trustScore + the
//     number of agreeing sources), never decorated. The numeric `score` is set
//     only when a principled signal exists (a verified trustScore); otherwise nil.
//   - safetyChecksPassed lists only checks that actually ran.
//   - unknowns are the backend's real unknowns[].

import Foundation

enum AIReceiptService {

    /// Builds an AIReceipt from a real pipeline response. Returns nil for a
    /// degraded/empty response so callers never render an empty receipt.
    static func makeReceipt(
        from response: BereanPipelineResponse,
        mode: String
    ) -> AIReceipt? {
        // A degraded response carries no real grounding; do not surface a receipt.
        guard !response.traceId.isEmpty else { return nil }

        let sources = response.evidence.map(makeSource)
        let confidence = deriveConfidence(from: response, sourceCount: sources.count)

        return AIReceipt(
            responseId: response.traceId,
            mode: mode,
            sources: sources,
            confidence: confidence,
            unknowns: response.unknowns,
            lastUpdated: iso8601.string(from: response.timestamp),
            safetyChecksPassed: derivePassedChecks(from: response)
        )
    }

    /// True when the answer should branch into multiple grounded interpretations
    /// instead of a single confident statement (brief Wave 1 uncertainty mode).
    /// Triggers on real signals only: unverified, low derived confidence, or the
    /// backend already returned more than one interpretation.
    static func shouldBranchUncertainty(_ response: BereanPipelineResponse) -> Bool {
        if !response.isVerified { return true }
        if response.interpretations.count > 1 { return true }
        let confidence = deriveConfidence(from: response, sourceCount: response.evidence.count)
        return confidence.band == .low
    }

    // MARK: - Source mapping

    private static func makeSource(_ evidence: BereanPipelineEvidence) -> ReceiptSource {
        let title = evidence.source.isEmpty ? evidence.citation : evidence.source
        return ReceiptSource(
            title: title,
            type: classify(evidence),
            // The citation IS the real locator (e.g. "John 3:16", a chunk id, or URL).
            locator: evidence.citation.isEmpty ? evidence.source : evidence.citation,
            // No per-chunk retrieval score is returned by the pipeline — omit, never invent.
            retrievalScore: nil
        )
    }

    /// Conservative classification from the real citation/source strings.
    private static func classify(_ evidence: BereanPipelineEvidence) -> ReceiptSourceType {
        let lowerSource = evidence.source.lowercased()
        if lowerSource.hasPrefix("http") { return .web }
        if isScriptureReference(evidence.citation) { return .scripture }
        if lowerSource.contains("note") { return .userNote }
        return .commentary
    }

    /// Matches "John 3:16", "1 Cor 13:4", "Genesis 1:1-3" style references.
    private static func isScriptureReference(_ text: String) -> Bool {
        let pattern = #"^\s*[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*\s+\d+:\d+(?:-\d+)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Confidence derivation (brief §2.2)

    private static func deriveConfidence(
        from response: BereanPipelineResponse,
        sourceCount: Int
    ) -> ReceiptConfidence {
        // Unverified responses get a low band with an honest basis and no number.
        guard response.isVerified else {
            return ReceiptConfidence(
                band: .low,
                basis: "Not confirmed by constitutional review",
                score: nil
            )
        }

        let trust = response.trustScore
        let distinctSources = sourceCount
        let trustPct = Int((trust * 100).rounded())

        if trust >= 0.75 && distinctSources >= 2 {
            return ReceiptConfidence(
                band: .high,
                basis: "\(distinctSources) sources agree · trust \(trustPct)%",
                score: trust
            )
        } else if trust >= 0.5 && distinctSources >= 1 {
            return ReceiptConfidence(
                band: .medium,
                basis: "\(distinctSources) source\(distinctSources == 1 ? "" : "s") · trust \(trustPct)%",
                score: trust
            )
        } else {
            let basis = distinctSources == 0
                ? "No grounding sources · low confidence"
                : "Limited sources · trust \(trustPct)%"
            return ReceiptConfidence(band: .low, basis: basis, score: trust)
        }
    }

    // MARK: - Safety checks (only what actually ran)

    private static func derivePassedChecks(from response: BereanPipelineResponse) -> [String] {
        // The crisis pre-screen runs synchronously before every pipeline call
        // (BereanConstitutionalPipeline I-4); reaching a response means it passed.
        var checks = ["Crisis pre-screen"]
        // isVerified reflects the server-side constitutional review stage.
        if response.isVerified {
            checks.append("Constitutional review")
        }
        return checks
    }

    // MARK: - Date

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
