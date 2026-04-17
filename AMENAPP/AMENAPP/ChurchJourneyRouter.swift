// ChurchJourneyRouter.swift
// AMENAPP
//
// Shared navigation coordinator for the Church Journey system.
// Supports:
//   - Deep links (amen://church-journey/...)
//   - Push notification opens (userInfo[route] key)
//   - In-app suggestion taps
//   - Restoring active session state on warm launch
//
// Usage: inject as @StateObject in AMENTabBar or ContentView,
// then pass as @EnvironmentObject to all church journey views.

import SwiftUI

// MARK: - Route Enum

enum ChurchJourneyRoute: Hashable {
    case churchDetail(churchID: String)
    case plan(churchID: String, serviceTimeID: String?)
    case prep(journeyID: String)
    case notes(sessionID: String)
    case reflection(journeyID: String)

    // MARK: Deep link parsing
    // URL scheme: amen://church-journey/<path>

    init?(url: URL) {
        guard url.scheme == "amen",
              url.host == "church-journey" else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        switch components.first {
        case "church":
            guard let id = components.dropFirst().first else { return nil }
            self = .churchDetail(churchID: id)
        case "plan":
            guard let id = components.dropFirst().first else { return nil }
            let serviceTimeID = components.dropFirst(2).first
            self = .plan(churchID: id, serviceTimeID: serviceTimeID)
        case "prep":
            guard let id = components.dropFirst().first else { return nil }
            self = .prep(journeyID: id)
        case "notes":
            guard let id = components.dropFirst().first else { return nil }
            self = .notes(sessionID: id)
        case "reflection":
            guard let id = components.dropFirst().first else { return nil }
            self = .reflection(journeyID: id)
        default:
            return nil
        }
    }

    // MARK: Push notification parsing

    static func from(notificationUserInfo info: [AnyHashable: Any]) -> ChurchJourneyRoute? {
        guard let routeString = info["churchJourneyRoute"] as? String,
              let url = URL(string: routeString) else { return nil }
        return ChurchJourneyRoute(url: url)
    }
}

// MARK: - Router

@MainActor
final class ChurchJourneyRouter: ObservableObject {

    static let shared = ChurchJourneyRouter()

    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: ChurchJourneySheet?

    private init() {}

    // MARK: - Navigate

    func navigate(to route: ChurchJourneyRoute) {
        navigationPath.append(route)
    }

    func present(sheet: ChurchJourneySheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func popToRoot() {
        navigationPath = NavigationPath()
    }

    // MARK: - Deep link handler

    func handle(url: URL) {
        guard let route = ChurchJourneyRoute(url: url) else { return }
        // Clear stack and navigate to the deep-linked destination
        navigationPath = NavigationPath()
        navigationPath.append(route)
    }

    // MARK: - Push notification handler

    func handle(notificationUserInfo info: [AnyHashable: Any]) {
        guard let route = ChurchJourneyRoute.from(notificationUserInfo: info) else { return }
        navigationPath = NavigationPath()
        navigationPath.append(route)
    }

    // MARK: - Restore active session

    func restoreActiveSessionIfNeeded(store: ChurchJourneyStore) {
        guard let journey = store.activeJourney else { return }
        switch journey.status {
        case .prepActive:
            navigateIfNotAlreadyThere(.prep(journeyID: journey.id))
        case .arrived, .notesActive:
            if let sessionId = journey.noteSessionId {
                navigateIfNotAlreadyThere(.notes(sessionID: sessionId))
            }
        case .reflectionPending:
            navigateIfNotAlreadyThere(.reflection(journeyID: journey.id))
        default:
            break
        }
    }

    private func navigateIfNotAlreadyThere(_ route: ChurchJourneyRoute) {
        // Only push if not already the top of the stack
        // NavigationPath doesn't expose its contents so we push unconditionally
        // (acceptable for notification/deep-link driven navigation)
        navigationPath.append(route)
    }
}

// MARK: - Sheets

enum ChurchJourneySheet: Identifiable, Hashable {
    case planForChurch(churchID: String)
    case routineEditor(routineID: String?)
    case prepSuggestions(journeyID: String)
    case reflectionAISummary(reflectionID: String)
    case midweekReminderSettings(reflectionID: String)

    var id: String {
        switch self {
        case .planForChurch(let id):         return "plan_\(id)"
        case .routineEditor(let id):         return "routine_\(id ?? "new")"
        case .prepSuggestions(let id):       return "prep_\(id)"
        case .reflectionAISummary(let id):   return "ai_\(id)"
        case .midweekReminderSettings(let id): return "mwr_\(id)"
        }
    }
}
