// ChurchInteractionService.swift
// AMENAPP
//
// Church Interaction Tracking Service — Manages the full lifecycle of a user's
// relationship with a specific church. Provides idempotent phase transitions
// and real-time Firestore sync.
//
// Firestore path: users/{uid}/churchInteractions/{churchId}

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
final class ChurchInteractionService: ObservableObject {

    static let shared = ChurchInteractionService()

    // MARK: - Published State

    /// All interactions for the current user, keyed by churchId for O(1) lookup
    @Published private(set) var interactions: [String: ChurchInteraction] = [:]

    /// Whether initial load is in progress
    @Published private(set) var isLoading = false

    // MARK: - Private

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentUserId: String?

    private init() {}

    // MARK: - Lifecycle

    /// Call on sign-in to start listening for the user's church interactions
    func startListening(userId: String) {
        guard userId != currentUserId else { return }
        stopListening()
        currentUserId = userId
        isLoading = true

        listener = db.collection("users")
            .document(userId)
            .collection("churchInteractions")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error {
                        dlog("[ChurchInteraction] Listener error: \(error.localizedDescription)")
                    }
                    return
                }

                var updated: [String: ChurchInteraction] = [:]
                for doc in snapshot.documents {
                    if let interaction = try? doc.data(as: ChurchInteraction.self) {
                        updated[doc.documentID] = interaction
                    }
                }
                self.interactions = updated
                self.isLoading = false
            }
    }

    /// Call on sign-out to detach the listener
    func stopListening() {
        listener?.remove()
        listener = nil
        interactions = [:]
        currentUserId = nil
    }

    // MARK: - Queries

    /// Returns the interaction for a specific church, or nil
    func interaction(for churchId: String) -> ChurchInteraction? {
        interactions[churchId]
    }

    /// Returns all interactions at or beyond a given phase
    func interactions(atOrBeyond phase: ChurchInteractionPhase) -> [ChurchInteraction] {
        interactions.values.filter { $0.phase >= phase }
    }

    // MARK: - Phase Transitions

    /// Records that a church appeared in search results / recommendations.
    /// Creates the interaction document if it doesn't exist.
    func recordDiscovered(churchId: String, churchName: String) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled else { return }
        ensureOrTransition(
            churchId: churchId,
            churchName: churchName,
            targetPhase: .discovered,
            timestampKey: "discovered_at"
        )
        AMENAnalyticsService.shared.track(.churchSearchPerformed)
    }

    /// Records that the user saved / bookmarked the church
    func recordSaved(churchId: String, churchName: String) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled else { return }
        ensureOrTransition(
            churchId: churchId,
            churchName: churchName,
            targetPhase: .saved,
            timestampKey: "saved_at"
        )
        AMENAnalyticsService.shared.track(.churchSaved)
    }

    /// Records that the user expanded a church card or viewed its profile
    func recordInterested(churchId: String, churchName: String) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled else { return }
        ensureOrTransition(
            churchId: churchId,
            churchName: churchName,
            targetPhase: .interested,
            timestampKey: "interested_at"
        )
        AMENAnalyticsService.shared.track(.churchProfileViewed)
    }

    /// Records that the user began planning a visit (opened First Visit Companion)
    func transitionToPlanning(churchId: String, visitPlanId: String? = nil) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        var updates: [String: Any] = [
            "phase": ChurchInteractionPhase.planning.rawValue,
            "planning_at": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ]
        if let visitPlanId {
            updates["visit_plan_id"] = visitPlanId
        }

        docRef(userId: uid, churchId: churchId).setData(updates, merge: true)
        AMENAnalyticsService.shared.track(.churchFirstVisitGuideOpened)
    }

    /// Records that the user is ready to visit (checklist substantially complete)
    func transitionToReady(churchId: String) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        docRef(userId: uid, churchId: churchId).setData([
            "phase": ChurchInteractionPhase.ready.rawValue,
            "ready_at": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ], merge: true)
    }

    /// Records that the user attended the church
    func transitionToAttended(churchId: String, visitSessionId: String? = nil) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        var updates: [String: Any] = [
            "phase": ChurchInteractionPhase.attended.rawValue,
            "attended_at": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ]
        if let visitSessionId {
            updates["visit_session_id"] = visitSessionId
        }

        docRef(userId: uid, churchId: churchId).setData(updates, merge: true)
    }

    /// Records that the user completed a reflection
    func transitionToReflected(churchId: String, reflectionId: String? = nil) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        var updates: [String: Any] = [
            "phase": ChurchInteractionPhase.reflected.rawValue,
            "reflected_at": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ]
        if let reflectionId {
            updates["reflection_id"] = reflectionId
        }

        docRef(userId: uid, churchId: churchId).setData(updates, merge: true)
    }

    /// Records that the user returned to the church
    func transitionToReturned(churchId: String) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        docRef(userId: uid, churchId: churchId).setData([
            "phase": ChurchInteractionPhase.returned.rawValue,
            "returned_at": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ], merge: true)
    }

    // MARK: - Checklist Updates

    /// Updates a single checklist item for a church interaction
    func updateChecklist(churchId: String, key: String, value: Bool) {
        guard AMENFeatureFlags.shared.churchInteractionTrackingEnabled,
              let uid = currentUserId else { return }

        docRef(userId: uid, churchId: churchId).setData([
            "checklist.\(key)": value,
            "updated_at": Timestamp(date: Date())
        ], merge: true)

        // Check if checklist is substantially complete → transition to ready
        if var interaction = interactions[churchId] {
            switch key {
            case "got_directions":    interaction.checklist.gotDirections = value
            case "enabled_quiet_mode": interaction.checklist.enabledQuietMode = value
            case "invited_friend":    interaction.checklist.invitedFriend = value
            case "created_note":      interaction.checklist.createdNote = value
            case "prepared_post_card": interaction.checklist.preparedPostCard = value
            default: break
            }
            if interaction.checklist.completionPercentage >= 0.6 && interaction.phase < .ready {
                transitionToReady(churchId: churchId)
            }
        }
    }

    // MARK: - Note & PostCard Linking

    /// Links a church note to the interaction
    func linkNote(churchId: String, noteId: String) {
        guard let uid = currentUserId else { return }

        docRef(userId: uid, churchId: churchId).setData([
            "note_ids": FieldValue.arrayUnion([noteId]),
            "updated_at": Timestamp(date: Date())
        ], merge: true)
    }

    /// Links a PostCard draft to the interaction
    func linkPostCardDraft(churchId: String, draftId: String) {
        guard let uid = currentUserId else { return }

        docRef(userId: uid, churchId: churchId).setData([
            "post_card_draft_ids": FieldValue.arrayUnion([draftId]),
            "updated_at": Timestamp(date: Date())
        ], merge: true)
    }

    /// Sets recommendation reasons for a church
    func setRecommendationReasons(churchId: String, reasons: [ChurchRecommendationReason]) {
        guard let uid = currentUserId else { return }

        let reasonData = reasons.compactMap { reason -> [String: Any]? in
            guard let data = try? JSONEncoder().encode(reason),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return dict
        }

        docRef(userId: uid, churchId: churchId).setData([
            "recommendation_reasons": reasonData,
            "updated_at": Timestamp(date: Date())
        ], merge: true)
    }

    // MARK: - Private Helpers

    private func docRef(userId: String, churchId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("churchInteractions")
            .document(churchId)
    }

    /// Creates or advances an interaction to a target phase.
    /// Only advances forward — never goes backward.
    private func ensureOrTransition(
        churchId: String,
        churchName: String,
        targetPhase: ChurchInteractionPhase,
        timestampKey: String
    ) {
        guard let uid = currentUserId else { return }

        // If already at or beyond this phase, skip
        if let existing = interactions[churchId], existing.phase >= targetPhase {
            return
        }

        var data: [String: Any] = [
            "user_id": uid,
            "church_id": churchId,
            "church_name": churchName,
            "phase": targetPhase.rawValue,
            timestampKey: Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date())
        ]

        // Set created_at only if document doesn't exist
        if interactions[churchId] == nil {
            data["created_at"] = Timestamp(date: Date())
            data["note_ids"] = [String]()
            data["post_card_draft_ids"] = [String]()
            data["checklist"] = [
                "got_directions": false,
                "enabled_quiet_mode": false,
                "invited_friend": false,
                "created_note": false,
                "prepared_post_card": false
            ] as [String: Any]
            data["recommendation_reasons"] = [[String: Any]]()
        }

        docRef(userId: uid, churchId: churchId).setData(data, merge: true)
    }
}
