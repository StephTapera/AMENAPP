// BereanMentorshipService.swift
// AMENAPP — Berean Mentorship OS — Service layer
// Swift 6, iOS 18+ — async/await only, no Combine, no force unwraps.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class BereanMentorshipService: ObservableObject {
    static let shared = BereanMentorshipService()
    private init() {}

    // MARK: - Published state

    @Published var mentorPulse: BereanMentorPulse?
    @Published var menteeGrowthPlan: BereanMenteeGrowthPlan?
    @Published var myMentorships: [BereanMentorship] = []
    @Published var isMentor: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    // MARK: - Private

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()
    private var mentorshipsListener: ListenerRegistration?
    private var menteeListener: ListenerRegistration?

    // MARK: - deinit

    deinit {
        mentorshipsListener?.remove()
        menteeListener?.remove()
    }

    // MARK: - Load mentorships + set up live listeners

    /// Checks whether the current user has the "mentor" role, then attaches
    /// two Firestore listeners (one for mentor side, one for mentee side) and
    /// merges results client-side.
    func loadMentorships() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        defer { isLoading = false }

        // Check roles array on users/{uid}
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            if let roles = userDoc.data()?["roles"] as? [String] {
                isMentor = roles.contains("mentor")
            }
        } catch {
            lastError = error.localizedDescription
        }

        // Tear down old listeners before attaching new ones
        mentorshipsListener?.remove()
        menteeListener?.remove()

        var mentorSide: [BereanMentorship] = []
        var menteeSide: [BereanMentorship] = []

        // Listener 1: mentorships where I am the mentor
        mentorshipsListener = db.collection("mentorships")
            .whereField("mentorId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                mentorSide = docs.compactMap { BereanMentorship(documentID: $0.documentID, data: $0.data()) }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.myMentorships = (mentorSide + menteeSide)
                        .sorted { $0.startedAt > $1.startedAt }
                }
            }

        // Listener 2: mentorships where I am the mentee
        menteeListener = db.collection("mentorships")
            .whereField("menteeId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                menteeSide = docs.compactMap { BereanMentorship(documentID: $0.documentID, data: $0.data()) }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.myMentorships = (mentorSide + menteeSide)
                        .sorted { $0.startedAt > $1.startedAt }
                }
            }
    }

    // MARK: - Fetch mentor pulse (mentor-only)

    /// Calls the "getBereanMentorPulse" Cloud Function.
    /// No-ops silently if the current user is not a mentor.
    func fetchMentorPulse() async throws {
        guard isMentor else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let callable = functions.httpsCallable("getBereanMentorPulse")

        do {
            let result = try await callable.call(["uid": uid])
            guard let data = result.data as? [String: Any] else { return }

            let rawItems = data["items"] as? [[String: Any]] ?? []
            let items: [BereanMentorPulseItem] = rawItems.compactMap { d in
                guard
                    let id         = d["id"]         as? String,
                    let menteeId   = d["menteeId"]   as? String,
                    let menteeName = d["menteeName"] as? String,
                    let signalRaw  = d["signal"]     as? String,
                    let signal     = BereanMentorSignal(rawValue: signalRaw),
                    let detail     = d["detail"]     as? String
                else { return nil }
                let date = (d["date"] as? Timestamp)?.dateValue() ?? Date()
                return BereanMentorPulseItem(
                    id: id, menteeId: menteeId, menteeName: menteeName,
                    signal: signal, detail: detail, date: date
                )
            }

            let rawMentorships = data["mentorships"] as? [[String: Any]] ?? []
            let pulseMentorships: [BereanMentorship] = rawMentorships.compactMap {
                guard let id = $0["id"] as? String else { return nil }
                return BereanMentorship(documentID: id, data: $0)
            }

            let generatedAt = (data["generatedAt"] as? Timestamp)?.dateValue() ?? Date()
            mentorPulse = BereanMentorPulse(
                mentorships: pulseMentorships.isEmpty ? myMentorships : pulseMentorships,
                items: items.sorted { $0.signal.priority < $1.signal.priority },
                generatedAt: generatedAt
            )
        } catch {
            // CF not yet deployed — fall back to mock in DEBUG, silent fail in release
#if DEBUG
            mentorPulse = BereanMentorPulse(
                mentorships: BereanMentorshipMockData.mentorships,
                items: BereanMentorshipMockData.pulseItems.sorted { $0.signal.priority < $1.signal.priority },
                generatedAt: Date()
            )
#else
            lastError = error.localizedDescription
#endif
        }
    }

    // MARK: - Fetch growth plan (mentee)

    /// Calls the "getBereanMenteeGrowthPlan" Cloud Function.
    func fetchGrowthPlan(mentorshipId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let callable = functions.httpsCallable("getBereanMenteeGrowthPlan")

        do {
            let result = try await callable.call(["uid": uid, "mentorshipId": mentorshipId])
            guard let data = result.data as? [String: Any] else { return }

            let goals              = data["goals"]              as? [String] ?? []
            let currentStudy       = data["currentStudy"]       as? String
            let suggestedResources = data["suggestedResources"] as? [String] ?? []
            let nextSessionDate: Date? = (data["nextSessionDate"] as? Timestamp).map { $0.dateValue() }
            let rawMilestones      = data["milestones"]          as? [[String: Any]] ?? []
            let milestones: [BereanMilestoneBadge] = rawMilestones.compactMap { BereanMilestoneBadge(data: $0) }

            menteeGrowthPlan = BereanMenteeGrowthPlan(
                goals: goals,
                currentStudy: currentStudy,
                nextSessionDate: nextSessionDate,
                suggestedResources: suggestedResources,
                milestones: milestones
            )
        } catch {
#if DEBUG
            menteeGrowthPlan = BereanMentorshipMockData.growthPlan
#else
            lastError = error.localizedDescription
#endif
        }
    }

    // MARK: - Log session

    /// Writes a session document to Firestore and calls the AI processing CF.
    func logSession(mentorshipId: String, notes: String, durationMinutes: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let sessionId  = UUID().uuidString
        let sessionRef = db.collection("mentorships").document(mentorshipId)
                          .collection("sessions").document(sessionId)
        let mentorshipRef = db.collection("mentorships").document(mentorshipId)

        let batch = db.batch()
        batch.setData([
            "id": sessionId, "mentorId": uid, "notes": notes,
            "durationMinutes": durationMinutes, "date": Timestamp(date: Date())
        ], forDocument: sessionRef)
        batch.updateData(["sessionCount": FieldValue.increment(Int64(1))], forDocument: mentorshipRef)
        try await batch.commit()

        // Fire-and-forget CF call for AI processing
        let callable = functions.httpsCallable("logBereanMentorSession")
        _ = try? await callable.call([
            "uid": uid, "mentorshipId": mentorshipId,
            "sessionId": sessionId, "durationMinutes": durationMinutes
        ])

        // Reflect increment locally
        if let idx = myMentorships.firstIndex(where: { $0.id == mentorshipId }) {
            myMentorships[idx].sessionCount += 1
        }
    }

    // MARK: - Dismiss pulse item

    /// Persists the dismissal to Firestore and removes the item from local pulse immediately.
    func dismissPulseItem(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Optimistic update
        mentorPulse?.items.removeAll { $0.id == id }

        let ref = db.collection("users").document(uid)
                    .collection("dismissedMentorPulseItems").document(id)
        do {
            try await ref.setData(["dismissedAt": Timestamp(date: Date())])
        } catch {
            lastError = error.localizedDescription
        }
    }
}
