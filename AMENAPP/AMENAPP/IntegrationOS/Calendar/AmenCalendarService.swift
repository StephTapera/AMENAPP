// AmenCalendarService.swift — AMEN IntegrationOS
// Actor wrapping EKEventStore for calendar operations.

import Foundation
import EventKit
import FirebaseRemoteConfig

actor AmenCalendarService {
    static let shared = AmenCalendarService()
    private init() {}

    private let adapter = EventKitCalendarAdapter()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_calendar_enabled").boolValue }

    // MARK: - Authorization

    func requestAccess() async throws {
        guard isEnabled else { return }
        try await adapter.authorize(scopes: [.calendarRead, .calendarWrite])
    }

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }

    // MARK: - Add Event

    func addEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, calendarId: String? = nil) async throws {
        guard isEnabled else { return }
        if !isAuthorized { try await requestAccess() }
        let store = adapter.eventStore
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        if let calId = calendarId, let cal = store.calendar(withIdentifier: calId) {
            event.calendar = cal
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        try store.save(event, span: .thisEvent)
    }

    // MARK: - Fetch Events

    func fetchEvents(from start: Date, to end: Date) async throws -> [EKEvent] {
        guard isEnabled else { return [] }
        if !isAuthorized { try await requestAccess() }
        let store = adapter.eventStore
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Remove Event

    func removeEvent(eventId: String) async throws {
        guard isEnabled else { return }
        if !isAuthorized { try await requestAccess() }
        let store = adapter.eventStore
        guard let event = store.event(withIdentifier: eventId) else { return }
        try store.remove(event, span: .thisEvent)
    }

    // MARK: - Calendars

    func availableCalendars() async -> [EKCalendar] {
        guard isEnabled, isAuthorized else { return [] }
        return adapter.eventStore.calendars(for: .event)
    }
}
