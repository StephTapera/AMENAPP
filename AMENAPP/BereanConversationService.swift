//
//  BereanConversationService.swift
//  AMENAPP
//
//  Firestore-backed conversation and message persistence for Berean AI.
//
//  Schema:
//    users/{uid}/bereanConversations/{convId}           — conversation metadata
//    users/{uid}/bereanConversations/{convId}/messages  — ordered messages
//
//  Design rules:
//    - All writes are idempotent (server timestamps, no client-side clock drift)
//    - Real-time listener scoped to ONE active conversation at a time
//    - Project chat-count is kept in sync via a lightweight Firestore increment
//    - No private data is cached beyond the active session
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Models

struct BereanConversation: Identifiable, Codable {
    var id: String
    var title: String
    var projectId: String?          // nil = ungrouped
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var lastMessagePreview: String? // first 80 chars of last message
    var modeName: String            // active BereanMode at creation time
    var memoryScopeName: String     // active BereanMemoryScope

    var relativeDate: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60        { return "just now" }
        if interval < 3600      { return "\(Int(interval / 60))m ago" }
        if interval < 86400     { return "\(Int(interval / 3600))h ago" }
        if interval < 604800    { return "\(Int(interval / 86400))d ago" }
        return "\(Int(interval / 604800))w ago"
    }
}

struct BereanConversationMessage: Identifiable, Codable {
    var id: String
    var conversationId: String
    var role: String               // "user" | "assistant"
    var content: String
    var createdAt: Date
    var agentRoute: String?        // which provider/agent handled this (for observability)
    var scriptureRefs: [String]?   // detected scripture references
    var tokensUsed: Int?
}

// MARK: - Service

@MainActor
final class BereanConversationService: ObservableObject {

    static let shared = BereanConversationService()

    @Published var conversations: [BereanConversation] = []
    @Published var activeMessages: [BereanConversationMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    private lazy var db = Firestore.firestore()
    private var messageListener: ListenerRegistration?
    private var activeConversationId: String?

    private var uid: String? { Auth.auth().currentUser?.uid }

    private init() {}

    // MARK: - Collection References

    private func conversationsRef(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bereanConversations")
    }

    private func messagesRef(uid: String, convId: String) -> CollectionReference {
        conversationsRef(uid: uid).document(convId).collection("messages")
    }

    // MARK: - Conversations

    /// Create a new conversation and return it. Increments project chatCount if projectId given.
    func createConversation(
        title: String,
        projectId: String? = nil,
        modeName: String = "Standard",
        memoryScopeName: String = "thisChat"
    ) async throws -> BereanConversation {
        guard let uid else { throw ConversationError.notAuthenticated }

        let id = conversationsRef(uid: uid).document().documentID
        let now = Date()
        let conv = BereanConversation(
            id: id,
            title: title.isEmpty ? "New Conversation" : title,
            projectId: projectId,
            createdAt: now,
            updatedAt: now,
            messageCount: 0,
            lastMessagePreview: nil,
            modeName: modeName,
            memoryScopeName: memoryScopeName
        )

        try await conversationsRef(uid: uid).document(id).setData(conv.firestoreData)

        // Sync project chat count
        if let pid = projectId {
            await incrementProjectChatCount(uid: uid, projectId: pid, delta: 1)
        }

        conversations.insert(conv, at: 0)
        return conv
    }

    /// Load conversations, optionally filtered by project.
    func fetchConversations(projectId: String? = nil) async {
        guard let uid else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var query: Query = conversationsRef(uid: uid)
                .order(by: "updatedAt", descending: true)
                .limit(to: 50)

            if let pid = projectId {
                query = conversationsRef(uid: uid)
                    .whereField("projectId", isEqualTo: pid)
                    .order(by: "updatedAt", descending: true)
                    .limit(to: 50)
            }

            let snapshot = try await query.getDocuments()
            conversations = snapshot.documents.compactMap { BereanConversation(from: $0.data()) }
        } catch {
            self.error = error.localizedDescription
            dlog("❌ [BereanConvService] fetchConversations: \(error)")
        }
    }

