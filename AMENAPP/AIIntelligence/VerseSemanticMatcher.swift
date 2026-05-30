import Foundation

@MainActor
final class VerseSemanticMatcher {
    static let shared = VerseSemanticMatcher()

    private let contextResolver: ScriptureContextResolver

    init(contextResolver: ScriptureContextResolver? = nil) {
        self.contextResolver = contextResolver ?? ScriptureContextResolver()
    }

    func matchVerses(
        in text: String,
        language: BereanSupportedLanguage,
        minimumConfidence: Double = 0.5,
        sessionId: String? = nil
    ) async throws -> [BereanResolvedScriptureRef] {
        let references = try await contextResolver.contextualReferences(
            for: text,
            language: language,
            sessionId: sessionId
        )
        return references.filter { $0.confidence >= minimumConfidence }
    }
}
