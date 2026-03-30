
//  BereanChatSessionManager.swift
//  AMENAPP
//
//  Manages multiple simultaneous Berean AI chat sessions (Safari-style tabs).
//  Session data is stored in UserDefaults under the current user's scope.
//  This layer sits entirely on top of BereanViewModel — it never touches
//  BereanInteractiveUI, BereanOrchestrator, or BereanRAGService.

import SwiftUI
import Combine
import Foundation
import FirebaseAuth

// MARK: - BereanChatSession

struct BereanChatSession: Identifiable, Codable {
    let id: UUID
    var title: String          // auto-generated from first user message
    var messages: [BereanMessage]
    let createdAt: Date
    var lastUpdatedAt: Date

    // Default title shown before the user sends any message
    static func defaultTitle(for date: Date) -> String {
        "Chat — \(BereanSessionDateFormatter.short.string(from: date))"
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        messages: [BereanMessage] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title.isEmpty ? BereanChatSession.defaultTitle(for: createdAt) : title
        self.messages = messages
        self.createdAt = createdAt
        self.lastUpdatedAt = createdAt
    }

    /// The title shown in the tab card header.
    var displayTitle: String { title }

    /// The last message sent by the user in this session, used for card preview.
    var lastUserMessage: BereanMessage? {
        messages.last(where: { $0.role == .user })
    }

    /// The last response from Berean, used for card preview.
    var lastAssistantMessage: BereanMessage? {
        messages.last(where: { $0.role == .assistant })
    }

    /// Relative timestamp string for the card footer.
    var relativeTimestamp: String {
        let diff = Date().timeIntervalSince(lastUpdatedAt)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return BereanSessionDateFormatter.short.string(from: lastUpdatedAt)
    }
}

// MARK: - BereanChatSessionManager

/// Singleton that manages up to 10 concurrent Berean chat sessions.
/// Persists to UserDefaults keyed by Firebase UID so sessions survive app restarts.
/// All mutations must happen on the @MainActor.
@MainActor
final class BereanChatSessionManager: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = BereanChatSessionManager()

    @Published var sessions: [BereanChatSession] = []
    @Published var activeSessionID: UUID

    private let maxSessions = 10

    // UserDefaults keys — suffixed with UID at first load
    private var storageKey: String { "berean_sessions_v1_\(uid)" }
    private var activeKey:  String { "berean_active_id_v1_\(uid)" }
    private var uid: String { Auth.auth().currentUser?.uid ?? "anon" }

    private init() {
        let seed = BereanChatSession()
        activeSessionID = seed.id
        sessions = [seed]
        load()
    }

    // MARK: - Accessors

    var activeSession: BereanChatSession? {
        sessions.first(where: { $0.id == activeSessionID })
    }

    private var activeIndex: Int? {
        sessions.firstIndex(where: { $0.id == activeSessionID })
    }

    // MARK: - Mutations

    /// Syncs the current viewModel.messages into the active session and saves.
    /// Called from BereanAIAssistantView's `.onChange(of: viewModel.messages)`.
    func updateActiveMessages(_ messages: [BereanMessage]) {
        guard let idx = activeIndex else { return }
        sessions[idx].messages = messages
        sessions[idx].lastUpdatedAt = Date()

        // Auto-title: first 40 chars of the first user message
        let hasCustomTitle = !sessions[idx].title.hasPrefix("Chat — ")
        if !hasCustomTitle, let first = messages.first(where: { $0.role == .user }) {
            let raw = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[idx].title = String(raw.prefix(40))
        }
        save()
    }

    /// Creates a fresh session, inserts at the front, activates it, and returns it.
    @discardableResult
    func newSession() -> BereanChatSession {
        // Archive the oldest if we're at cap
        if sessions.count >= maxSessions {
            sessions.removeLast()
        }
        let session = BereanChatSession()
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        save()
        return session
    }

    /// Activates an existing session by ID. Caller is responsible for loading
    /// that session's messages into viewModel.messages.
    func activate(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
        save()
    }

    /// Deletes a session. If it was the active one, activates the next available session.
    func delete(_ id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if activeSessionID == id {
            if let first = sessions.first {
                activeSessionID = first.id
            } else {
                let fresh = BereanChatSession()
                sessions = [fresh]
                activeSessionID = fresh.id
            }
        }
        save()
    }

    /// Duplicates an existing session (copies messages into a new session at the front).
    @discardableResult
    func duplicate(_ id: UUID) -> BereanChatSession? {
        guard let source = sessions.first(where: { $0.id == id }) else { return nil }
        if sessions.count >= maxSessions { sessions.removeLast() }
        var copy = BereanChatSession(
            messages: source.messages,
            createdAt: Date()
        )
        copy.title = "Copy of \(source.displayTitle)".prefix(40).description
        sessions.insert(copy, at: 0)
        save()
        return copy
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.set(activeSessionID.uuidString, forKey: activeKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([BereanChatSession].self, from: data),
            !saved.isEmpty
        else { return }

        sessions = saved

        if let idStr = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: idStr),
           sessions.contains(where: { $0.id == id }) {
            activeSessionID = id
        } else {
            activeSessionID = sessions[0].id
        }
    }
}

// MARK: - Private Date Formatter

private enum BereanSessionDateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
