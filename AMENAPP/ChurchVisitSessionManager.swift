// ChurchVisitSessionManager.swift
// Manages visit state machine + Firestore persistence
// AMENAPP

import Foundation
import FirebaseFirestore

// MARK: - ChurchVisitSessionManager

@MainActor
final class ChurchVisitSessionManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = ChurchVisitSessionManager()

    // MARK: - Published State
    @Published private(set) var currentSession: ChurchVisitSession?
    @Published private(set) var currentState: ChurchVisitState = .none
    @Published private(set) var assistState: ChurchAssistState = .defaultState

    // MARK: - Private
    private let db = Firestore.firestore()
    private var sessionListener: ListenerRegistration?

    private init() {}

    // MARK: - Session Lifecycle

    /// Create a new planning session and persist to Firestore.
    func startPlanning(churchId: String, userId: String) async {
        let session = ChurchVisitSession(
            churchId: churchId,
            userId: userId,
            state: .planning,
            plannedAt: Date()
        )
        do {
            let data = try encodeSession(session)
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .setData(data)
            currentSession = session
            currentState = .planning
            var updated = assistState
            updated.currentChurchId = churchId
            updated.currentVisitSessionId = session.id
            updated.currentVisitState = .planning
            assistState = updated
            dlog("[VisitSession] Started planning session \(session.id) for church \(churchId)")
        } catch {
            dlog("[VisitSession] Error starting planning session: \(error)")
        }
    }

    /// Transition to .arrived if confidence threshold met.
    func recordArrival(churchId: String, confidence: Double) async {
        guard confidence > 0.6 else {
            dlog("[VisitSession] Arrival confidence \(confidence) below threshold — skipping")
            return
        }
        guard isValidTransition(from: currentState, to: .arrived) else {
            dlog("[VisitSession] Invalid transition \(currentState) → arrived")
            return
        }
        guard let session = currentSession, let userId = session.userId as String? else { return }
        let arrivedAt = Date()
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "state": ChurchVisitState.arrived.rawValue,
                    "arrivedAt": Timestamp(date: arrivedAt),
                    "arrivalConfidence": confidence,
                    "updatedAt": Timestamp(date: Date())
                ])
            var updated = session
            updated.state = .arrived
            updated.arrivedAt = arrivedAt
            updated.arrivalConfidence = confidence
            currentSession = updated
            currentState = .arrived
            var updatedAssist = assistState
            updatedAssist.currentVisitState = .arrived
            assistState = updatedAssist
            dlog("[VisitSession] Recorded arrival for session \(session.id), confidence: \(confidence)")
        } catch {
            dlog("[VisitSession] Error recording arrival: \(error)")
        }
    }

    /// Transition from .arrived to .inService.
    func transitionToInService() async {
        guard isValidTransition(from: currentState, to: .inService) else {
            dlog("[VisitSession] Invalid transition \(currentState) → inService")
            return
        }
        guard let session = currentSession else { return }
        let userId = session.userId
        let now = Date()
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "state": ChurchVisitState.inService.rawValue,
                    "serviceStartedAt": Timestamp(date: now),
                    "updatedAt": Timestamp(date: Date())
                ])
            var updated = session
            updated.state = .inService
            updated.serviceStartedAt = now
            currentSession = updated
            currentState = .inService
            var updatedAssist = assistState
            updatedAssist.currentVisitState = .inService
            assistState = updatedAssist
            dlog("[VisitSession] Transitioned to inService for session \(session.id)")
        } catch {
            dlog("[VisitSession] Error transitioning to inService: \(error)")
        }
    }

    /// Record exit. Only transitions to postVisit if dwell > 10 minutes (600s).
    func recordExit(dwellDurationSeconds: Int) async {
        guard let session = currentSession else { return }
        guard dwellDurationSeconds > 600 else {
            dlog("[VisitSession] Dwell \(dwellDurationSeconds)s too short — not marking postVisit")
            return
        }
        guard isValidTransition(from: currentState, to: .postVisit) else {
            dlog("[VisitSession] Invalid transition \(currentState) → postVisit")
            return
        }
        let userId = session.userId
        let now = Date()
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "state": ChurchVisitState.postVisit.rawValue,
                    "exitedAt": Timestamp(date: now),
                    "dwellDurationSeconds": dwellDurationSeconds,
                    "updatedAt": Timestamp(date: Date())
                ])
            var updated = session
            updated.state = .postVisit
            updated.exitedAt = now
            updated.dwellDurationSeconds = dwellDurationSeconds
            currentSession = updated
            currentState = .postVisit
            var updatedAssist = assistState
            updatedAssist.currentVisitState = .postVisit
            assistState = updatedAssist
            dlog("[VisitSession] Recorded exit for session \(session.id), dwell: \(dwellDurationSeconds)s")
        } catch {
            dlog("[VisitSession] Error recording exit: \(error)")
        }
    }

    /// Attach a note ID to the current session.
    func attachNote(noteId: String) async {
        guard let session = currentSession else { return }
        let userId = session.userId
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "noteIds": FieldValue.arrayUnion([noteId]),
                    "updatedAt": Timestamp(date: Date())
                ])
            var updated = session
            if !updated.noteIds.contains(noteId) {
                updated.noteIds.append(noteId)
            }
            currentSession = updated
            dlog("[VisitSession] Attached note \(noteId) to session \(session.id)")
        } catch {
            dlog("[VisitSession] Error attaching note: \(error)")
        }
    }

    /// Attach a reflection ID to the current session.
    func attachReflection(reflectionId: String) async {
        guard let session = currentSession else { return }
        let userId = session.userId
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "reflectionId": reflectionId,
                    "updatedAt": Timestamp(date: Date())
                ])
            var updated = session
            updated.reflectionId = reflectionId
            currentSession = updated
            dlog("[VisitSession] Attached reflection \(reflectionId) to session \(session.id)")
        } catch {
            dlog("[VisitSession] Error attaching reflection: \(error)")
        }
    }

    /// Mark session complete and reset local state.
    func completeSession() async {
        guard let session = currentSession else { return }
        let userId = session.userId
        do {
            try await db
                .collection("users").document(userId)
                .collection("churchVisitSessions").document(session.id)
                .updateData([
                    "state": ChurchVisitState.none.rawValue,
                    "updatedAt": Timestamp(date: Date())
                ])
            currentSession = nil
            currentState = .none
            var updatedAssist = assistState
            updatedAssist.currentVisitState = nil
            updatedAssist.currentVisitSessionId = nil
            assistState = updatedAssist
            dlog("[VisitSession] Completed session \(session.id)")
        } catch {
            dlog("[VisitSession] Error completing session: \(error)")
        }
    }

    // MARK: - Assist State Persistence

    /// Load assist state from Firestore.
    func loadAssistState(userId: String) async {
        do {
            let doc = try await db
                .collection("users").document(userId)
                .collection("churchAssistState").document("current")
                .getDocument()
            if doc.exists, let data = doc.data() {
                let decoded = try Firestore.Decoder().decode(ChurchAssistState.self, from: data)
                assistState = decoded
                dlog("[VisitSession] Loaded assist state for user \(userId)")
            } else {
                dlog("[VisitSession] No assist state found, using defaults")
            }
        } catch {
            dlog("[VisitSession] Error loading assist state: \(error)")
        }
    }

    /// Persist assist state to Firestore.
    func updateAssistState(_ state: ChurchAssistState, userId: String) async {
        do {
            let data = try Firestore.Encoder().encode(state)
            try await db
                .collection("users").document(userId)
                .collection("churchAssistState").document("current")
                .setData(data, merge: true)
            assistState = state
            dlog("[VisitSession] Updated assist state for user \(userId)")
        } catch {
            dlog("[VisitSession] Error updating assist state: \(error)")
        }
    }

    /// Add a prompt type to the dismissed list.
    func dismissPrompt(_ type: ChurchAssistPromptType, userId: String) async {
        var updated = assistState
        if !updated.dismissedPromptTypes.contains(type.rawValue) {
            updated.dismissedPromptTypes.append(type.rawValue)
        }
        updated.lastPromptAt = Date()
        await updateAssistState(updated, userId: userId)
        dlog("[VisitSession] Dismissed prompt '\(type.rawValue)' for user \(userId)")
    }

    // MARK: - State Machine Validation

    /// Returns true if the requested state transition is legal.
    private func isValidTransition(from: ChurchVisitState, to: ChurchVisitState) -> Bool {
        switch (from, to) {
        case (.none, .planning):
            return true
        case (.none, .arrived):
            return true  // Direct arrival without planning
        case (.planning, .arrived):
            return true
        case (.arrived, .inService):
            return true
        case (.inService, .postVisit):
            return true
        case (.arrived, .postVisit):
            return true  // Left before service started
        case (.postVisit, .revisitSuggested):
            return true
        case (.postVisit, .none):
            return true
        case (.revisitSuggested, .none):
            return true
        case (.revisitSuggested, .planning):
            return true
        default:
            return false
        }
    }

    // MARK: - Helpers

    private func encodeSession(_ session: ChurchVisitSession) throws -> [String: Any] {
        return try Firestore.Encoder().encode(session)
    }
}
