// CaughtUpService.swift
// AMENAPP
//
// Tracks which posts the user has seen and determines whether all content
// from the last 72 hours has been consumed — triggering the "You're All
// Caught Up" experience.
//
// Architecture:
//   • In-memory seen set (fast, zero-latency per card)
//   • Debounced async background writes to Firestore (non-blocking)
//   • 72-hour completeness check run once per feed load (not per card)
//   • Rapid-refresh detection (5 refreshes < 60s)
//   • Deep-scroll guardrail (120 cards in one session)

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - CaughtUpService

@MainActor
final class CaughtUpService: ObservableObject {
    static let shared = CaughtUpService()

    // MARK: Published

    /// Feed is caught up: user has seen all posts from the past 72 hours.
    @Published var isCaughtUp: Bool = false

    /// Triggers the rapid-refresh nudge ("Nothing new right now").
    @Published var showRapidRefreshNudge: Bool = false

    /// Triggers the deep-scroll pause reminder (120+ cards).
    @Published var showDeepScrollNudge: Bool = false

    // MARK: Private state

    /// In-memory set of seen post IDs this session (fast lookup, no Firestore read).
    private var seenIdsInMemory: Set<String> = []

    /// Posts visible to the user in the current 72-hour window (set by OpenTableView).
    private var currentWindowPostIds: Set<String> = []

    // Debounce: batch Firestore writes every 3 seconds.
    private var pendingWrites: [String: Date] = [:]
    private var writeTask: Task<Void, Never>?

    // Rapid-refresh detection
    private var refreshTimestamps: [Date] = []
    private let rapidRefreshWindow: TimeInterval = 60
    private let rapidRefreshThreshold: Int = 5

    // Deep-scroll detection
    private var cardsSeenThisSession: Int = 0
    private let deepScrollThreshold: Int = 120

    private let db = Firestore.firestore()

    // MARK: Init

    private init() {}

    // MARK: - Public API

    /// Called by OpenTableView when the post list updates.
    /// Provides the full set of 72-hour post IDs so completeness can be checked.
    func setCurrentWindow(postIds: Set<String>) {
        currentWindowPostIds = postIds
        checkIfCaughtUp()
    }

    /// Called when a post becomes visible for ≥1.5 seconds.
    /// Non-blocking — writes to memory immediately, Firestore asynchronously.
    func markSeen(postId: String) {
        guard !seenIdsInMemory.contains(postId) else { return }
        seenIdsInMemory.insert(postId)

        // Deep-scroll counter
        cardsSeenThisSession += 1
        if cardsSeenThisSession == deepScrollThreshold {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDeepScrollNudge = true
            }
        }

        // Queue Firestore write (debounced)
        pendingWrites[postId] = Date()
        scheduleBatchWrite()

        // Check completeness
        checkIfCaughtUp()
    }

    /// Call on every pull-to-refresh. Returns true if the nudge was triggered.
    @discardableResult
    func recordRefresh() -> Bool {
        let now = Date()
        refreshTimestamps.append(now)
        // Prune timestamps outside the window
        refreshTimestamps = refreshTimestamps.filter {
            now.timeIntervalSince($0) < rapidRefreshWindow
        }
        if refreshTimestamps.count >= rapidRefreshThreshold {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showRapidRefreshNudge = true
            }
            // Auto-dismiss after 4s
            Task {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    withAnimation { showRapidRefreshNudge = false }
                }
            }
            return true
        }
        return false
    }

    /// Dismiss the deep-scroll nudge.
    func dismissDeepScrollNudge() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showDeepScrollNudge = false
        }
    }

    /// Called when the user taps "View older posts" — clears the caught-up state.
    func dismissCaughtUp() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isCaughtUp = false
        }
    }

    /// Reset session counters on each new feed appearance.
    func resetSession() {
        cardsSeenThisSession = 0
        showDeepScrollNudge = false
        isCaughtUp = false
        // Reload seen IDs from Firestore to seed the in-memory set
        Task { await loadSeenIdsFromFirestore() }
    }

    // MARK: - Completeness check

    private func checkIfCaughtUp() {
        guard !currentWindowPostIds.isEmpty else { return }
        let unseen = currentWindowPostIds.subtracting(seenIdsInMemory)
        let caught = unseen.isEmpty
        guard caught != isCaughtUp else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isCaughtUp = caught
        }
    }

    // MARK: - Firestore: seed seen IDs

    private func loadSeenIdsFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cutoff = Date().addingTimeInterval(-72 * 3600)
        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("seenPosts")
                .whereField("seenAt", isGreaterThan: Timestamp(date: cutoff))
                .getDocuments()
            let ids = Set(snapshot.documents.map { $0.documentID })
            await MainActor.run {
                seenIdsInMemory.formUnion(ids)
                checkIfCaughtUp()
            }
        } catch {
            // Non-critical: in-memory set still works without Firestore data
        }
    }

    // MARK: - Firestore: batch write seen posts

    private func scheduleBatchWrite() {
        writeTask?.cancel()
        writeTask = Task {
            // Debounce: wait 3 seconds before flushing
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await flushPendingWrites()
        }
    }

    private func flushPendingWrites() async {
        guard let uid = Auth.auth().currentUser?.uid,
              !pendingWrites.isEmpty else { return }

        let toWrite = pendingWrites
        pendingWrites = [:]

        // Use a Firestore batch for efficiency
        let batch = db.batch()
        let seenRef = db.collection("users").document(uid).collection("seenPosts")

        for (postId, seenAt) in toWrite {
            let docRef = seenRef.document(postId)
            batch.setData(["postId": postId, "seenAt": Timestamp(date: seenAt)], forDocument: docRef)
        }

        do {
            try await batch.commit()
        } catch {
            // Re-queue failed writes silently — non-critical
            for (id, date) in toWrite where pendingWrites[id] == nil {
                pendingWrites[id] = date
            }
        }
    }
}
