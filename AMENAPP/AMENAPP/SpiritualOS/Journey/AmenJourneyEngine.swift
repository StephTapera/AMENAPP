// AmenJourneyEngine.swift
// AMEN Spiritual Journey Engine — Observable Singleton
//
// Manages the user's personalized spiritual journey profile, growth snapshot,
// and in-progress resource tracking. All data is private; none is shared.
//
// Feature flag: amen_journey_engine_enabled (AppStorage / Remote Config)
//   false → initialize() returns immediately; all state remains nil/empty.
//
// Firestore paths:
//   Journey profile : users/{userId}/journeyProfile           (document)
//   Progress items  : users/{userId}/journeyProgress          (collection, limit 20)
//   Growth snapshot : users/{userId}/growthSnapshot           (document)
//
// Staleness threshold for growthSnapshot: 24 hours.

import Foundation
import Observation
import FirebaseFirestore

// MARK: - AmenJourneyEngine

@Observable
@MainActor
final class AmenJourneyEngine {

    // MARK: - Singleton

    static let shared = AmenJourneyEngine()
    private init() {}

    // MARK: - Public state

    private(set) var currentJourney: UserJourneyProfile?
    private(set) var growthSnapshot: PersonalGrowthSnapshot?
    private(set) var progressItems: [JourneyProgressItem] = []

    /// True while any async operation is running.
    private(set) var isLoading: Bool = false

    // MARK: - Private state

    private var userId: String?
    private let db = Firestore.firestore()

