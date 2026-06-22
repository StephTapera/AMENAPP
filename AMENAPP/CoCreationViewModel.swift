// CoCreationViewModel.swift — AMEN App
// View model for the Real-Time Co-Creation Engine

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class CoCreationViewModel: ObservableObject {
    @Published var sessions: [CoCreationSession] = []
    @Published var activeSessions: [CoCreationSession] = []
    @Published var currentSession: CoCreationSession? = nil
    @Published var canvasText: String = ""
    @Published var aiSuggestion: String = ""
    @Published var isLoadingAI = false
    @Published var isCreatingSession = false
    @Published var elapsedSeconds: Int = 0

    private lazy var db = Firestore.firestore()
    private var sessionsListener: ListenerRegistration?
    private var canvasListener: ListenerRegistration?
    private var canvasDebounceTask: Task<Void, Never>? = nil
    private var timerTask: Task<Void, Never>? = nil

    // MARK: - Load sessions

    func loadSessions() {
        guard let uid = Auth.auth().currentUser?.uid, sessionsListener == nil else { return }
        sessionsListener = db.collection("coCreationSessions")
            .whereField("isLive", isEqualTo: true)
            .whereField("isOpenToAnyone", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    SwiftUI.withAnimation(.easeInOut(duration: 0.2)) {
                        self?.activeSessions = snap?.documents.compactMap {
                            try? $0.data(as: CoCreationSession.self)
                        } ?? []
                    }
                }
            }

        // User's own sessions
        db.collection("coCreationSessions")
            .whereField("hostId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    self?.sessions = snap?.documents.compactMap {
                        try? $0.data(as: CoCreationSession.self)
                    } ?? []
                }
            }
    }

    // MARK: - Create session

    func createSession(title: String, type: CoCreationSession.SessionType, maxCollaborators: Int, isOpen: Bool) async throws -> CoCreationSession {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }
        isCreatingSession = true
        defer { isCreatingSession = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let ref = db.collection("coCreationSessions").document()
        let data: [String: Any] = [
            "title": title,
            "type": type.rawValue,
            "hostId": uid,
            "collaboratorIds": [uid],
            "canvasState": "",
            "isLive": true,
            "isOpenToAnyone": isOpen,
            "maxCollaborators": maxCollaborators,
            "aiSuggestions": [],
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await ref.setData(data)
        let session = CoCreationSession(
            title: title, type: type, hostId: uid,
            collaboratorIds: [uid], canvasState: "",
            isLive: true, isOpenToAnyone: isOpen,
            maxCollaborators: maxCollaborators, aiSuggestions: []
        )
        currentSession = session
        return session
    }

    // MARK: - Join session

    func joinSession(_ session: CoCreationSession) async {
        guard let uid = Auth.auth().currentUser?.uid, let sid = session.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        try? await db.collection("coCreationSessions").document(sid)
            .updateData(["collaboratorIds": FieldValue.arrayUnion([uid])])
        currentSession = session
        startCanvasListener(sessionId: sid)
        startTimer()
    }

    // MARK: - Canvas real-time sync

    func startCanvasListener(sessionId: String) {
        guard canvasListener == nil else { return }
        canvasListener = db.collection("coCreationSessions").document(sessionId)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let remote = snap?.data()?["canvasState"] as? String ?? ""
                    // Only update if different (don't overwrite local in-progress edits)
                    if remote != self.canvasText && !self.canvasText.isEmpty {
                        // Merge: append remote-only additions
                        if remote.count > self.canvasText.count {
                            self.canvasText = remote
                        }
                    } else if self.canvasText.isEmpty {
                        self.canvasText = remote
                    }
                }
            }
    }

    func onCanvasChange(_ text: String) {
        canvasText = text
        canvasDebounceTask?.cancel()
        canvasDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled, let sid = currentSession?.id else { return }
            try? await db.collection("coCreationSessions").document(sid)
                .updateData(["canvasState": text])
        }
    }

    // MARK: - AI suggestion

    func getAISuggestion(prompt: String) async {
        guard let session = currentSession else { return }
        isLoadingAI = true
        defer { isLoadingAI = false }

        let system = """
        You are a creative AI collaborator in a \(session.type.label) co-creation session. \
        Given the current canvas content and a specific request, respond with a focused, \
        spiritually-grounded suggestion (2-4 sentences or lines). Be creative and specific.
        """
        let user = "Canvas so far:\n\(canvasText.prefix(500))\n\nRequest: \(prompt)"
        let payload: [String: Any] = ["systemPrompt": system, "userMessage": user, "maxTokens": 300]

        guard let result = try? await Functions.functions().httpsCallable("bereanChatProxy").call(payload),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String
        else { return }
        aiSuggestion = text
    }

    func insertAISuggestion() {
        guard !aiSuggestion.isEmpty else { return }
        let newText = canvasText.isEmpty ? aiSuggestion : "\(canvasText)\n\n\(aiSuggestion)"
        onCanvasChange(newText)
        aiSuggestion = ""
    }

    // MARK: - End session

    func endSession() async {
        guard let sid = currentSession?.id else { return }
        timerTask?.cancel()
        canvasListener?.remove()
        try? await db.collection("coCreationSessions").document(sid)
            .updateData(["isLive": false, "endedAt": FieldValue.serverTimestamp()])
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { elapsedSeconds += 1 }
            }
        }
    }

    var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    deinit {
        sessionsListener?.remove()
        canvasListener?.remove()
    }
}
