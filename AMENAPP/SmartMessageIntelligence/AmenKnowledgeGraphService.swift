import Foundation

@MainActor
final class AmenKnowledgeGraphService: ObservableObject {
    static let shared = AmenKnowledgeGraphService()
    @Published private(set) var nodes: [SmartKnowledgeNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private init() {}

    func build(scope: SmartKnowledgeScope, source: SmartMessageSource, text: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let node = try await AmenSmartMessageIntelligenceService.shared.buildKnowledgeGraph(scope: scope, source: source, text: text)
            nodes.insert(node, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
