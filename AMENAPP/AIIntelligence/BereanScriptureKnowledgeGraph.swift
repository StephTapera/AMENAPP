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
    ) async throws -> [BereanResolvedScriptureRef] {
        return try await scriptureEngine.resolve(text: text, language: language, sessionId: sessionId)
    }
}
