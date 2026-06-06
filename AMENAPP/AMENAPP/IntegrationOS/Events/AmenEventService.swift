// AmenIntegrationEventService.swift — AMEN IntegrationOS
// Actor for event RSVP and follow-up. Calls `sendEventFollowUpNotification` CF.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import FirebaseRemoteConfig

actor AmenIntegrationEventService {
    static let shared = AmenIntegrationEventService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_events_enabled").boolValue }

    // MARK: - Fetch

    func fetchEvents(spaceId: String? = nil, limit: Int = 25) async throws -> [AmenIntegrationEvent] {
        guard isEnabled else { return [] }
        var query: Query = db.collection("amenEvents")
            .whereField("isPublic", isEqualTo: true)
            .whereField("startDate", isGreaterThanOrEqualTo: Timestamp(date: Date()))
            .order(by: "startDate")
            .limit(to: limit)

        if let sid = spaceId {
            query = db.collection("amenEvents")
                .whereField("spaceId", isEqualTo: sid)
                .whereField("startDate", isGreaterThanOrEqualTo: Timestamp(date: Date()))
                .order(by: "startDate")
                .limit(to: limit)
        }

        let snap = try await query.getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AmenIntegrationEvent.self) }
    }

    // MARK: - RSVP

    func rsvp(eventId: String, status: EventRSVPStatus, notes: String? = nil) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        let rsvp = EventRSVP(
            eventId: eventId,
            userId: uid,
            status: status,
            respondedAt: Date(),
            notes: notes
        )
        try db.collection("amenEvents").document(eventId)
            .collection("rsvps").document(uid)
            .setData(from: rsvp)

        try await db.collection("amenEvents").document(eventId)
            .updateData(["rsvpCount.\(status.rawValue)": FieldValue.increment(Int64(1))])
    }

    func myRSVP(eventId: String) async -> EventRSVP? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let doc = try? await db.collection("amenEvents").document(eventId)
            .collection("rsvps").document(uid)
            .getDocument()
        return try? doc?.data(as: EventRSVP.self)
    }

    // MARK: - Follow-Up Notification

    func sendFollowUp(eventId: String) async throws {
        guard isEnabled else { return }
        let payload: [String: Any] = ["eventId": eventId]
        try await functions.httpsCallable("sendEventFollowUpNotification").call(payload)
    }

    // MARK: - Attendees

    func fetchAttendees(eventId: String) async throws -> [EventAttendee] {
        guard isEnabled else { return [] }
        let snap = try await db.collection("amenEvents").document(eventId)
            .collection("rsvps")
            .whereField("status", isEqualTo: EventRSVPStatus.going.rawValue)
            .limit(to: 50)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: EventAttendee.self) }
    }
}
