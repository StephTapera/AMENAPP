import Foundation
import FirebaseFunctions

// Routes Ask Amen queries through companion context (location, saved churches, visit plans)
@MainActor
final class AskAmenCompanionRouter: ObservableObject {
    static let shared = AskAmenCompanionRouter()

    @Published private(set) var isProcessing = false
    @Published private(set) var lastResponse: CompanionAIResponse?
    @Published private(set) var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func ask(_ query: String) async {
        guard !query.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let context = buildContext()
        do {
            let result = try await functions.httpsCallable("askAmenCompanion").call([
                "query": query,
                "context": context
            ])
            guard let data = result.data as? [String: Any] else { return }
            lastResponse = CompanionAIResponse(from: data)
        } catch {
            errorMessage = "Ask Amen couldn't respond right now."
        }
    }

    // Pre-built companion queries
    func helpFindChurch(city: String, state: String) async {
        await ask("I'm new to \(city), \(state). Help me find a church and maybe someone safe to go with.")
    }

    func compareChurches(churchNames: [String]) async {
        let list = churchNames.joined(separator: ", ")
        await ask("Help me compare these churches near me: \(list)")
    }

    func prayerForNewArea(city: String) async {
        await ask("I just arrived in \(city). Give me a prayer for settling into a new place and finding community.")
    }

    func planVisitHelp(churchName: String, serviceDay: String) async {
        await ask("I'm planning to visit \(churchName) on \(serviceDay). What should I know before going?")
    }

    private func buildContext() -> [String: Any] {
        let locationContext = LocationContextService.shared.currentContext
        let savedChurches = ChurchCompanionService.shared.savedChurches.prefix(3).map { $0.name }
        let activePlans = VisitPlanningService.shared.activePlans.prefix(2).map { $0.churchName }

        return [
            "location": [
                "city": locationContext.city,
                "state": locationContext.state,
                "country": locationContext.country,
                "isNewArea": locationContext.isNewArea,
                "broadArea": locationContext.broadAreaLabel
            ],
            "savedChurches": Array(savedChurches),
            "visitPlans": Array(activePlans),
            "companionEnabled": true
        ]
    }
}

struct CompanionAIResponse: Equatable {
    var text: String
    var suggestions: [String]
    var churchSuggestionIds: [String]
    var prayerText: String?
    var hasVisitPlan: Bool

    init(from data: [String: Any]) {
        text = data["text"] as? String ?? ""
        suggestions = data["suggestions"] as? [String] ?? []
        churchSuggestionIds = data["churchIds"] as? [String] ?? []
        prayerText = data["prayer"] as? String
        hasVisitPlan = data["hasVisitPlan"] as? Bool ?? false
    }

    static let empty = CompanionAIResponse(from: [:])
}
