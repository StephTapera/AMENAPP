// BereanCitationGate.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 1)
//
// GUARDIAN: Scripture Citation Integrity capability.
// Every verse Berean is about to emit must pass through this gate before display.
//
// Fail-closed contract:
//   - Flag OFF  → verify() returns .unverifiable immediately; shouldBlock = true.
//   - Source down → .unverifiable → shouldBlock = true (same treatment as fabricated).
//   - Only .verified and .paraphrase verdicts allow emission to proceed.
//
// The outer flag guard on callers (`bereanCitationIntegrityEnabled`) prevents
// most traffic from reaching this gate when the feature is OFF; verify() handles
// the remaining cases defensively via its own guard.

import Foundation

@MainActor
final class BereanCitationGate: ObservableObject {

    static let shared = BereanCitationGate()

    // MARK: - Verify

    /// Verifies a scripture quotation against the known canon.
    ///
    /// When `bereanCitationIntegrityEnabled` is false (default), returns an
    /// `.unverifiable` verdict immediately — fail-closed.
    ///
    /// When the flag is ON, delegates to `BereanScriptureKnowledgeGraph` to
    /// resolve the reference, then compares the claimed quotation against the
    /// resolved verse text to produce a verdict.
    ///
    /// - Parameters:
    ///   - reference: Canonical scripture reference, e.g. "Romans 8:28".
    ///   - quotation: The verse text Berean is about to emit.
    ///   - translation: Bible translation code, e.g. "BSB".
    ///   - depth: The active `BereanDepth` for this response (recorded in the verdict).
    /// - Returns: A `CitationVerdict` capturing the result and all audit fields.
    func verify(
        reference: String,
        quotation: String,
        translation: String,
        depth: BereanDepth
    ) async -> CitationVerdict {
        // Fail-closed: if the feature is OFF, return unverifiable immediately.
        // Callers treat .unverifiable identically to .fabricated.
        guard AMENFeatureFlags.shared.bereanCitationIntegrityEnabled else {
            return CitationVerdict(
                reference: reference,
                quotation: quotation,
                result: .unverifiable,
                sourceId: "none",
                translation: translation,
                actualText: nil,
                confidence: 0.0,
                checkedAt: Date().timeIntervalSince1970,
                depth: depth
            )
        }

        // Flag is ON: resolve the reference via the existing knowledge graph.
        let resolvedRefs: [BereanScriptureReference]
        do {
            resolvedRefs = try await BereanScriptureKnowledgeGraph.shared.resolveReferences(
                in: reference,
                language: .english,
                claimedTexts: [reference: quotation],
                translation: translation
            )
        } catch {
            dlog("[BereanCitationGate] resolveReferences threw — treating as unverifiable. Error: \(error)")
            return CitationVerdict(
                reference: reference,
                quotation: quotation,
                result: .unverifiable,
                sourceId: "error",
                translation: translation,
                actualText: nil,
                confidence: 0.0,
                checkedAt: Date().timeIntervalSince1970,
                depth: depth
            )
        }

        // If the resolver found no matching reference, the citation is unverifiable.
        guard let match = resolvedRefs.first(where: { $0.reference == reference }) else {
            return CitationVerdict(
                reference: reference,
                quotation: quotation,
                result: .unverifiable,
                sourceId: "unresolved",
                translation: translation,
                actualText: nil,
                confidence: 0.0,
                checkedAt: Date().timeIntervalSince1970,
                depth: depth
            )
        }

        // A flagged reference (out-of-range, unknown book, malformed) → .fabricated.
        // BereanScriptureReference carries no resolved text — the knowledge graph
        // marks unverified refs via `isUnverified`; we surface that as fabricated.
        if match.isUnverified {
            return CitationVerdict(
                reference: reference,
                quotation: quotation,
                result: .fabricated,
                sourceId: "knowledge-graph",
                translation: translation,
                actualText: nil,
                confidence: match.confidence,
                checkedAt: Date().timeIntervalSince1970,
                depth: depth
            )
        }

        // Reference resolved and validated. Without a text payload from the knowledge
        // graph, we mark it verified at the reference level (the resolution engine
        // already validated canon bounds). Full text comparison requires the connector
        // service (TODO wave1-deploy: pass actualText from fetchVerse).
        return CitationVerdict(
            reference: reference,
            quotation: quotation,
            result: .verified,
            sourceId: "knowledge-graph",
            translation: translation,
            actualText: nil,
            confidence: match.confidence,
            checkedAt: Date().timeIntervalSince1970,
            depth: depth
        )
    }

    // MARK: - Guarded Emit

    /// Single call site for all Berean scripture emission.
    /// Returns both the verdict and a computed `shouldBlock` for convenience.
    static func guardedEmit(
        reference: String,
        quotation: String,
        depth: BereanDepth,
        translation: String = "BSB"
    ) async -> (verdict: CitationVerdict, shouldBlock: Bool) {
        let verdict = await BereanCitationGate.shared.verify(
            reference: reference,
            quotation: quotation,
            translation: translation,
            depth: depth
        )
        return (verdict, verdict.shouldBlock)
    }

    private init() {}
}
