import Foundation
import CoreLocation
import UIKit

@MainActor
final class SmartCommunitySearchViewModel: ObservableObject {

    // MARK: - Published State
    @Published var queryText: String = ""
    @Published private(set) var uiState: SmartSearchUIState = .idle
    @Published private(set) var refinementSuggestions: [String] = []
    @Published private(set) var lastSearchId: String?
    @Published var showLocationPrompt: Bool = false
    @Published var isShowingManualLocationEntry: Bool = false

    // MARK: - Dependencies
    private let service: SmartCommunitySearchService
    private let locationManager: SmartCommunityLocationManager
    let surface: SmartSearchSurface

    // MARK: - Init
    // Default parameters use nil so @MainActor-isolated .shared is resolved inside the init body
    init(
        surface: SmartSearchSurface = .findChurch,
        service: SmartCommunitySearchService? = nil,
        locationManager: SmartCommunityLocationManager? = nil
    ) {
        self.surface = surface
        self.service = service ?? SmartCommunitySearchService.shared
        self.locationManager = locationManager ?? SmartCommunityLocationManager.shared
    }

    // MARK: - Search

    func submitSearch() {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let location = locationManager.locationState.searchLocation

        // Prompt for location only when completely undetermined — never block the search
        if location == nil && locationManager.authorizationStatus == .notDetermined {
            showLocationPrompt = true
            return
        }

        Task { await performSearch(query: trimmed, location: location) }
    }

    func proceedWithoutLocation() {
        showLocationPrompt = false
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await performSearch(query: trimmed, location: nil) }
    }

    func proceedWithLocation() {
        showLocationPrompt = false
        locationManager.requestLocationIfNeeded()
        Task {
            // Brief wait for CLLocationManager to deliver a fix
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let location = locationManager.locationState.searchLocation
            let trimmed = queryText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            await performSearch(query: trimmed, location: location)
        }
    }

    func applyRefinement(_ chip: String) {
        queryText = chip
        submitSearch()
    }

    func retrySearch() {
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await performSearch(query: trimmed, location: locationManager.locationState.searchLocation) }
    }

    func clearSearch() {
        queryText = ""
        uiState = .idle
        refinementSuggestions = []
        lastSearchId = nil
        service.cancelSearch()
    }

    // MARK: - Actions

    func handleAction(_ action: SmartCommunityAction, result: SmartCommunityRankedResult) {
        Task { await service.logInteraction(event: action.type.rawValue, result: result) }

        switch action.type {
        case .directions:
            let urlString = action.payload?["mapsUrl"] ?? action.payload?["url"]
            if let urlString, let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            } else if let coord = result.locationCoord,
                      let url = URL(string: "maps://?daddr=\(coord.lat),\(coord.lng)") {
                UIApplication.shared.open(url)
            }
        case .view:
            if let urlString = action.payload?["url"], let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    func saveResult(_ result: SmartCommunityRankedResult) {
        Task { await service.logInteraction(event: "save", result: result) }
    }

    // MARK: - Private

    private func performSearch(query: String, location: SmartSearchLocation?) async {
        uiState = .loading

        do {
            let response = try await service.search(
                query: query,
                location: location,
                surface: surface,
                previousSearchId: lastSearchId
            )

            lastSearchId = response.searchId
            refinementSuggestions = response.refinementSuggestions

            if let notice = response.safetyNotice,
               notice.localizedCaseInsensitiveContains("crisis") ||
               notice.localizedCaseInsensitiveContains("self-harm") ||
               notice.localizedCaseInsensitiveContains("immediate support") {
                uiState = .crisis
                return
            }

            if response.results.isEmpty {
                uiState = .empty(query: query)
                if refinementSuggestions.isEmpty {
                    refinementSuggestions = defaultRefinements()
                }
            } else {
                uiState = .results(response.results)
            }
        } catch is CancellationError {
            // No-op — task was intentionally cancelled
        } catch {
            uiState = .error(error.localizedDescription)
        }
    }

    private func defaultRefinements() -> [String] {
        ["Closer", "Young adults", "Has childcare", "Bible study", "Small groups", "This week", "More diverse", "Quiet community"]
    }
}
