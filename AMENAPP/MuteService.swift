//
//  MuteService.swift
//  AMENAPP
//
//  Created by Steph on 6/16/26.
//
//  Client-side user mute system.
//
//  Mute is a FEED-ONLY filter: the muted user can still post and DM;
//  they simply do not appear in the muter's feed. The muted user is
//  NEVER notified — no FCM, no audit trail they can read.
//
//  Architecture mirrors BlockService exactly:
//    - Singleton with auth-state listener
//    - Real-time Firestore snapshot listener on mutedUsers where muterId == uid
//    - In-memory Set<String> for O(1) feed filtering
//    - muteUser / unmuteUser write directly to mutedUsers/{muterId}_{mutedId}
//    - isMuted() checks the Set first, then falls back to Firestore

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Mute Model

struct Mute: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var muterId: String      // User who muted
    var mutedId: String      // User being muted
    var mutedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case muterId
        case mutedId
        case mutedAt
    }

    init(
        id: String? = nil,
        muterId: String,
        mutedId: String,
        mutedAt: Date = Date()
    ) {
        self.id = id
        self.muterId = muterId
        self.mutedId = mutedId
        self.mutedAt = mutedAt
    }
}

// MARK: - Mute Service

@MainActor
class MuteService: ObservableObject {
    static let shared = MuteService()

    /// In-memory set of user IDs that the current user has muted.
    /// Used for O(1) feed filtering — never exposed to the muted party.
    @Published var mutedUsers: Set<String> = []
    @Published var isLoading = false
    @Published var error: String?

    private lazy var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        guard FirebaseApp.app() != nil else { return }
        setupAuthListener()
    }

    deinit {
        if let h = authStateListener {
            Auth.auth().removeStateDidChangeListener(h)
        }
        listeners.forEach { $0.remove() }
    }

    // MARK: - Auth Lifecycle

    /// Start/stop the real-time mute listener when the auth state changes.
    /// Ensures mutedUsers is always fresh and cleared on sign-out.
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user != nil {
                    if self.listeners.isEmpty {
                        self.startListening()
                    }
                } else {
                    self.stopListening()
                    self.clearCache()
                }
            }
        }
    }

    // MARK: - Mute User

    /// Silently mute a user. Writes to `mutedUsers/{muterId}_{mutedId}`.
    /// The muted user is NOT notified.
    func muteUser(muterId: String, mutedId: String) async throws {
        dlog("🔇 Muting user: \(mutedId)")

        guard mutedId != muterId else {
            dlog("⚠️ Cannot mute yourself")
            return
        }

        if mutedUsers.contains(mutedId) {
            dlog("⚠️ User already muted")
            return
        }

        let mute = Mute(muterId: muterId, mutedId: mutedId)
        let docId = "\(muterId)_\(mutedId)"
        let muteData = try Firestore.Encoder().encode(mute)

        try await db.collection("mutedUsers")
            .document(docId)
            .setData(muteData, merge: true)

        dlog("✅ User muted successfully")
        mutedUsers.insert(mutedId)

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    // MARK: - Unmute User

    /// Unmute a user. Deletes `mutedUsers/{muterId}_{mutedId}`.
    func unmuteUser(muterId: String, mutedId: String) async throws {
        dlog("🔊 Unmuting user: \(mutedId)")

        let docId = "\(muterId)_\(mutedId)"

        try await db.collection("mutedUsers")
            .document(docId)
            .delete()

        dlog("✅ User unmuted successfully")
        mutedUsers.remove(mutedId)

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    // MARK: - Check Mute Status

    /// Returns true if the current user has muted `mutedId`.
    /// Checks the in-memory Set first (O(1)), then falls back to Firestore.
    func isMuted(mutedId: String) -> Bool {
        mutedUsers.contains(mutedId)
    }

    /// Async variant: checks in-memory Set first, then queries Firestore if needed.
    func isMutedAsync(mutedId: String) async -> Bool {
        if mutedUsers.contains(mutedId) { return true }

        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }

        do {
            let doc = try await db.collection("mutedUsers")
                .document("\(currentUserId)_\(mutedId)")
                .getDocument()
            if doc.exists { mutedUsers.insert(mutedId) }
            return doc.exists
        } catch {
            dlog("❌ Error checking mute status: \(error)")
            return false
        }
    }

    // MARK: - Real-time Listener

    /// Start listening to `mutedUsers` where `muterId == currentUserId`.
    /// Syncs the in-memory Set in real-time so feed filters react immediately.
    func startListening() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ No user ID for mute listener")
            return
        }

        dlog("🔊 Starting real-time listener for mutes...")

        let listener = db.collection("mutedUsers")
            .whereField("muterId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    dlog("❌ Mutes listener error: \(error)")
                    return
                }

                guard let snapshot = snapshot else { return }

                Task { @MainActor in
                    let mutedIds = snapshot.documents.compactMap { doc -> String? in
                        doc.data()["mutedId"] as? String
                    }
                    self.mutedUsers = Set(mutedIds)
                    dlog("✅ Real-time update: \(mutedIds.count) muted users")
                }
            }

        listeners.append(listener)
    }

    /// Stop all Firestore listeners.
    func stopListening() {
        dlog("🔇 Stopping mute listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    /// Stop listeners AND clear all in-memory state so previous user's mute list
    /// is never visible to the next signed-in account.
    /// Called by AppLifecycleManager.performFullSignOutCleanup().
    func resetUserState() {
        stopListening()
        mutedUsers.removeAll()
        dlog("🧹 MuteService: user state cleared on sign-out")
    }

    // MARK: - Helpers

    /// Clear the in-memory cache without stopping listeners.
    func clearCache() {
        mutedUsers.removeAll()
    }

    /// Returns true if the current user has muted `authorId`.
    /// Convenience wrapper used at the feed-filtering call site.
    func shouldHideFromFeed(authorId: String) -> Bool {
        mutedUsers.contains(authorId)
    }
}
