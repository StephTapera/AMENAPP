import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Covenant Service

@MainActor
final class CovenantService: ObservableObject {
    static let shared = CovenantService()

    @Published var covenants: [Covenant] = []
    @Published var pinnedCovenants: [Covenant] = []
    @Published var currentCovenant: Covenant?
    @Published var rooms: [CovenantRoom] = []
    @Published var activities: [CovenantActivity] = []
    @Published var prayerRequests: [CovenantPrayerRequest] = []
    @Published var isLoading = false
    @Published var error: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    func stopAll() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Load User's Covenants

    func loadMyCovenants() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("covenantMemberships")
                .whereField("userId", isEqualTo: uid)
                .whereField("status", in: ["active", "trialing"])
                .getDocuments()
            let membershipCovenantIds = snap.documents.compactMap { $0.data()["covenantId"] as? String }
            guard !membershipCovenantIds.isEmpty else {
                covenants = []
                return
            }
            let chunks = stride(from: 0, to: membershipCovenantIds.count, by: 10).map {
                Array(membershipCovenantIds[$0..<min($0 + 10, membershipCovenantIds.count)])
            }
            var all: [Covenant] = []
            for chunk in chunks {
                let cSnap = try await db.collection("covenants")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                let decoded = cSnap.documents.compactMap { try? $0.data(as: Covenant.self) }
                all.append(contentsOf: decoded)
            }
            covenants = all
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Load Rooms for Covenant

