import Foundation

@MainActor
final class ScriptureContextResolver {
    static let shared = ScriptureContextResolver()

    private let knowledgeGraph: BereanScriptureKnowledgeGraph

    init(knowledgeGraph: BereanScriptureKnowledgeGraph? = nil) {
        self.knowledgeGraph = knowledgeGraph ?? BereanScriptureKnowledgeGraph()
    }

    func contextualReferences(
        for text: String,
        language: BereanSupportedLanguage,
        sessionId: String? = nil
    ) async throws -> [BereanScriptureReference] {
        try await knowledgeGraph.resolveReferences(in: text, language: language, sessionId: sessionId)
            .sorted { $0.confidence > $1.confidence }
    }
}
