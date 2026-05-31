// BereanVoiceStudySessionStore.swift
// AMEN App — Context-Aware Voice Bible Companion (Agent 5)
//
// Persists spiritual context across voice companion sessions.
// Schema: turns (user + Berean), scripture refs, reflection notes.
// User must consent before anything is saved to journal or Church Notes.
// Context lives in Firestore under users/{uid}/bereanVoiceSessions/{sessionId}.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Session Turn

struct BereanVoiceTurn: Codable, Identifiable {
    var id: String = UUID().uuidString
    let role: TurnRole
    let text: String
    let timestamp: Date
    let scriptureRefs: [String]     // cited references in this turn
    let label: String               // "scripture" | "interpretation" | "encouragement"

    enum TurnRole: String, Codable {
        case user   = "user"
        case berean = "berean"
    }
}

// MARK: - Session

struct BereanVoiceStudySession: Codable, Identifiable {
    var id: String
    let uid: String
    var title: String               // e.g. "Studying Proverbs 9:10" — auto-set
    var turns: [BereanVoiceTurn]
    var spiritualContext: String    // brief summary of what was discussed
    var lastScriptureRef: String?   // for "continue studying" re-entry
    var isSaved: Bool               // user explicitly saved this session
    var createdAt: Date
    var updatedAt: Date

    init(uid: String) {
        id = UUID().uuidString
        self.uid = uid
        title = "Voice Study"
        turns = []
        spiritualContext = ""
        lastScriptureRef = nil
        isSaved = false
        createdAt = Date()
        updatedAt = Date()
    }
}

// MARK: - Store

@MainActor
final class BereanVoiceStudySessionStore: ObservableObject {

    static let shared = BereanVoiceStudySessionStore()

    @Published private(set) var currentSession: BereanVoiceStudySession?
    @Published private(set) var recentSessions: [BereanVoiceStudySession] = []
    @Published private(set) var isSaving = false

    private let db = Firestore.firestore()

    // MARK: - Session Lifecycle

    func startOrResumeSession() async {
        guard AMENFeatureFlags.shared.bereanVoiceCompanionEnabled,
              let uid = Auth.auth().currentUser?.uid else { return }

        // Resume the most recent unsaved session from the last 24 hours if available
        if let recent = recentSessions.first(where: {
            !$0.isSaved && $0.updatedAt > Date().addingTimeInterval(-86400)
        }) {
            currentSession = recent
            return
        }

        // Otherwise start fresh
        currentSession = BereanVoiceStudySession(uid: uid)
    }

    func addTurn(_ turn: BereanVoiceTurn) {
        guard currentSession != nil else { return }
        currentSession?.turns.append(turn)
        currentSession?.updatedAt = Date()
        if turn.role == .berean, let ref = turn.scriptureRefs.last {
            currentSession?.lastScriptureRef = ref
        }
    }

    // MARK: - Explicit Save (user must confirm)

    func saveSession(title: String? = nil) async {
        guard var session = currentSession,
              let uid = Auth.auth().currentUser?.uid else { return }

        isSaving = true
        defer { isSaving = false }

        if let title { session.title = title }
        session.isSaved = true
        session.updatedAt = Date()
        currentSession = session

        do {
            let data = try Firestore.Encoder().encode(session)
            try await db
                .collection("users").document(uid)
                .collection("bereanVoiceSessions").document(session.id)
                .setData(data, merge: true)

            // Refresh recent sessions
            await loadRecentSessions()
        } catch {
            dlog("[BereanVoiceStore] saveSession failed (non-fatal, session stays in memory): \(error.localizedDescription)")
        }
    }

    // MARK: - Load Recent

    func loadRecentSessions() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("bereanVoiceSessions")
                .order(by: "updatedAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            recentSessions = snapshot.documents.compactMap {
                try? Firestore.Decoder().decode(BereanVoiceStudySession.self, from: $0.data())
            }
        } catch {
            dlog("[BereanVoiceStore] loadRecentSessions failed (non-fatal): \(error.localizedDescription)")
        }
    }

    // MARK: - Delete (hard delete per privacy contract)

    func deleteSession(_ session: BereanVoiceStudySession) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try? await db
            .collection("users").document(uid)
            .collection("bereanVoiceSessions").document(session.id)
            .delete()

        recentSessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
    }

    // MARK: - Context Summary for Prompt

    var contextSummary: String {
        guard let session = currentSession else { return "" }
        let refs = session.turns
            .flatMap(\.scriptureRefs)
            .prefix(5)
            .joined(separator: ", ")
        return refs.isEmpty
            ? session.spiritualContext
            : "We've been studying: \(refs). \(session.spiritualContext)"
    }
}