    // Feature flag — mirrors Remote Config value via AppStorage.
    // Defaults to true when the key has never been written (nil object = first install).
    @MainActor
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "amen_journey_engine_enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "amen_journey_engine_enabled")
    }

    // MARK: - Initialize

    /// Loads journey profile, growth snapshot (if fresh), and recent progress items.
    /// Safe to call multiple times — no-ops if the same userId is already loaded.
    func initialize(userId: String) async {
        guard isEnabled else { return }
        guard self.userId != userId else { return }

        self.userId = userId
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadJourneyProfile(userId: userId) }
            group.addTask { await self.loadProgressItems(userId: userId) }
            group.addTask { await self.loadOrRefreshGrowthSnapshot(userId: userId) }
        }
    }

    // MARK: - Save journey

    /// Persists the user's journey profile to Firestore and updates local state.
    func saveJourney(_ profile: UserJourneyProfile) async throws {
        guard let userId else { return }

        let ref = db.collection("users").document(userId).collection("journeyProfile").document("current")

        let data: [String: Any] = [
            "primaryStage":      profile.primaryStage.rawValue,
            "secondaryStages":   profile.secondaryStages.map { $0.rawValue },
            "customDescription": profile.customDescription as Any,
            "setAt":             Timestamp(date: profile.setAt),
            "updatedAt":         Timestamp(date: Date())
        ]

        try await ref.setData(data, merge: true)
        currentJourney = profile
    }

    // MARK: - Update growth snapshot

    /// Recomputes the growth snapshot from Firestore counters and persists it.
    /// Called internally; also callable from the UI's "Update Your Journey" flow.
    func updateGrowthSnapshot() async {
        guard let userId else { return }
        await computeAndSaveGrowthSnapshot(userId: userId)
    }

    // MARK: - Mark progress

    /// Records or updates progress for a resource. Upserts into journeyProgress collection.
    func markProgress(resourceId: String, type: String, fraction: Double) async {
        guard let userId else { return }
        guard fraction >= 0, fraction <= 1 else { return }

        let ref = db
            .collection("users")
            .document(userId)
            .collection("journeyProgress")
            .document(resourceId)

        let data: [String: Any] = [
            "resourceId":      resourceId,
            "type":            type,
            "progressFraction": fraction,
            "lastAccessedAt":  Timestamp(date: Date()),
            "completed":       false
        ]

        // Optimistic local update
        if let idx = progressItems.firstIndex(where: { $0.resourceId == resourceId }) {
            progressItems[idx].progressFraction = fraction
            progressItems[idx].lastAccessedAt = Date()
        }

        do {
            try await ref.setData(data, merge: true)
        } catch {
            // Non-fatal — progress tracking is best-effort.
        }
    }

    // MARK: - Complete item

    /// Marks a progress item as completed. Updates Firestore and local state.
    func completeItem(resourceId: String) async {
        guard let userId else { return }

        let ref = db
            .collection("users")
            .document(userId)
            .collection("journeyProgress")
            .document(resourceId)

        let update: [String: Any] = [
            "completed":       true,
            "progressFraction": 1.0,
            "lastAccessedAt":  Timestamp(date: Date())
        ]

        // Optimistic local update
        if let idx = progressItems.firstIndex(where: { $0.resourceId == resourceId }) {
            progressItems[idx].completed = true
            progressItems[idx].progressFraction = 1.0
            progressItems[idx].lastAccessedAt = Date()
        }

        do {
            try await ref.updateData(update)
        } catch {
            // Non-fatal.
        }
    }

    // MARK: - Private: load journey profile

    private func loadJourneyProfile(userId: String) async {
        let ref = db
            .collection("users")
            .document(userId)
            .collection("journeyProfile")
            .document("current")

        guard let snap = try? await ref.getDocument(),
              snap.exists,
              let data = snap.data() else { return }

        guard
            let primaryRaw = data["primaryStage"] as? String,
            let primary    = SpiritualJourneyStage(rawValue: primaryRaw)
        else { return }

        let secondaryRaws = data["secondaryStages"] as? [String] ?? []
        let secondary     = secondaryRaws.compactMap { SpiritualJourneyStage(rawValue: $0) }

        let setAt    = (data["setAt"]     as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        currentJourney = UserJourneyProfile(
            primaryStage:      primary,
            secondaryStages:   secondary,
            customDescription: data["customDescription"] as? String,
            setAt:             setAt,
            updatedAt:         updatedAt
        )
    }

    // MARK: - Private: load progress items

    private func loadProgressItems(userId: String) async {
        let ref = db
            .collection("users")
            .document(userId)
            .collection("journeyProgress")
            .order(by: "lastAccessedAt", descending: true)
            .limit(to: 20)

        guard let snap = try? await ref.getDocuments() else { return }

        progressItems = snap.documents.compactMap { doc -> JourneyProgressItem? in
            let d = doc.data()
            guard
                let type            = d["type"]     as? String,
                let title           = d["title"]    as? String,
                let resourceId      = d["resourceId"] as? String
            else { return nil }

            let fraction       = d["progressFraction"] as? Double ?? 0.0
            let lastAccessedAt = (d["lastAccessedAt"] as? Timestamp)?.dateValue() ?? Date()
            let completed      = d["completed"] as? Bool ?? false

            return JourneyProgressItem(
                id:               doc.documentID,
                type:             type,
                title:            title,
                resourceId:       resourceId,
                progressFraction: fraction,
                lastAccessedAt:   lastAccessedAt,
                completed:        completed
            )
        }
    }

    // MARK: - Private: load or refresh growth snapshot

    private func loadOrRefreshGrowthSnapshot(userId: String) async {
        let ref = db.collection("users").document(userId).collection("growthSnapshot").document("current")

        if let snap = try? await ref.getDocument(),
           snap.exists,
           let data = snap.data(),
           let computedAt = (data["computedAt"] as? Timestamp)?.dateValue(),
           Date().timeIntervalSince(computedAt) < 86_400 {
            // Snapshot is fresh — decode and use it.
            growthSnapshot = decodeSnapshot(data)
            return
        }

        // Snapshot is missing or stale — recompute.
        await computeAndSaveGrowthSnapshot(userId: userId)
    }

    // MARK: - Private: compute and save growth snapshot

    private func computeAndSaveGrowthSnapshot(userId: String) async {
        async let studiesCompleted   = countDocuments("users/\(userId)/studyProgress",   field: "completed", equals: true)
        async let studiesInProgress  = countDocuments("users/\(userId)/studyProgress",   field: "completed", equals: false)
        async let prayerSessions     = countDocuments("prayerSessions/\(userId)/sessions", field: nil, sinceStartOfMonth: true)
        async let mentorshipSessions = countMentorshipSessions(userId: userId)
        async let communities        = countDocuments("spaceMemberships/\(userId)/spaces",    field: nil, equals: nil)
        async let events             = countDocuments("eventAttendees/\(userId)/attended",    field: nil, equals: nil)
        async let notes              = countDocuments("churchNotes", field: "authorId", equalsString: userId)
        async let discussions        = countDocuments("discussionParticipants/\(userId)/threads", field: nil, equals: nil)

        let (sc, si, ps, ms, com, ev, no, di) = await (
            studiesCompleted,
            studiesInProgress,
            prayerSessions,
            mentorshipSessions,
            communities,
            events,
            notes,
            discussions
        )

        // Build named metric map for strong-area / opportunity derivation
        let metrics: [(label: String, count: Int)] = [
            ("Bible Study",  sc + si),
            ("Prayer",       ps),
            ("Mentorship",   ms),
            ("Community",    com),
            ("Events",       ev),
            ("Notes",        no),
            ("Discussions",  di)
        ]

        let sorted        = metrics.sorted { $0.count > $1.count }
        let strongAreas   = sorted.prefix(2).map { $0.label }
        let opportunities = sorted.suffix(2).map { $0.label }

        let snapshot = PersonalGrowthSnapshot(
            studiesCompleted:        sc,
            studiesInProgress:       si,
            prayerSessionsThisMonth: ps,
            mentorshipSessionsTotal: ms,
            communitiesJoined:       com,
            eventsAttended:          ev,
            notesWritten:            no,
            discussionsParticipated: di,
            computedAt:              Date(),
            strongAreas:             strongAreas,
            growthOpportunities:     opportunities
        )

        growthSnapshot = snapshot

        let ref = db
            .collection("users")
            .document(userId)
            .collection("growthSnapshot")
            .document("current")

        let data: [String: Any] = [
            "studiesCompleted":        sc,
            "studiesInProgress":       si,
            "prayerSessionsThisMonth": ps,
            "mentorshipSessionsTotal": ms,
            "communitiesJoined":       com,
            "eventsAttended":          ev,
            "notesWritten":            no,
            "discussionsParticipated": di,
            "computedAt":              Timestamp(date: Date()),
            "strongAreas":             Array(strongAreas),
            "growthOpportunities":     Array(opportunities)
        ]

        try? await ref.setData(data)
    }

    // MARK: - Private: count helpers

    /// Counts documents in a Firestore collection path.
    /// When field/equals are nil, counts all documents.
    private func countDocuments(
        _ path: String,
        field: String?,
        equals: Bool? = nil,
        equalsString: String? = nil,
        sinceStartOfMonth: Bool = false
    ) async -> Int {
        var query: Query = db.collection(path)

        if let field, let equals {
            query = query.whereField(field, isEqualTo: equals)
        } else if let field, let equalsString {
            query = query.whereField(field, isEqualTo: equalsString)
        }

        if sinceStartOfMonth {
            let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
            query = query.whereField("date", isGreaterThanOrEqualTo: Timestamp(date: start))
        }

        guard let count = try? await query.count.getAggregation(source: .server) else { return 0 }
        return count.count.intValue
    }

    /// Counts mentorship sessions where menteeId == userId.
    private func countMentorshipSessions(userId: String) async -> Int {
        let query = db.collection("mentorshipSessions").whereField("menteeId", isEqualTo: userId)
        guard let count = try? await query.count.getAggregation(source: .server) else { return 0 }
        return count.count.intValue
    }

    // MARK: - Private: decode snapshot

    private func decodeSnapshot(_ data: [String: Any]) -> PersonalGrowthSnapshot {
        PersonalGrowthSnapshot(
            studiesCompleted:        data["studiesCompleted"]        as? Int ?? 0,
            studiesInProgress:       data["studiesInProgress"]       as? Int ?? 0,
            prayerSessionsThisMonth: data["prayerSessionsThisMonth"] as? Int ?? 0,
            mentorshipSessionsTotal: data["mentorshipSessionsTotal"] as? Int ?? 0,
            communitiesJoined:       data["communitiesJoined"]       as? Int ?? 0,
            eventsAttended:          data["eventsAttended"]          as? Int ?? 0,
            notesWritten:            data["notesWritten"]            as? Int ?? 0,
            discussionsParticipated: data["discussionsParticipated"] as? Int ?? 0,
            computedAt:              (data["computedAt"] as? Timestamp)?.dateValue() ?? Date(),
            strongAreas:             data["strongAreas"]         as? [String] ?? [],
            growthOpportunities:     data["growthOpportunities"] as? [String] ?? []
        )
    }
}
