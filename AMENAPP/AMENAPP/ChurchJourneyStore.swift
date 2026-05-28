// ChurchJourneyStore.swift
// AMENAPP
//
// Unified shared state for the Church Journey system.
// Prevents duplicated logic across tabs or views.
//
// Responsibilities:
//   - Active journey tracking
//   - Active note session tracking
//   - Active reflection state
//   - Persisting + restoring active session (survives app restart)
//   - Routing signals for contextual banners
//
// All views that need journey context observe this store via @EnvironmentObject
// or through the ChurchJourneyRouter.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChurchJourneyStore: ObservableObject {

    static let shared = ChurchJourneyStore()

    // MARK: - Published State

    @Published private(set) var activeJourney: ChurchJourney?
    @Published private(set) var activeNoteSession: ChurchNoteSession?
    @Published private(set) var activeReflection: ChurchReflection?
    @Published private(set) var todaysJourneys: [ChurchJourney] = []
    @Published private(set) var recentJourneys: [ChurchJourney] = []

    /// Transient suggestion state — routine suggestion to surface to user
    @Published var pendingRoutineSuggestion: ChurchRoutine?

    // MARK: - Loading state

    @Published private(set) var isLoadingJourney = false
    @Published private(set) var isLoadingSession = false

    // MARK: - Private

    private let db = Firestore.firestore()
    private var journeyListener: ListenerRegistration?
    private var sessionListener: ListenerRegistration?
    private var reflectionListener: ListenerRegistration?

    private let persistenceKey = "activeChurchJourneyId"
    private let sessionPersistenceKey = "activeChurchNoteSessionId"

    private init() {}

    // MARK: - Lifecycle

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listenToActiveJourneys(uid: uid)
    }

    func stopListening() {
        journeyListener?.remove()
        sessionListener?.remove()
        reflectionListener?.remove()
        journeyListener = nil
        sessionListener = nil
        reflectionListener = nil
    }

    // MARK: - Journey Listeners

    private func listenToActiveJourneys(uid: String) {
        isLoadingJourney = true

        // Today's journeys
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? Date(timeIntervalSinceNow: 86400)

        journeyListener = db
            .collection("churchJourneys")
            .whereField("userId", isEqualTo: uid)
            .whereField("serviceStartAt", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("serviceStartAt", isLessThan: Timestamp(date: endOfDay))
            .order(by: "serviceStartAt")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let journeys = snapshot?.documents.compactMap {
                    try? $0.data(as: ChurchJourney.self)
                } ?? []
                self.todaysJourneys = journeys
                self.updateActiveJourney(from: journeys)
                self.isLoadingJourney = false
            }

        // Recent journeys (last 7 days)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(timeIntervalSinceNow: -604800)
        db.collection("churchJourneys")
            .whereField("userId", isEqualTo: uid)
            .whereField("serviceStartAt", isGreaterThanOrEqualTo: Timestamp(date: weekAgo))
            .order(by: "serviceStartAt", descending: true)
            .limit(to: 10)
            .getDocuments { [weak self] snapshot, _ in
                self?.recentJourneys = snapshot?.documents.compactMap {
                    try? $0.data(as: ChurchJourney.self)
                } ?? []
            }
    }

    private func updateActiveJourney(from journeys: [ChurchJourney]) {
        // Pick the most relevant active journey for today
        let active = journeys.first(where: { $0.status.isActive })
        if let active {
            activeJourney = active
            // Restore persisted active session if needed
            if activeNoteSession == nil, let sessionId = active.noteSessionId {
                loadNoteSession(id: sessionId)
            }
            if activeReflection == nil, let reflectionId = active.reflectionId {
                loadReflection(id: reflectionId)
            }
        } else if let persisted = UserDefaults.standard.string(forKey: persistenceKey) {
            // Try restoring from UserDefaults (warm launch)
            loadJourney(id: persisted)
        }
    }

    // MARK: - Load by ID

    func loadJourney(id: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingJourney = true
        db.collection("churchJourneys").document(id).getDocument { [weak self] doc, _ in
            guard let self else { return }
            if let journey = try? doc?.data(as: ChurchJourney.self),
               journey.userId == uid,
               journey.status.isActive {
                self.activeJourney = journey
                UserDefaults.standard.set(id, forKey: self.persistenceKey)
                if let sessionId = journey.noteSessionId {
                    self.loadNoteSession(id: sessionId)
                }
            }
            self.isLoadingJourney = false
        }
    }

    func loadNoteSession(id: String) {
        isLoadingSession = true
        db.collection("churchNoteSessions").document(id).getDocument { [weak self] doc, _ in
            guard let self else { return }
            self.activeNoteSession = try? doc?.data(as: ChurchNoteSession.self)
            self.isLoadingSession = false
        }
    }

    func loadReflection(id: String) {
        db.collection("churchReflections").document(id).getDocument { [weak self] doc, _ in
            self?.activeReflection = try? doc?.data(as: ChurchReflection.self)
        }
    }

    // MARK: - Clear

    func clearActiveJourney() {
        activeJourney = nil
        activeNoteSession = nil
        activeReflection = nil
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        UserDefaults.standard.removeObject(forKey: sessionPersistenceKey)
    }

    // MARK: - Status helpers

    var shouldShowPrepBanner: Bool {
        activeJourney?.status == .prepActive
    }

    var shouldShowNotesBanner: Bool {
        guard let journey = activeJourney else { return false }
        return journey.status == .arrived || journey.status == .notesActive
    }

    var shouldShowReflectionBanner: Bool {
        activeJourney?.status == .reflectionPending
    }

    var hasActiveJourneyToday: Bool {
        todaysJourneys.contains(where: { $0.status.isActive })
    }
}
