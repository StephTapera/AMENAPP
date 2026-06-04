// BereanPrayerService.swift
// AMENAPP — Berean Prayer Intelligence OS — Service layer
//
// Firestore path:  users/{uid}/prayerEntries/{entryId}
// Firestore path:  users/{uid}/prayerStreak (single document)
// Cloud Functions: getBereanPrayerBriefing, logBereanPrayerSession,
//                  markBereanPrayerAnswered

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class BereanPrayerService: ObservableObject {

    // MARK: - Singleton

    static let shared = BereanPrayerService()
    private init() {}

    // MARK: - Published state

    @Published var entries: [BereanPrayerEntry] = []
    @Published var todaysBriefing: BereanPrayerBriefing?
    @Published var streak: BereanPrayerStreak?
    @Published var isLoading = false

    // MARK: - Private

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    // MARK: - Load entries (real-time listener)

    /// Starts a Firestore real-time listener on users/{uid}/prayerEntries
    /// ordered by createdAt descending. Updates self.entries on each snapshot.
    func loadEntries() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener?.remove()
        isLoading = true

        listener = db
            .collection("users")
            .document(uid)
            .collection("prayerEntries")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                isLoading = false

                if let error {
                    // Non-fatal: listener will retry on reconnect
                    print("[BereanPrayerService] loadEntries error: \(error.localizedDescription)")
                    return
                }

                guard let docs = snapshot?.documents else { return }
                entries = docs.compactMap { doc in
                    BereanPrayerEntry(firestoreData: doc.data())
                }
            }
    }

    // MARK: - Add entry

    /// Validates the entry and writes it to Firestore.
    func addEntry(_ entry: BereanPrayerEntry) async throws {
        guard !entry.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanPrayerServiceError.invalidInput("Subject cannot be empty")
        }
        guard !entry.forWhom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanPrayerServiceError.invalidInput("'For whom' cannot be empty")
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanPrayerServiceError.notAuthenticated
        }

        try await db
            .collection("users")
            .document(uid)
            .collection("prayerEntries")
            .document(entry.id)
            .setData(entry.firestoreData, merge: true)
    }

    // MARK: - Mark answered

    /// Updates the entry status to .answered and sets answeredAt timestamp.
    func markAnswered(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanPrayerServiceError.notAuthenticated
        }

        let update: [String: Any] = [
            "status":     BereanPrayerEntryStatus.answered.rawValue,
            "answeredAt": Timestamp(date: Date())
        ]

        try await db
            .collection("users")
            .document(uid)
            .collection("prayerEntries")
            .document(id)
            .setData(update, merge: true)
    }

    // MARK: - Log prayer session (non-critical)

    /// Calls CF "logBereanPrayerSession". Errors are caught and ignored
    /// because session logging is non-critical telemetry.
    func logSession(durationSeconds: Int, visited: [String]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let payload: [String: Any] = [
            "uid":             uid,
            "durationSeconds": durationSeconds,
            "visitedIds":      visited
        ]

        do {
            try await functions
                .httpsCallable("logBereanPrayerSession")
                .call(payload)
        } catch {
            // Non-critical — silently ignore
            print("[BereanPrayerService] logSession (non-critical): \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch briefing

    /// Calls CF "getBereanPrayerBriefing" and decodes the response into
    /// a BereanPrayerBriefing, then sets todaysBriefing.
    func fetchBriefing() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanPrayerServiceError.notAuthenticated
        }

        let result = try await functions
            .httpsCallable("getBereanPrayerBriefing")
            .call(["uid": uid])

        guard let data = result.data as? [String: Any] else {
            throw BereanPrayerServiceError.decodingFailed
        }

        let briefingId      = data["id"]   as? String ?? UUID().uuidString
        let scripture       = data["suggestedScripture"] as? String ?? "Philippians 4:6"
        let intercedePeople = data["peopleToIntercede"] as? [String] ?? []

        let focusDocs    = data["todaysFocus"]     as? [[String: Any]] ?? []
        let answeredDocs = data["answeredThisWeek"] as? [[String: Any]] ?? []

        let focus    = focusDocs.prefix(5).compactMap { BereanPrayerEntry(firestoreData: $0) }
        let answered = answeredDocs.compactMap { BereanPrayerEntry(firestoreData: $0) }

        todaysBriefing = BereanPrayerBriefing(
            id:                 briefingId,
            date:               Date(),
            todaysFocus:        Array(focus),
            suggestedScripture: scripture,
            answeredThisWeek:   answered,
            peopleToIntercede:  intercedePeople
        )
    }

    // MARK: - Fetch streak

    /// Reads users/{uid}/prayerStreak/streak and decodes into BereanPrayerStreak.
    func fetchStreak() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanPrayerServiceError.notAuthenticated
        }

        let doc = try await db
            .collection("users")
            .document(uid)
            .collection("prayerStreak")
            .document("streak")
            .getDocument()

        guard doc.exists, let data = doc.data() else {
            // No streak document yet — use zero-state
            streak = BereanPrayerStreak()
            return
        }

        streak = BereanPrayerStreak(firestoreData: data) ?? BereanPrayerStreak()
    }

    // MARK: - Deinit

    deinit {
        listener?.remove()
    }
}

// MARK: - Service Errors

enum BereanPrayerServiceError: LocalizedError {
    case notAuthenticated
    case invalidInput(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:       return "You must be signed in to use Prayer."
        case .invalidInput(let msg):  return msg
        case .decodingFailed:         return "Could not read prayer data. Please try again."
        }
    }
}
