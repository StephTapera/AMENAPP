// ChurchRoutineMemoryService.swift
// AMENAPP
//
// Manages the user's church routine memory:
//   - Load saved routines for a user
//   - Save a new routine (manual)
//   - Activate / deactivate a routine
//   - Apply routine defaults to a journey draft
//   - Surface routine suggestions from server-learned patterns
//
// Memory behavior is transparent: suggestions are surfaced to the user
// and must be explicitly accepted, dismissed, or edited. Nothing is
// silently applied without a clear user-visible path.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChurchRoutineMemoryService: ObservableObject {

    static let shared = ChurchRoutineMemoryService()

    @Published private(set) var routines: [ChurchRoutine] = []
    @Published private(set) var pendingSuggestions: [ChurchRoutine] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Load

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        listener = db
            .collection("users").document(uid)
            .collection("churchRoutines")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else {
                    self?.isLoading = false
                    return
                }
                let all = docs.compactMap { try? $0.data(as: ChurchRoutine.self) }
                self.routines = all.filter { $0.active && $0.source == .manual }
                self.pendingSuggestions = all.filter { !$0.active && $0.source == .suggested }
                self.isLoading = false
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Lookup

    /// Returns the best active routine for a given church + optional service time.
    func routine(for churchId: String, serviceTimeId: String? = nil) -> ChurchRoutine? {
        let candidates = routines.filter { $0.churchId == churchId && $0.active }
        if let serviceTimeId {
            return candidates.first { $0.preferredServiceTimeId == serviceTimeId }
                ?? candidates.first
        }
        return candidates.first
    }

    // MARK: - Apply routine to draft

    func applyRoutine(_ routine: ChurchRoutine, to draft: inout ChurchJourneyDraft) {
        draft.useRoutineId = routine.id
        draft.options = ChurchJourneyOptions(
            coffeeEnabled: routine.coffeeEnabled,
            worshipPrepEnabled: routine.worshipPrepEnabled,
            scripturePrepEnabled: routine.scripturePrepEnabled,
            familyModeEnabled: routine.familyModeEnabled,
            noteModeEnabled: true,
            reflectionEnabled: routine.postServiceReflectionEnabled
        )
        if let serviceTimeId = routine.preferredServiceTimeId {
            // Caller is responsible for matching the service time object
            _ = serviceTimeId
        }
    }

    // MARK: - Save new routine

    func saveRoutine(
        from draft: ChurchJourneyDraft,
        label: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ChurchRoutineError.notSignedIn
        }
        guard let serviceTime = draft.selectedServiceTime else {
            throw ChurchRoutineError.noServiceTimeSelected
        }

        let routineRef = db
            .collection("users").document(uid)
            .collection("churchRoutines").document()

        let data: [String: Any] = [
            "id": routineRef.documentID,
            "userId": uid,
            "churchId": draft.church.id,
            "churchNameSnapshot": draft.church.name,
            "preferredServiceTimeId": serviceTime.id,
            "preferredServiceLabel": label ?? [serviceTime.label, serviceTime.startTime].compactMap { $0 }.joined(separator: " • "),
            "daysOfWeek": [serviceTime.dayOfWeek],
            "planningEnabled": true,
            "coffeeEnabled": draft.options.coffeeEnabled,
            "coffeeVendorType": NSNull(),
            "coffeeTemplateId": NSNull(),
            "worshipPrepEnabled": draft.options.worshipPrepEnabled,
            "scripturePrepEnabled": draft.options.scripturePrepEnabled,
            "familyModeEnabled": draft.options.familyModeEnabled,
            "preferredArrivalBufferMinutes": 10,
            "preferredPrepLeadMinutes": 30,
            "preferredReminderLeadMinutes": 60,
            "postServiceReflectionEnabled": draft.options.reflectionEnabled,
            "midweekReminderEnabled": false,
            "active": true,
            "source": "manual",
            // confidenceScore is intentionally omitted — server-managed field
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try await routineRef.setData(data)
    }

    // MARK: - Accept suggestion

    func acceptSuggestion(_ routine: ChurchRoutine) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db
            .collection("users").document(uid)
            .collection("churchRoutines").document(routine.id)
            .updateData([
                "active": true,
                "planningEnabled": true,
                "source": "manual",
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }

    // MARK: - Dismiss suggestion

    func dismissSuggestion(_ routine: ChurchRoutine) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db
            .collection("users").document(uid)
            .collection("churchRoutines").document(routine.id)
            .updateData([
                "active": false,
                "source": "manual", // demote from suggested so it won't re-appear
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }

    // MARK: - Update routine

    func updateRoutine(_ routine: ChurchRoutine) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Encode only the client-editable subset of fields
        let data: [String: Any] = [
            "coffeeEnabled": routine.coffeeEnabled,
            "worshipPrepEnabled": routine.worshipPrepEnabled,
            "scripturePrepEnabled": routine.scripturePrepEnabled,
            "familyModeEnabled": routine.familyModeEnabled,
            "planningEnabled": routine.planningEnabled,
            "postServiceReflectionEnabled": routine.postServiceReflectionEnabled,
            "midweekReminderEnabled": routine.midweekReminderEnabled,
            "preferredArrivalBufferMinutes": routine.preferredArrivalBufferMinutes,
            "preferredPrepLeadMinutes": routine.preferredPrepLeadMinutes,
            "preferredReminderLeadMinutes": routine.preferredReminderLeadMinutes,
            "active": routine.active,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try await db
            .collection("users").document(uid)
            .collection("churchRoutines").document(routine.id)
            .updateData(data)
    }

    // MARK: - Delete routine

    func deleteRoutine(_ routine: ChurchRoutine) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db
            .collection("users").document(uid)
            .collection("churchRoutines").document(routine.id)
            .delete()
    }
}

// MARK: - Errors

enum ChurchRoutineError: LocalizedError {
    case notSignedIn
    case noServiceTimeSelected

    var errorDescription: String? {
        switch self {
        case .notSignedIn:          return "You must be signed in to save a routine."
        case .noServiceTimeSelected: return "Please select a service time first."
        }
    }
}
