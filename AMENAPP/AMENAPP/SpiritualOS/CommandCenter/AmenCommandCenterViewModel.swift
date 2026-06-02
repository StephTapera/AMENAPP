// AmenCommandCenterViewModel.swift
// AMEN Spiritual OS — Agent F: Command Center
// Private formation overview ViewModel.
// Built 2026-06-02 — do not copy types; import SharedComponents instead.
//
// FORMATION RULES (enforced throughout):
// - Counts are private, never comparative, never guilt-inducing.
// - daysInWordCount is nil unless the user has explicitly opted in.
// - Label is "days in the Word", never "streak".

import Foundation
import FirebaseFirestore

// MARK: - AmenCommandCenterViewModel

@MainActor
final class AmenCommandCenterViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activeCommunityCount: Int = 0
    @Published var savedNotesCount: Int = 0
    @Published var bereanSessionCount: Int = 0
    @Published var upcomingEventCount: Int = 0

    @Published var readingPlanTitle: String? = nil
    @Published var readingPlanProgress: Double = 0.0   // 0.0–1.0

    /// Private opt-in only — nil when user has NOT opted in.
    /// Never surfaced unless isFormationTrackingOptedIn == true.
    @Published var daysInWordCount: Int? = nil

    @Published var isLoading: Bool = false
    @Published var isFormationTrackingOptedIn: Bool = false

    // MARK: - Private

    private let db = Firestore.firestore()

    // MARK: - Load

    /// Loads all Command Center data for the given userId.
    /// Safe to call from `.task {}` — cancellable on view disappearance.
    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCommunityCount(userId: userId) }
            group.addTask { await self.loadSavedNotesCount(userId: userId) }
            group.addTask { await self.loadBereanSessionCount(userId: userId) }
            group.addTask { await self.loadUpcomingEventCount(userId: userId) }
            group.addTask { await self.loadReadingPlan(userId: userId) }
            group.addTask { await self.loadUserPreferences(userId: userId) }
        }
    }

    // MARK: - Formation Tracking Opt-In Toggle

    /// Toggles the user's gentle formation tracking preference and persists it to Firestore.
    /// When toggled off, daysInWordCount is cleared immediately on the client.
    func toggleFormationTracking(userId: String) async {
        guard !userId.isEmpty else { return }

        let newValue = !isFormationTrackingOptedIn
        isFormationTrackingOptedIn = newValue

        if !newValue {
            // Clear private count immediately when user opts out
            daysInWordCount = nil
        }

        do {
            try await db.collection("users").document(userId).setData(
                [
                    "preferences": [
                        "isFormationTrackingOptedIn": newValue
                    ] as [String: Any]
                ],
                merge: true
            )
            // Reload to pull fresh daysInWordCount if they opted back in
            if newValue {
                await loadUserPreferences(userId: userId)
            }
        } catch {
            // Revert optimistic update on failure
            isFormationTrackingOptedIn = !newValue
            if !newValue {
                // They tried to opt out but it failed — restore privacy to the last known value
                daysInWordCount = nil
            }
        }
    }

    // MARK: - Private Loaders

    private func loadCommunityCount(userId: String) async {
        do {
            let snapshot = try await db.collection("communities")
                .whereField("memberIds", arrayContains: userId)
                .getDocuments()
            activeCommunityCount = snapshot.documents.count
        } catch {
            // Non-blocking; leaves count at 0
        }
    }

    private func loadSavedNotesCount(userId: String) async {
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("churchNotes")
                .getDocuments()
            savedNotesCount = snapshot.documents.count
        } catch {
            // Non-blocking; leaves count at 0
        }
    }

    private func loadBereanSessionCount(userId: String) async {
        do {
            let snapshot = try await db.collection("aiBibleStudyConversations")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            bereanSessionCount = snapshot.documents.count
        } catch {
            // Non-blocking; leaves count at 0
        }
    }

    private func loadUpcomingEventCount(userId: String) async {
        do {
            let now = Timestamp(date: Date())
            let snapshot = try await db.collection("spiritualOS_planner")
                .document(userId)
                .collection("events")
                .whereField("startDate", isGreaterThan: now)
                .whereField("isCompleted", isEqualTo: false)
                .getDocuments()
            upcomingEventCount = snapshot.documents.count
        } catch {
            // Non-blocking; leaves count at 0
        }
    }

    private func loadReadingPlan(userId: String) async {
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("readingPlans")
                .whereField("isActive", isEqualTo: true)
                .limit(to: 1)
                .getDocuments()

            guard let doc = snapshot.documents.first else {
                readingPlanTitle = nil
                readingPlanProgress = 0.0
                return
            }

            let data = doc.data()
            readingPlanTitle = data["title"] as? String
            let progress = data["progressFraction"] as? Double ?? 0.0
            readingPlanProgress = min(max(progress, 0.0), 1.0)
        } catch {
            readingPlanTitle = nil
            readingPlanProgress = 0.0
        }
    }

    private func loadUserPreferences(userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return }

            let prefs = data["preferences"] as? [String: Any] ?? [:]
            let optedIn = prefs["isFormationTrackingOptedIn"] as? Bool ?? false
            isFormationTrackingOptedIn = optedIn

            // Only populate daysInWordCount when the user has explicitly opted in
            if optedIn {
                let count = prefs["daysInWordCount"] as? Int
                daysInWordCount = count
            } else {
                daysInWordCount = nil
            }
        } catch {
            // Non-blocking; formation tracking stays off by default
        }
    }
}
