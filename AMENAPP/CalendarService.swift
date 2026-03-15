// CalendarService.swift
// AMEN Calendar & Reminder System — EventKit Integration
// Privacy-first: least-privilege calendar access

import SwiftUI
import Combine
import EventKit
import EventKitUI
import UserNotifications
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CalendarService: NSObject, ObservableObject {
    static let shared = CalendarService()

    // MARK: - Published State

    @Published var permissionState: CalendarPermissionState = .notDetermined
    @Published var savedEvents: [AMENSavedCalendarEvent] = []
    @Published var myRSVPs: [AMENEventRSVP] = []
    @Published var isLoading = false
    @Published var lastError: String?

    // MARK: - Private Properties

    private let eventStore = EKEventStore()
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var isListening = false

    // Track added events to prevent duplicates
    private var addedEventKeys = Set<EventDuplicateKey>()

    private override init() {
        super.init()
        checkCurrentPermission()
    }

    // MARK: - Permission Management

    /// Check current authorization status without requesting
    func checkCurrentPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        permissionState = mapEKStatus(status)
    }

    /// Request calendar permission with clear context.
    /// Only called when the user taps "Add to Calendar"
    func requestCalendarPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        // If already decided, return immediately
        if status == .authorized || status == .fullAccess {
            permissionState = .authorized
            return true
        }

        if status == .denied || status == .restricted {
            permissionState = status == .denied ? .denied : .restricted
            return false
        }

        // Request access
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                permissionState = granted ? .authorized : .denied
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                permissionState = granted ? .authorized : .denied
                return granted
            }
        } catch {
            permissionState = .denied
            return false
        }
    }

    private func mapEKStatus(_ status: EKAuthorizationStatus) -> CalendarPermissionState {
        switch status {
        case .notDetermined:            return .notDetermined
        case .authorized, .fullAccess:  return .authorized
        case .denied:                   return .denied
        case .restricted:               return .restricted
        case .writeOnly:                return .authorized  // Sufficient for our use
        @unknown default:               return .denied
        }
    }

    // MARK: - Add Event to Calendar

    /// Add an AMEN event to the user's calendar (no permission prompt shown here).
    /// Returns the EKEvent identifier or nil on failure.
    func addEventToCalendar(
        _ amenEvent: AMENEvent,
        options: CalendarAddOptions = CalendarAddOptions()
    ) async -> String? {
        guard permissionState.canAddEvents else { return nil }

        // Duplicate check
        let key = EventDuplicateKey(event: amenEvent)
        if addedEventKeys.contains(key) {
            // Event already added — skip silently
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = amenEvent.title
        event.startDate = amenEvent.startDate
        event.endDate = amenEvent.endDate
        event.timeZone = amenEvent.timeZone
        event.location = amenEvent.location
        event.notes = buildCalendarNotes(amenEvent)
        event.url = amenEvent.deepLinkURL.flatMap { URL(string: $0) }

        // Set the appropriate calendar
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Add reminders
        if options.enableReminder {
            let alarms = options.reminderOffsets.map { offset in
                EKAlarm(relativeOffset: -TimeInterval(offset.minutesBefore * 60))
            }
            event.alarms = alarms
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            addedEventKeys.insert(key)

            // Save identifier for future management
            let identifier = event.eventIdentifier
            await saveCalendarEventRecord(
                amenEvent: amenEvent,
                calendarEventId: identifier,
                options: options
            )
            return identifier
        } catch {
            lastError = "Couldn't save to calendar."
            return nil
        }
    }

    /// Create a prefilled event using the native EKEventEditViewController (low-friction, user controls it)
    func makeEKEvent(for amenEvent: AMENEvent, options: CalendarAddOptions = CalendarAddOptions()) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = amenEvent.title
        event.startDate = amenEvent.startDate
        event.endDate = amenEvent.endDate
        event.timeZone = amenEvent.timeZone
        event.location = amenEvent.location
        event.notes = buildCalendarNotes(amenEvent)
        event.url = amenEvent.deepLinkURL.flatMap { URL(string: $0) }
        event.calendar = eventStore.defaultCalendarForNewEvents

        if options.enableReminder && !options.reminderOffsets.isEmpty {
            event.alarms = options.reminderOffsets.map {
                EKAlarm(relativeOffset: -TimeInterval($0.minutesBefore * 60))
            }
        }
        return event
    }

    /// Remove an event from the calendar by its EKEvent identifier
    func removeEventFromCalendar(calendarEventId: String) async -> Bool {
        guard permissionState.canAddEvents else { return false }
        if let event = eventStore.event(withIdentifier: calendarEventId) {
            do {
                try eventStore.remove(event, span: .thisEvent)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    // MARK: - Build Calendar Notes

    private func buildCalendarNotes(_ event: AMENEvent) -> String {
        var parts: [String] = []
        if let notes = event.notes, !notes.isEmpty { parts.append(notes) }
        if event.isOnline, let url = event.onlineMeetingURL { parts.append("Join online: \(url)") }
        if let deepLink = event.deepLinkURL { parts.append("View in AMEN: \(deepLink)") }
        let typeNote = event.eventType.calendarNotes
        if !typeNote.isEmpty { parts.append(typeNote) }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Firestore: Save Record

    private func saveCalendarEventRecord(
        amenEvent: AMENEvent,
        calendarEventId: String?,
        options: CalendarAddOptions
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let record = AMENSavedCalendarEvent(
            userId: userId,
            amenEventId: amenEvent.id,
            title: amenEvent.title,
            eventType: amenEvent.eventType,
            startDate: amenEvent.startDate,
            endDate: amenEvent.endDate,
            timeZoneIdentifier: amenEvent.timeZoneIdentifier,
            location: amenEvent.location,
            isOnline: amenEvent.isOnline,
            notes: buildCalendarNotes(amenEvent),
            calendarEventId: calendarEventId,
            localNotificationIds: [],
            reminders: options.reminderOffsets,
            isSavedToCalendar: true,
            followUpSent: false,
            createdAt: Date()
        )
        let docId = UUID().uuidString
        guard let encoded = try? Firestore.Encoder().encode(record) else { return }
        try? await db.collection(CalendarCollections.savedCalendarEvents).document(docId).setData(encoded)
    }

    // MARK: - RSVP

    func rsvp(eventId: String, status: RSVPStatus, note: String? = nil) async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let displayName = Auth.auth().currentUser?.displayName ?? Auth.auth().currentUser?.email else { return }

        // Check for existing RSVP
        let existing = try? await db.collection(CalendarCollections.rsvps)
            .whereField("eventId", isEqualTo: eventId)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        if let doc = existing?.documents.first {
            // Update existing RSVP
            try await doc.reference.updateData([
                "status": status.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        } else {
            // Create new RSVP
            let rsvp = AMENEventRSVP(
                eventId: eventId,
                userId: userId,
                displayName: displayName,
                status: status,
                addedToCalendar: false,
                reminderEnabled: false,
                selectedReminderOffsets: [],
                note: note,
                createdAt: Date(),
                updatedAt: Date()
            )
            let docId = UUID().uuidString
            let encoded = try Firestore.Encoder().encode(rsvp)
            try await db.collection(CalendarCollections.rsvps).document(docId).setData(encoded)

            // Update event rsvpCount (atomic)
            let eventRef = db.collection(CalendarCollections.events).document(eventId)
            try await eventRef.updateData(["rsvpCount": FieldValue.increment(Int64(1))])
        }
    }

    func cancelRSVP(eventId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let docs = try await db.collection(CalendarCollections.rsvps)
            .whereField("eventId", isEqualTo: eventId)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        for doc in docs.documents {
            try await doc.reference.updateData(["status": RSVPStatus.notGoing.rawValue])
        }
        let eventRef = db.collection(CalendarCollections.events).document(eventId)
        try? await eventRef.updateData(["rsvpCount": FieldValue.increment(Int64(-1))])
    }

    func fetchMyRSVP(for eventId: String) async -> AMENEventRSVP? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        guard let snap = try? await db.collection(CalendarCollections.rsvps)
            .whereField("eventId", isEqualTo: eventId)
            .whereField("userId", isEqualTo: userId)
            .limit(to: 1)
            .getDocuments() else { return nil }
        return snap.documents.first.flatMap { try? $0.data(as: AMENEventRSVP.self) }
    }

    func fetchUpcomingEvents() async -> [AMENEvent] {
        let now = Date()
        guard let snap = try? await db.collection(CalendarCollections.events)
            .whereField("startDate", isGreaterThan: now)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "startDate")
            .limit(to: 30)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: AMENEvent.self) }
    }

    func fetchMySavedEvents() async -> [AMENSavedCalendarEvent] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        guard let snap = try? await db.collection(CalendarCollections.savedCalendarEvents)
            .whereField("userId", isEqualTo: userId)
            .order(by: "startDate")
            .getDocuments() else { return [] }
        return snap.documents.compactMap { try? $0.data(as: AMENSavedCalendarEvent.self) }
    }

    // MARK: - Duplicate Prevention

    func isAlreadySaved(_ event: AMENEvent) -> Bool {
        addedEventKeys.contains(EventDuplicateKey(event: event))
    }

    // MARK: - Listeners

    func setupListeners() {
        guard !isListening, let userId = Auth.auth().currentUser?.uid else { return }
        isListening = true

        let rsvpListener = db.collection(CalendarCollections.rsvps)
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myRSVPs = snap?.documents.compactMap {
                    try? $0.data(as: AMENEventRSVP.self)
                } ?? []
            }
        listeners.append(rsvpListener)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
        isListening = false
    }
}

// MARK: - EKEventEditViewDelegate (for native event editor)

extension CalendarService: EKEventEditViewDelegate {
    nonisolated func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        controller.dismiss(animated: true)
    }
}