    func loadRooms(covenantId: String) {
        let listener = db.collection("covenants").document(covenantId)
            .collection("rooms")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snap, error in
                guard let snap else { return }
                self?.rooms = snap.documents.compactMap { try? $0.data(as: CovenantRoom.self) }
            }
        listeners.append(listener)
    }

    // MARK: - Load Activity for User

    func loadActivity() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let listener = db.collection("users").document(uid)
            .collection("covenantActivity")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, error in
                guard let snap else { return }
                self?.activities = snap.documents.compactMap { try? $0.data(as: CovenantActivity.self) }
            }
        listeners.append(listener)
    }

    // MARK: - Load Prayer Requests

    func loadPrayerRequests(covenantId: String) {
        let listener = db.collection("covenants").document(covenantId)
            .collection("prayerRequests")
            .whereField("status", in: ["open", "updated"])
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                self?.prayerRequests = snap.documents.compactMap { try? $0.data(as: CovenantPrayerRequest.self) }
            }
        listeners.append(listener)
    }

    // MARK: - Mark Activity Read

    func markActivityRead(_ activityId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid)
            .collection("covenantActivity").document(activityId)
            .updateData(["isRead": true])
    }

    func markAllActivityRead() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let unread = activities.filter { !$0.isRead }
        let batch = db.batch()
        for activity in unread {
            guard let aid = activity.id else { continue }
            let ref = db.collection("users").document(uid)
                .collection("covenantActivity").document(aid)
            batch.updateData(["isRead": true], forDocument: ref)
        }
        try? await batch.commit()
    }

    // MARK: - Prayer Actions

    func markIPrayed(prayerRequestId: String, covenantId: String) async {
        let ref = db.collection("covenants").document(covenantId)
            .collection("prayerRequests").document(prayerRequestId)
        try? await ref.updateData(["prayedCount": FieldValue.increment(Int64(1))])
    }

    func updatePrayerStatus(prayerRequestId: String, covenantId: String, status: CovenantPrayerRequest.PrayerStatus) async throws {
        let data: [String: Any] = ["status": status.rawValue, "lastUpdateAt": Timestamp(date: Date())]
        try await db.collection("covenants").document(covenantId)
            .collection("prayerRequests").document(prayerRequestId)
            .updateData(data)
    }

    // MARK: - Onboarding

    func loadOnboarding(covenantId: String) async throws -> CovenantOnboarding? {
        let doc = try await db.collection("covenants").document(covenantId)
            .collection("onboarding").document("startHere")
            .getDocument()
        return try? doc.data(as: CovenantOnboarding.self)
    }

    // MARK: - Analytics (Creator only)

    func loadAnalytics(covenantId: String, dateKey: String) async throws -> CovenantAnalytics? {
        let doc = try await db.collection("covenants").document(covenantId)
            .collection("analytics").document(dateKey)
            .getDocument()
        return try? doc.data(as: CovenantAnalytics.self)
    }

    // MARK: - Scheduled Content

    func loadScheduledContent(covenantId: String) async throws -> [CovenantScheduledContent] {
        let snap = try await db.collection("covenants").document(covenantId)
            .collection("scheduledContent")
            .whereField("status", isEqualTo: "scheduled")
            .order(by: "scheduledAt")
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CovenantScheduledContent.self) }
    }

    // MARK: - Member Directory

    func loadMembers(covenantId: String) async throws -> [CovenantMembership] {
        let snap = try await db.collection("covenantMemberships")
            .whereField("covenantId", isEqualTo: covenantId)
            .whereField("status", in: ["active", "trialing"])
            .limit(to: 100)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CovenantMembership.self) }
    }

    // MARK: - Moderation Queue

    func loadModerationQueue(covenantId: String) async throws -> [CovenantModerationItem] {
        let snap = try await db.collection("covenants").document(covenantId)
            .collection("moderationQueue")
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CovenantModerationItem.self) }
    }

    func performModerationAction(
        covenantId: String,
        itemId: String,
        action: String,
        note: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let entry = CovenantAuditEntry(
            action: action,
            performedBy: uid,
            note: note,
            timestamp: Timestamp(date: Date())
        )
        let entryData: [String: Any] = [
            "action": entry.action,
            "performedBy": entry.performedBy,
            "note": entry.note as Any,
            "timestamp": entry.timestamp
        ]
        try await db.collection("covenants").document(covenantId)
            .collection("moderationQueue").document(itemId)
            .updateData([
                "status": action,
                "resolvedBy": uid,
                "resolvedAt": Timestamp(date: Date()),
                "auditLog": FieldValue.arrayUnion([entryData])
            ])
    }

    // MARK: - Catch-Up Summary

    func generateCatchUp(covenantId: String, roomId: String? = nil, since: Date) async throws -> CovenantCatchUpSummary {
        var params: [String: Any] = ["covenantId": covenantId, "since": since.timeIntervalSince1970 * 1000]
        if let roomId { params["roomId"] = roomId }
        let result = try await functions.httpsCallable("generateCatchUpSummary").call(params)
        guard let data = result.data as? [String: Any] else {
            throw CovenantError.invalidResponse
        }
        return CovenantCatchUpSummary(
            covenantId: covenantId,
            roomId: roomId,
            threadId: nil,
            since: since,
            summary: data["summary"] as? String ?? "",
            decisions: data["decisions"] as? [String] ?? [],
            prayerUpdates: data["prayerUpdates"] as? [String] ?? [],
            unansweredQuestions: data["unansweredQuestions"] as? [String] ?? [],
            upcomingEvents: data["upcomingEvents"] as? [String] ?? [],
            suggestedActions: data["suggestedActions"] as? [String] ?? []
        )
    }

    // MARK: - Verification Request

    func submitVerificationRequest(type: CreatorVerificationRequest.VerificationType) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "creatorId": uid,
            "userId": uid,
            "type": type.rawValue,
            "status": "pending",
            "submittedAt": Timestamp(date: Date())
        ]
        try await db.collection("creatorVerificationRequests").addDocument(data: data)
    }

    // MARK: - Churn Signals

    func loadChurnSignals(covenantId: String) async throws -> [CovenantMemberSignal] {
        let snap = try await db.collection("covenants").document(covenantId)
            .collection("memberSignals")
            .whereField("churnRisk", in: ["medium", "high"])
            .order(by: "computedAt", descending: true)
            .limit(to: 30)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CovenantMemberSignal.self) }
    }
}

// MARK: - Covenant Error

enum CovenantError: LocalizedError {
    case invalidResponse
    case unauthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected response from server."
        case .unauthorized:    return "You don't have permission to do that."
        case .notFound:        return "This content could not be found."
        }
    }
}