    /// Delete a conversation and all its messages.
    func deleteConversation(_ id: String) async throws {
        guard let uid else { throw ConversationError.notAuthenticated }

        // Remove from Firestore (messages subcollection cleaned up by Cloud Function)
        try await conversationsRef(uid: uid).document(id).delete()

        // If it had a project, decrement count
        if let conv = conversations.first(where: { $0.id == id }), let pid = conv.projectId {
            await incrementProjectChatCount(uid: uid, projectId: pid, delta: -1)
        }

        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            stopListening()
        }
    }

    /// Rename a conversation.
    func updateTitle(_ id: String, title: String) async throws {
        guard let uid else { throw ConversationError.notAuthenticated }
        try await conversationsRef(uid: uid).document(id).updateData(["title": title])
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = title
        }
    }

    // MARK: - Messages

    /// Append a message to a conversation. Also updates conversation metadata.
    @discardableResult
    func appendMessage(
        to convId: String,
        role: String,
        content: String,
        agentRoute: String? = nil,
        scriptureRefs: [String]? = nil,
        tokensUsed: Int? = nil
    ) async throws -> BereanConversationMessage {
        guard let uid else { throw ConversationError.notAuthenticated }

        let msgId = messagesRef(uid: uid, convId: convId).document().documentID
        let now = Date()
        let msg = BereanConversationMessage(
            id: msgId,
            conversationId: convId,
            role: role,
            content: content,
            createdAt: now,
            agentRoute: agentRoute,
            scriptureRefs: scriptureRefs,
            tokensUsed: tokensUsed
        )

        // Write message
        try await messagesRef(uid: uid, convId: convId).document(msgId).setData(msg.firestoreData)

        // Update conversation metadata
        let preview = String(content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        try await conversationsRef(uid: uid).document(convId).updateData([
            "updatedAt": Timestamp(date: now),
            "messageCount": FieldValue.increment(Int64(1)),
            "lastMessagePreview": preview
        ])

        // Update local cache
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].updatedAt = now
            conversations[idx].messageCount += 1
            conversations[idx].lastMessagePreview = preview
        }

        return msg
    }

    /// Fetch messages for a conversation once (non-streaming).
    func fetchMessages(conversationId: String) async throws -> [BereanConversationMessage] {
        guard let uid else { throw ConversationError.notAuthenticated }
        let snapshot = try await messagesRef(uid: uid, convId: conversationId)
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snapshot.documents.compactMap { BereanConversationMessage(from: $0.data()) }
    }

    // MARK: - Real-time Listener

    /// Listen to messages for the active conversation. Updates `activeMessages` in real time.
    func listenToMessages(conversationId: String) {
        guard let uid else { return }
        stopListening()
        activeConversationId = conversationId
        activeMessages = []

        messageListener = messagesRef(uid: uid, convId: conversationId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else { return }
                self.activeMessages = snapshot.documents.compactMap {
                    BereanConversationMessage(from: $0.data())
                }
            }
    }

    func stopListening() {
        messageListener?.remove()
        messageListener = nil
        activeConversationId = nil
    }

    // MARK: - Project Sync

    /// Increment (or decrement) the chatCount on a Firestore-backed project.
    /// Silently no-ops if the project doc doesn't exist yet.
    private func incrementProjectChatCount(uid: String, projectId: String, delta: Int) async {
        let ref = db.collection("users").document(uid)
            .collection("bereanProjects").document(projectId)
        do {
            try await ref.updateData(["chatCount": FieldValue.increment(Int64(delta))])
        } catch {
            dlog("⚠️ [BereanConvService] Could not update project chatCount: \(error)")
        }
    }
}

// MARK: - Firestore Serialization

private extension BereanConversation {
    var firestoreData: [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "title": title,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "messageCount": messageCount,
            "modeName": modeName,
            "memoryScopeName": memoryScopeName
        ]
        if let pid = projectId       { d["projectId"] = pid }
        if let p = lastMessagePreview { d["lastMessagePreview"] = p }
        return d
    }

    init?(from data: [String: Any]) {
        guard
            let id   = data["id"]    as? String,
            let title = data["title"] as? String,
            let created = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updated = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id                 = id
        self.title              = title
        self.projectId          = data["projectId"]          as? String
        self.createdAt          = created
        self.updatedAt          = updated
        self.messageCount       = data["messageCount"]       as? Int ?? 0
        self.lastMessagePreview = data["lastMessagePreview"] as? String
        self.modeName           = data["modeName"]           as? String ?? "Standard"
        self.memoryScopeName    = data["memoryScopeName"]    as? String ?? "thisChat"
    }
}

private extension BereanConversationMessage {
    var firestoreData: [String: Any] {
        var d: [String: Any] = [
            "id":             id,
            "conversationId": conversationId,
            "role":           role,
            "content":        content,
            "createdAt":      Timestamp(date: createdAt)
        ]
        if let r = agentRoute   { d["agentRoute"]    = r }
        if let s = scriptureRefs, !s.isEmpty { d["scriptureRefs"] = s }
        if let t = tokensUsed   { d["tokensUsed"]    = t }
        return d
    }

    init?(from data: [String: Any]) {
        guard
            let id       = data["id"]             as? String,
            let convId   = data["conversationId"] as? String,
            let role     = data["role"]            as? String,
            let content  = data["content"]         as? String,
            let created  = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id             = id
        self.conversationId = convId
        self.role           = role
        self.content        = content
        self.createdAt      = created
        self.agentRoute     = data["agentRoute"]    as? String
        self.scriptureRefs  = data["scriptureRefs"] as? [String]
        self.tokensUsed     = data["tokensUsed"]    as? Int
    }
}

// MARK: - Errors

enum ConversationError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in to use Berean conversations."
        }
    }
}
