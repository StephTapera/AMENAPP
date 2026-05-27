import Foundation
import SwiftUI

@MainActor
final class AmenCompanionViewModel: ObservableObject {
    static let shared = AmenCompanionViewModel()

    @Published private(set) var activePrompt: CompanionPrompt?
    @Published private(set) var locationContext: LocationContext = .unknown
    @Published private(set) var isInitializing = false
    @Published var askQuery = ""
    @Published var showAskAmen = false
    @Published var showChurchDiscovery = false
    @Published var showVisitPlanning = false
    @Published var showSafeConnection = false
    @Published var selectedChurchForVisit: SmartChurchSummary?

    private let location = LocationContextService.shared
    private let privacy = CompanionPrivacyManager.shared
    private let churchService = ChurchCompanionService.shared
    private let visitService = VisitPlanningService.shared
    private let ai = AskAmenCompanionRouter.shared

    private init() {}

    func initialize() async {
        guard privacy.companionActive else { return }
        isInitializing = true
        defer { isInitializing = false }

        await privacy.load()
        location.requestLocationIfNeeded()

        if privacy.preferences.locationSharingEnabled {
            let ctx = await location.resolveApproximateLocation()
            locationContext = ctx
            await churchService.loadSavedChurches()
            await visitService.loadPlans()

            // Surface a prompt if the user is in a new area
            if ctx.isNewArea && !ctx.city.isEmpty && privacy.preferences.newAreaDetectionEnabled {
                activePrompt = .newAreaPrompt(city: ctx.city, state: ctx.state)
                return
            }

            // Surface Sunday reminder if they have saved churches
            let upcomingSunday = Calendar.current.component(.weekday, from: Date()) == 1
            if upcomingSunday || isSundaySoon() {
                if let church = churchService.savedChurches.first {
                    activePrompt = .sundayReminderPrompt(churchName: church.name)
                }
            }
        }
    }

    func handlePromptAction(_ action: CompanionAction) {
        switch action.destination {
        case .churchDiscovery:
            showChurchDiscovery = true
            activePrompt = nil
            if locationContext.isNewArea {
                Task { await churchService.discoverForNewArea(context: locationContext) }
            }
        case .visitPlanning:
            showVisitPlanning = true
            activePrompt = nil
        case .safeConnection:
            showSafeConnection = true
            activePrompt = nil
        case .dismiss:
            activePrompt = nil
        case .externalURL:
            activePrompt = nil
        }
    }

    func startVisitPlan(for church: SmartChurchSummary) {
        selectedChurchForVisit = church
        showVisitPlanning = true
    }

    func askCompanion(_ query: String) async {
        await ai.ask(query)
        showAskAmen = true
    }

    private func isSundaySoon() -> Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 6 || weekday == 7 // Friday or Saturday
    }
}
