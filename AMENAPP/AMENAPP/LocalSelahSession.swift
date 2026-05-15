// LocalSelahSession.swift
// AMENAPP
//
// SwiftData models for locally-persisted Selah session state.
// Sessions survive app termination and are scoped to userId for sign-out isolation.
//
// Container: SelahLocalStore.shared (accessible from both views and AppLifecycleManager)
// Firestore sync is intentionally NOT done here — local drafts only.

import SwiftData
import Foundation

// MARK: - LocalSelahSessionPhase

enum LocalSelahSessionPhase: String, Codable {
    case idle        = "idle"
    case preparing   = "preparing"
    case active      = "active"
    case paused      = "paused"
    case completed   = "completed"
    case failed      = "failed"

    var isContinuable: Bool { self == .active || self == .paused }
}

// MARK: - LocalSelahSession

@Model
final class LocalSelahSession {
    var id: UUID
    var userId: String
    var title: String
    var reflectionText: String
    var promptText: String
    var mediaItemId: String?
    var scriptureRef: String?
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var pausedAt: Date?
    var completedAt: Date?
    var phaseRawValue: String
    var syncState: String
    var continuationEligibility: Bool

    @Relationship(deleteRule: .cascade)
    var sections: [LocalSelahSection] = []

    init(userId: String,
         promptText: String = "",
         mediaItemId: String? = nil,
         scriptureRef: String? = nil) {
        self.id = UUID()
        self.userId = userId
        self.title = ""
        self.reflectionText = ""
        self.promptText = promptText
        self.mediaItemId = mediaItemId
        self.scriptureRef = scriptureRef
        self.createdAt = Date()
        self.updatedAt = Date()
        self.phaseRawValue = LocalSelahSessionPhase.idle.rawValue
        self.syncState = "local"
        self.continuationEligibility = false
    }

    var phase: LocalSelahSessionPhase {
        get { LocalSelahSessionPhase(rawValue: phaseRawValue) ?? .idle }
        set { phaseRawValue = newValue.rawValue; updatedAt = Date() }
    }

    func start() {
        phase = .active
        if startedAt == nil { startedAt = Date() }
        continuationEligibility = true
    }

    func pause() {
        guard phase == .active else { return }
        phase = .paused
        pausedAt = Date()
    }

    func resume() {
        guard phase.isContinuable else { return }
        phase = .active
        pausedAt = nil
    }

    func complete() {
        phase = .completed
        completedAt = Date()
        continuationEligibility = false
    }

    func updateReflection(_ text: String) {
        reflectionText = text
        if !text.isEmpty { title = String(text.prefix(60)) }
        updatedAt = Date()
    }
}

// MARK: - LocalSelahSection

@Model
final class LocalSelahSection {
    var id: UUID
    var sessionId: UUID
    var kind: String      // "prompt" | "reflection" | "scripture" | "prayer"
    var text: String
    var sortOrder: Int
    var createdAt: Date

    init(sessionId: UUID, kind: String, text: String, sortOrder: Int) {
        self.id = UUID()
        self.sessionId = sessionId
        self.kind = kind
        self.text = text
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

// MARK: - SelahLocalStore

/// Shared ModelContainer for LocalSelahSession + LocalSelahSection.
/// Accessible from both the SwiftUI view hierarchy and AppLifecycleManager
/// so sign-out cleanup can delete user-scoped sessions without needing a view context.
@MainActor
final class SelahLocalStore {
    static let shared = SelahLocalStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([LocalSelahSession.self, LocalSelahSection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("SelahLocalStore: failed to initialize ModelContainer: \(error)")
        }
    }

    /// Deletes all sessions owned by userId. Called from performFullSignOutCleanup().
    func cleanupSessions(forUserId userId: String) {
        let context = ModelContext(container)
        let uid = userId
        let descriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate { $0.userId == uid }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        sessions.forEach { context.delete($0) }
        try? context.save()
    }
}
