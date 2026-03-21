// MentorshipService.swift
// AMENAPP
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class MentorshipService: ObservableObject {
    static let shared = MentorshipService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Mentors
    func fetchMentors(specialty: String? = nil) async throws -> [Mentor] {
        var query: Query = db.collection("mentors").limit(to: 30)
        if let spec = specialty, spec != "All" {
            query = query.whereField("specialties", arrayContains: spec)
        }
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { doc -> Mentor? in
            try? doc.data(as: Mentor.self)
        }
    }

    // MARK: - Relationships
    func fetchMyRelationships() async throws -> [MentorshipRelationship] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("mentorshipRelationships")
            .whereField("menteeId", isEqualTo: uid)
            .whereField("status", isEqualTo: "active")
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: MentorshipRelationship.self) }
    }

    func createFreeRelationship(mentorId: String, planId: String, planName: String, mentorName: String, mentorPhotoURL: String?) async throws -> MentorshipRelationship {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "auth", code: 0) }
        let relId = UUID().uuidString
        let rel = MentorshipRelationship(
            id: relId, mentorId: mentorId, menteeId: uid,
            planId: planId, planName: planName, startedAt: Date(),
            status: .active, sessionsCompleted: 0, totalSessions: 4,
            stripeSubscriptionId: nil, nextCheckInDate: Date().addingTimeInterval(7 * 24 * 3600),
            mentorName: mentorName, mentorPhotoURL: mentorPhotoURL
        )
        try db.collection("mentorshipRelationships").document(relId).setData(from: rel)
        // Notify mentor
        try? await sendMentorshipRequestNotification(mentorId: mentorId, mentorName: mentorName)
        return rel
    }

    func createPaidRelationship(mentorId: String, planId: String, planName: String, stripePriceId: String, mentorName: String, mentorPhotoURL: String?) async throws -> (clientSecret: String, subscriptionId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "auth", code: 0) }
        let result = try await functions.httpsCallable("createMentorshipSubscription").safeCall([
            "mentorId": mentorId,
            "menteeId": uid,
            "stripePriceId": stripePriceId
        ])
        guard let data = result.data as? [String: Any],
              let clientSecret = data["clientSecret"] as? String,
              let subscriptionId = data["subscriptionId"] as? String else {
            throw NSError(domain: "stripe", code: 0)
        }
        return (clientSecret, subscriptionId)
    }

    func finalizeRelationship(mentorId: String, planId: String, planName: String, subscriptionId: String, mentorName: String, mentorPhotoURL: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let relId = UUID().uuidString
        let rel = MentorshipRelationship(
            id: relId, mentorId: mentorId, menteeId: uid,
            planId: planId, planName: planName, startedAt: Date(),
            status: .active, sessionsCompleted: 0, totalSessions: 4,
            stripeSubscriptionId: subscriptionId,
            nextCheckInDate: Date().addingTimeInterval(7 * 24 * 3600),
            mentorName: mentorName, mentorPhotoURL: mentorPhotoURL
        )
        try db.collection("mentorshipRelationships").document(relId).setData(from: rel)
    }

    // MARK: - Check-ins
    func fetchMyCheckIns() async throws -> [MentorshipCheckIn] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("mentorshipCheckIns")
            .whereField("menteeId", isEqualTo: uid)
            .whereField("status", in: ["pending", "overdue"])
            .order(by: "dueDate")
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: MentorshipCheckIn.self) }
    }

    func submitCheckInResponse(checkInId: String, response: String) async throws {
        try await db.collection("mentorshipCheckIns").document(checkInId).updateData([
            "response": response,
            "completedAt": Timestamp(date: Date()),
            "status": "completed"
        ])
    }

    func createCheckIn(relationshipId: String, mentorId: String, menteeId: String, mentorName: String, mentorPhotoURL: String?, prompt: String, dueDate: Date) async throws {
        let checkInId = UUID().uuidString
        let checkIn = MentorshipCheckIn(
            id: checkInId, relationshipId: relationshipId,
            mentorId: mentorId, menteeId: menteeId,
            mentorName: mentorName, mentorPhotoURL: mentorPhotoURL,
            prompt: prompt, dueDate: dueDate,
            completedAt: nil, response: nil, mentorReply: nil,
            status: .pending
        )
        try db.collection("mentorshipCheckIns").document(checkInId).setData(from: checkIn)
    }

    // MARK: - Notifications (via existing FCM system)
    private func sendMentorshipRequestNotification(mentorId: String, mentorName: String) async throws {
        // Uses existing notification infrastructure
        // Sends to mentor's FCM token stored in users/{mentorId}/fcmToken
        let mentorDoc = try await db.collection("users").document(mentorId).getDocument()
        guard let fcmToken = mentorDoc.data()?["fcmToken"] as? String else { return }
        dlog("📬 MentorshipService: would send FCM to \(fcmToken) for \(mentorName)")
        // Full FCM send handled by Cloud Function trigger on mentorshipRelationships creation
    }

    // MARK: - Chat ID
    func chatId(mentorId: String, menteeId: String) -> String {
        let sorted = [mentorId, menteeId].sorted()
        return "mentorship_\(sorted[0])_\(sorted[1])"
    }

    func hasRelationship(mentorId: String, relationships: [MentorshipRelationship]) -> Bool {
        relationships.contains { $0.mentorId == mentorId && $0.status == .active }
    }
}
