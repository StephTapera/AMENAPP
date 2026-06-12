import Foundation
import FirebaseFunctions

@MainActor
final class BereanScriptureKnowledgeGraph {
    static let shared = BereanScriptureKnowledgeGraph()

    private let scriptureEngine: BereanScriptureResolutionEngine

    init(scriptureEngine: BereanScriptureResolutionEngine? = nil) {
        self.scriptureEngine = scriptureEngine ?? BereanScriptureResolutionEngine()
    }

    /// Resolves scripture references found in `text`, validates them locally, then
    /// calls the `verifyScriptureText` CF for any reference that requires API verification.
    ///
    /// - Parameters:
    ///   - text: The raw text to scan for scripture references.
    ///   - language: The session language (used by the resolution engine).
    ///   - sessionId: Optional session identifier for the resolution engine.
    ///   - claimedTexts: Optional map of ref → alleged verse text to verify against the CF.
    ///   - translation: Bible translation code passed to the verification CF (e.g. "ESV").
    ///   - mode: Constitutional mode — drives the verification policy for any mismatches.
    func resolveReferences(
        in text: String,
        language: BereanSupportedLanguage,
        sessionId: String? = nil,
        claimedTexts: [String: String] = [:],
        translation: String = "ESV",
        mode: BereanConstitutionalMode = .discern
    ) async throws -> [BereanScriptureReference] {
        var resolved = try await scriptureEngine.resolve(text: text, sessionId: sessionId, language: language)

        // H-10: Validate every reference returned by the LLM-backed Cloud Function.
        // Flag any reference whose book, chapter, or verse falls outside known canon bounds.
        for index in resolved.indices {
            let validationResult = ScriptureReferenceValidator.validate(resolved[index].reference)
            switch validationResult {
            case .valid:
                break
            case .unknownBook, .outOfRange, .malformed:
                resolved[index].isUnverified = true
            }
        }

        // G-1: For any reference that the local validator flagged as requiring API verification,
        // call the verifyScriptureText CF and update isUnverified based on the verdict.
        let refsNeedingVerification = resolved
            .filter { ScriptureReferenceValidator.requiresVerification($0.reference) && $0.isUnverified }
            .map(\.reference)

        if !refsNeedingVerification.isEmpty {
            let report = await ScriptureReferenceValidator.verifyWithAPIPipeline(
                references: refsNeedingVerification,
                claimedTexts: claimedTexts,
                translation: translation,
                mode: mode
            )

            // Mark verified refs as no longer unverified; everything else stays flagged.
            let confirmedVerified = Set(report.verifiedRefs)
            for index in resolved.indices {
                if confirmedVerified.contains(resolved[index].reference) {
                    resolved[index].isUnverified = false
                }
            }
        }

        return resolved
    }
}
