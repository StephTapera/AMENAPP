import Foundation

@MainActor
final class BereanScriptureKnowledgeGraph {
    static let shared = BereanScriptureKnowledgeGraph()

    private let scriptureEngine: BereanScriptureResolutionEngine

    init(scriptureEngine: BereanScriptureResolutionEngine? = nil) {
        self.scriptureEngine = scriptureEngine ?? BereanScriptureResolutionEngine()
    }

    func resolveReferences(
        in text: String,
        language: BereanSupportedLanguage,
        sessionId: String? = nil
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
        return resolved
    }
}
