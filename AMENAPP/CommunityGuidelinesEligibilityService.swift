//
//  CommunityGuidelinesEligibilityService.swift
//  AMENAPP
//
//  Smart trigger logic for the Community Guidelines floating welcome card.
//  Determines when to show the guidelines based on:
//    • First-ever post (totalPostCount == 0)
//    • New sign-in session (not yet acknowledged this session)
//    • 30+ days since last post
//
//  Persistence: local (UserDefaults) + server-side (Firestore) for cross-device sync.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Posting Session State

/// Tracks the user's posting activity state for guidelines eligibility.
struct PostingSessionState {
    var totalPostCount: Int
    var lastPostAt: Date?
    var lastGuidelinesAcknowledgedAt: Date?
    var guidelinesAcknowledgedForCurrentSession: Bool
    var guidelinesVersion: Int

    static let currentGuidelinesVersion = 1
}

// MARK: - Eligibility Service

@MainActor
final class CommunityGuidelinesEligibilityService: ObservableObject {

    static let shared = CommunityGuidelinesEligibilityService()

    // MARK: - Published State

    @Published private(set) var sessionState = PostingSessionState(
        totalPostCount: 0,
        lastPostAt: nil,
        lastGuidelinesAcknowledgedAt: nil,
        guidelinesAcknowledgedForCurrentSession: false,
        guidelinesVersion: PostingSessionState.currentGuidelinesVersion
    )

    @Published private(set) var isLoaded = false

    // MARK: - Keys

    private enum Keys {
        static let totalPostCount = "cg_totalPostCount"
        static let lastPostAt = "cg_lastPostAt"
        static let lastAcknowledgedAt = "cg_lastGuidelinesAcknowledgedAt"
        static let acknowledgedSessionId = "cg_acknowledgedSessionId"
        static let guidelinesVersion = "cg_guidelinesVersion"
    }

    /// Unique per app launch — resets on cold start or sign-in.
    private var currentSessionId: String

    // MARK: - Init

    private init() {
        currentSessionId = UUID().uuidString
        loadFromLocal()
    }

    // MARK: - Core Decision

    /// Returns `true` when the guidelines floating card should be presented
    /// before the user's post is published.
    var shouldShowGuidelines: Bool {
        // Already acknowledged this session — skip
        if sessionState.guidelinesAcknowledgedForCurrentSession {
            return false
        }

        // First-ever post
        if sessionState.totalPostCount == 0 {
            return true
        }

        // 30+ days since last post
        if let lastPost = sessionState.lastPostAt {
            let daysSince = Calendar.current.dateComponents([.day], from: lastPost, to: Date()).day ?? 0
            if daysSince >= 30 {
                return true
            }
        }

        // Guidelines version changed since last ack
        if let lastAck = sessionState.lastGuidelinesAcknowledgedAt {
            let savedVersion = UserDefaults.standard.integer(forKey: Keys.guidelinesVersion)
            if savedVersion < PostingSessionState.currentGuidelinesVersion {
                return true
            }
            // Never acknowledged at all
            _ = lastAck // suppress unused warning
        } else {
            // Never acknowledged at all
            return true
        }

        // New session (cold start / fresh sign-in) and NOT yet acknowledged this session
        let savedSessionId = UserDefaults.standard.string(forKey: Keys.acknowledgedSessionId) ?? ""
        if savedSessionId != currentSessionId {
            return true
        }

        return false
    }

    // MARK: - Actions

    /// Call when the user taps "I Understand" on the guidelines card.
    func acknowledgeGuidelines() {
        let now = Date()
        sessionState.guidelinesAcknowledgedForCurrentSession = true
        sessionState.lastGuidelinesAcknowledgedAt = now

        // Persist locally
        UserDefaults.standard.set(now, forKey: Keys.lastAcknowledgedAt)
        UserDefaults.standard.set(currentSessionId, forKey: Keys.acknowledgedSessionId)
        UserDefaults.standard.set(PostingSessionState.currentGuidelinesVersion, forKey: Keys.guidelinesVersion)

        // Persist to Firestore for cross-device
        persistToFirestore(acknowledgedAt: now)
    }

    /// Call after a post is successfully published to update counts.
    func recordPostPublished() {
        sessionState.totalPostCount += 1
        sessionState.lastPostAt = Date()

        UserDefaults.standard.set(sessionState.totalPostCount, forKey: Keys.totalPostCount)
        UserDefaults.standard.set(Date(), forKey: Keys.lastPostAt)
    }

    /// Call on sign-in or app start to reset session tracking.
    func resetSession() {
        currentSessionId = UUID().uuidString
        sessionState.guidelinesAcknowledgedForCurrentSession = false
    }

    /// Loads state from Firestore (for cross-device consistency).
    func loadFromServer() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        lazy var db = Firestore.firestore()
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return }

            let serverPostCount = data["totalPostCount"] as? Int
            let serverLastPost = (data["lastPostAt"] as? Timestamp)?.dateValue()
            let serverLastAck = (data["lastGuidelinesAcknowledgedAt"] as? Timestamp)?.dateValue()

            // Merge: prefer server values if they're more recent / higher
            if let count = serverPostCount, count > sessionState.totalPostCount {
                sessionState.totalPostCount = count
                UserDefaults.standard.set(count, forKey: Keys.totalPostCount)
            }

            if let lastPost = serverLastPost {
                if sessionState.lastPostAt == nil || lastPost > sessionState.lastPostAt! {
                    sessionState.lastPostAt = lastPost
                    UserDefaults.standard.set(lastPost, forKey: Keys.lastPostAt)
                }
            }

            if let lastAck = serverLastAck {
                if sessionState.lastGuidelinesAcknowledgedAt == nil || lastAck > sessionState.lastGuidelinesAcknowledgedAt! {
                    sessionState.lastGuidelinesAcknowledgedAt = lastAck
                    UserDefaults.standard.set(lastAck, forKey: Keys.lastAcknowledgedAt)
                }
            }

            isLoaded = true
        } catch {
            dlog("CommunityGuidelinesEligibilityService: Failed to load from server: \(error)")
            isLoaded = true // Still mark loaded so we don't block
        }
    }

    // MARK: - Private

    private func loadFromLocal() {
        sessionState.totalPostCount = UserDefaults.standard.integer(forKey: Keys.totalPostCount)
        sessionState.lastPostAt = UserDefaults.standard.object(forKey: Keys.lastPostAt) as? Date
        sessionState.lastGuidelinesAcknowledgedAt = UserDefaults.standard.object(forKey: Keys.lastAcknowledgedAt) as? Date

        // Check if this session was already acknowledged
        let savedSessionId = UserDefaults.standard.string(forKey: Keys.acknowledgedSessionId) ?? ""
        sessionState.guidelinesAcknowledgedForCurrentSession = (savedSessionId == currentSessionId)

        isLoaded = true
    }

    private func persistToFirestore(acknowledgedAt: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        lazy var db = Firestore.firestore()
        db.collection("users").document(uid).setData([
            "lastGuidelinesAcknowledgedAt": Timestamp(date: acknowledgedAt),
            "guidelinesVersion": PostingSessionState.currentGuidelinesVersion
        ], merge: true)
    }
}
