import Foundation
import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {

    @Published var state: CatalogUIState = .loading
    @Published var selectedType: WorkType? = nil
    @Published var tabs: [CatalogTab] = []
    @Published var askQuery: String = ""
    @Published var askResult: AskCreatorResult? = nil
    @Published var isAsking: Bool = false
    @Published var knowledgeNodes: [KnowledgeNode] = []

    let creatorId: String
    private let service: CatalogService

    init(creatorId: String, service: CatalogService? = nil) {
        self.creatorId = creatorId
        self.service = service ?? CatalogService.shared
    }

    func load() async {
        state = .loading
        async let works = service.fetchWorks(creatorId: creatorId, type: nil)
        async let counts = service.countByType(creatorId: creatorId)
        async let nodes = service.fetchKnowledgeNodes(creatorId: creatorId)

        let (fetchedWorks, typeCounts, fetchedNodes) = await (works, counts, nodes)

        knowledgeNodes = fetchedNodes

        var builtTabs: [CatalogTab] = [CatalogTab(type: nil, count: fetchedWorks.count)]
        for type in WorkType.allCases {
            let count = typeCounts[type] ?? 0
            if count > 0 {
                builtTabs.append(CatalogTab(type: type, count: count))
            }
        }
        tabs = builtTabs

        if fetchedWorks.isEmpty {
            state = .empty
        } else {
            state = .populated(fetchedWorks)
        }
    }

    func selectType(_ type: WorkType?) async {
        selectedType = type
        state = .loading
        let works = await service.fetchWorks(creatorId: creatorId, type: type)
        if works.isEmpty {
            state = .empty
        } else {
            state = .populated(works)
        }
    }

    func askCreator() async {
        guard !askQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            let result = try await service.askCreator(
                creatorId: creatorId,
                question: askQuery,
                userId: "current"
            )
            askResult = result
        } catch {
            askResult = AskCreatorResult(
                answer: "Unable to answer at this time.",
                citations: [],
                mode: "ai_summary",
                confidence: 0,
                refused: true
            )
        }
    }

    func filteredWorks(from works: [CatalogWork]) -> [CatalogWork] {
        guard let type = selectedType else { return works }
        return works.filter { $0.type == type }
    }

    var workCount: Int {
        if case .populated(let works) = state { return works.count }
        return 0
    }

    var activeTypeNames: [String] {
        tabs.compactMap { $0.type?.displayName }
    }
}
