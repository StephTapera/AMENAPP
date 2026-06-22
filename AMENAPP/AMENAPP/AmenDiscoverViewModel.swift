import Foundation
import SwiftUI

@MainActor
final class AmenDiscoverViewModel: ObservableObject {
    @Published private(set) var items: [AmenDiscoverItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedFilter: String = "For You"
    @Published var searchQuery: String = ""
    @Published var selectedItem: AmenDiscoverItem?
    @Published var reasonText: String = ""

    private(set) var sessionId: String = UUID().uuidString
    private var nextCursor: String?

    let filters = ["For You", "Churches", "Prayer", "Testimonies", "Sermons", "Scripture", "Selah", "Creators", "Near Me"]

    func loadInitial() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await AmenDiscoverService.shared.loadDiscoverFeed(cursor: nil, sessionId: sessionId, filter: selectedFilter, query: searchQuery)
            sessionId = response.sessionId
            items = response.items
            nextCursor = response.nextCursor
            isLoading = false
            AMENAnalyticsService.shared.track(.discoverFeedLoaded(count: items.count))
            if items.isEmpty {
                AMENAnalyticsService.shared.track(.discoverEmptyStateSeen)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            AMENAnalyticsService.shared.track(.discoverErrorSeen(message: error.localizedDescription))
        }
    }

    func loadMoreIfNeeded(current item: AmenDiscoverItem) async {
        guard !isLoading, let nextCursor, items.last?.id == item.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await AmenDiscoverService.shared.loadDiscoverFeed(cursor: nextCursor, sessionId: sessionId, filter: selectedFilter, query: searchQuery)
            self.nextCursor = response.nextCursor
            self.items.append(contentsOf: response.items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyFilter(_ filter: String) async {
        guard filter != selectedFilter else { return }
        selectedFilter = filter
        AMENAnalyticsService.shared.track(.discoverFilterChanged(filter: filter))
        await loadInitial()
    }

    func openDetail(_ item: AmenDiscoverItem) {
        selectedItem = item
        AMENAnalyticsService.shared.track(.discoverDetailOpened(itemType: item.type.rawValue))
        AmenDiscoverService.shared.logDiscoverEvent(sessionId: sessionId, itemId: item.id, event: "detail_open")
    }

    func logTap(_ item: AmenDiscoverItem) {
        AMENAnalyticsService.shared.track(.discoverItemTapped(itemType: item.type.rawValue))
        AmenDiscoverService.shared.logDiscoverEvent(sessionId: sessionId, itemId: item.id, event: "tap")
    }

    func loadWhyThis(for item: AmenDiscoverItem) async {
        do {
            let reason = try await AmenDiscoverService.shared.getDiscoverReason(itemId: item.id, sessionId: sessionId)
            reasonText = reason.reason
            AMENAnalyticsService.shared.track(.discoverWhyThisOpened)
        } catch {
            reasonText = "This was recommended based on your recent Amen activity and Discover settings."
        }
    }

    func submitFeedback(_ item: AmenDiscoverItem, feedback: AmenDiscoverFeedbackType) async {
        do {
            try await AmenDiscoverService.shared.submitDiscoverFeedback(itemId: item.id, sessionId: sessionId, feedback: feedback)
            AMENAnalyticsService.shared.track(.discoverFeedbackSubmitted(type: feedback.rawValue))
            AmenDiscoverService.shared.logDiscoverEvent(sessionId: sessionId, itemId: item.id, event: feedback.rawValue)
            if [.notForMe, .hideCreator, .hideTopic, .report].contains(feedback) {
                items.removeAll { $0.id == item.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
