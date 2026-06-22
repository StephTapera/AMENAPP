// EventProviderAdapter.swift — AMEN IntegrationOS
// EventKit adapter + Eventbrite deep-link adapter.

import Foundation
import UIKit
import EventKit

final class EventKitEventsAdapter: ProviderAdapter {
    let providerId = "eventkit_events"
    let capabilities: ProviderCapabilitySet = [.events, .calendar]
    let costClass: ProviderCostClass = .free

    private let store = EKEventStore()
    private var authorized = false

    func authorize(scopes: [ConsentScope]) async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }
        authorized = granted
        if !authorized { throw IntegrationOSError.consentDenied(.eventsRead) }
    }

    func refresh() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
    }

    func revoke() async throws { authorized = false }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard authorized else { throw IntegrationOSError.consentDenied(.eventsRead) }
        return ProviderResponse(providerId: providerId, payload: [:], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .calendarEvent,
            title: "Event",
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

final class EventbriteDeepLinkAdapter: ProviderAdapter {
    let providerId = "eventbrite"
    let capabilities: ProviderCapabilitySet = [.events]
    let costClass: ProviderCostClass = .free

    func authorize(scopes: [ConsentScope]) async throws { }
    func refresh() async throws { }
    func revoke() async throws { }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard let eventId = request.parameters["eventId"] as? String,
              let url = URL(string: "eventbrite://event/\(eventId)") else {
            throw IntegrationOSError.providerUnavailable(providerId)
        }
        let canOpen = await UIApplication.shared.canOpenURL(url)
        if canOpen {
            await UIApplication.shared.open(url)
        } else if let webURL = URL(string: "https://www.eventbrite.com/e/\(eventId)") {
            await UIApplication.shared.open(webURL)
        }
        return ProviderResponse(providerId: providerId, payload: ["opened": true], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .churchEvent,
            title: "Eventbrite Event",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus { .healthy }
}
