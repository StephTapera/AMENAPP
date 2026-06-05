// CalendarProviderAdapter.swift — AMEN IntegrationOS
// EventKit adapter conforming to ProviderAdapter.

import Foundation
import EventKit

final class EventKitCalendarAdapter: ProviderAdapter {
    let providerId = "eventkit"
    let capabilities: ProviderCapabilitySet = [.calendar]
    let costClass: ProviderCostClass = .free

    private let store = EKEventStore()
    private var authorized = false

    func authorize(scopes: [ConsentScope]) async throws {
        let status: Bool
        if #available(iOS 17.0, *) {
            status = try await store.requestFullAccessToEvents()
        } else {
            status = try await store.requestAccess(to: .event)
        }
        authorized = status
        if !authorized { throw IntegrationOSError.consentDenied(.calendarRead) }
    }

    func refresh() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = (status == .fullAccess || status == .authorized)
    }

    func revoke() async throws {
        authorized = false
    }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard authorized else { throw IntegrationOSError.consentDenied(.calendarRead) }
        let start = request.parameters["startDate"] as? Date ?? Date()
        let end = request.parameters["endDate"] as? Date ?? Date().addingTimeInterval(604800)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        let payload: [String: Any] = ["count": events.count]
        return ProviderResponse(providerId: providerId, payload: payload, statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .calendarEvent,
            title: "Calendar Event",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized: return .healthy
        case .denied, .restricted:     return .unauthorized
        default:                        return .unavailable
        }
    }

    var eventStore: EKEventStore { store }
}
